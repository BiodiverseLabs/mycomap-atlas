# Development API for the Atlas web app.
#
# It serves what the pull wrote, and never an exact coordinate: the map
# endpoint aggregates to ATLAS_PUBLIC_DEGREES, which is the rule published
# rasters follow too.

root <- Sys.getenv("ATLAS_ROOT", unset = ".")

if (requireNamespace("mycomapatlas", quietly = TRUE)) {
  library(mycomapatlas)
} else {
  for (file in list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) {
    source(file)
  }
}

cache <- new.env(parent = emptyenv())

cached_occurrences <- function() {
  if (is.null(cache$occurrences)) {
    cache$occurrences <- atlas_read_occurrences()
  }
  cache$occurrences
}

# On a machine that holds a release but never made the pull, there are no
# occurrences; the collection cells come from what the release published.
cached_cells_source <- function() {
  if (is.null(cache$cells_source)) {
    occurrences <- tryCatch(cached_occurrences(), error = function(e) NULL)
    cache$cells_source <- list(
      occurrences = occurrences,
      public = if (is.null(occurrences)) atlas_read_public_cells() else NULL
    )
  }
  cache$cells_source
}

cached_taxa <- function() {
  if (is.null(cache$taxa)) {
    # The pull already wrote this; recomputing 17k fingerprints per boot is
    # pure waste. Fall back to computing them if the file is missing or empty.
    path <- atlas_path("occurrences", "taxa-latest.json")
    from_file <- if (file.exists(path)) {
      jsonlite::fromJSON(path, simplifyVector = TRUE)
    } else {
      NULL
    }
    cache$taxa <- if (is.data.frame(from_file) && nrow(from_file)) {
      from_file
    } else {
      atlas_taxon_fingerprints(cached_occurrences())
    }
  }
  cache$taxa
}

#* @filter cors
function(req, res) {
  # The web app reaches this through vite's proxy, which is same-origin, so
  # nothing normal depends on these headers. They exist for a browser opened
  # straight at the dev server, and only for origins on the allowlist.
  origin <- atlas_allowed_origin(req$HTTP_ORIGIN)
  if (!is.null(origin)) {
    res$setHeader("Access-Control-Allow-Origin", origin)
    res$setHeader("Vary", "Origin")
  }
  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Content-Type")
    res$status <- 200L
    return(list())
  }
  plumber::forward()
}

#* This API's OpenAPI description: the file the developer page is drawn from.
#* @get /api/openapi.json
#* @serializer contentType list(type = "application/json")
function() {
  path <- atlas_openapi_path(root)
  readBin(path, "raw", file.info(path)$size)
}

#* Every dataset, package and paper Atlas is built on, and every file it makes.
#* @get /api/sources
#* @serializer contentType list(type = "application/json")
function() {
  path <- atlas_sources_path(root)
  readBin(path, "raw", file.info(path)$size)
}

#* What the last pull holds.
#* @get /api/status
#* @serializer unboxedJSON
function() {
  manifest <- atlas_status_manifest()
  if (is.null(manifest)) {
    return(list(ready = FALSE))
  }
  out <- list(
    ready = TRUE,
    pulledAt = manifest$pulled_at,
    records = manifest$records,
    taxa = manifest$taxa,
    fingerprint = manifest$fingerprint
  )
  # A full pull has no since date. Leave the field out rather than shipping an
  # NA, which serialises as an empty object.
  since <- manifest$since
  if (length(since) && !is.na(since)) {
    out$since <- as.character(since)
  }
  out
}

#* Environmental layers: what is registered, and what of it is built.
#* @param grid draft or production
#* @get /api/layers
#* @serializer unboxedJSON
function(grid = "draft") {
  list(grid = grid, layers = atlas_layer_overview(grid))
}

