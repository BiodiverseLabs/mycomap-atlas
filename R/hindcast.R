# A private release: Atlas fitted in full on a variant of a release's pull,
# graded by its own null tests, finished as any release is, and kept where
# nothing public can reach it (Steve, 2026-10-13).
#
# Two purposes, one machinery:
#
#   hindcast      Atlas as it would have been at a cutoff (Atlas E2, and
#                 MycoMap Vision's R_train): the release's pull with only the
#                 records first validated (first_green_on, R/firstgreen.R) on
#                 or before the cutoff; records with no first green date are
#                 left out and counted, since nothing says they were known
#                 by then. Never the observation date.
#   record-names  Atlas with each record under .org's own name for it instead
#                 of its approved sequence's (Atlas E9): the same records,
#                 named as their observers named them. Only the models whose
#                 record set changes are fitted: a taxon with the same records
#                 under the same name would refit to the release's own model.
#
# Unlike a prior-only job (R/prioronly.R), which refits R_main's strong
# models and inherits their grades, this plans every taxon afresh, with the
# release's settings, null tests and tuning, so its grades are its own: a
# release that saw the test records cannot be the one that grades them.
#
# Everything record-derived comes from the variant pull: survey sites,
# effort, background and each taxon's accessible area are built on the
# worker from the pull the job carries (R/background.R), never the box's.
#
# Its finishing runs the same builders a release's finishing does (R/finish.R:
# counts by state, combined maps, the here index, the prior with its trust
# signals, the weak maps' ranks, the continent export from full views on the
# sliver-free scope) on one worker, and files everything privately:
#
#   private/vision-benchmark/<id>/release.json     its files and model index (never under releases/)
#   private/vision-benchmark/<id>/prior/<grid>/     the prior export
#   private/vision-benchmark/<id>/continent/<grid>/ the continent export
#   private/vision-benchmark/<id>/here/<grid>/      the here index
#   private/vision-benchmark/<id>/weak/<grid>/      the weak maps' ranks
#   private/vision-benchmark/<id>/models.tsv.gz     every model's grade, strength and scores
#   private/vision-benchmark/<id>/summary.json      what was filtered, fitted, graded and cost
#   private/trained-ids/<grid>/releases/<id>.tsv.gz the records it trained on
#
# It is never a release: nothing is written under releases/ or current/,
# so it cannot be promoted, pulled, served, archived or put in a sitemap.
#
#   ./atlas plan-job --hindcast --from-release=<R_main> --validated-through=YYYY-MM-DD [--dry-run]
#   ./atlas plan-job --record-names --from-release=<R_main> [--dry-run]
#   ./atlas run-job-ec2 --job=<ID>      (fits the shards, then finishes it on one worker)

atlas_is_private_release <- function(job) identical(job$kind, "private-release")

ATLAS_PRIVATE_PURPOSES <- c("hindcast", "record-names")

# Seconds per model for the plan's estimate when the release's job has no
# timed results: a full fit with tuning and null tests (the 2026-10-12/13
# timings, after the short-path pass budget).
ATLAS_PRIVATE_SECONDS <- c(maxnet = 1500, rf = 600, xgboost = 300, esm = 120)

#' The pull named by records' own names (R/labels.R keeps .org's name in
#' record_name beside the sequence's): a record keeps its place under its
#' record name when that is species level, and is left out otherwise.
atlas_record_named <- function(occurrences) {
  if (!"record_name" %in% names(occurrences)) {
    stop("this pull carries no record names: it was made before they were kept", call. = FALSE)
  }
  name <- trimws(as.character(occurrences$record_name))
  species <- !is.na(name) & grepl(" ", name) &
    !grepl(" sp[.]?$", tolower(name)) & !tolower(name) %in% c("fungi", "unknown")
  out <- occurrences[species, , drop = FALSE]
  # Reading a pull names each record from original_name (R/names.R), so the
  # record name goes there too, with the same spelling merges.
  out$scientific_name <- name[species]
  out$original_name <- name[species]
  out <- atlas_canonicalise_occurrences(out)
  rownames(out) <- NULL
  list(occurrences = out, counts = list(records_in_pull = nrow(occurrences), records_kept = nrow(out),
                                        records_not_species_level = sum(!species)))
}

