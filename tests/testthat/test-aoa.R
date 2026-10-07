# Area of applicability: where a map has data behind it.

# Sites that cover v1 and v2 only between -1 and 1, dealt into five folds.
aoa_sites <- function(n = 800, seed = 2) {
  set.seed(seed)
  data.frame(presence = stats::rbinom(n, 1, 0.1), cell = seq_len(n),
             x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
             v1 = stats::runif(n, -1, 1), v2 = stats::runif(n, -1, 1),
             effort = 0)
}

test_that("nearest distances in predictor space match a brute-force search", {
  set.seed(3)
  q <- matrix(stats::rnorm(300 * 4), ncol = 4)
  r <- matrix(stats::rnorm(120 * 4), ncol = 4)
  expected <- apply(q, 1, function(row) min(sqrt(colSums((t(r) - row)^2))))
  expect_equal(atlas_nearest_rows(q, r, chunk = 37L), expected, tolerance = 1e-8)
  expect_equal(atlas_nearest_rows(q[0, , drop = FALSE], r), numeric())
})

test_that("weights come from held-out importance, never below zero, and are equal when none was measured", {
  falls <- matrix(c(0.04, 0.02, -0.01, -0.03, 0.01, 0.01), nrow = 3, byrow = TRUE,
                  dimnames = list(c("predictor\rv1", "predictor\rv2", "layer\rclimate"), NULL))
  w <- atlas_aoa_weights(falls, c("v1", "v2", "v3"))
  expect_equal(unname(w[c("v1", "v2", "v3")]), c(0.03, 0, 0))
  expect_equal(attr(w, "source"), "importance")
  none <- atlas_aoa_weights(NULL, c("v1", "v2"))
  expect_equal(as.numeric(none), c(1, 1))
  expect_equal(attr(none, "source"), "equal")
})

test_that("a place unlike every training site is outside the area of applicability", {
  sites <- aoa_sites()
  folds <- atlas_spatial_folds(sites$x, sites$y, k = 5, block_km = 200, seed = 1)
  # Unequal weights, so a site and a place are only comparable if both are
  # weighted the same way.
  aoa <- atlas_aoa_train(sites, c("v1", "v2"), c(v1 = 2, v2 = 0.5), folds)
  places <- data.frame(v1 = c(0, 0.9, 4, 0), v2 = c(0, -0.9, 0, -20))
  index <- atlas_aoa_index(aoa, places)
  expect_true(all(index[1:2] <= aoa$threshold))
  expect_true(all(index[3:4] > aoa$threshold))
  expect_gt(index[[4]], index[[3]])
  # A training site itself is at no distance at all.
  expect_equal(atlas_aoa_index(aoa, sites[1, ]), 0)
})

test_that("a predictor the model never used does not count against a place", {
  sites <- aoa_sites()
  folds <- atlas_spatial_folds(sites$x, sites$y, k = 5, block_km = 200, seed = 1)
  aoa <- atlas_aoa_train(sites, c("v1", "v2"), c(v1 = 1, v2 = 0), folds)
  expect_equal(aoa$predictors, "v1")
  index <- atlas_aoa_index(aoa, data.frame(v1 = c(0.5, 0.5), v2 = c(0, 50)))
  expect_equal(index[[1]], index[[2]])
  expect_true(index[[2]] <= aoa$threshold)
})

test_that("a heavier predictor counts for more", {
  sites <- aoa_sites()
  folds <- atlas_spatial_folds(sites$x, sites$y, k = 5, block_km = 200, seed = 1)
  light <- atlas_aoa_train(sites, c("v1", "v2"), c(v1 = 1, v2 = 0.1), folds)
  heavy <- atlas_aoa_train(sites, c("v1", "v2"), c(v1 = 1, v2 = 10), folds)
  place <- data.frame(v1 = 0, v2 = 3)
  # The index is relative to the training sites' own spread, so compare how
  # far past each model's threshold the place falls.
  expect_gt(atlas_aoa_index(heavy, place) / heavy$threshold,
            atlas_aoa_index(light, place) / light$threshold)
})

test_that("the threshold is set from held-out folds, not from each site against itself", {
  sites <- aoa_sites()
  folds <- atlas_spatial_folds(sites$x, sites$y, k = 5, block_km = 200, seed = 1)
  aoa <- atlas_aoa_train(sites, c("v1", "v2"), c(v1 = 1, v2 = 1), folds)
  expect_gt(aoa$threshold, 0)
  expect_gt(aoa$training_index[[1]], 0)
})

test_that("a fitted map carries its dissimilarity layer and says how much of it is applicable", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    fit <- atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                           fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                           buffer_km = 300, quiet = TRUE, nulls = 0, tune = FALSE,
                           block_km = 200)
    applicability <- fit$metrics$applicability
    # The synthetic records carry no dates, so the model says nothing about years.
    expect_null(fit$metrics$record_years)
    expect_true(is.finite(applicability$threshold) && applicability$threshold > 0)
    expect_true(applicability$inside_share > 0 && applicability$inside_share <= 1)
    expect_equal(fit$metrics$dissimilarity, "eastern-fungus.di.tif")
    path <- atlas_model_path("Eastern fungus", "draft", ".di.tif")
    expect_true(file.exists(path))
    layer <- terra::rast(path)
    expect_true(terra::compareGeom(layer, terra::rast(atlas_model_path("Eastern fungus", "draft")),
                                   stopOnError = FALSE))
    # Removing the map removes its dissimilarity layer with it.
    atlas_remove_map("Eastern fungus", "draft")
    expect_false(file.exists(path))
  })
})

test_that("a change to how applicability is judged makes every stored model stale", {
  settings <- atlas_fit_settings(layers = "synthetic")
  before <- atlas_settings_key(settings)
  local_mocked_bindings(atlas_design = function() {
    design <- list(unit = "survey sites, detection/non-detection")
    design$applicability <- list(method = "something else")
    design
  })
  expect_false(identical(atlas_settings_key(atlas_fit_settings(layers = "synthetic")), before))
})

test_that("a fitted model says what years its records were collected over", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    points <- world$points
    points$year <- ifelse(points$scientific_name == "Eastern fungus", 1990L + seq_len(nrow(points)) %% 30L, 2000L)
    fit <- atlas_fit_taxon("Eastern fungus", points = points, stack = world$stack,
                           fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                           buffer_km = 300, quiet = TRUE, nulls = 0, tune = FALSE,
                           block_km = 200, predict = FALSE, write = FALSE)
    years <- fit$metrics$record_years
    own <- points$year[points$scientific_name == "Eastern fungus"]
    expect_equal(years$records, length(own))
    expect_equal(c(years$first, years$last), range(own))
    expect_equal(years$before_climate_period, round(mean(own < 1991L), 3))
  })
})
