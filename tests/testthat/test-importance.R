# What each predictor and layer is worth, measured on held-out ground.

importance_world <- function(n = 1200, seed = 4) {
  set.seed(seed)
  table <- data.frame(presence = 0L, cell = seq_len(n),
                      x = stats::runif(n, 0, 1e6), y = stats::runif(n, 0, 1e6),
                      signal = stats::runif(n), twin = 0, noise = stats::runif(n),
                      effort = stats::runif(n))
  table$twin <- table$signal + stats::rnorm(n, sd = 0.02)
  table$presence[sample.int(n, 150, prob = table$signal^4)] <- 1L
  table
}

glm_on <- function(formula) {
  list(
    fit = function(train) stats::glm(formula, data = train, family = stats::binomial()),
    score = function(model, newdata) {
      as.numeric(stats::predict(model, newdata, type = "response"))
    }
  )
}

test_that("a predictor that carries the signal costs AUC when shuffled, and noise costs none", {
  table <- importance_world()
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                               presence = table$presence)
  learner <- glm_on(presence ~ signal + noise)
  scores <- atlas_cross_validate_importance(
    table[, setdiff(names(table), "twin")], folds, fit = learner$fit, score = learner$score
  )
  importance <- attr(scores, "importance")
  fall <- stats::setNames(importance$fall, importance$name)
  expect_gt(fall[["signal"]], 0.1)
  expect_lt(abs(fall[["noise"]]), 0.03)
  # Effort is held at one value when scoring, so it is not measured.
  expect_false("effort" %in% importance$name)
})

test_that("the scores are the ones plain cross-validation gives", {
  table <- importance_world()
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                               presence = table$presence)
  learner <- glm_on(presence ~ signal + noise)
  plain <- atlas_cross_validate(table, folds, fit = learner$fit, score = learner$score)
  measured <- atlas_cross_validate_importance(table, folds, fit = learner$fit,
                                              score = learner$score)
  expect_equal(measured$auc, plain$auc)
  expect_equal(attr(measured, "held"), attr(plain, "held"))
})

test_that("a layer is shuffled whole, so twins cannot cover for one another", {
  table <- importance_world()
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                               presence = table$presence)
  learner <- glm_on(presence ~ I(signal + twin) + noise)
  scores <- atlas_cross_validate_importance(
    table, folds, fit = learner$fit, score = learner$score,
    layers = list(climate = c("signal", "twin"), other = "noise", absent = "nowhere")
  )
  importance <- attr(scores, "importance")
  layer <- importance[importance$kind == "layer", ]
  expect_setequal(layer$name, c("climate", "other"))
  one <- importance$fall[importance$kind == "predictor" & importance$name == "signal"]
  both <- layer$fall[layer$name == "climate"]
  # Shuffling one twin leaves the other carrying half the signal.
  expect_gt(both, one + 0.02)
})

test_that("importance is measured on the held-out sites, not the ones a model learned from", {
  table <- importance_world()
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250,
                               presence = table$presence)
  seen <- list()
  learner <- list(
    fit = function(train) list(cells = train$cell),
    score = function(model, newdata) {
      seen[[length(seen) + 1L]] <<- list(n = nrow(newdata), trained = length(model$cells))
      newdata$signal
    }
  )
  atlas_cross_validate_importance(table[, c("presence", "cell", "x", "y", "signal", "noise")],
                                  folds, fit = learner$fit, score = learner$score)
  # Every scoring, the plain one and the shuffled ones, is of a whole fold's
  # held-out sites: never of the sites the model was given.
  expect_true(all(vapply(seen, function(s) s$n + s$trained, numeric(1)) == nrow(table)))
  expect_setequal(unique(vapply(seen, function(s) s$n, numeric(1))),
                  as.integer(table(folds)))
})

