# A prior-only job: MycoMap Vision's leave-validation-out benchmark release.
#
# Vision benchmarks photo identification on the records validated after a
# cutoff, and weighs photos by Atlas's location prior. The main release
# (R_main) was fitted on those records too, so its prior would flatter the
# benchmark: a held-out record sits in its own map's high ground, and a record
# far from the rest brings its own 500 km of reach. So Vision asks for a
# second prior (R_train) from the same pull without them (Vision spec
# docs/atlas-environment.md section 3, option B; Steve, 2026-10-12):
#
#   - the same pull as R_main, filtered: a record stays when its first green
#     validation date (R/firstgreen.R) is on or before the cutoff, or when it
#     has none;
#   - R_main's strong (taxon, algorithm) models, refitted with its settings,
#     layers, grid and seeds, but with no null tests: their grades are taken
#     from R_main and declared as inherited;
#   - the area of applicability computed as ever, since the prior uses it;
#   - a taxon that falls below its minimum sites loses its map, and is listed.
#
# One way only: Vision hands Atlas a date, never records.
#
# Nothing it makes is public. It is never a release: never promoted, pulled
# to the box, served, put in the sitemap or archived. Its fits go to the
# store's content-addressed objects like any job's; its only products are
#
#   private/vision-benchmark/<id>/prior/<grid>/   the prior export (R/prior.R)
#   private/vision-benchmark/<id>/summary.json    what was filtered, fitted and lost, and the cost
#   private/trained-ids/<grid>/releases/<id>.tsv.gz  the records it was trained on (R/trained.R)
#
#   ./atlas plan-job --prior-only --from-release=<R_main> --validated-through=<YYYY-MM-DD>
#   ./atlas run-job-ec2 --job=<ID>        (fits the shards, then builds the prior on one worker)

ATLAS_BENCHMARK_PREFIX <- "private/vision-benchmark"

atlas_benchmark_key <- function(id, ...) {
  paste(c(ATLAS_BENCHMARK_PREFIX, id, ...), collapse = "/")
}

atlas_is_prior_only <- function(job) identical(job$kind, "prior-only")

#' The pull a release's job was planned from: its input entry, or NULL.
atlas_job_pull_entry <- function(job) {
  pulls <- Filter(function(e) grepl("^occurrences/occurrences-.*[.]tsv[.]gz$", e$path %||% ""),
                  job$inputs %||% list())
  if (length(pulls)) pulls[[1]] else NULL
}

#' Keep the records a model may train on for a benchmark with this cutoff:
#' first green on or before it, or none. Returns the kept records and counts.
atlas_filter_validated_through <- function(occurrences, validated_through) {
  if (!ATLAS_FIRST_GREEN_FIELD %in% names(occurrences)) {
    stop("this pull carries no first green dates: it was made before they were kept, ",
         "so it cannot be filtered by validation date", call. = FALSE)
  }
  first <- occurrences[[ATLAS_FIRST_GREEN_FIELD]]
  first[!is.na(first) & !nzchar(first)] <- NA_character_
  keep <- is.na(first) | first <= validated_through
  kept <- occurrences[keep, , drop = FALSE]
  rownames(kept) <- NULL
  kept_first <- first[keep]
  list(
    occurrences = kept,
    counts = list(
      records_in_pull = nrow(occurrences),
      records_removed = sum(!keep),
      records_kept = nrow(kept),
      records_kept_dated = sum(!is.na(kept_first)),
      records_kept_undated = sum(is.na(kept_first)),
      # Must be 0: checked here and again before the summary is written.
      records_after_cutoff_kept = sum(!is.na(kept_first) & kept_first > validated_through)
    )
  )
}

#' Run code with ATLAS_DATA_DIR pointing at a scratch directory of its own,
#' so a prior-only job never writes into the data directory of the machine
#' it runs on (the box's pull, or a release it serves).
atlas_in_scratch_data_dir <- function(code, dir = tempfile("atlas-prior-only-")) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  old <- Sys.getenv("ATLAS_DATA_DIR", unset = NA)
  Sys.setenv(ATLAS_DATA_DIR = dir)
  on.exit(if (is.na(old)) Sys.unsetenv("ATLAS_DATA_DIR") else Sys.setenv(ATLAS_DATA_DIR = old), add = TRUE)
  force(code)
}

