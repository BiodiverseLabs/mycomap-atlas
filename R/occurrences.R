# The phase 1 training universe: records mycomap.org has validated by DNA, with
# coordinates good enough for a 1 km model, in North America.
#
# Eligibility (decided 2026-09-28):
#   - green in at least one validation project (decided 2026-09-30: a red in
#     another project does not rule it out; the green project settled the name);
#   - coordinates present, not obscured, accuracy within 1 km where recorded;
#   - for a Mushroom Observer record, a GPS point the observer has not hidden,
#     or else a named location small enough that its centre is within
#     ATLAS_MO_MAX_LOCATION_M of every point in it (R/occurrences.R
#     atlas_mo_location_clause);
#   - for a MyCoPortal record, MyCoPortal's own coordinates within
#     ATLAS_MO_MAX_LOCATION_M, or a place geocoded from its label that no
#     record with a different label shares, which would make it a county's or
#     state's centre (atlas_mycoportal_location_clause);
#   - in North America (or a Puerto Rico record with a blank country);
#   - a species-level name, provisional temp codes included.
#
# Records green only in a fourth or later project are missed, because .org
# flattens three validation slots. MycoMap Vision has the same limitation, and
# the fix for both is a shared view on .org rather than a change here.
#
# Unassessed records and eDNA are deliberately out of phase 1.

ATLAS_OCCURRENCE_FIELDS <- c(
  "id", "observation_id", "source", "scientific_name", "genus", "observed_on",
  "latitude", "longitude", "state", "country", "sequence_id", "updated_at"
)

#' One page of the eligible universe, ordered by id for keyset paging.
atlas_occurrence_sql <- function(after_id = 0, limit = 20000, since = NULL) {
  stopifnot(length(after_id) == 1, is.numeric(after_id), after_id >= 0)
  stopifnot(length(limit) == 1, is.numeric(limit), limit > 0)
  if (!is.null(since) && !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", since)) {
    stop("since must be a YYYY-MM-DD date", call. = FALSE)
  }
  since_clause <- if (is.null(since)) "" else {
    sprintf("AND o.updated_at >= date '%s'", since)
  }
  countries <- paste(sprintf("'%s'", ATLAS_NA_COUNTRIES), collapse = ", ")
  statuses <- paste(
    "coalesce(o.validation_status_1, '')",
    "coalesce(o.validation_status_2, '')",
    "coalesce(o.validation_status_3, '')",
    sep = ", "
  )
  sql <- sprintf(
    "SELECT %s FROM observations o
     WHERE 'yes' IN (%s)
       AND o.latitude IS NOT NULL
       AND o.longitude IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM observation_cache c
         WHERE c.source = 'inat'
           AND c.source_observation_id = o.observation_id
           AND (c.coordinates_obscured = true OR c.positional_accuracy > %d))
       AND (o.country IN (%s) OR o.state = 'Puerto Rico')
       AND o.scientific_name IS NOT NULL
       AND o.scientific_name NOT IN ('', 'Fungi', 'Unknown')
       AND strpos(o.scientific_name, ' ') > 0
       AND right(lower(o.scientific_name), 4) <> ' sp.'
       AND right(lower(o.scientific_name), 3) <> ' sp'
       %s
       %s
       %s
       AND o.id > %d
     ORDER BY o.id
     LIMIT %d",
    paste0("o.", ATLAS_OCCURRENCE_FIELDS, collapse = ", "),
    statuses, ATLAS_MAX_ACCURACY_M, countries, since_clause,
    atlas_mo_location_clause(), atlas_mycoportal_location_clause(),
    as.integer(after_id), as.integer(limit)
  )
  atlas_one_line(sql)
}

# How .org labels MyCoPortal records (both spellings occur).
ATLAS_MYCOPORTAL_SOURCES <- c("MycoPortal", "MyCoPortal")
# What to do with a MyCoPortal record .org has not yet fetched MyCoPortal's
# answer for: keep it ("keep") or leave it out ("drop").
ATLAS_MYCOPORTAL_UNKNOWN <- "keep"

