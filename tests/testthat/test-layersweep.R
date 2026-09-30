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

# In the synthetic landscape v1 carries the signal and v2 is noise; v3 is a
# second noise layer, because maxnet cannot fit a single predictor. Treat the
# noise as the baseline and the signal as a new layer: adding it must help.
signal_setup <- function() {
  world <- synthetic_landscape()
  set.seed(11)
  v3 <- world$stack[[2]]
  terra::values(v3) <- stats::runif(terra::ncell(v3))
  names(v3) <- "v3"
  world$stack <- c(world$stack, v3)
  bands <- list(noise = c("v2", "v3"), signal = "v1")
  arms <- atlas_layer_sweep_arms(list(signal = "signal"), base = "noise")
  list(world = world, bands = bands, arms = arms)
}

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
      n_background = 500, buffer_km = 300, quiet = TRUE
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
