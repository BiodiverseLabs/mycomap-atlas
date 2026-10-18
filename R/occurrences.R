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
#   - a species-level name, provisional temp codes included: the name of the
#     record's approved sequences, not the record's own name (R/labels.R).
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
  sql <- sprintf(
    "SELECT %s FROM observations o
     WHERE 'yes' IN (%s)
       AND o.latitude IS NOT NULL
       AND o.longitude IS NOT NULL
       %s
       %s
       %s
       %s
       %s
       AND o.id > %d
     ORDER BY o.id
     LIMIT %d",
    atlas_occurrence_columns_sql(),
    atlas_status_columns(), atlas_obscured_clause(), atlas_place_clause(),
    since_clause, atlas_mo_location_clause(), atlas_mycoportal_location_clause(),
    as.integer(after_id), as.integer(limit)
  )
  atlas_one_line(sql)
}

#' The SQL condition that leaves out an iNaturalist record whose coordinates
#' iNaturalist obscures or places no better than max_m.
#'
#' Only iNaturalist records are checked. .org's sources number their records
#' independently, so an MO, MyCoPortal or Sequences record can carry the same
#' number as an obscured iNaturalist observation; matched by number alone,
#' 20 MO records and 1 MyCoPortal record were left out of every pull
#' (2026-10-18).
#'
#' OFFSET 0 keeps the check a per-record index probe. Without it the planner
#' turns it into an anti join that rescans ~32,000 cached iNat answers for
#' every record, and a page ran past the route's 60 s cap (2026-10-08). The
#' records returned are the same.
atlas_obscured_clause <- function(max_m = ATLAS_MAX_ACCURACY_M) {
  sprintf(
    paste(
      "AND (o.source <> '%s' OR NOT EXISTS (SELECT 1 FROM observation_cache c",
      "WHERE c.source = 'inat' AND c.source_observation_id = o.observation_id",
      "AND (c.coordinates_obscured = true OR c.positional_accuracy > %d) OFFSET 0))"
    ),
    ATLAS_INAT_SOURCE, as.integer(max_m)
  )
}

#' The columns a pull selects: .org's, with an MO record's coordinate taken
#' from MO's own answer (atlas_mo_coordinate_sql).
atlas_occurrence_columns_sql <- function() {
  columns <- paste0("o.", ATLAS_OCCURRENCE_FIELDS)
  columns[ATLAS_OCCURRENCE_FIELDS == "latitude"] <- atlas_mo_coordinate_sql("latitude")
  columns[ATLAS_OCCURRENCE_FIELDS == "longitude"] <- atlas_mo_coordinate_sql("longitude")
  paste(columns, collapse = ", ")
}

#' .org's three validation slots, each blank where it has no verdict.
atlas_status_columns <- function() {
  paste(
    "coalesce(o.validation_status_1, '')",
    "coalesce(o.validation_status_2, '')",
    "coalesce(o.validation_status_3, '')",
    sep = ", "
  )
}

#' The place a record must be in, shared by the pull and the not-yet-validated
#' counts so the two can never cover different ground: North America, or a
#' Puerto Rico record with a blank country.
atlas_place_clause <- function() {
  countries <- paste(sprintf("'%s'", ATLAS_NA_COUNTRIES), collapse = ", ")
  sprintf("AND (o.country IN (%s) OR o.state = 'Puerto Rico')", countries)
}

#' The counts' place and name: atlas_place_clause and a species-level record
#' name. The pull does not filter on the record name: it names a record by its
#' approved sequences (R/labels.R) and applies the same species-level rule to
#' that name. A record with no verdict yet has no approved sequence to name it,
#' so the counts go by the record name.
atlas_place_and_name_clause <- function() {
  # The name trimmed as atlas_species_level trims it (spaces, tabs, line
  # breaks), so "Russula " is no more species-level here than in the pull.
  trimmed <- "btrim(o.scientific_name, ' ' || chr(9) || chr(10) || chr(13))"
  sprintf(
    "%s
       AND o.scientific_name IS NOT NULL
       AND %s NOT IN ('', 'Fungi', 'Unknown')
       AND strpos(%s, ' ') > 0
       AND right(lower(%s), 4) <> ' sp.'
       AND right(lower(%s), 3) <> ' sp'",
    atlas_place_clause(), trimmed, trimmed, trimmed, trimmed
  )
}

