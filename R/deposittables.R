# Tables deposited with a models version (R/archive.R): the training-record
# table, built from the release's training records, and the lineage table,
# which says which job and which pull fitted each model.
#
# Both are built from the store's job records and pulls, and from the
# bundle's own tree, by reading only. A model's training records are its
# presence records in the pull its job fitted it on, found as finishing finds
# a model's pull (R/blocks.R: the newest job planned before the model was
# built that lists it, then any other kept pull with the same record set):
# the records of its taxon in its detection sites the predictors cover.

ATLAS_TRAINING_COLUMNS <- c("source", "source_id", "taxon", "sequence_id", "site_id")
ATLAS_LINEAGE_MODEL_COLUMNS <- c("algorithm", "taxon", "job", "pull_fingerprint", "built_at")
ATLAS_LINEAGE_PULL_COLUMNS <- c("pull_fingerprint", "stamp", "pulled_at", "records", "job", "models")

#' Each model of a release with the job and pull that fitted it. tree is a
#' directory laid out like a data directory holding the release's model
#' metrics (a bundle's tree). Returns a data frame: taxon, algorithm, job,
#' pull (the pull object's sha256), pull_fingerprint (the whole-pull
#' fingerprint the job's plan recorded), built_at, thin_km, and by_job (FALSE
#' when the record set was found in another job's pull than the one that
#' lists it); NA job for a model whose record set no kept pull holds.
atlas_deposit_fitting <- function(store, manifest, tree, grid = "draft", jobs = atlas_deposit_jobs(store, grid),
                                  read_pull = atlas_block_read_pull) {
  entries <- Filter(function(e) !isTRUE(e$refused) && is.character(e$fingerprint) && length(e$fingerprint) == 1L,
                    manifest$index %||% list())
  rows <- lapply(entries, function(e) {
    algorithm <- e$algorithm %||% "maxnet"
    path <- atlas_with_data_dir(tree, atlas_model_path(e$taxon, grid, ".json", algorithm))
    metrics <- if (file.exists(path)) jsonlite::fromJSON(path, simplifyVector = FALSE) else list()
    settings <- if (is.list(metrics$settings)) metrics$settings else list()
    thin <- suppressWarnings(as.numeric(unlist(settings$thin_km %||% metrics$thin_km)))
    data.frame(taxon = e$taxon, algorithm = algorithm, fingerprint = e$fingerprint,
               built_at = atlas_json_string(metrics$built_at) %||% "",
               thin_km = if (length(thin) == 1L && is.finite(thin)) thin else ATLAS_SITE_KM,
               stringsAsFactors = FALSE)
  })
  models <- do.call(rbind, rows)
  if (is.null(models)) {
    return(data.frame(taxon = character(), algorithm = character(), job = character(), pull = character(),
                      pull_fingerprint = character(), built_at = character(), thin_km = numeric(),
                      by_job = logical(), stringsAsFactors = FALSE))
  }
  models$job <- NA_character_
  models$pull <- NA_character_
  models$pull_fingerprint <- NA_character_
  models$by_job <- FALSE
  key <- paste(models$taxon, models$algorithm, sep = "\x1f")
  prints <- list()
  print_of <- function(j, taxa) {
    have <- prints[[jobs[[j]]$sha256]]
    need <- setdiff(taxa, names(have))
    if (length(need)) {
      pull <- read_pull(store, jobs[[j]]$sha256, grid)
      if (!is.null(pull)) have <- c(have, atlas_fingerprints_for(pull$occurrences, need))
      prints[[jobs[[j]]$sha256]] <<- have
    }
    have[taxa]
  }
  for (i in seq_len(nrow(models))) {
    fitted_by <- which(vapply(jobs, function(j) key[[i]] %in% j$fitted && j$created_at <= models$built_at[[i]],
                              logical(1)))
    first <- utils::head(fitted_by, 1L)
    for (j in c(first, setdiff(seq_along(jobs), first))) {
      if (identical(unname(print_of(j, models$taxon[[i]])), models$fingerprint[[i]])) {
        models$job[[i]] <- jobs[[j]]$id
        models$pull[[i]] <- jobs[[j]]$sha256
        models$pull_fingerprint[[i]] <- jobs[[j]]$pull_fingerprint
        models$by_job[[i]] <- length(first) && j == first
        break
      }
    }
  }
  models$fingerprint <- NULL
  models
}

