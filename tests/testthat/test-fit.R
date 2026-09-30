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

test_that("a map never asks the model about ground outside the accessible area", {
  skip_if_not_installed("terra")
  world <- synthetic_landscape()
  area <- atlas_accessible_area(x = 500000, y = 500000, buffer_km = 150)
  seen <- 0L
  count_rows <- function(model, data) {
    seen <<- seen + nrow(data)
    rep(0.5, nrow(data))
  }
  predicted <- atlas_predict_raster(NULL, world$stack, area, score = count_rows)
  inside <- sum(!is.na(terra::values(predicted)))
  # Only the cells inside the circle reach the model; the square around it
  # holds about 4/pi times as many. terra also tries the function once on a
  # small sample to learn its output, hence the tolerance.
  expect_gt(inside, 0L)
  expect_lt(seen, inside * 1.1)
})

test_that("folds are dealt so every fold holds a detection when that is possible", {
  # Twenty blocks, detections in only five of them. A careless deal leaves
  # folds with nothing to score; the balanced one does not.
  block <- rep(0:19, each = 10)
  x <- block * 1e5 + 5e4
  y <- rep(0, length(x))
  presence <- as.integer(block %in% c(0, 4, 8, 12, 16) & rep(c(1, rep(0, 9)), 20) == 1)
  folds <- atlas_spatial_folds(x, y, k = 5, block_km = 100, seed = 3L, presence = presence)
  expect_equal(sort(unique(folds[presence == 1L])), 1:5)
  # Blocks still stay whole.
  expect_true(all(tapply(folds, floor(x / 1e5), function(f) length(unique(f))) == 1L))
  expect_equal(folds, atlas_spatial_folds(x, y, k = 5, block_km = 100, seed = 3L,
                                          presence = presence))
})

test_that("Maxent fitted by appending presences matches maxnet's own way", {
  skip_if_not_installed("maxnet")
  training <- simulated_training(n_background = 300, n_presence = 40)
  # The simulation copies presences from background rows; a site is never
  # both, so nudge them apart as sites are.
  found <- training$presence == 1L
  training$v2[found] <- training$v2[found] + 1e-3
  ours <- atlas_fit_maxnet(training, classes = "lq")
  predictors <- training[, atlas_predictor_columns(training)]
  theirs <- maxnet::maxnet(training$presence, predictors,
                           maxnet::maxnet.formula(training$presence, predictors, classes = "lq"))
  # Not to the last digit: Atlas steps through 20 penalty values on the way to
  # maxnet's final one, maxnet through 200, and the solver stops a hair apart.
  expect_equal(atlas_suitability(ours, predictors), atlas_suitability(theirs, predictors),
               tolerance = 1e-3)
})

test_that("scores and maps hold effort at one value, whatever a site's effort was", {
  score <- function(model, newdata) newdata$effort
  held <- atlas_score_at_effort(score, effort_at = 1.5)
  expect_equal(held(NULL, data.frame(v1 = 1:3, effort = c(0, 2, 7))), rep(1.5, 3))
  # A raster block has no effort column at all; it is added.
  expect_equal(held(NULL, data.frame(v1 = 1:2)), rep(1.5, 2))
  # Without effort in the design the score is untouched.
  expect_identical(atlas_score_at_effort(score, NULL), score)
})

test_that("the effort a map is drawn at is the median of the detection sites", {
  training <- data.frame(presence = c(1L, 1L, 1L, 0L), effort = c(0, 1, 5, 9))
  expect_equal(atlas_effort_level(training), 1)
  expect_null(atlas_effort_level(data.frame(presence = 1L)))
})

