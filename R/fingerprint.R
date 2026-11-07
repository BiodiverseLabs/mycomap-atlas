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

# A taxon's fingerprint and a model's seed stay private, where the refits read
# them, and nothing public carries them (Steve, 2026-11-05). The calculation must
# never change: every model would read as stale and refit. The pull's own
# fingerprint is public: it is what a result cites.
ATLAS_PRIVATE_FIELDS <- c("fingerprint", "seed")

#' x, as anything public may carry it: without the private fields, at any depth.
#' A table loses the columns; the files x was read from do not change.
atlas_public_fields <- function(x) {
  if (!is.list(x)) return(x)
  if (!is.null(names(x))) x <- x[!names(x) %in% ATLAS_PRIVATE_FIELDS]
  if (is.data.frame(x)) return(x)
  x[] <- lapply(x, atlas_public_fields)
  x
}

#' JSON text without the private fields, every other byte as it was, so an
#' archived file differs from the release's only by what was withheld. Stops
#' rather than publish anything it could not take out cleanly.
atlas_public_json_text <- function(text) {
  field <- paste0('"(?:', paste(ATLAS_PRIVATE_FIELDS, collapse = "|"), ')"\\s*:\\s*(?:"[^"]*"|-?[0-9.eE+-]+|null|\\[\\s*\\]|\\{\\s*\\})')
  out <- gsub(paste0("\\s*", field, "\\s*,"), "", text, perl = TRUE)
  out <- gsub(paste0(",\\s*", field, "(?=\\s*[}])"), "", out, perl = TRUE)
  out <- gsub(paste0("\\s*", field, "(?=\\s*[}])"), "", out, perl = TRUE)
  read <- function(json) jsonlite::fromJSON(json, simplifyVector = FALSE)
  if (!identical(read(out), atlas_public_fields(read(text)))) {
    stop("a file's private fields could not be taken out cleanly", call. = FALSE)
  }
  out
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
