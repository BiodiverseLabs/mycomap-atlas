# A model is invalidated by a change in the records it was trained on, never by
# a change in a name string. Half of the modelable taxa carry provisional temp
# codes that FungAI can rename or re-cluster, so every taxon carries a
# fingerprint of its record set and the nightly refit compares fingerprints.

ATLAS_FINGERPRINT_FIELDS <- c(
  "id", "scientific_name", "latitude", "longitude", "observed_on"
)

#' Fingerprint a set of records. Order-independent, content-sensitive.
atlas_fingerprint <- function(df) {
  if (is.null(df) || !nrow(df)) {
    return(digest::digest("", algo = "sha256"))
  }
  missing <- setdiff(ATLAS_FINGERPRINT_FIELDS, names(df))
  if (length(missing)) {
    stop("cannot fingerprint, missing columns: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  parts <- lapply(ATLAS_FINGERPRINT_FIELDS, function(f) as.character(df[[f]]))
  rows <- do.call(paste, c(parts, sep = "\x1f"))
  digest::digest(paste(sort(rows), collapse = "\x1e"), algo = "sha256")
}

#' Grid cell a coordinate falls in, as a key. Used for counting independent
#' localities and, at a coarser grid, for anything shown on a map.
atlas_locality_key <- function(lat, lng, degrees = ATLAS_LOCALITY_DEGREES) {
  paste(
    floor(as.numeric(lat) / degrees),
    floor(as.numeric(lng) / degrees),
    sep = ":"
  )
}

#' Records, independent localities and a fingerprint for every taxon.
atlas_taxon_fingerprints <- function(df) {
  empty <- data.frame(
    scientific_name = character(), records = integer(),
    localities = integer(), fingerprint = character(),
    stringsAsFactors = FALSE
  )
  if (is.null(df) || !nrow(df)) {
    return(empty)
  }
  by_name <- split(seq_len(nrow(df)), df$scientific_name)
  rows <- lapply(names(by_name), function(name) {
    sub <- df[by_name[[name]], , drop = FALSE]
    data.frame(
      scientific_name = name,
      records = nrow(sub),
      localities = length(unique(atlas_locality_key(sub$latitude, sub$longitude))),
      fingerprint = atlas_fingerprint(sub),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[order(-out$localities, out$scientific_name), , drop = FALSE]
  rownames(out) <- NULL
  out
}
