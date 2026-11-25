# The training-record and lineage tables of a models version, made on the
# box and deposited with the version (R/deposittables.R builds them).
#
# The archive's training-record table is built from the release's training
# records, for the release named in ATLAS_TRAINING_TABLE_RELEASES only
# (Steve, 2026-11-24); for every other release, a bundle is as it was. The
# tables are made on the machine that can ask .org how the sources stand
# now, by the read-only queries the collection cells made now use
# (R/cellsnow.R), so the tables and the cells say the same of each record:
# a record in groups (a) to (c) keeps its row and has no site, and a record
# in group (d) is left out. They are written into a folder of their own with
# a summary of counts and the files' sums, and the deposit adds them to the
# bundle (archive-release --tables=DIR), each file checked against its sum.

ATLAS_TRAINING_TABLE_RELEASES <- c("20261013T191324Z-fa1b4198")
ATLAS_TRAINING_TABLE_FILES <- c(
  records = "training-records.tsv.gz",
  models = "lineage-models.tsv",
  pulls = "lineage-pulls.tsv",
  removed = "removed-records.tsv"
)
ATLAS_TRAINING_TABLE_SUMMARY <- "training-records.json"

# The memory terra may use for the predictor cover, in GB. On the 5 km grid,
# in a container capped at 1 GB, the step peaked at about 520 MB with this
# (2026-11-25); without it terra took the machine's memory as its own and the
# container was stopped.
ATLAS_TABLES_TERRA_GB <- 0.3

#' Whether a release's models version carries the training-record table.
atlas_training_tables_for <- function(release) {
  as.character(release %||% "") %in% ATLAS_TRAINING_TABLE_RELEASES
}

atlas_training_tables_refuse_release <- function(release) {
  if (!atlas_training_tables_for(release)) {
    stop("the training-record table is made only for release ", paste(ATLAS_TRAINING_TABLE_RELEASES, collapse = ", "),
         ", not ", release %||% "?", call. = FALSE)
  }
}

#' A release's record, and the metrics of its models and its taxa table,
#' fetched from the store into tree (laid out as a data directory), each
#' checked against its hash.
atlas_training_tables_release <- function(store, release, grid = "draft", tree) {
  key <- paste0("releases/", grid, "/", release, ".json")
  manifest <- if (store$exists(key)) atlas_store_text(store, key)
  if (is.null(manifest)) stop("no release ", release, " in the store for the ", grid, " grid", call. = FALSE)
  pattern <- paste0("^(models/", grid, "/(.+/)?[^/]+[.]json|occurrences/taxa-latest[.]json)$")
  # Thousands of small files: fetched as finishing fetches a release, several
  # at once, each checked against its hash.
  wanted <- Filter(function(f) grepl(pattern, f$path %||% ""), manifest$files %||% list())
  dir.create(tree, recursive = TRUE, showWarnings = FALSE)
  atlas_with_data_dir(tree, atlas_fetch_entries(store, wanted))
  manifest
}

# The records removed from the frozen release's pull under non-fungal
# sequence names on 2026-10-13: the rows of the pull before that cleaning
# that the release's pull no longer holds, checked against the drop list's
# entries of that cleaning.
ATLAS_REMOVED_RECORDS <- list(
  before = "x2dd5cb30", after = "x73b85b36", records = 54L, source = "iNaturalist", names = 51L,
  added_at = "2026-10-13T13:34", reason = "non-fungal sequence names, 2026-10-13"
)
ATLAS_REMOVED_COLUMNS <- c("source", "source_id", "name")

