# Down-sampled random forest, the third model.
#
# A plain random forest against ten thousand background records and twenty
# presences learns to say "background" everywhere. Down-sampling fixes that at
# the root: every tree is grown on as many background records as there are
# presences, drawn afresh for each tree, so each tree sees a balanced problem
# and the forest still uses the whole background across its trees. Valavi et
# al. (2021, 2022) found this among the best presence-background methods,
# alongside boosted trees and Maxent.
#
# Averaging many independently grown trees also makes it a different animal
# from boosting, which fits trees in sequence and can chase noise on small
# samples — which is the point of keeping both.

ATLAS_RF_TREES <- 1000

#' Fit a down-sampled random forest to a training table.
atlas_fit_rf <- function(training, num_trees = ATLAS_RF_TREES, seed = 1L) {
  if (!requireNamespace("ranger", quietly = TRUE)) {
    stop("ranger is needed to fit: install.packages('ranger')", call. = FALSE)
  }
  presence <- as.integer(training$presence)
  n1 <- sum(presence == 1L)
  if (n1 < 2L) {
    stop("a fit needs at least two presences", call. = FALSE)
  }
  predictors <- atlas_predictor_columns(training)
  data <- training[, predictors, drop = FALSE]
  data$presence <- factor(presence, levels = c(0L, 1L))
  # Class-specific fractions of the whole table: n1 background and n1
  # presences per tree, with replacement.
  fraction <- n1 / nrow(data)
  model <- ranger::ranger(
    dependent.variable.name = "presence", data = data,
    num.trees = num_trees, probability = TRUE, replace = TRUE,
    sample.fraction = c(fraction, fraction),
    # One thread per fit: a batch already runs one fit per core.
    num.threads = 1, seed = seed
  )
  attr(model, "predictors") <- predictors
  model
}

# Rows handed to ranger at once when predicting. ranger keeps every tree's
# vote for every row before averaging, so memory grows with rows x trees: a
# map chunk of half a million rows took one worker to 4.5 GB, and twelve
# workers doing that at once ran a 64 GB machine out of memory. 20,000 rows is
# about 320 MB with a thousand trees.
ATLAS_RF_PREDICT_ROWS <- 20000L

#' Suitability from the forest: the share of trees voting "presence".
atlas_rf_suitability <- function(model, newdata, batch = ATLAS_RF_PREDICT_ROWS) {
  predictors <- attr(model, "predictors") %||% names(newdata)
  data <- newdata[, predictors, drop = FALSE]
  n <- nrow(data)
  out <- numeric(n)
  for (start in seq(1L, max(1L, n), by = batch)) {
    rows <- start:min(n, start + batch - 1L)
    if (!length(rows) || n == 0L) break
    predicted <- stats::predict(
      model, data = data[rows, , drop = FALSE], num.threads = 1, verbose = FALSE
    )$predictions
    out[rows] <- predicted[, "1"]
  }
  out
}
