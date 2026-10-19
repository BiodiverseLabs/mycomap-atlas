# Each record's first green validation date: a private side column of the
# pull, for MycoMap Vision's leave-validation-out benchmark (Vision spec
# docs/atlas-environment.md section 3; Steve, 2026-10-12).
#
# Vision holds out the records validated after a cutoff, and Atlas fits a
# prior-only release on the same pull without them. Vision hands Atlas the
# cutoff, a date, and never records: Atlas finds the records itself from this
# column. It is the earliest validation_date_i, over every .org row of the
# record's observation, whose validation_status_i is 'yes' (trimmed, any
# case), as an ISO date; empty when there is none. That is exactly how
# Vision's records.build_records computes validated_on, parsing included, so
# the two agree on which records fall after a cutoff.
#
# An observation is its source and its number together. .org's sources number
# their records independently, so MO 355385 and MycoPortal 355385 are two
# observations, and one's validation must never date the other (the 10/12
# pull dated an MO record by a MycoPortal one, years before it was even
# collected). Rows of one source sharing a number are one observation.
#
# It changes nothing else. The pull's own query, its rows and the fields a
# record-set fingerprint covers (ATLAS_FINGERPRINT_FIELDS) are untouched, and
# the dates come from a separate query per page. Like the pull itself the
# column is private: it never reaches a release, the API or Zenodo.

ATLAS_FIRST_GREEN_FIELD <- "first_green_on"

#' The validation slots of every .org row of the observations on one page of
#' the pull: the page's records, found by the id range the page spans, and
#' every other row of the same observations, same source and same number.
atlas_first_green_sql <- function(min_id, max_id) {
  stopifnot(is.numeric(min_id), is.numeric(max_id), length(min_id) == 1L, length(max_id) == 1L,
            min_id <= max_id)
  slots <- paste(sprintf("g.validation_status_%d, g.validation_date_%d", 1:3, 1:3), collapse = ", ")
  atlas_one_line(sprintf(
    "SELECT g.observation_id, g.source, %s FROM observations g WHERE (g.source, g.observation_id) IN (SELECT o.source, o.observation_id FROM observations o WHERE o.id >= %.0f AND o.id <= %.0f)",
    slots, min_id, max_id
  ))
}

#' .org's validation dates as ISO dates, or NA. .org keeps them as text,
#' usually M/D/YYYY with an optional time; an ISO date is read too, and
#' anything that is not a real date is NA. Mirrors Vision's
#' records.parse_validation_date.
atlas_parse_validation_date <- function(x) {
  x <- trimws(as.character(x))
  out <- rep(NA_character_, length(x))
  real <- function(y, m, d) {
    ok <- !is.na(y) & !is.na(m) & !is.na(d) & y >= 1 & m >= 1 & m <= 12 & d >= 1 & d <= 31
    iso <- ifelse(ok, sprintf("%04d-%02d-%02d", y, m, d), NA_character_)
    parsed <- as.Date(iso, format = "%Y-%m-%d")
    # A day the month does not have (31 April) is not a date.
    ifelse(!is.na(parsed) & format(parsed, "%Y-%m-%d") == iso, iso, NA_character_)
  }
  mdy <- regmatches(x, regexec("^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})", x))
  is_mdy <- lengths(mdy) == 4L
  if (any(is_mdy)) {
    parts <- do.call(rbind, mdy[is_mdy])
    out[is_mdy] <- real(as.integer(parts[, 4]), as.integer(parts[, 2]), as.integer(parts[, 3]))
  }
  iso <- !is_mdy & !is.na(x) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", x)
  if (any(iso)) {
    head <- substr(x[iso], 1, 10)
    out[iso] <- real(as.integer(substr(head, 1, 4)), as.integer(substr(head, 6, 7)),
                     as.integer(substr(head, 9, 10)))
  }
  out
}

#' The key an observation's first green date is held under: its source and
#' its number, both trimmed (Vision keys its records by trimmed ids).
atlas_first_green_key <- function(source, observation_id) {
  paste(trimws(source), trimws(observation_id), sep = "	")
}

#' Each observation's first green date, from the rows atlas_first_green_sql
#' returns: a named vector, atlas_first_green_key(source, observation id) ->
#' ISO date, holding only the observations that have one.
atlas_first_green_dates <- function(slots) {
  if (is.null(slots) || !nrow(slots)) return(stats::setNames(character(), character()))
  dates <- lapply(1:3, function(i) {
    status <- slots[[sprintf("validation_status_%d", i)]]
    green <- !is.na(status) & tolower(trimws(status)) == "yes"
    date <- atlas_parse_validation_date(slots[[sprintf("validation_date_%d", i)]])
    data.frame(source = slots$source, observation_id = trimws(slots$observation_id),
               date = ifelse(green, date, NA_character_), stringsAsFactors = FALSE)
  })
  all <- do.call(rbind, dates)
  all <- all[!is.na(all$date) & !is.na(all$observation_id) & nzchar(all$observation_id) &
               !is.na(all$source), , drop = FALSE]
  if (!nrow(all)) return(stats::setNames(character(), character()))
  # ISO dates sort as text.
  first <- tapply(all$date, atlas_first_green_key(all$source, all$observation_id), min)
  stats::setNames(as.character(first), names(first))
}

#' Add the column to one page of the pull.
atlas_add_first_green <- function(page, slots) {
  first <- atlas_first_green_dates(slots)
  page[[ATLAS_FIRST_GREEN_FIELD]] <- unname(first[atlas_first_green_key(page$source, page$observation_id)])
  page
}
