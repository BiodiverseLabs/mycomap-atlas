# The block-size check: does cross-validation test at the distances a map
# predicts at?

test_that("nearest distances match a brute-force search, in km", {
  set.seed(5)
  qx <- stats::runif(1200, 0, 1e6); qy <- stats::runif(1200, 0, 1e6)
  tx <- stats::runif(300, 0, 1e6); ty <- stats::runif(300, 0, 1e6)
  expected <- vapply(seq_along(qx), function(i) min(sqrt((tx - qx[i])^2 + (ty - qy[i])^2)),
                     numeric(1)) / 1000
  # A chunk smaller than the query set exercises the joins between chunks.
  expect_equal(atlas_nearest_km(qx, qy, tx, ty, chunk = 100L), expected)
  expect_equal(atlas_nearest_km(0, 0, 3000, 4000), 5)
  expect_equal(atlas_nearest_km(numeric(), numeric(), tx, ty), numeric())
})

test_that("a held-out site is measured only to sites in the other folds", {
  training <- data.frame(presence = c(1L, 0L, 1L, 0L), x = c(0, 1000, 10000, 11000),
                         y = 0, cell = 1:4)
  # The near neighbour of each site sits in its own fold, so it must not count.
  folds <- c(1L, 1L, 2L, 2L)
  d <- atlas_cv_distances(training, folds)
  expect_equal(sort(d), c(9, 9, 10, 10))
  found <- atlas_cv_distances(training, folds, which = training$presence == 1L,
                              to_detections = TRUE)
  expect_equal(found, c(10, 10))
})

test_that("the Wasserstein distance is the mean gap between quantiles", {
  a <- seq(0, 100, length.out = 501)
  expect_equal(atlas_wasserstein(a, a), 0)
  expect_equal(atlas_wasserstein(a, a + 30), 30)
  expect_equal(atlas_wasserstein(a, a + 30), atlas_wasserstein(a + 30, a))
  # Distributions that cross: as many quantiles above as below cancel in a
  # signed mean, but every gap counts.
  expect_equal(atlas_wasserstein(a, rep(50, 501)), 25, tolerance = 0.01)
  expect_true(is.na(atlas_wasserstein(numeric(), a)))
})

test_that("wider blocks test at greater distances", {
  set.seed(9)
  n <- 3000
  training <- data.frame(presence = rbinom(n, 1, 0.05), cell = seq_len(n),
                         x = stats::runif(n, 0, 2e6), y = stats::runif(n, 0, 2e6))
  medians <- vapply(c(50, 200, 500), function(size) {
    folds <- atlas_spatial_folds(training$x, training$y, k = 5, block_km = size, seed = 1,
                                 presence = training$presence)
    stats::median(atlas_cv_distances(training, folds))
  }, numeric(1))
  expect_true(all(diff(medians) > 0))
})

test_that("the check scores every size on a real-shaped taxon and writes its results", {
  skip_if_not_installed("terra")
  with_data_dir({
    world <- synthetic_landscape()
    occurrences <- data.frame(
      id = as.character(seq_len(nrow(world$points))),
      scientific_name = world$points$scientific_name,
      latitude = "45", longitude = "-100", observed_on = "2025-01-01",
      stringsAsFactors = FALSE
    )
    result <- atlas_block_study(
      occurrences = occurrences, points = world$points, stack = world$stack,
      sizes = c(50, 200), n_background = 500, buffer_km = 300, quiet = TRUE,
      taxa = "Eastern fungus"
    )
    expect_true(file.exists(result$path))
    expect_match(result$path, "block-studies")
    saved <- jsonlite::fromJSON(result$path, simplifyVector = FALSE)
    row <- saved$taxa[[1]]
    expect_equal(row$status, "scored")
    expect_equal(vapply(row$arms, function(a) a$block_km, numeric(1)), c(50, 200))
    for (arm in row$arms) {
      expect_true(is.finite(arm$w_all) && arm$w_all >= 0)
      expect_true(is.logical(arm$scorable))
    }
    expect_true(row$map_median_km >= 0)
    sizes <- unique(vapply(saved$summary, function(r) r$size_km, numeric(1)))
    expect_setequal(sizes, c(50, 200))
  })
})
