# Where the records go (Steve, 2026-11-19): from every observation .org holds
# to the records a release trains on, one step at a time, as counts. Every
# full pull writes it into its manifest (waterfall), and its release's pull
# summary carries it, so the site can show why Atlas uses fewer records than
# .org holds. Counts only, by step and by source: never a record's number,
# name or place.
#
# total is every observation in .org. Each step then removes records that
# passed every step before it:
#
#   dna            not green in any validation project
#   coordinates    no latitude or longitude
#   north_america  outside North America (atlas_place_clause)
#   obscured       an iNaturalist record iNaturalist obscures
#   inat_coarse    an iNaturalist record placed no better than the cutoff
#                  (max_accuracy_m; ATLAS_MAX_ACCURACY_M)
#   other_coarse   no usable point under the other sources' place rules
#                  (atlas_mo_location_clause, atlas_mycoportal_location_clause),
#                  in parts by source, Mushroom Observer's by why
#                  (atlas_mo_left_out: mo_place_centre, mo_deleted)
#   name           no single species name from the record's approved
#                  sequences, in parts by why (R/labels.R): disagree,
#                  no_named_sequence, genus_only, a rank word, no taxon
#   excluded       the box's drop list (R/exclude.R)
#   other_kingdom  names GBIF matches exactly in another kingdom (R/qa.R)
#
# and used is what is left: the pull's records. pulled is what the pull's
# query returned, before the name step.
#
# The steps up to north_america, and the iNaturalist ones, are counted on
# .org by a read-only query per id window the pull read (as
# atlas_mo_left_out counts MO), each well inside the route's 60 s cap, one
# at a time. other_coarse is what is left between them and the rows the
# pull returned, so the steps add up exactly by construction; where a
# source's remainder has no rule to explain it (a record that changed while
# the pull ran), it shows as a part of its own, not hidden.

ATLAS_WATERFALL_COLUMNS <- c("observations", "dna_validated", "with_coordinates", "in_north_america",
                             "inat_obscured", "inat_coarse")

#' Counts by source of the observations with ids after_id < id <= through_id
#' (no upper bound when through_id is NULL), step by step to the pull's own
#' place rules. One row per source.
atlas_waterfall_sql <- function(after_id = 0, through_id = NULL, max_m = ATLAS_MAX_ACCURACY_M) {
  through <- if (is.null(through_id)) "" else sprintf("AND o.id <= %d", as.integer(through_id))
  inat_cache <- function(condition) {
    sprintf(paste("(o.source = '%s' AND EXISTS (SELECT 1 FROM observation_cache c WHERE c.source = 'inat'",
                  "AND c.source_observation_id = o.observation_id AND %s OFFSET 0))"),
            ATLAS_INAT_SOURCE, condition)
  }
  place <- sub("^AND ", "", atlas_place_clause())
  sql <- sprintf(
    "SELECT x.source,
       count(*) AS observations,
       count(*) FILTER (WHERE x.green) AS dna_validated,
       count(*) FILTER (WHERE x.green AND x.located) AS with_coordinates,
       count(*) FILTER (WHERE x.green AND x.located AND x.placed) AS in_north_america,
       count(*) FILTER (WHERE x.green AND x.located AND x.placed AND x.obscured) AS inat_obscured,
       count(*) FILTER (WHERE x.green AND x.located AND x.placed AND NOT x.obscured AND x.coarse) AS inat_coarse
     FROM (SELECT o.source,
       ('yes' IN (%s)) AS green,
       (o.latitude IS NOT NULL AND o.longitude IS NOT NULL) AS located,
       coalesce(%s, false) AS placed,
       %s AS obscured,
       %s AS coarse
     FROM observations o
     WHERE o.id > %d
       %s) x
     GROUP BY x.source
     ORDER BY x.source",
    atlas_status_columns(), place,
    inat_cache("c.coordinates_obscured = true"),
    inat_cache(sprintf("c.positional_accuracy > %d", as.integer(max_m))),
    as.integer(after_id), through
  )
  atlas_one_line(sql)
}

#' The id windows a pull read, page by page: each page's last id closes one,
#' and when the pull read to the end, one more is open above the last.
atlas_pull_windows <- function(bounds, complete) {
  windows <- if (length(bounds)) {
    lapply(seq_along(bounds), function(i) c(if (i == 1L) 0 else bounds[[i - 1L]], bounds[[i]]))
  } else {
    list()
  }
  if (isTRUE(complete)) windows <- c(windows, list(c(if (length(bounds)) utils::tail(bounds, 1) else 0, NA)))
  windows
}