#' Seconds per model by algorithm: the mean of the release job's own timed
#' fits where it has them, else ATLAS_PRIVATE_SECONDS.
atlas_private_seconds <- function(store, job_id, grid = "draft") {
  measured <- tryCatch(atlas_job_timing(store, job_id, grid)$per_algorithm, error = function(e) NULL)
  out <- ATLAS_PRIVATE_SECONDS
  if (!is.null(measured) && nrow(measured)) {
    for (i in seq_len(nrow(measured))) out[[measured$algorithm[[i]]]] <- measured$mean_seconds[[i]]
  }
  out
}

#' Plan a private release from a release's pull: a hindcast at a cutoff, or
#' the records under their own names. dry_run = TRUE reads the store and
#' says what it would fit and cost, and writes nothing.
atlas_plan_private_release <- function(store = atlas_store(), from_release, purpose = ATLAS_PRIVATE_PURPOSES,
                                       validated_through = NULL, grid = "draft", algorithms = "all",
                                       shards = 4L, tasks_per_shard = NULL, quiet = FALSE, dry_run = FALSE,
                                       fits_at_once = 128) {
  purpose <- match.arg(purpose)
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (identical(purpose, "hindcast")) {
    if (!is.character(validated_through) || length(validated_through) != 1L ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", validated_through) ||
        is.na(as.Date(validated_through, format = "%Y-%m-%d"))) {
      stop("a hindcast needs --validated-through=YYYY-MM-DD", call. = FALSE)
    }
  } else if (!is.null(validated_through)) {
    stop("only a hindcast takes a cutoff", call. = FALSE)
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
  pulled <- atlas_read_occurrences(pull_file)

  variant <- if (identical(purpose, "hindcast")) {
    filtered <- atlas_filter_validated_through(pulled, validated_through, undated = "exclude")
    if (filtered$counts$records_after_cutoff_kept != 0L) {
      stop("records validated after the cutoff survived the filter; nothing planned", call. = FALSE)
    }
    filtered
  } else {
    atlas_record_named(pulled)
  }
  occurrences <- variant$occurrences

  algorithms <- if (length(algorithms) == 1L) atlas_parse_algorithms(algorithms) else algorithms
  min_presences <- main_job$fit$min_presences %||% 20
  points <- atlas_occurrence_points(occurrences, grid)
  areas <- vapply(base$index %||% list(), function(e) {
    if (is.numeric(e$area_km2) && length(e$area_km2) == 1L) e$area_km2 else NA_real_
  }, numeric(1))
  typical <- if (any(is.finite(areas))) stats::median(areas, na.rm = TRUE) else 5e6
  area_of <- list()
  fitted_on <- list()
  for (e in base$index %||% list()) {
    area_of[[paste(e$algorithm, e$taxon)]] <- e$area_km2
    if (!isTRUE(e$refused)) fitted_on[[paste(e$algorithm, e$taxon)]] <- e$fingerprint
  }
  unchanged <- 0L
  tasks <- list()
  for (algorithm in algorithms) {
    algo <- atlas_algorithm(algorithm)
    minimum <- atlas_algorithm_min(algo, min_presences)
    candidates <- atlas_batch_candidates(points, minimum,
                                         max_presences = atlas_algorithm_max(algo) + ATLAS_RANGE_MARGIN)$scientific_name
    fingerprints <- atlas_fingerprints_for(occurrences, candidates)
    for (name in candidates) {
      if (identical(purpose, "record-names") &&
          identical(as.character(fitted_on[[paste(algorithm, name)]] %||% ""), as.character(fingerprints[[name]]))) {
        unchanged <- unchanged + 1L
        next
      }
      tasks[[length(tasks) + 1L]] <- list(
        taxon = name, algorithm = algorithm, fingerprint = fingerprints[[name]],
        cost = atlas_task_cost(algorithm, area_of[[paste(algorithm, name)]], typical)
      )
    }
  }
  if (identical(purpose, "record-names")) variant$counts$models_unchanged <- unchanged
  if (!length(tasks)) stop("nothing to fit: no taxon has enough records in the ", purpose, " pull",
                           if (unchanged) paste0(", or each is unchanged (", unchanged, ")"), call. = FALSE)
  seconds <- atlas_private_seconds(store, main_job_id, grid)
  models <- table(vapply(tasks, function(t) t$algorithm, ""))
  cpu_hours <- sum(vapply(tasks, function(t) seconds[[t$algorithm]] %||% 600, numeric(1))) / 3600
  estimate <- list(
    models = length(tasks), taxa = length(unique(vapply(tasks, function(t) t$taxon, ""))),
    per_algorithm = as.list(models), cpu_hours = round(cpu_hours, 1),
    wall_hours = round(cpu_hours / fits_at_once, 1),
    basis = paste("mean seconds per model of job", main_job_id, "where timed, else ATLAS_PRIVATE_SECONDS;",
                  "wall at", fits_at_once, "fits at once; an estimate")
  )
  if (isTRUE(dry_run)) {
    say(purpose, " from ", from_release, if (!is.null(validated_through)) paste0(" validated through ", validated_through),
        " (dry run, nothing written): ", variant$counts$records_kept, " of ", variant$counts$records_in_pull,
        " records kept", if (!is.null(variant$counts$records_undated_left_out))
          paste0(" (", variant$counts$records_undated_left_out, " with no first green date left out)"),
        "; ", estimate$models, " models of ", estimate$taxa, " taxa (",
        paste(names(models), models, collapse = ", "), "); about ", estimate$cpu_hours, " CPU-h, ",
        estimate$wall_hours, " h on EC2")
    return(invisible(list(from_release = from_release, purpose = purpose, filter = variant$counts,
                          estimate = estimate, tasks = tasks)))
  }

  costs <- vapply(tasks, function(t) t$cost, numeric(1))
  if (!is.null(tasks_per_shard)) shards <- atlas_shard_count(length(tasks), shards, tasks_per_shard)
  assignment <- atlas_assign_shards(costs, shards)
  for (i in seq_along(tasks)) tasks[[i]]$shard <- assignment[[i]]
  id <- paste0("priv-", atlas_release_id(digest::digest(list(tasks, from_release, purpose, validated_through),
                                                        algo = "sha256")))
  # The variant pull goes to the workers as the job's pull, written in a
  # scratch directory, never over this machine's own.
  pull_entries <- atlas_in_scratch_data_dir({
    file <- paste0("occurrences-", id, ".tsv.gz")
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(
      stamp = id, pulled_at = base$pull$pulled_at %||% NA_character_, since = NA_character_,
      records = nrow(occurrences), fingerprint = atlas_fingerprint(occurrences), file = file,
      made_from = list(release = from_release, job = main_job_id, pull = pull_entry$sha256,
                       purpose = purpose, validated_through = validated_through)
    ), atlas_path("occurrences", "latest.json"))
    entries <- atlas_file_entries(c(file.path("occurrences", file), "occurrences/latest.json"))
    atlas_upload_objects(store, entries)
    entries
  })
  others <- Filter(function(e) !startsWith(e$path, "occurrences/"), main_job$inputs %||% list())
  trained_ids <- atlas_save_trained_pull(store, grid, occurrences)
  job <- list(
    id = id, grid = grid, kind = "private-release", purpose = purpose,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    from_release = from_release, from_job = main_job_id, validated_through = validated_through,
    algorithms = as.list(algorithms), shards = max(assignment),
    # The release's own settings, null tests and tuning included: the
    # grades are this job's.
    fit = main_job$fit,
    layers_key = main_job$layers_key,
    pull = base$pull,
    inputs = c(pull_entries, others),
    public = list(), tasks = tasks, retire = list(), deferred = 0L,
    trained_ids = trained_ids,
    filter = variant$counts,
    estimate = estimate,
    declared = if (identical(purpose, "hindcast")) {
      paste("Fitted and graded afresh on the records of", from_release, "'s pull first validated on or before",
            validated_through, "; records with no first green date left out.")
    } else {
      paste("Fitted and graded afresh on the records of", from_release, "'s pull under their own .org names.")
    }
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
  say(purpose, " job ", id, " from ", from_release, ": ", variant$counts$records_kept, " of ",
      variant$counts$records_in_pull, " records; ", length(tasks), " models in ", job$shards, " shard",
      if (job$shards == 1L) "" else "s", "; about ", estimate$cpu_hours, " CPU-h")
  invisible(job)
}

#' Every model's grade, strength and scores, from this data directory's
#' metrics: what Atlas E2 scores by grade.
atlas_private_models_table <- function(grid = "draft") {
  rows <- lapply(names(ATLAS_ALGORITHMS), function(algorithm) {
    files <- list.files(atlas_model_dir(grid, algorithm), pattern = "[.]json$", full.names = TRUE)
    lapply(files, function(path) {
      m <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(m$taxon)) return(NULL)
      number <- function(x) if (is.numeric(x) && length(x) == 1L) x else NA_real_
      data.frame(taxon = m$taxon, algorithm = algorithm, grade = atlas_metrics_grade(m),
                 presences = number(m$presences), map_strength = number(m$map_strength),
                 auc_mean = number(m$auc_mean), boyce_pooled = number(m$boyce_pooled),
                 null_reps = number(m$null$reps), null_auc_p = number(m$null$auc_p),
                 threshold = number(m$applicability$threshold),
                 full_view = !is.null(m$full_map), stringsAsFactors = FALSE)
    })
  })
  out <- do.call(rbind, unlist(rows, recursive = FALSE))
  if (is.null(out)) out <- data.frame(taxon = character(), algorithm = character(), grade = character())
  out[order(out$taxon, out$algorithm), , drop = FALSE]
}

