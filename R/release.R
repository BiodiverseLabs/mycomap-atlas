# Releases: a published, versioned snapshot of what Atlas computed.
#
# Atlas is computed remotely and read everywhere else. No machine is the
# source of truth; a store is — an S3 bucket in production, a plain folder on
# a laptop or in tests. A release is a small manifest that maps each published
# path to the SHA-256 of its content; the content lives once, under that hash:
#
#   objects/<aa>/<sha256>          every file ever published, stored once
#   releases/<grid>/<id>.json      a manifest: path -> sha256, plus provenance
#   current/<grid>.json            which release is live
#
# So a weekly release that changes 200 taxa uploads only their files, a pull
# downloads only what changed, and rolling back rewrites one small pointer.
#
# What goes in is an allowlist, not "everything under data/": models, maps,
# the per-taxon counts, the layer manifest, the newest benchmark, and where
# each taxon was collected aggregated to ATLAS_PUBLIC_DEGREES. Exact
# coordinates, raw pulls and training tables cannot be published by accident.

# ---- stores --------------------------------------------------------------

#' A store on the local file system: a laptop's stand-in for the bucket.
atlas_local_store <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  path <- function(key) file.path(root, key)
  list(
    uri = paste0("file://", root),
    put = function(key, file) {
      dir.create(dirname(path(key)), recursive = TRUE, showWarnings = FALSE)
      if (!file.copy(file, path(key), overwrite = TRUE)) {
        stop("could not write ", key, " to the store", call. = FALSE)
      }
      invisible(key)
    },
    get = function(key, dest) {
      if (!file.exists(path(key))) stop("not in the store: ", key, call. = FALSE)
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      file.copy(path(key), dest, overwrite = TRUE)
      invisible(dest)
    },
    exists = function(key) file.exists(path(key)),
    list = function(prefix) {
      base <- path(prefix)
      if (!dir.exists(base)) return(character())
      files <- list.files(base, recursive = TRUE, all.files = TRUE)
      # paste0 with no files would give the prefix itself, as if it were a key.
      if (!length(files)) return(character())
      paste0(sub("/?$", "/", prefix), files)
    }
  )
}

#' A store in S3, through paws. The client can be replaced, which is how the
#' tests exercise this without a network.
atlas_s3_store <- function(bucket, prefix = "", client = NULL) {
  if (is.null(client)) {
    if (!requireNamespace("paws.storage", quietly = TRUE)) {
      stop("paws.storage is needed for an S3 store: install.packages('paws.storage')",
           call. = FALSE)
    }
    client <- paws.storage::s3()
  }
  prefix <- sub("^/+", "", prefix)
  if (nzchar(prefix) && !grepl("/$", prefix)) prefix <- paste0(prefix, "/")
  full <- function(key) paste0(prefix, key)
  list(
    uri = paste0("s3://", bucket, "/", prefix),
    put = function(key, file) {
      client$put_object(Bucket = bucket, Key = full(key),
                        Body = readBin(file, "raw", file.info(file)$size))
      invisible(key)
    },
    get = function(key, dest) {
      body <- client$get_object(Bucket = bucket, Key = full(key))$Body
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      writeBin(body, dest)
      invisible(dest)
    },
    exists = function(key) {
      tryCatch({ client$head_object(Bucket = bucket, Key = full(key)); TRUE },
               error = function(e) FALSE)
    },
    list = function(within) {
      keys <- character()
      token <- NULL
      repeat {
        page <- if (is.null(token)) {
          client$list_objects_v2(Bucket = bucket, Prefix = full(within))
        } else {
          client$list_objects_v2(Bucket = bucket, Prefix = full(within),
                                 ContinuationToken = token)
        }
        keys <- c(keys, vapply(page$Contents, function(o) o$Key, character(1)))
        if (!isTRUE(page$IsTruncated)) break
        token <- page$NextContinuationToken
      }
      substring(keys, nchar(prefix) + 1L)
    }
  )
}