#' The SQL condition that keeps only MyCoPortal records placed well enough
#' to model.
#'
#' Legacy .com places a MyCoPortal record by geocoding its label: MyCoPortal's
#' coordinates when it has them, else a place search on the locality, and
#' when that fails the county or state alone. .org's mycoportal_data holds
#' MyCoPortal's own answer for each record (filled by .org's
#' backfillMycoportalData script). A record passes when MyCoPortal placed it
#' with an uncertainty within max_m, or recorded none; or, when MyCoPortal
#' gave no coordinates, when no record with a different locality sits on
#' exactly the same point: many labels on one point means the geocoder fell
#' back to the county or state. A record with no answer yet is kept or
#' dropped as unknown says. Other sources are untouched.
atlas_mycoportal_location_clause <- function(max_m = ATLAS_MO_MAX_LOCATION_M,
                                             unknown = ATLAS_MYCOPORTAL_UNKNOWN) {
  unknown <- match.arg(unknown, c("keep", "drop"))
  sources <- paste(sprintf("'%s'", ATLAS_MYCOPORTAL_SOURCES), collapse = ", ")
  answered <- "p.observation_id = o.observation_id AND p.sync_status = 'success'"
  placed <- sprintf(paste(
    "EXISTS (SELECT 1 FROM mycoportal_data p WHERE %s AND (",
    "(p.decimal_latitude IS NOT NULL AND coalesce(p.coordinate_uncertainty_in_meters, 0) <= %d)",
    "OR (p.decimal_latitude IS NULL AND NOT EXISTS (SELECT 1 FROM observations o2",
    "JOIN mycoportal_data p2 ON p2.observation_id = o2.observation_id",
    "WHERE o2.latitude = o.latitude AND o2.longitude = o.longitude",
    "AND o2.observation_id <> o.observation_id",
    "AND coalesce(p2.locality, '') <> coalesce(p.locality, '')))))"
  ), answered, as.integer(max_m))
  unanswered <- sprintf("NOT EXISTS (SELECT 1 FROM mycoportal_data p WHERE %s)", answered)
  keep <- if (identical(unknown, "keep")) paste(placed, "OR", unanswered) else placed
  sprintf("AND (o.source NOT IN (%s) OR %s)", sources, keep)
}

# How .org labels Mushroom Observer records, and how its cache labels their
# MO answers.
ATLAS_MO_SOURCE <- "MO Observations"
ATLAS_MO_CACHE_SOURCE <- "mo"
# A Mushroom Observer record without a GPS point carries the centre of a named
# location (a park, a county). It is kept when every point of that location
# lies within this many metres of the centre: half the box's diagonal.
ATLAS_MO_MAX_LOCATION_M <- 5000
# What to do with an MO record whose MO answer .org has not cached: keep it
# ("keep") or leave it out ("drop").
ATLAS_MO_UNKNOWN <- "keep"

#' The SQL condition that keeps only Mushroom Observer records placed well
#' enough to model.
#'
#' .org caches each MO observation's API answer (observation_cache,
#' api_response_json): latitude and longitude are the observer's GPS point,
#' null when there is none; gps_hidden says the observer hid it; location is
#' the named place with its north, south, east and west edges. A record
#' passes when its GPS point is there and not hidden, or when half the
#' location box's diagonal is within max_m. Records of other sources are
#' untouched. One line, with no double quote or percent sign, like every
#' statement sent to the SQL route.
atlas_mo_location_clause <- function(max_m = ATLAS_MO_MAX_LOCATION_M,
                                     unknown = ATLAS_MO_UNKNOWN) {
  unknown <- match.arg(unknown, c("keep", "drop"))
  json <- "CAST(m.api_response_json AS jsonb)"
  edge <- function(side) sprintf("(%s -> 'location' ->> '%s')::numeric", json, side)
  half_diagonal_km <- sprintf(
    "sqrt(power((%s - %s) * 111.2, 2) + power((%s - %s) * 111.2 * cos(radians((%s + %s) / 2)), 2)) / 2",
    edge("latitude_north"), edge("latitude_south"),
    edge("longitude_east"), edge("longitude_west"),
    edge("latitude_north"), edge("latitude_south")
  )
  placed <- sprintf(
    paste(
      "EXISTS (SELECT 1 FROM observation_cache m WHERE m.source = '%s'",
      "AND m.source_observation_id = o.observation_id",
      "AND coalesce((%s ->> 'gps_hidden')::boolean, false) = false",
      "AND ((%s ->> 'latitude') IS NOT NULL OR %s <= %s))"
    ),
    ATLAS_MO_CACHE_SOURCE, json, json, half_diagonal_km, format(max_m / 1000)
  )
  uncached <- sprintf(
    "NOT EXISTS (SELECT 1 FROM observation_cache m WHERE m.source = '%s' AND m.source_observation_id = o.observation_id)",
    ATLAS_MO_CACHE_SOURCE
  )
  keep <- if (identical(unknown, "keep")) paste(placed, "OR", uncached) else placed
  sprintf("AND (o.source <> '%s' OR %s)", ATLAS_MO_SOURCE, keep)
}

