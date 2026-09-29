# Boosted trees against Maxent, on the richest taxa.
#
# Every taxon is scored three ways on one training table and one set of
# spatial folds, so each comparison is the taxon against itself:
#
#   maxnet          what production fits: pruned, capped predictors
#   xgboost         boosted trees on every predictor, as they are normally used
#   xgboost-pruned  boosted trees on Maxent's predictors, which separates the
#                   algorithm from the choice of variables
#
# The richest taxa, because that is where trees are expected to earn their
# keep; with twenty records Maxent's regularisation is the safer bet anyway.
# Nothing here writes a model.

ATLAS_BENCHMARK_ARMS <- c("maxnet", "xgboost", "xgboost-pruned")

# Richer bands than the sweep's: the benchmark starts at 50 presence cells.
ATLAS_BENCHMARK_BANDS <- c(50, 100, 200)

#' Score one taxon under every arm, on one set of folds.
atlas_benchmark_taxon <- function(name, fingerprint, points, stack,
                                  arms = ATLAS_BENCHMARK_ARMS, grid = "draft",
                                  n_background = 10000, buffer_km = 500, folds = 5,
                                  block_km = 200, regmult = 1, correlation = 0.7,
                                  min_presences = 50) {
  started <- Sys.time()
  training <- atlas_build_training(
    name, grid, n_background = n_background, buffer_km = buffer_km,
    write = FALSE, quiet = TRUE, points = points, stack = stack,
    fingerprint = fingerprint
  )
  presences <- sum(training$presence == 1L)
  if (presences < min_presences) {
    return(list(taxon = name, status = "refused", presences = presences))
  }
  seed <- attr(training, "seed")
  fold_ids <- atlas_spatial_folds(
    training$x, training$y, k = folds, block_km = block_km, seed = seed
  )
  pruned <- atlas_choose_predictors(training, threshold = correlation)
  everything <- atlas_predictor_columns(training)
  bookkeeping <- c("presence", "cell", "x", "y")

  run_arm <- function(arm) {
    arm_started <- Sys.time()
    if (arm == "maxnet") {
      table <- training[, c(bookkeeping, pruned), drop = FALSE]
      scores <- atlas_cross_validate(table, fold_ids, regmult = regmult)
    } else {
      keep <- if (arm == "xgboost-pruned") pruned else everything
      table <- training[, c(bookkeeping, keep), drop = FALSE]
      scores <- atlas_cross_validate(
        table, fold_ids,
        fit = function(train) atlas_fit_xgboost(train, block_km = block_km, seed = seed),
        score = atlas_xgboost_suitability
      )
    }
    list(
      arm = arm,
      predictors = length(atlas_predictor_columns(table)),
      auc = round(mean(scores$auc, na.rm = TRUE), 4),
      boyce = round(mean(scores$boyce, na.rm = TRUE), 4),
      folds_scored = sum(!is.na(scores$auc)),
      seconds = round(as.numeric(difftime(Sys.time(), arm_started, units = "secs")), 1)
    )
  }

  list(
    taxon = name, status = "scored", presences = presences,
    band = atlas_presence_band(presences, ATLAS_BENCHMARK_BANDS),
    arms = lapply(arms, run_arm),
    seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  )
}

#' Benchmark boosted trees against Maxent over the richest taxa.
#'
#' Up to per_band taxa from each band of presence cells (50-99, 100-199,
#' 200+), drawn reproducibly.
atlas_model_benchmark <- function(grid = "draft", per_band = 40, min_presences = 50,
                                  arms = ATLAS_BENCHMARK_ARMS, workers = 1L,
                                  seed = 1L, n_background = 10000, buffer_km = 500,
                                  folds = 5, block_km = 200, regmult = 1,
                                  correlation = 0.7, quiet = FALSE,
                                  occurrences = NULL, points = NULL, stack = NULL,
                                  taxa = NULL) {
  if (!requireNamespace("xgboost", quietly = TRUE)) {
    stop("xgboost is needed for the benchmark: install.packages('xgboost')", call. = FALSE)
  }
  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  candidates <- atlas_batch_candidates(points, min_presences, taxa = taxa)
  sample <- atlas_sweep_sample(candidates, per_band = per_band, seed = seed,
                               breaks = ATLAS_BENCHMARK_BANDS)
  fingerprints <- atlas_fingerprints_for(occurrences, sample$scientific_name)

  args <- list(
    arms = arms, grid = grid, n_background = n_background, buffer_km = buffer_km,
    folds = folds, block_km = block_km, regmult = regmult,
    correlation = correlation, min_presences = min_presences
  )
  settings <- c(args, list(
    per_band = per_band, seed = seed,
    xgboost = ATLAS_XGBOOST_PARAMS,
    xgboost_version = as.character(utils::packageVersion("xgboost")),
    maxnet_version = as.character(utils::packageVersion("maxnet"))
  ))
  atlas_run_study(
    kind = "benchmarks", file_prefix = "models", taxon_fn = "atlas_benchmark_taxon",
    sample = sample, fingerprints = fingerprints, args = args,
    settings = settings, baseline = "maxnet", grid = grid, workers = workers,
    points = points, stack = stack, quiet = quiet,
    opening = paste0(
      nrow(sample), " taxa sampled from ", nrow(candidates), " with ",
      min_presences, "+ presence cells (", atlas_band_counts(sample), "); arms: ",
      paste(arms, collapse = ", ")
    )
  )
}
