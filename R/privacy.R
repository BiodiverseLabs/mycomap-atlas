# Places a source hides stay hidden in what Atlas publishes (Steve,
# 2026-10-13): a record whose location is hidden or obscured where it came
# from, or whose source never told us, is left out of anything Atlas
# publishes record by record. Models still train on it as before: a map
# shows habitat, not where a record is.
#
# What is published record by record is the collection cells layer
# (public/cells.tsv.gz: records per taxon per 0.1 degree cell), in every
# release and the Zenodo bundle, and the only cells the API serves, so the web
# map too (atlas_served_cells). Everything else Atlas publishes is built from
# the maps, or counts by state, which read every record: a state is no finer
# than the source shows.
#
# Four kinds of record are left out of it, all read from .org:
#   - an iNaturalist record .org holds no cached iNaturalist answer for (no
#     cache row, or one with no stored answer), so whether iNaturalist
#     obscures it is unknown (the pull drops the ones it knows are obscured);
#   - a Mushroom Observer record .org holds no cached MO answer for (the
#     pull keeps it at .org's own coordinate);
#   - a Mushroom Observer record with no GPS point its observer shows, which
#     the pull places at its named place's centre: the place is public, the
#     observer's point is not, and a cell of our own would say more than MO
#     does;
#   - a Mushroom Observer record .org marks as deleted at the source
#     (ATLAS_SOURCE_DELETED). The pull keeps one that has a cached answer,
#     and models train on it (Steve: train, never list); a record its source
#     no longer holds is not listed record by record. It is listed as
#     deleted only when no other kind holds for it, so the other kinds'
#     counts mean what they meant before.
# On 2026-10-13 that was about 42 iNaturalist and 767 uncached MO records,
# and the MO records placed at a centre, of about 180,000.
#
# The list of them is made by a read-only query when the pull is made, kept
# private beside it (occurrences/privacy-latest.tsv.gz), and never put in a
# release, a job's inputs or a fingerprint: a list that changes as caches
# fill must never make a model stale.

ATLAS_INAT_SOURCE <- "iNaturalist"

atlas_privacy_path <- function() atlas_path("occurrences", "privacy-latest.tsv.gz")

#' The query for one window of record ids: the records the pull could take
#' (green, with coordinates, in North America) whose place their source
#' hides or may hide, or that their source has deleted, with which kind.
#' One line, with no double quote or percent sign, like every statement sent
#' to the SQL route.
atlas_privacy_sql <- function(from_id, to_id) {
  stopifnot(is.numeric(from_id), is.numeric(to_id), from_id >= 0, to_id > from_id)
  shown <- sprintf(
    "EXISTS (SELECT 1 FROM %s m WHERE m.source_observation_id = o.observation_id AND m.latitude IS NOT NULL AND m.longitude IS NOT NULL)",
    ATLAS_MO_POINTS
  )
  cached_mo <- sprintf("EXISTS (SELECT 1 FROM %s m WHERE m.source_observation_id = o.observation_id)",
                       ATLAS_MO_POINTS)
  # A cache row with no stored iNaturalist answer is no answer: whether
  # iNaturalist obscures the record is still unknown (four such rows on
  # 2026-11-19). Only the column's null flag is read, never its text.
  cached_inat <- paste("EXISTS (SELECT 1 FROM observation_cache c WHERE c.source = 'inat'",
                       "AND c.source_observation_id = o.observation_id AND c.api_response_json IS NOT NULL)")
  # Deleted at the source: MO only, as .org marks only MO today.
  deleted <- sprintf("(o.source = '%s' AND %s IS NOT NULL)", ATLAS_MO_SOURCE, ATLAS_SOURCE_DELETED)
  sql <- sprintf(paste(
    "SELECT o.source, o.observation_id,",
    "CASE WHEN o.source = '%s' THEN 'unknown' WHEN NOT %s THEN 'unknown' WHEN NOT %s THEN 'place' ELSE 'deleted' END AS privacy",
    "FROM observations o",
    "WHERE o.id > %d AND o.id <= %d",
    "AND 'yes' IN (%s) AND o.latitude IS NOT NULL AND o.longitude IS NOT NULL %s",
    "AND ((o.source = '%s' AND NOT %s) OR (o.source = '%s' AND NOT %s) OR %s)",
    "ORDER BY o.id"
  ), ATLAS_INAT_SOURCE, cached_mo, shown, as.integer(from_id), as.integer(to_id), atlas_status_columns(),
  atlas_place_clause(), ATLAS_INAT_SOURCE, cached_inat, ATLAS_MO_SOURCE, shown, deleted)
  atlas_one_line(sql)
}

#' Run the privacy query over every record id, a window at a time (each
#' well inside the route's 60 s cap), and keep the list privately. A failure
#' keeps the last good list, as the not-yet-validated counts do.
atlas_pull_privacy <- function(host = atlas_sql_host(), quiet = FALSE, window = 100000, run = atlas_run_sql) {
  top <- atlas_parse_tsv(run("SELECT max(id) AS top FROM observations", host = host))
  top <- suppressWarnings(as.numeric(top$top[[1]]))
  if (!length(top) || !is.finite(top)) stop("could not read the highest record id", call. = FALSE)
  rows <- list()
  for (from in seq(0, top, by = window)) {
    page <- atlas_parse_tsv(run(atlas_privacy_sql(from, from + window), host = host))
    if (nrow(page)) rows[[length(rows) + 1L]] <- page
  }
  flagged <- do.call(rbind, rows)
  if (is.null(flagged)) {
    flagged <- data.frame(source = character(), observation_id = character(), privacy = character())
  }
  missing <- setdiff(c("source", "observation_id", "privacy"), names(flagged))
  if (length(missing)) stop("privacy query is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  atlas_write_tsv_gz(flagged[, c("source", "observation_id", "privacy")], atlas_privacy_path())
  if (!isTRUE(quiet)) {
    counts <- table(paste(flagged$source, flagged$privacy))
    message("places hidden or unknown at their source: ", nrow(flagged), " records (",
            paste(names(counts), counts, sep = " ", collapse = ", "), ")")
  }
  invisible(flagged)
}

#' The records left out of what Atlas publishes record by record, as
#' "source:observation_id" keys, or NULL when no list has been made.
atlas_read_privacy <- function(path = atlas_privacy_path()) {
  if (!file.exists(path)) return(NULL)
  flagged <- utils::read.delim(gzfile(path, encoding = "UTF-8"), sep = "\t", quote = "", comment.char = "",
                               na.strings = "", colClasses = "character", check.names = FALSE,
                               stringsAsFactors = FALSE, encoding = "UTF-8")
  atlas_record_key(flagged$source, flagged$observation_id)
}
