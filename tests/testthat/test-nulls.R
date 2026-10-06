# Null models that keep clustering, the sequential test, and q-values.

# 2,000 survey sites on a 1,000 km square whose two predictors change
# smoothly with place, as climate does. kind "cluster": the taxon is 40
# sites within 150 km of one spot, whatever the environment there. kind
# "habitat": the taxon follows v1 across the whole square.
null_world <- function(kind = "cluster", seed = 21, n = 2000) {
  set.seed(seed)
  x <- stats::runif(n, 0, 1e6)
  y <- stats::runif(n, 0, 1e6)
  table <- data.frame(
    presence = 0L, cell = seq_len(n), x = x, y = y,
    v1 = x / 1e5 + stats::rnorm(n, 0, 0.3), v2 = y / 1e5 + stats::rnorm(n, 0, 0.3),
    effort = log(pmax(1, stats::rpois(n, 3)))
  )
  if (identical(kind, "cluster")) {
    d <- sqrt((x - 6.5e5)^2 + (y - 3.5e5)^2)
    table$presence[order(d)[1:40]] <- 1L
  } else {
    table$presence[sample.int(n, 60, prob = exp(-(table$v1 - 3)^2))] <- 1L
  }
  table
}

nearest_neighbour_km <- function(x, y) {
  vapply(seq_along(x), function(i) min(sqrt((x[-i] - x[i])^2 + (y[-i] - y[i])^2)), numeric(1)) / 1000
}

test_that("a moved point snaps to the nearest free site, never two to one", {
  set.seed(1)
  sx <- c(0, 10e3, 20e3, 500e3)
  sy <- c(0, 0, 0, 0)
  chosen <- atlas_snap_to_sites(c(1e3, 2e3, 19e3), c(0, 0, 0), sx, sy, snap_km = 25)
  expect_equal(sort(chosen), c(1L, 2L, 3L))
  expect_equal(anyDuplicated(chosen), 0L)
  # Two of three points far from any free site: more than a fifth, so rejected.
  expect_null(atlas_snap_to_sites(c(0, 250e3, 260e3), c(0, 0, 0), sx, sy, snap_km = 25))
  # More points than sites can never be placed.
  expect_null(atlas_snap_to_sites(rep(0, 5), rep(0, 5), sx, sy))
})

test_that("a shifted null keeps the clustering that a scattered null loses", {
  world <- null_world("cluster")
  found <- world$presence == 1L
  real <- stats::median(nearest_neighbour_km(world$x[found], world$y[found]))
  shifted <- vapply(1:5, function(s) {
    null <- atlas_null_shift(world, seed = s)
    expect_false(attr(null, "best_effort"))
    expect_equal(sum(null), sum(found))
    stats::median(nearest_neighbour_km(world$x[null == 1L], world$y[null == 1L]))
  }, numeric(1))
  scattered <- vapply(1:5, function(s) {
    null <- atlas_null_presence(world, sum(found), seed = s)
    stats::median(nearest_neighbour_km(world$x[null == 1L], world$y[null == 1L]))
  }, numeric(1))
  expect_lt(abs(mean(shifted) - real), 0.5 * real)
  expect_gt(mean(scattered), 3 * real)
})

test_that("a shift null that cannot be placed cleanly takes its best try, keeps its clustering, and says so", {
  world <- null_world("cluster")
  found <- world$presence == 1L
  real <- stats::median(nearest_neighbour_km(world$x[found], world$y[found]))
  # Snap distance too small for any moved point to land near a site.
  null <- atlas_null_shift(world, seed = 1, tries = 3, snap_km = 0.001)
  expect_true(attr(null, "best_effort"))
  expect_equal(sum(null), sum(found))
  expect_gt(attr(null, "far_share"), 0.2)
  # Still a cluster, not a scatter.
  placed <- null == 1L
  expect_lt(stats::median(nearest_neighbour_km(world$x[placed], world$y[placed])), 2 * real)
  # The same seed gives the same null.
  expect_identical(as.integer(null), as.integer(atlas_null_shift(world, seed = 1, tries = 3, snap_km = 0.001)))
})

test_that("an unknown null design is refused", {
  expect_error(atlas_null_design("sideways"), "unknown null design")
  expect_equal(atlas_null_design(NULL), "scatter")
})

test_that("drawn in full, the sequential test gives production's p", {
  skip_if_not_installed("maxnet")
  world <- null_world("habitat")
  folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1,
                               presence = world$presence)
  algo <- atlas_algorithm("maxnet")
  production <- atlas_null_test(world, folds, algo, reps = 19, seed = 3)
  sequential <- atlas_null_test_sequential(world, folds, algo, reps = 19, seed = 3,
                                           stop_after = 20L)
  expect_equal(sequential$auc_p, production$auc_p)
  expect_equal(sequential$auc_mean, production$auc_mean)
  expect_false(sequential$stopped_early)
})

test_that("stopping early gives the same verdict as drawing all 99, and the batch size changes nothing", {
  skip_if_not_installed("maxnet")
  world <- null_world("cluster")
  folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1,
                               presence = world$presence)
  algo <- atlas_algorithm("maxnet")
  early <- atlas_null_test_sequential(world, folds, algo, reps = 99, seed = 3,
                                      design = "shift", stop_after = 5L)
  expect_true(early$stopped_early)
  expect_lt(early$reps, 99)
  expect_equal(early$auc_p, round(5 / early$reps, 4))
  small_batches <- atlas_null_test_sequential(world, folds, algo, reps = 99, seed = 3,
                                              design = "shift", stop_after = 5L, batch = 3L)
  expect_equal(small_batches$auc_p, early$auc_p)
  full <- atlas_null_test_sequential(world, folds, algo, reps = 99, seed = 3,
                                     design = "shift", stop_after = 100L)
  expect_equal(full$auc_p <= 0.05, early$auc_p <= 0.05)
})

test_that("a cluster that knows nothing passes scattered nulls but not shifted ones", {
  skip_if_not_installed("maxnet")
  world <- null_world("cluster")
  folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1,
                               presence = world$presence)
  algo <- atlas_algorithm("maxnet")
  scattered <- atlas_null_test_sequential(world, folds, algo, reps = 19, seed = 3,
                                          design = "scatter", stop_after = 20L)
  shifted <- atlas_null_test_sequential(world, folds, algo, reps = 19, seed = 3,
                                        design = "shift", stop_after = 20L)
  expect_lte(scattered$auc_p, 0.05)
  expect_gt(shifted$auc_p, 0.05)
})

test_that("q-values are Benjamini-Hochberg's, and a missing p is not counted as a test", {
  p <- c(0.01, 0.04, NA, 0.03, 0.5)
  q <- atlas_null_qvalues(p)
  expect_true(is.na(q[[3]]))
  expect_equal(q[-3], stats::p.adjust(p[-3], method = "BH"))
  expect_true(all(q[-3] >= p[-3]))
})