#' A store from a URI: s3://bucket/prefix, file:///path, or a plain path.
#' Defaults to ATLAS_STORE.
atlas_store <- function(uri = Sys.getenv("ATLAS_STORE", unset = "")) {
  if (!nzchar(uri)) {
    stop("no store given: pass --store=s3://bucket/prefix or set ATLAS_STORE", call. = FALSE)
  }
  if (grepl("^s3://", uri)) {
    rest <- sub("^s3://", "", uri)
    bucket <- sub("/.*$", "", rest)
    prefix <- if (grepl("/", rest)) sub("^[^/]*/", "", rest) else ""
    return(atlas_s3_store(bucket, prefix))
  }
  atlas_local_store(sub("^file://", "", uri))
}

atlas_store_text <- function(store, key) {
  file <- tempfile(fileext = ".json")
  on.exit(unlink(file), add = TRUE)
  store$get(key, file)
  jsonlite::fromJSON(file, simplifyVector = FALSE)
}

atlas_store_json <- function(store, key, x) {
  file <- tempfile(fileext = ".json")
  on.exit(unlink(file), add = TRUE)
  atlas_write_json(x, file)
  store$put(key, file)
}

# ---- what a release holds ------------------------------------------------

#' Where published objects live: objects/ab/<sha256>.
atlas_object_key <- function(sha256) {
  paste0("objects/", substr(sha256, 1, 2), "/", sha256)
}

atlas_sha256 <- function(file) digest::digest(file = file, algo = "sha256")

#' Where each taxon was collected, at the public resolution, for every taxon.
#'
#' The only form in which collection locations enter a release: cell centres
#' of ATLAS_PUBLIC_DEGREES, with a count. The same numbers the API already
#' serves one taxon at a time.
atlas_public_cells_table <- function(occurrences, degrees = ATLAS_PUBLIC_DEGREES) {
  keys <- atlas_locality_key(occurrences$latitude, occurrences$longitude, degrees = degrees)
  counts <- stats::aggregate(
    list(records = rep(1L, nrow(occurrences))),
    by = list(taxon = occurrences$scientific_name, key = keys),
    FUN = sum
  )
  parts <- do.call(rbind, strsplit(counts$key, ":", fixed = TRUE))
  data.frame(
    taxon = counts$taxon,
    lat = (as.numeric(parts[, 1]) + 0.5) * degrees,
    lng = (as.numeric(parts[, 2]) + 0.5) * degrees,
    records = as.integer(counts$records),
    stringsAsFactors = FALSE
  )
}

#' The public cells file a release carries, and the API reads when this
#' machine holds a release but not the pull behind it.
atlas_public_cells_path <- function() {
  atlas_path("public", "cells.tsv.gz")
}

#' The published summary of the pull: what the API's status reads on a machine
#' that holds a release but not the pull itself.
atlas_public_pull_path <- function() {
  atlas_path("public", "pull.json")
}

#' The pull's summary without the SQL text or the host it came from.
atlas_release_pull_summary <- function(manifest) {
  if (is.null(manifest)) return(NULL)
  manifest[intersect(names(manifest), c("stamp", "pulled_at", "records", "taxa", "fingerprint", "file"))]
}