test_that("the summary says how much, how surely, for how many taxa, and by guild", {
  arm <- function(falls) list(arm = "rf:all", importance = lapply(names(falls), function(n) {
    list(kind = "predictor", name = n, fall = falls[[n]])
  }))
  rows <- list(
    list(taxon = "A", status = "scored", guild = "ectomycorrhizal",
         arms = list(arm(c(bio12 = 0.10, host_pinus = 0.06)))),
    list(taxon = "B", status = "scored", guild = "wood_saprotroph",
         arms = list(arm(c(bio12 = 0.06, host_pinus = 0)))),
    list(taxon = "C", status = "scored", guild = "unknown",
         arms = list(arm(c(bio12 = 0.02)), list(arm = "base"))),
    list(taxon = "D", status = "refused")
  )
  summary <- atlas_importance_summary(rows)
  pick <- function(guild, name) summary[summary$guild == guild & summary$name == name, ]
  expect_equal(pick("all", "bio12")$taxa, 3L)
  expect_equal(pick("all", "bio12")$fall, 0.06)
  expect_equal(pick("all", "bio12")$helped, 1)
  expect_equal(pick("all", "host_pinus")$taxa, 2L)
  expect_equal(pick("all", "host_pinus")$helped, 0.5)
  expect_equal(pick("ectomycorrhizal", "host_pinus")$fall, 0.06)
  expect_equal(pick("other", "host_pinus")$fall, 0)
  expect_equal(pick("other", "bio12")$taxa, 2L)
  expect_equal(nrow(atlas_importance_summary(list(list(taxon = "D", status = "refused")))), 0L)
})

test_that("the sweep measures importance for the arms fitted on everything, and writes it", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
  expect_equal(ATLAS_IMPORTANCE_ARMS, c("all", "rf:all"))
  with_data_dir({
    s <- signal_setup()
    occurrences <- data.frame(
      id = as.character(seq_len(nrow(s$world$points))),
      scientific_name = s$world$points$scientific_name,
      latitude = "45", longitude = "-100", observed_on = "2025-01-01",
      stringsAsFactors = FALSE
    )
    result <- atlas_layer_sweep(
      occurrences = occurrences, points = s$world$points, stack = s$world$stack,
      bands = s$bands, base = "noise", groups = list(signal = "signal"),
      n_background = 500, buffer_km = 300, quiet = TRUE, method = FALSE
    )
    expect_true(file.exists(result$importance_path))
    expect_match(basename(result$importance_path), "^importance-")
    forest <- result$importance[result$importance$arm == "rf:all" &
                                  result$importance$guild == "all", ]
    fall <- stats::setNames(forest$fall, paste(forest$kind, forest$name))
    expect_gt(fall[["layer signal"]], fall[["layer noise"]] + 0.05)
    expect_gt(fall[["predictor v1"]], fall[["predictor v2"]] + 0.05)
    measured <- unique(result$importance$arm)
    expect_setequal(measured, c("all", "rf:all"))
  })
})

# --- The breakdown stored with every model ------------------------------------

test_that("every production predictor has a name people can read", {
  production <- c(paste0("bio", 1:19), "elevation", "slope", "roughness",
                  paste0("soil_", c("phh2o", "soc", "clay", "sand", "cec")),
                  paste0("cover_", c("trees", "shrubs", "grassland", "wetland", "water", "built")),
                  ATLAS_HOST_BANDS, "host_known",
                  "forest_needleleaf", "forest_broadleaf", "forest_mixed", "forest_known")
  expect_equal(length(production), 58L)
  missing <- setdiff(production, names(ATLAS_PREDICTOR_LABELS))
  expect_equal(missing, character(0))
  expect_true(all(ATLAS_PRODUCTION_LAYERS %in% names(ATLAS_LAYER_LABELS)))
  expect_equal(atlas_label("bio14"), "Precipitation of the driest month")
  expect_equal(atlas_label("something_new"), "something_new")
})

test_that("a model's breakdown nests each layer's predictors under it, largest first", {
  groups <- atlas_importance_groups(c("bio1", "bio12", "soil_phh2o", "effort"),
                                    c(bio1 = "bioclim", bio12 = "bioclim", soil_phh2o = "soil",
                                      effort = "other"))
  expect_false(any(grepl("effort", names(groups))))
  expect_equal(groups[["layer\rbioclim"]], c("bio1", "bio12"))
  falls <- matrix(c(0.01, 0.03, 0.05, 0.08, 0.02,
                    0.03, 0.05, 0.03, 0.10, 0.04), ncol = 2,
                  dimnames = list(names(groups), NULL))
  table <- atlas_importance_table(falls, c(bio1 = "bioclim", bio12 = "bioclim", soil_phh2o = "soil"))
  expect_equal(vapply(table, function(x) x$name, character(1)), c("bioclim", "soil"))
  climate <- table[[1]]
  expect_equal(climate$label, "Climate")
  expect_equal(climate$fall, 0.09)
  expect_equal(climate$sd, round(stats::sd(c(0.08, 0.10)), 4))
  expect_equal(vapply(climate$predictors, function(x) x$name, character(1)), c("bio12", "bio1"))
  expect_equal(climate$predictors[[1]]$label, "Annual precipitation")
  expect_equal(table[[2]]$predictors[[1]]$name, "soil_phh2o")
  expect_null(atlas_importance_table(NULL, character()))
  # Written as JSON, layers and predictors are arrays, not keyed objects.
  json <- jsonlite::toJSON(table, auto_unbox = TRUE)
  back <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_null(names(back))
  expect_null(names(back[[1]]$predictors))
})

