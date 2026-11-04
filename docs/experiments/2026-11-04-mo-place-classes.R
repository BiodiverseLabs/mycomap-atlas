# QA place_centres analysis (coordinator's request, 2026-11-04, for Steve's
# threshold decision): why MO's place-centre share went from 38.5% in the
# frozen pull to 41.0% in the dry pull, what limit real values support, and
# what these records do to the fits.
#
# READ-ONLY. Run on the Atlas box, inside the Atlas image (91e7b5e), with both
# data directories mounted read-only. It reads:
#   FROZEN_PULL     /data/occurrences/occurrences-20261012T051017Z-x73b85b36.tsv.gz
#   FROZEN_PRIVACY  /data/occurrences/privacy-latest.tsv.gz (the list dated 10/13, as in E16)
#   DRY_PULL        the dry pull's combined file (the "file" named by its occurrences/latest.json)
#   DRY_PRIVACY     /dry/occurrences/privacy-latest.tsv.gz
#   MODELLED        modelled-taxa-fa1b4198.txt (taxon names only, as in E16)
# and asks .org, through the box's read-only route (atlas_ro), about the
# departed records, the size of MO's location boxes, and what its caches hold
# for every record the two privacy lists disagree on. It writes ONE file,
# OUT: counts, shares, quantiles and distances. No record, place, coordinate,
# taxon name or record id. Nothing else is written anywhere.
#
#   docker run --rm --memory 800m -v <data>:/data:ro -v <dry>:/dry:ro \
#     -v <dir with this script>:/work -e FROZEN_PULL=... -e FROZEN_PRIVACY=... \
#     -e DRY_PULL=... -e DRY_PRIVACY=... -e MODELLED=/work/modelled-taxa-fa1b4198.txt \
#     -e OUT=/work/qa-place.json <image> Rscript /work/qa_place_centres.R

suppressPackageStartupMessages(attach(asNamespace("mycomapatlas"), name = "atlas", warn.conflicts = FALSE))
env <- function(name) {
  value <- Sys.getenv(name)
  if (!nzchar(value)) stop(name, " is not set", call. = FALSE)
  value
}
read_list <- function(path) {
  utils::read.delim(gzfile(path, encoding = "UTF-8"), sep = "\t", quote = "", comment.char = "",
                    na.strings = "", colClasses = "character", stringsAsFactors = FALSE)
}
q <- function(x, d = 2) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NULL)
  as.list(stats::setNames(round(stats::quantile(x, c(0, 0.1, 0.25, 0.5, 0.75, 0.9, 1), names = FALSE), d),
                          c("min", "p10", "p25", "median", "p75", "p90", "max")))
}
key <- function(x) atlas_record_key(x$source, x$observation_id)
counts <- function(x) as.list(table(x))
share <- function(k, n) if (n) round(k / n, 4) else NA_real_
MO <- ATLAS_MO_SOURCE

frozen <- atlas_read_occurrences(env("FROZEN_PULL"))
dry <- atlas_read_occurrences(env("DRY_PULL"))
frozen_list <- read_list(env("FROZEN_PRIVACY"))
dry_list <- read_list(env("DRY_PRIVACY"))
modelled <- trimws(readLines(env("MODELLED"), warn = FALSE))
modelled <- modelled[nzchar(modelled)]

# A record's class on its own pull's list: place, unknown, or gps (MO and not
# on the list: a point the observer shows).
class_of <- function(pull, list) {
  listed <- list$privacy[match(key(pull), atlas_record_key(list$source, list$observation_id))]
  ifelse(is.na(listed), "gps", listed)
}
frozen_mo <- frozen[frozen$source == MO, , drop = FALSE]
dry_mo <- dry[dry$source == MO, , drop = FALSE]
frozen_mo$class <- class_of(frozen_mo, frozen_list)
dry_mo$class <- class_of(dry_mo, dry_list)

