# Records Atlas leaves out of every pull, by a private list on the box
# (Steve, 2026-10-13).
#
# .org held 75 bogus iNaturalist rows: Mushroom Observer specimens labelled
# "iNat<number>", pointing at unrelated iNaturalist observations with the
# wrong taxon and place. 22 passed the pull's rules into the frozen pull of
# 2026-10-12 (occurrences-20261012T051017Z): 18 non-fungal names (a mallard,
# a coyote, ...) of one or two records each, and one bad point each for
# Clitocybe deceptiva and Agaricus bitorquis. Until .com's repair has run and
# .org's mirror has re-synced, any pull brings them back.
#
# So the box keeps a drop list (occurrences/exclude.tsv: by, id, reason,
# added_at), private like the pull, which every pull applies after its rows
# are named and before anything is fingerprinted or written: the pull's
# latest.json records the list's hash and how many rows it removed.
#
#   ./atlas exclude-records --ids=<file or comma list> [--by=id|observation_id] [--reason=...]
#       adds the ids to the list, then rewrites this machine's current pull
#       without every listed row, as a new pull file latest.json points at:
#       no fresh pull, so a cutoff on the frozen pull (Vision's v1-test) holds.
#       Its pulled_at, first green dates and record names are the pull's own;
#       the taxa summary and spelling merges are made again from the cleaned
#       rows. The pull file it was made from is untouched.
#   ./atlas exclude-records --clear --confirm
#       retires the list (kept as exclude-cleared-<time>.tsv), deliberately:
#       the next pull leaves nothing out.
#
# A plan-job on the cleaned pull refits exactly the taxa whose records
# changed, since planning compares each taxon's records with the current
# release; a name left with too few records is never a candidate, so it gets
# no model, and it leaves the published cells and counts.

# How a row is named in the list: .org's row id (the pull's id column,
# unique), or its source and the source's own number ("iNaturalist:489483").
# Never the source's number alone: iNaturalist's and Mushroom Observer's
# overlap, and a valid record of the other source could go.
ATLAS_EXCLUDE_BY <- c("id", "source_observation")

#' The key a row has under a way of naming it.
atlas_exclude_keys <- function(occurrences, by) {
  if (identical(by, "id")) as.character(occurrences$id) else atlas_record_key(occurrences$source, occurrences$observation_id)
}

atlas_exclude_path <- function() atlas_path("occurrences", "exclude.tsv")

#' Read a list of ids: a file of them (one per line, or comma separated), or
#' the list itself.
atlas_read_id_list <- function(ids) {
  text <- if (length(ids) == 1L && file.exists(ids)) readLines(ids, warn = FALSE) else as.character(ids)
  out <- trimws(unlist(strsplit(text, "[,[:space:]]+")))
  unique(out[nzchar(out)])
}

#' The drop list, or NULL when there is none.
atlas_read_exclusions <- function(path = atlas_exclude_path()) {
  if (!file.exists(path)) return(NULL)
  list <- utils::read.delim(path, sep = "\t", quote = "", comment.char = "", na.strings = "",
                            colClasses = "character", stringsAsFactors = FALSE, encoding = "UTF-8")
  if (!all(c("by", "id") %in% names(list))) stop("the drop list ", path, " has no by and id columns", call. = FALSE)
  list
}