#' The files a release publishes, relative to the data directory.
#'
#' An allowlist: model scores, rasters and maps of every algorithm, per-taxon
#' counts and fingerprints, the pull summary, public cells and regions, the layer
#' manifest, the newest benchmark, the here index and the location prior.
#' Nothing else under data/ can be published, whatever lands there.
atlas_release_files <- function(grid = "draft") {
  root <- atlas_data_dir()
  model_files <- unlist(lapply(names(ATLAS_ALGORITHMS), function(algorithm) {
    list.files(atlas_model_dir(grid, algorithm), pattern = "[.](json|tif|png)$",
               full.names = TRUE)
  }), use.names = FALSE)
  # The ensemble of each taxon's passing models, and where they disagree.
  model_files <- c(model_files, list.files(atlas_path("models", grid, "ensemble"),
                                           pattern = "[.](json|tif|png)$", full.names = TRUE))
  benchmarks <- sort(list.files(atlas_path("benchmarks", grid),
                                pattern = "^models-[0-9T]+Z[.]json$", full.names = TRUE))
  files <- c(
    model_files,
    atlas_path("occurrences", "taxa-latest.json"),
    atlas_name_merges_path(),
    atlas_renames_path(),
    atlas_public_pull_path(),
    atlas_public_cells_path(),
    atlas_public_regions_path(),
    file.path(atlas_layer_dir(grid), "manifest.json"),
    utils::tail(benchmarks, 1),
    # Ranks by 20 km cell for "what could grow here", built from the maps above,
    # and the location prior built from the same ranks (R/prior.R).
    atlas_here_index_path(grid),
    file.path(atlas_prior_dir(grid), ATLAS_PRIOR_FILES)
  )
  files <- files[file.exists(files)]
  rel <- substring(normalizePath(files, winslash = "/"),
                   nchar(normalizePath(root, winslash = "/")) + 2L)
  sort(unique(rel))
}

# ---- publishing ----------------------------------------------------------

