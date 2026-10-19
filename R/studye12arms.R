# Paper E12's refit arms: the drawn models of the frozen release fitted
# again, graded, on one processor family per arm (docs/experiments,
# plan-e12-grade-stability).
#
#   ./atlas plan-study --command=study-repro --shards=4 \
#     --args="--draw --release=<frozen> --label=a1 --workers=8"
#   ATLAS_EC2_INSTANCE_TYPES=r7i.8xlarge ./atlas run-job-ec2 --job=<ID>
#
# Arm a2 is the same on r7i with --order=reverse and another shard count, so
# each model sits at another place in another worker process; arm b runs on
# r7a. Each worker:
#
#   - draws the sample itself from the release, by the plan's rule
#     (atlas_e12_draw, then the cost rule from the recorded fit times), so
#     every arm fits exactly the same models, and records the sample's key;
#   - finds, for each drawn model, the job that fitted it (the refresh's
#     lineage, atlas_refresh_sources: the frozen release holds models of more
#     than one job and pull) and fits it on that job's inputs and settings,
#     nulls included (the job's own, production's 99 stopping at 5), so the
#     refit is graded as the release's model was;
#   - runs the models in fresh worker processes (a PSOCK cluster), each
#     worker's in a fixed order, and records for each model its worker, its
#     place in that worker's order and the machine (instance type, CPU, BLAS);
#   - compares each fit with the release's: settings, tuning scores, held-out
#     scores, grade, null p and the default raster's bytes.
#
# Nothing here writes a model or a release: one results file per shard under
# the study's prefix. The comparison across arms is the analysis's.

ATLAS_E12_ORDERS <- c("seeded", "reverse")

#' The drawn models of a release, as every arm fits them: the plan's sample
#' (draw, then the cost rule), in the draw's seeded order (cell by cell, by
#' rank) or its reverse, with a key that names the sample whatever the order.
atlas_e12_arm_models <- function(store, base, grid = "draft", order = "seeded",
                                 seconds = atlas_e12_seconds(store, base, grid)) {
  order <- match.arg(order, ATLAS_E12_ORDERS)
  cost <- atlas_e12_cost(atlas_e12_draw(base$index), seconds)
  d <- cost$models[cost$models$sample, c("algorithm", "taxon", "fingerprint", "presences", "band", "grade",
                                         "cell", "rank"), drop = FALSE]
  d <- d[order(d$cell, d$rank, method = "radix"), , drop = FALSE]
  if (identical(order, "reverse")) d <- d[rev(seq_len(nrow(d))), , drop = FALSE]
  rownames(d) <- NULL
  ids <- sort(paste(d$algorithm, d$taxon, d$fingerprint, sep = "|"), method = "radix")
  attr(d, "sample_key") <- digest::digest(ids, algo = "sha256")
  attr(d, "cost") <- cost$summary
  d
}

#' What one graded fit chose and scored: atlas_repro_summary, and its grade,
#' null test and map strength.
atlas_e12_fit_summary <- function(m, tif_sha256 = NULL) {
  num <- function(x) if (is.null(x)) NA_real_ else suppressWarnings(as.numeric(unlist(x))[1])
  c(atlas_repro_summary(m, tif_sha256), Filter(Negate(is.null), list(
    fingerprint = m$fingerprint %||% NA_character_,
    grade = atlas_metrics_grade(m), skill = m$skill %||% NA_character_,
    null_p = num(m$null$auc_p), null_reps = num(m$null$reps), null_drawn = num(m$null$drawn),
    map_strength = num(m$map_strength)
  )))
}