#' Leave the listed rows out: the rows kept, those removed, and what the
#' pull's manifest says about it (the list's hash, how many it listed and
#' removed, and how many rows the entries added on each day removed: a row an
#' entry of each of two days names counts under the earlier day, and entries
#' with no date under "undated"). With no list, nothing is left out and the
#' manifest says so.
atlas_apply_exclusions <- function(occurrences, exclusions = atlas_read_exclusions(), path = atlas_exclude_path()) {
  if (is.null(exclusions) || !nrow(exclusions)) {
    return(list(kept = occurrences, removed = occurrences[0, , drop = FALSE],
                info = list(list = "none", removed = 0L)))
  }
  drop <- rep(FALSE, nrow(occurrences))
  unknown <- setdiff(unique(exclusions$by), ATLAS_EXCLUDE_BY)
  if (length(unknown)) stop("the drop list names rows by ", paste(unknown, collapse = ", "),
                            "; only ", paste(ATLAS_EXCLUDE_BY, collapse = " or "), call. = FALSE)
  # The day each entry was added ("undated" sorts after every date).
  day <- substr(as.character(exclusions$added_at %||% rep(NA_character_, nrow(exclusions))), 1, 10)
  day[is.na(day) | !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", day)] <- "undated"
  first_day <- rep(NA_character_, nrow(occurrences))
  for (by in unique(exclusions$by)) {
    listed <- exclusions$by == by
    at <- match(atlas_exclude_keys(occurrences, by), exclusions$id[listed])
    hit <- !is.na(at)
    drop <- drop | hit
    # The earliest day of the entries that name a row (match finds the first
    # of a repeated id; an id is listed once per way of naming it).
    this <- day[listed][at[hit]]
    first_day[hit] <- ifelse(is.na(first_day[hit]) | this < first_day[hit], this, first_day[hit])
  }
  kept <- occurrences[!drop, , drop = FALSE]
  rownames(kept) <- NULL
  by_day <- table(first_day[drop])
  list(kept = kept, removed = occurrences[drop, , drop = FALSE],
       info = list(list = basename(path), sha256 = atlas_sha256(path), listed = nrow(exclusions),
                   removed = sum(drop),
                   removed_by_day_added = as.list(stats::setNames(as.integer(by_day), names(by_day)))))
}

#' Add ids to the drop list (once each), then rewrite this machine's current
#' pull without every listed row. Returns what was removed.
atlas_exclude_records <- function(ids, by = ATLAS_EXCLUDE_BY, reason = "", quiet = FALSE) {
  by <- match.arg(by)
  listed <- atlas_read_id_list(ids)
  if (!length(listed)) stop("no ids to exclude", call. = FALSE)
  manifest <- atlas_read_manifest()
  if (is.null(manifest)) stop("nothing pulled yet: run ./atlas pull-occurrences", call. = FALSE)
  existing <- atlas_read_exclusions()
  added <- data.frame(by = by, id = listed, reason = as.character(reason),
                      added_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), stringsAsFactors = FALSE)
  new_ids <- nrow(added)
  if (!is.null(existing)) {
    added <- added[!paste(added$by, added$id) %in% paste(existing$by, existing$id), , drop = FALSE]
    new_ids <- nrow(added)
    for (column in setdiff(names(added), names(existing))) existing[[column]] <- ""
    added <- rbind(existing[, names(added)], added)
  }
  dir.create(dirname(atlas_exclude_path()), recursive = TRUE, showWarnings = FALSE)
  utils::write.table(added, atlas_exclude_path(), sep = "\t", quote = FALSE, row.names = FALSE,
                     fileEncoding = "UTF-8")

  source_file <- atlas_path("occurrences", manifest$file)
  applied <- atlas_apply_exclusions(atlas_read_occurrences(source_file))
  kept <- applied$kept
  stamp <- paste0(sub("-x[0-9a-f]{8}$", "", manifest$stamp), "-x", substr(applied$info$sha256, 1, 8))
  file <- atlas_path("occurrences", sprintf("occurrences-%s.tsv.gz", stamp), create = TRUE)
  atlas_write_tsv_gz(kept, file)
  atlas_write_json(atlas_name_merges(kept), atlas_name_merges_path())
  taxa <- atlas_add_sites(atlas_taxon_fingerprints(kept), kept)
  atlas_write_json(taxa, atlas_path("occurrences", "taxa-latest.json", create = TRUE))
  in_pull <- atlas_exclude_keys(applied$removed, by)
  excluded <- c(applied$info, list(
    from_file = manifest$from_file %||% manifest$file,
    from_sha256 = manifest$from_sha256 %||% atlas_sha256(source_file),
    removed_ids = as.list(sort(as.character(applied$removed$id))),
    not_in_pull = as.list(sort(setdiff(listed, in_pull))),
    names_gone = as.list(sort(setdiff(unique(applied$removed$scientific_name), unique(kept$scientific_name)))),
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ))
  new_manifest <- utils::modifyList(manifest, list(
    stamp = stamp, file = basename(file), records = nrow(kept), taxa = nrow(taxa),
    fingerprint = atlas_fingerprint(kept), exclusions = excluded,
    # The waterfall's last steps follow the rows removed now.
    waterfall = atlas_waterfall_recut(manifest$waterfall, applied$info$removed, nrow(kept)),
    # The pull the cleaning was made from, however many times it is cleaned.
    from_file = excluded$from_file, from_sha256 = excluded$from_sha256
  ))
  atlas_write_json(new_manifest, atlas_path("occurrences", "latest.json", create = TRUE))
  if (!isTRUE(quiet)) {
    message(sprintf("drop list: %d ids (%d new); the pull %s less %d rows -> %s; %d names gone, %d listed ids not in it",
                    applied$info$listed, new_ids, excluded$from_file, applied$info$removed, basename(file),
                    length(excluded$names_gone), length(excluded$not_in_pull)))
  }
  invisible(excluded)
}

#' Retire the drop list, deliberately: it is kept beside the pull under a
#' dated name, and the next pull leaves nothing out.
atlas_clear_exclusions <- function(confirm = FALSE, quiet = FALSE) {
  if (!isTRUE(confirm)) {
    stop("clearing the drop list brings its rows back in the next pull; say --confirm to do it", call. = FALSE)
  }
  path <- atlas_exclude_path()
  if (!file.exists(path)) return(invisible(NULL))
  kept <- atlas_path("occurrences", sprintf("exclude-cleared-%s.tsv", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")))
  file.rename(path, kept)
  if (!isTRUE(quiet)) message("drop list retired to ", basename(kept), "; the next pull leaves nothing out")
  invisible(kept)
}
