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

test_that("the settings record the method, so changing it makes every model stale", {
  settings <- atlas_fit_settings(layers = "L1")
  expect_equal(settings$algorithm, "maxnet")
  expect_equal(settings$block_km, "auto")
  expect_equal(settings$priority$ectomycorrhizal[[1]], "soil_phh2o")
  expect_equal(settings$priority$other[[1]], "soil_phh2o")
  expect_true(all(c("unit", "effort", "block", "tuning") %in% names(settings$design)))
  base <- atlas_settings_key(settings)
  expect_false(base == atlas_settings_key(atlas_fit_settings(layers = "L1", nulls = 0)))
  expect_false(base == atlas_settings_key(atlas_fit_settings(layers = "L1", tune = FALSE)))
  expect_false(base == atlas_settings_key(atlas_fit_settings(layers = "L1", thin_km = 10)))
  expect_false(base == atlas_settings_key(atlas_fit_settings(layers = "L1", block_km = 200)))
})

test_that("Maxent tries every feature class with regularisation down to 0.25, strongest first", {
  grid <- atlas_algorithm("maxnet")$grid(NULL)
  expect_length(grid, 10L)
  regmult <- vapply(grid, function(p) p$regmult, numeric(1))
  classes <- vapply(grid, function(p) p$classes, character(1))
  for (cls in c("lq", "lqh")) {
    expect_equal(regmult[classes == cls], c(4, 2, 1, 0.5, 0.25))
  }
  # A wider grid is a different method: every Maxent model goes stale.
  expect_equal(atlas_fit_settings(layers = "L1")$tuning$regmult, c(4, 2, 1, 0.5, 0.25))
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
    forest <- run_batch(world, algorithm = "rf")
    expect_equal(forest$counts$fitted, 2L)
    expect_equal(forest$counts$skipped, 0L)
    expect_equal(run_batch(world, algorithm = "rf")$counts$skipped, 2L)
    expect_true(file.exists(atlas_path("batches", "draft", "latest-rf.json")))
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

test_that("a forest predicts in batches, and batching changes nothing", {
  skip_if_not_installed("ranger")
  training <- simulated_training(n_background = 500, n_presence = 60)
  model <- atlas_fit_rf(training, num_trees = 100)
  newdata <- data.frame(v1 = seq(-3, 3, length.out = 250), v2 = 0)
  expect_equal(
    atlas_rf_suitability(model, newdata, batch = 7L),
    atlas_rf_suitability(model, newdata, batch = 100000L)
  )
  expect_length(atlas_rf_suitability(model, newdata[0, ]), 0L)
})

test_that("boosted trees are not fitted below 50 presence cells; other models are", {
  expect_equal(atlas_algorithm_min(atlas_algorithm("xgboost"), 20), 50)
  expect_equal(atlas_algorithm_min(atlas_algorithm("maxnet"), 20), 20)
  expect_equal(atlas_algorithm_min(atlas_algorithm("rf"), 20), 20)
  # A stricter run minimum still wins.
  expect_equal(atlas_algorithm_min(atlas_algorithm("xgboost"), 80), 80)
})

test_that("a sparse taxon is refused boosted trees, and its old tree map is removed", {
  skip_if_not_installed("terra")
  skip_if_not_installed("xgboost")
  with_data_dir({
    world <- synthetic_landscape()
    focal <- which(world$points$scientific_name == "Eastern fungus")
    sparse <- world$points[-focal[31:length(focal)], ]
    # A tree map from when the taxon had more cells.
    dir.create(atlas_model_dir("draft", "xgboost"), recursive = TRUE)
    writeLines("{}", atlas_model_path("Eastern fungus", "draft", ".json", "xgboost"))
    writeLines("old", atlas_model_path("Eastern fungus", "draft", ".png", "xgboost"))

    condition <- tryCatch(
      atlas_fit_taxon("Eastern fungus", points = sparse, stack = world$stack,
                      fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                      buffer_km = 300, quiet = TRUE, algorithm = "xgboost"),
      error = function(e) e
    )
    expect_s3_class(condition, "atlas_insufficient_evidence")
    expect_match(conditionMessage(condition), "needs 50")
    expect_false(file.exists(atlas_model_path("Eastern fungus", "draft", ".json", "xgboost")))
    expect_false(file.exists(atlas_model_path("Eastern fungus", "draft", ".png", "xgboost")))
  })
})

test_that("Maxent's settings hold the guild rule and the guild table; the trees' hold neither", {
  a <- atlas_guild_table_key(c(Amanita = "ectomycorrhizal"))
  b <- atlas_guild_table_key(c(Amanita = "ectomycorrhizal", Mycena = "litter_saprotroph"))
  maxent <- function(table) atlas_settings_key(atlas_fit_settings(layers = "L1", guild_table = table))
  expect_false(maxent(a) == maxent(b))
  for (trees in c("xgboost", "rf")) {
    key <- function(table) {
      atlas_settings_key(atlas_fit_settings(layers = "L1", algorithm = trees,
                                            prune = atlas_algorithm(trees)$prune, guild_table = table))
    }
    expect_equal(key(a), key(b), info = trees)
  }
  settings <- atlas_fit_settings(layers = "L1", guild_table = a)
  expect_equal(settings$priority$ectomycorrhizal, atlas_predictor_priority("ectomycorrhizal"))
  expect_equal(settings$priority$other, atlas_predictor_priority("unknown"))
  expect_equal(settings$priority$guild_table, a)
})

test_that("a forest is 250 trees, for a map as for tuning, and its settings say so", {
  skip_if_not_installed("ranger")
  expect_equal(ATLAS_RF_TREES, 250)
  expect_equal(ATLAS_RF_TUNE_TREES, 250L)
  algo <- atlas_algorithm("rf")
  expect_equal(algo$learner()$num_trees, 250)
  set.seed(2)
  training <- data.frame(presence = rep(c(1L, 0L), c(30, 300)), cell = 1:330, x = 0, y = 0,
                         v1 = stats::runif(330), v2 = stats::runif(330))
  expect_equal(algo$fit(training, list(mtry = 1), 1L)$num.trees, 250)
  expect_equal(algo$fit(training, list(mtry = 1), 1L, tuning = TRUE)$num.trees, 250)
  # The tree count is part of what makes a stored forest current.
  settings <- atlas_fit_settings(algorithm = "rf", layers = "x", guild_table = "g")
  expect_equal(settings$learner$num_trees, 250)
  thousand <- settings
  thousand$learner$num_trees <- 1000
  expect_false(identical(atlas_settings_key(settings), atlas_settings_key(thousand)))
})
