correlated_frame <- function(n = 200, seed = 4) {
  set.seed(seed)
  base <- stats::rnorm(n)
  data.frame(
    bio1 = base,                      # high priority
    bio10 = base + stats::rnorm(n, sd = 0.01), # a near-copy, lower priority
    bio12 = stats::rnorm(n),          # independent, highest priority
    soil_phh2o = stats::rnorm(n)      # independent
  )
}

test_that("one of a correlated pair is kept, and it is the higher priority one", {
  kept <- atlas_prune_correlated(correlated_frame())
  expect_true("bio1" %in% kept)
  expect_false("bio10" %in% kept)
})

test_that("independent predictors all survive", {
  kept <- atlas_prune_correlated(correlated_frame())
  expect_true(all(c("bio12", "soil_phh2o") %in% kept))
  expect_equal(length(kept), 3L)
})

test_that("priority decides, not the order the columns happen to be in", {
  frame <- correlated_frame()
  shuffled <- frame[, c("bio10", "soil_phh2o", "bio1", "bio12")]
  expect_setequal(atlas_prune_correlated(frame), atlas_prune_correlated(shuffled))
})

test_that("a looser threshold keeps more predictors", {
  frame <- correlated_frame()
  expect_gte(
    length(atlas_prune_correlated(frame, threshold = 0.99)),
    length(atlas_prune_correlated(frame, threshold = 0.5))
  )
})

test_that("negative correlation counts as correlation", {
  set.seed(7)
  base <- stats::rnorm(200)
  frame <- data.frame(bio1 = base, bio10 = -base + stats::rnorm(200, sd = 0.01))
  kept <- atlas_prune_correlated(frame)
  expect_equal(kept, "bio1")
})

test_that("a predictor that never varies is dropped", {
  frame <- correlated_frame()
  frame$soil_cec <- 5
  expect_false("soil_cec" %in% atlas_prune_correlated(frame))
  expect_false("soil_cec" %in% atlas_drop_constant(frame))
})

test_that("an all-missing predictor is dropped rather than breaking the maths", {
  frame <- correlated_frame()
  frame$soil_clay <- NA_real_
  expect_false("soil_clay" %in% atlas_prune_correlated(frame))
})

test_that("a predictor outside the priority list is still considered, last", {
  frame <- correlated_frame()
  frame$mystery <- stats::rnorm(nrow(frame))
  expect_true("mystery" %in% atlas_prune_correlated(frame))
})

test_that("correlations are read off the background, not the presences", {
  # Presences are few and unrepresentative; a pair correlated only among them
  # must not decide the choice.
  set.seed(11)
  background <- correlated_frame(n = 300)
  presence <- data.frame(
    bio1 = 1:5, bio10 = 1:5, bio12 = 1:5, soil_phh2o = 1:5 # perfectly aligned
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:5, x = 0, y = 0, presence),
    data.frame(
      presence = 0L, cell = seq_len(nrow(background)) + 5L, x = 0, y = 0, background
    )
  )
  kept <- atlas_choose_predictors(training)
  expect_true(all(c("bio12", "soil_phh2o") %in% kept))
})

test_that("with no background at all, every predictor is offered", {
  training <- data.frame(
    presence = 1L, cell = 1:5, x = 0, y = 0,
    bio1 = stats::rnorm(5), bio12 = stats::rnorm(5)
  )
  expect_setequal(atlas_choose_predictors(training), c("bio1", "bio12"))
})

test_that("a sparse taxon gets a short predictor list", {
  set.seed(3)
  background <- data.frame(
    bio12 = stats::rnorm(400), bio1 = stats::rnorm(400),
    cover_trees = stats::rnorm(400), soil_phh2o = stats::rnorm(400),
    elevation = stats::rnorm(400), slope = stats::rnorm(400),
    roughness = stats::rnorm(400), bio15 = stats::rnorm(400)
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:20, x = 0, y = 0, background[1:20, ]),
    data.frame(presence = 0L, cell = 21:420, x = 0, y = 0, background)
  )
  # 20 presences, one predictor per four records: five survive.
  expect_equal(length(atlas_choose_predictors(training)), 5L)
})

test_that("the cap keeps the ecologically primary variables", {
  set.seed(3)
  background <- data.frame(
    roughness = stats::rnorm(400), slope = stats::rnorm(400),
    bio12 = stats::rnorm(400), bio1 = stats::rnorm(400)
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:8, x = 0, y = 0, background[1:8, ]),
    data.frame(presence = 0L, cell = 9:408, x = 0, y = 0, background)
  )
  kept <- atlas_choose_predictors(training, minimum = 2)
  expect_equal(kept, c("bio12", "bio1"))
})

test_that("a well-recorded taxon is not capped", {
  set.seed(3)
  background <- data.frame(
    bio12 = stats::rnorm(600), bio1 = stats::rnorm(600),
    cover_trees = stats::rnorm(600), soil_phh2o = stats::rnorm(600)
  )
  training <- rbind(
    data.frame(presence = 1L, cell = 1:400, x = 0, y = 0, background[1:400, ]),
    data.frame(presence = 0L, cell = 401:1000, x = 0, y = 0, background)
  )
  expect_equal(length(atlas_choose_predictors(training)), 4L)
})

test_that("even a tiny taxon keeps a workable minimum", {
  set.seed(3)
  background <- as.data.frame(matrix(stats::rnorm(400 * 8), ncol = 8))
  names(background) <- c("bio12", "bio1", "cover_trees", "soil_phh2o",
                         "elevation", "slope", "roughness", "bio15")
  training <- rbind(
    data.frame(presence = 1L, cell = 1:4, x = 0, y = 0, background[1:4, ]),
    data.frame(presence = 0L, cell = 5:404, x = 0, y = 0, background)
  )
  expect_equal(length(atlas_choose_predictors(training)), 5L)
})
