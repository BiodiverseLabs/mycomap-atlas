# Boosted trees, the benchmark for Maxent.

test_that("presences and background carry equal total weight", {
  presence <- c(rep(1L, 20), rep(0L, 1000))
  weights <- atlas_balanced_weights(presence)
  expect_equal(sum(weights[presence == 1L]), sum(weights[presence == 0L]))
  expect_true(all(weights[presence == 0L] == 1))
})

test_that("weights stay plain when one side is missing", {
  expect_equal(atlas_balanced_weights(c(0L, 0L)), c(1, 1))
})

test_that("boosted trees recover a response they were never told about", {
  skip_if_not_installed("xgboost")
  training <- simulated_training()
  model <- atlas_fit_xgboost(training, nrounds = 200)
  sweep <- data.frame(v1 = seq(-3, 3, by = 0.05), v2 = 0)
  suitability <- atlas_xgboost_suitability(model, sweep)
  peak <- sweep$v1[which.max(suitability)]
  expect_lt(abs(peak - 1), 0.5)
  expect_gt(
    atlas_xgboost_suitability(model, data.frame(v1 = 1, v2 = 0)),
    atlas_xgboost_suitability(model, data.frame(v1 = -3, v2 = 0))
  )
})

test_that("boosted trees separate presences from background, scored on held-out blocks", {
  skip_if_not_installed("xgboost")
  training <- simulated_training()
  set.seed(9)
  training$x <- stats::runif(nrow(training), 0, 3e6)
  folds <- atlas_spatial_folds(training$x, training$y, k = 4)
  scores <- atlas_cross_validate(
    training, folds,
    fit = function(train) atlas_fit_xgboost(train),
    score = atlas_xgboost_suitability
  )
  expect_equal(nrow(scores), length(unique(folds)))
  expect_gt(mean(scores$auc, na.rm = TRUE), 0.7)
})

test_that("the tree count is chosen by early stopping, and a given count is kept", {
  skip_if_not_installed("xgboost")
  training <- simulated_training()
  set.seed(9)
  training$x <- stats::runif(nrow(training), 0, 3e6)
  chosen <- atlas_fit_xgboost(training, max_rounds = 400)
  expect_gte(attr(chosen, "nrounds"), 1L)
  expect_lt(attr(chosen, "nrounds"), 400L)
  expect_equal(attr(atlas_fit_xgboost(training, nrounds = 17), "nrounds"), 17)
})

test_that("inner folds without presences fall back to a fixed count", {
  skip_if_not_installed("xgboost")
  training <- simulated_training()
  # Every row in one block: the inner folds cannot hold a presence out.
  expect_equal(attr(atlas_fit_xgboost(training), "nrounds"), 200L)
})

test_that("a fit with almost no presences is refused", {
  skip_if_not_installed("xgboost")
  training <- simulated_training(n_background = 50, n_presence = 10)
  training$presence <- 0L
  training$presence[1] <- 1L
  expect_error(atlas_fit_xgboost(training), "at least two presences")
})

test_that("cross-validation hands every fold to the fitter it is given", {
  training <- simulated_training(n_background = 200, n_presence = 40)
  folds <- rep(1:4, length.out = nrow(training))
  calls <- 0L
  scores <- atlas_cross_validate(
    training, folds,
    fit = function(train) {
      calls <<- calls + 1L
      "a model"
    },
    score = function(model, newdata) newdata$v1
  )
  expect_equal(calls, 4L)
  expect_equal(nrow(scores), 4L)
})
