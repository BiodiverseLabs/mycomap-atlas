# The models Atlas fits, side by side.
#
# Every taxon can carry one fitted model per algorithm, each with its own map
# and scores, so people can compare what Maxent, boosted trees and a
# down-sampled random forest make of the same records. They share the training
# table, the sites and the spatial folds; only the learner differs.
#
# Each algorithm says how to fit with a set of settings, what its default
# settings are, and which settings are worth trying. Anything that reads a
# constant from another file is a function, because files load in
# alphabetical order and this one comes first. The candidates are tuned
# inside nested spatial folds (R/fit.R), so a choice of settings never sees the
# region it is scored on.
#
# Maxent keeps the paths it always had (models/<grid>/<taxon>.*); the others
# live in models/<grid>/<algorithm>/, so the maps fitted before there was a
# choice stay where they were.

# Maxent's candidates, strongest regularisation first so a tie goes to the
# simpler model. Regularisation multipliers and feature classes as ENMeval
# tunes them, reaching down to 0.25: on the 40-taxon pilot (2026-09-29) 0.5,
# then the weakest on offer, was the most frequent choice (21 of 39 final
# models, 90 of 195 folds), so the grid stopped short of where some taxa want
# to be.
ATLAS_MAXNET_GRID <- list(
  classes = c("lq", "lqh"),
  regmult = c(4, 2, 1, 0.5, 0.25)
)

# Trees in each boosted model of the null test.
ATLAS_XGBOOST_NULL_ROUNDS <- 200L
# Tree depths boosted trees try; the tree count is set by early stopping.
ATLAS_XGBOOST_DEPTHS <- c(2L, 3L, 5L)

# Trees in each forest while tuning and in the null test: as many as a map's
# forest has (R/forest.R).
ATLAS_RF_TUNE_TREES <- 250L