test_that("collecting effort alone does not make a habitat map", {
  skip_if_not_installed("maxnet")
  # Sites in the east were worked far harder, and the species is nothing but
  # a random share of what was collected: no habitat preference at all. A map
  # that ignores effort puts the species in the east; holding effort fixed,
  # the map should be nearly flat along v1.
  set.seed(21)
  n <- 3000
  v1 <- stats::runif(n, 0, 10)
  records <- 1 + stats::rpois(n, exp(0.35 * v1))
  found <- stats::runif(n) < 1 - (1 - 0.01)^records
  # v2 is noise; maxnet cannot fit a single predictor.
  training <- data.frame(presence = as.integer(found), cell = seq_len(n), x = 0, y = 0,
                         v1 = v1, v2 = stats::runif(n), effort = log(records))
  grid <- data.frame(v1 = seq(0, 10, length.out = 50), v2 = 0.5)

  # Production's Maxent leaves effort out (it scored better without); the
  # mechanism is tested here with it in, as the trees use it.
  with_effort <- atlas_fit_maxnet(training, classes = "l", use_effort = TRUE)
  held <- atlas_score_at_effort(atlas_suitability, atlas_effort_level(training))
  flat <- held(with_effort, grid)

  without <- atlas_fit_maxnet(training[, setdiff(names(training), "effort")], classes = "l")
  biased <- atlas_suitability(without, grid)

  expect_gt(stats::cor(biased, grid$v1), 0.9)
  expect_lt(abs(log(max(flat) / min(flat))), 0.25 * abs(log(max(biased) / min(biased))))
})

test_that("tuning picks the candidate that scores best on the folds it is given", {
  training <- simulated_training(n_background = 300, n_presence = 60)
  set.seed(2)
  training$x <- stats::runif(nrow(training), 0, 1e6)
  folds <- atlas_spatial_folds(training$x, training$y, k = 3, block_km = 100)
  # A fake learner whose "model" is its setting: +1 ranks the simulated
  # species the right way up, -1 upside down, 0 not at all.
  algo <- list(
    default = function(training) list(sign = 0),
    grid = function(training) list(list(sign = -1), list(sign = 1), list(sign = 0)),
    fit = function(train, params, seed = 1L, tuning = FALSE) params$sign,
    score = function(model, newdata) model * -abs(newdata$v1 - 1)
  )
  tuned <- atlas_tune(training, folds, algo)
  expect_equal(tuned$params$sign, 1)
  expect_equal(length(tuned$tried), 3L)
})

test_that("nested tuning never lets a setting see the region it is scored on", {
  training <- simulated_training(n_background = 300, n_presence = 60)
  set.seed(5)
  training$x <- stats::runif(nrow(training), 0, 1e6)
  training$cell <- seq_len(nrow(training))
  folds <- atlas_spatial_folds(training$x, training$y, k = 3, block_km = 100,
                               presence = training$presence)
  touched <- list()
  algo <- list(
    default = function(training) list(),
    grid = function(training) list(list(a = 1), list(a = 2)),
    fit = function(train, params, seed = 1L, tuning = FALSE) {
      touched[[length(touched) + 1L]] <<- train$cell
      0
    },
    score = function(model, newdata) stats::runif(nrow(newdata))
  )
  scores <- atlas_nested_cross_validate(training, folds, algo, block_km = 100)
  expect_equal(nrow(scores), 3L)
  # Fits come in fold order: fold 1's tuning fits and final fit, then fold
  # 2's. Every one made for fold f used only sites outside fold f.
  per_fold <- length(touched) / 3
  for (f in 1:3) {
    held <- training$cell[folds == f]
    for (cells in touched[((f - 1) * per_fold + 1):(f * per_fold)]) {
      expect_length(intersect(cells, held), 0L)
    }
  }
})

test_that("null detections are drawn from the sites, busier sites more often", {
  training <- data.frame(presence = 0L, effort = log(c(rep(1, 900), rep(100, 100))))
  hits <- vapply(1:40, function(i) {
    p <- atlas_null_presence(training, 20, seed = i)
    c(sum(p), sum(p[901:1000]))
  }, numeric(2))
  expect_true(all(hits[1, ] == 20))
  # 100 sites with 100 records each against 900 with 1: most draws land busy.
  expect_gt(mean(hits[2, ] / 20), 0.7)
})

