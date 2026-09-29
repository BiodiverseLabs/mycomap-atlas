test_that("the palette runs from the pale end to the dark end", {
  colours <- atlas_suitability_colours(c(0, 1))
  pale <- grDevices::col2rgb(ATLAS_MAP_RAMP[1])[, 1]
  dark <- grDevices::col2rgb(ATLAS_MAP_RAMP[length(ATLAS_MAP_RAMP)])[, 1]
  expect_equal(unname(colours[1, 1:3]), unname(as.integer(pale)))
  expect_equal(unname(colours[2, 1:3]), unname(as.integer(dark)))
})

test_that("low suitability is drawn faint, high suitability solid", {
  colours <- atlas_suitability_colours(c(0, 0.5, 1))
  expect_true(all(diff(colours[, "alpha"]) > 0))
  expect_lt(colours[1, "alpha"], 128)
  expect_gt(colours[3, "alpha"], 200)
})

test_that("cells the model could not reach are fully transparent", {
  colours <- atlas_suitability_colours(c(NA, 0.5, NaN))
  expect_equal(unname(colours[1, "alpha"]), 0)
  expect_equal(unname(colours[3, "alpha"]), 0)
  expect_false(anyNA(colours))
})

test_that("values outside 0 and 1 are clamped rather than wrapped", {
  colours <- atlas_suitability_colours(c(-2, 3))
  expect_equal(colours[1, ], atlas_suitability_colours(0)[1, ])
  expect_equal(colours[2, ], atlas_suitability_colours(1)[1, ])
})

test_that("bounds come back as a latitude/longitude rectangle", {
  skip_if_not_installed("terra")
  mercator <- terra::rast(
    xmin = -13000000, xmax = -8000000, ymin = 3000000, ymax = 6000000,
    resolution = 100000, crs = "EPSG:3857"
  )
  bounds <- atlas_map_bounds(mercator)
  expect_lt(bounds$south, bounds$north)
  expect_lt(bounds$west, bounds$east)
  expect_gt(bounds$west, -180)
  expect_lt(bounds$east, 0)
  expect_gt(bounds$north, 20)
  expect_lt(bounds$north, 60)
})

test_that("a suitability raster becomes a real PNG within the pixel cap", {
  skip_if_not_installed("terra")
  suitability <- terra::rast(
    xmin = -2000000, xmax = 0, ymin = 0, ymax = 2000000,
    resolution = 5000, crs = ATLAS_CRS
  )
  terra::values(suitability) <- seq(0, 1, length.out = terra::ncell(suitability))

  path <- file.path(tempdir(), "suitability-test.png")
  on.exit(unlink(path), add = TRUE)
  drawn <- atlas_write_map_png(suitability, path, max_pixels = 200)

  expect_true(file.exists(path))
  expect_equal(as.integer(readBin(path, "raw", 4)), c(137L, 80L, 78L, 71L))
  expect_lte(max(drawn$width, drawn$height), 200)
  expect_lt(drawn$bounds$south, drawn$bounds$north)
})

# Metrics shaped like the ones a fit writes, with the heavy parts included so
# a test can check they stay out of the list.
write_metrics <- function(name, built_at, auc = 0.6, map = TRUE) {
  dir.create(atlas_path("models", "draft"), recursive = TRUE, showWarnings = FALSE)
  atlas_write_json(
    list(taxon = name, built_at = built_at, presences = 40, auc_mean = auc,
         boyce_mean = 0.3, predictors = list("bio12", "bio1"),
         folds = list(list(fold = 1, auc = auc)), settings = list(grid = "draft"),
         map = if (map) "x.png" else NULL),
    atlas_model_path(name, "draft", ".json")
  )
}

test_that("nothing fitted means an empty list, not an error", {
  with_data_dir({
    expect_equal(nrow(atlas_model_index("draft")), 0L)
  })
})

