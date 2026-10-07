# Ensembles of small models, and the study that says how few sites carry a map.

# A landscape where suitability rises with v1 and peaks in the middle of v3;
# v2 and v4 say nothing. Sites lie in blocks so folds can be spatial.
esm_world <- function(n = 1500, presences = 12, seed = 3) {
  set.seed(seed)
  table <- data.frame(
    presence = 0L, cell = seq_len(n),
    x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
    v1 = stats::runif(n, -2, 2), v2 = stats::runif(n, -2, 2),
    v3 = stats::runif(n, -2, 2), v4 = stats::runif(n, -2, 2),
    effort = stats::runif(n, 0, 3)
  )
  truth <- stats::plogis(2.5 * table$v1) * exp(-table$v3^2)
  table$presence[sample.int(n, presences, prob = truth)] <- 1L
  attr(table, "truth") <- truth
  table
}

test_that("an ensemble is every pair of its predictors, weighted to sum to one", {
  skip_if_not_installed("glmnet")
  world <- esm_world(presences = 40)
  model <- atlas_fit_esm(world, predictors = c("v1", "v2", "v3", "v4"))
  expect_s3_class(model, "atlas_esm")
  expect_equal(model$considered, 6L)
  expect_equal(sum(model$weights), 1)
  expect_true(all(model$weights > 0))
  expect_equal(length(model$models), length(model$pairs))
  expect_true(all(vapply(model$pairs, function(p) all(p %in% c("v1", "v2", "v3", "v4")),
                         logical(1))))
})

test_that("a small model that does no better than chance has no say", {
  skip_if_not_installed("glmnet")
  world <- esm_world(presences = 60)
  model <- atlas_fit_esm(world, predictors = c("v1", "v2", "v3", "v4"))
  kept <- vapply(model$pairs, paste, character(1), collapse = "+")
  all_pairs <- vapply(utils::combn(c("v1", "v2", "v3", "v4"), 2, simplify = FALSE), paste,
                      character(1), collapse = "+")
  somers <- stats::setNames(model$somers, all_pairs)
  expect_setequal(kept, names(somers)[is.finite(somers) & somers > 0])
  # The pair that holds both real predictors weighs more than the pair of noise.
  weight <- stats::setNames(model$weights, kept)
  expect_gt(weight[["v1+v3"]], if ("v2+v4" %in% kept) weight[["v2+v4"]] else 0)
})

test_that("an ensemble of twelve sites finds the habitat", {
  skip_if_not_installed("glmnet")
  world <- esm_world(presences = 12)
  model <- atlas_fit_esm(world, predictors = c("v1", "v2", "v3", "v4"))
  scores <- atlas_esm_suitability(model, world)
  expect_true(all(is.finite(scores) & scores >= 0 & scores <= 1))
  expect_gt(stats::cor(scores, attr(world, "truth"), method = "spearman"), 0.5)
})

test_that("eight detections cannot drive a small model to certainty", {
  skip_if_not_installed("glmnet")
  world <- esm_world(presences = 8)
  # Every detection far out on v1, where no other site is: an unpenalised
  # regression would separate them perfectly.
  world$v1[world$presence == 1L] <- 5
  model <- atlas_fit_esm(world, predictors = c("v1", "v2"))
  coefficients <- as.numeric(stats::coef(model$models[[1]]))
  expect_true(all(is.finite(coefficients)))
  expect_lt(max(abs(coefficients)), 12)
})

test_that("effort is in every small model and is held fixed when a map is scored", {
  skip_if_not_installed("glmnet")
  world <- esm_world(presences = 30)
  model <- atlas_fit_esm(world, predictors = c("v1", "v3"))
  expect_true("effort" %in% rownames(stats::coef(model$models[[1]])))
  held <- atlas_score_at_effort(atlas_esm_suitability, 1.5)
  busy <- world
  busy$effort <- 3
  expect_equal(held(model, world), held(model, busy))
  expect_false(isTRUE(all.equal(atlas_esm_suitability(model, world),
                                atlas_esm_suitability(model, busy))))
})

test_that("when the inner blocks cannot be scored the small models weigh the same", {
  skip_if_not_installed("glmnet")
  world <- esm_world(presences = 6)
  # Every detection in one corner: no inner fold has detections on both sides.
  world$x[world$presence == 1L] <- 5000
  world$y[world$presence == 1L] <- 5000
  model <- atlas_fit_esm(world, predictors = c("v1", "v2", "v3"))
  expect_equal(model$weights, rep(1 / 3, 3))
})