#' Ask .org for the counts, window by window, and sum them by source. A data
#' frame with a source column and ATLAS_WATERFALL_COLUMNS.
atlas_waterfall_counts <- function(windows, host = atlas_sql_host(), max_m = ATLAS_MAX_ACCURACY_M) {
  totals <- list()
  for (w in windows) {
    rows <- atlas_parse_tsv(atlas_run_sql(
      atlas_waterfall_sql(w[[1]], if (is.na(w[[2]])) NULL else w[[2]], max_m), host = host))
    missing <- setdiff(c("source", ATLAS_WATERFALL_COLUMNS), names(rows))
    if (nrow(rows) && length(missing)) {
      stop("the waterfall query is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    for (i in seq_len(nrow(rows))) {
      source <- as.character(rows$source[[i]])
      counts <- vapply(ATLAS_WATERFALL_COLUMNS, function(k) as.numeric(rows[[k]][[i]]), numeric(1))
      totals[[source]] <- (totals[[source]] %||% 0) + counts
    }
  }
  if (!length(totals)) {
    return(as.data.frame(c(list(source = character()),
                           stats::setNames(rep(list(numeric()), length(ATLAS_WATERFALL_COLUMNS)), ATLAS_WATERFALL_COLUMNS))))
  }
  out <- data.frame(source = names(totals), do.call(rbind, totals), stringsAsFactors = FALSE, row.names = NULL)
  out[order(out$source), , drop = FALSE]
}

#' Why each pulled record has no modelled name: its name status when it has
#' no name, "not species level" for a genus or "sp." alone, else why the
#' name is no species (atlas_not_species: a rank word, or no taxon). NA for a
#' record whose name is modelled.
atlas_waterfall_name_reason <- function(labelled) {
  name <- as.character(labelled$scientific_name)
  reason <- rep(NA_character_, length(name))
  no_name <- is.na(name) | !nzchar(name)
  reason[no_name] <- as.character(labelled$name_status[no_name])
  named <- !no_name
  species <- atlas_species_level(name)
  reason[named & !species] <- "not species level"
  why <- atlas_not_species(name)
  ranked <- named & species & !is.na(why)
  reason[ranked] <- why[ranked]
  reason
}

# The ids of the name reasons a record leaves at the name step.
ATLAS_WATERFALL_NAME_PARTS <- c(
  "sequences disagree (left out)" = "disagree",
  "no approved named sequence" = "no_named_sequence",
  "sequence name is one word (left out)" = "sequence_one_word",
  "not species level" = "genus_only",
  "a rank above species" = "rank_above_species",
  "not a species name" = "not_a_species_name"
)

#' An id for a source or a reason: lower case, words joined by "_".
atlas_waterfall_id <- function(x) {
  gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(x)))
}

