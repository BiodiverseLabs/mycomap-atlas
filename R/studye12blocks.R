# Paper E12's block-only step: for every drawn full-design model (Maxent,
# random forest, boosted trees), the spatial block its fit would measure, and
# nothing else (docs/experiments, plan-e12-grade-stability, Reading). A full
# design's block is the blockCV variogram range rounded to 5 km (R/sites.R),
# and E6b found it can differ between processor families. The arms do not
# record their blocks, so this step measures them, once per family:
#
#   ./atlas plan-study --command=study-repro --shards=1 \
#     --args="--draw --blocks --release=<frozen> --label=r7i --workers=4"
#   ATLAS_EC2_INSTANCE_TYPES=r7i.2xlarge ./atlas run-job-ec2 --job=<ID>
#
# and again with --label=r7a on r7a.2xlarge. Fits are deterministic within a
# family, so each run's blocks are the ones that family's arm fitted on.
#
# Each model's training table is built as its fit builds it: the inputs and
# settings of the job that fitted it (atlas_refresh_sources), its own
# fingerprint, so the same sites and seed. No model is fitted and nothing but
# one results file under the study's prefix is written.

# The learners whose block is measured; the small-model ensemble's is a fixed
# 100 km (R/algorithms.R) and cannot differ.
ATLAS_E12_BLOCK_LEARNERS <- c("maxnet", "rf", "xgboost")

#' The drawn models whose block is measured: the full-design learners'.
atlas_e12_block_models <- function(models) {
  models[models$algorithm %in% ATLAS_E12_BLOCK_LEARNERS, , drop = FALSE]
}

#' In one process: each model's block, from a training table built as its fit
#' builds it. A model whose table cannot be built is reported, not fatal.
atlas_e12_block_worker <- function(models, fit_settings, grid = "draft",
                                   occurrences = NULL, points = NULL, stack = NULL) {
  s <- fit_settings
  if (is.null(points)) {
    occurrences <- occurrences %||% atlas_read_occurrences()
    points <- atlas_occurrence_points(occurrences, grid)
  }
  stack <- stack %||% atlas_predictor_stack(grid)
  lapply(seq_len(nrow(models)), function(i) {
    started <- Sys.time()
    row <- tryCatch({
      training <- atlas_build_training(
        models$taxon[[i]], grid,
        n_background = s$n_background %||% 10000, buffer_km = s$buffer_km %||% 500,
        write = FALSE, quiet = TRUE, points = points, stack = stack, occurrences = occurrences,
        fingerprint = models$fingerprint[[i]], thin_km = s$thin_km %||% ATLAS_SITE_KM
      )
      fixed <- s$block_km %||% "auto"
      block <- if (atlas_block_is_auto(fixed)) {
        atlas_block_size(training, seed = attr(training, "seed"))
      } else {
        list(block_km = as.numeric(fixed), range_km = NA_real_, source = "fixed")
      }
      list(status = "measured", presences = sum(training$presence == 1L),
           block_km = block$block_km, range_km = block$range_km, source = block$source)
    }, error = function(e) list(status = "failed", error = conditionMessage(e)))
    c(list(taxon = models$taxon[[i]], algorithm = models$algorithm[[i]]), row,
      list(seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)))
  })
}

#' The models in `workers` fresh processes, every workers-th model each, as
#' the arms deal them. Returns the rows in the models' order.
atlas_e12_block_workers <- function(models, fit_settings, grid = "draft", workers = 1L) {
  part <- atlas_e12_worker_parts(nrow(models), workers)
  if (max(part) <= 1L) return(atlas_e12_block_worker(models, fit_settings, grid))
  cluster <- parallel::makePSOCKcluster(max(part))
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  package <- utils::packageName()
  pieces <- lapply(seq_len(max(part)), function(w) models[part == w, , drop = FALSE])
  rows <- parallel::parLapply(cluster, pieces, function(piece, package, fit_settings, grid) {
    asNamespace(package)$atlas_e12_block_worker(piece, fit_settings, grid)
  }, package = package, fit_settings = fit_settings, grid = grid)
  out <- vector("list", nrow(models))
  for (w in seq_along(rows)) {
    at <- which(part == w)
    for (k in seq_along(at)) out[[at[[k]]]] <- rows[[w]][[k]]
  }
  out
}