#' In one process: fit the given models in their order, as a shard of their
#' job would (fit_settings, nulls), each read back at once. A model's place in
#' this process's order and the process are recorded with it.
atlas_e12_worker_fit <- function(models, fit_settings, nulls, grid = "draft",
                                 occurrences = NULL, points = NULL, stack = NULL) {
  s <- fit_settings
  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  stack <- stack %||% atlas_predictor_stack(grid)
  machine <- atlas_machine_info()
  lapply(seq_len(nrow(models)), function(i) {
    name <- models$taxon[[i]]
    algorithm <- models$algorithm[[i]]
    started <- Sys.time()
    run <- tryCatch(atlas_fit_batch(
      grid = grid, force = TRUE, workers = 1L, taxa = name, algorithm = algorithm,
      min_presences = s$min_presences %||% 20, n_background = s$n_background %||% 10000,
      buffer_km = s$buffer_km %||% 500, folds = s$folds %||% 5, block_km = s$block_km %||% "auto",
      regmult = s$regmult %||% 1, correlation = s$correlation %||% 0.7,
      nulls = nulls, tune = s$tune %||% TRUE, full = FALSE, quiet = TRUE,
      occurrences = occurrences, points = points, stack = stack
    ), error = function(e) e)
    m <- if (!inherits(run, "error")) atlas_read_metrics(name, grid, algorithm)
    tif <- atlas_model_path(name, grid, ".tif", algorithm)
    fit <- if (is.null(m)) {
      list(taxon = name, status = "not fitted", error = if (inherits(run, "error")) conditionMessage(run))
    } else {
      atlas_e12_fit_summary(m, if (file.exists(tif)) atlas_sha256(tif))
    }
    c(fit, list(algorithm = algorithm, position = i, process = Sys.getpid(), machine = machine,
                seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)))
  })
}

#' Which worker process each of n models goes to: every workers-th model, in
#' order, so the k-th model is its worker's ceiling(k / workers)-th.
atlas_e12_worker_parts <- function(n, workers = 1L) {
  workers <- max(1L, min(as.integer(workers), as.integer(n)))
  (seq_len(n) - 1L) %% workers + 1L
}

#' The models in `workers` fresh processes, each taking every workers-th model
#' in order, so a model's place in its process depends on the order and the
#' split. Returns the fits in the models' order.
atlas_e12_run_workers <- function(models, fit_settings, nulls, grid = "draft", workers = 1L) {
  part <- atlas_e12_worker_parts(nrow(models), workers)
  workers <- max(part)
  pieces <- lapply(seq_len(workers), function(w) models[part == w, , drop = FALSE])
  cluster <- parallel::makePSOCKcluster(workers)
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  package <- utils::packageName()
  fits <- parallel::parLapply(cluster, pieces, function(piece, package, fit_settings, nulls, grid) {
    asNamespace(package)$atlas_e12_worker_fit(piece, fit_settings, nulls, grid)
  }, package = package, fit_settings = fit_settings, nulls = nulls, grid = grid)
  out <- vector("list", nrow(models))
  for (w in seq_len(workers)) {
    rows <- which(part == w)
    for (k in seq_along(rows)) out[[rows[[k]]]] <- c(fits[[w]][[k]], list(worker = w))
  }
  out
}