#' The store's jobs with their pulls, newest first: as atlas_block_job_pulls,
#' with the whole-pull fingerprint, stamp, time and record count each job's
#' plan recorded of its pull.
atlas_deposit_jobs <- function(store, grid = "draft") {
  keys <- grep("/job[.]json$", store$list(paste0("jobs/", grid, "/")), value = TRUE)
  out <- list()
  for (key in keys) {
    job <- tryCatch(atlas_store_text(store, key), error = function(e) NULL)
    if (!is.list(job)) next
    pulls <- Filter(function(e) grepl("^occurrences/occurrences-.*[.]tsv[.]gz$", e$path %||% ""), job$inputs %||% list())
    if (!length(pulls)) next
    summary <- if (is.list(job$pull)) job$pull else list()
    out[[length(out) + 1L]] <- list(
      id = job$id, created_at = atlas_json_string(job$created_at) %||% "", sha256 = pulls[[1]]$sha256,
      pull_fingerprint = atlas_json_string(summary$fingerprint) %||% NA_character_,
      stamp = atlas_json_string(summary$stamp) %||% "", pulled_at = atlas_json_string(summary$pulled_at) %||% "",
      records = suppressWarnings(as.integer(unlist(summary$records)))[1],
      fitted = vapply(job$tasks %||% list(), function(t) {
        paste(t$taxon, atlas_json_string(t$algorithm) %||% "maxnet", sep = "\x1f")
      }, "")
    )
  }
  out[order(vapply(out, function(j) j$created_at, ""), decreasing = TRUE)]
}

#' A taxon's training records in a pull: the rows of occurrences (by number)
#' of its records in its detection sites that the predictors cover (land),
#' with each one's site in that pull.
atlas_deposit_taxon_records <- function(name, occurrences, points, kept_rows, land, thin_km = ATLAS_SITE_KM) {
  points <- atlas_ensure_sites(points, thin_km)
  sites <- attr(points, "sites")
  mine <- which(points$scientific_name == name)
  found <- unique(points$site[mine])
  if (!length(found)) return(data.frame(row = integer(), site = integer()))
  covered <- terra::extract(land, as.matrix(sites[found, c("x", "y"), drop = FALSE]))[, 1] %in% c(TRUE, 1)
  trained <- mine[points$site[mine] %in% found[covered]]
  data.frame(row = kept_rows[trained], site = points$site[trained])
}

