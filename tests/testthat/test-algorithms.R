# Three models side by side: Maxent, boosted trees, down-sampled random forest.

test_that("only the models Atlas fits are accepted", {
  expect_equal(atlas_algorithm("xgboost")$id, "xgboost")
  expect_error(atlas_algorithm("glm"), "unknown algorithm 'glm'")
})

test_that("--algorithms reads a list, or all of them", {
  expect_equal(atlas_parse_algorithms("maxnet,rf"), c("maxnet", "rf"))
  expect_equal(atlas_parse_algorithms("all"), names(ATLAS_ALGORITHMS))
  expect_equal(atlas_parse_algorithms(NULL), "maxnet")
  expect_error(atlas_parse_algorithms("maxnet,svm"), "unknown algorithm")
})

test_that("Maxent's settings are exactly what they were before there was a choice", {
  # If the key changed, every map fitted before would go stale at once.
  settings <- atlas_fit_settings(layers = "L1")
  expect_null(settings$algorithm)
  expect_null(settings$learner)
  expect_equal(sort(names(settings)),
               sort(c("grid", "n_background", "buffer_km", "folds", "block_km",
                      "regmult", "correlation", "layers")))
})

test_that("each model has its own settings key", {
  keys <- vapply(names(ATLAS_ALGORITHMS), function(a) {
    atlas_settings_key(atlas_fit_settings(layers = "L1", algorithm = a))
  }, character(1))
  expect_equal(length(unique(keys)), length(keys))
})

test_that("Maxent keeps its paths and the others get a folder each", {
  with_data_dir({
    expect_match(atlas_model_path("Trametes versicolor"), "models/draft/trametes-versicolor.tif$")
    expect_match(atlas_model_path("Trametes versicolor", algorithm = "xgboost"),
                 "models/draft/xgboost/trametes-versicolor.tif$")
    expect_match(atlas_model_path("Trametes versicolor", "draft", ".json", "rf"),
                 "models/draft/rf/trametes-versicolor.json$")
  })
})

test_that("a down-sampled forest recovers a response it was never told about", {
  skip_if_not_installed("ranger")
  training <- simulated_training()
  model <- atlas_fit_rf(training, num_trees = 300)
  sweep <- data.frame(v1 = seq(-3, 3, by = 0.05), v2 = 0)
  suitability <- atlas_rf_suitability(model, sweep)
  expect_lt(abs(sweep$v1[which.max(suitability)] - 1), 0.5)
})

test_that("down-sampling lets a rare species win votes where it lives", {
  skip_if_not_installed("ranger")
  # 20 presences against 2,000 background: a forest grown on everything would
  # vote "background" almost everywhere. Down-sampled, the optimum is a clear
  # majority for presence.
  training <- simulated_training(n_background = 2000, n_presence = 20)
  model <- atlas_fit_rf(training, num_trees = 300)
  expect_gt(atlas_rf_suitability(model, data.frame(v1 = 1, v2 = 0)), 0.5)
  expect_lt(atlas_rf_suitability(model, data.frame(v1 = -3, v2 = 0)), 0.3)
})

test_that("a forest with almost no presences is refused", {
  skip_if_not_installed("ranger")
  training <- simulated_training(n_background = 50, n_presence = 10)
  training$presence <- 0L
  training$presence[1] <- 1L
  expect_error(atlas_fit_rf(training), "at least two presences")
})

for (algorithm in c("xgboost", "rf")) {
  test_that(paste("a", algorithm, "fit writes its own map and scores beside Maxent's"), {
    skip_if_not_installed("terra")
    skip_if_not_installed("maxnet")
    skip_if_not_installed(atlas_algorithm(algorithm)$package)
    with_data_dir({
      world <- synthetic_landscape()
      fit <- function(which) {
        atlas_fit_taxon(
          "Eastern fungus", points = world$points, stack = world$stack,
          fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
          buffer_km = 300, quiet = TRUE, algorithm = which
        )
      }
      maxent <- fit("maxnet")
      other <- fit(algorithm)

      expect_equal(other$metrics$algorithm, algorithm)
      expect_true(file.exists(atlas_model_path("Eastern fungus", algorithm = algorithm)))
      expect_true(file.exists(atlas_model_path("Eastern fungus", "draft", ".png", algorithm)))
      expect_gt(other$metrics$auc_mean, 0.6)
      # Maxent's files are where they were, and still Maxent's.
      expect_equal(atlas_read_metrics("Eastern fungus")$algorithm, "maxnet")
      expect_equal(atlas_read_metrics("Eastern fungus")$auc_mean, maxent$metrics$auc_mean)

      settings <- atlas_fit_settings(n_background = 500, buffer_km = 300,
                                     layers = "synthetic", algorithm = algorithm,
                                     prune = atlas_algorithm(algorithm)$prune)
      stored <- atlas_read_metrics("Eastern fungus", algorithm = algorithm)
      expect_true(atlas_fit_is_current(stored, "f00dfeed", settings, predict = TRUE))
      expect_false(atlas_fit_is_current(
        atlas_read_metrics("Eastern fungus"), "f00dfeed", settings, predict = TRUE
      ))
    })
  })
}

test_that("a batch of one model does not count another's fits as current", {
  with_data_dir({
    world <- batch_world()
    first <- run_batch(world)
    expect_equal(first$counts$fitted, 2L)
    trees <- run_batch(world, algorithm = "xgboost")
    expect_equal(trees$counts$fitted, 2L)
    expect_equal(trees$counts$skipped, 0L)
    expect_equal(run_batch(world, algorithm = "xgboost")$counts$skipped, 2L)
    expect_true(file.exists(atlas_path("batches", "draft", "latest-xgboost.json")))
  })
})

test_that("the model list carries every algorithm, and says which is which", {
  with_data_dir({
    world <- batch_world()
    run_batch(world)
    run_batch(world, algorithm = "rf")
    index <- atlas_model_index("draft")
    expect_equal(nrow(index), 4L)
    expect_setequal(unique(index$algorithm), c("maxnet", "rf"))
  })
})

test_that("the folder a model sits in decides which model it is", {
  with_data_dir({
    # Metrics written before there was a choice carry no algorithm at all.
    dir.create(atlas_model_dir("draft", "rf"), recursive = TRUE)
    atlas_write_json(list(taxon = "Old record", built_at = "2026-01-01T00:00:00Z"),
                     atlas_model_path("Old record", "draft", ".json", "rf"))
    expect_equal(atlas_model_index("draft")$algorithm, "rf")
  })
})