#' Per spelling, how many sequenced records no project has given a verdict:
#' no "yes" and no "no" in any of the three slots. Every source, and no
#' location-quality filter: these are counted, never modelled. One row per raw
#' spelling; atlas_unvalidated_table folds them into taxa.
atlas_unvalidated_sql <- function() {
  sql <- sprintf(
    "SELECT o.scientific_name AS taxon, count(*) AS not_yet_validated,
       count(*) FILTER (WHERE o.latitude IS NOT NULL AND o.longitude IS NOT NULL) AS with_coordinates
     FROM observations o
     WHERE coalesce(o.validation_status_1, '') NOT IN ('yes', 'no')
       AND coalesce(o.validation_status_2, '') NOT IN ('yes', 'no')
       AND coalesce(o.validation_status_3, '') NOT IN ('yes', 'no')
       %s
     GROUP BY o.scientific_name",
    atlas_place_and_name_clause()
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
  # A geocoded record is kept unless its point carries two or more labels.
  # Each observation has one mycoportal_data row, so that is the same as
  # "another record with a different label sits on this point", and it is
  # found in one pass: the points with several labels (a few hundred) are
  # gathered once and probed. The per-record form scanned every observation
  # for each geocoded record (no index on coordinates) and could run a page
  # past the route's 60 s cap; on prod (2026-10-12) both keep the same 1,352
  # of 4,352 geocoded green records. Only MyCoPortal records count: another
  # source's record can carry a MyCoPortal record's number (28 MO rows did
  # on 2026-10-18) and would lend its point that record's label.
  shared <- paste(
    "SELECT o2.latitude, o2.longitude FROM observations o2",
    "JOIN mycoportal_data p2 ON p2.observation_id = o2.observation_id",
    sprintf("WHERE o2.source IN (%s) AND o2.latitude IS NOT NULL AND o2.longitude IS NOT NULL", sources),
    "GROUP BY o2.latitude, o2.longitude HAVING count(DISTINCT coalesce(p2.locality, '')) >= 2"
  )
  placed <- sprintf(paste(
    "EXISTS (SELECT 1 FROM mycoportal_data p WHERE %s AND (",
    "(p.decimal_latitude IS NOT NULL AND coalesce(p.coordinate_uncertainty_in_meters, 0) <= %d)",
    "OR (p.decimal_latitude IS NULL AND (o.latitude, o.longitude) NOT IN (%s))))"
  ), answered, as.integer(max_m), shared)
  unanswered <- sprintf("NOT EXISTS (SELECT 1 FROM mycoportal_data p WHERE %s)", answered)
  keep <- if (identical(unknown, "keep")) paste(placed, "OR", unanswered) else placed
  sprintf("AND (o.source NOT IN (%s) OR %s)", sources, keep)
}

# How .org labels Mushroom Observer records, and the view on .org that places
# them (atlas.mo_points, created by .org's deploy/readonly-sql/atlas-install.sh).
ATLAS_MO_SOURCE <- "MO Observations"
ATLAS_MO_POINTS <- "atlas.mo_points"
# A Mushroom Observer record without a GPS point carries the centre of a named
# location (a park, a county). It is kept when every point of that location
# lies within this many metres of the centre: half the box's diagonal.
ATLAS_MO_MAX_LOCATION_M <- 5000
# What to do with an MO record whose MO answer .org has not cached: keep it
# ("keep") or leave it out ("drop").
ATLAS_MO_UNKNOWN <- "keep"

# What .org holds for an MO record is not the observer's GPS point: its index
# takes MO's GPS field and then overwrites it with the named location's
# centre, or a geocoded point near it (data inputs lane, 2026-10-07: of 333
# cached green MO rows, 47 sat outside their own location box, and only 4 of
# the 12 with a visible GPS point held that point). So Atlas takes an MO
# record's coordinate from .org's cache of MO's own answer, not from .org's
# row: the GPS point when the observer shows one, else the centre of a named
# location small enough to model. A hidden GPS point is no GPS point:
# anonymous reads of MO return none, only the box.
#
# Atlas reads those answers through a view, never the cached JSON itself
# (which holds the observer's name and any GPS point they hid; Steve,
# 2026-10-12): per cached MO observation, its GPS point only when the observer
# shows it (latitude and longitude, null otherwise) and its named location's
# edges (latitude_north, latitude_south, longitude_east, longitude_west).

#' The pieces of an MO record's place the rules below read, as SQL on its row
#' m of ATLAS_MO_POINTS.
atlas_mo_answer_sql <- function(max_m = ATLAS_MO_MAX_LOCATION_M) {
  edge <- function(side) sprintf("m.%s", side)
  half_diagonal_km <- sprintf(
    "sqrt(power((%s - %s) * 111.2, 2) + power((%s - %s) * 111.2 * cos(radians((%s + %s) / 2)), 2)) / 2",
    edge("latitude_north"), edge("latitude_south"),
    edge("longitude_east"), edge("longitude_west"),
    edge("latitude_north"), edge("latitude_south")
  )
  list(
    # A GPS point the observer shows: the view has none for a hidden one.
    gps = "(m.latitude IS NOT NULL AND m.longitude IS NOT NULL)",
    # A named location whose every point is within max_m of its centre.
    small = sprintf("(%s <= %s)", half_diagonal_km, format(max_m / 1000)),
    point = list(latitude = "m.latitude", longitude = "m.longitude"),
    centre = list(latitude = sprintf("(%s + %s) / 2", edge("latitude_north"), edge("latitude_south")),
                  longitude = sprintf("(%s + %s) / 2", edge("longitude_east"), edge("longitude_west")))
  )
}

#' The SQL condition that keeps only Mushroom Observer records placed well
#' enough to model.
#'
#' ATLAS_MO_POINTS holds a row per MO observation .org has cached MO's answer
#' for: latitude and longitude, the GPS point the observer shows (null when
#' there is none or it is hidden), and the named place's north, south, east
#' and west edges. A record passes when it has a GPS point the observer shows,
#' or when half its location box's diagonal is within max_m, hidden GPS or not.
#' Records of other sources are untouched. One line, with no double quote or
#' percent sign, like every statement sent to the SQL route.
atlas_mo_location_clause <- function(max_m = ATLAS_MO_MAX_LOCATION_M,
                                     unknown = ATLAS_MO_UNKNOWN) {
  unknown <- match.arg(unknown, c("keep", "drop"))
  answer <- atlas_mo_answer_sql(max_m)
  placed <- sprintf(
    paste(
      "EXISTS (SELECT 1 FROM %s m WHERE m.source_observation_id = o.observation_id",
      "AND (%s OR %s))"
    ),
    ATLAS_MO_POINTS, answer$gps, answer$small
  )
  uncached <- sprintf(
    "NOT EXISTS (SELECT 1 FROM %s m WHERE m.source_observation_id = o.observation_id)",
    ATLAS_MO_POINTS
  )
  keep <- if (identical(unknown, "keep")) paste(placed, "OR", uncached) else placed
  sprintf("AND (o.source <> '%s' OR %s)", ATLAS_MO_SOURCE, keep)
}

#' An MO record's coordinate, as a column of the pull: the shown GPS point,
#' else the centre of its small named location, from ATLAS_MO_POINTS. Any other record, and an MO record with no cached answer, keeps
#' .org's own coordinate. (The location clause has already dropped an MO
#' record with neither.)
atlas_mo_coordinate_sql <- function(axis = c("latitude", "longitude"),
                                    max_m = ATLAS_MO_MAX_LOCATION_M) {
  axis <- match.arg(axis)
  answer <- atlas_mo_answer_sql(max_m)
  sprintf(
    paste(
      "CASE WHEN o.source = '%s' THEN coalesce((SELECT CASE WHEN %s THEN %s WHEN %s THEN %s END",
      "FROM %s m WHERE m.source_observation_id = o.observation_id",
      "LIMIT 1), o.%s) ELSE o.%s END AS %s"
    ),
    ATLAS_MO_SOURCE, answer$gps, answer$point[[axis]], answer$small, answer$centre[[axis]],
    ATLAS_MO_POINTS, axis, axis, axis
  )
}

#' Pull the eligible universe in pages, keeping every page as fetched.
atlas_pull_occurrences <- function(since = NULL, chunk_size = 10000,
                                   max_rows = Inf, host = atlas_sql_host(),
                                   dry_run = FALSE, quiet = FALSE) {
  if (isTRUE(dry_run)) {
    cat(atlas_occurrence_sql(0, chunk_size, since), "\n", sep = "")
    cat(atlas_unvalidated_sql(), "\n", sep = "")
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

    ids <- as.numeric(page$id)
    names_page <- atlas_parse_tsv(
      atlas_run_sql(atlas_sequence_names_sql(min(ids), max(ids)), host = host)
    )
    if (!nrow(names_page)) names_page <- data.frame(id = character(), species_name = character())

    n <- length(chunks) + 1L
    atlas_write_tsv_gz(page, file.path(raw_dir, sprintf("chunk-%04d.tsv.gz", n)))
    atlas_write_tsv_gz(names_page, file.path(raw_dir, sprintf("names-%04d.tsv.gz", n)))
    # Each record's first green validation date, from a query of its own so
    # the pull's rows and fingerprints stay as they were (R/firstgreen.R).
    slots <- atlas_parse_tsv(atlas_run_sql(atlas_first_green_sql(min(ids), max(ids)), host = host))
    chunks[[n]] <- atlas_label_occurrences(atlas_add_first_green(page, slots), names_page)
    total <- total + nrow(page)
    if (!quiet) {
      message(sprintf("  page %d: %d records (%d so far)", n, nrow(page), total))
    }

    after_id <- max(ids)
    if (nrow(page) < want) break
  }

  labelled <- if (length(chunks)) do.call(rbind, chunks) else atlas_label_occurrences(
    atlas_empty_occurrences(), data.frame(id = character(), species_name = character()))
  audit <- atlas_label_audit(labelled)
  atlas_write_json(audit, atlas_label_audit_path())
  occurrences <- labelled[atlas_species_level(labelled$scientific_name), , drop = FALSE]
  rownames(occurrences) <- NULL
  atlas_check_occurrences(occurrences)
  occurrences <- atlas_canonicalise_occurrences(occurrences)
  # The box's drop list (R/exclude.R): rows Atlas leaves out of every pull,
  # before anything is fingerprinted, merged or written.
  excluded <- atlas_apply_exclusions(occurrences)
  occurrences <- excluded$kept
  atlas_write_json(atlas_name_merges(occurrences), atlas_name_merges_path())
  # Only a full pull can say a name is gone; read before this pull replaces
  # the previous one.
  if (is.null(since) && !is.finite(max_rows)) atlas_record_renames(occurrences, quiet = quiet)

  combined <- atlas_path("occurrences", sprintf("occurrences-%s.tsv.gz", stamp),
                         create = TRUE)
  atlas_write_tsv_gz(occurrences, combined)

  taxa <- atlas_add_sites(atlas_taxon_fingerprints(occurrences), occurrences)
  manifest <- list(
    stamp = stamp,
    pulled_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    since = if (is.null(since)) NA_character_ else since,
    host = host,
    records = nrow(occurrences),
    taxa = nrow(taxa),
    names = list(rule = audit$rule, pulled = audit$pulled,
                 by_status = stats::setNames(as.list(audit$by_status$records),
                                             audit$by_status$status)),
    fingerprint = atlas_fingerprint(occurrences),
    # The drop list applied: its hash and how many rows it removed.
    exclusions = excluded$info,
    file = basename(combined),
    # Private, like the rest of this manifest: atlas_release_pull_summary
    # publishes none of it.
    first_green = list(
      records_with_date = sum(!is.na(occurrences[[ATLAS_FIRST_GREEN_FIELD]])),
      latest = if (any(!is.na(occurrences[[ATLAS_FIRST_GREEN_FIELD]]))) max(occurrences[[ATLAS_FIRST_GREEN_FIELD]], na.rm = TRUE)
    ),
    sql = atlas_occurrence_sql(0, chunk_size, since),
    first_green_sql = atlas_first_green_sql(0, 1),
    names_sql = atlas_sequence_names_sql(0, chunk_size)
  )
  atlas_write_json(manifest, atlas_path("occurrences", "latest.json", create = TRUE))
  atlas_write_json(taxa, atlas_path("occurrences", "taxa-latest.json", create = TRUE))
  # After the pull's own files, and outside its fingerprint: a count that moves
  # every night must never make a model stale, and a failed count must never
  # fail the pull. The last good counts stay until the next one succeeds.
  tryCatch(atlas_pull_unvalidated(host = host, quiet = quiet), error = function(e) {
    warning("not-yet-validated counts not refreshed: ", conditionMessage(e), call. = FALSE)
  })
  # Likewise the private list of records whose place their source hides
  # (R/privacy.R): kept out of the published collection cells.
  tryCatch(atlas_pull_privacy(host = host, quiet = quiet), error = function(e) {
    warning("hidden-place list not refreshed: ", conditionMessage(e), call. = FALSE)
  })

  if (!quiet) {
    message(sprintf("pulled %d records across %d taxa -> %s",
                    nrow(occurrences), nrow(taxa), combined))
    renamed <- sum(labelled$name_status %in% c(ATLAS_LABEL_OTHER_SPECIES, ATLAS_LABEL_OTHER_GENUS))
    left_out <- nrow(labelled) - nrow(occurrences)
    message(sprintf("  %d records named by their sequences, not their record name; %d left out; audit: %s",
                    renamed, left_out, atlas_label_audit_path()))
  }
  invisible(manifest)
}

#' An empty pull, with the columns a real one has.
atlas_empty_occurrences <- function() {
  fields <- c(ATLAS_OCCURRENCE_FIELDS, ATLAS_FIRST_GREEN_FIELD)
  out <- as.data.frame(
    matrix(character(), nrow = 0, ncol = length(fields)),
    stringsAsFactors = FALSE
  )
  names(out) <- fields
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
