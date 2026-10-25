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

#' Per sequence name, how many records no validation project has given a
#' verdict, and how many of them have coordinates: .org's view
#' atlas.unvalidated_counts (.org deploy/readonly-sql/atlas-install.sh). It
#' reads the .com mirror (validation_project_records), where the backlog is:
#' .org's observations now holds validated records only, so a count from it
#' read near zero (335 rows against about 74,000, 2026-10-25). A record counts
#' with one clean approved sequence name, under that name, in North America
#' as the pull means it (atlas_place_clause). The view is refreshed nightly
#' before the pull, since counting takes about 45 s; atlas_unvalidated_table
#' folds the names into the pull's taxa by atlas_name_key, so a name of no
#' modelled taxon (a genus, a code) is dropped there.
atlas_unvalidated_sql <- function() {
  "SELECT taxon, not_yet_validated, with_coordinates FROM atlas.unvalidated_counts"
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
# ("keep") or leave it out ("drop"). Left out (Steve, 2026-10-18): since the
# MO cache backfill, an uncached record is either new (cached by the next
# night, so it waits a day) or deleted on MO, and .org's own point for either
# is one this file does not trust (below). A record deleted on MO with no
# cached answer is left out under "keep" too: its answer can never come.
# One deleted on MO WITH a cached answer is kept, on that answer.
ATLAS_MO_UNKNOWN <- "drop"

# .org's marker for a record its source platform has deleted (data inputs
# lane, 2026-10-18): when .org learned it, NULL when not known deleted. Set
# only for MO today. atlas_ro reads it by its own column grant
# (deploy/readonly-sql/atlas-install.sh on .org).
ATLAS_SOURCE_DELETED <- "o.source_deleted_at"

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
    "(NOT EXISTS (SELECT 1 FROM %s m WHERE m.source_observation_id = o.observation_id) AND %s IS NULL)",
    ATLAS_MO_POINTS, ATLAS_SOURCE_DELETED
  )
  # "drop" needs no marker: every uncached record is left out already.
  keep <- if (identical(unknown, "keep")) paste(placed, "OR", uncached) else placed
  sprintf("AND (o.source <> '%s' OR %s)", ATLAS_MO_SOURCE, keep)
}

#' How many eligible MO records a pull leaves out, and why, among records
#' with ids in (after_id, through_id] (through_id NULL: every id above
#' after_id). The pull's own filters but its MO clause:
#'   deleted_at_source_uncached  deleted on MO, no cached answer: always left out
#'   uncached                    no cached answer, not known deleted: left out
#'                               under ATLAS_MO_UNKNOWN "drop", kept under "keep"
#'   too_coarse                  cached, but no shown GPS point and a named
#'                               location too big to model: always left out
atlas_mo_left_out_sql <- function(after_id = 0, through_id = NULL, since = NULL,
                                  max_m = ATLAS_MO_MAX_LOCATION_M) {
  answer <- atlas_mo_answer_sql(max_m)
  since_clause <- if (is.null(since)) "" else sprintf("AND o.updated_at >= date '%s'", since)
  through <- if (is.null(through_id)) "" else sprintf("AND o.id <= %d", as.integer(through_id))
  sql <- sprintf(
    "SELECT count(*) FILTER (WHERE NOT x.cached AND x.deleted) AS deleted_at_source_uncached,
       count(*) FILTER (WHERE NOT x.cached AND NOT x.deleted) AS uncached,
       count(*) FILTER (WHERE x.cached AND NOT x.placed) AS too_coarse
     FROM (SELECT
       EXISTS (SELECT 1 FROM %s m WHERE m.source_observation_id = o.observation_id) AS cached,
       EXISTS (SELECT 1 FROM %s m WHERE m.source_observation_id = o.observation_id AND (%s OR %s)) AS placed,
       %s IS NOT NULL AS deleted
     FROM observations o
     WHERE o.source = '%s'
       AND 'yes' IN (%s)
       AND o.latitude IS NOT NULL
       AND o.longitude IS NOT NULL
       %s
       %s
       AND o.id > %d
       %s) x",
    ATLAS_MO_POINTS, ATLAS_MO_POINTS, answer$gps, answer$small, ATLAS_SOURCE_DELETED, ATLAS_MO_SOURCE,
    atlas_status_columns(), atlas_place_clause(), since_clause, as.integer(after_id), through
  )
  atlas_one_line(sql)
}