test_that("an ensemble's predictors are the head of the pruned list, in the guild's order", {
  set.seed(9)
  n <- 400
  background <- data.frame(
    soil_phh2o = stats::rnorm(n), bio12 = stats::rnorm(n), bio1 = stats::rnorm(n),
    bio6 = stats::rnorm(n), cover_trees = stats::rnorm(n), elevation = stats::rnorm(n)
  )
  background$bio5 <- background$bio1 + stats::rnorm(n, sd = 0.01)
  for (band in ATLAS_HOST_BANDS) background[[band]] <- stats::runif(n)
  training <- rbind(
    data.frame(presence = 1L, cell = 1:8, x = 0, y = 0, background[1:8, ], effort = 1),
    data.frame(presence = 0L, cell = 9:(n + 8), x = 0, y = 0, background, effort = 1)
  )
  picked <- atlas_esm_predictors(training, n = 6,
                                 priority = atlas_predictor_priority("ectomycorrhizal"),
                                 host_share = atlas_host_allowance("ectomycorrhizal"))
  expect_equal(length(picked), 6L)
  expect_equal(picked[[1]], "soil_phh2o")
  # A third of six for the trees, the rest for soil and climate.
  expect_equal(sum(atlas_is_host_share(picked)), 2L)
  expect_true(all(c("bio12", "bio1") %in% picked))
  expect_false("bio5" %in% picked)
  expect_false("effort" %in% picked)
})

test_that("a fit refuses one detection, and one predictor", {
  skip_if_not_installed("glmnet")
  world <- esm_world(presences = 1)
  expect_error(atlas_fit_esm(world, predictors = c("v1", "v2")), "at least two presences")
  expect_error(atlas_fit_esm(esm_world(), predictors = "v1"), "at least two predictors")
})

# --- The study --------------------------------------------------------------

test_that("the study fits every learner at every size, and on every site", {
  arms <- atlas_sparse_arms(sizes = c(5, 12), learners = c("esm", "rf"))
  names <- vapply(arms, function(a) a$arm, character(1))
  expect_setequal(names, c("esm@5", "rf@5", "esm@12", "rf@12", "esm@all", "rf@all"))
  expect_equal(arms[[which(names == "esm@12")]]$size, 12)
  expect_true(is.infinite(arms[[which(names == "rf@all")]]$size))
  expect_true(ATLAS_SPARSE_BASELINE %in%
                vapply(atlas_sparse_arms(), function(a) a$arm, character(1)))
})

test_that("thinning takes detections away and leaves every non-detection", {
  world <- esm_world(presences = 50)
  thinned <- atlas_thin_detections(world, 8, seed = 4L)
  expect_equal(sum(thinned$presence == 1L), 8L)
  expect_equal(sum(thinned$presence == 0L), sum(world$presence == 0L))
  expect_true(all(thinned$cell[thinned$presence == 1L] %in% world$cell[world$presence == 1L]))
  expect_equal(thinned, atlas_thin_detections(world, 8, seed = 4L))
  expect_false(identical(thinned$cell, atlas_thin_detections(world, 8, seed = 5L)$cell))
  # A taxon with fewer sites than asked for keeps what it has.
  expect_equal(atlas_thin_detections(world, 80), world)
  expect_equal(atlas_thin_detections(world, Inf), world)
})

test_that("a thinned model is judged on every held-out detection, not on a thinned few", {
  skip_if_not_installed("terra")
  skip_if_not_installed("glmnet")
  world <- synthetic_landscape()
  seen <- list()
  testthat::local_mocked_bindings(
    atlas_fit_esm = function(training, ...) {
      seen[[length(seen) + 1L]] <<- list(found = sum(training$presence == 1L),
                                         others = sum(training$presence == 0L),
                                         cells = training$cell)
      structure(list(), class = "stub")
    },
    atlas_esm_suitability = function(model, newdata) {
      seen[[length(seen)]]$scored <<- nrow(newdata)
      newdata$v1
    },
    atlas_esm_predictors = function(training, ...) c("v1", "v2")
  )
  row <- atlas_sparse_taxon(
    "Eastern fungus", fingerprint = "f00dfeed", points = world$points, stack = world$stack,
    arms = atlas_sparse_arms(sizes = 5, learners = "esm"),
    n_background = 500, buffer_km = 300, block_km = 200, min_presences = 20,
    guilds = stats::setNames(character(), character())
  )
  expect_equal(row$status, "scored")
  thin <- row$arms[[which(vapply(row$arms, function(a) a$arm, character(1)) == "esm@5")]]
  full <- row$arms[[which(vapply(row$arms, function(a) a$arm, character(1)) == "esm@all")]]
  expect_equal(thin$sites_fitted, 5)
  expect_gt(full$sites_fitted, 20)
  folds <- thin$folds_scored
  thinned <- seen[seq_len(folds)]
  whole <- seen[folds + seq_len(folds)]
  expect_true(all(vapply(thinned, function(s) s$found, numeric(1)) == 5))
  # The same non-detections, and the same held-out sites, thinned or not.
  expect_equal(vapply(thinned, function(s) s$others, numeric(1)),
               vapply(whole, function(s) s$others, numeric(1)))
  expect_equal(vapply(thinned, function(s) s$scored, numeric(1)),
               vapply(whole, function(s) s$scored, numeric(1)))
  expect_true(is.finite(thin$auc))
})