test_that("a real habitat signal beats the nulls, and a random species does not", {
  skip_if_not_installed("maxnet")
  set.seed(8)
  n <- 1500
  v1 <- stats::runif(n, -3, 3)
  training <- data.frame(presence = 0L, cell = seq_len(n),
                         x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
                         v1 = v1, v2 = stats::runif(n), effort = stats::runif(n))
  real <- training
  real$presence[sample.int(n, 80, prob = exp(-((v1 - 1)^2) / 0.3))] <- 1L
  random <- training
  random$presence[sample.int(n, 80)] <- 1L
  algo <- atlas_algorithm("maxnet")
  params <- list(classes = "lq", regmult = 1)
  test <- function(table) {
    folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                                 presence = table$presence)
    scores <- atlas_cross_validate(table, folds, fit = function(t) algo$fit(t, params),
                                   score = algo$score)
    null <- atlas_null_test(table, folds, algo, reps = 9)
    atlas_skill(null, atlas_pooled_boyce(scores), alpha = 0.1)
  }
  expect_equal(test(real), "passed")
  expect_equal(test(random), "failed")
})

test_that("skill needs both a beaten null and a positive Boyce index", {
  expect_equal(atlas_skill(list(reps = 19, auc_p = 0.05), 0.3), "passed")
  expect_equal(atlas_skill(list(reps = 19, auc_p = 0.05), -0.1), "failed")
  expect_equal(atlas_skill(list(reps = 19, auc_p = 0.3), 0.6), "failed")
  expect_equal(atlas_skill(list(reps = 0), 0.6), "untested")
  expect_equal(atlas_skill(NULL, 0.6), "untested")
})

test_that("a taxon found in too few blocks is refused, not scored on nothing", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    condition <- tryCatch(
      atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                      fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                      buffer_km = 300, quiet = TRUE, block_km = 1000, nulls = 0),
      error = function(e) e
    )
    expect_s3_class(condition, "atlas_insufficient_evidence")
    expect_match(conditionMessage(condition), "blocks")
  })
})

test_that("a Maxent fit records its guild and the predictor order that guild gave it", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    fit <- function(guilds) {
      atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                      fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                      buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 0,
                      tune = FALSE, guilds = guilds)
    }
    mycorrhizal <- fit(c(Eastern = "ectomycorrhizal"))$metrics
    expect_equal(mycorrhizal$genus, "Eastern")
    expect_equal(mycorrhizal$guild, "ectomycorrhizal")
    # Whether the inventories spoke for the ground comes before what they said.
    expect_equal(unlist(mycorrhizal$priority)[1:3],
                 c("soil_phh2o", ATLAS_HOST_KNOWN_BANDS, "host_conifer"))

    unknown <- fit(stats::setNames(character(), character()))$metrics
    expect_equal(unknown$guild, "unknown")
    expect_equal(unlist(unknown$priority), atlas_predictor_priority("unknown"))
    # The rule is in the settings, not the taxon's guild: both share a key.
    expect_equal(mycorrhizal$settings_key,
                 atlas_settings_key(atlas_fit_settings(n_background = 500, buffer_km = 300,
                                                       layers = "synthetic", nulls = 0, tune = FALSE,
                                                       guild_table = atlas_guild_table_key(c(Eastern = "ectomycorrhizal")))))
    stored <- atlas_read_metrics("Eastern fungus")
    expect_equal(stored$guild, "unknown")
  })
})

