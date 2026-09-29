# Boosted trees against Maxent, on shared folds.

test_that("the benchmark's bands start at 50 presence cells", {
  expect_equal(atlas_presence_band(c(55, 150, 400), ATLAS_BENCHMARK_BANDS),
               c("50-99", "100-199", "200+"))
})

test_that("band counts are listed smallest band first", {
  sample <- data.frame(band = c("200+", "50-99", "50-99", "100-199"))
  expect_equal(atlas_band_counts(sample), "50-99: 2, 100-199: 1, 200+: 1")
})

test_that("the summary compares every model with Maxent, AUC and Boyce alike", {
  arm <- function(name, auc, boyce) list(arm = name, predictors = 5, auc = auc, boyce = boyce)
  rows <- list(
    list(taxon = "A", status = "scored", presences = 60, band = "50-99",
         arms = list(arm("maxnet", 0.60, 0.20), arm("xgboost", 0.66, 0.30))),
    list(taxon = "B", status = "scored", presences = 150, band = "100-199",
         arms = list(arm("maxnet", 0.70, 0.40), arm("xgboost", 0.68, 0.50)))
  )
  summary <- atlas_sweep_summary(rows, baseline = "maxnet")
  all_xgb <- summary[summary$band == "all" & summary$arm == "xgboost", ]
  expect_equal(all_xgb$delta_auc, 0.02)
  expect_equal(all_xgb$delta_boyce, 0.1)
  expect_equal(summary$delta_auc[summary$band == "all" & summary$arm == "maxnet"], 0)
})

test_that("the maxnet arm scores exactly as production's cross-validation does", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("xgboost")
  world <- synthetic_landscape()
  row <- atlas_benchmark_taxon(
    "Eastern fungus", fingerprint = "f00dfeed", points = world$points,
    stack = world$stack, n_background = 500, buffer_km = 300, min_presences = 20
  )
  expect_equal(row$status, "scored")
  expect_equal(vapply(row$arms, function(a) a$arm, character(1)), ATLAS_BENCHMARK_ARMS)

  # The same folds and table production would use, scored the usual way.
  training <- atlas_build_training(
    "Eastern fungus", n_background = 500, buffer_km = 300, write = FALSE,
    quiet = TRUE, points = world$points, stack = world$stack, fingerprint = "f00dfeed"
  )
  folds <- atlas_spatial_folds(training$x, training$y, seed = attr(training, "seed"))
  keep <- atlas_choose_predictors(training)
  expected <- atlas_cross_validate(training[, c("presence", "cell", "x", "y", keep)], folds)
  expect_equal(row$arms[[1]]$auc, round(mean(expected$auc, na.rm = TRUE), 4))

  xgb <- row$arms[[2]]
  expect_gt(xgb$auc, 0.6)
  expect_equal(xgb$folds_scored, row$arms[[1]]$folds_scored)
})

test_that("a benchmark writes its results and never touches the fitted models", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("xgboost")
  with_data_dir({
    world <- synthetic_landscape()
    occurrences <- data.frame(
      id = as.character(seq_len(nrow(world$points))),
      scientific_name = world$points$scientific_name,
      latitude = "45", longitude = "-100", observed_on = "2025-01-01",
      stringsAsFactors = FALSE
    )
    result <- atlas_model_benchmark(
      occurrences = occurrences, points = world$points, stack = world$stack,
      taxa = "Eastern fungus", min_presences = 20, arms = c("maxnet", "xgboost"),
      n_background = 500, buffer_km = 300, quiet = TRUE
    )
    expect_true(file.exists(result$path))
    expect_match(result$path, "benchmarks/draft/models-")
    expect_false(dir.exists(atlas_path("models")))
    saved <- jsonlite::fromJSON(result$path, simplifyVector = FALSE)
    expect_equal(saved$baseline, "maxnet")
    expect_equal(length(saved$taxa), 1L)
  })
})