out <- list(
  frozen = list(records = nrow(frozen), mo = nrow(frozen_mo), classes = counts(frozen_mo$class),
                place_share_of_mo = share(sum(frozen_mo$class == "place"), nrow(frozen_mo)),
                place_share_of_cached_mo = share(sum(frozen_mo$class == "place"), sum(frozen_mo$class != "unknown")),
                place_share_of_pull = share(sum(frozen_mo$class == "place"), nrow(frozen))),
  dry = list(records = nrow(dry), mo = nrow(dry_mo), classes = counts(dry_mo$class),
             place_share_of_mo = share(sum(dry_mo$class == "place"), nrow(dry_mo)),
             place_share_of_cached_mo = share(sum(dry_mo$class == "place"), sum(dry_mo$class != "unknown")),
             place_share_of_pull = share(sum(dry_mo$class == "place"), nrow(dry)))
)

# 1. The rise: every MO record's class in the frozen pull against the dry pull.
all_keys <- union(key(frozen_mo), key(dry_mo))
was <- frozen_mo$class[match(all_keys, key(frozen_mo))]
now <- dry_mo$class[match(all_keys, key(dry_mo))]
was[is.na(was)] <- "not_in_frozen"
now[is.na(now)] <- "not_in_dry"
out$class_changes <- as.data.frame(table(frozen = was, dry = now), stringsAsFactors = FALSE)
out$class_changes <- out$class_changes[out$class_changes$Freq > 0, ]

# The same in share points: the frozen share, with each group removed in turn.
in_both <- all_keys[was != "not_in_frozen" & now != "not_in_dry"]
stayed_place <- sum(was == "place" & now == "place")
out$rise_terms <- list(
  place_frozen = sum(was == "place"), place_dry = sum(now == "place"),
  place_stayed = stayed_place,
  place_new = sum(was == "not_in_frozen" & now == "place"),
  place_from_unknown = sum(was == "unknown" & now == "place"),
  place_from_gps = sum(was == "gps" & now == "place"),
  place_to_gps = sum(was == "place" & now == "gps"),
  place_to_unknown = sum(was == "place" & now == "unknown"),
  place_departed = sum(was == "place" & now == "not_in_dry"),
  mo_new = sum(was == "not_in_frozen"), mo_departed = sum(now == "not_in_dry"),
  mo_in_both = length(in_both)
)

# How far a record that stayed moved between the pulls, by its class change.
moved_km <- function(from, to) {
  a <- frozen_mo[match(in_both, key(frozen_mo)), , drop = FALSE]
  b <- dry_mo[match(in_both, key(dry_mo)), , drop = FALSE]
  use <- a$class == from & b$class == to
  if (!any(use)) return(list(records = 0L))
  rad <- pi / 180
  lat1 <- as.numeric(a$latitude[use]) * rad
  lat2 <- as.numeric(b$latitude[use]) * rad
  lon1 <- as.numeric(a$longitude[use]) * rad
  lon2 <- as.numeric(b$longitude[use]) * rad
  h <- sin((lat2 - lat1) / 2)^2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2)^2
  km <- 2 * 6371 * asin(pmin(1, sqrt(h)))
  list(records = sum(use), moved = sum(km > 0.001, na.rm = TRUE), km = q(km),
       over_5_km = sum(km > 5, na.rm = TRUE), over_25_km = sum(km > 25, na.rm = TRUE))
}
out$moved_between_pulls <- list(
  unknown_to_place = moved_km("unknown", "place"), unknown_to_gps = moved_km("unknown", "gps"),
  gps_to_place = moved_km("gps", "place"), place_to_gps = moved_km("place", "gps"),
  place_to_place = moved_km("place", "place"), gps_to_gps = moved_km("gps", "gps")
)

# New MO records: validated since the frozen pull, or older and newly eligible.
new_mo <- dry_mo[!key(dry_mo) %in% key(frozen_mo), , drop = FALSE]
first_green <- function(x) as.Date(substr(as.character(x[[ATLAS_FIRST_GREEN_FIELD]]), 1, 10))
new_mo$since <- ifelse(!is.na(first_green(new_mo)) & first_green(new_mo) >= as.Date("2026-10-12"),
                       "first_green_since_10_12", "first_green_before_10_12")
out$new_mo <- as.data.frame(table(when = new_mo$since, class = new_mo$class), stringsAsFactors = FALSE)