test_that("a changed guild table makes a stored Maxent model stale", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    before <- c(Eastern = "wood_saprotroph")
    atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                    fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                    buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 0,
                    tune = FALSE, guilds = before)
    stored <- atlas_read_metrics("Eastern fungus")
    settings <- function(guilds) {
      atlas_fit_settings(n_background = 500, buffer_km = 300, layers = "synthetic",
                         nulls = 0, tune = FALSE, guild_table = atlas_guild_table_key(guilds))
    }
    expect_true(atlas_fit_is_current(stored, "f00dfeed", settings(before), predict = FALSE))
    expect_false(atlas_fit_is_current(stored, "f00dfeed", settings(c(Eastern = "ectomycorrhizal")),
                                      predict = FALSE))
  })
})

test_that("the guild's order decides which of two interchangeable predictors a fit keeps", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    # Rainfall and pine share are the same surface here, so pruning keeps
    # whichever of the two the guild puts first.
    stack <- c(world$stack[["v1"]], world$stack[["v2"]], world$stack[["v2"]] * 2)
    names(stack) <- c("soil_phh2o", "bio12", "host_pinus")
    fit <- function(guild) {
      atlas_fit_taxon("Eastern fungus", points = world$points, stack = stack,
                      fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                      buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 0,
                      tune = FALSE, guilds = c(Eastern = guild))$metrics
    }
    expect_equal(unlist(fit("ectomycorrhizal")$predictors), c("soil_phh2o", "host_pinus"))
    expect_equal(unlist(fit("wood_saprotroph")$predictors), c("soil_phh2o", "bio12"))
  })
})

# --- One Boyce index over every fold -----------------------------------------

test_that("the Boyce index is taken over every fold's held-out scores together", {
  # Two folds. Between them the detections sit on the higher scores, but a
  # fold alone has too few detections for an index at all.
  scores <- data.frame(fold = 1:2, presences = c(2L, 2L), auc = c(1, 1),
                       boyce = c(NA_real_, NA_real_))
  attr(scores, "held") <- data.frame(
    fold = rep(1:2, each = 12),
    presence = rep(c(1L, 1L, rep(0L, 10)), 2),
    score = c(0.9, 0.6, seq(0.05, 0.95, length.out = 10),
              0.8, 0.7, seq(0.1, 1, length.out = 10))
  )
  expect_true(all(is.na(scores$boyce)))
  pooled <- atlas_pooled_boyce(scores)
  expect_true(is.finite(pooled))
  expect_gt(pooled, 0)
  expect_equal(pooled, atlas_boyce(attr(scores, "held")$score[attr(scores, "held")$presence == 1L],
                                   attr(scores, "held")$score[attr(scores, "held")$presence == 0L]))
  expect_true(is.na(atlas_pooled_boyce(data.frame(fold = 1L))))
})

test_that("cross-validation keeps every held-out score, once", {
  skip_if_not_installed("maxnet")
  set.seed(5)
  n <- 400
  table <- data.frame(presence = 0L, cell = seq_len(n),
                      x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
                      v1 = stats::runif(n), v2 = stats::runif(n))
  table$presence[sample.int(n, 60, prob = table$v1^2)] <- 1L
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                               presence = table$presence)
  scores <- atlas_cross_validate(table, folds, classes = "lq")
  held <- attr(scores, "held")
  expect_equal(nrow(held), n)
  expect_equal(sum(held$presence), 60L)
  expect_equal(as.integer(table(held$fold)), as.integer(table(folds)))
  algo <- atlas_algorithm("maxnet")
  nested <- atlas_nested_cross_validate(table, folds, algo, block_km = 250, tune = FALSE)
  expect_equal(nrow(attr(nested, "held")), n)
})

# --- The taxon and its nulls go through one procedure -------------------------