#' The training-record table of a release, and its summary.
#'
#' privacy: the private list (source, observation_id, privacy) of records
#' whose place their source hides or may hide: their site_id is left blank.
#' deleted: Mushroom Observer records the source no longer holds (source,
#' observation_id), with deleted_on, the date that list was read: they are
#' left out. sequences: the approval of each sequence id (sequence_id,
#' approved), with sequences_exported_on, the date it was exported: a
#' sequence id is listed only where approved is 1, and is blank for any other
#' value or an id not in it (all blank when sequences is NULL). taxa: the release's taxa table (scientific_name,
#' records), for the summary's count of taxa whose rows differ from it.
#'
#' judge, in place of privacy and deleted: a function of the table's records
#' (source, source_id) that returns list(hidden, deleted), one logical each
#' (atlas_deposit_judge_status judges them by how the sources stand now).
#'
#' Stops, with counts, if a taxon's models were trained on different records,
#' if a record trained two taxa, if a record's site membership differs
#' between two pulls, or if any model's record set is in no kept pull.
atlas_deposit_training_table <- function(store, manifest, tree, land, grid = "draft", privacy = NULL,
                                         deleted = NULL, deleted_on = NA_character_, sequences = NULL,
                                         sequences_exported_on = NA_character_,
                                         taxa = NULL, jobs = atlas_deposit_jobs(store, grid),
                                         read_pull = atlas_block_read_pull,
                                         judge = atlas_deposit_judge_lists(privacy, deleted)) {
  fitting <- atlas_deposit_fitting(store, manifest, tree, grid, jobs = jobs, read_pull = read_pull)
  if (anyNA(fitting$job)) {
    stop("the training-record table is not built: the record sets of ", sum(is.na(fitting$job)),
         " models are in no kept pull", call. = FALSE)
  }
  records <- list()
  for (sha in unique(fitting$pull)) {
    pull <- read_pull(store, sha, grid)
    occ <- pull$occurrences
    on_grid <- which(!is.na(terra::cellFromXY(atlas_grid_template(grid),
                                           atlas_project_points(occ$latitude, occ$longitude))))
    on_pull <- fitting[fitting$pull == sha, , drop = FALSE]
    # A pull's detection sites are found once for each site spacing its models used.
    sited <- list()
    for (i in seq_len(nrow(on_pull))) {
      spacing <- as.character(on_pull$thin_km[[i]])
      if (is.null(sited[[spacing]])) sited[[spacing]] <- atlas_ensure_sites(pull$points, on_pull$thin_km[[i]])
      found <- atlas_deposit_taxon_records(on_pull$taxon[[i]], occ, sited[[spacing]], on_grid, land,
                                           on_pull$thin_km[[i]])
      records[[length(records) + 1L]] <- data.frame(
        taxon = on_pull$taxon[[i]], algorithm = on_pull$algorithm[[i]], pull = sha,
        source = occ$source[found$row], source_id = as.character(occ$observation_id[found$row]),
        sequence_id = as.character(occ$sequence_id[found$row] %||% rep(NA, nrow(found))),
        site = paste(sha, found$site), stringsAsFactors = FALSE
      )
    }
    rm(pull)
  }
  all <- do.call(rbind, records)
  all$record <- paste(all$source, all$source_id, sep = "\x1f")

  # Each taxon's models were trained on the same records.
  per_model <- split(all$record, paste(all$taxon, all$algorithm, sep = "\x1f"))
  taxon_of_model <- sub("\x1f.*$", "", names(per_model))
  union <- tapply(all$record, all$taxon, function(r) sort(unique(r)))
  differ <- sum(vapply(seq_along(per_model), function(i) {
    !identical(sort(unique(per_model[[i]])), union[[taxon_of_model[[i]]]])
  }, logical(1)))
  if (differ) stop("the training-record table is not built: ", differ,
                   " models were trained on other records than their taxon's other models", call. = FALSE)
  # A record trains one taxon.
  two <- sum(tapply(all$taxon, all$record, function(t) length(unique(t))) > 1L)
  if (two) stop("the training-record table is not built: ", two, " records trained two taxa", call. = FALSE)
  # A record's site membership is the same in every pull it trained from.
  rows <- all[!duplicated(all[c("record", "pull")]), , drop = FALSE]
  clash <- 0L
  for (taxon in unique(rows$taxon[duplicated(rows$record)])) {
    mine <- rows[rows$taxon == taxon, , drop = FALSE]
    by_pull <- split(mine, mine$pull)
    if (length(by_pull) < 2L) next
    groups <- lapply(by_pull, function(p) sort(vapply(split(p$record, p$site), function(r) paste(sort(r), collapse = "|"), "")))
    if (length(unique(lapply(groups, unname))) > 1L) clash <- clash + 1L
  }
  if (clash) stop("the training-record table is not built: the site membership of ", clash,
                  " taxa differs between the pulls they trained from", call. = FALSE)

  kept <- rows[!duplicated(rows$record), c("source", "source_id", "taxon", "sequence_id", "site", "record"), drop = FALSE]
  # Left out: records the source no longer holds (Mushroom Observer).
  judged <- judge(kept[c("source", "source_id")])
  if (length(judged$hidden) != nrow(kept) || length(judged$deleted) != nrow(kept) ||
      anyNA(judged$hidden) || anyNA(judged$deleted)) {
    stop("the training-record table is not built: the records were not all judged", call. = FALSE)
  }
  hidden <- kept$record[judged$hidden]
  out_deleted <- judged$deleted
  summary_deleted <- list(left_out = sum(out_deleted), in_another_privacy_group = sum(out_deleted & judged$hidden),
                          list_read_on = deleted_on)
  kept <- kept[!out_deleted, , drop = FALSE]
  approved <- if (is.null(sequences)) character() else
    as.character(sequences$sequence_id[trimws(as.character(sequences$approved)) %in% "1"])
  known <- if (is.null(sequences)) character() else as.character(sequences$sequence_id)
  has <- !is.na(kept$sequence_id) & nzchar(kept$sequence_id)
  summary_sequences <- list(
    exported_on = sequences_exported_on,
    filled = sum(has & kept$sequence_id %in% approved),
    blank_not_approved = sum(has & kept$sequence_id %in% known & !kept$sequence_id %in% approved),
    blank_not_in_the_approvals = sum(has & !kept$sequence_id %in% known),
    blank_no_sequence = sum(!has)
  )
  kept$sequence_id[!has | !kept$sequence_id %in% approved] <- ""
  kept <- kept[order(kept$source, kept$source_id), , drop = FALSE]
  # Sites numbered in the table's own order, so a number says nothing of where
  # a site is; blank where the source hides or may hide the place.
  blank <- kept$record %in% hidden
  keyed <- ifelse(blank, NA_character_, kept$site)
  kept$site_id <- ifelse(blank, "", as.character(match(keyed, unique(stats::na.omit(keyed)))))
  out <- data.frame(source = kept$source, source_id = kept$source_id, taxon = kept$taxon,
                    sequence_id = kept$sequence_id, site_id = kept$site_id, stringsAsFactors = FALSE)
  rownames(out) <- NULL

  per_taxon <- table(out$taxon)
  differs <- if (is.data.frame(taxa)) {
    listed <- taxa$records[match(names(per_taxon), taxa$scientific_name)]
    sum(is.na(listed) | as.integer(per_taxon) != listed)
  } else NA_integer_
  summary <- list(
    rows = nrow(out), taxa = length(per_taxon), models = nrow(fitting),
    models_found_by_their_job = sum(fitting$by_job),
    checks = list(
      models_checked = nrow(fitting),
      models_whose_records_differ_from_the_listed_rows = 0L,
      records_trained_under_two_taxa = 0L,
      records_whose_site_membership_differs_between_pulls = 0L,
      models_found_by_their_own_job = sum(fitting$by_job),
      models_found_only_through_another_pull = sum(!fitting$by_job)
    ),
    by_source = as.list(table(out$source)), rows_without_site = sum(!nzchar(out$site_id)),
    rows_with_sequence_id = sum(nzchar(out$sequence_id)), sequence_ids = summary_sequences,
    sites = length(unique(out$site_id[nzchar(out$site_id)])), deleted_at_source = summary_deleted,
    taxa_whose_rows_differ_from_taxa_table = differs
  )
  atlas_deposit_refuse(out, ATLAS_TRAINING_COLUMNS, manifest)
  hidden_with_site <- sum(paste(out$source, out$source_id, sep = "\x1f") %in% hidden & nzchar(out$site_id))
  if (hidden_with_site) stop("refused: ", hidden_with_site, " hidden records carry a site", call. = FALSE)
  list(table = out, summary = summary, fitting = fitting)
}

