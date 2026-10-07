# Boosted trees against Maxent, on the richest taxa.
#
# Every taxon is scored four ways on one training table and one set of
# spatial folds, so each comparison is the taxon against itself:
#
#   maxnet          what production fits: pruned, capped predictors
#   xgboost         boosted trees on every predictor, as they are normally used
#   xgboost-pruned  boosted trees on Maxent's predictors, which separates the
#                   algorithm from the choice of variables
#   rf              down-sampled random forest on every predictor
#
# An arm is an algorithm from ATLAS_ALGORITHMS, optionally with "-pruned" to
# give it Maxent's predictors instead of its own habit.
#
# The richest taxa, because that is where trees are expected to earn their
# keep; with twenty records Maxent's regularisation is the safer bet anyway.
# Nothing here writes a model.

ATLAS_BENCHMARK_ARMS <- c("maxnet", "xgboost", "xgboost-pruned", "rf")

# Boosted trees set up for few records, tried beside the production setting
# on the sparse bands, where that setting ranked ground backwards (Boyce
# below zero at 20-29 cells, 2026-09-29). For samples this small Elith,
# Leathwick & Hastie (2008, J Anim Ecol 77:802) advise simple trees (depth 1
# or 2), a slow learning rate and half the data per tree. And presences are
# weighted up to balance ten thousand background records, so a leaf of
# min_child_weight 5 can hold a single presence and a tree can wall off one
# collection site; here a leaf has to carry the weight of several.
ATLAS_BENCHMARK_VARIANTS <- list(
  "xgboost-small" = list(algorithm = "xgboost", max_depth = 2L, learning_rate = 0.01,
                         subsample = 0.5, leaf_presences = 3),
  "xgboost-stumps" = list(algorithm = "xgboost", max_depth = 1L, learning_rate = 0.01,
                          subsample = 0.5, leaf_presences = 3)
)
# Slow learning needs more trees before early stopping can tell.
ATLAS_BENCHMARK_VARIANT_ROUNDS <- 3000L
ATLAS_BENCHMARK_VARIANT_PATIENCE <- 100L

#' The algorithm behind a benchmark arm: its own, Maxent's predictors for a
#' "-pruned" arm, or the algorithm a variant sets up differently.
atlas_benchmark_algorithm <- function(arm) {
  variant <- ATLAS_BENCHMARK_VARIANTS[[arm]]
  atlas_algorithm(variant$algorithm %||% sub("-pruned$", "", arm))
}

#' The min_child_weight that makes a leaf hold the weight of `presences`
#' presences, given the balancing weights (atlas_balanced_weights). A row's
#' hessian is its weight times p(1 - p), a quarter where trees start.
atlas_leaf_weight <- function(presence, presences) {
  presence <- as.integer(presence)
  n1 <- sum(presence == 1L)
  n0 <- sum(presence == 0L)
  per_presence <- if (n1 && n0) n0 / n1 else 1
  presences * per_presence * 0.25
}

#' Fit a variant arm: production's boosted trees with the variant's settings.
atlas_fit_benchmark_variant <- function(variant, train, seed = 1L) {
  params <- utils::modifyList(ATLAS_XGBOOST_PARAMS, list(
    max_depth = variant$max_depth,
    learning_rate = variant$learning_rate,
    subsample = variant$subsample,
    min_child_weight = atlas_leaf_weight(train$presence, variant$leaf_presences)
  ))
  atlas_fit_xgboost(train, params = params, max_rounds = ATLAS_BENCHMARK_VARIANT_ROUNDS,
                    patience = ATLAS_BENCHMARK_VARIANT_PATIENCE, seed = seed)
}

# Bands of presence cells. The first benchmark started at 50, where boosted
# trees tied Maxent; in production their median Boyce over every taxon was
# about zero, so the sparse bands are here to see where they fall apart.
ATLAS_BENCHMARK_BANDS <- c(20, 30, 50, 100, 200)

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
    algo <- atlas_benchmark_algorithm(arm)
    variant <- ATLAS_BENCHMARK_VARIANTS[[arm]]
    keep <- if (grepl("-pruned$", arm) || isTRUE(algo$prune)) pruned else everything
    table <- training[, c(bookkeeping, keep), drop = FALSE]
    scores <- atlas_cross_validate(
      table, fold_ids,
      # Studies compare learners at their default settings; production tunes.
      fit = if (is.null(variant)) {
        function(train) algo$fit(train, algo$default(train), seed)
      } else {
        function(train) atlas_fit_benchmark_variant(variant, train, seed)
      },
      score = algo$score
    )
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
  for (arm in arms) {
    package <- atlas_benchmark_algorithm(arm)$package
    if (!requireNamespace(package, quietly = TRUE)) {
      stop(package, " is needed for the ", arm, " arm: install.packages('", package, "')",
           call. = FALSE)
    }
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
    variants = ATLAS_BENCHMARK_VARIANTS[intersect(arms, names(ATLAS_BENCHMARK_VARIANTS))],
    rf_trees = ATLAS_RF_TREES,
    versions = lapply(
      stats::setNames(nm = unique(vapply(arms, function(a) {
        atlas_benchmark_algorithm(a)$package
      }, character(1)))),
      function(p) as.character(utils::packageVersion(p))
    )
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
