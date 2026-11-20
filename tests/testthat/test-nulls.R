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

# ---- production's null test (Steve, 2026-10-08) ---------------------------------

test_that("production tests every map against shifted nulls, up to 99, stopping after 5, and up to 499 near the line", {
  expect_equal(ATLAS_NULL_DESIGN, "shift")
  expect_equal(ATLAS_NULL_REPS, 99L)
  expect_equal(ATLAS_NULL_STOP_AFTER, 5L)
  expect_equal(ATLAS_NULL_EXTEND, list(from = 99L, to = 499L, stop_after = 25L, clear_pass = 1L, near_from = 50L))
  expect_equal(ATLAS_NULL_EXTEND$from, ATLAS_NULL_REPS)
  # Recorded in the design, so every model fitted under scattered nulls, or
  # without the near-line extension, is stale.
  expect_equal(atlas_design()$skill$design, "shift")
  expect_equal(atlas_design()$skill$stop_after, 5L)
  expect_equal(atlas_design()$skill$near_line, ATLAS_NULL_EXTEND)
})

test_that("a fitted map's null test is the shifted one, and its grade follows it", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    metrics <- atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                               fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                               buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 9L,
                               tune = FALSE, guilds = stats::setNames(character(), character()))$metrics
    expect_equal(metrics$null$design, "shift")
    expect_lte(metrics$null$reps, 9L)
    # Production asks for the near-line extension; a first stage of 9 is not
    # the 99 it was calibrated for, so it stands.
    expect_false(metrics$null$extended)
    expect_equal(metrics$null$first_reps, metrics$null$reps)
    expect_true(metrics$grade %in% c("strong", "weak", "failed"))
    expect_equal(metrics$grade, atlas_map_grade(metrics$skill, metrics$null, metrics$auc_mean,
                                                metrics$boyce))
  })
})

test_that("only a map that beat shifted nulls is strong; scattered nulls or held-out skill alone is weak", {
  shift <- list(design = "shift", observed_auc = 0.8, observed_boyce = 0.6)
  scatter <- list(observed_auc = 0.8, observed_boyce = 0.6)
  expect_equal(atlas_map_grade("passed", shift), "strong")
  # A fit from before the switch passed scattered nulls only.
  expect_equal(atlas_map_grade("passed", scatter), "weak")
  expect_equal(atlas_map_grade("passed", c(scatter, design = "scatter")), "weak")
  # Not passed, but better than chance on held-out ground.
  expect_equal(atlas_map_grade("failed", shift, auc = 0.66, boyce = 0.3), "weak")
  # No better than chance.
  expect_equal(atlas_map_grade("failed", shift, auc = 0.66, boyce = -0.1), "failed")
  expect_equal(atlas_map_grade("failed", shift, auc = 0.49, boyce = 0.3), "failed")
  expect_equal(atlas_map_grade("failed", shift), "weak")
  expect_equal(atlas_map_grade("failed", list(design = "shift", observed_auc = 0.5)), "failed")
  expect_equal(atlas_map_grade("untested"), "untested")
  expect_equal(atlas_map_grade(NULL), "untested")
  # A stored fit's grade is the one it recorded, else worked out.
  expect_equal(atlas_metrics_grade(list(skill = "passed", grade = "strong")), "strong")
  expect_equal(atlas_metrics_grade(list(skill = "passed", null = scatter)), "weak")
  expect_equal(atlas_metrics_grade(list(skill = "failed", auc_mean = 0.7, boyce = 0.2, null = shift)), "weak")
})

# The near-line extension (atlas_null_sequence), driven by a scripted run of
# null scores: draw i scores aucs[i] (NA: a null that could not be fitted).
# The map scores 0.8; a null at 0.9 does at least as well, one at 0.5 not.
scripted_nulls <- function(beats = integer(), fails = integer(), n = 1200L) {
  aucs <- rep(0.5, n)
  aucs[beats] <- 0.9
  aucs[fails] <- NA_real_
  calls <- 0L
  fetch <- function(take) {
    calls <<- calls + length(take)
    lapply(take, function(i) c(auc = aucs[[i]], boyce = 0.2))
  }
  fetch
}
run_nulls <- function(beats = integer(), fails = integer(), reps = 99L, batch = 10L,
                      extend = ATLAS_NULL_EXTEND) {
  atlas_null_sequence(0.8, scripted_nulls(beats, fails), reps = reps, stop_after = 5L,
                      batch = batch, extend = extend)
}