#' A release id: sortable, and unique even for two publishes in one second.
atlas_release_id <- function(files_key, time = Sys.time()) {
  paste0(format(time, "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", substr(files_key, 1, 8))
}

#' The code this release was built from, when it is known.
atlas_code_commit <- function() {
  explicit <- Sys.getenv("ATLAS_COMMIT", unset = "")
  if (nzchar(explicit)) return(explicit)
  root <- Sys.getenv("ATLAS_ROOT", unset = ".")
  out <- tryCatch(
    suppressWarnings(system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character()
  )
  if (length(out) == 1L && grepl("^[0-9a-f]{40}$", out)) out else NA_character_
}

#' A model's published paths, relative to the data directory.
atlas_model_relpaths <- function(name, grid = "draft", algorithm = "maxnet",
                                 extensions = c(".json", ".tif", ".png")) {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  folder <- if (identical(algorithm, "maxnet")) file.path("models", grid) else file.path("models", grid, algorithm)
  file.path(folder, paste0(slug, extensions))
}

#' What a release knows about each model without opening it: enough to decide
#' whether it is still current, and to plan who fits what.
atlas_model_index_entry <- function(metrics, algorithm) {
  number <- function(x) if (is.numeric(x) && length(x) == 1L && is.finite(x)) x else NULL
  text <- function(x) if (is.character(x) && length(x) == 1L) x else NULL
  # A field that is absent is left out, not written as null: JSON would bring
  # it back as an empty list.
  entry <- list(
    taxon = as.character(metrics$taxon),
    algorithm = algorithm,
    fingerprint = text(metrics$fingerprint),
    settings_key = text(metrics$settings_key),
    presences = number(metrics$presences),
    area_km2 = number(metrics$area_km2),
    map = is.character(metrics$raster) && length(metrics$raster) == 1L,
    # Drawn only once it passes its null test (a taxon with 3 or 4 sites).
    map_withheld = if (isTRUE(metrics$map_withheld)) TRUE else NULL,
    # Whether the map beat its null models; anything reading a release to
    # use a map (mycomap.org, Vision) should take only grade "strong".
    skill = text(metrics$skill),
    grade = atlas_metrics_grade(metrics)
  )
  Filter(Negate(is.null), entry)
}

#' A refusal as an index entry: no model, but a record that this record set
#' under these settings was too sparse, so planning does not try it again
#' until either changes.
atlas_refusal_entry <- function(taxon, algorithm, fingerprint, settings_key, presences = NULL) {
  Filter(Negate(is.null), list(
    taxon = taxon, algorithm = algorithm, refused = TRUE,
    fingerprint = if (is.character(fingerprint) && length(fingerprint) == 1L) fingerprint else NULL,
    settings_key = if (is.character(settings_key) && length(settings_key) == 1L) settings_key else NULL,
    presences = if (is.numeric(presences) && length(presences) == 1L) presences else NULL
  ))
}

#' Refusals recorded by this machine's latest batch of each algorithm.
atlas_batch_refusals <- function(grid = "draft") {
  out <- list()
  for (algorithm in names(ATLAS_ALGORITHMS)) {
    name <- if (algorithm == "maxnet") "latest.json" else paste0("latest-", algorithm, ".json")
    path <- atlas_path("batches", grid, name)
    if (!file.exists(path)) next
    batch <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    for (row in batch$taxa %||% list()) {
      if (!identical(row$status, "refused")) next
      out[[length(out) + 1L]] <- atlas_refusal_entry(
        row$taxon, algorithm, row$fingerprint, batch$settings_key, row$presences
      )
    }
  }
  out
}

#' The index of every model on this machine for a grid, and of the refusals
#' its latest batches recorded.
atlas_models_index <- function(grid = "draft", taxa = NULL, refusals = TRUE) {
  out <- list()
  for (algorithm in names(ATLAS_ALGORITHMS)) {
    files <- list.files(atlas_model_dir(grid, algorithm), pattern = "[.]json$", full.names = TRUE)
    for (file in files) {
      metrics <- tryCatch(jsonlite::fromJSON(file, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.list(metrics) || is.null(metrics$taxon)) next
      if (!is.null(taxa) && !metrics$taxon %in% taxa) next
      out[[length(out) + 1L]] <- atlas_model_index_entry(metrics, algorithm)
    }
  }
  if (isTRUE(refusals)) {
    have <- vapply(out, function(e) paste(e$algorithm, e$taxon), "")
    for (entry in atlas_batch_refusals(grid)) {
      if (!is.null(taxa) && !entry$taxon %in% taxa) next
      if (!paste(entry$algorithm, entry$taxon) %in% have) out[[length(out) + 1L]] <- entry
    }
  }
  out
}

#' Hash and size a list of files under the data directory.
atlas_file_entries <- function(paths) {
  full <- file.path(atlas_data_dir(), paths)
  lapply(seq_along(paths), function(i) {
    list(path = paths[[i]], sha256 = atlas_sha256(full[[i]]), bytes = file.info(full[[i]])$size)
  })
}

#' Upload whichever of these files the store does not already hold.
atlas_upload_objects <- function(store, entries, stored = store$list("objects/")) {
  keys <- vapply(entries, function(e) atlas_object_key(e$sha256), character(1))
  missing <- which(!duplicated(keys) & !keys %in% stored)
  for (i in missing) store$put(keys[[i]], file.path(atlas_data_dir(), entries[[i]]$path))
  list(count = length(missing),
       bytes = sum(vapply(entries[missing], function(e) as.numeric(e$bytes), numeric(1))))
}

#' One string standing for a model index, whatever order it was built in.
atlas_index_key <- function(models_index) {
  keys <- vapply(models_index, function(e) {
    paste(e$algorithm, e$taxon, e$fingerprint %||% "", e$settings_key %||% "",
          isTRUE(e$refused), isTRUE(e$map), sep = "|")
  }, "")
  digest::digest(paste(sort(keys), collapse = "
"), algo = "sha256")
}

#' Write a release manifest from files already in the store, and promote it.
#'
#' Both ways of making a release end here: publishing a machine's data
#' directory, and finishing a job whose shards ran elsewhere.
atlas_write_release <- function(store, grid, files, models_index, previous = NULL,
                                note = NULL, pull = NULL, layers_key = NULL,
                                promote = TRUE, quiet = FALSE, extra = list()) {
  files <- files[order(vapply(files, function(f) f$path, character(1)))]
  files_key <- digest::digest(
    paste(vapply(files, function(f) f$path, ""), vapply(files, function(f) f$sha256, ""), collapse = "\n"),
    algo = "sha256"
  )
  counts <- lapply(stats::setNames(nm = names(ATLAS_ALGORITHMS)), function(algorithm) {
    sum(vapply(models_index, function(m) identical(m$algorithm, algorithm) && !isTRUE(m$refused), logical(1)))
  })
  id <- atlas_release_id(files_key)
  index_key <- atlas_index_key(models_index)
  release <- c(list(
    id = id,
    grid = grid,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    previous = previous,
    note = note,
    commit = atlas_code_commit(),
    versions = list(
      r = as.character(getRversion()),
      packages = lapply(stats::setNames(nm = c("terra", "maxnet", "xgboost", "ranger")), function(p) {
        tryCatch(as.character(utils::packageVersion(p)), error = function(e) NULL)
      })
    ),
    layers_key = layers_key,
    pull = pull,
    models = counts
  ), extra, list(
    files_key = files_key,
    index_key = index_key,
    index = models_index,
    files = files
  ))
  atlas_store_json(store, paste0("releases/", grid, "/", id, ".json"), release)
  atlas_write_json(release, atlas_path("releases", grid, paste0(id, ".json")))
  if (!isTRUE(quiet)) message("release ", id, ": ", length(files), " files")
  if (isTRUE(promote)) atlas_promote_release(store, id, grid, quiet = quiet)
  invisible(release)
}

#' Refresh the public files a release carries from this machine's pull: the
#' collection cells at the public resolution, each taxon's states and
#' provinces, and the cut-down pull summary.
atlas_refresh_public_files <- function() {
  manifest <- atlas_read_manifest()
  occurrences <- tryCatch(atlas_read_occurrences(), error = function(e) NULL)
  if (!is.null(occurrences)) {
    atlas_write_tsv_gz(atlas_public_cells_table(occurrences), atlas_public_cells_path())
    atlas_write_tsv_gz(atlas_region_table(occurrences), atlas_public_regions_path())
    # The pull's own manifest keeps its SQL and host; the published summary
    # is a separate, cut-down copy.
    atlas_write_json(atlas_release_pull_summary(manifest), atlas_public_pull_path())
  }
  invisible(manifest)
}

#' Publish what this machine has computed as a new release.
#'
#' Refreshes the pull summary and public cells first (from the pull, when this
#' machine has one), uploads only objects the store lacks, writes the
#' manifest, and — unless promote is FALSE — makes it the current release. A
#' publish identical to the current release is skipped.
atlas_publish_release <- function(store = atlas_store(), grid = "draft", note = NULL,
                                  promote = TRUE, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  manifest <- atlas_refresh_public_files()

  paths <- atlas_release_files(grid)
  if (!length(paths)) stop("nothing to publish for the ", grid, " grid", call. = FALSE)
  entries <- atlas_file_entries(paths)
  files_key <- digest::digest(
    paste(paths, vapply(entries, function(e) e$sha256, ""), collapse = "\n"), algo = "sha256"
  )

  index <- atlas_models_index(grid)
  current <- atlas_current_release(store, grid)
  if (!is.null(current) && identical(current$files_key, files_key) &&
      identical(current$index_key, atlas_index_key(index))) {
    say("nothing changed since release ", current$id, "; not publishing")
    return(invisible(current))
  }

  uploaded <- atlas_upload_objects(store, entries)
  say("uploaded ", uploaded$count, " of ", length(paths), " files (",
      round(uploaded$bytes / 1048576, 1), " MB); the rest were already stored")

  atlas_write_release(
    store, grid, entries, index,
    previous = current$id, note = note,
    pull = atlas_release_pull_summary(manifest),
    layers_key = atlas_layers_key(grid), promote = promote, quiet = quiet
  )
}

#' Make a release the one everyone pulls. Rolling back is promoting an older one.
atlas_promote_release <- function(store = atlas_store(), id, grid = "draft", quiet = FALSE) {
  key <- paste0("releases/", grid, "/", id, ".json")
  if (!store$exists(key)) stop("no release ", id, " for the ", grid, " grid", call. = FALSE)
  atlas_store_json(store, paste0("current/", grid, ".json"), list(
    release = id,
    promoted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ))
  if (!isTRUE(quiet)) message("current release for the ", grid, " grid is now ", id)
  invisible(id)
}

#' The current release's manifest, or NULL when nothing has been published.
atlas_current_release <- function(store = atlas_store(), grid = "draft") {
  pointer <- paste0("current/", grid, ".json")
  if (!store$exists(pointer)) return(NULL)
  id <- atlas_store_text(store, pointer)$release
  atlas_store_text(store, paste0("releases/", grid, "/", id, ".json"))
}

#' Every release published for a grid, oldest first.
atlas_list_releases <- function(store = atlas_store(), grid = "draft") {
  keys <- store$list(paste0("releases/", grid, "/"))
  sort(sub("[.]json$", "", basename(keys[grepl("[.]json$", keys)])))
}

# ---- pulling -------------------------------------------------------------

#' Bring this machine up to a release: download only files whose content
#' changed, check every one against its hash, and — unless keep_local — remove
#' model files the release does not have, so the machine shows exactly what
#' was published.
#'
#' With rasters = FALSE the model rasters stay in the store: a web server
#' answers from the maps and scores, and its disk is the limit. Any raster
#' already here is removed, so none can be older than its map.
atlas_pull_release <- function(store = atlas_store(), grid = "draft", release = NULL,
                               keep_local = FALSE, rasters = TRUE, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  manifest <- if (is.null(release)) {
    atlas_current_release(store, grid)
  } else {
    atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  }
  if (is.null(manifest)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)

  root <- atlas_data_dir()
  is_raster <- function(path) grepl("[.]tif$", path)
  wanted <- if (isTRUE(rasters)) manifest$files else Filter(function(e) !is_raster(e$path), manifest$files)
  got <- atlas_fetch_entries(store, wanted)
  fetched <- got$fetched
  bytes <- got$bytes

  removed <- 0L
  if (!isTRUE(keep_local)) {
    published <- vapply(manifest$files, function(e) e$path, character(1))
    local <- substring(
      normalizePath(unlist(lapply(names(ATLAS_ALGORITHMS), function(a) {
        list.files(atlas_model_dir(grid, a), pattern = "[.](json|tif|png)$", full.names = TRUE)
      })), winslash = "/"),
      nchar(normalizePath(root, winslash = "/")) + 2L
    )
    stale <- setdiff(local, published)
    if (!isTRUE(rasters)) stale <- union(stale, local[is_raster(local) & grepl("^models/", local)])
    unlink(file.path(root, stale))
    removed <- length(stale)
  }

  # Which releases went to Zenodo, and under which DOIs, so the API can list
  # the downloads. Small files, always fetched whole.
  for (key in store$list("archives/")) {
    if (grepl("^archives/[^/]+[.]json$", key)) store$get(key, file.path(root, key))
  }

  # What this machine now serves: enough to cite it, and the records it was
  # built from, which a later nightly pull must not be mistaken for.
  atlas_write_json(c(
    list(release = manifest$id, grid = grid,
         pulled_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
         created_at = manifest$created_at, commit = manifest$commit),
    if (!is.null(manifest$pull)) list(data = manifest$pull)
  ), atlas_path("releases", grid, "pulled.json"))
  say("release ", manifest$id, ": downloaded ", fetched, " of ", length(wanted),
      " files (", round(bytes / 1048576, 1), " MB)",
      if (removed) paste0(", removed ", removed, " local model files it does not have") else "")
  invisible(list(release = manifest$id, fetched = fetched, removed = removed))
}
