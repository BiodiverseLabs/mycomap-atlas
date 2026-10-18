# One name decision everywhere (Steve, 2026-10-18).
#
# mycomap.org logs every rename its Name Update makes, whoever ran it and
# wherever the decision came from: name_change_log, one row per run, with the
# records it renamed in name_change_records. Atlas reads both over its
# read-only SQL login after each pull, from a cursor (the log's id, which .org
# hands out in order), and keeps what it read in occurrences/name-changes.json
# beside the pull. That file is private like the pull: it names records.
#
# The log does two things here:
#
#   - Its renames go into occurrences/renames.json as source "org", ahead of
#     the majority-of-record-ids guess (atlas_detect_renames), which cannot
#     tell a split from a dropped name. .org knows what it did.
#   - A taxon that a merge or a split touched since the release a plan builds
#     on is planned with the reason, "refit: name merged (org change 812)".
#     The record-set fingerprint already forces those refits; the reason says
#     why. A pure rename or re-spelling also refits, under its new name (the
#     Atlas coordinator, 2026-10-18): a model is traced to the job that fitted
#     it by its record set, and a relabelled one would carry a fingerprint no
#     job ever fitted.
#
# Frozen releases never change. A rename reaches the next pull, and the next
# release carries it in its renames.json.
#
# A failed read never fails the pull: the cursor stays where it was, the error
# is kept in the file, and the next pull reads from the same place.

ATLAS_NAME_CHANGE_KINDS <- c("respelling", "rename", "merge", "split")
ATLAS_NAME_CHANGE_COLUMNS <- c(
  "id", "logged_at", "batch_id", "merge_group_id", "request_id", "source", "decision_ref",
  "old_name", "new_name", "kind", "respelling", "synonym_registered", "records_changed",
  "old_name_left", "new_name_before"
)
ATLAS_NAME_CHANGE_PAGE <- 500L
ATLAS_NAME_CHANGE_RECORD_PAGE <- 20000L
ATLAS_NAME_CHANGE_MAX_PAGES <- 200L

# How a record_ref names a record Atlas pulls: the prefix and the .org source
# whose observation_id follows it. seq: and mp: refs name sequences and
# local records, which a pull holds under other ids; they are matched by name.
ATLAS_NAME_CHANGE_REF_SOURCES <- c(inat = "iNaturalist", mo = "MO Observations")

#' Where the log read so far is kept, beside the pull. Never published.
atlas_name_changes_path <- function() {
  atlas_path("occurrences", "name-changes.json")
}

#' One page of the log after a cursor. logged_at is a timestamp without a
#' time zone, written by .org's defaultNow(), so it is UTC only because .org's
#' database runs Etc/UTC (checked 2026-10-18). Plan reasons compare it with a
#' release's pulled_at; a change of that server's time zone would shift them.
atlas_name_change_log_sql <- function(after_id = 0, limit = ATLAS_NAME_CHANGE_PAGE) {
  stopifnot(length(after_id) == 1, is.numeric(after_id), after_id >= 0)
  columns <- paste0("l.", ATLAS_NAME_CHANGE_COLUMNS)
  columns[ATLAS_NAME_CHANGE_COLUMNS == "logged_at"] <- "CAST(CAST(l.logged_at AS timestamp(0)) AS text) AS logged_at"
  atlas_one_line(sprintf(
    "SELECT %s FROM name_change_log l WHERE l.id > %.0f ORDER BY l.id LIMIT %d",
    paste(columns, collapse = ", "), after_id, as.integer(limit)
  ))
}

#' One page of the records behind log rows first_id..last_id, after a record id.
atlas_name_change_records_sql <- function(first_id, last_id, after_record = 0,
                                          limit = ATLAS_NAME_CHANGE_RECORD_PAGE) {
  atlas_one_line(sprintf(
    "SELECT r.id, r.log_id, r.record_ref FROM name_change_records r WHERE r.log_id >= %.0f AND r.log_id <= %.0f AND r.id > %.0f ORDER BY r.id LIMIT %d",
    first_id, last_id, after_record, as.integer(limit)
  ))
}

