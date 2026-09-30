# Ensembles of small models, for taxa with too few sites for a model of their
# own.
#
# A taxon found at eight sites cannot support a model of ten predictors: there
# is nothing left over to say whether the model is right. But it can support
# many models of two predictors each, and their average is steadier than any
# one of them and uses every predictor (Lomba et al. 2010; Breiner et al. 2015,
# 2018). Each small model here is a logistic regression on two predictors,
# their squares, and effort, with a ridge penalty so that eight detections
# cannot drive a coefficient to infinity, and with detections and
# non-detections given equal total weight. Each is scored on spatial blocks
# held out inside the training sites, and the ensemble is the average of the
# small models weighted by Somers' D (2 x AUC - 1); a small model that does no
# better than chance there has no say.
#
# The predictors are the first few of the taxon's pruned list, in the same
# ecological order Maxent uses and with the same allowance for host trees.

# Predictors an ensemble draws its pairs from: ten give forty-five pairs.
ATLAS_ESM_PREDICTORS <- 10L
# Ridge penalty of each small model, on standardised predictors.
ATLAS_ESM_LAMBDA <- 0.01
# Blocks held out inside the training sites to weigh the small models.
ATLAS_ESM_INNER_FOLDS <- 3L
ATLAS_ESM_INNER_BLOCK_KM <- 100

#' The predictors an ensemble's pairs are drawn from.
atlas_esm_predictors <- function(training, n = ATLAS_ESM_PREDICTORS, correlation = 0.7,
                                 priority = atlas_predictor_priority(),
                                 host_share = atlas_host_allowance()) {
  available <- setdiff(atlas_predictor_columns(training), ATLAS_EFFORT_COLUMN)
  background <- training[training$presence == 0L, available, drop = FALSE]
  kept <- atlas_prune_correlated(background, threshold = correlation, priority = priority)
  kept <- atlas_limit_hosts(kept, background, n, host_share)
  utils::head(kept, n)
}

#' The columns of one small model: two predictors, their squares, and effort
#' when the table has it.
atlas_esm_features <- function(data, pair, centre, scale) {
  a <- (data[[pair[1]]] - centre[[pair[1]]]) / scale[[pair[1]]]
  b <- (data[[pair[2]]] - centre[[pair[2]]]) / scale[[pair[2]]]
  out <- cbind(a = a, a2 = a^2, b = b, b2 = b^2)
  if (ATLAS_EFFORT_COLUMN %in% names(centre)) {
    out <- cbind(out, effort = (data[[ATLAS_EFFORT_COLUMN]] - centre[[ATLAS_EFFORT_COLUMN]]) /
                   scale[[ATLAS_EFFORT_COLUMN]])
  }
  out
}

#' Fit one small model: ridge logistic regression, detections and
#' non-detections weighing the same in total.
atlas_fit_small_model <- function(training, pair, centre, scale, lambda = ATLAS_ESM_LAMBDA) {
  if (!requireNamespace("glmnet", quietly = TRUE)) {
    stop("glmnet is needed for small models: install.packages('glmnet')", call. = FALSE)
  }
  x <- atlas_esm_features(training, pair, centre, scale)
  glmnet::glmnet(
    x, training$presence, family = "binomial", alpha = 0, lambda = lambda,
    weights = atlas_balanced_weights(training$presence), standardize = FALSE
  )
}

#' One small model's prediction, as a probability.
atlas_small_model_predict <- function(model, data, pair, centre, scale) {
  x <- atlas_esm_features(data, pair, centre, scale)
  as.numeric(stats::predict(model, newx = x, type = "response"))
}

#' Means and spreads the predictors are standardised by, from the training
#' sites. A predictor that does not vary gets a spread of 1.
atlas_esm_scaling <- function(training, columns) {
  centre <- vapply(columns, function(c) mean(training[[c]], na.rm = TRUE), numeric(1))
  scale <- vapply(columns, function(c) stats::sd(training[[c]], na.rm = TRUE), numeric(1))
  scale[!is.finite(scale) | scale == 0] <- 1
  list(centre = centre, scale = scale)
}

