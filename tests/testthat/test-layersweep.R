# The layer sweep: does a new layer make the models better?

test_that("every arm adds one group to the baseline, and 'all' adds every group", {
  arms <- atlas_layer_sweep_arms(list(a = "la", b = c("lb1", "lb2")), base = "base1")
  names <- vapply(arms, function(x) x$arm, character(1))
  expect_equal(names, c("base", "+a", "+b", "all", "rf:base", "rf:all"))
  layers <- function(n) arms[[which(names == n)]]$layers
  expect_equal(layers("base"), "base1")
  expect_equal(layers("+b"), c("base1", "lb1", "lb2"))
  expect_equal(layers("all"), c("base1", "la", "lb1", "lb2"))
  expect_equal(arms[[which(names == "rf:all")]]$algorithm, "rf")
})

test_that("a group that is not built is left out, and 'all' means all that are built", {
  arms <- atlas_layer_sweep_arms(list(a = "la", b = "lb"), built = c("base1", "la"),
                                 base = "base1")
  names <- vapply(arms, function(x) x$arm, character(1))
  expect_false("+b" %in% names)
  expect_equal(arms[[which(names == "all")]]$layers, c("base1", "la"))
})

test_that("an arm needing a layer that is not built is skipped, and named", {
  arms <- list(list(arm = "base", layers = "x"), list(arm = "+y", layers = c("x", "y")))
  kept <- atlas_runnable_arms(arms, built = "x")
  expect_equal(length(kept), 1L)
  expect_equal(attr(kept, "skipped"), "+y")
})

test_that("the sweep's baseline is what production fits on", {
  expect_equal(ATLAS_BASE_LAYERS, ATLAS_PRODUCTION_LAYERS)
  expect_true(all(ATLAS_BASE_LAYERS %in% names(atlas_layer_registry())))
})

test_that("every candidate group names a registered layer", {
  expect_true(all(unlist(ATLAS_NEW_LAYER_GROUPS) %in% names(atlas_layer_registry())))
})

test_that("a layer that carries the signal beats a baseline that does not", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
  s <- signal_setup()
  row <- atlas_layer_sweep_taxon(
    "Eastern fungus", fingerprint = "f00dfeed", points = s$world$points,
    stack = s$world$stack, arms = s$arms, bands = s$bands,
    n_background = 500, buffer_km = 300
  )
  expect_equal(row$status, "scored")
  auc <- vapply(row$arms, function(a) a$auc, numeric(1))
  names(auc) <- vapply(row$arms, function(a) a$arm, character(1))
  expect_gt(auc[["+signal"]], auc[["base"]] + 0.1)
  expect_gt(auc[["rf:all"]], auc[["rf:base"]] + 0.1)
})

test_that("an arm only ever sees the predictors of its own layers", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
  s <- signal_setup()
  row <- atlas_layer_sweep_taxon(
    "Eastern fungus", fingerprint = "f00dfeed", points = s$world$points,
    stack = s$world$stack, arms = s$arms, bands = s$bands,
    n_background = 500, buffer_km = 300
  )
  kept <- lapply(row$arms, function(a) unlist(a$kept))
  names(kept) <- vapply(row$arms, function(a) a$arm, character(1))
  expect_setequal(kept[["base"]], c("v2", "v3"))
  expect_setequal(kept[["rf:base"]], c("v2", "v3"))
  expect_true("v1" %in% kept[["+signal"]])
  expect_setequal(kept[["rf:all"]], c("v1", "v2", "v3"))
})

test_that("coverage counts the records a new layer cannot describe", {
  skip_if_not_installed("terra")
  s <- signal_setup()
  stack <- s$world$stack
  # Blank the signal layer over the western half, where most records are.
  west <- terra::xyFromCell(stack, seq_len(terra::ncell(stack)))[, 1] < 5e5
  values <- terra::values(stack)
  values[west, "v1"] <- NA
  terra::values(stack) <- values
  coverage <- atlas_layer_coverage(s$world$points, stack, s$bands, base = "noise")
  expected <- sum(s$world$points$x < 5e5)
  expect_equal(coverage$signal$records_missing, expected)
  expect_equal(coverage$signal$share_missing,
               round(expected / nrow(s$world$points), 4))
})