#' Judge records by two lists (source, observation_id): privacy, records
#' whose place their source hides or may hide, and deleted, records their
#' source no longer holds.
atlas_deposit_judge_lists <- function(privacy = NULL, deleted = NULL) {
  keys <- function(d) if (is.null(d)) character() else paste(d$source, as.character(d$observation_id), sep = "\x1f")
  hidden <- keys(privacy)
  gone <- keys(deleted)
  function(records) {
    key <- paste(records$source, records$source_id, sep = "\x1f")
    list(hidden = key %in% hidden, deleted = key %in% gone)
  }
}

#' Judge records by how the sources stand now, as the collection cells made
#' now do (R/cellsnow.R): hidden, a record on the privacy list (listed, record
#' keys) or in groups (b) and (c); deleted, group (d).
atlas_deposit_judge_status <- function(status, listed = character()) {
  function(records) {
    groups <- atlas_cells_now_groups(data.frame(source = records$source, observation_id = records$source_id,
                                                stringsAsFactors = FALSE), listed %||% character(), status)
    list(hidden = groups[, "a"] | groups[, "b"] | groups[, "c"], deleted = groups[, "d"])
  }
}

#' Which of a pull's two hashes the lineage names it by: the whole-pull
#' fingerprint its job's plan recorded (pull_fingerprint), or the sha256 of
#' its file (pull_file_sha256). printed: the values as printed elsewhere,
#' each the first characters of one; the hash every one of them begins is
#' kept. With none printed, the fingerprint.
atlas_deposit_pull_column <- function(fitting, printed = NULL) {
  if (!length(printed)) return("pull_fingerprint")
  printed <- tolower(trimws(as.character(printed)))
  if (!all(grepl("^[0-9a-f]{7,64}$", printed))) {
    stop("a printed pull value is not the start of a hash (7 to 64 hex characters)", call. = FALSE)
  }
  begins <- function(values) {
    values <- unique(values[!is.na(values)])
    all(vapply(printed, function(p) any(startsWith(values, p)), logical(1)))
  }
  by_print <- begins(fitting$pull_fingerprint)
  by_file <- begins(fitting$pull)
  if (by_print && by_file) stop("the printed pull values begin both hashes of the pulls", call. = FALSE)
  if (!by_print && !by_file) {
    stop("the printed pull values begin neither the pulls' fingerprints nor their files' sha256", call. = FALSE)
  }
  if (by_print) "pull_fingerprint" else "pull_file_sha256"
}