#' On a worker (or any machine): finish a private release from its shards,
#' as a release's finishing does, in a scratch data directory, filing every
#' product privately. Never in part: every shard must have reported.
atlas_finish_private_release_work <- function(store = atlas_store(), id, grid = "draft", quiet = FALSE,
                                              count = atlas_count_regions, ensembles = atlas_build_ensembles,
                                              build = atlas_build_finish_indexes, defer = FALSE,
                                              usd_per_vcpu_hour = 0.025, vcpus_per_worker = 32) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (isTRUE(defer)) store <- atlas_deferring_store(store)
  job <- atlas_read_job(store, id, grid)
  if (!atlas_is_private_release(job)) stop("job ", id, " is not a private release", call. = FALSE)
  status <- atlas_job_status(store, id, grid)
  if (length(status$missing)) {
    stop("job ", id, " is not finished: shard", if (length(status$missing) > 1L) "s " else " ",
         paste(status$missing, collapse = ", "), " not reported; a private release is never finished in part",
         call. = FALSE)
  }
  if (identical(job$purpose, "hindcast") && !identical(as.integer(job$filter$records_after_cutoff_kept), 0L)) {
    stop("job ", id, " kept records validated after its cutoff; nothing built", call. = FALSE)
  }
  records <- lapply(seq_len(job$shards), function(n) atlas_store_text(store, atlas_shard_key(id, n, grid)))
  results <- unlist(lapply(records, function(r) r$results), recursive = FALSE)
  files <- unlist(lapply(records, function(r) r$files), recursive = FALSE)
  index <- unlist(lapply(records, function(r) r$index), recursive = FALSE)
  for (r in Filter(function(r) identical(r$status, "refused"), results)) {
    index[[length(index) + 1L]] <- atlas_refusal_entry(r$taxon, r$algorithm, r$fingerprint, r$settings_key, r$presences)
  }

  key <- function(...) atlas_benchmark_key(id, ...)
  uploaded <- character()
  upload <- function(path, ...) {
    if (!file.exists(path)) return(invisible(NULL))
    k <- key(...)
    store$put(k, path)
    uploaded <<- c(uploaded, k)
  }
  built <- atlas_in_scratch_data_dir({
    # The job's own pull, for the collection cells counting reads; the
    # layers are not needed, only the maps.
    atlas_fetch_entries(store, Filter(function(e) startsWith(e$path, "occurrences/"), job$inputs))
    atlas_fetch_entries(store, files)
    atlas_refresh_public_files()
    counted <- count(grid = grid, only_missing = TRUE, quiet = quiet)
    ensembles(grid = grid, quiet = quiet)
    build(grid = grid, quiet = quiet)
    models <- atlas_private_models_table(grid)
    models_file <- tempfile(fileext = ".tsv.gz")
    atlas_write_tsv_gz(models, models_file)
    upload(models_file, "models.tsv.gz")
    for (f in ATLAS_PRIOR_FILES) upload(file.path(atlas_prior_dir(grid), f), "prior", grid, f)
    for (f in ATLAS_CONTINENT_FILES) upload(file.path(atlas_continent_dir(grid), f), "continent", grid, f)
    upload(atlas_here_index_path(grid), "here", grid, basename(atlas_here_index_path(grid)))
    upload(atlas_weak_ranks_path(grid), "weak", grid, basename(atlas_weak_ranks_path(grid)))
    # Its files as a release would list them, kept privately: the fitted
    # maps (metrics counted by state now) and the combined maps.
    paths <- atlas_release_files(grid)
    paths <- paths[!startsWith(paths, "public/") & !startsWith(paths, "occurrences/")]
    entries <- atlas_file_entries(paths)
    atlas_upload_objects(store, entries)
    list(counted = counted, models = models, entries = entries)
  })
  manifest_file <- tempfile(fileext = ".json")
  atlas_write_json(list(id = id, grid = grid, kind = "private-release", purpose = job$purpose,
                        from_release = job$from_release, validated_through = job$validated_through,
                        created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                        pull = job$pull, layers_key = job$layers_key,
                        index = index, files = built$entries), manifest_file)
  upload(manifest_file, "release.json")

  fitted <- Filter(function(r) identical(r$status, "fitted"), results)
  trained <- atlas_write_trained_ids(store, list(id = id, index = Filter(function(e) !isTRUE(e$refused), index)),
                                     grid, prefer = atlas_json_string(job$trained_ids), quiet = TRUE)
  grades <- table(factor(built$models$grade, levels = c("strong", "weak", "failed", "untested")),
                  built$models$algorithm)
  seconds <- sum(vapply(results, function(r) as.numeric(r$seconds %||% 0), 0), na.rm = TRUE)
  worker_hours <- sum(vapply(records, function(r) {
    if (is.null(r$started_at) || is.null(r$finished_at)) return(0)
    as.numeric(difftime(as.POSIXct(r$finished_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                        as.POSIXct(r$started_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours"))
  }, 0), na.rm = TRUE)
  summary <- Filter(Negate(is.null), list(
    job = id, grid = grid, kind = "private-release", purpose = job$purpose,
    from_release = job$from_release, validated_through = job$validated_through,
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    filter = job$filter,
    models_planned = length(job$tasks),
    models_fitted = length(fitted),
    models_refused = sum(vapply(results, function(r) identical(r$status, "refused"), logical(1))),
    models_failed = sum(vapply(results, function(r) identical(r$status, "failed"), logical(1))),
    grades = lapply(stats::setNames(nm = colnames(grades)), function(a) as.list(grades[, a])),
    counted = as.integer(built$counted %||% 0L),
    files = as.list(uploaded),
    trained_ids = list(key = atlas_trained_release_key(id, grid), records = trained$records),
    cpu_hours = round(seconds / 3600, 2),
    worker_hours = round(worker_hours, 2),
    cost_estimate_usd = round(worker_hours * vcpus_per_worker * usd_per_vcpu_hour, 2),
    declared = job$declared
  ))
  atlas_store_json(store, key("summary.json"), summary)
  atlas_store_json(store, atlas_shard_key(atlas_finish_id(id), 1L, grid),
                   list(job = atlas_finish_id(id), shard = 1L, private_release = id,
                        finished_at = summary$finished_at,
                        deferred = if (isTRUE(defer)) store$deferred() else list()))
  say(job$purpose, " ", id, ": ", length(fitted), " of ", length(job$tasks), " models fitted; ",
      sum(built$models$grade == "strong"), " strong; summary at ", key("summary.json"))
  invisible(summary)
}

#' On the box: once a private release's shards have reported, finish it on
#' one EC2 worker and put its private files in place.
atlas_finish_private_release_on_ec2 <- function(store, job, grid = "draft", ec2 = NULL, config = atlas_ec2_config(),
                                                poll_seconds = 60, wait = Sys.sleep, quiet = FALSE,
                                                clock = Sys.time, hours = config$finish_hours %||% 3,
                                                image_exists = atlas_image_exists) {
  if (!atlas_is_private_release(job)) stop("job ", job$id, " is not a private release", call. = FALSE)
  atlas_one_worker_on_ec2(
    store, atlas_finish_id(job$id), grid,
    command = sprintf("finish-private-release --grid=%s --job=%s --defer", grid, job$id),
    label = paste("the private release of job", job$id),
    ec2 = ec2, config = config, poll_seconds = poll_seconds, wait = wait, quiet = quiet,
    clock = clock, hours = hours, image_exists = image_exists
  )
  record <- atlas_store_text(store, atlas_shard_key(atlas_finish_id(job$id), 1L, grid))
  atlas_place_deferred(store, record$deferred)
  invisible(atlas_store_text(store, atlas_benchmark_key(job$id, "summary.json")))
}