#' What this machine has read of the log: the cursor, the changes (a list,
#' one entry each, with its record refs), and the last read's outcome.
atlas_read_name_changes <- function(path = atlas_name_changes_path()) {
  empty <- list(cursor = 0, changes = list())
  if (!file.exists(path)) return(empty)
  known <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(known)) return(empty)
  known$cursor <- as.numeric(known$cursor %||% 0)
  known$changes <- lapply(known$changes %||% list(), atlas_name_change_entry)
  known
}

#' A change as kept: typed fields, NA where .org has none, refs as a vector.
atlas_name_change_entry <- function(x) {
  value <- function(name) {
    v <- x[[name]]
    if (is.null(v) || !length(v) || identical(v, list())) NA else v[[1]]
  }
  int <- function(name) {
    v <- value(name)
    if (is.na(v) || !nzchar(as.character(v))) NA_integer_ else as.integer(v)
  }
  text <- function(name) {
    v <- value(name)
    if (is.na(v)) NA_character_ else as.character(v)
  }
  flag <- function(name) as.character(value(name)) %in% c("t", "true", "TRUE")
  list(
    id = int("id"), logged_at = text("logged_at"), batch_id = int("batch_id"),
    merge_group_id = int("merge_group_id"), request_id = int("request_id"),
    source = text("source"), decision_ref = text("decision_ref"),
    old_name = text("old_name"), new_name = text("new_name"), kind = text("kind"),
    respelling = flag("respelling"), synonym_registered = flag("synonym_registered"),
    records_changed = int("records_changed"), old_name_left = int("old_name_left"),
    new_name_before = int("new_name_before"),
    records = as.character(unlist(x$records %||% character()))
  )
}

#' Rows of the log as read from the route, as change entries. A timestamp
#' "2026-10-18 12:00:00" becomes "2026-10-18T12:00:00Z".
atlas_name_change_rows <- function(raw) {
  missing <- setdiff(ATLAS_NAME_CHANGE_COLUMNS, names(raw))
  if (length(missing)) {
    stop("name-change log is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  rows <- lapply(seq_len(nrow(raw)), function(i) {
    entry <- atlas_name_change_entry(as.list(raw[i, ATLAS_NAME_CHANGE_COLUMNS, drop = FALSE]))
    if (!is.na(entry$logged_at)) entry$logged_at <- paste0(sub(" ", "T", entry$logged_at, fixed = TRUE), "Z")
    entry
  })
  bad <- vapply(rows, function(r) is.na(r$id) || is.na(r$old_name) || is.na(r$new_name), logical(1))
  if (any(bad)) stop("name-change log has a row without an id or a name", call. = FALSE)
  rows
}