#' The removed-records table: the rows of before (a pull) that after (the
#' pull made from it by the drop list) does not hold, with their source,
#' number and name as before lists them. Stops, giving the counts, unless
#' there are expect$records of them, all from expect$source, under
#' expect$names names, and unless their row ids are exactly the drop list's
#' (exclude: by, id, reason, added_at) entries added at expect$added_at with
#' expect$reason (only the number that differ is given).
atlas_removed_records <- function(before, after, exclude, expect = ATLAS_REMOVED_RECORDS) {
  key <- function(d) paste(d$source, d$observation_id, sep = "\x1f")
  gone <- before[!key(before) %in% key(after), , drop = FALSE]
  sources <- unique(gone$source)
  names <- length(unique(gone$scientific_name))
  if (nrow(gone) != expect$records || !identical(sources, expect$source) || names != expect$names) {
    stop(sprintf("removed records: %d rows from %s under %d names, not %d from %s under %d; nothing written",
                 nrow(gone), if (length(sources)) paste(sources, collapse = " and ") else "no source", names,
                 expect$records, expect$source, expect$names), call. = FALSE)
  }
  if (is.null(exclude)) stop("removed records: no drop list on this machine to check them against", call. = FALSE)
  batch <- exclude[startsWith(as.character(exclude$added_at), expect$added_at) &
                     as.character(exclude$reason) == expect$reason, , drop = FALSE]
  if (any(batch$by != "id")) stop("removed records: the drop list's entries of that cleaning are not all by id", call. = FALSE)
  differ <- length(union(setdiff(as.character(gone$id), as.character(batch$id)),
                         setdiff(as.character(batch$id), as.character(gone$id))))
  if (differ) {
    stop("removed records: ", differ, " ids differ between the pulls and the drop list's entries of that cleaning",
         call. = FALSE)
  }
  out <- data.frame(source = gone$source, source_id = as.character(gone$observation_id), name = gone$scientific_name,
                    stringsAsFactors = FALSE)
  out <- out[order(out$source, out$source_id), , drop = FALSE]
  rownames(out) <- NULL
  list(table = out, summary = list(records = nrow(out), source = sources, names = names,
                                   ids_differing_from_the_drop_list = 0L,
                                   from_pull = expect$before, to_pull = expect$after))
}

#' The cells made now (atlas_read_cells_now's summary) that the tables are
#' made beside: the same release, the same privacy list (privacy_list's
#' sha256), and asked within a day of the tables' status.
atlas_training_tables_check_cells_now <- function(cells_now, release, privacy_list, checked_at) {
  if (is.null(cells_now)) stop("the tables are made beside cells made now: give --cells-now=DIR", call. = FALSE)
  if (!identical(cells_now$release, release)) {
    stop("the cells made now are release ", cells_now$release %||% "?", "'s, not ", release, call. = FALSE)
  }
  if (!identical(cells_now$privacy_list$sha256, atlas_sha256(privacy_list))) {
    stop("the cells made now were checked with another privacy list than ", privacy_list, call. = FALSE)
  }
  atlas_training_tables_within_a_day(cells_now$checked_at, checked_at)
}