#' Plan a prior-only job from a release (R_main) and a cutoff date.
atlas_plan_prior_only <- function(store = atlas_store(), from_release, validated_through,
                                  grid = "draft", shards = 4L, tasks_per_shard = NULL, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (!is.character(validated_through) || length(validated_through) != 1L ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", validated_through) ||
      is.na(as.Date(validated_through, format = "%Y-%m-%d"))) {
    stop("--validated-through must be a date, YYYY-MM-DD", call. = FALSE)
  }
  key <- paste0("releases/", grid, "/", from_release, ".json")
  if (!store$exists(key)) stop("no release ", from_release, " for the ", grid, " grid", call. = FALSE)
  base <- atlas_store_text(store, key)
  main_job_id <- atlas_json_string(base$job)
  if (is.null(main_job_id)) {
    stop("release ", from_release, " was not made by a job, so its pull is not in the store", call. = FALSE)
  }
  main_job <- atlas_read_job(store, main_job_id, grid)
  pull_entry <- atlas_job_pull_entry(main_job)
  if (is.null(pull_entry)) stop("job ", main_job_id, " carries no pull", call. = FALSE)

  pull_file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(pull_file), add = TRUE)
  store$get(atlas_object_key(pull_entry$sha256), pull_file)
  filtered <- atlas_filter_validated_through(atlas_read_occurrences(pull_file), validated_through)
  if (filtered$counts$records_after_cutoff_kept != 0L) {
    stop("records validated after the cutoff survived the filter; nothing planned", call. = FALSE)
  }
  occurrences <- filtered$occurrences

  strong <- Filter(function(e) !isTRUE(e$refused) && identical(e$grade, "strong"), base$index %||% list())
  if (!length(strong)) stop("release ", from_release, " has no strong models to refit", call. = FALSE)
  fingerprints <- atlas_fingerprints_for(occurrences, unique(vapply(strong, function(e) e$taxon, "")))
  areas <- vapply(base$index %||% list(), function(e) {
    if (is.numeric(e$area_km2) && length(e$area_km2) == 1L) e$area_km2 else NA_real_
  }, numeric(1))
  typical <- if (any(is.finite(areas))) stats::median(areas, na.rm = TRUE) else 5e6
  tasks <- lapply(strong, function(e) list(
    taxon = e$taxon, algorithm = e$algorithm, fingerprint = fingerprints[[e$taxon]],
    cost = atlas_task_cost(e$algorithm, e$area_km2, typical),
    inherited_grade = e$grade
  ))
  costs <- vapply(tasks, function(t) t$cost, numeric(1))
  if (!is.null(tasks_per_shard)) shards <- atlas_shard_count(length(tasks), shards, tasks_per_shard)
  assignment <- atlas_assign_shards(costs, shards)
  for (i in seq_along(tasks)) tasks[[i]]$shard <- assignment[[i]]

  id <- paste0("train-", atlas_release_id(digest::digest(list(tasks, from_release, validated_through),
                                                         algo = "sha256")))
  # The filtered pull goes to the workers as the job's pull. It is written in
  # a scratch directory, never over this machine's own pull.
  pull_entries <- atlas_in_scratch_data_dir({
    file <- paste0("occurrences-", id, ".tsv.gz")
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(
      stamp = id, pulled_at = base$pull$pulled_at %||% NA_character_, since = NA_character_,
      records = nrow(occurrences), fingerprint = atlas_fingerprint(occurrences), file = file,
      filtered_from = list(release = from_release, job = main_job_id, pull = pull_entry$sha256,
                           validated_through = validated_through)
    ), atlas_path("occurrences", "latest.json"))
    entries <- atlas_file_entries(c(file.path("occurrences", file), "occurrences/latest.json"))
    atlas_upload_objects(store, entries)
    entries
  })
  # Layers and the guild table exactly as R_main's job had them.
  others <- Filter(function(e) !startsWith(e$path, "occurrences/"), main_job$inputs %||% list())
  trained_ids <- atlas_save_trained_pull(store, grid, occurrences)

  job <- list(
    id = id, grid = grid, kind = "prior-only",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    from_release = from_release, from_job = main_job_id, validated_through = validated_through,
    algorithms = as.list(unique(vapply(tasks, function(t) t$algorithm, ""))),
    shards = max(assignment),
    # R_main's settings, with no null tests: the grades are R_main's.
    fit = utils::modifyList(main_job$fit, list(nulls = 0)),
    layers_key = main_job$layers_key,
    pull = base$pull,
    inputs = c(pull_entries, others),
    public = list(), tasks = tasks, retire = list(), deferred = 0L,
    trained_ids = trained_ids,
    filter = filtered$counts,
    declared = paste("Grades are inherited from", from_release, "and were judged on records this job leaves",
                     "out; no null tests were run.")
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
  say("prior-only job ", id, " from ", from_release, " validated through ", validated_through, ": ",
      filtered$counts$records_removed, " of ", filtered$counts$records_in_pull, " records left out; ",
      length(tasks), " strong models to refit in ", job$shards, " shard", if (job$shards == 1L) "" else "s")
  invisible(job)
}

