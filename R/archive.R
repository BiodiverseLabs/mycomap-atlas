# Archives: releases and layers deposited on Zenodo, versioned, with DOIs.
#
# Two series per grid, each one Zenodo record with many versions:
#
#   models-<grid>   the maps, scores, counts and collection cells of one
#                   release. A new version when a release is archived.
#   layers-<grid>   the predictor rasters every model was fitted on. A new
#                   version only when a layer is rebuilt, so the 2 GB stack is
#                   not deposited again with every release.
#
# Each version has its own DOI, fixed to exactly those files; the record's
# concept DOI always resolves to the newest. A models version names the
# layers version it was fitted on, so a map can be traced to its inputs.
#
# Which release went to which DOI is kept in a ledger in the store,
# archives/<series>.json, pulled with releases so the API can list downloads.
# Sandbox archives keep a separate ledger (series name ending -sandbox) and
# never mix with real DOIs.
#
# A run leaves a draft on Zenodo unless told to publish: publishing mints the
# DOI and can never be undone, so the draft can be checked on zenodo.org
# first. An unchanged release or layer build is never deposited twice.

ATLAS_ARCHIVE_KINDS <- c("models", "layers")

#' The series name: models-production, layers-draft-sandbox, ...
atlas_archive_series <- function(kind, grid, target = "zenodo") {
  kind <- match.arg(kind, ATLAS_ARCHIVE_KINDS)
  paste0(kind, "-", grid, if (identical(target, "sandbox")) "-sandbox" else "")
}

atlas_archive_ledger_key <- function(series) paste0("archives/", series, ".json")

#' The ledger for a series, or an empty one.
atlas_archive_ledger <- function(store, series) {
  key <- atlas_archive_ledger_key(series)
  if (!is.null(store) && store$exists(key)) {
    return(atlas_store_text(store, key))
  }
  # Fields appear once known: JSON has no NULL, and an empty one would read back as {}.
  list(series = series, versions = list())
}

#' Save a ledger to the store and to this machine, where the API reads it.
atlas_archive_save_ledger <- function(store, ledger) {
  atlas_store_json(store, atlas_archive_ledger_key(ledger$series), ledger)
  atlas_write_json(ledger, atlas_path("archives", paste0(ledger$series, ".json")))
  invisible(ledger)
}

#' Every ledger this machine holds, for the API.
atlas_archive_ledgers <- function() {
  files <- list.files(atlas_path("archives"), pattern = "[.]json$", full.names = TRUE)
  lapply(sort(files), jsonlite::fromJSON, simplifyVector = FALSE)
}

#' The layers version a release was fitted on: the one archived from the same
#' layer builds, whatever its state, or NULL when those layers are not archived.
atlas_archive_layers_for <- function(store, grid, layers_key, target = "zenodo") {
  if (is.null(layers_key)) return(NULL)
  ledger <- atlas_archive_ledger(store, atlas_archive_series("layers", grid, target))
  match <- Filter(function(v) identical(v$key, layers_key), ledger$versions)
  if (length(match)) match[[length(match)]] else NULL
}

#' The newest published version in a ledger, or NULL.
atlas_archive_latest <- function(ledger) {
  published <- Filter(function(v) identical(v$state, "published"), ledger$versions)
  if (length(published)) published[[length(published)]] else NULL
}

# ---- bundles -------------------------------------------------------------

#' Write a tar of files, named inside as given, from a root folder.
atlas_archive_tar <- function(tarfile, root, files, compression = "none") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  utils::tar(tarfile, files = files, compression = compression, tar = "internal")
  tarfile
}

atlas_archive_checksums <- function(dir, sources) {
  sums <- vapply(unname(sources), atlas_sha256, character(1), USE.NAMES = FALSE)
  writeLines(paste0(sums, "  ", names(sources)), file.path(dir, "CHECKSUMS.sha256"))
  sums
}

