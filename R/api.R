# Helpers behind the HTTP routes. The logic lives here rather than in the
# plumber file so it can be tested without starting a server.

# The development API answers a browser on the developer's own machine. A
# wildcard would let any site that developer happens to visit read it, so an
# origin is matched exactly — never by prefix, which would accept
# http://localhost:5101.example.com.
ATLAS_DEFAULT_ORIGINS <- c("http://localhost:5101", "http://127.0.0.1:5101")

#' Origins the API will answer cross-site, from ATLAS_ALLOWED_ORIGINS.
atlas_allowed_origins <- function() {
  configured <- Sys.getenv("ATLAS_ALLOWED_ORIGINS", unset = "")
  if (!nzchar(configured)) {
    return(ATLAS_DEFAULT_ORIGINS)
  }
  origins <- trimws(strsplit(configured, ",", fixed = TRUE)[[1]])
  origins[nzchar(origins)]
}

#' The origin to echo back, or NULL when it is not allowed.
atlas_allowed_origin <- function(origin, allowed = atlas_allowed_origins()) {
  if (is.null(origin) || !length(origin)) {
    return(NULL)
  }
  origin <- as.character(origin)[[1]]
  if (!nzchar(origin) || !origin %in% allowed) {
    return(NULL)
  }
  origin
}

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