#' One shard of an E12 arm. fit_models (atlas_e12_run_workers) and seconds
#' are replaceable for tests.
atlas_e12_arm_study <- function(store = atlas_store(), release, grid = "draft", out = NULL, shard = "1/1",
                                label = NULL, order = "seeded", workers = 1L, nulls = NULL,
                                fit_models = atlas_e12_run_workers, seconds = NULL, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (!is.null(out)) atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
  key <- paste0("releases/", grid, "/", release, ".json")
  if (!store$exists(key)) stop("no release ", release, " for the ", grid, " grid", call. = FALSE)
  base <- atlas_store_text(store, key)
  models <- atlas_e12_arm_models(store, base, grid, order,
                                 seconds = seconds %||% atlas_e12_seconds(store, base, grid))
  sample_key <- attr(models, "sample_key")
  drawn <- nrow(models)
  mine <- models[atlas_study_shard(seq_len(drawn), shard), , drop = FALSE]
  # Each model on the inputs of the job that fitted it.
  tasks <- lapply(seq_len(nrow(mine)), function(i) {
    list(algorithm = mine$algorithm[[i]], taxon = mine$taxon[[i]], fingerprint = mine$fingerprint[[i]])
  })
  sources <- atlas_refresh_sources(store, base, tasks, grid)
  model_key <- paste(mine$algorithm, mine$taxon)
  mine$source_job <- vapply(model_key, function(k) sources$source[[k]] %||% NA_character_, "", USE.NAMES = FALSE)
  say("E12 arm ", label %||% "", " (shard ", shard, ", ", order, " order): ", nrow(mine), " of ", drawn,
      " drawn models from ", length(unique(stats::na.omit(mine$source_job))), " fitting job(s), on ",
      workers, " worker process(es)")
  fits <- vector("list", nrow(mine))
  for (job_id in unique(stats::na.omit(mine$source_job))) {
    job <- sources$jobs[[job_id]]
    rows <- which(mine$source_job %in% job_id)
    atlas_fetch_entries(store, job$inputs %||% list())
    job_nulls <- as.integer(nulls %||% job$fit$nulls %||% ATLAS_NULL_REPS)
    got <- fit_models(mine[rows, , drop = FALSE], job$fit %||% list(), job_nulls, grid, workers)
    for (k in seq_along(rows)) fits[[rows[[k]]]] <- c(got[[k]], list(source_job = job_id, nulls = job_nulls))
  }
  results <- lapply(seq_len(nrow(mine)), function(i) {
    fit <- fits[[i]] %||% list(taxon = mine$taxon[[i]], status = "no fitting job found")
    released <- atlas_repro_release_fits(store, base, mine$taxon[[i]], mine$algorithm[[i]], grid)[[1]]
    released_graded <- atlas_e12_release_grade(store, base, mine$taxon[[i]], mine$algorithm[[i]], grid)
    list(taxon = mine$taxon[[i]], algorithm = mine$algorithm[[i]], fingerprint = mine$fingerprint[[i]],
         band = mine$band[[i]], cell = mine$cell[[i]], rank = mine$rank[[i]],
         fit = fit, release = c(released, released_graded),
         same_records = identical(as.character(fit$fingerprint %||% ""), mine$fingerprint[[i]]),
         same_grade = identical(fit$grade, released_graded$grade),
         against_release = atlas_repro_compare(released, fit))
  })
  result <- list(
    study = "e12-arm", label = label, release = release, shard = shard, order = order, workers = workers,
    sample_key = sample_key, drawn = drawn, cost = attr(models, "cost"),
    machine = atlas_machine_info(), image_commit = Sys.getenv("ATLAS_COMMIT", unset = NA),
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    summary = list(
      models = length(results),
      fitted = sum(vapply(results, function(r) identical(r$fit$status, "fitted"), logical(1))),
      same_records = sum(vapply(results, function(r) isTRUE(r$same_records), logical(1))),
      same_grade = sum(vapply(results, function(r) isTRUE(r$same_grade), logical(1))),
      identical_to_release = sum(vapply(results, function(r) isTRUE(r$against_release$identical), logical(1)))
    ),
    models = results
  )
  where <- atlas_study_out(out, "repro-studies", grid, paste("e12", label %||% "arm", release, gsub("/", "of", shard)))
  path <- file.path(where$dir, paste0(where$prefix, ".json"))
  atlas_write_json(result, path)
  if (!is.null(where$key)) atlas_study_publish(store, path, where$key, where$dir)
  s <- result$summary
  say(sprintf("  %d fitted of %d; same records %d; same grade as the release %d; identical to the release %d",
              s$fitted, s$models, s$same_records, s$same_grade, s$identical_to_release))
  # More than a few unfitted models fail the shard (its file kept), as for
  # every study (atlas_study_guard).
  atlas_study_guard(lapply(results, function(r) list(status = if (identical(r$fit$status, "fitted")) "fitted" else "failed",
                                                      error = r$fit$error %||% r$fit$status)),
                    "E12 arm")
  invisible(result)
}

#' The release's own grade and null test of one model, as the arms record
#' theirs.
atlas_e12_release_grade <- function(store, base, taxon, algorithm, grid = "draft") {
  files <- stats::setNames(base$files, vapply(base$files, function(f) f$path, ""))
  json <- files[[atlas_model_relpaths(taxon, grid, algorithm, ".json")]]
  if (is.null(json)) return(list(grade = NA_character_))
  file <- tempfile(fileext = ".json")
  on.exit(unlink(file), add = TRUE)
  store$get(atlas_object_key(json$sha256), file)
  m <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  full <- atlas_e12_fit_summary(m)
  full[c("grade", "skill", "null_p", "null_reps", "null_drawn", "map_strength")]
}