#' The files of a bundle, with sizes and hashes. sources maps the name a file
#' has on Zenodo to where it is on this machine.
atlas_archive_file_table <- function(sources) {
  full <- unname(sources)
  data.frame(
    name = names(sources),
    path = full,
    bytes = file.info(full)$size,
    sha256 = vapply(full, atlas_sha256, character(1), USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
}

#' Which algorithm a published model path belongs to, or NA.
atlas_archive_algorithm <- function(path, grid) {
  prefix <- paste0("models/", grid, "/")
  if (!startsWith(path, prefix)) return(NA_character_)
  rest <- substring(path, nchar(prefix) + 1L)
  if (!grepl("/", rest, fixed = TRUE)) return("maxnet")
  sub("/.*$", "", rest)
}

#' Build the models bundle for one release: fetch its files from the store,
#' check each against its hash, and pack them into a handful of files, since
#' a Zenodo record holds at most 100.
atlas_archive_models_bundle <- function(store, grid = "draft", release = NULL,
                                        dir = tempfile("atlas-archive-")) {
  manifest <- if (is.null(release)) {
    atlas_current_release(store, grid)
  } else {
    atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  }
  if (is.null(manifest)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)

  tree <- file.path(dir, "tree")
  out <- file.path(dir, "bundle")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  paths <- vapply(manifest$files, function(f) f$path, character(1))
  for (entry in manifest$files) {
    dest <- file.path(tree, entry$path)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    # This machine usually holds the release already; the store is the fallback.
    local <- file.path(atlas_data_dir(), entry$path)
    if (!(file.exists(local) && identical(atlas_sha256(local), entry$sha256) &&
          file.copy(local, dest, overwrite = TRUE))) {
      store$get(atlas_object_key(entry$sha256), dest)
    }
    if (!identical(atlas_sha256(dest), entry$sha256)) {
      stop("the store's copy of ", entry$path, " does not match its hash", call. = FALSE)
    }
  }

  # A tar records each file's time. Stamped with the release's own time, the
  # same release always packs to the same bytes, so a resumed upload can see
  # that a file already on Zenodo is the right one.
  stamp <- as.POSIXct(manifest$created_at %||% "2000-01-01T00:00:00Z", format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  Sys.setFileTime(file.path(tree, paths), stamp)

  names <- character()
  algorithms <- vapply(paths, atlas_archive_algorithm, character(1), grid = grid)
  model_paths <- paths[!is.na(algorithms)]
  model_algorithms <- algorithms[!is.na(algorithms)]
  # Maps per algorithm: raw suitability rasters and the drawn rank maps.
  for (algorithm in intersect(names(ATLAS_ALGORITHMS), unique(model_algorithms))) {
    mine <- model_paths[model_algorithms == algorithm & grepl("[.](tif|png)$", model_paths)]
    if (!length(mine)) next
    name <- paste0("maps-", algorithm, ".tar")
    atlas_archive_tar(normalizePath(file.path(out, name), mustWork = FALSE), tree, mine)
    names <- c(names, name)
  }
  # Every model's scores and settings, all algorithms, in one small archive.
  scores <- model_paths[grepl("[.]json$", model_paths)]
  if (length(scores)) {
    atlas_archive_tar(normalizePath(file.path(out, "scores.tar.gz"), mustWork = FALSE), tree, scores,
                      compression = "gzip")
    names <- c(names, "scores.tar.gz")
  }
  singles <- c(
    "occurrences/taxa-latest.json" = "taxa.json",
    "public/cells.tsv.gz" = "collection-cells-0.1deg.tsv.gz",
    "public/pull.json" = "pull.json"
  )
  singles[[paste0("layers/", grid, "/manifest.json")]] <- "layers-manifest.json"
  for (benchmark in paths[startsWith(paths, paste0("benchmarks/", grid, "/"))]) {
    singles[[benchmark]] <- "benchmark.json"
  }
  for (path in intersect(names(singles), paths)) {
    file.copy(file.path(tree, path), file.path(out, singles[[path]]))
    names <- c(names, singles[[path]])
  }
  atlas_write_json(manifest, file.path(out, "release.json"))
  names <- c(names, "release.json")

  list(
    kind = "models", grid = grid, dir = out,
    version = manifest$id, key = manifest$files_key,
    release = manifest, sources = stats::setNames(file.path(out, names), names)
  )
}

#' Build the layers bundle from this machine's built layers.
atlas_archive_layers_bundle <- function(grid = "draft", dir = tempfile("atlas-archive-")) {
  layer_dir <- atlas_layer_dir(grid)
  manifest_file <- file.path(layer_dir, "manifest.json")
  if (!file.exists(manifest_file)) stop("no layers are built for the ", grid, " grid", call. = FALSE)
  manifest <- atlas_layer_manifest(grid)
  out <- file.path(dir, "bundle")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  # Uploaded from where they are built: the stack is gigabytes, not worth a copy.
  rasters <- list.files(layer_dir, pattern = "[.]tif$")
  key <- atlas_layers_key(grid, manifest)
  built <- vapply(manifest, function(x) as.character(x$built_at %||% ""), character(1))
  day <- substr(max(c(built, "")), 1, 10)
  list(
    kind = "layers", grid = grid, dir = out,
    version = paste0(grid, "-", if (nzchar(day)) day else "undated", "-", substr(key, 1, 8)),
    key = key, layers = manifest,
    sources = c(stats::setNames(file.path(layer_dir, rasters), rasters),
                "layers-manifest.json" = manifest_file)
  )
}

#' Refuse a bundle Zenodo would refuse, before uploading gigabytes of it.
atlas_archive_check_size <- function(files) {
  if (nrow(files) > ATLAS_ZENODO_MAX_FILES) {
    stop(nrow(files), " files is more than Zenodo's ", ATLAS_ZENODO_MAX_FILES, " per record",
         call. = FALSE)
  }
  total <- sum(files$bytes)
  if (total > ATLAS_ZENODO_MAX_BYTES) {
    stop(sprintf("%.1f GB is more than Zenodo's 50 GB per record; split the series or ask Zenodo for a larger quota",
                 total / 1024^3), call. = FALSE)
  }
  invisible(total)
}

# ---- metadata ------------------------------------------------------------

atlas_archive_template <- function(root = Sys.getenv("ATLAS_ROOT", unset = ".")) {
  path <- file.path(root, "inst", "archive", "zenodo.json")
  if (!file.exists(path)) path <- system.file("archive", "zenodo.json", package = "mycomapatlas")
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

atlas_html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

#' A README for the bundle, and the same facts as the record's description.
atlas_archive_readme <- function(bundle, files, layers_version = NULL) {
  size <- function(bytes) {
    if (bytes >= 1024^3) sprintf("%.1f GB", bytes / 1024^3) else sprintf("%.1f MB", bytes / 1024^2)
  }
  lines <- c(
    paste0("# ", if (bundle$kind == "models") "MycoMap Atlas habitat models" else "MycoMap Atlas environmental predictors",
           ", ", bundle$grid, " grid"),
    "",
    paste0("Version: ", bundle$version)
  )
  if (bundle$kind == "models") {
    r <- bundle$release
    lines <- c(
      lines,
      paste0("Atlas release: ", r$id, " (", r$created_at, ")"),
      paste0("Code: https://github.com/BiodiverseLabs/mycomap-atlas", if (!is.null(r$commit) && !is.na(r$commit)) paste0("/tree/", r$commit) else ""),
      paste0("Records: ", r$pull$records %||% "?", " DNA-validated collections, ", r$pull$taxa %||% "?",
             " taxa, pulled ", r$pull$pulled_at %||% "?", ", fingerprint ", r$pull$fingerprint %||% "?"),
      paste0("Models: ", paste(sprintf("%s %s", names(r$models), unlist(r$models)), collapse = ", ")),
      if (!is.null(layers_version)) paste0("Fitted on predictors: ", layers_version$version,
                                           if (!is.null(layers_version$doi)) paste0(" (doi:", layers_version$doi, ")") else "")
    )
  }
  lines <- c(
    lines, "",
    "## Files", "",
    paste0("- `", files$name, "` (", vapply(files$bytes, size, character(1)), ")"),
    "- `CHECKSUMS.sha256`: SHA-256 of every file above; check with `sha256sum -c CHECKSUMS.sha256`.",
    ""
  )
  if (bundle$kind == "models") {
    lines <- c(
      lines,
      "`maps-<model>.tar` holds, per taxon, the raw suitability raster (GeoTIFF, North America Albers Equal Area,",
      "inside the 500 km accessible area) and the drawn map (PNG, Web Mercator, coloured by percentile).",
      "`scores.tar.gz` holds each model's scores on every spatial fold, predictors and settings.",
      "Collection locations appear only as 0.1 degree cells; exact coordinates are never published.",
      ""
    )
  } else {
    lines <- c(
      lines,
      "Each GeoTIFF is one group of predictors on the Atlas grid (North America Albers Equal Area).",
      "`layers-manifest.json` lists every band with its source, licence, cell size and checksum.",
      "Sources: WorldClim 2.1 (CC BY-SA 4.0), SoilGrids 2.0 (CC BY 4.0), ESA WorldCover 2021 (CC BY 4.0).",
      # The Open Government Licence - Canada asks for this attribution wherever
      # NFI-derived data goes.
      if ("hosts" %in% vapply(bundle$layers %||% list(), function(x) as.character(x$id %||% ""), character(1))) {
        paste("Host trees: USFS FIA BIGMAP 2018 (US public domain); contains information licensed",
              "under the Open Government Licence - Canada (NFI kNN 2011, Natural Resources Canada).")
      },
      ""
    )
  }
  c(lines, "Method: https://atlas.mycomap.org/methods", "Sources and licences: https://atlas.mycomap.org/sources")
}

#' The Zenodo metadata for one version.
atlas_archive_metadata <- function(bundle, readme, template = atlas_archive_template(),
                                   layers_version = NULL, today = Sys.Date()) {
  common <- template$common
  own <- template[[bundle$kind]]
  fill <- function(x) gsub("{grid}", bundle$grid, x, fixed = TRUE)
  related <- c(common$related_identifiers, own$related_identifiers)
  if (!is.null(layers_version$doi)) {
    related <- c(related, list(list(identifier = layers_version$doi, relation = "isDerivedFrom", scheme = "doi")))
  }
  body <- readme[!startsWith(readme, "# ")]
  description <- paste0(
    "<p>", atlas_html_escape(fill(own$summary)), "</p>",
    "<pre>", atlas_html_escape(paste(body, collapse = "\n")), "</pre>"
  )
  metadata <- list(
    upload_type = common$upload_type,
    title = fill(own$title),
    creators = common$creators,
    description = description,
    access_right = common$access_right,
    license = common$license,
    keywords = common$keywords,
    version = bundle$version,
    publication_date = format(today, "%Y-%m-%d"),
    related_identifiers = related
  )
  if (length(common$communities)) metadata$communities <- common$communities
  metadata
}

# ---- archiving -----------------------------------------------------------

#' Deposit a bundle as the next version of its series.
#'
#' Leaves a draft unless publish = TRUE. Skips a bundle whose key matches the
#' newest published version, and refuses while an earlier draft is still
#' waiting, so two drafts never compete for the next version.
atlas_archive_deposit <- function(bundle, store, z, publish = FALSE, dry_run = FALSE,
                                  template = atlas_archive_template(), quiet = FALSE,
                                  resume_draft = NULL) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  series <- atlas_archive_series(bundle$kind, bundle$grid, z$target)
  ledger <- atlas_archive_ledger(store, series)

  waiting <- Filter(function(v) identical(v$state, "draft"), ledger$versions)
  if (length(waiting)) {
    stop("version ", waiting[[1]]$version, " of ", series, " is still a draft at ", waiting[[1]]$url,
         ": publish it with archive-publish, or discard it with archive-discard", call. = FALSE)
  }
  latest <- atlas_archive_latest(ledger)
  if (!is.null(latest) && identical(latest$key, bundle$key)) {
    say(series, ": nothing changed since version ", latest$version, " (doi:", latest$doi, "); not archiving")
    return(invisible(ledger))
  }

  readme_path <- file.path(bundle$dir, "README.md")
  layers_version <- if (bundle$kind == "models") {
    atlas_archive_layers_for(store, bundle$grid, bundle$release$layers_key, z$target)
  }
  # The README lists the files; the checksums then cover the README too.
  files <- atlas_archive_file_table(bundle$sources)
  writeLines(atlas_archive_readme(bundle, files, layers_version), readme_path)
  sources <- c(bundle$sources, "README.md" = readme_path)
  atlas_archive_checksums(bundle$dir, sources)
  files <- atlas_archive_file_table(c(sources, "CHECKSUMS.sha256" = file.path(bundle$dir, "CHECKSUMS.sha256")))
  total <- atlas_archive_check_size(files)
  metadata <- atlas_archive_metadata(bundle, readLines(readme_path), template, layers_version)

  if (isTRUE(dry_run)) {
    say(series, " version ", bundle$version, ": ", nrow(files), " files, ",
        sprintf("%.2f GB", total / 1024^3), " -> ", z$target,
        if (is.null(latest)) " (a new record)" else paste0(" (a new version after ", latest$version, ")"))
    for (i in seq_len(nrow(files))) say(sprintf("  %-34s %10.1f MB", files$name[i], files$bytes[i] / 1048576))
    return(invisible(list(ledger = ledger, files = files, metadata = metadata)))
  }

  # An upload that stopped part way leaves its draft in the ledger as
  # uploading: carry on in that draft rather than start a second record.
  unfinished <- Filter(function(v) identical(v$state, "uploading"), ledger$versions)
  if (length(unfinished) && !identical(unfinished[[1]]$key, bundle$key)) {
    stop("an unfinished upload of version ", unfinished[[1]]$version, " of ", series,
         " is on Zenodo at ", unfinished[[1]]$url, "; discard it with archive-discard first",
         call. = FALSE)
  }
  resume_id <- if (length(unfinished)) unfinished[[1]]$deposition_id else resume_draft
  draft <- if (!is.null(resume_id)) {
    found <- z$call("GET", paste0("/deposit/depositions/", resume_id))
    if (isTRUE(found$submitted)) stop("Zenodo record ", resume_id, " is already published", call. = FALSE)
    say(series, ": carrying on in the unfinished draft ", resume_id)
    found
  } else if (is.null(latest)) {
    atlas_zenodo_create(z)
  } else {
    atlas_zenodo_new_version(z, latest$deposition_id)
  }

  entry <- list(
    version = bundle$version,
    key = bundle$key,
    release = if (bundle$kind == "models") bundle$release$id else NULL,
    layers_version = layers_version$version,
    deposition_id = draft$id,
    url = draft$links$html %||% paste0(sub("/api$", "", z$base), "/deposit/", draft$id),
    state = "uploading",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    bytes = total,
    files = lapply(seq_len(nrow(files)), function(i) {
      list(name = files$name[i], bytes = files$bytes[i], sha256 = files$sha256[i])
    })
  )
  entry <- Filter(Negate(is.null), entry)
  # Written before a byte is uploaded, so a run that dies leaves a draft
  # the next run knows about, never one only Zenodo knows about.
  index <- which(vapply(ledger$versions, function(v) identical(v$state, "uploading"), logical(1)))
  index <- if (length(index)) index[[1]] else length(ledger$versions) + 1L
  ledger$versions[[index]] <- entry
  atlas_archive_save_ledger(store, ledger)

  atlas_zenodo_sync_files(z, draft, files, say)
  atlas_zenodo_set_metadata(z, draft$id, metadata)

  ledger$versions[[index]]$state <- "draft"
  atlas_archive_save_ledger(store, ledger)
  say(series, " version ", bundle$version, ": draft ready at ", entry$url)

  if (isTRUE(publish)) {
    ledger <- atlas_archive_publish(store, series, z, quiet = quiet)
  }
  invisible(ledger)
}

#' Publish the waiting draft of a series: mints its DOI, permanently.
atlas_archive_publish <- function(store, series, z, quiet = FALSE) {
  ledger <- atlas_archive_ledger(store, series)
  index <- which(vapply(ledger$versions, function(v) identical(v$state, "draft"), logical(1)))
  if (!length(index)) stop(series, " has no draft waiting to be published", call. = FALSE)
  index <- index[[1]]
  entry <- ledger$versions[[index]]
  record <- atlas_zenodo_publish(z, entry$deposition_id)
  entry$state <- "published"
  entry$doi <- record$doi
  entry$record_id <- record$record_id %||% record$id
  entry$url <- record$links$html %||% entry$url
  entry$published_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ledger$versions[[index]] <- entry
  ledger$concept_doi <- record$conceptdoi %||% ledger$concept_doi
  ledger$concept_recid <- record$conceptrecid %||% ledger$concept_recid
  atlas_archive_save_ledger(store, ledger)
  if (!isTRUE(quiet)) {
    message(series, " version ", entry$version, " published: doi:", entry$doi,
            " (all versions: doi:", ledger$concept_doi, ")")
  }
  invisible(ledger)
}

#' Throw away the waiting draft of a series.
atlas_archive_discard <- function(store, series, z, quiet = FALSE) {
  ledger <- atlas_archive_ledger(store, series)
  index <- which(vapply(ledger$versions, function(v) v$state %in% c("draft", "uploading"), logical(1)))
  if (!length(index)) stop(series, " has no draft to discard", call. = FALSE)
  entry <- ledger$versions[[index[[1]]]]
  atlas_zenodo_discard(z, entry$deposition_id)
  ledger$versions <- ledger$versions[-index[[1]]]
  atlas_archive_save_ledger(store, ledger)
  if (!isTRUE(quiet)) message(series, ": discarded the draft of version ", entry$version)
  invisible(ledger)
}

#' Archive a release, the layers, or both, as the next versions of their series.
atlas_archive <- function(store, grid = "draft", kinds = ATLAS_ARCHIVE_KINDS, release = NULL,
                          z, publish = FALSE, dry_run = FALSE, quiet = FALSE, resume_draft = NULL) {
  # Layers first: a models version records which layers version it was fitted on.
  for (kind in intersect(c("layers", "models"), kinds)) {
    bundle <- if (kind == "layers") {
      atlas_archive_layers_bundle(grid)
    } else {
      atlas_archive_models_bundle(store, grid, release)
    }
    on.exit(unlink(dirname(bundle$dir), recursive = TRUE), add = TRUE)
    atlas_archive_deposit(bundle, store, z, publish = publish, dry_run = dry_run, quiet = quiet,
                          resume_draft = resume_draft)
  }
  invisible(TRUE)
}