#* Taxa with their record and locality counts.
#* @param search Part of a scientific name
#* @param min_localities Smallest number of independent localities
#* @param limit Page size
#* @param offset Rows to skip
#* @get /api/taxa
#* @serializer unboxedJSON
function(search = "", min_localities = 0, limit = 100, offset = 0) {
  rows <- cached_taxa()
  rows <- rows[rows$localities >= as.numeric(min_localities), , drop = FALSE]
  if (nzchar(search)) {
    keep <- grepl(tolower(search), tolower(rows$scientific_name), fixed = TRUE)
    rows <- rows[keep, , drop = FALSE]
  }
  total <- nrow(rows)
  offset <- max(0, as.integer(offset))
  limit <- max(1, as.integer(limit))
  page <- if (offset >= total) rows[0, , drop = FALSE] else {
    rows[seq(offset + 1, min(total, offset + limit)), , drop = FALSE]
  }
  list(total = total, items = page)
}

#* One taxon's counts.
#* @get /api/taxa/<name>
#* @serializer unboxedJSON
function(name, res) {
  row <- atlas_taxon_row(cached_taxa(), atlas_decode_name(name))
  if (is.null(row)) {
    res$status <- 404L
    return(list(error = "no such taxon in the current pull"))
  }
  row
}

#* Every fitted model, newest first, as a light summary. The full record of
#* one model is at /api/taxa/<name>/model.
#* @param grid draft or production
#* @get /api/models
#* @serializer unboxedJSON
function(grid = "draft") {
  key <- paste0("models_", grid)
  if (is.null(cache[[key]])) {
    cache[[key]] <- new.env(parent = emptyenv())
  }
  list(grid = grid, models = atlas_model_index(grid, cache[[key]]))
}

#* The models Atlas fits, with the labels people see.
#* @get /api/algorithms
#* @serializer unboxedJSON
function() {
  atlas_algorithm_labels()
}

#* The newest model benchmark: every model scored on the same folds.
#* @get /api/benchmarks/latest
#* @serializer unboxedJSON
function(grid = "draft", res) {
  study <- atlas_latest_study("benchmarks", grid, prefix = "models")
  if (is.null(study)) {
    res$status <- 404L
    return(list(error = "no benchmark has been run yet"))
  }
  study
}

#* One taxon's fitted model: its scores, settings and map bounds.
#* @param algorithm maxnet (default), xgboost or rf
#* @get /api/taxa/<name>/model
#* @serializer unboxedJSON
function(name, grid = "draft", algorithm = "maxnet", res) {
  algorithm <- atlas_request_algorithm(algorithm)
  if (is.null(algorithm)) {
    res$status <- 400L
    return(list(error = "unknown algorithm"))
  }
  path <- atlas_model_path(atlas_decode_name(name), grid, ".json", algorithm)
  if (!file.exists(path)) {
    res$status <- 404L
    return(list(error = "no model for this taxon yet"))
  }
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

#* A taxon's suitability map, ready to lay over a slippy map.
#* @param algorithm maxnet (default), xgboost or rf
#* @get /api/taxa/<name>/map.png
#* @serializer contentType list(type = "image/png")
function(name, grid = "draft", algorithm = "maxnet", res) {
  algorithm <- atlas_request_algorithm(algorithm)
  if (is.null(algorithm)) {
    res$status <- 400L
    return(raw())
  }
  path <- atlas_model_path(atlas_decode_name(name), grid, ".png", algorithm)
  if (!file.exists(path)) {
    res$status <- 404L
    return(raw())
  }
  readBin(path, "raw", file.info(path)$size)
}

#* Where a taxon has been collected, aggregated to the public grid.
#* @get /api/taxa/<name>/cells
#* @serializer unboxedJSON
function(name) {
  decoded <- atlas_decode_name(name)
  source <- cached_cells_source()
  cells <- atlas_taxon_cells(decoded, source$occurrences, source$public)
  list(name = decoded, degrees = ATLAS_PUBLIC_DEGREES, cells = cells)
}
