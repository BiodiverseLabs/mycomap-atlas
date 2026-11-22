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

test_that("production tests every map against shifted nulls, up to 99, stopping after 5, and up to 199 near the line", {
  expect_equal(ATLAS_NULL_DESIGN, "shift")
  expect_equal(ATLAS_NULL_REPS, 99L)
  expect_equal(ATLAS_NULL_STOP_AFTER, 5L)
  expect_equal(ATLAS_NULL_EXTEND, list(from = 99L, to = 199L, stop_after = 10L, clear_pass = 1L, near_from = 50L))
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
    # It asks for the stricter test too, which a taxon this small is not given.
    expect_false(metrics$null$large)
    expect_equal(metrics$null$alpha, ATLAS_SKILL_ALPHA)
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

test_that("near the line the test goes on to 199 nulls, and can pass a map its first 99 failed", {
  run <- run_nulls(beats = c(10, 20, 30, 40, 50))
  expect_true(run$extended)
  expect_equal(run$first$reps, 50)
  expect_equal(run$first$p, 5 / 50)
  expect_false(run$stopped)
  expect_equal(length(run$aucs), 199)
  expect_equal(run$above, 5L)
  expect_equal(run$p, 6 / 200)
  expect_lte(run$p, ATLAS_SKILL_ALPHA)
})

test_that("near the line the test can fail a map its first 99 passed, stopping at the 10th null as good", {
  run <- run_nulls(beats = c(10, 20, 30, 100:106))
  expect_equal(run$first$p, 4 / 100)
  expect_lte(run$first$p, ATLAS_SKILL_ALPHA)
  expect_true(run$extended)
  expect_true(run$stopped)
  expect_equal(run$above, 10L)
  expect_equal(length(run$aucs), 106)
  expect_equal(run$p, 10 / 106)
  expect_gt(run$p, ATLAS_SKILL_ALPHA)
})

test_that("at 199 nulls, 9 as good is p = 0.05 and passes, and a 10th stops the test and fails it", {
  at_line <- run_nulls(beats = c(10, 20, 30, 100:105))
  expect_equal(at_line$above, 9L)
  expect_false(at_line$stopped)
  expect_equal(at_line$p, 10 / 200)
  expect_lte(at_line$p, ATLAS_SKILL_ALPHA)
  over <- run_nulls(beats = c(10, 20, 30, 100:105, 199))
  expect_true(over$stopped)
  expect_equal(over$p, 10 / 199)
  expect_gt(over$p, ATLAS_SKILL_ALPHA)
})

test_that("nulls that cannot be fitted are replaced in both stages, and the batch size changes nothing", {
  beats <- c(10, 20, 30, 40, 150)
  fails <- c(5, 60, 61, 120, 180)
  runs <- lapply(c(1L, 7L, 10L, 33L), function(b) run_nulls(beats, fails, batch = b))
  for (run in runs[-1]) {
    expect_identical(run[c("aucs", "above", "stopped", "p", "extended", "first")],
                     runs[[1]][c("aucs", "above", "stopped", "p", "extended", "first")])
  }
  run <- runs[[1]]
  expect_true(run$extended)
  expect_equal(length(run$aucs), 199)
  expect_equal(run$drawn, 199 + length(fails))
  expect_equal(run$p, 6 / 200)
  # Never more than twice as many draws as nulls wanted.
  hopeless <- run_nulls(beats = c(10, 20, 30), fails = 100:1200)
  expect_true(hopeless$extended)
  expect_equal(hopeless$drawn, 2 * 199)
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

# A taxon with many sites (ATLAS_NULL_LARGE, atlas_null_plan): 199 nulls,
# no clear pass on the first 99, stopping after 3, passing at p <= 0.015.
large_nulls <- function(beats = integer(), fails = integer(), batch = 10L) {
  plan <- atlas_null_plan(250L, ATLAS_NULL_REPS, ATLAS_NULL_STOP_AFTER, ATLAS_NULL_EXTEND, ATLAS_NULL_LARGE)
  run <- atlas_null_sequence(0.8, scripted_nulls(beats, fails), reps = plan$reps, stop_after = plan$stop_after,
                             batch = batch, extend = plan$extend)
  run$verdict <- atlas_skill(list(reps = length(run$aucs), auc_p = round(run$p, 4), alpha = plan$alpha), 0.3)
  run
}

test_that("from 200 sites production tests a map against 199 nulls, stopping after 3, and passes it at p <= 0.015", {
  expect_equal(ATLAS_NULL_LARGE, list(sites = 200L, reps = 199L, stop_after = 3L, alpha = 0.015))
  # Recorded in the design, so every model fitted before it is stale.
  expect_equal(atlas_design()$skill$large, ATLAS_NULL_LARGE)
  # At most 2 of 199 as good passes, and a test that stops fails, wherever it stops.
  expect_lte((1 + 2) / 200, ATLAS_NULL_LARGE$alpha)
  expect_gt(round(ATLAS_NULL_LARGE$stop_after / ATLAS_NULL_LARGE$reps, 4), ATLAS_NULL_LARGE$alpha)
})

test_that("a taxon of 200 sites or more gets the stricter test, one of 199 the near-line extension", {
  below <- atlas_null_plan(199L, 99L, 5L, ATLAS_NULL_EXTEND, ATLAS_NULL_LARGE)
  expect_equal(below, list(reps = 99L, stop_after = 5L, extend = ATLAS_NULL_EXTEND, large = FALSE,
                           alpha = ATLAS_SKILL_ALPHA))
  at <- atlas_null_plan(200L, 99L, 5L, ATLAS_NULL_EXTEND, ATLAS_NULL_LARGE)
  expect_equal(at, list(reps = 199L, stop_after = 3L, extend = NULL, large = TRUE, alpha = 0.015))
  expect_true(atlas_null_plan(344L, 99L, 5L, ATLAS_NULL_EXTEND, ATLAS_NULL_LARGE)$large)
  # Only production's test: a first stage of 99 with the extension, as it
  # was calibrated. The studies' tests, and a short test, are as asked.
  expect_false(atlas_null_plan(300L, 99L, 5L, NULL, ATLAS_NULL_LARGE)$large)
  expect_false(atlas_null_plan(300L, 19L, 5L, ATLAS_NULL_EXTEND, ATLAS_NULL_LARGE)$large)
  expect_equal(atlas_null_plan(300L, 19L, 5L, ATLAS_NULL_EXTEND, ATLAS_NULL_LARGE)$reps, 19L)
  expect_false(atlas_null_plan(300L, 99L, 5L, ATLAS_NULL_EXTEND, NULL)$large)
})

test_that("for a taxon with many sites, 2 of 199 nulls as good passes and a third fails, even on the last null", {
  two <- large_nulls(beats = c(40, 150))
  expect_false(two$stopped)
  expect_false(two$extended)
  expect_equal(length(two$aucs), 199)
  expect_equal(two$p, 3 / 200)
  expect_equal(two$verdict, "passed")
  last <- large_nulls(beats = c(40, 150, 199))
  expect_true(last$stopped)
  expect_equal(length(last$aucs), 199)
  expect_equal(last$p, 3 / 199)
  expect_equal(last$verdict, "failed")
  # Below 200 sites, 3 as good of 199 would pass.
  expect_lte((1 + 3) / 200, ATLAS_SKILL_ALPHA)
  early <- large_nulls(beats = c(5, 10, 15))
  expect_true(early$stopped)
  expect_equal(length(early$aucs), 15)
  expect_equal(early$verdict, "failed")
})

test_that("for a taxon with many sites, a clear first 99 does not stand: the test goes on to 199", {
  # One of the first 99 as good is a clear pass below 200 sites.
  clear <- run_nulls(beats = c(10, 150, 160))
  expect_false(clear$extended)
  expect_equal(length(clear$aucs), 99)
  expect_lte(clear$p, ATLAS_SKILL_ALPHA)
  run <- large_nulls(beats = c(10, 150, 160))
  expect_equal(length(run$aucs), 160)
  expect_true(run$stopped)
  expect_equal(run$verdict, "failed")
  none <- large_nulls()
  expect_equal(length(none$aucs), 199)
  expect_equal(none$p, 1 / 200)
  expect_equal(none$verdict, "passed")
})

test_that("for a taxon with many sites, failed nulls are replaced and the batch size changes nothing", {
  runs <- lapply(c(1L, 7L, 10L, 33L), function(b) large_nulls(beats = c(30, 170), fails = c(5, 60, 120), batch = b))
  for (run in runs[-1]) {
    expect_identical(run[c("aucs", "above", "stopped", "p", "verdict")],
                     runs[[1]][c("aucs", "above", "stopped", "p", "verdict")])
  }
  expect_equal(runs[[1]]$drawn, 199 + 3)
  expect_equal(runs[[1]]$verdict, "passed")
  # Too few nulls scored to reach 199: 2 as good is then not enough.
  short <- large_nulls(beats = c(30, 100), fails = 150:1200)
  expect_equal(short$drawn, 2 * 199)
  expect_equal(length(short$aucs), 149)
  expect_equal(short$p, 3 / 150)
  expect_equal(short$verdict, "failed")
})

test_that("a map is passed at the level its null test was run at, else at 0.05", {
  null <- list(reps = 199L, auc_p = 0.02)
  expect_equal(atlas_skill(null, 0.3), "passed")
  expect_equal(atlas_skill(c(null, list(alpha = 0.015)), 0.3), "failed")
  expect_equal(atlas_skill(list(reps = 199L, auc_p = 0.015, alpha = 0.015), 0.3), "passed")
  expect_equal(atlas_skill(list(reps = 199L, auc_p = 0.015, alpha = 0.015), -0.1), "failed")
  expect_equal(atlas_skill(c(null, list(alpha = 0.015)), 0.3, alpha = 0.05), "passed")
  expect_equal(atlas_skill(list(reps = 0L), 0.3), "untested")
})

test_that("the null test runs the stricter test from its sites, says so, and scores the same nulls as asked for directly", {
  skip_if_not_installed("maxnet")
  world <- null_world("habitat")
  n <- sum(world$presence == 1L)
  folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1, presence = world$presence)
  algo <- atlas_algorithm("maxnet")
  # Production's rule, scaled down so a test is quick: from n sites, 19
  # nulls stopping after 3, in place of a first stage of 9 with its extension.
  extend <- utils::modifyList(ATLAS_NULL_EXTEND, list(from = 9L, to = 15L))
  large <- list(sites = n, reps = 19L, stop_after = 3L, alpha = 0.015)
  got <- atlas_null_test_sequential(world, folds, algo, reps = 9L, seed = 3, design = "shift",
                                    stop_after = 5L, extend = extend, large = large)
  expect_true(got$large)
  expect_equal(got$alpha, 0.015)
  expect_false(got$extended)
  direct <- atlas_null_test_sequential(world, folds, algo, reps = 19L, seed = 3, design = "shift",
                                       stop_after = 3L)
  expect_identical(got[names(direct)], direct)
  # One site short of the rule, the test is the one asked for.
  short <- atlas_null_test_sequential(world, folds, algo, reps = 9L, seed = 3, design = "shift",
                                      stop_after = 5L, extend = extend,
                                      large = utils::modifyList(large, list(sites = n + 1L)))
  expect_false(short$large)
  expect_equal(short$alpha, ATLAS_SKILL_ALPHA)
  asked <- atlas_null_test_sequential(world, folds, algo, reps = 9L, seed = 3, design = "shift",
                                      stop_after = 5L, extend = extend)
  expect_null(asked$large)
  expect_identical(short[names(asked)], asked)
})

test_that("a map with many sites that knows nothing stops at its third null as good, not its fifth", {
  skip_if_not_installed("maxnet")
  # Sites drawn at random: the map knows nothing, and about half its nulls
  # do as well.
  world <- null_world("habitat")
  world$presence[] <- 0L
  set.seed(5)
  world$presence[sample.int(nrow(world), 60)] <- 1L
  n <- sum(world$presence == 1L)
  folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1, presence = world$presence)
  algo <- atlas_algorithm("maxnet")
  extend <- utils::modifyList(ATLAS_NULL_EXTEND, list(from = 9L, to = 15L))
  large <- list(sites = n, reps = 39L, stop_after = 3L, alpha = 0.015)
  got <- atlas_null_test_sequential(world, folds, algo, reps = 9L, seed = 3, design = "shift",
                                    stop_after = 5L, extend = extend, large = large)
  expect_true(got$large)
  expect_true(got$stopped_early)
  expect_equal(got$auc_p, round(3 / got$reps, 4))
  expect_equal(atlas_skill(got, 0.3), "failed")
  five <- atlas_null_test_sequential(world, folds, algo, reps = 39L, seed = 3, design = "shift", stop_after = 5L)
  expect_true(five$stopped_early)
  expect_lt(got$reps, five$reps)
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

# ---- one model's nulls in several processes (Steve, 2026-11-20) -----------------

# Stands in for forked processes where the machine cannot fork (Windows):
# each run starts from the stream as it stood, works on its own copy of
# nothing it could pass back but its result, and leaves this process's
# stream untouched, as a forked child does.
emulated_forks <- function(runs, f, cores, ...) {
  stream <- atlas_rng_state()
  on.exit(atlas_rng_restore(stream), add = TRUE)
  lapply(runs, function(run) {
    atlas_rng_restore(stream)
    f(run)
  })
}

test_that("a fit uses idle processes only in a pool that says some are idle, and an equal share of them", {
  state <- tempfile()
  writeLines("6 2", state)
  expect_equal(atlas_null_cores(state, most = 8L, can_fork = TRUE, pinned = TRUE), 4L)
  expect_equal(atlas_null_cores(state, most = 3L, can_fork = TRUE, pinned = TRUE), 3L)
  writeLines("0 21", state)
  expect_equal(atlas_null_cores(state, most = 8L, can_fork = TRUE, pinned = TRUE), 1L)
  writeLines("20 1", state)
  expect_equal(atlas_null_cores(state, most = 8L, can_fork = TRUE, pinned = TRUE), 8L)
  # Not in a pool, no state yet, a machine that cannot fork, a process whose
  # BLAS runs its own threads, or a state that makes no sense: one process.
  expect_equal(atlas_null_cores("", most = 8L, can_fork = TRUE, pinned = TRUE), 1L)
  expect_equal(atlas_null_cores(tempfile(), most = 8L, can_fork = TRUE, pinned = TRUE), 1L)
  expect_equal(atlas_null_cores(state, most = 8L, can_fork = FALSE, pinned = TRUE), 1L)
  expect_equal(atlas_null_cores(state, most = 8L, can_fork = TRUE, pinned = FALSE), 1L)
  writeLines("half a line", state)
  expect_equal(atlas_null_cores(state, most = 8L, can_fork = TRUE, pinned = TRUE), 1L)
  # A pool's processes start pinned; this one need not be.
  expect_true(atlas_threads_pinned(function(name, unset) "1"))
  expect_false(atlas_threads_pinned(function(name, unset) if (name == "OMP_NUM_THREADS") "1" else ""))
  with_env(c(ATLAS_NULL_MAX_CORES = "2"), expect_equal(atlas_null_max_cores(), 2L))
  with_env(c(ATLAS_NULL_MAX_CORES = "nonsense"), expect_equal(atlas_null_max_cores(), ATLAS_NULL_MAX_CORES))
})

test_that("a batch scored in several processes comes back in order, and a lost process's nulls are scored here", {
  tables <- as.list(1:7)
  score <- function(ts) lapply(ts, function(t) c(auc = t / 10, boyce = 0))
  serial <- score(tables)
  expect_identical(c(atlas_null_score(tables, score, 3L, map = emulated_forks)), serial)
  expect_identical(c(atlas_null_score(tables, score, 20L, map = emulated_forks)), serial)
  expect_equal(attr(atlas_null_score(tables, score, 3L, map = emulated_forks), "lost"), 0L)
  # One process killed (mclapply gives NULL or an error in its place).
  lose_second <- function(runs, f, cores, ...) {
    out <- emulated_forks(runs, f, cores)
    out[2] <- list(NULL)
    out[[3]] <- structure("killed", class = "try-error")
    out
  }
  lost <- atlas_null_score(tables, score, 4L, map = lose_second)
  expect_identical(unclass(lost)[seq_along(serial)], serial)
  expect_equal(attr(lost, "lost"), 2L)
  expect_identical(c(atlas_null_score(tables, score, 4L, map = function(...) stop("cannot fork"))), serial)
})

test_that("a model's null test gives the same result in one process or several, for every learner", {
  skip_if_not_installed("maxnet")
  world <- null_world("cluster")
  folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1, presence = world$presence)
  splits <- atlas_null_fold_splits(world$x, world$y, folds, k = 5, block_km = 200, seed = 1,
                                   presence = world$presence, splits = 2L)
  learners <- c("maxnet", if (requireNamespace("ranger", quietly = TRUE)) "rf",
                if (requireNamespace("xgboost", quietly = TRUE)) "xgboost")
  for (learner in learners) {
    algo <- atlas_algorithm(learner)
    run <- function(cores, map = emulated_forks, batch = 10L) {
      set.seed(42)
      result <- atlas_null_test_sequential(world, splits, algo, reps = 19L, seed = 3, design = "shift",
                                           stop_after = 20L, batch = batch, cores = function() cores, map = map)
      list(result = result, after = stats::runif(1))
    }
    one <- run(1L)
    expect_equal(one$result$reps, 19L, info = learner)
    # Several processes, and other batch sizes: the same nulls, the same
    # scores, and the stream left where it would be.
    for (other in list(run(3L), run(8L), run(1L, batch = 4L))) {
      expect_identical(other$result, one$result, info = learner)
      expect_identical(other$after, one$after, info = learner)
    }
  }
})

test_that("forked for real in a pool's process, as production forks, a model's nulls give the one-process result", {
  skip_on_os("windows")
  skip_if_not_installed("maxnet")
  root <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  skip_if_not(file.exists(file.path(root, "R", "nulls.R")), "sources not found")
  world <- null_world("cluster")
  learners <- c("maxnet", if (requireNamespace("ranger", quietly = TRUE)) "rf",
                if (requireNamespace("xgboost", quietly = TRUE)) "xgboost")
  with_env(c(ATLAS_ROOT = root), with_data_dir({
    cluster <- atlas_start_workers(1L, "draft", points = NULL)
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    compare <- function(world, learners) {
      folds <- atlas_spatial_folds(world$x, world$y, k = 5, block_km = 200, seed = 1, presence = world$presence)
      splits <- atlas_null_fold_splits(world$x, world$y, folds, k = 5, block_km = 200, seed = 1,
                                       presence = world$presence, splits = 2L)
      lapply(stats::setNames(nm = learners), function(learner) {
        # Every forked run must come back: one lost or stuck would be scored
        # in this process and hide the fault.
        lost <- 0L
        forked <- 0L
        counting <- function(runs, f, cores, timeout) {
          out <- atlas_null_fork_map(runs, f, cores, timeout = 120)
          forked <<- forked + length(runs)
          lost <<- lost + sum(vapply(out, is.null, logical(1)))
          out
        }
        run <- function(cores) atlas_null_test_sequential(
          world, splits, atlas_algorithm(learner), reps = 19L, seed = 3, design = "shift", stop_after = 20L,
          cores = function() cores, map = counting)
        list(pinned = atlas_threads_pinned(), same = identical(run(3L), run(1L)), forked = forked, lost = lost)
      })
    }
    environment(compare) <- globalenv()
    answers <- parallel::clusterCall(cluster, compare, world, learners)[[1]]
    for (learner in learners) {
      expect_true(answers[[learner]]$pinned, info = learner)
      expect_true(answers[[learner]]$same, info = learner)
      expect_gt(answers[[learner]]$forked, 0L)
      expect_equal(answers[[learner]]$lost, 0L, info = learner)
    }
  }))
})

test_that("a forked run that does not come back in time is killed and scored here, and the model forks no more", {
  skip_on_os("windows")
  stuck <- function(i) if (identical(i, 2L)) { Sys.sleep(600); "late" } else paste("done", i)
  started <- Sys.time()
  out <- atlas_null_fork_map(list(1L, 2L, 3L), stuck, 3L, timeout = 3)
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 60)
  expect_equal(out[[1]], "done 1")
  expect_null(out[[2]])
  expect_equal(out[[3]], "done 3")
  # In a model's test: the batch still comes back whole, from here.
  parent <- Sys.getpid()
  tables <- as.list(1:6)
  score <- function(ts) lapply(ts, function(t) c(auc = t / 10, boyce = 0))
  hang_one <- function(ts) if (identical(ts[[1]], 3L)) { Sys.sleep(600); list() } else score(ts)
  scored <- atlas_null_score(tables, function(ts) if (Sys.getpid() != parent) hang_one(ts) else score(ts),
                             3L, timeout = 3)
  expect_identical(c(scored), score(tables))
  expect_equal(attr(scored, "lost"), 1L)
})

test_that("a pool's processes are told where it says how many of them are idle, and it says so once its queue is empty", {
  cluster <- atlas_make_workers(2L)
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  state <- attr(cluster, "pool_state")
  expect_true(nzchar(state))
  told <- unlist(parallel::clusterEvalQ(cluster, Sys.getenv("ATLAS_POOL_STATE")))
  expect_equal(told, rep(state, 2L))
  # The variable is the workers', not this process's.
  expect_false(identical(Sys.getenv("ATLAS_POOL_STATE"), state))
  # The slow taxon reads the state after the quick one has finished, with
  # nothing left to send: one process idle, one busy.
  task <- function(name, state) {
    if (!identical(name, "slow")) return(list(taxon = name, status = "fitted"))
    Sys.sleep(3)
    list(taxon = name, status = "fitted", seen = readLines(state, n = 1L, warn = FALSE))
  }
  environment(task) <- globalenv()
  seen <- list()
  atlas_run_on_workers(cluster, c("slow", "quick"), task, function(row) seen[[row$taxon]] <<- row$seen,
                       state = state)
  expect_equal(seen$slow, "1 1")
  expect_equal(readLines(state, warn = FALSE), "2 0")
})
