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
#' counts and fingerprints, the pull summary, public cells, the layer
#' manifest, and the newest benchmark. Nothing else under data/ can be
#' published, whatever lands there.
atlas_release_files <- function(grid = "draft") {
  root <- atlas_data_dir()
  model_files <- unlist(lapply(names(ATLAS_ALGORITHMS), function(algorithm) {
    list.files(atlas_model_dir(grid, algorithm), pattern = "[.](json|tif|png)$",
               full.names = TRUE)
  }), use.names = FALSE)
  benchmarks <- sort(list.files(atlas_path("benchmarks", grid),
                                pattern = "^models-[0-9T]+Z[.]json$", full.names = TRUE))
  files <- c(
    model_files,
    atlas_path("occurrences", "taxa-latest.json"),
    atlas_public_pull_path(),
    atlas_public_cells_path(),
    file.path(atlas_layer_dir(grid), "manifest.json"),
    utils::tail(benchmarks, 1),
    # Ranks by 20 km cell for "what could grow here", built from the maps above.
    atlas_here_index_path(grid)
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

#' Publish what this machine has computed as a new release.
#'
#' Refreshes the pull summary and public cells first (from the pull, when this
#' machine has one), uploads only objects the store lacks, writes the
#' manifest, and — unless promote is FALSE — makes it the current release. A
#' publish identical to the current release is skipped.
atlas_publish_release <- function(store = atlas_store(), grid = "draft", note = NULL,
                                  promote = TRUE, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)

  manifest <- atlas_read_manifest()
  occurrences <- tryCatch(atlas_read_occurrences(), error = function(e) NULL)
  if (!is.null(occurrences)) {
    atlas_write_tsv_gz(atlas_public_cells_table(occurrences), atlas_public_cells_path())
    # The pull's own manifest keeps its SQL and host; the published summary
    # is a separate, cut-down copy.
    atlas_write_json(atlas_release_pull_summary(manifest), atlas_public_pull_path())
  }

  paths <- atlas_release_files(grid)
  if (!length(paths)) stop("nothing to publish for the ", grid, " grid", call. = FALSE)
  full <- file.path(atlas_data_dir(), paths)
  hashes <- vapply(full, atlas_sha256, character(1), USE.NAMES = FALSE)
  sizes <- file.info(full)$size
  files_key <- digest::digest(paste(paths, hashes, collapse = "\n"), algo = "sha256")

  current <- atlas_current_release(store, grid)
  if (!is.null(current) && identical(current$files_key, files_key)) {
    say("nothing changed since release ", current$id, "; not publishing")
    return(invisible(current))
  }

  stored <- store$list("objects/")
  keys <- vapply(hashes, atlas_object_key, character(1), USE.NAMES = FALSE)
  missing <- which(!duplicated(keys) & !keys %in% stored)
  for (i in missing) store$put(keys[[i]], full[[i]])
  say("uploaded ", length(missing), " of ", length(paths), " files (",
      round(sum(sizes[missing]) / 1048576, 1), " MB); the rest were already stored")

  # Models per algorithm: Maxent's sit in models/<grid>, the others one level down.
  models <- lapply(stats::setNames(nm = names(ATLAS_ALGORITHMS)), function(algorithm) {
    folder <- if (algorithm == "maxnet") file.path("models", grid) else file.path("models", grid, algorithm)
    sum(grepl("[.]json$", paths) & dirname(paths) == folder)
  })

  id <- atlas_release_id(files_key)
  release <- list(
    id = id,
    grid = grid,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    previous = current$id,
    note = note,
    commit = atlas_code_commit(),
    versions = list(
      r = as.character(getRversion()),
      packages = lapply(stats::setNames(nm = c("terra", "maxnet", "xgboost", "ranger")), function(p) {
        tryCatch(as.character(utils::packageVersion(p)), error = function(e) NULL)
      })
    ),
    layers_key = atlas_layers_key(grid),
    pull = atlas_release_pull_summary(manifest),
    models = models,
    files_key = files_key,
    files = lapply(seq_along(paths), function(i) {
      list(path = paths[[i]], sha256 = hashes[[i]], bytes = sizes[[i]])
    })
  )
  atlas_store_json(store, paste0("releases/", grid, "/", id, ".json"), release)
  atlas_write_json(release, atlas_path("releases", grid, paste0(id, ".json")))
  say("release ", id, ": ", length(paths), " files")
  if (isTRUE(promote)) atlas_promote_release(store, id, grid, quiet = quiet)
  invisible(release)
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
atlas_pull_release <- function(store = atlas_store(), grid = "draft", release = NULL,
                               keep_local = FALSE, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  manifest <- if (is.null(release)) {
    atlas_current_release(store, grid)
  } else {
    atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  }
  if (is.null(manifest)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)

  root <- atlas_data_dir()
  fetched <- 0L
  bytes <- 0
  for (entry in manifest$files) {
    dest <- file.path(root, entry$path)
    if (file.exists(dest) && identical(atlas_sha256(dest), entry$sha256)) next
    staging <- paste0(dest, ".part")
    store$get(atlas_object_key(entry$sha256), staging)
    if (!identical(atlas_sha256(staging), entry$sha256)) {
      unlink(staging)
      stop("the store's copy of ", entry$path, " does not match its hash; nothing replaced",
           call. = FALSE)
    }
    file.rename(staging, dest)
    fetched <- fetched + 1L
    bytes <- bytes + as.numeric(entry$bytes)
  }

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
    unlink(file.path(root, stale))
    removed <- length(stale)
  }

  # Which releases went to Zenodo, and under which DOIs, so the API can list
  # the downloads. Small files, always fetched whole.
  for (key in store$list("archives/")) {
    if (grepl("^archives/[^/]+[.]json$", key)) store$get(key, file.path(root, key))
  }

  atlas_write_json(list(release = manifest$id, grid = grid,
                        pulled_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                   atlas_path("releases", grid, "pulled.json"))
  say("release ", manifest$id, ": downloaded ", fetched, " of ", length(manifest$files),
      " files (", round(bytes / 1048576, 1), " MB)",
      if (removed) paste0(", removed ", removed, " local model files it does not have") else "")
  invisible(list(release = manifest$id, fetched = fetched, removed = removed))
}