#' The lineage table: each model with its fitting job and its pull, and each
#' pull and job with how many models they fitted. A pull is named by the hash
#' atlas_deposit_pull_column picks; the column is named for it.
atlas_deposit_lineage <- function(fitting, jobs, printed = NULL) {
  column <- atlas_deposit_pull_column(fitting, printed)
  by_file <- identical(column, "pull_file_sha256")
  models <- data.frame(algorithm = fitting$algorithm, taxon = fitting$taxon, job = fitting$job,
                       pull_fingerprint = if (by_file) fitting$pull else fitting$pull_fingerprint,
                       built_at = fitting$built_at, stringsAsFactors = FALSE)
  models <- models[order(models$taxon, models$algorithm), , drop = FALSE]
  rownames(models) <- NULL
  counts <- table(fitting$job)
  pulls <- do.call(rbind, lapply(Filter(function(j) j$id %in% names(counts), jobs), function(j) {
    data.frame(pull_fingerprint = if (by_file) j$sha256 else j$pull_fingerprint, stamp = j$stamp, pulled_at = j$pulled_at,
               records = j$records, job = j$id, models = as.integer(counts[[j$id]]), stringsAsFactors = FALSE)
  }))
  if (is.null(pulls)) pulls <- data.frame(pull_fingerprint = character(), stamp = character(), pulled_at = character(),
                                          records = integer(), job = character(), models = integer())
  pulls <- pulls[order(pulls$stamp, pulls$job), , drop = FALSE]
  rownames(pulls) <- NULL
  names(models)[names(models) == "pull_fingerprint"] <- column
  names(pulls)[names(pulls) == "pull_fingerprint"] <- column
  list(models = models, pulls = pulls, pull_column = column)
}

#' Refuse a deposited table that has other columns than it should, a value
#' shaped like a coordinate, or any taxon's record-set fingerprint.
atlas_deposit_refuse <- function(table, columns, manifest = NULL) {
  if (!identical(names(table), columns)) {
    stop("refused: the table's columns are not ", paste(columns, collapse = ", "), call. = FALSE)
  }
  values <- unlist(lapply(table, as.character), use.names = FALSE)
  values <- values[!is.na(values) & nzchar(values)]
  if (any(grepl("^-?[0-9]{1,3}[.][0-9]{3,}$", values))) {
    stop("refused: the table holds a value shaped like a coordinate", call. = FALSE)
  }
  prints <- unique(unlist(lapply(manifest$index %||% list(), function(e) atlas_json_string(e$fingerprint))))
  prints <- prints[nchar(prints) >= 7L]
  if (length(prints) && any(vapply(prints, function(p) any(grepl(p, values, fixed = TRUE)), logical(1)))) {
    stop("refused: the table holds a taxon's record-set fingerprint", call. = FALSE)
  }
  invisible(TRUE)
}