test_that("a layer sweep writes its results and never touches the fitted models", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
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
      bands = s$bands, base = "noise",
      groups = list(signal = "signal", unbuilt = "nowhere"),
      n_background = 500, buffer_km = 300, quiet = TRUE, method = FALSE
    )
    expect_true(file.exists(result$path))
    expect_match(result$path, "layer-sweeps")
    expect_false(dir.exists(atlas_path("models")))
    saved <- jsonlite::fromJSON(result$path, simplifyVector = FALSE)
    expect_equal(saved$baseline, "base")
    expect_true("+unbuilt" %in% unlist(saved$settings$skipped))
    arms <- unique(vapply(saved$summary, function(r) r$arm, character(1)))
    expect_setequal(arms, c("base", "+signal", "all", "rf:base", "rf:all"))
  })
})

# --- The design's own arms ---------------------------------------------------

test_that("the method arms fit the old designs on production's layers, for both learners", {
  arms <- atlas_layer_sweep_arms(list(a = "la"), base = "base1", method = TRUE)
  names <- vapply(arms, function(x) x$arm, character(1))
  expect_true(all(c("base:no-effort", "base:per-record",
                    "rf:base:no-effort", "rf:base:per-record") %in% names))
  old <- arms[[which(names == "rf:base:per-record")]]
  expect_equal(old$layers, "base1")
  expect_equal(old$algorithm, "rf")
  expect_equal(old$design, "per-record")
  plain <- vapply(atlas_layer_sweep_arms(list(a = "la"), base = "base1"),
                  function(x) x$arm, character(1))
  expect_false(any(grepl("per-record|no-effort", plain)))
})

test_that("the host trees get an arm in the order of an unknown guild", {
  arms <- atlas_layer_sweep_arms(list(a = "la"), base = c("base1", "hosts"))
  names <- vapply(arms, function(x) x$arm, character(1))
  flat <- arms[[which(names == "base:flat")]]
  expect_false(flat$guild_order)
  expect_equal(flat$layers, c("base1", "hosts"))
  none <- vapply(atlas_layer_sweep_arms(list(a = "la"), base = "base1"),
                 function(x) x$arm, character(1))
  expect_false("base:flat" %in% none)
})

design_table <- function() {
  data.frame(presence = c(1L, 1L, 0L, 0L, 0L), cell = 1:5, x = 0, y = 0,
             v1 = c(0.1, 0.2, 0.3, 0.4, 0.5),
             effort = log(c(8, 1, 1, 4, 1)))
}

test_that("production's design leaves the survey sites as they are", {
  expect_equal(atlas_design_rows(design_table(), "sites"), design_table())
})

test_that("without effort the sites are the same and the effort column is gone", {
  rows <- atlas_design_rows(design_table(), "no-effort")
  expect_false("effort" %in% names(rows))
  expect_equal(rows$cell, 1:5)
})

test_that("the old design repeats a non-detection site once per record, and detections once", {
  rows <- atlas_design_rows(design_table(), "per-record")
  expect_false("effort" %in% names(rows))
  expect_equal(rows$cell[rows$presence == 1L], 1:2)
  # One record, four records, and a site that must still count once.
  expect_equal(as.integer(table(rows$cell[rows$presence == 0L])), c(1L, 4L, 1L))
  expect_equal(rows$v1[rows$cell == 4L], rep(0.4, 4))
})

test_that("the old design draws no more than its background size, the same way each time", {
  table <- design_table()
  table$effort[4] <- log(5000)
  rows <- atlas_design_rows(table, "per-record", n_background = 100, seed = 3L)
  expect_equal(sum(rows$presence == 0L), 100L)
  expect_equal(sum(rows$presence == 1L), 2L)
  expect_equal(rows, atlas_design_rows(table, "per-record", n_background = 100, seed = 3L))
  expect_error(atlas_design_rows(table, "something else"))
})