test_that("a fitted model keeps what it owed to each layer, measured on its held-out folds", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
  with_data_dir({
    world <- synthetic_landscape()
    # v1 carries the signal and v2 is noise, each its own layer here.
    dir.create(atlas_layer_dir("draft"), recursive = TRUE, showWarnings = FALSE)
    atlas_write_json(list(list(id = "signal", bands = list("v1")), list(id = "noise", bands = list("v2"))),
                     atlas_manifest_path("draft"))
    fit <- function(algorithm, importance = TRUE) {
      atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                      fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                      buffer_km = 300, predict = FALSE, quiet = TRUE, nulls = 0, tune = FALSE,
                      algorithm = algorithm, importance = importance,
                      guilds = stats::setNames(character(), character()))$metrics
    }
    for (algorithm in c("maxnet", "rf")) {
      metrics <- fit(algorithm)
      layers <- stats::setNames(metrics$importance, vapply(metrics$importance, function(x) x$name, character(1)))
      expect_equal(names(layers)[[1]], "signal", info = algorithm)
      expect_gt(layers$signal$fall, layers$noise$fall + 0.05)
      expect_equal(layers$signal$predictors[[1]]$name, "v1")
      expect_false("effort" %in% unlist(lapply(metrics$importance, function(x) {
        vapply(x$predictors, function(p) p$name, character(1))
      })))
    }
    expect_null(fit("maxnet", importance = FALSE)$importance)
    expect_equal(fit("rf")$layers_unused, list())
  })
})

test_that("each scored fold gives one column of falls", {
  skip_if_not_installed("maxnet")
  set.seed(6)
  n <- 900
  table <- data.frame(presence = 0L, cell = seq_len(n), x = stats::runif(n, 0, 1e6),
                      y = stats::runif(n, 0, 1e6), v1 = stats::runif(n), v2 = stats::runif(n))
  table$presence[sample.int(n, 90, prob = table$v1^3)] <- 1L
  folds <- atlas_spatial_folds(table$x, table$y, k = 4, block_km = 250, presence = table$presence)
  groups <- atlas_importance_groups(c("v1", "v2"), c(v1 = "a", v2 = "b"))
  scores <- atlas_nested_cross_validate(table, folds, atlas_algorithm("maxnet"), block_km = 250,
                                        tune = FALSE, importance = groups)
  falls <- attr(scores, "falls")
  expect_equal(dim(falls), c(length(groups), sum(!is.na(scores$auc))))
  expect_equal(rownames(falls), names(groups))
  expect_null(attr(atlas_nested_cross_validate(table, folds, atlas_algorithm("maxnet"),
                                               block_km = 250, tune = FALSE), "falls"))
})

test_that("a fall is marked clear only when it stands out from the spread between folds", {
  groups <- atlas_importance_groups(c("a", "b", "c"), c(a = "L", b = "L", c = "L"))
  falls <- rbind(
    "predictor\ra" = c(0.05, 0.06, 0.05, 0.04),   # steady and large
    "predictor\rb" = c(0.04, -0.03, 0.05, -0.04), # large swings around nothing
    "predictor\rc" = c(0.001, 0.001, 0.001, 0.001), # steady but negligible
    "layer\rL" = c(0.08, 0.07, 0.09, 0.08)
  )
  table <- atlas_importance_table(falls, c(a = "L", b = "L", c = "L"))
  clear <- stats::setNames(vapply(table[[1]]$predictors, function(p) p$clear, logical(1)),
                           vapply(table[[1]]$predictors, function(p) p$name, character(1)))
  expect_true(clear[["a"]])
  expect_false(clear[["b"]])
  expect_false(clear[["c"]])
  expect_true(table[[1]]$clear)
  expect_equal(ATLAS_IMPORTANCE_REPEATS, 5L)
})