test_that("the study writes its results and never touches the fitted models", {
  skip_if_not_installed("terra")
  skip_if_not_installed("glmnet")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    occurrences <- data.frame(
      id = as.character(seq_len(nrow(world$points))),
      scientific_name = world$points$scientific_name,
      latitude = "45", longitude = "-100", observed_on = "2025-01-01",
      stringsAsFactors = FALSE
    )
    result <- atlas_sparse_study(
      occurrences = occurrences, points = world$points, stack = world$stack,
      sizes = 8, learners = c("esm", "maxnet"), n_background = 500, buffer_km = 300,
      block_km = 200, min_presences = 40, quiet = TRUE, taxa = "Eastern fungus"
    )
    expect_true(file.exists(result$path))
    expect_match(result$path, "sparse-studies")
    expect_false(dir.exists(atlas_path("models")))
    saved <- jsonlite::fromJSON(result$path, simplifyVector = FALSE)
    expect_equal(saved$baseline, "maxnet@all")
    arms <- unique(vapply(saved$summary, function(r) r$arm, character(1)))
    expect_setequal(arms, c("esm@8", "maxnet@8", "esm@all", "maxnet@all"))
    # In this landscape the fungus lives in the east and v1 rises eastward:
    # eight sites are enough for an ensemble to see it.
    scored <- saved$taxa[[1]]$arms
    auc <- stats::setNames(vapply(scored, function(a) as.numeric(a$auc), numeric(1)),
                           vapply(scored, function(a) a$arm, character(1)))
    expect_gt(auc[["esm@8"]], 0.7)
  })
})

# --- In production ---------------------------------------------------------

# The synthetic landscape with the eastern fungus cut down to k records.
sparse_world <- function(k) {
  world <- synthetic_landscape()
  focal <- which(world$points$scientific_name == "Eastern fungus")
  world$points <- world$points[-focal[-seq_len(k)], , drop = FALSE]
  world
}

fit_sparse <- function(world, algorithm = "esm", nulls = 0, predict = TRUE) {
  atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                  fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                  buffer_km = 300, predict = predict, quiet = TRUE, nulls = nulls,
                  algorithm = algorithm, guilds = stats::setNames(character(), character()))
}

test_that("the ensemble maps taxa with 3 to 49 sites, standing in for boosted trees from 20", {
  esm <- atlas_algorithm("esm")
  expect_equal(atlas_algorithm_min(esm, 20), 3)
  # Up to where boosted trees begin, so no taxon from 20 sites is left with
  # an empty panel (Steve, 2026-10-06).
  expect_equal(atlas_algorithm_max(esm), atlas_algorithm_min(atlas_algorithm("xgboost"), 20) - 1)
  expect_equal(atlas_algorithm_min(atlas_algorithm("maxnet"), 20), 20)
  expect_equal(atlas_algorithm_max(atlas_algorithm("maxnet")), Inf)
  expect_equal(atlas_algorithm_min(atlas_algorithm("xgboost"), 20), 50)
  expect_true("esm" %in% atlas_parse_algorithms("all"))
})

test_that("taxa under 20 sites are scored on three folds of 100 km blocks; the others as before", {
  esm <- atlas_fit_settings(algorithm = "esm", folds = 5, block_km = "auto", layers = "x", guild_table = "g")
  expect_equal(esm$folds, 3)
  expect_equal(esm$block_km, 100)
  expect_equal(esm$min_blocks, 3)
  maxent <- atlas_fit_settings(algorithm = "maxnet", folds = 5, block_km = "auto", layers = "x", guild_table = "g")
  expect_equal(maxent$folds, 5)
  expect_equal(maxent$block_km, "auto")
  expect_equal(maxent$min_blocks, ATLAS_MIN_BLOCKS)
})

test_that("a batch offers the ensemble its range, with a margin for sites that drop out", {
  points <- rbind(
    fake_points(x = seq(0, by = 6000, length.out = 25), y = 0, names = "Rich"),
    fake_points(x = seq(0, by = 6000, length.out = 21), y = 50000, names = "Edge"),
    fake_points(x = seq(0, by = 6000, length.out = 10), y = 100000, names = "Sparse"),
    fake_points(x = c(0, 6000), y = 150000, names = "Too few"),
    fake_points(x = seq(0, by = 6000, length.out = 60), y = 200000, names = "Well recorded")
  )
  points$cell <- seq_len(nrow(points))
  esm <- atlas_algorithm("esm")
  names <- atlas_batch_candidates(points, atlas_algorithm_min(esm),
                                  max_presences = atlas_algorithm_max(esm) + ATLAS_RANGE_MARGIN)$scientific_name
  # 25 and 21 sites: the ensemble beside Maxent and the forest. 60: trees.
  expect_setequal(names, c("Rich", "Edge", "Sparse"))
  expect_equal(atlas_batch_candidates(points, 20)$scientific_name, c("Well recorded", "Rich", "Edge"))
})