# Why a record left: asked of .org today, for MO and Sequences. Counts only.
why_left <- function(gone) {
  if (!nrow(gone)) return(list(records = 0L))
  ids <- sort(as.numeric(gone$id))
  named <- character()
  answers <- list()
  # Windows of at most 5,000 ids, which take seconds, so ids scattered across
  # the table never make one names query span it (atlas_ro's 60 s limit).
  for (chunk in split(ids, floor((ids - min(ids)) / 5000))) {
    page <- atlas_parse_tsv(atlas_run_sql(atlas_sequence_names_sql(min(chunk), max(chunk))))
    if (nrow(page)) named <- c(named, as.character(page$id))
    id_list <- paste(as.integer(chunk), collapse = ",")
    sql <- atlas_one_line(sprintf(
      "SELECT o.id, 'yes' IN (%s) AS green, o.latitude IS NOT NULL AS has_point, %s IS NOT NULL AS deleted,
         EXISTS (SELECT 1 FROM %s m WHERE o.source = '%s' AND m.source_observation_id = o.observation_id) AS cached
       FROM observations o WHERE o.id IN (%s)",
      atlas_status_columns(), ATLAS_SOURCE_DELETED, ATLAS_MO_POINTS, MO, id_list))
    answers[[length(answers) + 1L]] <- atlas_parse_tsv(atlas_run_sql(sql))
  }
  a <- do.call(rbind, answers)
  id <- as.character(gone$id)
  row <- a[match(id, as.character(a$id)), , drop = FALSE]
  yes <- function(x) !is.na(x) & x %in% c("t", "true", "TRUE")
  reason <- ifelse(is.na(row$id), "no longer on org",
            ifelse(!yes(row$green), "no longer green",
            ifelse(yes(row$deleted), "deleted at source",
            ifelse(!id %in% named, "no clean named sequence",
            ifelse(gone$source == MO & !yes(row$cached), "no cached MO answer",
                   "still named and green: place rule, region or name level")))))
  list(records = nrow(gone), reasons = counts(reason))
}
frozen_only <- frozen[!key(frozen) %in% key(dry), , drop = FALSE]
out$departed <- tryCatch(list(
  mo = c(why_left(frozen_only[frozen_only$source == MO, , drop = FALSE]),
         list(by_frozen_class = counts(frozen_mo$class[!key(frozen_mo) %in% key(dry_mo)]))),
  sequences = why_left(frozen_only[frozen_only$source == "Sequences", , drop = FALSE])
), error = function(e) list(error = conditionMessage(e)))

# Every source, frozen against dry.
out$sources <- lapply(sort(union(unique(frozen$source), unique(dry$source))), function(s) {
  a <- frozen[frozen$source == s, , drop = FALSE]
  b <- dry[dry$source == s, , drop = FALSE]
  list(source = s, frozen = nrow(a), dry = nrow(b), new = sum(!key(b) %in% key(a)), departed = sum(!key(a) %in% key(b)),
       one_record_as_share = share(1, nrow(b)))
})

# 2. Calibration, from the dry pull: MO's share as the pull would have read on
# each past day, by first validation and today's class. Today's classes and
# today's records, so it shows how much a day's validations can move the share,
# not what past pulls held.
dates <- first_green(dry_mo)
use <- !is.na(dates)
days <- sort(unique(dates[use]))
by_day <- data.frame(day = days,
                     mo = as.integer(table(factor(dates[use], levels = days))),
                     place = as.integer(table(factor(dates[use & dry_mo$class == "place"], levels = days))))
by_day$cum_mo <- cumsum(by_day$mo)
by_day$cum_place <- cumsum(by_day$place)
by_day$share <- by_day$cum_place / by_day$cum_mo
months <- format(by_day$day, "%Y-%m")
last_of <- !duplicated(months, fromLast = TRUE)
month_rows <- by_day[last_of & by_day$day >= as.Date("2025-10-01"), , drop = FALSE]
out$share_by_month <- data.frame(month = format(month_rows$day, "%Y-%m"), mo = month_rows$cum_mo,
                                 place = month_rows$cum_place, share = round(month_rows$share, 4))
