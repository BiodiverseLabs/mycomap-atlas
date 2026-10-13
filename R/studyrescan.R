# The standard null test on a release's real models (paper E1c).
#
# Production grades a map against shifted nulls: the taxon's own pattern,
# rotated and moved to other surveyed ground. The test most studies run, and
# Atlas ran before, scatters null detections site by site instead (19 of
# them, Raes & ter Steege 2007). On virtual species the scattered test passes
# most maps of species that follow no habitat at all (E1b). E1c asks the same
# of the real atlas: of the maps the standard test calls good, how many are
# not shown to beat collecting by the shift test?
#
# So a sample of the release's models, stratified by learner x site band x
# grade, is put through the old test again: atlas_null_test with 19
# scattered nulls, the model's untuned settings and its own folds. Nothing is
# refitted for a map; only the null test runs. A model passes the old test
# when its AUC beats every null at p <= 0.05 and its pooled Boyce index (the
# release's own) is above 0, as production's atlas_skill decides.
#
# Each model's inputs are rebuilt from the release's pull as atlas_fit_taxon
# builds them (R/fit.R; copied, since the fit path is frozen until the
# full-view refresh has run). A rebuild is trusted only when it matches what
# the release recorded: the fingerprint, the detection-site count, the
# predictors, the block size, the detection sites in each fold, and the null
# test's own untuned AUC (recorded to 3 decimals). A model that differs is
# dropped and counted; more than ATLAS_RESCAN_MAX_DROPPED of them stops the
# reading (plan-e1c, 2026-10-13).
#
# The output is one row per model: its shift grade beside its scattered
# verdict, and the release's count of models in every stratum, from which the
# share is weighted back to the release. Nothing here writes a model.

ATLAS_RESCAN_BANDS <- c(3, 5, 20, 50, 100)
ATLAS_RESCAN_GRADES <- c("strong", "weak", "failed")
ATLAS_RESCAN_PER_CELL <- 50L
ATLAS_RESCAN_NULLS <- 19L
# The share of sampled models whose rebuild may differ from the release
# before the results are not to be read.
ATLAS_RESCAN_MAX_DROPPED <- 0.02
# Rough seconds per model for planning, by learner: 20 untuned
# cross-validations (the taxon and 19 nulls) on its folds.
ATLAS_RESCAN_PLAN_SECONDS <- c(maxnet = 150, rf = 90, xgboost = 150, esm = 60)

#' A model's id in a study: algorithm|taxon. Algorithm ids hold no "|".
atlas_rescan_id <- function(taxon, algorithm) paste0(algorithm, "|", taxon)

#' The taxon and algorithm a model id names.
atlas_rescan_parse <- function(id) {
  list(algorithm = sub("[|].*$", "", id), taxon = sub("^[^|]*[|]", "", id))
}