#' The record refs behind log rows first_id..last_id, by log id.
atlas_pull_name_change_records <- function(first_id, last_id, host = atlas_sql_host()) {
  refs <- list()
  after <- 0
  for (page in seq_len(ATLAS_NAME_CHANGE_MAX_PAGES)) {
    raw <- atlas_parse_tsv(atlas_run_sql(atlas_name_change_records_sql(first_id, last_id, after), host = host))
    if (!nrow(raw)) break
    missing <- setdiff(c("id", "log_id", "record_ref"), names(raw))
    if (length(missing)) {
      stop("name-change records are missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    for (log_id in unique(raw$log_id)) {
      refs[[log_id]] <- c(refs[[log_id]], raw$record_ref[raw$log_id == log_id])
    }
    after <- max(as.numeric(raw$id))
    if (nrow(raw) < ATLAS_NAME_CHANGE_RECORD_PAGE) break
  }
  refs
}

#' Read the log since the stored cursor and keep what was read. Each page is
#' written as soon as it is whole (log rows and their records), so a read cut
#' short keeps what it finished and the next read carries on from there.
#' Never fails: a failure is kept in the file and reported, and the cursor
#' stays put.
atlas_pull_name_changes <- function(host = atlas_sql_host(), path = atlas_name_changes_path(),
                                    quiet = FALSE) {
  known <- atlas_read_name_changes(path)
  save <- function(error = NULL) {
    known$read_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    known$last_error <- error %||% NA_character_
    atlas_write_json(known, path)
  }
  read <- 0L
  outcome <- tryCatch({
    for (page in seq_len(ATLAS_NAME_CHANGE_MAX_PAGES)) {
      raw <- atlas_parse_tsv(atlas_run_sql(atlas_name_change_log_sql(known$cursor), host = host))
      if (!nrow(raw)) break
      rows <- atlas_name_change_rows(raw)
      ids <- vapply(rows, function(r) r$id, integer(1))
      refs <- atlas_pull_name_change_records(min(ids), max(ids), host = host)
      for (i in seq_along(rows)) rows[[i]]$records <- as.character(refs[[as.character(ids[[i]])]] %||% character())
      held <- vapply(known$changes, function(r) r$id, integer(1))
      known$changes <- c(known$changes[!held %in% ids], rows)
      known$cursor <- max(ids)
      read <- read + length(rows)
      save()
      if (nrow(raw) < ATLAS_NAME_CHANGE_PAGE) break
    }
    NULL
  }, error = function(e) conditionMessage(e))
  save(outcome)
  if (!isTRUE(quiet)) {
    if (is.null(outcome)) {
      message(sprintf("name-change log: %d new change(s), %d known, cursor %.0f",
                      read, length(known$changes), known$cursor))
    } else {
      message("name-change log not read (cursor stays at ", format(known$cursor), "): ", outcome)
    }
  }
  invisible(known)
}

# ---- renames ------------------------------------------------------------------

#' The renames the log says were made, as renames.json rows (source "org").
#' The latest change of each old name wins. A change inside one of Atlas's own
#' spelling folds (atlas_name_key) is no rename here. The new name is given in
#' the spelling the pull models it under when the pull has it.
#'
#' records and moved count the pull, as a detected row's do: records, the
#' change's records this pull holds; moved, how many of them sit under the new
#' name. .org's own count, over every record it renamed whatever its status,
#' place or kind, is org_records_changed. Without a pull both counts are NA.
atlas_org_renames <- function(changes, current_names = character(), occurrences = NULL) {
  empty <- data.frame(from = character(), to = character(), records = integer(), moved = integer(),
                      seen = character(), source = character(), change = integer(),
                      org_records_changed = integer(), stringsAsFactors = FALSE)
  changes <- Filter(function(r) r$kind %in% ATLAS_NAME_CHANGE_KINDS &&
                      !identical(atlas_name_key(r$old_name), atlas_name_key(r$new_name)), changes)
  if (!length(changes)) return(empty)
  ids <- vapply(changes, function(r) r$id, integer(1))
  changes <- changes[order(ids)]
  keys <- atlas_name_key(vapply(changes, function(r) r$old_name, ""))
  latest <- changes[!duplicated(keys, fromLast = TRUE)]
  current_names <- unique(as.character(current_names))
  canonical <- stats::setNames(current_names, atlas_name_key(current_names))
  refs <- if (!is.null(occurrences) && nrow(occurrences)) atlas_occurrence_refs(occurrences)
  out <- do.call(rbind, lapply(latest, function(r) {
    to <- unname(canonical[atlas_name_key(r$new_name)])
    to <- if (is.na(to)) r$new_name else to
    held <- if (!is.null(refs)) !is.na(refs) & refs %in% r$records
    data.frame(from = r$old_name, to = to,
               records = if (is.null(held)) NA_integer_ else sum(held),
               moved = if (is.null(held)) NA_integer_ else sum(held & occurrences$scientific_name == to),
               seen = substr(r$logged_at %||% NA_character_, 1L, 10L),
               source = "org", change = r$id, org_records_changed = r$records_changed,
               stringsAsFactors = FALSE)
  }))
  out <- out[order(out$from), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Renames with the log's in place: every "org" row rebuilt from the log, and
#' any guessed row for an old name the log has spoken for dropped. A name the
#' pull still models (in any spelling Atlas folds together) has not gone, so
#' no row leads away from it: a split that left records under the old name is
#' no rename.
atlas_merge_org_renames <- function(existing, org, current_names) {
  columns <- c("from", "to", "records", "moved", "seen", "source", "change", "org_records_changed")
  shape <- function(x, source) {
    if (is.null(x) || !NROW(x)) return(NULL)
    x <- as.data.frame(x, stringsAsFactors = FALSE)
    if (is.null(x$source)) x$source <- source
    x$source[is.na(x$source)] <- source
    if (is.null(x$change)) x$change <- NA_integer_
    if (is.null(x$org_records_changed)) x$org_records_changed <- NA_integer_
    x[, columns, drop = FALSE]
  }
  existing <- shape(existing, "detected")
  org <- shape(org, "org")
  if (!is.null(existing)) existing <- existing[existing$source != "org", , drop = FALSE]
  if (!is.null(existing) && !is.null(org)) {
    existing <- existing[!atlas_name_key(existing$from) %in% atlas_name_key(org$from), , drop = FALSE]
  }
  out <- rbind(existing, org)
  if (is.null(out) || !nrow(out)) {
    return(data.frame(from = character(), to = character(), records = integer(), moved = integer(),
                      seen = character(), source = character(), change = integer(),
                      org_records_changed = integer(), stringsAsFactors = FALSE))
  }
  out <- out[!atlas_name_key(out$from) %in% atlas_name_key(current_names), , drop = FALSE]
  out <- out[order(out$from), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Put the log's renames into renames.json for the pull just made. Never
#' fails the pull.
atlas_record_org_renames <- function(occurrences, path = atlas_renames_path(),
                                     changes = atlas_read_name_changes()$changes, quiet = FALSE) {
  tryCatch({
    current_names <- unique(occurrences$scientific_name)
    merged <- atlas_merge_org_renames(atlas_read_renames(path),
                                      atlas_org_renames(changes, current_names, occurrences),
                                      current_names)
    atlas_write_json(merged, path)
    invisible(merged)
  }, error = function(e) {
    if (!isTRUE(quiet)) message("renames from the name-change log not recorded: ", conditionMessage(e))
    invisible(NULL)
  })
}

#' Each pulled record as the log names it (inat:N, mo:N), NA for the rest.
atlas_occurrence_refs <- function(occurrences) {
  refs <- rep(NA_character_, nrow(occurrences))
  for (prefix in names(ATLAS_NAME_CHANGE_REF_SOURCES)) {
    hit <- occurrences$source %in% ATLAS_NAME_CHANGE_REF_SOURCES[[prefix]]
    refs[hit] <- paste0(prefix, ":", occurrences$observation_id[hit])
  }
  refs
}

# ---- plan reasons ---------------------------------------------------------------

#' Why each taxon a merge or a split touched since `since` (the base release's
#' pull time, "YYYY-MM-DDTHH:MM:SSZ"; NA for every change) is refitted: a
#' named vector, taxon to reason. A change touches the taxon the pull models
#' its new name under, the taxon now holding any of its records, and, for a
#' split, the taxon its old name still names.
atlas_name_change_reasons <- function(changes, occurrences, since = NA_character_) {
  none <- stats::setNames(character(), character())
  if (!length(changes) || is.null(occurrences) || !nrow(occurrences)) return(none)
  changes <- Filter(function(r) r$kind %in% c("merge", "split"), changes)
  if (!is.na(since %||% NA_character_) && nzchar(since)) {
    changes <- Filter(function(r) !is.na(r$logged_at) && r$logged_at > since, changes)
  }
  if (!length(changes)) return(none)
  taxa <- unique(occurrences$scientific_name)
  by_key <- stats::setNames(taxa, atlas_name_key(taxa))
  refs <- atlas_occurrence_refs(occurrences)
  touched <- list()
  for (r in changes) {
    names_hit <- c(by_key[atlas_name_key(r$new_name)],
                   if (identical(r$kind, "split")) by_key[atlas_name_key(r$old_name)],
                   occurrences$scientific_name[!is.na(refs) & refs %in% r$records])
    for (taxon in unique(stats::na.omit(unname(names_hit)))) {
      touched[[length(touched) + 1L]] <- data.frame(taxon = taxon, kind = r$kind, id = r$id,
                                                    stringsAsFactors = FALSE)
    }
  }
  if (!length(touched)) return(none)
  touched <- unique(do.call(rbind, touched))
  touched <- touched[order(touched$taxon, touched$kind, touched$id), , drop = FALSE]
  words <- c(merge = "merged", split = "split")
  reasons <- vapply(split(touched, touched$taxon), function(t) {
    parts <- vapply(unique(t$kind), function(kind) {
      ids <- sort(unique(t$id[t$kind == kind]))
      sprintf("name %s (org change%s %s)", words[[kind]], if (length(ids) > 1L) "s" else "",
              paste(ids, collapse = ", "))
    }, "")
    paste0("refit: ", paste(parts, collapse = "; "))
  }, "")
  reasons
}
