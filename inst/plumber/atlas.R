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

#* What the last pull holds.
#* @get /api/status
#* @serializer unboxedJSON
function() {
  manifest <- atlas_read_manifest()
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

#* Where a taxon has been collected, aggregated to the public grid.
#* @get /api/taxa/<name>/cells
#* @serializer unboxedJSON
function(name) {
  decoded <- atlas_decode_name(name)
  cells <- atlas_public_cells(cached_occurrences(), decoded)
  list(name = decoded, degrees = ATLAS_PUBLIC_DEGREES, cells = cells)
}