test_that("the null test fits the taxon and its nulls at the same untuned settings", {
  set.seed(8)
  n <- 300
  table <- data.frame(presence = 0L, cell = seq_len(n),
                      x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
                      v1 = stats::runif(n), v2 = stats::runif(n))
  table$presence[sample.int(n, 40, prob = table$v1^3)] <- 1L
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                               presence = table$presence)
  seen <- list()
  algo <- list(
    id = "stub",
    default = function(training) list(setting = "untuned"),
    fit = function(train, params, seed = 1L, tuning = FALSE) {
      seen[[length(seen) + 1L]] <<- list(
        setting = params$setting, tuning = tuning, real = identical(
          train$cell[train$presence == 1L],
          table$cell[table$presence == 1L & table$cell %in% train$cell]
        )
      )
      stats::glm(presence ~ v1, data = train, family = stats::binomial())
    },
    score = function(model, newdata) {
      as.numeric(stats::predict(model, newdata, type = "response"))
    }
  )
  null <- atlas_null_test(table, folds, algo, reps = 5)
  # Four folds for the taxon and four for each of five nulls.
  expect_equal(length(seen), 24L)
  expect_true(all(vapply(seen, function(s) s$setting, character(1)) == "untuned"))
  expect_true(all(vapply(seen, function(s) isTRUE(s$tuning), logical(1))))
  expect_equal(sum(vapply(seen, function(s) s$real, logical(1))), 4L)
  expect_equal(null$reps, 5L)
  expect_equal(null$settings, "setting=untuned")
  expect_true(is.finite(null$observed_auc))
  # p counts the taxon among the draws: it cannot be below 1 in 6.
  expect_gte(null$auc_p, 1 / 6 - 1e-9)
})

test_that("boosted trees meet their nulls at a fixed tree count", {
  algo <- atlas_algorithm("xgboost")
  params <- atlas_null_params(algo, data.frame(presence = 1L))
  expect_equal(params$nrounds, ATLAS_XGBOOST_NULL_ROUNDS)
  expect_equal(atlas_null_params(atlas_algorithm("maxnet"), data.frame(presence = rep(1L, 40))),
               atlas_algorithm("maxnet")$default(data.frame(presence = rep(1L, 40))))
})

test_that("the design a model records names the effort, the index and the null test", {
  design <- atlas_design()
  expect_match(design$effort, "counted once")
  expect_match(design$skill$boyce, "every fold")
  expect_match(design$skill$nulls, "untuned")
})

test_that("a predictor that does not vary among the sites fitted is left out, not fatal", {
  skip_if_not_installed("maxnet")
  training <- simulated_training(n_background = 800, n_presence = 60)
  # A flag that is 0 at two sites in all of them, as where the tree
  # inventories were silent. Held out together, it is constant in the fit.
  training$flag <- 1
  training$flag[c(100, 200)] <- 0
  fold <- rep(1L, nrow(training))
  fold[c(100, 200)] <- 2L
  fold[sample(setdiff(seq_len(nrow(training)), c(100, 200)), 200)] <- 2L
  train <- training[fold == 1L, ]
  expect_equal(length(unique(train$flag)), 1L)
  model <- atlas_fit_maxnet(train, classes = "lqh")
  scores <- atlas_suitability(model, training[fold == 2L, atlas_predictor_columns(training)])
  expect_true(all(is.finite(scores)))
  expect_false(any(grepl("flag", names(model$betas))))
  # And cross-validation, where it happened, scores every fold.
  folds <- atlas_cross_validate(training, fold, classes = "lqh")
  expect_true(all(is.finite(folds$auc)))
})

# --- A shorter penalty path ends at maxnet's own model ------------------------

path_table <- function(presences, seed = 12) {
  training <- simulated_training(n_background = 1500, n_presence = presences, seed = seed)
  training$v3 <- stats::runif(nrow(training))
  data <- training[, c("v1", "v2", "v3")]
  data <- rbind(data, data[training$presence == 1L, , drop = FALSE])
  p <- c(as.integer(training$presence), rep(0L, sum(training$presence == 1L)))
  list(p = p, data = data, grid = data[p == 0L, , drop = FALSE])
}

