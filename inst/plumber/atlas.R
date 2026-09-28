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
    cache$taxa <- atlas_taxon_fingerprints(cached_occurrences())
  }
  cache$taxa
}

#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
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
  list(
    ready = TRUE,
    pulledAt = manifest$pulled_at,
    records = manifest$records,
    taxa = manifest$taxa,
    fingerprint = manifest$fingerprint,
    since = manifest$since
  )
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
  rows <- cached_taxa()
  row <- rows[rows$scientific_name == name, , drop = FALSE]
  if (!nrow(row)) {
    res$status <- 404L
    return(list(error = "no such taxon in the current pull"))
  }
  as.list(row[1, ])
}

#* Where a taxon has been collected, aggregated to the public grid.
#* @get /api/taxa/<name>/cells
#* @serializer unboxedJSON
function(name) {
  records <- cached_occurrences()
  subset <- records[records$scientific_name == name, , drop = FALSE]
  if (!nrow(subset)) {
    return(list(name = name, degrees = ATLAS_PUBLIC_DEGREES, cells = list()))
  }
  keys <- atlas_locality_key(subset$latitude, subset$longitude,
                             degrees = ATLAS_PUBLIC_DEGREES)
  counts <- table(keys)
  parts <- do.call(rbind, strsplit(names(counts), ":", fixed = TRUE))
  cells <- data.frame(
    lat = (as.numeric(parts[, 1]) + 0.5) * ATLAS_PUBLIC_DEGREES,
    lng = (as.numeric(parts[, 2]) + 0.5) * ATLAS_PUBLIC_DEGREES,
    records = as.integer(counts),
    stringsAsFactors = FALSE
  )
  list(name = name, degrees = ATLAS_PUBLIC_DEGREES, cells = cells)
}