test_that("a near-line first stage is one that 2 to 4 of 99 nulls matched, or that stopped at its 50th null or later", {
  e <- ATLAS_NULL_EXTEND
  expect_false(atlas_null_near_line(99, 0, FALSE, e))
  expect_false(atlas_null_near_line(99, 1, FALSE, e))
  expect_true(atlas_null_near_line(99, 2, FALSE, e))
  expect_true(atlas_null_near_line(99, 4, FALSE, e))
  expect_false(atlas_null_near_line(49, 5, TRUE, e))
  expect_true(atlas_null_near_line(50, 5, TRUE, e))
  expect_true(atlas_null_near_line(99, 5, TRUE, e))
})

test_that("a clear first stage stands: one null in 99 as good passes, a fifth before the 50th fails", {
  passed <- run_nulls(beats = 10)
  expect_false(passed$extended)
  expect_equal(length(passed$aucs), 99)
  expect_equal(passed$p, 2 / 100)
  failed <- run_nulls(beats = c(10, 20, 30, 40, 49))
  expect_false(failed$extended)
  expect_true(failed$stopped)
  expect_equal(length(failed$aucs), 49)
  expect_equal(failed$p, 5 / 49)
})

test_that("near the line the test goes on to 499 nulls, and can pass a map its first 99 failed", {
  run <- run_nulls(beats = c(10, 20, 30, 40, 50))
  expect_true(run$extended)
  expect_equal(run$first$reps, 50)
  expect_equal(run$first$p, 5 / 50)
  expect_false(run$stopped)
  expect_equal(length(run$aucs), 499)
  expect_equal(run$above, 5L)
  expect_equal(run$p, 6 / 500)
  expect_lte(run$p, ATLAS_SKILL_ALPHA)
})

test_that("near the line the test can fail a map its first 99 passed, stopping at the 25th null as good", {
  run <- run_nulls(beats = c(10, 20, 30, 100:121))
  expect_equal(run$first$p, 4 / 100)
  expect_lte(run$first$p, ATLAS_SKILL_ALPHA)
  expect_true(run$extended)
  expect_true(run$stopped)
  expect_equal(run$above, 25L)
  expect_equal(length(run$aucs), 121)
  expect_equal(run$p, 25 / 121)
  expect_gt(run$p, ATLAS_SKILL_ALPHA)
})

test_that("at 499 nulls, 24 as good is p = 0.05 and passes, and a 25th stops the test and fails it", {
  at_line <- run_nulls(beats = c(10, 20, 30, 100:120))
  expect_equal(at_line$above, 24L)
  expect_false(at_line$stopped)
  expect_equal(at_line$p, 25 / 500)
  expect_lte(at_line$p, ATLAS_SKILL_ALPHA)
  over <- run_nulls(beats = c(10, 20, 30, 100:120, 499))
  expect_true(over$stopped)
  expect_equal(over$p, 25 / 499)
  expect_gt(over$p, ATLAS_SKILL_ALPHA)
})

test_that("nulls that cannot be fitted are replaced in both stages, and the batch size changes nothing", {
  beats <- c(10, 20, 30, 40, 150, 300)
  fails <- c(5, 60, 61, 200, 450)
  runs <- lapply(c(1L, 7L, 10L, 33L), function(b) run_nulls(beats, fails, batch = b))
  for (run in runs[-1]) {
    expect_identical(run[c("aucs", "above", "stopped", "p", "extended", "first")],
                     runs[[1]][c("aucs", "above", "stopped", "p", "extended", "first")])
  }
  run <- runs[[1]]
  expect_true(run$extended)
  expect_equal(length(run$aucs), 499)
  expect_equal(run$drawn, 499 + length(fails))
  expect_equal(run$p, 7 / 500)
  # Never more than twice as many draws as nulls wanted.
  hopeless <- run_nulls(beats = c(10, 20, 30), fails = 100:1200)
  expect_true(hopeless$extended)
  expect_equal(hopeless$drawn, 2 * 499)
  expect_equal(length(hopeless$aucs), 99)
})