ATLAS_ALGORITHMS <- list(
  maxnet = list(
    label = "Maxent",
    # Maxent is a regression: correlated predictors blur its response curves,
    # so they are pruned and capped by the number of records.
    prune = TRUE,
    default = function(training) {
      list(classes = atlas_feature_classes(sum(training$presence == 1L)), regmult = 1)
    },
    grid = function(training) {
      combos <- expand.grid(regmult = ATLAS_MAXNET_GRID$regmult,
                            classes = ATLAS_MAXNET_GRID$classes,
                            stringsAsFactors = FALSE)
      lapply(seq_len(nrow(combos)), function(i) {
        list(classes = combos$classes[[i]], regmult = combos$regmult[[i]])
      })
    },
    grid_description = function() ATLAS_MAXNET_GRID,
    # Maxent leaves effort out. Measured twice on 150-odd taxa (2026-09-30),
    # it scored better without it: +0.017 +/- 0.002 and +0.020 +/- 0.002
    # blocked AUC, Boyce unchanged. The trees need it (the forest's Boyce
    # fell 0.084 +/- 0.013 without). Effort still weights the null models,
    # which are about where people collect, not what Maxent is given.
    use_effort = FALSE,
    learner = function() list(path_steps = ATLAS_MAXNET_PATH_STEPS, effort = FALSE),
    # features: a store through which fits of the same sites share their
    # feature matrices (atlas_feature_cache); the model is the same without.
    fit = function(train, params, seed = 1L, tuning = FALSE, features = NULL) {
      atlas_fit_maxnet(train, classes = params$classes, regmult = params$regmult,
                       use_effort = FALSE, features = features)
    },
    score = function(model, newdata) atlas_suitability(model, newdata),
    package = "maxnet"
  ),
  xgboost = list(
    label = "Boosted trees",
    prune = FALSE,
    # Benchmarked from 20 cells (2026-09-29): below 50 presence cells boosted
    # trees overfit, and at 20-29 cells their maps ranked ground backwards
    # (mean Boyce -0.15, 0.35 below Maxent). From 50 they match Maxent.
    min_presences = 50,
    default = function(training) list(max_depth = ATLAS_XGBOOST_PARAMS$max_depth),
    # The null test fits a hundred models; a fixed tree count spares each an
    # early-stopping search, and is the same for the taxon and its nulls.
    null_params = function(training) {
      list(max_depth = ATLAS_XGBOOST_PARAMS$max_depth, nrounds = ATLAS_XGBOOST_NULL_ROUNDS)
    },
    grid = function(training) {
      lapply(ATLAS_XGBOOST_DEPTHS, function(depth) list(max_depth = depth))
    },
    # Depth and tree count are tuned together: early stopping on the folds
    # gives each depth its best tree count and score in one pass.
    tune = function(training, folds, seed = 1L) {
      atlas_tune_xgboost(training, folds, seed = seed)
    },
    grid_description = function() {
      list(max_depth = ATLAS_XGBOOST_DEPTHS, nrounds = "early stopping")
    },
    learner = function() ATLAS_XGBOOST_PARAMS,
    fit = function(train, params, seed = 1L, tuning = FALSE) {
      atlas_fit_xgboost(
        train, nrounds = params$nrounds,
        params = utils::modifyList(
          ATLAS_XGBOOST_PARAMS,
          list(max_depth = params$max_depth %||% ATLAS_XGBOOST_PARAMS$max_depth)
        ),
        seed = seed
      )
    },
    score = function(model, newdata) atlas_xgboost_suitability(model, newdata),
    package = "xgboost"
  ),
  rf = list(
    label = "Random forest",
    prune = FALSE,
    default = function(training) {
      list(mtry = atlas_rf_default_mtry(length(atlas_predictor_columns(training))))
    },
    grid = function(training) {
      p <- length(atlas_predictor_columns(training))
      lapply(atlas_rf_mtry_candidates(p), function(m) list(mtry = m))
    },
    grid_description = function() {
      list(mtry = c("2", "sqrt(p)", "p/3"), tuning_trees = ATLAS_RF_TUNE_TREES)
    },
    learner = function() list(num_trees = ATLAS_RF_TREES, down_sampled = TRUE),
    fit = function(train, params, seed = 1L, tuning = FALSE) {
      atlas_fit_rf(
        train, seed = seed, mtry = params$mtry,
        num_trees = if (isTRUE(tuning)) ATLAS_RF_TUNE_TREES else ATLAS_RF_TREES
      )
    },
    score = function(model, newdata) atlas_rf_suitability(model, newdata),
    package = "ranger"
  ),
  esm = list(
    label = "Small-model ensemble",
    # Only for taxa with too few sites for the other three (R/esm.R). Thinned
    # to 8 sites, rich taxa kept Boyce within 0.04 of what all their sites
    # gave; at 5, half still showed clear skill (2026-09-30, 118 taxa).
    min_presences = 3,
    max_presences = 19,
    # Every ensemble is drawn, faint when it fails its null test (Steve,
    # 2026-10-04). Until then a map from 3 or 4 sites was drawn only when it
    # passed, but with so few sites the null models' AUC spreads so widely
    # (sd 0.25 at 3-4 sites, 0.18 at 5-7) that no map can beat all nineteen:
    # 64 of 1,801 passed, fewer than chance alone would let through. The test
    # cannot vouch for a sparse map either way, so the page says how often
    # maps of that size had clear skill on well-recorded fungi instead.
    # (map_needs_skill_below, still honoured by the fit, is left unset.)
    # Few sites are rarely spread over five blocks of up to 300 km (38% of
    # taxa with 5-7 sites, none with 3-4), so these taxa are scored on three
    # folds of 100 km blocks (98% and 80%).
    design = list(folds = 3L, block_km = 100, min_blocks = 3L),
    prune = TRUE,
    # Up to ten predictors in the guild's order, whatever the site count:
    # each small model takes only two.
    choose = function(training, correlation, priority, host_share) {
      c(atlas_esm_predictors(training, correlation = correlation, priority = priority,
                             host_share = host_share),
        intersect(ATLAS_EFFORT_COLUMN, names(training)))
    },
    default = function(training) list(),
    # The ensemble weighs its own small models; there is nothing to tune.
    grid = function(training) list(list()),
    grid_description = function() {
      list(pairs = "every pair of up to 10 predictors", weights = "Somers' D on inner blocks")
    },
    learner = function() {
      list(predictors = ATLAS_ESM_PREDICTORS, lambda = ATLAS_ESM_LAMBDA,
           inner_folds = ATLAS_ESM_INNER_FOLDS, inner_block_km = ATLAS_ESM_INNER_BLOCK_KM)
    },
    fit = function(train, params, seed = 1L, tuning = FALSE) {
      atlas_fit_esm(train, predictors = setdiff(atlas_predictor_columns(train), ATLAS_EFFORT_COLUMN),
                    seed = seed)
    },
    score = function(model, newdata) atlas_esm_suitability(model, newdata),
    package = "glmnet"
  )
)