atlas_training_tables_within_a_day <- function(a, b) {
  t <- as.POSIXct(c(a %||% NA, b %||% NA), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (anyNA(t) || abs(as.numeric(difftime(t[[1]], t[[2]], units = "hours"))) > 24) {
    stop("the cells made now (", a %||% "?", ") and the tables (", b %||% "?",
         ") were not made within a day of each other", call. = FALSE)
  }
  invisible(TRUE)
}

#' Make the tables and write them, with their summary, into dir.
#'
#' status is how the sources stand now (atlas_status_paged); listed the
#' privacy-list record keys whose sites are blank whatever the status says
#' (the release's own list and this machine's latest); cells_now the summary
#' of the cells made beside them. removed is atlas_removed_records' answer.
#' sequences and sequences_exported_on as atlas_deposit_training_table takes
#' them. names and opt_outs, when given, make the contributors table
#' (atlas_contributors_table). The summary counts the taxa whose rows differ from the release's
#' taxa table, when tree holds it. Stops, writing nothing, when the status
#' answer looks incomplete: more than ATLAS_CELLS_NOW_MAX_UNANSWERED of the
#' table's iNaturalist or Mushroom Observer records with no cached answer, or
#' no record deleted at the source at all.
atlas_training_tables_make <- function(store, manifest, tree, land, status, dir, listed = character(), grid = "draft",
                                       printed = NULL, removed = NULL, cells_now = NULL, sequences = NULL,
                                       sequences_exported_on = NA_character_, names = NULL, opt_outs = NULL,
                                       jobs = atlas_deposit_jobs(store, grid), read_pull = atlas_block_read_pull) {
  atlas_training_tables_refuse_release(manifest$id)
  if (!length(status$deleted)) {
    stop("the status answer lists no record deleted at the source; nothing written", call. = FALSE)
  }
  if (is.null(removed)) stop("the tables are made with the removed-records table", call. = FALSE)
  if (!is.null(cells_now)) atlas_training_tables_within_a_day(cells_now$checked_at, status$checked_at)
  seen <- NULL
  judge <- function(records) {
    seen <<- records
    atlas_deposit_judge_status(status, listed)(records)
  }
  taxa_path <- file.path(tree, "occurrences", "taxa-latest.json")
  taxa <- if (file.exists(taxa_path)) as.data.frame(jsonlite::fromJSON(taxa_path)) else NULL
  built <- atlas_deposit_training_table(store, manifest, tree, land, grid, deleted_on = substr(status$checked_at, 1L, 10L),
                                        sequences = sequences, sequences_exported_on = sequences_exported_on,
                                        taxa = taxa, jobs = jobs, read_pull = read_pull, judge = judge)
  probe <- data.frame(source = seen$source, observation_id = seen$source_id, stringsAsFactors = FALSE)
  answered <- atlas_cells_now_answered(probe, status)
  unanswered <- c(iNaturalist = mean(!answered[probe$source == ATLAS_INAT_SOURCE]),
                  `Mushroom Observer` = mean(!answered[probe$source == ATLAS_MO_SOURCE]))
  unanswered[is.nan(unanswered)] <- 0
  if (any(unanswered > ATLAS_CELLS_NOW_MAX_UNANSWERED)) {
    stop(sprintf("the status answer looks incomplete: no cached answer now for %s of the table's records; nothing written",
                 paste(sprintf("%.1f per cent of %s", 100 * unanswered, names(unanswered)), collapse = " and ")),
         call. = FALSE)
  }
  lineage <- atlas_deposit_lineage(built$fitting, jobs, printed)
  for (t in list(lineage$models, lineage$pulls)) atlas_deposit_refuse(t, names(t), manifest)
  atlas_deposit_refuse(removed$table, ATLAS_REMOVED_COLUMNS, manifest)
  if (any(paste(removed$table$source, removed$table$source_id) %in% paste(built$table$source, built$table$source_id))) {
    stop("a removed record is in the training-record table", call. = FALSE)
  }
  contributors <- if (!is.null(names)) atlas_contributors_table(built$table, names, opt_outs)

  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (length(list.files(dir))) stop(dir, " is not empty: the tables are written into an empty directory", call. = FALSE)
  paths <- stats::setNames(file.path(dir, ATLAS_TRAINING_TABLE_FILES), names(ATLAS_TRAINING_TABLE_FILES))
  atlas_write_tsv_gz(built$table, paths[["records"]])
  write_tsv <- function(table, path) {
    utils::write.table(table, path, sep = "\t", quote = FALSE, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  }
  write_tsv(lineage$models, paths[["models"]])
  write_tsv(lineage$pulls, paths[["pulls"]])
  write_tsv(removed$table, paths[["removed"]])
  if (!is.null(contributors)) {
    paths <- c(paths, contributors = file.path(dir, ATLAS_CONTRIBUTORS_FILE))
    write_tsv(contributors$table, paths[["contributors"]])
  }
  summary <- c(
    list(release = manifest$id, checked_at = status$checked_at, checked_on = substr(status$checked_at, 1L, 10L),
         cells_now_checked_at = cells_now$checked_at %||% NA_character_, privacy_list_records = length(listed)),
    built$summary,
    list(
      lineage = list(pull_column = lineage$pull_column, models = nrow(lineage$models), pulls = nrow(lineage$pulls),
                     printed_pull_values_checked = length(printed) > 0L),
      removed_records = removed$summary,
      contributors = contributors$summary,
      files = lapply(stats::setNames(as.list(paths), basename(paths)), function(p) list(sha256 = atlas_sha256(p)))
    )
  )
  atlas_write_json(summary, file.path(dir, ATLAS_TRAINING_TABLE_SUMMARY))
  invisible(summary)
}

#' A pull file on this machine, by the last part of its stamp ("x73b85b36").
atlas_pull_by_stamp <- function(suffix) {
  files <- list.files(atlas_path("occurrences"), pattern = paste0("^occurrences-.*-", suffix, "[.]tsv[.]gz$"))
  if (length(files) != 1L) stop(length(files), " pull files on this machine end in ", suffix, ", not 1", call. = FALSE)
  files
}

#' A private input file (tab-separated, with a header), or NULL.
atlas_read_private_tsv <- function(path, columns) {
  if (is.null(path)) return(NULL)
  if (!file.exists(path)) stop("no file at ", path, call. = FALSE)
  out <- utils::read.delim(path, sep = "\t", quote = "", comment.char = "", na.strings = "", colClasses = "character",
                           check.names = FALSE, stringsAsFactors = FALSE, encoding = "UTF-8")
  missing <- setdiff(columns, names(out))
  if (length(missing)) stop(basename(path), " lacks columns: ", paste(missing, collapse = ", "), call. = FALSE)
  out
}

#' The sequence approvals file (sequence_id, approved), or NULL.
atlas_read_sequence_approvals <- function(path) atlas_read_private_tsv(path, c("sequence_id", "approved"))

#' On the box: make a release's tables as the sources stand now, into dir,
#' beside the cells made now in cells_now (made with the release's own
#' privacy list at privacy_list). Read-only on the store and on .org; holds
#' the box's orchestrator lock, and works in a folder of its own under the
#' data directory, removed when it ends however it ends.
atlas_training_tables_run <- function(dir, release, privacy_list, cells_now, store = atlas_store(), grid = "draft",
                                      run = atlas_run_sql, host = atlas_sql_host(), printed = NULL,
                                      sequences = NULL, sequences_exported_on = NA_character_, names = NULL,
                                      opt_outs = NULL, work_root = atlas_path("work"), status = NULL) {
  atlas_training_tables_refuse_release(release)
  if (!is.null(sequences) && !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", sequences_exported_on %||% "")) {
    stop("the sequence approvals need the date they were exported (--sequences-exported-on=YYYY-MM-DD)", call. = FALSE)
  }
  # Everything it writes is readable by its own user only: files 0600,
  # folders 0700, its working folder included.
  old_mask <- Sys.umask("077")
  on.exit(Sys.umask(old_mask), add = TRUE)
  work <- file.path(work_root, basename(tempfile("training-tables-")))
  dir.create(work, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  atlas_with_orchestrator_lock("training-tables", 2, {
    tree <- file.path(work, "tree")
    manifest <- atlas_training_tables_release(store, release, grid, tree)
    cells <- atlas_read_cells_now(cells_now, manifest)$summary
    if (is.null(privacy_list) || !file.exists(privacy_list)) stop("no privacy list at ", privacy_list %||% "?", call. = FALSE)
    listed <- unique(c(atlas_read_privacy(privacy_list), atlas_read_privacy() %||% character()))
    after <- atlas_pull_by_stamp(ATLAS_REMOVED_RECORDS$after)
    if (!identical(after, manifest$pull$file)) {
      stop("the pull ending in ", ATLAS_REMOVED_RECORDS$after, " is not release ", release, "'s", call. = FALSE)
    }
    exclude <- if (file.exists(atlas_exclude_path())) {
      utils::read.delim(atlas_exclude_path(), colClasses = "character", quote = "", na.strings = "")
    }
    removed <- atlas_removed_records(
      atlas_read_occurrences(atlas_path("occurrences", atlas_pull_by_stamp(ATLAS_REMOVED_RECORDS$before))),
      atlas_read_occurrences(atlas_path("occurrences", after)), exclude
    )
    # terra sizes its chunks by the machine's memory, not the container's cap:
    # held to ATLAS_TABLES_TERRA_GB, the predictor cover streams through it.
    old <- terra::terraOptions(print = FALSE)$memmax
    terra::terraOptions(memmax = ATLAS_TABLES_TERRA_GB)
    on.exit(terra::terraOptions(memmax = old), add = TRUE)
    land <- terra::rast(atlas_archive_block_land(store, grid, manifest$layers_key, work))
    status <- status %||% atlas_status_paged(run, host, max_m = atlas_pull_max_accuracy(manifest$pull))
    atlas_training_tables_check_cells_now(cells, release, privacy_list, status$checked_at)
    atlas_training_tables_make(store, manifest, tree, land, status, dir, listed = listed, grid = grid,
                               printed = printed, removed = removed, cells_now = cells,
                               sequences = atlas_read_sequence_approvals(sequences),
                               sequences_exported_on = sequences_exported_on,
                               names = atlas_read_private_tsv(names, c("source", "source_id", "contributor")),
                               opt_outs = atlas_read_private_tsv(opt_outs, c("source", "contributor")))
  })
}

#' A bundle with the tables made by atlas_training_tables_run, each checked
#' against the summary's sum, the summary against the bundle's release, and
#' each table again for its columns and for any value shaped like a
#' coordinate. The bundle must already hold the cells made now, made within
#' a day of the tables. Its key changes with them. The tables' own files are
#' not changed.
atlas_archive_bundle_tables <- function(bundle, dir) {
  atlas_training_tables_refuse_release(bundle$release$id)
  if (length(bundle$tables)) stop("the bundle already holds the training-record table", call. = FALSE)
  if (!length(bundle$cells_now)) {
    stop("the tables go into a bundle with its cells made now: give --cells-now as well", call. = FALSE)
  }
  summary_path <- file.path(dir, ATLAS_TRAINING_TABLE_SUMMARY)
  if (!file.exists(summary_path)) stop("no ", ATLAS_TRAINING_TABLE_SUMMARY, " in ", dir, call. = FALSE)
  summary <- jsonlite::fromJSON(summary_path, simplifyVector = FALSE)
  if (!identical(summary$release, bundle$release$id)) {
    stop("the tables were made for release ", summary$release %||% "?", ", not ", bundle$release$id, call. = FALSE)
  }
  atlas_training_tables_within_a_day(bundle$cells_now$checked_at, summary$checked_at)
  names <- unname(ATLAS_TRAINING_TABLE_FILES)
  if (ATLAS_CONTRIBUTORS_FILE %in% names(summary$files)) names <- c(names, ATLAS_CONTRIBUTORS_FILE)
  if (!setequal(names(summary$files %||% list()), names)) stop("the tables' summary does not list its files", call. = FALSE)
  for (name in names) {
    path <- file.path(dir, name)
    if (!file.exists(path) || !identical(atlas_sha256(path), summary$files[[name]]$sha256)) {
      stop("the table ", name, " does not match its summary", call. = FALSE)
    }
  }
  if (any(c(names, ATLAS_TRAINING_TABLE_SUMMARY) %in% names(bundle$sources))) {
    stop("the bundle already has a file named as one of the tables", call. = FALSE)
  }
  read <- function(name) {
    con <- if (grepl("[.]gz$", name)) gzfile(file.path(dir, name)) else file.path(dir, name)
    utils::read.delim(con, sep = "\t", quote = "", comment.char = "", na.strings = character(),
                      colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE)
  }
  atlas_deposit_refuse(read(ATLAS_TRAINING_TABLE_FILES[["records"]]), ATLAS_TRAINING_COLUMNS)
  column <- summary$lineage$pull_column %||% "pull_fingerprint"
  swap <- function(columns) replace(columns, columns == "pull_fingerprint", column)
  atlas_deposit_refuse(read(ATLAS_TRAINING_TABLE_FILES[["models"]]), swap(ATLAS_LINEAGE_MODEL_COLUMNS))
  atlas_deposit_refuse(read(ATLAS_TRAINING_TABLE_FILES[["pulls"]]), swap(ATLAS_LINEAGE_PULL_COLUMNS))
  atlas_deposit_refuse(read(ATLAS_TRAINING_TABLE_FILES[["removed"]]), ATLAS_REMOVED_COLUMNS)
  if (ATLAS_CONTRIBUTORS_FILE %in% names) atlas_deposit_refuse(read(ATLAS_CONTRIBUTORS_FILE), ATLAS_CONTRIBUTOR_COLUMNS)
  added <- c(names, ATLAS_TRAINING_TABLE_SUMMARY)
  bundle$sources <- c(bundle$sources, stats::setNames(file.path(dir, added), added))
  bundle$tables <- summary[setdiff(names(summary), "files")]
  bundle$key <- digest::digest(paste(bundle$key, atlas_sha256(summary_path)), algo = "sha256")
  bundle
}

#' What the README says of the tables: only for a version that holds them.
atlas_archive_tables_lines <- function(bundle) {
  t <- bundle$tables
  if (!length(t)) return(character())
  pull <- if (identical(t$lineage$pull_column, "pull_file_sha256")) {
    "the sha256 of the file of the pull it was fitted on (`pull_file_sha256`)"
  } else {
    paste("the fingerprint of the pull it was fitted on (`pull_fingerprint`: the hash of every pulled record at once,",
          "as `pull.json` gives it for the release's own pull)")
  }
  sequences <- if (isTRUE((t$rows_with_sequence_id %||% 0L) > 0L)) {
    sprintf("`sequence_id` is given where the sequence is approved at its source, as .org said on %s.",
            t$sequence_ids$exported_on)
  } else {
    "`sequence_id` is left blank in this version."
  }
  c(
    sprintf(paste(
      "`training-records.tsv.gz` lists the records the models were trained on: one row per record, with its source,",
      "its number at that source (`source_id`), its taxon, and `site_id`, a number shared by the records of one",
      "detection site. Site numbers are the table's own, given in the table's order, and say nothing of where a site is.",
      "`site_id` is blank for a record whose location its source hides, obscures or may hide, and Mushroom Observer",
      "records the source no longer holds are left out, as the sources said on %s. %s"), t$checked_on, sequences),
    sprintf(paste(
      "`lineage-models.tsv` gives each model's fitting job, %s, and when the model was built;",
      "`lineage-pulls.tsv` gives each pull with each job that fitted models from it and how many.",
      "`training-records.json` gives the tables' counts."), pull),
    sprintf(paste(
      "`removed-records.tsv` lists the %d records removed from the pull on 13 October 2026, before the models were",
      "fitted, under non-fungal sequence names (`source`, `source_id`, and `name`, the name as listed)."),
      as.integer(t$removed_records$records %||% 0L)),
    if (length(t$contributors)) {
      paste("`contributors.tsv` gives, by source, how many of the training-record table's rows each contributor gave;",
            "records whose contributor asked not to be named, gave no public name, or is known only by an email address",
            "are counted together as `anonymous`.")
    },
    paste("The training-record table (`training-records.tsv.gz`) is released under CC0 1.0; every other file in this",
          "version under CC BY-SA 4.0.")
  )
}

# ---- the contributors table ---------------------------------------------------

ATLAS_CONTRIBUTOR_COLUMNS <- c("source", "contributor", "training_records")
ATLAS_CONTRIBUTORS_FILE <- "contributors.tsv"
ATLAS_ANONYMOUS <- "anonymous"

#' The contributors table: how many of the training-record table's rows each
#' contributor gave, by source. names is the private names file (source,
#' source_id, contributor), one row per record; opt_outs the private list
#' (source, contributor) of people who asked not to be named. A record is
#' counted under "anonymous", one row per source, when its contributor is
#' on that list, has no name in the file, or has a name shaped like an email
#' address. Returns list(table, summary).
atlas_contributors_table <- function(training, names, opt_outs = NULL) {
  missing <- setdiff(c("source", "source_id", "contributor"), names(names))
  if (length(missing)) stop("the names file lacks columns: ", paste(missing, collapse = ", "), call. = FALSE)
  key <- function(a, b) paste(a, b, sep = "\x1f")
  if (anyDuplicated(key(names$source, names$source_id))) {
    stop("the names file names a record more than once", call. = FALSE)
  }
  who <- trimws(as.character(names$contributor[match(key(training$source, training$source_id),
                                                     key(names$source, names$source_id))]))
  unnamed <- is.na(who) | !nzchar(who)
  email <- !unnamed & grepl("@", who, fixed = TRUE)
  out_list <- if (is.null(opt_outs)) character() else key(opt_outs$source, trimws(opt_outs$contributor))
  opted <- !unnamed & !email & key(training$source, who) %in% out_list
  anonymous <- unnamed | email | opted
  who[anonymous] <- ATLAS_ANONYMOUS
  counts <- stats::aggregate(list(training_records = rep(1L, nrow(training))),
                             list(source = training$source, contributor = who), sum)
  counts <- counts[order(counts$source, -counts$training_records, counts$contributor), ATLAS_CONTRIBUTOR_COLUMNS,
                   drop = FALSE]
  rownames(counts) <- NULL
  if (sum(counts$training_records) != nrow(training)) stop("the contributors table does not add up", call. = FALSE)
  atlas_deposit_refuse(counts, ATLAS_CONTRIBUTOR_COLUMNS)
  summary <- list(
    rows = nrow(counts), records = nrow(training),
    named = as.list(tapply(counts$contributor != ATLAS_ANONYMOUS, counts$source, sum)),
    anonymous_records = list(no_name = sum(unnamed), email_like = sum(email), asked_not_to_be_named = sum(opted))
  )
  list(table = counts, summary = summary)
}

# ---- the second licence ---------------------------------------------------------

# The licences of a version with the training-record table (Steve,
# 2026-10-25): CC BY-SA 4.0 for every file and CC0 1.0 for the table.
# Zenodo's deposit API takes one licence, so the code writes the first and a
# person adds the second on the draft at zenodo.org before it is published.
ATLAS_TABLES_LICENCES <- c("cc-by-sa-4.0", "cc0-1.0")
ATLAS_TABLES_LICENCE_CONFIRMATION <- "both licences are on the draft: yes"

#' The line the depositor is shown once such a draft is made.
atlas_archive_licence_step <- function(url) {
  paste0("Before publishing: add CC0 1.0 as a second licence on the draft at ", url,
         " (CC BY-SA 4.0 is already on it).")
}

#' The licences a draft read back from Zenodo shows: list(ids, listed), where
#' listed is FALSE when it shows only the deposit API's single licence, from
#' which a second cannot be read. Legacy ids are read as the current ones.
atlas_archive_draft_licences <- function(metadata) {
  id_of <- function(x) {
    value <- if (is.list(x)) x$id %||% x$identifier %||% NA else x
    value <- tolower(trimws(as.character(value %||% NA)))
    if (value %in% c("cc-zero", "cc0", "cc0-1.0")) "cc0-1.0" else value
  }
  lists <- Filter(function(x) is.list(x) && length(x) && is.null(names(x)), list(metadata$rights, metadata$licenses))
  if (length(lists)) return(list(ids = unique(vapply(unlist(lists, recursive = FALSE), id_of, "")), listed = TRUE))
  single <- metadata$license
  list(ids = if (is.null(single)) character() else id_of(single), listed = FALSE)
}

#' Before a draft that needs two licences is published: refuse unless the
#' draft, read back, lists both; when Zenodo shows only one licence, refuse
#' unless the person typed ATLAS_TABLES_LICENCE_CONFIRMATION. Returns how it
#' was checked, for the ledger.
atlas_archive_check_licences <- function(z, entry, confirmed = NULL) {
  needed <- unlist(entry$licences)
  draft <- z$call("GET", paste0("/deposit/depositions/", entry$deposition_id))
  shown <- atlas_archive_draft_licences(draft$metadata %||% list())
  if (isTRUE(shown$listed)) {
    missing <- setdiff(needed, shown$ids)
    if (length(missing)) {
      stop("not published: the draft at ", entry$url, " lacks the licence ", paste(missing, collapse = " and "),
           "; add it there, then publish again", call. = FALSE)
    }
    return("both licences read back from the draft")
  }
  if (identical(trimws(as.character(confirmed %||% "")), ATLAS_TABLES_LICENCE_CONFIRMATION)) {
    return("the second licence confirmed by the person publishing")
  }
  stop("not published: Zenodo's deposit API shows one licence for the draft (",
       if (length(shown$ids)) shown$ids else "none", "), so the second cannot be read back. Check on ", entry$url,
       " that it carries both CC BY-SA 4.0 and CC0 1.0, then publish again with --licences-confirmed=\"",
       ATLAS_TABLES_LICENCE_CONFIRMATION, "\"", call. = FALSE)
}