test_that("20 penalty steps give maxnet's own model, for every feature class it tunes", {
  skip_if_not_installed("maxnet")
  for (classes in c("lq", "lqh")) {
    t <- path_table(60)
    f <- maxnet::maxnet.formula(t$p, t$data, classes = classes)
    theirs <- maxnet::maxnet(t$p, t$data, f, regmult = 1, addsamplestobackground = FALSE)
    ours <- atlas_maxnet(t$p, t$data, f, regmult = 1)
    expect_s3_class(ours, "maxnet")
    a <- atlas_suitability(theirs, t$grid)
    b <- atlas_suitability(ours, t$grid)
    expect_gt(stats::cor(a, b), 0.9999)
    expect_lt(max(abs(a - b)), 0.01)
    expect_equal(ours$alpha, theirs$alpha, tolerance = 0.01)
  }
})

test_that("the path is as long as asked, and a weaker or stronger penalty still ends where maxnet does", {
  skip_if_not_installed("maxnet")
  t <- path_table(40)
  f <- maxnet::maxnet.formula(t$p, t$data, classes = "lq")
  expect_equal(length(atlas_maxnet(t$p, t$data, f)$lambda), ATLAS_MAXNET_PATH_STEPS)
  expect_equal(length(atlas_maxnet(t$p, t$data, f, steps = 7L)$lambda), 7L)
  for (regmult in c(0.25, 4)) {
    theirs <- maxnet::maxnet(t$p, t$data, f, regmult = regmult, addsamplestobackground = FALSE)
    ours <- atlas_maxnet(t$p, t$data, f, regmult = regmult)
    expect_equal(min(ours$lambda), min(theirs$lambda))
    expect_gt(stats::cor(atlas_suitability(theirs, t$grid), atlas_suitability(ours, t$grid)), 0.9999)
  }
})

test_that("Maxent fits through the short path, and its settings say how long it is", {
  skip_if_not_installed("maxnet")
  training <- simulated_training(n_background = 800, n_presence = 60)
  model <- atlas_fit_maxnet(training, classes = "lqh")
  expect_equal(length(model$lambda), ATLAS_MAXNET_PATH_STEPS)
  expect_equal(ATLAS_MAXNET_PATH_STEPS, 20L)
  settings <- atlas_fit_settings(algorithm = "maxnet", layers = "x", guild_table = "g")
  expect_equal(settings$learner$path_steps, 20L)
  longer <- settings
  longer$learner$path_steps <- 200L
  expect_false(identical(atlas_settings_key(settings), atlas_settings_key(longer)))
})

# --- Maxent leaves effort out ---------------------------------------------------

test_that("production's Maxent leaves effort out, and its maps do not change with it", {
  skip_if_not_installed("maxnet")
  training <- simulated_training(n_background = 800, n_presence = 60)
  training$effort <- stats::runif(nrow(training), 0, 4)
  algo <- atlas_algorithm("maxnet")
  expect_false(algo$use_effort)
  expect_false(algo$learner()$effort)
  model <- algo$fit(training, list(classes = "lq", regmult = 1))
  expect_false(any(grepl("effort", names(model$betas))))
  grid <- training[, c("v1", "v2", "effort")]
  busy <- grid
  busy$effort <- 4
  expect_equal(algo$score(model, grid), algo$score(model, busy))
})

test_that("the trees still use effort, and so does the null model behind Maxent", {
  expect_true(is.null(atlas_algorithm("rf")$use_effort) || isTRUE(atlas_algorithm("rf")$use_effort))
  expect_true(is.null(atlas_algorithm("xgboost")$use_effort) || isTRUE(atlas_algorithm("xgboost")$use_effort))
  # Nulls are drawn where collecting was busiest, whatever the model is given.
  training <- data.frame(presence = 0L, cell = 1:1000, x = 0, y = 0, v1 = 0,
                         effort = c(rep(log(5000), 10), rep(0, 990)))
  drawn <- atlas_null_presence(training, 10, seed = 3L)
  expect_gt(sum(drawn[1:10]), 7)
})