settled <- by_day$cum_mo >= 2000
step <- c(NA_real_, diff(by_day$share))
week <- vapply(seq_len(nrow(by_day)), function(i) {
  earlier <- which(by_day$day <= by_day$day[[i]] - 7)
  if (length(earlier)) by_day$share[[i]] - by_day$share[[max(earlier)]] else NA_real_
}, 0)
out$share_steps <- list(
  from_cum_mo = 2000, days = sum(settled),
  share_range = q(by_day$share[settled], 4),
  largest_one_day_rise_points = round(100 * max(step[settled], na.rm = TRUE), 2),
  largest_one_day_fall_points = round(100 * min(step[settled], na.rm = TRUE), 2),
  one_day_rises_over_2_points = sum(step[settled] > 0.02, na.rm = TRUE),
  largest_7_day_rise_points = round(100 * max(week[settled], na.rm = TRUE), 2),
  one_day_abs_points = q(100 * abs(step[settled]), 3),
  largest_day_mo_records = max(by_day$mo[settled])
)

# 3. The science: what place records do to the frozen pull (the v1 fits) and
# the dry pull. A site is a 5 km cell, as the release counts on the draft grid.
effect <- function(pull, mo, label) {
  place_keys <- key(mo)[mo$class == "place"]
  is_place <- key(pull) %in% place_keys
  all_points <- atlas_occurrence_points(pull, "draft")
  rest_points <- atlas_occurrence_points(pull[!is_place, , drop = FALSE], "draft")
  place_points <- atlas_occurrence_points(pull[is_place, , drop = FALSE], "draft")
  sites <- function(points) tapply(points$cell, points$scientific_name, function(x) length(unique(x)))
  every <- sites(all_points)
  rest <- sites(rest_points)
  without <- as.numeric(rest[names(every)])
  without[is.na(without)] <- 0
  names(without) <- names(every)
  in_set <- names(every) %in% modelled
  lost <- every - without
  crossed <- function(limit, keep = rep(TRUE, length(every))) sum(keep & every >= limit & without < limit)
  affected <- lost > 0
  cell_records <- as.numeric(table(place_points$cell))
  cell_taxa <- as.numeric(tapply(place_points$scientific_name, place_points$cell, function(x) length(unique(x))))
  site_share <- share(sum(lost), sum(every))
  list(
    pull = label,
    taxa_with_a_place_record = length(unique(pull$scientific_name[is_place])),
    taxa = length(every), taxa_with_a_site_only_from_place = sum(affected),
    sites_only_from_place = sum(lost), of_sites = sum(every), share_of_sites = site_share,
    taxa_only_at_place_sites = sum(without == 0),
    taxa_crossing_below = list(`3` = crossed(3), `5` = crossed(5), `20` = crossed(20), `50` = crossed(50)),
    modelled_taxa = list(
      taxa = sum(in_set), with_a_site_only_from_place = sum(affected & in_set),
      share_of_their_sites = share(sum(lost[in_set]), sum(every[in_set])),
      their_lost_share = q((lost / every)[affected & in_set], 3),
      half_or_more_of_sites_only_from_place = sum(in_set & (lost / every) >= 0.5),
      crossing_below = list(`3` = crossed(3, in_set), `5` = crossed(5, in_set), `20` = crossed(20, in_set),
                            `50` = crossed(50, in_set))
    ),
    pile_up = list(place_cells = length(cell_records), records_per_cell = q(cell_records, 1),
                   taxa_per_cell = q(cell_taxa, 1), cells_with_20_plus_records = sum(cell_records >= 20),
                   records_in_those_cells = sum(cell_records[cell_records >= 20]))
  )
}
out$effect <- list(frozen = effect(frozen, frozen_mo, "x73b85b36"), dry = effect(dry, dry_mo, "dry 20261104T215205Z"))

# How big the boxes are: half the diagonal, for green MO records with coordinates
# and a cached answer showing no GPS point. .org today.
half <- paste("sqrt(power((m.latitude_north - m.latitude_south) * 111.2, 2) +",
              "power((m.longitude_east - m.longitude_west) * 111.2 *",
              "cos(radians((m.latitude_north + m.latitude_south) / 2)), 2)) / 2")