#' Put the steps together, in the shape the site's page reads: total, used,
#' max_accuracy_m, and steps of {id, removed, parts: [{id, count}]}, where a
#' step's parts add up to what it removed and total less every step's
#' removed is used (adds_up says whether it does).
#'
#' counts is atlas_waterfall_counts; labelled the pull's rows with their names
#' (atlas_label_occurrences); mo_left_out the manifest's; excluded and kingdom
#' the rows removed by the drop list and by kingdom; used the records the
#' pull keeps.
atlas_waterfall <- function(counts, labelled, mo_left_out, excluded, kingdom, used,
                            max_m = ATLAS_MAX_ACCURACY_M) {
  total <- function(column) sum(counts[[column]])
  part <- function(id, count) list(id = id, count = as.integer(count))
  step <- function(id, removed, parts = NULL) {
    c(list(id = id, removed = as.integer(removed)), if (!is.null(parts)) list(parts = parts))
  }
  in_na <- stats::setNames(counts$in_north_america, counts$source)
  inat_out <- stats::setNames(counts$inat_obscured + counts$inat_coarse, counts$source)
  sources <- union(counts$source, unique(as.character(labelled$source)))
  pulled_by <- table(factor(as.character(labelled$source), levels = sources))
  # What each source lost to the other place rules: what reached North
  # America, less the iNaturalist steps, less what the pull returned.
  remainder <- vapply(sources, function(s) {
    unname((if (s %in% names(in_na)) in_na[[s]] else 0) - (if (s %in% names(inat_out)) inat_out[[s]] else 0) -
             as.numeric(pulled_by[[s]]))
  }, numeric(1))
  of <- function(which) sum(remainder[names(remainder) %in% which])
  mo <- of(ATLAS_MO_SOURCE)
  mo_known <- if (is.null(mo_left_out$error)) {
    c(mo_place_centre = as.numeric(mo_left_out$too_coarse %||% 0),
      mo_deleted = as.numeric(mo_left_out$deleted_at_source_uncached %||% 0),
      mo_uncached = as.numeric(mo_left_out$uncached %||% 0))
  } else {
    c(mo_place_centre = 0, mo_deleted = 0, mo_uncached = 0)
  }
  named_sources <- c(ATLAS_MO_SOURCE, ATLAS_MYCOPORTAL_SOURCES, "Sequences", "GenBank")
  others <- remainder[!names(remainder) %in% named_sources]
  place_parts <- c(
    list(part("mo_place_centre", mo_known[["mo_place_centre"]]), part("mo_deleted", mo_known[["mo_deleted"]])),
    if (mo_known[["mo_uncached"]] != 0) list(part("mo_uncached", mo_known[["mo_uncached"]])),
    # MO records the place rules left out with no reason counted for them.
    if (mo != sum(mo_known)) list(part("mo_unexplained", mo - sum(mo_known))),
    list(part("mycoportal", of(ATLAS_MYCOPORTAL_SOURCES)), part("sequences", of("Sequences")),
         part("genbank", of("GenBank"))),
    # A source with no place rule of its own loses nothing here unless a
    # record changed while the pull ran; it shows under its own id.
    lapply(names(others)[others != 0], function(s) part(atlas_waterfall_id(s), others[[s]]))
  )
  reasons <- atlas_waterfall_name_reason(labelled)
  named <- reasons[!is.na(reasons)]
  ids <- unname(ifelse(named %in% names(ATLAS_WATERFALL_NAME_PARTS), ATLAS_WATERFALL_NAME_PARTS[named],
                       atlas_waterfall_id(named)))
  levels <- unique(c(unname(ATLAS_WATERFALL_NAME_PARTS), ids))
  name_counts <- table(factor(ids, levels = levels))
  always <- c("disagree", "no_named_sequence", "genus_only")
  name_parts <- lapply(levels[as.numeric(name_counts) > 0 | levels %in% always],
                       function(id) part(id, name_counts[[id]]))
  steps <- list(
    step("dna", total("observations") - total("dna_validated")),
    step("coordinates", total("dna_validated") - total("with_coordinates")),
    step("north_america", total("with_coordinates") - total("in_north_america")),
    step("obscured", total("inat_obscured")),
    step("inat_coarse", total("inat_coarse")),
    step("other_coarse", sum(remainder), place_parts),
    step("name", length(named), name_parts),
    step("excluded", excluded),
    step("other_kingdom", kingdom)
  )
  list(
    version = 1L,
    total = as.integer(total("observations")),
    pulled = nrow(labelled),
    used = as.integer(used),
    max_accuracy_m = max_m,
    steps = steps,
    # The page draws nothing unless total less every removal is used and each
    # step's parts are what it removed; so the pull says whether they are.
    adds_up = atlas_waterfall_adds_up(list(total = total("observations"), used = used, steps = steps))
  )
}

#' Whether a waterfall adds up: total less every step's removed is used, and
#' each step's parts add up to what it removed.
atlas_waterfall_adds_up <- function(waterfall) {
  removed <- sum(vapply(waterfall$steps, function(x) as.numeric(x$removed), numeric(1)))
  parts <- vapply(waterfall$steps, function(x) {
    is.null(x$parts) || sum(vapply(x$parts, function(q) as.numeric(q$count), numeric(1))) == as.numeric(x$removed)
  }, logical(1))
  isTRUE(as.numeric(waterfall$total) - removed == as.numeric(waterfall$used)) && all(parts)
}

#' After the drop list is applied again to a pull (exclude-records), its
#' waterfall follows: the rows removed now leave at "excluded", and used is
#' the records kept.
atlas_waterfall_recut <- function(waterfall, removed, used) {
  if (is.null(waterfall$steps)) return(waterfall)
  i <- which(vapply(waterfall$steps, function(x) identical(x$id, "excluded"), logical(1)))
  if (!length(i)) return(waterfall)
  waterfall$steps[[i]]$removed <- as.integer(waterfall$steps[[i]]$removed + removed)
  waterfall$used <- as.integer(used)
  waterfall$adds_up <- atlas_waterfall_adds_up(waterfall)
  waterfall
}