#' One algorithm's definition, refusing names Atlas does not fit.
atlas_algorithm <- function(name = "maxnet") {
  name <- as.character(name %||% "maxnet")[[1]]
  if (!name %in% names(ATLAS_ALGORITHMS)) {
    stop("unknown algorithm '", name, "': use one of ",
         paste(names(ATLAS_ALGORITHMS), collapse = ", "), call. = FALSE)
  }
  c(list(id = name), ATLAS_ALGORITHMS[[name]])
}

#' The fewest detection sites an algorithm will map: the run's own minimum,
#' or the algorithm's, whichever is higher. An algorithm made for a range of
#' site counts (the small-model ensemble) keeps its own.
atlas_algorithm_min <- function(algo, min_presences = 20) {
  if (!is.null(algo$max_presences)) return(algo$min_presences)
  max(min_presences, algo$min_presences %||% 0)
}

#' The most detection sites an algorithm will map; beyond it the taxon gets
#' the other models.
atlas_algorithm_max <- function(algo) {
  algo$max_presences %||% Inf
}

#' Whether an algorithm holds back the map of a taxon with this many sites
#' until it passes its null test. algo is an algorithm or its id.
atlas_map_withheld_at <- function(algo, presences) {
  if (is.character(algo)) algo <- tryCatch(atlas_algorithm(algo), error = function(e) NULL)
  below <- algo$map_needs_skill_below %||% 0
  is.numeric(presences) && length(presences) == 1L && is.finite(presences) && presences < below
}

# Candidates are counted before sites without predictor data are dropped, so
# a range algorithm looks this many sites past its maximum and lets the fit
# refuse what is really too rich; a taxon counted at 20 that has 19 usable
# sites is refused by the others and must not fall between them.
ATLAS_RANGE_MARGIN <- 3

#' How an algorithm is scored: its own folds, block size and fewest blocks
#' when it has them, otherwise the run's.
atlas_algorithm_design <- function(algo, folds = 5, block_km = "auto",
                                   min_blocks = ATLAS_MIN_BLOCKS) {
  design <- algo$design %||% list()
  list(folds = design$folds %||% folds, block_km = design$block_km %||% block_km,
       min_blocks = design$min_blocks %||% min_blocks)
}

#' Delete a taxon's model for one algorithm: its scores and its map.
atlas_remove_model <- function(name, grid = "draft", algorithm = "maxnet") {
  paths <- atlas_model_path(name, grid, c(".json", ".tif", ".png", ".png.aux.xml"), algorithm)
  existed <- file.exists(paths)
  unlink(paths[existed])
  invisible(any(existed))
}

#' "maxnet,xgboost" or "all" as a vector of algorithm names.
atlas_parse_algorithms <- function(value) {
  if (is.null(value) || identical(value, TRUE)) {
    return("maxnet")
  }
  parts <- trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1]])
  if (identical(parts, "all")) {
    return(names(ATLAS_ALGORITHMS))
  }
  for (part in parts) atlas_algorithm(part)
  unique(parts)
}

#' The folder an algorithm's models live in.
atlas_model_dir <- function(grid = "draft", algorithm = "maxnet") {
  if (identical(algorithm, "maxnet")) {
    atlas_path("models", grid)
  } else {
    atlas_path("models", grid, algorithm)
  }
}