#' The block a release's model was fitted on, from its metrics; NA when the
#' release has no model or no block for it.
atlas_e12_release_block <- function(store, base, taxon, algorithm, grid = "draft") {
  files <- stats::setNames(base$files, vapply(base$files, function(f) f$path, ""))
  json <- files[[atlas_model_relpaths(taxon, grid, algorithm, ".json")]]
  if (is.null(json)) return(NA_real_)
  file <- tempfile(fileext = ".json")
  on.exit(unlink(file), add = TRUE)
  store$get(atlas_object_key(json$sha256), file)
  m <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  suppressWarnings(as.numeric(m$block_km %||% NA))
}

#' One shard of the block-only step: the drawn full-design models' blocks on
#' this machine, each beside the block its release fit recorded. block_models
#' (atlas_e12_block_workers) and seconds are replaceable for tests.
atlas_e12_block_study <- function(store = atlas_store(), release, grid = "draft", out = NULL, shard = "1/1",
                                  label = NULL, workers = 1L, block_models = atlas_e12_block_workers,
                                  seconds = NULL, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (!is.null(out)) atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
  key <- paste0("releases/", grid, "/", release, ".json")
  if (!store$exists(key)) stop("no release ", release, " for the ", grid, " grid", call. = FALSE)
  base <- atlas_store_text(store, key)
  models <- atlas_e12_arm_models(store, base, grid, "seeded",
                                 seconds = seconds %||% atlas_e12_seconds(store, base, grid))
  sample_key <- attr(models, "sample_key")
  full <- atlas_e12_block_models(models)
  mine <- full[atlas_study_shard(seq_len(nrow(full)), shard), , drop = FALSE]
  tasks <- lapply(seq_len(nrow(mine)), function(i) {
    list(algorithm = mine$algorithm[[i]], taxon = mine$taxon[[i]], fingerprint = mine$fingerprint[[i]])
  })
  sources <- atlas_refresh_sources(store, base, tasks, grid)
  model_key <- paste(mine$algorithm, mine$taxon)
  mine$source_job <- vapply(model_key, function(k) sources$source[[k]] %||% NA_character_, "", USE.NAMES = FALSE)
  say("E12 blocks ", label %||% "", " (shard ", shard, "): ", nrow(mine), " full-design models of ",
      nrow(models), " drawn, on ", workers, " worker process(es)")
  measured <- vector("list", nrow(mine))
  for (job_id in unique(stats::na.omit(mine$source_job))) {
    job <- sources$jobs[[job_id]]
    rows <- which(mine$source_job %in% job_id)
    atlas_fetch_entries(store, job$inputs %||% list())
    got <- block_models(mine[rows, , drop = FALSE], job$fit %||% list(), grid, workers)
    for (k in seq_along(rows)) measured[[rows[[k]]]] <- c(got[[k]], list(source_job = job_id))
  }
  results <- lapply(seq_len(nrow(mine)), function(i) {
    row <- measured[[i]] %||% list(taxon = mine$taxon[[i]], algorithm = mine$algorithm[[i]],
                                   status = "no fitting job found")
    recorded <- atlas_e12_release_block(store, base, mine$taxon[[i]], mine$algorithm[[i]], grid)
    c(row, list(fingerprint = mine$fingerprint[[i]], band = mine$band[[i]], cell = mine$cell[[i]],
                release_block_km = recorded,
                same_as_release = isTRUE(all.equal(as.numeric(row$block_km %||% NA), recorded))))
  })
  status <- vapply(results, function(r) as.character(r$status %||% "unknown"), "")
  summary <- list(models = length(results), measured = sum(status == "measured"),
                  same_as_release = sum(vapply(results, function(r) isTRUE(r$same_as_release), logical(1))))
  result <- list(
    study = "e12-blocks", label = label, release = release, shard = shard, workers = workers,
    sample_key = sample_key, drawn = nrow(models), full_design = nrow(full),
    machine = atlas_machine_info(), image_commit = Sys.getenv("ATLAS_COMMIT", unset = NA),
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    summary = summary, models = results
  )
  where <- atlas_study_out(out, "repro-studies", grid, paste("e12-blocks", label %||% "run", release), shard = shard)
  path <- file.path(where$dir, paste0(where$prefix, ".json"))
  atlas_write_json(result, path)
  if (!is.null(where$key)) atlas_study_publish(store, path, where$key, where$dir)
  say(sprintf("  %d measured of %d; the same block as the release %d", summary$measured, summary$models,
              summary$same_as_release))
  atlas_study_guard(lapply(results, function(r) list(status = if (identical(r$status, "measured")) "measured" else "failed",
                                                      error = r$error %||% r$status)),
                    "E12 blocks")
  invisible(result)
}