test_that("an ensemble fitted on a dozen sites has a map, scores on three folds, and a breakdown", {
  skip_if_not_installed("terra")
  skip_if_not_installed("glmnet")
  with_data_dir({
    result <- fit_sparse(sparse_world(12))
    m <- result$metrics
    expect_equal(m$algorithm, "esm")
    expect_equal(m$presences, 12)
    expect_equal(length(m$folds), 3L)
    expect_equal(m$block_km, 100)
    expect_false(m$map_withheld)
    expect_true(file.exists(atlas_model_path("Eastern fungus", "draft", ".tif", "esm")))
    expect_true(length(m$importance) >= 1L)
    expect_true(is.finite(m$auc_mean))
  })
})

test_that("from 3 or 4 sites a map that fails its null test is still drawn: no test can vouch for so few", {
  skip_if_not_installed("terra")
  skip_if_not_installed("glmnet")
  with_data_dir({
    testthat::local_mocked_bindings(atlas_skill = function(null, boyce, alpha = 0.05) "failed")
    m <- fit_sparse(sparse_world(4))$metrics
    expect_equal(m$presences, 4)
    expect_equal(m$skill, "failed")
    expect_false(m$map_withheld)
    expect_true(file.exists(atlas_model_path("Eastern fungus", "draft", ".tif", "esm")))
  })
})

test_that("a map withheld under the old rule is fitted again, so that it is drawn", {
  settings <- list(algorithm = "esm", a = 1)
  key <- atlas_settings_key(settings)
  metrics <- list(fingerprint = "f", settings_key = key, presences = 4, map_withheld = TRUE)
  expect_false(atlas_fit_is_current(metrics, "f", settings, predict = TRUE))
  entry <- list(fingerprint = "f", settings_key = key, map = FALSE, map_withheld = TRUE, presences = 4)
  expect_false(atlas_index_current(entry, "f", settings, 3, 19))
})

test_that("from 5 sites up a map is drawn whatever its skill, as every other map is", {
  skip_if_not_installed("terra")
  skip_if_not_installed("glmnet")
  with_data_dir({
    testthat::local_mocked_bindings(atlas_skill = function(null, boyce, alpha = 0.05) "failed")
    m <- fit_sparse(sparse_world(6))$metrics
    expect_equal(m$skill, "failed")
    expect_false(m$map_withheld)
    expect_true(file.exists(atlas_model_path("Eastern fungus", "draft", ".tif", "esm")))
  })
})

test_that("the ensemble refuses a taxon rich enough for the other models, and they refuse a sparse one", {
  skip_if_not_installed("terra")
  skip_if_not_installed("glmnet")
  skip_if_not_installed("maxnet")
  with_data_dir({
    rich <- tryCatch(fit_sparse(synthetic_landscape(), predict = FALSE), atlas_insufficient_evidence = function(e) e)
    expect_s3_class(rich, "atlas_insufficient_evidence")
    expect_match(conditionMessage(rich), "enough detection sites")
    sparse <- tryCatch(fit_sparse(sparse_world(12), algorithm = "maxnet", predict = FALSE),
                       atlas_insufficient_evidence = function(e) e)
    expect_s3_class(sparse, "atlas_insufficient_evidence")
  })
})

test_that("where an algorithm still withholds a map, the withheld fit is current and says so", {
  # No algorithm withholds today; the rule is kept for one that would.
  expect_false(atlas_map_withheld_at("esm", 4))
  expect_true(atlas_map_withheld_at(list(map_needs_skill_below = 5), 4))
  expect_false(atlas_map_withheld_at(list(map_needs_skill_below = 5), 5))
  testthat::local_mocked_bindings(atlas_map_withheld_at = function(algo, presences) presences < 5)
  entry <- list(fingerprint = "f", settings_key = "k", map = FALSE, map_withheld = TRUE, presences = 4)
  settings <- list(a = 1)
  entry$settings_key <- atlas_settings_key(settings)
  expect_true(atlas_index_current(entry, "f", settings, 3, 19))
  expect_false(atlas_index_current(entry, "f", settings, 5, 19))
  entry$map_withheld <- NULL
  expect_false(atlas_index_current(entry, "f", settings, 3, 19))
  indexed <- atlas_model_index_entry(list(taxon = "T", fingerprint = "f", settings_key = "k", presences = 4,
                                    map_withheld = TRUE, skill = "failed"), "esm")
  expect_true(indexed$map_withheld)
  expect_false(indexed$map)
})
