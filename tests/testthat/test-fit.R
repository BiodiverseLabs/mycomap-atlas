# A synthetic world where the answer is known: suitability peaks at v1 = 1 and
# falls away from it, and v2 says nothing at all. A fit that cannot recover
# that is broken, however plausible its output looks.
simulated_training <- function(n_background = 2000, n_presence = 200, seed = 42) {
  set.seed(seed)
  background <- data.frame(
    v1 = stats::runif(n_background, -3, 3),
    v2 = stats::runif(n_background, -3, 3)
  )
  truth <- exp(-((background$v1 - 1)^2) / 0.5)
  drawn <- sample.int(n_background, n_presence, replace = TRUE, prob = truth)
  rbind(
    data.frame(presence = 1L, cell = seq_len(n_presence), x = 0, y = 0,
               background[drawn, , drop = FALSE]),
    data.frame(presence = 0L, cell = seq_len(n_background) + n_presence,
               x = 0, y = 0, background)
  )
}

test_that("bookkeeping columns are not offered to the model as predictors", {
  training <- simulated_training(n_background = 50, n_presence = 10)
  expect_equal(atlas_predictor_columns(training), c("v1", "v2"))
})

test_that("hinge features wait until there are records to support them", {
  expect_equal(atlas_feature_classes(12), "lq")
  expect_equal(atlas_feature_classes(29), "lq")
  expect_equal(atlas_feature_classes(30), "lqh")
})

test_that("points in the same block share a fold", {
  x <- c(0, 1000, 5000, 400000)
  y <- c(0, 0, 0, 0)
  folds <- atlas_spatial_folds(x, y, k = 2, block_km = 200)
  expect_equal(folds[1], folds[2])
  expect_equal(folds[2], folds[3])
})

test_that("folds are reproducible and split the blocks up", {
  x <- seq(0, 3e6, by = 1e5)
  y <- rep(0, length(x))
  first <- atlas_spatial_folds(x, y, k = 5, seed = 3L)
  again <- atlas_spatial_folds(x, y, k = 5, seed = 3L)
  expect_equal(first, again)
  expect_equal(length(unique(first)), 5L)
})

test_that("fewer blocks than folds gives fewer folds, not empty ones", {
  folds <- atlas_spatial_folds(c(0, 1e6, 2e6), c(0, 0, 0), k = 5, block_km = 200)
  expect_lte(length(unique(folds)), 3L)
  expect_gte(length(unique(folds)), 2L)
})

test_that("AUC is 1 when separation is perfect and 0.5 when there is none", {
  expect_equal(atlas_auc(c(3, 4, 5), c(0, 1, 2)), 1)
  expect_equal(atlas_auc(c(0, 1, 2), c(3, 4, 5)), 0)
  expect_equal(atlas_auc(c(1, 2, 3), c(1, 2, 3)), 0.5)
})

test_that("AUC ignores missing scores rather than returning nonsense", {
  expect_equal(atlas_auc(c(3, NA, 5), c(0, 1, 2)), 1)
  expect_true(is.na(atlas_auc(numeric(), c(1, 2))))
})

test_that("Boyce rewards a model that ranks presences honestly", {
  set.seed(1)
  background <- stats::runif(2000)
  presence <- stats::runif(400)^0.25 # crowded towards high suitability
  expect_gt(atlas_boyce(presence, background), 0.8)
})

test_that("Boyce is near zero for a model that says nothing", {
  set.seed(1)
  expect_lt(abs(atlas_boyce(stats::runif(400), stats::runif(2000))), 0.5)
})

test_that("Boyce goes negative when the model is upside down", {
  set.seed(1)
  background <- stats::runif(2000)
  presence <- 1 - stats::runif(400)^0.25
  expect_lt(atlas_boyce(presence, background), -0.8)
})

test_that("Boyce refuses to score what it cannot: too few records", {
  expect_true(is.na(atlas_boyce(c(0.5, 0.6), stats::runif(100))))
})

test_that("a fit recovers a response it was never told about", {
  skip_if_not_installed("maxnet")
  training <- simulated_training()
  model <- atlas_fit_maxnet(training)

  # Where does the fitted model think the optimum is?
  sweep <- data.frame(v1 = seq(-3, 3, by = 0.05), v2 = 0)
  suitability <- atlas_suitability(model, sweep)
  peak <- sweep$v1[which.max(suitability)]
  expect_lt(abs(peak - 1), 0.5)

  # And it prefers the optimum to ground far from it.
  expect_gt(
    atlas_suitability(model, data.frame(v1 = 1, v2 = 0)),
    atlas_suitability(model, data.frame(v1 = -3, v2 = 0))
  )
})

test_that("a fit separates presences from background on data it has seen", {
  skip_if_not_installed("maxnet")
  training <- simulated_training()
  model <- atlas_fit_maxnet(training)
  scores <- atlas_suitability(model, training[, c("v1", "v2")])
  expect_gt(atlas_auc(scores[training$presence == 1L], scores[training$presence == 0L]), 0.8)
})

test_that("a fit with almost no presences is refused rather than attempted", {
  skip_if_not_installed("maxnet")
  training <- simulated_training(n_background = 50, n_presence = 10)
  training$presence <- 0L
  training$presence[1] <- 1L
  expect_error(atlas_fit_maxnet(training), "at least two presences")
})

test_that("cross-validation scores every fold it can", {
  skip_if_not_installed("maxnet")
  training <- simulated_training()
  # Scatter the rows across blocks so the folds have something to hold out.
  set.seed(9)
  training$x <- stats::runif(nrow(training), 0, 3e6)
  folds <- atlas_spatial_folds(training$x, training$y, k = 4)

  scores <- atlas_cross_validate(training, folds)
  expect_equal(nrow(scores), length(unique(folds)))
  expect_true(all(c("fold", "presences", "auc", "boyce") %in% names(scores)))
  expect_gt(mean(scores$auc, na.rm = TRUE), 0.7)
})

test_that("a fold with no held-out presences scores NA instead of guessing", {
  skip_if_not_installed("maxnet")
  training <- simulated_training(n_background = 400, n_presence = 40)
  folds <- rep(1L, nrow(training))
  folds[training$presence == 0L][1:50] <- 2L # fold 2 holds background only

  scores <- atlas_cross_validate(training, folds)
  expect_true(is.na(scores$auc[scores$fold == 2L]))
  expect_equal(scores$presences[scores$fold == 2L], 0L)
})

test_that("a map file is named after the taxon, provisional names included", {
  with_data_dir({
    expect_match(atlas_model_path("Trametes versicolor"), "models/draft/trametes-versicolor.tif$")
    expect_match(atlas_model_path("Mycena sp. 'IN10'", "draft", ".json"),
                 "models/draft/mycena-sp-in10.json$")
    expect_match(atlas_model_path("Amanita muscaria", "production"), "models/production/")
  })
})