box_sql <- atlas_one_line(sprintf(
  "SELECT count(*) FILTER (WHERE d <= 1) AS km_0_1, count(*) FILTER (WHERE d > 1 AND d <= 2) AS km_1_2,
     count(*) FILTER (WHERE d > 2 AND d <= 5) AS km_2_5, count(*) FILTER (WHERE d > 5 AND d <= 25) AS km_5_25,
     count(*) FILTER (WHERE d > 25) AS km_over_25, count(*) FILTER (WHERE d IS NULL) AS no_box
   FROM (SELECT %s AS d FROM observations o JOIN %s m ON m.source_observation_id = o.observation_id
     WHERE o.source = '%s' AND 'yes' IN (%s) AND o.latitude IS NOT NULL AND o.longitude IS NOT NULL %s
       AND (m.latitude IS NULL OR m.longitude IS NULL)) x",
  half, ATLAS_MO_POINTS, MO, atlas_status_columns(), atlas_place_clause()))
out$box_half_diagonal_km <- tryCatch(as.list(atlas_parse_tsv(atlas_run_sql(box_sql))[1, ]),
                                     error = function(e) list(error = conditionMessage(e)))

# 4. The privacy lists, entry by entry (the standing rule: a place hidden or
# obscured at source stays hidden). A record off the list and in a pull goes
# into the published cells, so each such record must be one its source shows.
# What the source shows is read from .org's cache of its answer, as the pull
# reads it; nothing is asked of iNaturalist or MO live. Only iNaturalist and MO
# have a list: other sources' places are not checked here.
yes <- function(x) !is.na(x) & x %in% c("t", "true", "TRUE")
facts_sql <- function(source, numbers) {
  sprintf(paste(
    "SELECT o.source, o.observation_id, 'yes' IN (%s) AS green,",
    "(o.latitude IS NOT NULL AND o.longitude IS NOT NULL) AS has_point,",
    "(o.country IN (%s) OR o.state = 'Puerto Rico') AS in_region, %s IS NOT NULL AS deleted,",
    "EXISTS (SELECT 1 FROM %s m WHERE o.source = '%s' AND m.source_observation_id = o.observation_id) AS mo_cached,",
    "EXISTS (SELECT 1 FROM %s m WHERE o.source = '%s' AND m.source_observation_id = o.observation_id",
    "AND m.latitude IS NOT NULL AND m.longitude IS NOT NULL) AS mo_shown,",
    "EXISTS (SELECT 1 FROM observation_cache c WHERE o.source = '%s' AND c.source = 'inat'",
    "AND c.source_observation_id = o.observation_id) AS inat_cached,",
    "EXISTS (SELECT 1 FROM observation_cache c WHERE o.source = '%s' AND c.source = 'inat'",
    "AND c.source_observation_id = o.observation_id AND c.coordinates_obscured = true) AS inat_obscured,",
    "EXISTS (SELECT 1 FROM observation_cache c WHERE o.source = '%s' AND c.source = 'inat'",
    "AND c.source_observation_id = o.observation_id AND c.coordinates_obscured IS NULL) AS inat_obscured_blank,",
    "EXISTS (SELECT 1 FROM observation_cache c WHERE o.source = '%s' AND c.source = 'inat'",
    "AND c.source_observation_id = o.observation_id AND c.positional_accuracy > %d) AS inat_coarse",
    "FROM observations o WHERE o.source = '%s' AND o.observation_id IN (%s)"),
    atlas_status_columns(), paste(sprintf("'%s'", ATLAS_NA_COUNTRIES), collapse = ", "), ATLAS_SOURCE_DELETED,
    ATLAS_MO_POINTS, MO, ATLAS_MO_POINTS, MO, ATLAS_INAT_SOURCE, ATLAS_INAT_SOURCE, ATLAS_INAT_SOURCE,
    ATLAS_INAT_SOURCE, as.integer(ATLAS_MAX_ACCURACY_M), source,
    paste(sprintf("'%s'", numbers), collapse = ","))
}
# .org's facts on (source, number) pairs, 200 numbers a query. Stops on any
# number it could not safely ask about, rather than leave it out of the count.
facts_of <- function(entries) {
  entries <- unique(entries[, c("source", "observation_id")])
  if (!nrow(entries)) return(NULL)
  bad <- !grepl("^[A-Za-z0-9_.:-]+$", entries$observation_id) | !grepl("^[A-Za-z ]+$", entries$source)
  if (any(bad)) stop(sum(bad), " list entries have a source or number that cannot be asked about", call. = FALSE)
  pages <- list()
  for (s in unique(entries$source)) {
    numbers <- entries$observation_id[entries$source == s]
    for (chunk in split(numbers, ceiling(seq_along(numbers) / 200))) {
      pages[[length(pages) + 1L]] <- atlas_parse_tsv(atlas_run_sql(atlas_one_line(facts_sql(s, chunk))))
    }
  }
  do.call(rbind, pages)
}
facts_at <- function(entries, facts) {
  if (is.null(facts)) return(NULL)
  facts[match(atlas_record_key(entries$source, entries$observation_id),
              atlas_record_key(facts$source, facts$observation_id)), , drop = FALSE]
}
# Is a record off the list and in a pull one its source shows?
public_verdict <- function(source, f) {
  ifelse(is.na(f$observation_id), "VIOLATION not on org, cannot be confirmed",
  ifelse(source == MO & yes(f$mo_shown), "fine: MO observer shows a GPS point",
  ifelse(source == MO & yes(f$mo_cached), "VIOLATION MO answer cached, no shown GPS",
  ifelse(source == MO, "VIOLATION MO no cached answer",
  ifelse(!yes(f$inat_cached), "VIOLATION iNaturalist no cached answer",
  ifelse(yes(f$inat_obscured), "VIOLATION iNaturalist obscured",
  ifelse(yes(f$inat_coarse), "VIOLATION iNaturalist placed too coarsely",
  ifelse(yes(f$inat_obscured_blank), "VIOLATION iNaturalist obscured field blank",
         "fine: iNaturalist answer cached, not obscured"))))))))
}
why_not_in_pull <- function(f) {
  ifelse(is.na(f$observation_id), "no longer on org",
  ifelse(yes(f$deleted), "deleted at source",
  ifelse(!yes(f$green), "no longer green",
  ifelse(!yes(f$has_point), "no coordinates",
  ifelse(!yes(f$in_region), "outside the region",
  ifelse(yes(f$inat_obscured) | yes(f$inat_coarse), "iNaturalist obscured or too coarse: the pull drops it",
         "eligible on place: no clean species-level name, or MO box too big"))))))
}
audit_lists <- function() {
  a <- unique(frozen_list[, c("source", "observation_id", "privacy")])
  b <- unique(dry_list[, c("source", "observation_id", "privacy")])
  a_key <- atlas_record_key(a$source, a$observation_id)
  b_key <- atlas_record_key(b$source, b$observation_id)
  dry_keys <- key(dry)
  frozen_keys <- key(frozen)
  a$now <- ifelse(a_key %in% b_key, b$privacy[match(a_key, b_key)], "off_list")
  a$in_dry_pull <- a_key %in% dry_keys
  b$was <- ifelse(b_key %in% a_key, a$privacy[match(b_key, a_key)], "not_on_10_13_list")
  b$in_dry_pull <- b_key %in% dry_keys
  tab <- function(...) {
    x <- as.data.frame(table(...), stringsAsFactors = FALSE)
    x[x$Freq > 0, ]
  }
  joined <- b$was == "not_on_10_13_list"
  result <- list(
    frozen_list = nrow(a), dry_list = nrow(b),
    frozen_by_kind = tab(source = a$source, kind = a$privacy),
    dry_by_kind = tab(source = b$source, kind = b$privacy),
    every_frozen_entry = tab(source = a$source, was = a$privacy, now = a$now, in_dry_pull = a$in_dry_pull),
    joined_the_list = if (any(joined)) tab(source = b$source[joined], kind = b$privacy[joined], in_dry_pull = b$in_dry_pull[joined])
  )
  # Left the list and in the dry pull: no longer private, so the source must show it.
  off <- a[a$now == "off_list", , drop = FALSE]
  f_off <- facts_at(off, facts_of(off))
  still <- off$in_dry_pull
  result$left_list_still_in_pull <- list(
    records = sum(still),
    verdicts = if (any(still)) tab(source = off$source[still], was = off$privacy[still],
                                   verdict = public_verdict(off$source[still], f_off[still, , drop = FALSE]))
  )
  # Left the list and out of the dry pull: not published. Why it left.
  result$left_list_out_of_pull <- list(
    records = sum(!still),
    reasons = if (any(!still)) tab(source = off$source[!still], was = off$privacy[!still],
                                   why = why_not_in_pull(f_off[!still, , drop = FALSE]))
  )
  # Every record the dry pull treats as public, list or no list.
  public_mo <- dry[dry$source == MO & !dry_keys %in% b_key, c("source", "observation_id"), drop = FALSE]
  f_mo <- facts_at(public_mo, facts_of(public_mo))
  public_inat <- dry[dry$source == ATLAS_INAT_SOURCE & !dry_keys %in% b_key, c("id", "source", "observation_id"), drop = FALSE]
  ids <- as.numeric(public_inat$id)
  flagged <- list()
  for (from in seq(0, max(ids), by = 50000)) {
    sql <- sprintf(paste(
      "SELECT o.id FROM observations o WHERE o.source = '%s' AND o.id > %d AND o.id <= %d AND (",
      "NOT EXISTS (SELECT 1 FROM observation_cache c WHERE c.source = 'inat' AND c.source_observation_id = o.observation_id OFFSET 0)",
      "OR EXISTS (SELECT 1 FROM observation_cache c WHERE c.source = 'inat' AND c.source_observation_id = o.observation_id",
      "AND (c.coordinates_obscured = true OR c.coordinates_obscured IS NULL OR c.positional_accuracy > %d) OFFSET 0))"),
      ATLAS_INAT_SOURCE, as.integer(from), as.integer(from + 50000), as.integer(ATLAS_MAX_ACCURACY_M))
    page <- atlas_parse_tsv(atlas_run_sql(atlas_one_line(sql)))
    if (nrow(page)) flagged[[length(flagged) + 1L]] <- as.character(page$id)
  }
  flagged <- unlist(flagged)
  inat_bad <- public_inat[as.character(public_inat$id) %in% flagged, , drop = FALSE]
  f_bad <- facts_at(inat_bad, facts_of(inat_bad))
  result$everything_treated_as_public <- list(
    mo_records = nrow(public_mo),
    mo_verdicts = if (nrow(public_mo)) tab(verdict = public_verdict(public_mo$source, f_mo)),
    inat_records = nrow(public_inat),
    inat_not_shown = nrow(inat_bad),
    inat_verdicts = if (nrow(inat_bad)) tab(verdict = public_verdict(inat_bad$source, f_bad))
  )
  # The frozen release's published cells left out its own list. Records in those
  # cells that a source hides today: reported only; the frozen release stays.
  frozen_public <- !frozen_keys %in% a_key
  now_listed <- frozen_public & frozen_keys %in% b_key
  gone <- frozen[frozen_public & frozen$source %in% c(MO, ATLAS_INAT_SOURCE) & !frozen_keys %in% dry_keys,
                 c("source", "observation_id"), drop = FALSE]
  f_gone <- facts_at(gone, facts_of(gone))
  result$public_in_frozen_cells_private_today <- list(
    records_on_the_dry_list = sum(now_listed),
    on_the_dry_list = if (any(now_listed)) tab(source = frozen$source[now_listed],
                                               kind = b$privacy[match(frozen_keys[now_listed], b_key)]),
    left_the_pull_records = nrow(gone),
    left_the_pull_inat_obscured_or_coarse = if (nrow(gone)) sum(yes(f_gone$inat_obscured) | yes(f_gone$inat_coarse), na.rm = TRUE)
  )
  verdicts <- c(if (any(still)) public_verdict(off$source[still], f_off[still, , drop = FALSE]),
                if (nrow(public_mo)) public_verdict(public_mo$source, f_mo),
                if (nrow(inat_bad)) public_verdict(inat_bad$source, f_bad))
  result$limits <- paste("Read from .org's caches today, as the pull reads them; nothing asked of iNaturalist or MO live.",
                         "Only iNaturalist and MO have a list; other sources' places are not checked here.")
  result$violations <- sum(startsWith(verdicts, "VIOLATION"))
  result
}
out$privacy_audit <- tryCatch(audit_lists(), error = function(e) list(error = conditionMessage(e), violations = NA))

atlas_write_json(out, env("OUT"))
message("QA place analysis written: ", env("OUT"), "; privacy violations: ", out$privacy_audit$violations)