test_that("a Maxent fit records that it left effort out", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    metrics <- atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                               fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                               buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 0,
                               tune = FALSE, guilds = stats::setNames(character(), character()))$metrics
    expect_false(metrics$uses_effort)
    expect_false("effort" %in% unlist(metrics$predictors))
  })
})

# --- Robust to a fit that does not converge -----------------------------------

test_that("a short path that does not converge falls back to maxnet's own 200 steps", {
  skip_if_not_installed("maxnet")
  training <- simulated_training(n_background = 600, n_presence = 50)
  calls <- integer()
  real <- atlas_glmnet_path
  testthat::local_mocked_bindings(atlas_glmnet_path = function(mm, p, reg, lambda, weights) {
    calls <<- c(calls, length(lambda))
    model <- real(mm, p, reg, lambda, weights)
    # The first, short path stops short of its last penalty, as glmnet does
    # when a step does not converge.
    if (length(calls) == 1L) model$lambda <- model$lambda[-length(model$lambda)]
    model
  })
  model <- atlas_fit_maxnet(training, classes = "lq")
  expect_equal(calls, c(ATLAS_MAXNET_PATH_STEPS, 200L))
  expect_equal(length(model$lambda), 200L)
  expect_true(all(is.finite(atlas_suitability(model, training[, c("v1", "v2")]))))
})

test_that("a null model whose fit fails is replaced, so the test keeps all its nulls", {
  set.seed(8)
  n <- 300
  table <- data.frame(presence = 0L, cell = seq_len(n),
                      x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
                      v1 = stats::runif(n), v2 = stats::runif(n))
  table$presence[sample.int(n, 40, prob = table$v1^6)] <- 1L
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                               presence = table$presence)
  fits <- 0L
  algo <- list(
    id = "stub",
    default = function(training) list(),
    fit = function(train, params, seed = 1L, tuning = FALSE) {
      fits <<- fits + 1L
      # The second null (fits 9-12, after the taxon's 4 and the first null's 4)
      # cannot be fitted.
      if (fits > 8L && fits <= 12L) stop("glmnet failed to complete regularization path")
      stats::glm(presence ~ v1, data = train, family = stats::binomial())
    },
    score = function(model, newdata) as.numeric(stats::predict(model, newdata, type = "response"))
  )
  null <- atlas_null_test(table, folds, algo, reps = 19)
  expect_equal(null$reps, 19L)
  # A strong taxon that beats every null reaches p = 0.05, not 0.053.
  expect_equal(null$auc_p, 0.05)
})

# --- Fits of the same sites share their features ---------------------------------

# A taxon with enough detections for hinges, on a landscape with folds.
shared_features_table <- function(n = 600, presences = 60, seed = 8) {
  set.seed(seed)
  table <- data.frame(presence = 0L, cell = seq_len(n),
                      x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
                      v1 = stats::runif(n, -3, 3), v2 = stats::runif(n), v3 = stats::runif(n),
                      effort = stats::runif(n, 0, 3))
  table$presence[sample.int(n, presences, prob = exp(-((table$v1 - 1)^2) / 0.5))] <- 1L
  table
}

shared_features_folds <- function(table) {
  atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250, presence = table$presence)
}

# Maxent exactly as production fits it, but with no way to share features.
maxnet_unshared <- function() {
  algo <- atlas_algorithm("maxnet")
  algo$fit <- function(train, params, seed = 1L, tuning = FALSE) {
    atlas_fit_maxnet(train, classes = params$classes, regmult = params$regmult)
  }
  algo
}

test_that("Maxent's regularization is maxnet's own, number for number", {
  skip_if_not_installed("maxnet")
  table <- shared_features_table()
  # A predictor the detections all share, so its penalty is the floor set by
  # its range over every site.
  table$v4 <- ifelse(table$presence == 1L, 0.5, stats::runif(nrow(table)))
  for (classes in c("l", "lq", "lqh", "lqph")) {
    data <- table[, c("v1", "v2", "v3", "v4")]
    f <- maxnet::maxnet.formula(table$presence, data, classes = classes)
    mm <- stats::model.matrix(f, data)
    expect_identical(atlas_maxnet_regularization(table$presence, mm),
                     maxnet::maxnet.default.regularization(table$presence, mm))
  }
})