test_that("the extension is for a first stage of 99, and without it the test is the one the studies ran", {
  short <- run_nulls(beats = c(3, 9), reps = 19L)
  expect_false(short$extended)
  expect_equal(length(short$aucs), 19)
  plain <- run_nulls(beats = c(10, 20, 30), extend = NULL)
  expect_false(plain$extended)
  expect_equal(length(plain$aucs), 99)
  expect_equal(plain$p, 4 / 100)
  # The study path (no extend) returns exactly the fields it always did.
  skip_if_not_installed("maxnet")
  world <- null_world("habitat")
  folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1,
                               presence = world$presence)
  study <- atlas_null_test_sequential(world, folds, atlas_algorithm("maxnet"), reps = 19, seed = 3,
                                      design = "shift", stop_after = 5L)
  expect_null(study$extended)
  expect_null(study$first_reps)
  extended <- atlas_null_test_sequential(world, folds, atlas_algorithm("maxnet"), reps = 19, seed = 3,
                                         design = "shift", stop_after = 5L, extend = ATLAS_NULL_EXTEND)
  expect_false(extended$extended)
  expect_identical(extended[names(study)], study)
})

# Pooled fold splits (atlas_null_fold_splits): the map and every null are
# scored on several splits and compared by the mean.
test_that("the pooled test's first split is the map's own, the others are dealt afresh, and the random stream is left as it was", {
  world <- null_world("habitat")
  own <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1, presence = world$presence)
  set.seed(42)
  before <- .Random.seed
  splits <- atlas_null_fold_splits(world$x, world$y, own, k = 5, block_km = 200, seed = 1,
                                   presence = world$presence, splits = 5L)
  expect_identical(.Random.seed, before)
  expect_length(splits, 5)
  expect_identical(splits[[1]], own)
  for (i in 2:5) {
    expect_false(identical(splits[[i]], own))
    expect_setequal(unique(splits[[i]]), 1:5)
    expect_identical(splits[[i]], atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1 + 100 * (i - 1),
                                                      presence = world$presence))
  }
  expect_identical(atlas_null_fold_splits(world$x, world$y, own, 5, 200, 1, world$presence, splits = 1L), list(own))
})

test_that("pooled over splits, the map and its nulls are compared by their mean over the splits; one split is the single-split test", {
  skip_if_not_installed("maxnet")
  world <- null_world("habitat")
  own <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1, presence = world$presence)
  splits <- atlas_null_fold_splits(world$x, world$y, own, k = 5, block_km = 200, seed = 1,
                                   presence = world$presence, splits = 3L)
  algo <- atlas_algorithm("maxnet")
  test <- function(folds) atlas_null_test_sequential(world, folds, algo, reps = 7, seed = 3,
                                                     design = "shift", stop_after = 100L)
  single <- test(own)
  expect_identical(test(list(own)), single)
  each <- lapply(splits, test)
  pooled <- test(splits)
  expect_equal(pooled$splits, 3L)
  expect_equal(pooled$first_split_auc, single$observed_auc)
  # Every null is scored on every split, so the nulls' mean is the mean of
  # each split's nulls' mean (rounding aside).
  expect_equal(pooled$auc_mean, mean(vapply(each, function(x) x$auc_mean, numeric(1))), tolerance = 2e-3)
  expect_equal(pooled$observed_auc, mean(vapply(each, function(x) x$observed_auc, numeric(1))), tolerance = 2e-3)
  expect_equal(pooled$reps, 7L)
  expect_null(single$splits)
})

test_that("production pools its null test over 5 splits, records it in the settings, and leaves the map's own scores alone", {
  expect_equal(ATLAS_NULL_SPLITS, 5L)
  expect_equal(atlas_fit_settings()$null_splits, 5)
  expect_false(identical(atlas_settings_key(atlas_fit_settings()), atlas_settings_key(atlas_fit_settings(null_splits = 1L))))
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    fit <- function(splits) atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                                            fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                                            buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 5L,
                                            tune = FALSE, guilds = stats::setNames(character(), character()),
                                            null_splits = splits)$metrics
    one <- fit(1L)
    five <- fit(5L)
    expect_equal(five$null$splits, 5L)
    expect_null(one$null$splits)
    expect_equal(five$settings$null_splits, 5)
    expect_equal(five$null$first_split_auc, one$null$observed_auc)
    for (field in c("auc_mean", "boyce", "boyce_mean", "folds", "block_km")) {
      expect_identical(five[[field]], one[[field]], info = field)
    }
  })
})
