# A detection model: was the taxon found at a site, given how hard it was worked?
#
# Maxent compares detection sites with every site, each counted once. A site
# worked a hundred times had a hundred chances to turn the taxon up and a site
# worked once had one, so detections lean towards busy sites whatever the
# habitat. This model says so directly. If each record at a site is the taxon
# with a small chance that rises with the habitat, then
#
#   P(detected at site i) = 1 - exp(-lambda(x_i) * E_i),
#
# where E_i is the site's records and lambda the habitat's intensity. On the
# complementary log-log scale that is log lambda(x_i) + log E_i: a binomial
# regression with log effort as an offset (Fithian et al. 2015, as the
# thinning of a point process). Effort enters with a known coefficient of
# one, so the model cannot trade habitat for effort the way a fitted effort
# predictor can.
#
# It uses Maxent's features, regularisation and penalty path, so the two
# differ only in the likelihood. A map is drawn at the effort of a typical
# detection site, like every other model's.

#' Fit the detection model to a training table (presence, cell, x, y,
#' predictors, effort). classes and regmult as for atlas_fit_maxnet.
atlas_fit_detection <- function(training, classes = NULL, regmult = 1,
                                steps = ATLAS_MAXNET_PATH_STEPS) {
  if (!requireNamespace("maxnet", quietly = TRUE) || !requireNamespace("glmnet", quietly = TRUE)) {
    stop("maxnet and glmnet are needed to fit: install.packages(c('maxnet', 'glmnet'))",
         call. = FALSE)
  }
  if (!ATLAS_EFFORT_COLUMN %in% names(training)) {
    stop("the detection model needs the effort column", call. = FALSE)
  }
  columns <- setdiff(atlas_predictor_columns(training), ATLAS_EFFORT_COLUMN)
  predictors <- training[, columns, drop = FALSE]
  predictors <- predictors[, atlas_drop_constant(predictors), drop = FALSE]
  presence <- as.integer(training$presence)
  if (sum(presence == 1L) < 2L) {
    stop("a fit needs at least two presences", call. = FALSE)
  }
  if (anyNA(predictors)) {
    stop("NA values in data table. Please remove them and rerun.", call. = FALSE)
  }
  classes <- classes %||% atlas_feature_classes(sum(presence == 1L))
  f <- maxnet::maxnet.formula(presence, predictors, classes = classes)
  mm <- atlas_model_matrix(f, predictors)
  lower <- apply(mm, 2, min)
  upper <- apply(mm, 2, max)
  reg <- atlas_maxnet_regularization(presence, mm, lower, upper) * regmult
  offset <- training[[ATLAS_EFFORT_COLUMN]]
  # maxnet's path, with every site weighted once: its last penalty is the
  # mean regularisation times detections over sites.
  lambda <- 10^(seq(4, 0, length.out = steps)) * mean(reg) * sum(presence) / length(presence)
  model <- suppressWarnings(glmnet::glmnet(
    x = mm, y = presence, family = stats::binomial(link = "cloglog"),
    standardize = FALSE, penalty.factor = reg, lambda = lambda, offset = offset
  ))
  if (length(model$lambda) < steps) {
    stop("glmnet failed to complete the detection model's regularization path", call. = FALSE)
  }
  beta <- model$beta[, steps]
  out <- list(
    betas = beta[beta != 0],
    alpha = unname(model$a0[[steps]]),
    entropy = 0,
    featuremins = lower,
    featuremaxs = upper,
    varmin = apply(predictors, 2, min),
    varmax = apply(predictors, 2, max),
    lambda = model$lambda
  )
  class(out) <- c("atlas_detection", "maxnet")
  out
}

#' Chance of detecting the taxon at a site worked as hard as newdata's effort
#' says, clamped to the training range like Maxent. Without an effort column
#' it is the chance per record.
atlas_detection_suitability <- function(model, newdata) {
  link <- if (length(model$betas)) {
    as.numeric(stats::predict(model, newdata, type = "link", clamp = TRUE))
  } else {
    rep(model$alpha, nrow(newdata))
  }
  effort <- if (ATLAS_EFFORT_COLUMN %in% names(newdata)) newdata[[ATLAS_EFFORT_COLUMN]] else 0
  1 - exp(-exp(link + effort))
}
