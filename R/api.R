# Helpers behind the HTTP routes. The logic lives here rather than in the
# plumber file so it can be tested without starting a server.

#' Decode a taxon name taken from a URL path.
#'
#' Plumber leaves path parameters percent-encoded, and every species name has a
#' space in it. Decoding twice is harmless, since a decoded name has no percent
#' sign left.
atlas_decode_name <- function(name) {
  if (is.null(name) || !length(name)) {
    return("")
  }
  utils::URLdecode(as.character(name)[[1]])
}

#' One taxon's row, or NULL when the current pull does not hold it.
atlas_taxon_row <- function(taxa, name) {
  if (is.null(taxa) || !nrow(taxa)) {
    return(NULL)
  }
  row <- taxa[taxa$scientific_name == name, , drop = FALSE]
  if (!nrow(row)) {
    return(NULL)
  }
  as.list(row[1, ])
}

#' Where a taxon has been collected, aggregated to the public grid.
#'
#' Returns cell centres, never a record's own coordinates: this is the only
#' shape in which collection locations leave the machine.
atlas_public_cells <- function(records, name, degrees = ATLAS_PUBLIC_DEGREES) {
  empty <- data.frame(
    lat = numeric(), lng = numeric(), records = integer(),
    stringsAsFactors = FALSE
  )
  if (is.null(records) || !nrow(records)) {
    return(empty)
  }
  subset <- records[records$scientific_name == name, , drop = FALSE]
  if (!nrow(subset)) {
    return(empty)
  }
  keys <- atlas_locality_key(subset$latitude, subset$longitude, degrees = degrees)
  counts <- table(keys)
  parts <- do.call(rbind, strsplit(names(counts), ":", fixed = TRUE))
  data.frame(
    lat = (as.numeric(parts[, 1]) + 0.5) * degrees,
    lng = (as.numeric(parts[, 2]) + 0.5) * degrees,
    records = as.integer(counts),
    stringsAsFactors = FALSE
  )
}