#' Every model of a release that can be rescanned, one row each: taxon,
#' algorithm, detection sites, band and grade. Untested and refused models
#' are left out, since they have no shift grade to compare.
atlas_rescan_population <- function(entries) {
  rows <- lapply(entries, function(e) {
    grade <- as.character(e$grade %||% NA)
    presences <- suppressWarnings(as.integer(e$presences %||% NA))
    if (isTRUE(e$refused) || !grade %in% ATLAS_RESCAN_GRADES || is.na(presences)) return(NULL)
    data.frame(taxon = as.character(e$taxon), algorithm = as.character(e$algorithm),
               presences = presences, grade = grade, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) {
    out <- data.frame(taxon = character(), algorithm = character(), presences = integer(),
                      grade = character(), stringsAsFactors = FALSE)
  }
  out$band <- atlas_presence_band(out$presences, ATLAS_RESCAN_BANDS)
  out$stratum <- paste(out$algorithm, out$band, out$grade, sep = " / ")
  out
}

#' Up to per_cell models from every stratum, all of a stratum that has fewer,
#' drawn reproducibly from seed. The draw is by stratum in a fixed order, so
#' a release with the same models always gives the same sample.
atlas_rescan_sample <- function(population, per_cell = ATLAS_RESCAN_PER_CELL, seed = 1L) {
  population <- population[order(population$stratum, population$taxon, population$algorithm), , drop = FALSE]
  set.seed(seed)
  picked <- lapply(split(seq_len(nrow(population)), population$stratum), function(rows) {
    if (length(rows) <= per_cell) rows else sort(rows[sample.int(length(rows), per_cell)])
  })
  out <- population[sort(unlist(picked, use.names = FALSE)), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Release models in each stratum: the weights the share is read with.
atlas_rescan_strata <- function(population, sample) {
  count <- function(x) if (nrow(x)) as.list(table(x$stratum)) else list()
  list(population = count(population), sampled = count(sample))
}

#' What a model's record says it was fitted on, kept small enough to send to
#' a worker: the fields the rebuild is checked against.
atlas_rescan_record <- function(metrics) {
  list(
    presences = suppressWarnings(as.integer(metrics$presences %||% NA)),
    predictors = as.character(unlist(metrics$predictors %||% list())),
    block_km = suppressWarnings(as.numeric(metrics$block_km %||% NA)),
    seed = suppressWarnings(as.integer(metrics$seed %||% NA)),
    fingerprint = as.character(metrics$fingerprint %||% NA),
    fold_presences = vapply(metrics$folds %||% list(), function(f) as.integer(f$presences %||% NA), 0L),
    observed_auc = suppressWarnings(as.numeric(metrics$null$observed_auc %||% NA)),
    boyce = suppressWarnings(as.numeric(metrics$boyce %||% NA)),
    grade = as.character(metrics$grade %||% NA),
    settings = as.character(metrics$null$settings %||% NA)
  )
}

#' A model's training table and folds, rebuilt from the pull as
#' atlas_fit_taxon builds them, with the predictors the release recorded.
#' The block size is the recorded one; the variogram is not run again.
atlas_rescan_inputs <- function(taxon, algorithm, record, points, stack, grid = "draft",
                                n_background = 10000, buffer_km = 500, thin_km = ATLAS_SITE_KM) {
  algo <- atlas_algorithm(algorithm)
  design <- atlas_algorithm_design(algo)
  training <- atlas_build_training(
    taxon, grid, n_background = n_background, buffer_km = buffer_km, write = FALSE,
    quiet = TRUE, points = points, stack = stack, fingerprint = record$fingerprint, thin_km = thin_km
  )
  if (isTRUE(algo$prune)) {
    keep <- c(intersect(record$predictors, names(training)),
              intersect(ATLAS_EFFORT_COLUMN, names(training)))
    kept <- attributes(training)[c("area_km2", "seed", "fingerprint", "dropped", "thin_km")]
    training <- training[, c("presence", "cell", "x", "y", keep), drop = FALSE]
    attributes(training)[names(kept)] <- kept
  }
  seed <- attr(training, "seed")
  folds <- atlas_spatial_folds(training$x, training$y, k = design$folds, block_km = record$block_km,
                               seed = seed, presence = training$presence)
  list(training = training, folds = folds, algo = algo, seed = seed)
}

#' Where a rebuild differs from the release's record, as short reasons; empty
#' when it matches. observed_auc is the untuned AUC of the taxon on its folds
#' (the null test's own), checked at the 3 decimals the release keeps.
atlas_rescan_differences <- function(inputs, record, fingerprint, observed_auc = NULL) {
  training <- inputs$training
  why <- character()
  if (!identical(as.character(fingerprint), record$fingerprint)) why <- c(why, "fingerprint")
  if (!identical(as.integer(sum(training$presence == 1L)), record$presences)) why <- c(why, "presences")
  used <- setdiff(atlas_predictor_columns(training), ATLAS_EFFORT_COLUMN)
  if (!setequal(used, record$predictors)) why <- c(why, "predictors")
  if (!identical(inputs$seed, record$seed)) why <- c(why, "seed")
  fold_presences <- vapply(sort(unique(inputs$folds)), function(f) {
    sum(training$presence[inputs$folds == f] == 1L)
  }, 0L)
  # A record that keeps no folds cannot vouch for them.
  if (!length(record$fold_presences)) {
    why <- c(why, "no folds recorded")
  } else if (!identical(as.integer(fold_presences), as.integer(record$fold_presences))) {
    why <- c(why, "folds")
  }
  if (!is.null(observed_auc) && is.finite(record$observed_auc) &&
      !(is.finite(observed_auc) && abs(round(observed_auc, 3) - record$observed_auc) <= 0.001 + 1e-9)) {
    why <- c(why, "observed_auc")
  }
  why
}

#' One model of the study: rebuild, check, run the old test, and set its
#' verdict beside its grade.
atlas_rescan_model <- function(name, fingerprint, points, stack, grid = "draft", records,
                               reps = ATLAS_RESCAN_NULLS, n_background = 10000, buffer_km = 500) {
  started <- Sys.time()
  seconds <- function() round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  model <- atlas_rescan_parse(name)
  record <- records[[name]]
  row <- list(taxon = name, model_taxon = model$taxon, algorithm = model$algorithm,
              presences = record$presences, band = atlas_presence_band(record$presences, ATLAS_RESCAN_BANDS),
              grade = record$grade)
  inputs <- atlas_rescan_inputs(model$taxon, model$algorithm, record, points, stack, grid = grid,
                                n_background = n_background, buffer_km = buffer_km)
  differs <- atlas_rescan_differences(inputs, record, fingerprint)
  if (length(differs)) {
    return(c(row, list(status = "mismatch", differs = as.list(differs), seconds = seconds())))
  }
  null <- atlas_null_test(inputs$training, inputs$folds, inputs$algo, reps = reps, seed = inputs$seed)
  differs <- atlas_rescan_differences(inputs, record, fingerprint, observed_auc = null$observed_auc %||% NA)
  if (length(differs)) {
    return(c(row, list(status = "mismatch", differs = as.list(differs),
                       observed_auc = null$observed_auc %||% NA, seconds = seconds())))
  }
  verdict <- atlas_skill(null, record$boyce)
  c(row, list(status = "scored",
              arms = list(list(arm = "scatter19", auc = null$observed_auc, p = null$auc_p,
                               nulls = null$reps, verdict = verdict)),
              scatter = list(reps = null$reps, observed_auc = null$observed_auc,
                             auc_mean = null$auc_mean, auc_p = null$auc_p,
                             boyce = record$boyce, verdict = verdict),
              seconds = seconds()))
}

#' The share each way, unweighted, by learner: passed the old test but not
#' strong, and strong but failed it. The weighted share is read from the
#' rows and the strata (the Paper Coordinator's reading); this is a check.
atlas_rescan_summary <- function(rows, baseline = NULL) {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  if (!length(scored)) return(data.frame())
  long <- data.frame(
    algorithm = vapply(scored, function(r) r$algorithm, ""),
    grade = vapply(scored, function(r) r$grade, ""),
    passed = vapply(scored, function(r) identical(r$scatter$verdict, "passed"), TRUE),
    stringsAsFactors = FALSE
  )
  out <- do.call(rbind, lapply(split(long, long$algorithm), function(x) data.frame(
    algorithm = x$algorithm[[1]], models = nrow(x), scatter_passed = sum(x$passed),
    passed_not_strong = sum(x$passed & x$grade != "strong"),
    strong_failed = sum(!x$passed & x$grade == "strong"), stringsAsFactors = FALSE
  )))
  rownames(out) <- NULL
  out
}

#' Whether the rows may be read: the share of sampled models with no
#' verdict, against ATLAS_RESCAN_MAX_DROPPED. A model whose rebuild differed
#' from the release and one whose run failed are both dropped: either way
#' the sample lost it.
atlas_rescan_health <- function(rows, max_dropped = ATLAS_RESCAN_MAX_DROPPED) {
  status <- vapply(rows, function(r) as.character(r$status %||% "unknown"), "")
  dropped <- sum(status != "scored")
  share <- if (length(status)) dropped / length(status) else 0
  list(models = length(status), dropped = dropped, mismatched = sum(status == "mismatch"),
       failed = sum(status == "failed"), dropped_share = round(share, 4),
       readable = share <= max_dropped)
}

#' The shards of one rescan read together: every shard's rows, the 2% rule
#' over all of them (a shard on its own can pass while the run fails), and
#' the summary. paths are the shards' results files; they must come from one
#' release, seed, sample size and null count, all from one split into n
#' shards, and no shard or model may appear twice. The run is readable only
#' with every shard 1..n there and every sampled model in it.
atlas_rescan_pool <- function(paths) {
  results <- lapply(paths, function(p) jsonlite::fromJSON(p, simplifyVector = FALSE))
  key <- function(r) paste(r$settings$release, r$settings$seed, r$settings$per_cell, r$settings$nulls)
  keys <- vapply(results, key, "")
  if (length(unique(keys)) != 1L) {
    stop("the results files are not shards of one rescan (release, seed, sample or nulls differ)", call. = FALSE)
  }
  shards <- vapply(results, function(r) as.character(r$settings$shard %||% "1/1"), "")
  if (anyDuplicated(shards)) stop("a shard appears twice: ", paste(shards[duplicated(shards)], collapse = ", "),
                                  call. = FALSE)
  splits <- unique(sub("^.*/", "", shards))
  if (length(splits) != 1L) {
    stop("the shards come from different splits (", paste(sort(shards), collapse = ", "), ")", call. = FALSE)
  }
  rows <- do.call(c, lapply(results, function(r) r$taxa))
  ids <- vapply(rows, function(r) as.character(r$taxon %||% NA), "")
  if (anyDuplicated(ids)) stop("a model appears in two shards: ", ids[duplicated(ids)][[1]], call. = FALSE)
  every_shard <- setequal(as.integer(sub("/.*$", "", shards)), seq_len(as.integer(splits)))
  sampled <- sum(unlist(results[[1]]$strata$sampled %||% list()))
  health <- atlas_rescan_health(rows)
  complete <- every_shard && length(rows) == sampled
  list(shards = sort(shards), models = length(rows), sampled = sampled,
       complete = complete, health = health,
       readable = isTRUE(health$readable) && complete,
       summary = atlas_rescan_summary(rows), strata = results[[1]]$strata, rows = rows)
}

#' Rough CPU-hours for a sample.
atlas_rescan_plan <- function(sample, seconds = ATLAS_RESCAN_PLAN_SECONDS) {
  per <- seconds[sample$algorithm]
  per[is.na(per)] <- max(seconds)
  list(models = nrow(sample), by_algorithm = as.list(table(sample$algorithm)),
       cpu_hours = round(sum(per) / 3600, 1))
}

#' Rescan a release's models with the standard test.
#'
#' release is the frozen release; its job's pull is the data the models were
#' fitted on. plan_only prints the sample's size and CPU-hours and stops.
atlas_rescan_study <- function(store = atlas_store(), release, grid = "draft",
                               per_cell = ATLAS_RESCAN_PER_CELL, seed = 1L,
                               reps = ATLAS_RESCAN_NULLS, out = NULL, shard = "1/1",
                               workers = 1L, plan_only = FALSE, quiet = FALSE, view = NULL) {
  view <- view %||% atlas_tracker_view(store, release, grid)
  population <- atlas_rescan_population(view$entries)
  sample <- atlas_rescan_sample(population, per_cell = per_cell, seed = seed)
  ids <- atlas_study_shard(atlas_rescan_id(sample$taxon, sample$algorithm), shard)
  plan <- atlas_rescan_plan(sample[atlas_rescan_id(sample$taxon, sample$algorithm) %in% ids, , drop = FALSE])
  if (isTRUE(plan_only)) {
    if (!isTRUE(quiet)) {
      message("standard-test rescan of release ", release, " (shard ", shard, ", seed ", seed, "): ",
              plan$models, " models of ", nrow(population), ", about ", plan$cpu_hours, " CPU-hours")
      print(unlist(plan$by_algorithm))
    }
    return(invisible(c(plan, list(strata = atlas_rescan_strata(population, sample)))))
  }
  out <- atlas_study_out(out, "rescan-studies", grid, release)
  records <- lapply(stats::setNames(ids, ids), function(id) {
    model <- atlas_rescan_parse(id)
    path <- atlas_model_relpaths(model$taxon, grid, model$algorithm, ".json")[[1]]
    json <- atlas_tracker_file(view, path, ".json")
    if (is.null(json)) stop("release ", release, " holds no record for ", id, call. = FALSE)
    atlas_rescan_record(jsonlite::fromJSON(json, simplifyVector = FALSE))
  })
  pull <- atlas_tracker_release_pull(store, view$manifest, grid, view$cache)
  points <- atlas_occurrence_points(pull, grid)
  taxa <- vapply(ids, function(id) atlas_rescan_parse(id)$taxon, "")
  by_taxon <- atlas_fingerprints_for(pull, unique(taxa))
  fingerprints <- as.list(stats::setNames(unname(by_taxon[taxa]), ids))
  settings <- list(release = release, shard = shard, seed = seed, per_cell = per_cell,
                   nulls = reps, design = "scatter", test = "atlas_null_test, untuned, own folds",
                   bands = ATLAS_RESCAN_BANDS, max_dropped = ATLAS_RESCAN_MAX_DROPPED)
  result <- atlas_run_study(
    kind = "rescan-studies", file_prefix = out$prefix, taxon_fn = "atlas_rescan_model",
    sample = data.frame(scientific_name = ids, stringsAsFactors = FALSE),
    fingerprints = fingerprints, args = list(grid = grid, records = records, reps = reps),
    settings = settings, baseline = "scatter19", grid = grid, workers = workers,
    points = points, quiet = quiet, summarise = atlas_rescan_summary,
    extra = function(rows) list(health = atlas_rescan_health(rows),
                                strata = atlas_rescan_strata(population, sample),
                                counts = atlas_study_counts(rows)),
    detail = function(arm) sprintf("%s p=%s", arm$verdict, arm$p),
    opening = paste0(length(ids), " models of release ", release, " (shard ", shard, ", seed ",
                     seed, "): ", reps, " scattered nulls each")
  )
  # This shard's own health is a warning only; whether the run may be read is
  # decided over every shard together (atlas_rescan_pool).
  health <- atlas_rescan_health(result$taxa)
  if (!isTRUE(health$readable)) {
    warning(health$dropped, " of ", health$models, " models in this shard have no verdict ",
            "(more than ", 100 * ATLAS_RESCAN_MAX_DROPPED, "%): stop and report before reading ",
            "the results", call. = FALSE)
  }
  if (!is.null(out$key)) {
    files <- c(result$path, sub("[.]json$", ".log", result$path))
    atlas_study_publish(store, files[file.exists(files)], out$key, root = dirname(out$dir))
  }
  invisible(c(result, list(health = health)))
}