test_that("every design is scored on the same held-out sites, each counted once", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
  s <- signal_setup()
  arms <- atlas_layer_sweep_arms(list(signal = "signal"), base = c("noise", "signal"),
                                 method = TRUE)
  arms <- Filter(function(a) a$algorithm == "maxnet" && !grepl("^[+]|^all$", a$arm), arms)
  seen <- list()
  testthat::local_mocked_bindings(atlas_cross_validate = function(training, folds, fit, score,
                                                                  effort_at) {
    seen[[length(seen) + 1L]] <<- list(cells = training$cell, folds = folds,
                                       fitted = nrow(fit(training)$rows))
    out <- data.frame(fold = 1L, presences = 1L, auc = 0.5, boyce = 0)
    attr(out, "held") <- data.frame(fold = 1L, presence = c(1L, 1L, 1L, 0L, 0L, 0L),
                                    score = c(0.9, 0.8, 0.7, 0.3, 0.2, 0.1))
    out
  }, atlas_algorithm = function(name = "maxnet") {
    list(id = "stub", prune = FALSE, default = function(training) list(),
         fit = function(train, params, seed = 1L, tuning = FALSE) list(rows = train),
         score = function(model, newdata) rep(0, nrow(newdata)))
  })
  row <- atlas_layer_sweep_taxon(
    "Eastern fungus", fingerprint = "f00dfeed", points = s$world$points,
    stack = s$world$stack, arms = arms, bands = s$bands,
    n_background = 500, buffer_km = 300
  )
  designs <- vapply(row$arms, function(a) a$design, character(1))
  expect_equal(designs, c("sites", "no-effort", "per-record"))
  # One table, one set of folds, whatever the design.
  expect_equal(seen[[2]]$cells, seen[[1]]$cells)
  expect_equal(seen[[3]]$folds, seen[[1]]$folds)
  # Only the rows a model is fitted on differ: the old design repeats sites.
  expect_equal(seen[[2]]$fitted, seen[[1]]$fitted)
  expect_gt(seen[[3]]$fitted, seen[[1]]$fitted)
})

test_that("an arm that cannot be fitted is recorded, and the taxon keeps its other arms", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
  s <- signal_setup()
  real <- atlas_algorithm
  testthat::local_mocked_bindings(atlas_algorithm = function(name = "maxnet") {
    algo <- real(name)
    if (identical(name, "rf")) {
      algo$fit <- function(...) stop("glmnet failed to complete regularization path")
    }
    algo
  })
  row <- atlas_layer_sweep_taxon(
    "Eastern fungus", fingerprint = "f00dfeed", points = s$world$points,
    stack = s$world$stack, arms = s$arms, bands = s$bands,
    n_background = 500, buffer_km = 300
  )
  expect_equal(row$status, "scored")
  by_arm <- stats::setNames(row$arms, vapply(row$arms, function(a) a$arm, character(1)))
  expect_true(is.finite(by_arm[["base"]]$auc))
  expect_true(is.na(by_arm[["rf:base"]]$auc))
  expect_match(by_arm[["rf:base"]]$error, "regularization path")
  # A failed arm is left out of the comparison, not counted as a zero.
  summary <- atlas_sweep_summary(list(row), baseline = "base")
  expect_true(is.na(summary$auc[summary$arm == "rf:base" & summary$band == "all"]))
})

test_that("a swap replaces production layers with candidates, for Maxent and the forest", {
  swaps <- list(newclimate = list(drop = "oldclimate", add = c("c1", "c2")))
  arms <- atlas_layer_sweep_arms(list(), base = c("oldclimate", "soil"), swaps = swaps,
                                 built = c("oldclimate", "soil", "c1", "c2"))
  names <- vapply(arms, function(a) a$arm, character(1))
  expect_true(all(c("swap:newclimate", "rf:swap:newclimate") %in% names))
  swap <- arms[[which(names == "swap:newclimate")]]
  expect_setequal(swap$layers, c("soil", "c1", "c2"))
  expect_equal(swap$algorithm, "maxnet")
  expect_equal(arms[[which(names == "rf:swap:newclimate")]]$algorithm, "rf")
  # Not offered until every layer it brings in is built.
  partial <- atlas_layer_sweep_arms(list(), base = c("oldclimate", "soil"), swaps = swaps,
                                    built = c("oldclimate", "soil", "c1"))
  expect_false(any(grepl("swap", vapply(partial, function(a) a$arm, character(1)))))
  # The production sweep offers the 1991-2020 climate in place of WorldClim's.
  expect_equal(ATLAS_SWAP_LAYER_GROUPS$climate1991$drop, "bioclim")
  expect_setequal(ATLAS_SWAP_LAYER_GROUPS$climate1991$add, c("climatena", "waterbalance"))
})