#' The MO records a pull left out, summed over its pages' id windows (the
#' last one open, when the pull read to the end), for its manifest. A count
#' that fails never fails the pull: the manifest says why it has none.
atlas_mo_left_out <- function(bounds, complete, since = NULL, host = atlas_sql_host(),
                              unknown = ATLAS_MO_UNKNOWN) {
  windows <- if (length(bounds)) {
    lapply(seq_along(bounds), function(i) c(if (i == 1L) 0 else bounds[[i - 1L]], bounds[[i]]))
  } else {
    list()
  }
  if (isTRUE(complete)) windows <- c(windows, list(c(if (length(bounds)) utils::tail(bounds, 1) else 0, NA)))
  tryCatch({
    totals <- c(deleted_at_source_uncached = 0, uncached = 0, too_coarse = 0)
    for (w in windows) {
      row <- atlas_parse_tsv(atlas_run_sql(atlas_mo_left_out_sql(w[[1]], if (is.na(w[[2]])) NULL else w[[2]], since),
                                           host = host))
      for (k in names(totals)) if (nrow(row) && !is.null(row[[k]])) totals[[k]] <- totals[[k]] + as.numeric(row[[k]][[1]])
    }
    drop <- identical(unknown, "drop")
    list(unknown = unknown,
         deleted_at_source_uncached = as.integer(totals[["deleted_at_source_uncached"]]),
         uncached = if (drop) as.integer(totals[["uncached"]]) else 0L,
         uncached_kept = if (drop) 0L else as.integer(totals[["uncached"]]),
         too_coarse = as.integer(totals[["too_coarse"]]),
         complete = isTRUE(complete))
  }, error = function(e) {
    warning("MO records left out not counted: ", conditionMessage(e), call. = FALSE)
    list(unknown = unknown, error = conditionMessage(e))
  })
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
  # Each page's last id, so the MO records left out can be counted window by
  # window, as the pull itself pages; complete when it read to the end.
  bounds <- numeric()
  complete <- FALSE

  repeat {
    want <- if (is.finite(max_rows)) min(chunk_size, max_rows - total) else chunk_size
    if (want <= 0) break

    page <- atlas_parse_tsv(
      atlas_run_sql(atlas_occurrence_sql(after_id, want, since), host = host)
    )
    if (!nrow(page)) {
      complete <- TRUE
      break
    }

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
    bounds <- c(bounds, after_id)
    if (nrow(page) < want) {
      complete <- TRUE
      break
    }
  }
  mo_left_out <- atlas_mo_left_out(bounds, complete, since, host = host)

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
    # MO records left out by place, and why (atlas_mo_left_out).
    mo_left_out = mo_left_out,
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
  # And .org's name-change log (R/namechanges.R), read from its cursor: its
  # renames go into renames.json ahead of the guessed ones. Neither step can
  # fail the pull, and only a full pull can say which names are gone.
  tryCatch(atlas_pull_name_changes(host = host, quiet = quiet), error = function(e) {
    warning("name-change log not kept: ", conditionMessage(e), call. = FALSE)
  })
  if (is.null(since) && !is.finite(max_rows)) {
    atlas_record_org_renames(occurrences, quiet = quiet)
  }
  # The pull's QA report (R/qa.R), after its privacy list: one that cannot be
  # made is written as a stop of its own, so it never passes unseen. GBIF is
  # asked for new names' kingdoms only where ATLAS_QA_KINGDOM_LOOKUP=gbif
  # (the box); elsewhere the cache alone answers.
  tryCatch({
    gbif <- identical(Sys.getenv("ATLAS_QA_KINGDOM_LOOKUP"), "gbif")
    number <- function(name, unset) {
      value <- suppressWarnings(as.numeric(Sys.getenv(name, unset = "")))
      if (length(value) == 1L && is.finite(value) && value >= 0) value else unset
    }
    kingdoms <- atlas_name_kingdoms(
      occurrences$scientific_name, lookup = if (gbif) atlas_gbif_kingdom else function(name) NA_character_,
      max_new = if (gbif) as.integer(number("ATLAS_QA_KINGDOM_CAP", ATLAS_QA_KINGDOM_CAP)) else 0L,
      pace_seconds = number("ATLAS_QA_KINGDOM_PACE_MS", 1000 * ATLAS_QA_KINGDOM_PACE_SECONDS) / 1000
    )
    atlas_pull_qa(occurrences, manifest, audit, kingdoms = kingdoms, quiet = quiet)
  }, error = function(e) {
    atlas_write_json(list(pull = manifest$stamp, stops = list("qa_failed"),
                          checks = list(qa_failed = list(stop = TRUE, why = paste("the QA report could not be made:",
                                                                                  conditionMessage(e))))),
                     atlas_qa_path())
    warning("pull QA not made: ", conditionMessage(e), call. = FALSE)
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
