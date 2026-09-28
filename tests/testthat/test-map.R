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

test_that("nothing fitted means an empty overview, not an error", {
  with_data_dir({
    expect_equal(length(atlas_model_overview("draft")), 0L)
  })
})

test_that("the overview reads what fitting wrote, newest first", {
  with_data_dir({
    dir.create(atlas_path("models", "draft"), recursive = TRUE, showWarnings = FALSE)
    atlas_write_json(
      list(taxon = "Older species", built_at = "2026-01-01T00:00:00Z"),
      atlas_model_path("Older species", "draft", ".json")
    )
    atlas_write_json(
      list(taxon = "Newer species", built_at = "2026-06-01T00:00:00Z"),
      atlas_model_path("Newer species", "draft", ".json")
    )
    overview <- atlas_model_overview("draft")
    expect_equal(length(overview), 2L)
    expect_equal(overview[[1]]$taxon, "Newer species")
  })
})