test_that("the list reads what fitting wrote, newest first", {
  with_data_dir({
    write_metrics("Older species", "2026-01-01T00:00:00Z")
    write_metrics("Newer species", "2026-06-01T00:00:00Z")
    index <- atlas_model_index("draft")
    expect_equal(index$taxon, c("Newer species", "Older species"))
    expect_equal(index$predictors, c(2L, 2L))
    expect_equal(index$auc_mean, c(0.6, 0.6))
  })
})

test_that("the list carries a summary, not every fold and setting", {
  with_data_dir({
    write_metrics("Some species", "2026-01-01T00:00:00Z")
    index <- atlas_model_index("draft")
    expect_false(any(c("folds", "settings", "bounds") %in% names(index)))
  })
})

test_that("a model without a map says so", {
  with_data_dir({
    write_metrics("Scored only", "2026-01-01T00:00:00Z", map = FALSE)
    write_metrics("Mapped", "2026-01-02T00:00:00Z")
    index <- atlas_model_index("draft")
    expect_equal(index$map[index$taxon == "Scored only"], FALSE)
    expect_equal(index$map[index$taxon == "Mapped"], TRUE)
  })
})

test_that("a second call reads only the files that changed", {
  with_data_dir({
    write_metrics("First species", "2026-01-01T00:00:00Z")
    write_metrics("Second species", "2026-01-01T00:00:00Z")
    cache <- new.env()
    atlas_model_index("draft", cache)
    expect_equal(cache$reads, 2L)

    atlas_model_index("draft", cache)
    expect_equal(cache$reads, 2L)

    Sys.sleep(1.1) # let the timestamp move on file systems with coarse clocks
    write_metrics("Second species", "2026-02-01T00:00:00Z", auc = 0.9)
    index <- atlas_model_index("draft", cache)
    expect_equal(cache$reads, 3L)
    expect_equal(index$auc_mean[index$taxon == "Second species"], 0.9)
  })
})

test_that("a deleted model leaves the list", {
  with_data_dir({
    write_metrics("Staying", "2026-01-01T00:00:00Z")
    write_metrics("Going", "2026-01-01T00:00:00Z")
    cache <- new.env()
    atlas_model_index("draft", cache)
    unlink(atlas_model_path("Going", "draft", ".json"))
    expect_equal(atlas_model_index("draft", cache)$taxon, "Staying")
  })
})

test_that("a half-written file is skipped rather than breaking the list", {
  with_data_dir({
    write_metrics("Whole", "2026-01-01T00:00:00Z")
    writeLines('{"taxon": "Half', atlas_model_path("Half", "draft", ".json"))
    expect_equal(atlas_model_index("draft")$taxon, "Whole")
  })
})

test_that("a map is coloured by rank, so its lowest ground is 0 and its highest 1", {
  expect_equal(atlas_rank_scale(c(0.2, 0.6, 0.4)), c(0, 1, 0.5))
  expect_equal(atlas_rank_scale(c(NA, 0.3, 0.1)), c(NA, 1, 0))
  expect_equal(atlas_rank_scale(0.7), 1)
  expect_true(all(is.na(atlas_rank_scale(c(NA_real_, NaN)))))
})

test_that("two models that order the ground alike are drawn alike, whatever their scales", {
  # Maxent reaches 1; boosted trees rarely pass 0.65. Ranked, the same
  # ordering must give the same picture, or the tree maps look washed out.
  set.seed(4)
  maxent <- stats::runif(500)
  trees <- 0.27 + 0.36 * maxent^2
  expect_equal(
    atlas_suitability_colours(atlas_rank_scale(maxent)),
    atlas_suitability_colours(atlas_rank_scale(trees))
  )
})

test_that("a drawn map records how its colours were scaled", {
  skip_if_not_installed("terra")
  suitability <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 1e5,
                             ymin = 0, ymax = 1e5, crs = ATLAS_CRS)
  terra::values(suitability) <- seq(0.3, 0.6, length.out = 400)
  drawn <- atlas_write_map_png(suitability, file.path(tempdir(), "ranked.png"))
  expect_equal(drawn$scale, "rank")
  expect_match(drawn$drawn_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T")
})