#' Pull the eligible universe in pages, keeping every page as fetched.
atlas_pull_occurrences <- function(since = NULL, chunk_size = 20000,
                                   max_rows = Inf, host = atlas_sql_host(),
                                   dry_run = FALSE, quiet = FALSE) {
  if (isTRUE(dry_run)) {
    cat(atlas_occurrence_sql(0, chunk_size, since), "\n", sep = "")
    return(invisible(NULL))
  }

  stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
  raw_dir <- atlas_path("raw", "occurrences", stamp)
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

  chunks <- list()
  after_id <- 0
  total <- 0

  repeat {
    want <- if (is.finite(max_rows)) min(chunk_size, max_rows - total) else chunk_size
    if (want <= 0) break

    page <- atlas_parse_tsv(
      atlas_run_sql(atlas_occurrence_sql(after_id, want, since), host = host)
    )
    if (!nrow(page)) break

    n <- length(chunks) + 1L
    atlas_write_tsv_gz(page, file.path(raw_dir, sprintf("chunk-%04d.tsv.gz", n)))
    chunks[[n]] <- page
    total <- total + nrow(page)
    if (!quiet) {
      message(sprintf("  page %d: %d records (%d so far)", n, nrow(page), total))
    }

    after_id <- max(as.numeric(page$id))
    if (nrow(page) < want) break
  }

  occurrences <- if (length(chunks)) do.call(rbind, chunks) else atlas_empty_occurrences()
  atlas_check_occurrences(occurrences)
  occurrences <- atlas_canonicalise_occurrences(occurrences)
  atlas_write_json(atlas_name_merges(occurrences), atlas_name_merges_path())
  # Only a full pull can say a name is gone; read before this pull replaces
  # the previous one.
  if (is.null(since) && !is.finite(max_rows)) atlas_record_renames(occurrences, quiet = quiet)

  combined <- atlas_path("occurrences", sprintf("occurrences-%s.tsv.gz", stamp),
                         create = TRUE)
  atlas_write_tsv_gz(occurrences, combined)

  taxa <- atlas_taxon_fingerprints(occurrences)
  manifest <- list(
    stamp = stamp,
    pulled_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    since = if (is.null(since)) NA_character_ else since,
    host = host,
    records = nrow(occurrences),
    taxa = nrow(taxa),
    fingerprint = atlas_fingerprint(occurrences),
    file = basename(combined),
    sql = atlas_occurrence_sql(0, chunk_size, since)
  )
  atlas_write_json(manifest, atlas_path("occurrences", "latest.json", create = TRUE))
  atlas_write_json(taxa, atlas_path("occurrences", "taxa-latest.json", create = TRUE))

  if (!quiet) {
    message(sprintf("pulled %d records across %d taxa -> %s",
                    nrow(occurrences), nrow(taxa), combined))
  }
  invisible(manifest)
}

#' An empty pull, with the columns a real one has.
atlas_empty_occurrences <- function() {
  out <- as.data.frame(
    matrix(character(), nrow = 0, ncol = length(ATLAS_OCCURRENCE_FIELDS)),
    stringsAsFactors = FALSE
  )
  names(out) <- ATLAS_OCCURRENCE_FIELDS
  out
}

#' Refuse a pull that broke the eligibility rule on the way here.
atlas_check_occurrences <- function(df) {
  if (!nrow(df)) return(invisible(df))
  missing <- setdiff(ATLAS_OCCURRENCE_FIELDS, names(df))
  if (length(missing)) {
    stop("pull is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (anyNA(df$latitude) || anyNA(df$longitude)) {
    stop("pull contains a record without coordinates", call. = FALSE)
  }
  if (anyNA(df$scientific_name) || any(!nzchar(df$scientific_name))) {
    stop("pull contains a record without a name", call. = FALSE)
  }
  if (anyDuplicated(df$id)) {
    stop("pull contains duplicate record ids", call. = FALSE)
  }
  invisible(df)
}

atlas_write_tsv_gz <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- gzfile(path, open = "wt")
  on.exit(close(con), add = TRUE)
  utils::write.table(df, con, sep = "\t", row.names = FALSE, quote = FALSE, na = "")
  invisible(path)
}

atlas_write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(
    jsonlite::toJSON(x, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE,
                     na = "null"),
    path
  )
  invisible(path)
}

#' The manifest of the last pull, or NULL when nothing has been pulled.
atlas_read_manifest <- function() {
  path <- atlas_path("occurrences", "latest.json")
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

#' The records from the last pull (or a given file).
atlas_read_occurrences <- function(path = NULL) {
  if (is.null(path)) {
    manifest <- atlas_read_manifest()
    if (is.null(manifest)) {
      stop("nothing pulled yet: run ./atlas pull-occurrences", call. = FALSE)
    }
    path <- atlas_path("occurrences", manifest$file)
  }
  records <- utils::read.delim(
    gzfile(path), sep = "\t", quote = "", comment.char = "", na.strings = "",
    colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE
  )
  # Spellings of one taxon that differ only in punctuation are one taxon
  # (see R/names.R). Pulls made before that rule get it here.
  atlas_canonicalise_occurrences(records)
}

#' Print what the last pull holds.
atlas_status <- function() {
  manifest <- atlas_read_manifest()
  if (is.null(manifest)) {
    message("no pull yet. run: ./atlas pull-occurrences")
    return(invisible(NULL))
  }
  message("last pull:   ", manifest$pulled_at)
  message("records:     ", manifest$records)
  message("taxa:        ", manifest$taxa)
  message("fingerprint: ", substr(manifest$fingerprint, 1, 12))
  message("file:        ", atlas_path("occurrences", manifest$file))
  invisible(manifest)
}
