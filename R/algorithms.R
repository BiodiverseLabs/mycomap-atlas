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
# tunes them.
ATLAS_MAXNET_GRID <- list(
  classes = c("lq", "lqh"),
  regmult = c(4, 2, 1, 0.5)
)

# Tree depths boosted trees try; the tree count is set by early stopping.
ATLAS_XGBOOST_DEPTHS <- c(2L, 3L, 5L)

# Trees in each forest while tuning. 250 trees ranked cells within 0.994
# (Spearman) of 1,000 on 24 taxa, at a sixth of the cost.
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
    learner = function() list(),
    fit = function(train, params, seed = 1L, tuning = FALSE) {
      atlas_fit_maxnet(train, classes = params$classes, regmult = params$regmult)
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
#' or the algorithm's, whichever is higher.
atlas_algorithm_min <- function(algo, min_presences = 20) {
  max(min_presences, algo$min_presences %||% 0)
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