#' On a worker (or any machine): build the prior-only job's prior from its
#' shards, and write its trained ids and summary. Everything happens in a
#' scratch data directory, and goes only under the store's private prefixes.
atlas_finish_prior_only_work <- function(store = atlas_store(), id, grid = "draft", quiet = FALSE,
                                         build = atlas_build_prior, usd_per_vcpu_hour = 0.025,
                                         vcpus_per_worker = 32) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  job <- atlas_read_job(store, id, grid)
  if (!atlas_is_prior_only(job)) stop("job ", id, " is not a prior-only job", call. = FALSE)
  status <- atlas_job_status(store, id, grid)
  if (length(status$missing)) {
    stop("job ", id, " is not finished: shard", if (length(status$missing) > 1L) "s " else " ",
         paste(status$missing, collapse = ", "), " not reported", call. = FALSE)
  }
  if (!identical(as.integer(job$filter$records_after_cutoff_kept), 0L)) {
    stop("job ", id, " kept records validated after its cutoff; nothing built", call. = FALSE)
  }
  records <- lapply(seq_len(job$shards), function(n) atlas_store_text(store, atlas_shard_key(id, n, grid)))
  results <- unlist(lapply(records, function(r) r$results), recursive = FALSE)
  files <- unlist(lapply(records, function(r) r$files), recursive = FALSE)
  index <- unlist(lapply(records, function(r) r$index), recursive = FALSE)
  grades <- list()
  for (t in job$tasks) grades[[paste(t$algorithm, t$taxon)]] <- t$inherited_grade

  built <- atlas_in_scratch_data_dir({
    atlas_fetch_entries(store, files)
    # The grade each model had in the release this job refits: no null test
    # ran here, and that is said in every model's metrics.
    for (e in index) {
      path <- atlas_model_path(e$taxon, grid, ".json", e$algorithm)
      if (!file.exists(path)) next
      metrics <- jsonlite::fromJSON(path, simplifyVector = FALSE)
      metrics$grade <- grades[[paste(e$algorithm, e$taxon)]] %||% "untested"
      metrics$grade_inherited_from <- job$from_release
      atlas_write_json(metrics, path)
    }
    prior <- build(grid = grid, quiet = quiet)
    uploaded <- character()
    for (file in ATLAS_PRIOR_FILES) {
      path <- atlas_prior_path(file, grid)
      if (!file.exists(path)) next
      key <- atlas_benchmark_key(id, "prior", grid, file)
      store$put(key, path)
      uploaded <- c(uploaded, key)
    }
    list(prior = prior, uploaded = uploaded)
  })

  fitted <- Filter(function(r) identical(r$status, "fitted"), results)
  fitted_index <- Filter(function(e) paste(e$algorithm, e$taxon) %in%
                           vapply(fitted, function(r) paste(r$algorithm, r$taxon), ""), index)
  trained <- atlas_write_trained_ids(store, list(id = id, index = fitted_index), grid,
                                     prefer = atlas_json_string(job$trained_ids), quiet = TRUE)

  planned_taxa <- unique(vapply(job$tasks, function(t) t$taxon, ""))
  fitted_taxa <- unique(vapply(fitted, function(r) r$taxon, ""))
  lost <- setdiff(planned_taxa, fitted_taxa)
  lost_rows <- lapply(lost, function(name) {
    mine <- Filter(function(r) identical(r$taxon, name), results)
    list(taxon = name, statuses = as.list(unique(vapply(mine, function(r) r$status, ""))),
         reason = (Filter(Negate(is.null), lapply(mine, function(r) r$error)) %||% list(NULL))[[1]])
  })
  seconds <- sum(vapply(results, function(r) as.numeric(r$seconds %||% 0), 0), na.rm = TRUE)
  worker_hours <- sum(vapply(records, function(r) {
    if (is.null(r$started_at) || is.null(r$finished_at)) return(0)
    as.numeric(difftime(as.POSIXct(r$finished_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                        as.POSIXct(r$started_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours"))
  }, 0), na.rm = TRUE)
  summary <- list(
    job = id, grid = grid, kind = "prior-only",
    from_release = job$from_release, validated_through = job$validated_through,
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    filter = job$filter,
    models_planned = length(job$tasks),
    models_fitted = length(fitted),
    models_refused = sum(vapply(results, function(r) identical(r$status, "refused"), logical(1))),
    models_failed = sum(vapply(results, function(r) identical(r$status, "failed"), logical(1))),
    taxa_planned = length(planned_taxa),
    taxa_refitted = length(fitted_taxa),
    taxa_lost = lost_rows,
    prior = list(taxa = nrow(built$prior$taxa), rows = nrow(built$prior$ranks), files = as.list(built$uploaded)),
    trained_ids = list(key = atlas_trained_release_key(id, grid), records = trained$records,
                       not_found = trained$not_found),
    cpu_hours = round(seconds / 3600, 2),
    worker_hours = round(worker_hours, 2),
    cost_estimate_usd = round(worker_hours * vcpus_per_worker * usd_per_vcpu_hour, 2),
    cost_basis = sprintf("worker hours x %d vCPU x $%.3f per vCPU-hour (spot, estimate; a lost worker's hours are not counted)",
                         as.integer(vcpus_per_worker), usd_per_vcpu_hour),
    declared = job$declared
  )
  atlas_store_json(store, atlas_benchmark_key(id, "summary.json"), summary)
  # The record the EC2 loop waits for, as a finishing worker writes one.
  atlas_store_json(store, atlas_shard_key(atlas_finish_id(id), 1L, grid),
                   list(job = atlas_finish_id(id), shard = 1L, prior_only = id, finished_at = summary$finished_at))
  say("prior-only job ", id, ": ", length(fitted_taxa), " of ", length(planned_taxa), " taxa refitted, ",
      length(lost), " lost; prior of ", summary$prior$taxa, " taxa; ", summary$cpu_hours, " CPU-h, about $",
      summary$cost_estimate_usd, "; summary at ", atlas_benchmark_key(id, "summary.json"))
  invisible(summary)
}

#' On the box: once a prior-only job's shards have reported, build its prior on
#' one EC2 worker (the box keeps no rasters and does no processing).
atlas_finish_prior_only_on_ec2 <- function(store, job, grid = "draft", ec2 = NULL, config = atlas_ec2_config(),
                                           poll_seconds = 60, wait = Sys.sleep, quiet = FALSE,
                                           clock = Sys.time, hours = config$finish_hours %||% 3,
                                           image_exists = atlas_image_exists) {
  if (!atlas_is_prior_only(job)) stop("job ", job$id, " is not a prior-only job", call. = FALSE)
  atlas_one_worker_on_ec2(
    store, atlas_finish_id(job$id), grid,
    command = sprintf("finish-prior-only --grid=%s --job=%s", grid, job$id),
    label = paste("the prior of job", job$id),
    ec2 = ec2, config = config, poll_seconds = poll_seconds, wait = wait, quiet = quiet,
    clock = clock, hours = hours, image_exists = image_exists
  )
  invisible(atlas_store_text(store, atlas_benchmark_key(job$id, "summary.json")))
}