test_that("a shared feature matrix is the one model.matrix builds, names and all", {
  skip_if_not_installed("maxnet")
  table <- shared_features_table()
  predictors <- table[table$cell > 100, c("v1", "v2", "v3")]
  presence <- table$presence[table$cell > 100]
  data <- rbind(predictors, predictors[presence == 1L, , drop = FALSE])
  p <- c(presence, rep(0L, sum(presence == 1L)))
  f <- maxnet::maxnet.formula(p, data, classes = "lqh")
  shared <- atlas_cached_features(atlas_feature_cache(), f, predictors, data,
                                  rows = c(seq_len(nrow(predictors)), which(presence == 1L)))
  built <- stats::model.matrix(f, data)
  expect_identical(shared$matrix, built)
  expect_identical(shared$lower, apply(built, 2, min))
  expect_identical(shared$upper, apply(built, 2, max))
})

test_that("a null test gives exactly the same answer whether or not its fits share features", {
  skip_if_not_installed("maxnet")
  table <- shared_features_table()
  folds <- shared_features_folds(table)
  expect_equal(atlas_null_params(atlas_algorithm("maxnet"), table)$classes, "lqh")
  shared <- atlas_null_test(table, folds, atlas_algorithm("maxnet"), reps = 3)
  alone <- atlas_null_test(table, folds, maxnet_unshared(), reps = 3)
  expect_equal(shared$reps, 3L)
  expect_identical(shared, alone)
  # Tuning shares them too, and chooses the same settings on the same scores.
  expect_identical(atlas_tune(table, folds, atlas_algorithm("maxnet")),
                   atlas_tune(table, folds, maxnet_unshared()))
})

test_that("fits share features only when they fit the same sites, predictors and classes", {
  skip_if_not_installed("maxnet")
  table <- shared_features_table()
  folds <- shared_features_folds(table)
  store <- atlas_feature_cache()
  check <- function(train, classes = "lqh", built) {
    expect_identical(atlas_fit_maxnet(train, classes = classes, features = store),
                     atlas_fit_maxnet(train, classes = classes))
    expect_equal(store$built, built)
  }
  first <- table[folds != 1L, ]
  check(first, built = 1L)
  # The same sites with other detections: the same matrix.
  relabelled <- first
  relabelled$presence <- atlas_null_presence(first, sum(first$presence), seed = 3)
  check(relabelled, built = 1L)
  # Other sites, as many of them as before: a matrix of their own.
  other <- table[folds != 2L, ]
  other <- other[seq_len(min(nrow(other), nrow(first))), ]
  swapped <- first
  swapped[, c("v1", "v2", "v3")] <- table[rev(seq_len(nrow(first))), c("v1", "v2", "v3")]
  check(swapped, built = 2L)
  check(other, built = 3L)
  # Fewer predictors, or other feature classes: each their own.
  check(first[, setdiff(names(first), "v3")], built = 4L)
  check(first, classes = "lq", built = 5L)
  # And every one of them is still there to share.
  check(relabelled, built = 5L)
  check(swapped, built = 5L)
})

test_that("a null test builds each fold's features once, for the taxon and all its nulls", {
  skip_if_not_installed("maxnet")
  table <- shared_features_table()
  folds <- shared_features_folds(table)
  built <- 0L
  real <- atlas_model_matrix
  testthat::local_mocked_bindings(atlas_model_matrix = function(f, data) {
    built <<- built + 1L
    real(f, data)
  })
  null <- atlas_null_test(table, folds, atlas_algorithm("maxnet"), reps = 3)
  expect_equal(null$reps, 3L)
  expect_equal(built, length(unique(folds)))
})