#' Fit an ensemble of small models to a training table.
#'
#' Returns the small models, the pair each was fitted on, and its weight.
#' When no small model beats chance on the inner blocks, or the inner blocks
#' cannot be scored at all (every detection in one block), the small models
#' weigh the same: an average of all of them is still the better guess.
atlas_fit_esm <- function(training, predictors = NULL, seed = 1L,
                          lambda = ATLAS_ESM_LAMBDA,
                          inner_folds = ATLAS_ESM_INNER_FOLDS,
                          inner_block_km = ATLAS_ESM_INNER_BLOCK_KM) {
  presence <- as.integer(training$presence)
  if (sum(presence == 1L) < 2L) {
    stop("a fit needs at least two presences", call. = FALSE)
  }
  predictors <- predictors %||% atlas_esm_predictors(training)
  if (length(predictors) < 2L) {
    stop("an ensemble needs at least two predictors that vary", call. = FALSE)
  }
  effort <- intersect(ATLAS_EFFORT_COLUMN, names(training))
  scaling <- atlas_esm_scaling(training, c(predictors, effort))
  pairs <- utils::combn(predictors, 2, simplify = FALSE)

  folds <- atlas_spatial_folds(training$x, training$y, k = inner_folds,
                               block_km = inner_block_km, seed = seed,
                               presence = presence)
  effort_at <- atlas_effort_level(training)
  somers <- vapply(pairs, function(pair) {
    held <- lapply(sort(unique(folds)), function(fold) {
      out <- folds == fold
      train <- training[!out, , drop = FALSE]
      test <- training[out, , drop = FALSE]
      if (sum(train$presence == 1L) < 2L || !any(test$presence == 1L) ||
          !any(test$presence == 0L)) {
        return(NULL)
      }
      if (length(effort)) test[[ATLAS_EFFORT_COLUMN]] <- effort_at
      model <- tryCatch(atlas_fit_small_model(train, pair, scaling$centre, scaling$scale, lambda),
                        error = function(e) NULL)
      if (is.null(model)) return(NULL)
      data.frame(
        presence = test$presence,
        score = atlas_small_model_predict(model, test, pair, scaling$centre, scaling$scale)
      )
    })
    held <- do.call(rbind, held)
    if (is.null(held)) return(NA_real_)
    2 * atlas_auc(held$score[held$presence == 1L], held$score[held$presence == 0L]) - 1
  }, numeric(1))

  weights <- ifelse(is.finite(somers) & somers > 0, somers, 0)
  if (!any(weights > 0)) {
    weights <- rep(1, length(pairs))
  }
  models <- lapply(pairs, function(pair) {
    tryCatch(atlas_fit_small_model(training, pair, scaling$centre, scaling$scale, lambda),
             error = function(e) NULL)
  })
  fitted <- !vapply(models, is.null, logical(1))
  weights[!fitted] <- 0
  if (!any(weights > 0)) {
    stop("no small model could be fitted", call. = FALSE)
  }
  structure(
    list(
      predictors = predictors,
      pairs = pairs[weights > 0],
      models = models[weights > 0],
      weights = weights[weights > 0] / sum(weights),
      somers = round(somers, 4),
      considered = length(pairs),
      centre = scaling$centre,
      scale = scaling$scale
    ),
    class = "atlas_esm"
  )
}

#' Suitability from an ensemble: the weighted average of its small models.
atlas_esm_suitability <- function(model, newdata) {
  out <- numeric(nrow(newdata))
  for (i in seq_along(model$models)) {
    out <- out + model$weights[[i]] * atlas_small_model_predict(
      model$models[[i]], newdata, model$pairs[[i]], model$centre, model$scale
    )
  }
  out
}
