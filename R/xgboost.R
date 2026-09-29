# Boosted trees, as the benchmark for Maxent.
#
# Maxent is the default because it behaves well with few records. Boosted
# trees are the usual challenger on well-recorded species: they find
# interactions Maxent's features cannot, and they shrug off correlated
# predictors. Whether that shows up in the scores is an empirical question,
# which the benchmark answers on the same training tables and the same spatial
# folds as Maxent.
#
# Two choices matter.
#
# Weights. Against ten thousand background records, twenty presences would be
# drowned out, so presences and background carry equal total weight — the
# usual advice for boosted trees on presence-background data.
#
# How many trees. Too many and the model memorises the training blocks. The
# count is chosen by early stopping on spatially blocked folds inside the
# training data only: the region held out for scoring is never seen, so the
# choice cannot leak into the score.

ATLAS_XGBOOST_PARAMS <- list(
  objective = "binary:logistic",
  eval_metric = "auc",
  learning_rate = 0.05,
  max_depth = 3,
  min_child_weight = 5,
  subsample = 0.75,
  colsample_bytree = 0.8,
  # One thread per fit: a batch already runs one fit per core.
  nthread = 1
)

#' Weights that give presences and background equal say.
atlas_balanced_weights <- function(presence) {
  presence <- as.integer(presence)
  n1 <- sum(presence == 1L)
  n0 <- sum(presence == 0L)
  if (!n1 || !n0) {
    return(rep(1, length(presence)))
  }
  ifelse(presence == 1L, n0 / n1, 1)
}

#' Fit boosted trees to a training table.
#'
#' The number of trees comes from early stopping on inner spatial folds unless
#' nrounds is given. The chosen count is kept on the model as
#' attr(model, "nrounds").
atlas_fit_xgboost <- function(training, nrounds = NULL, params = ATLAS_XGBOOST_PARAMS,
                              max_rounds = 1000, patience = 30, inner_folds = 3,
                              block_km = 200, seed = 1L) {
  if (!requireNamespace("xgboost", quietly = TRUE)) {
    stop("xgboost is needed to fit: install.packages('xgboost')", call. = FALSE)
  }
  presence <- as.integer(training$presence)
  if (sum(presence == 1L) < 2L) {
    stop("a fit needs at least two presences", call. = FALSE)
  }
  predictors <- atlas_predictor_columns(training)
  data <- xgboost::xgb.DMatrix(
    as.matrix(training[, predictors, drop = FALSE]),
    label = presence,
    weight = atlas_balanced_weights(presence)
  )
  params$seed <- seed

  if (is.null(nrounds)) {
    nrounds <- atlas_xgboost_rounds(
      training, data, params, max_rounds, patience, inner_folds, block_km, seed
    )
  }
  model <- xgboost::xgb.train(params = params, data = data, nrounds = nrounds, verbose = 0)
  attr(model, "nrounds") <- nrounds
  attr(model, "predictors") <- predictors
  model
}

#' Early stopping on spatial blocks inside the training data.
atlas_xgboost_rounds <- function(training, data, params, max_rounds, patience,
                                 inner_folds, block_km, seed) {
  inner <- atlas_spatial_folds(training$x, training$y, k = inner_folds,
                               block_km = block_km, seed = seed + 1L)
  # A fold with no presence cannot be scored by AUC; fall back to a fixed
  # count rather than stop on nothing.
  usable <- vapply(sort(unique(inner)), function(fold) {
    any(training$presence[inner == fold] == 1L) && any(training$presence[inner != fold] == 1L)
  }, logical(1))
  if (length(usable) < 2L || !all(usable)) {
    return(200L)
  }
  folds <- lapply(sort(unique(inner)), function(fold) which(inner == fold))
  cv <- xgboost::xgb.cv(
    params = params, data = data, nrounds = max_rounds, folds = folds,
    early_stopping_rounds = patience, maximize = TRUE, verbose = 0
  )
  best <- cv$early_stop$best_iteration %||% attr(cv, "best_iteration") %||% max_rounds
  max(1L, as.integer(best))
}

#' Suitability from boosted trees: the fitted probability, which ranks places
#' the way AUC and Boyce need.
atlas_xgboost_suitability <- function(model, newdata) {
  predictors <- attr(model, "predictors") %||% names(newdata)
  as.numeric(stats::predict(model, as.matrix(newdata[, predictors, drop = FALSE])))
}
