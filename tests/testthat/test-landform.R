# Landform: wetness, northness and heat load, derived from elevation.

test_that("northness is positive facing north, negative facing south, zero on the flat", {
  expect_gt(atlas_northness(30, 0), 0.49)
  expect_lt(atlas_northness(30, 180), -0.49)
  expect_equal(atlas_northness(0, 0), 0)
  expect_equal(atlas_northness(0, 180), 0)
  # East and west faces are neither.
  expect_equal(atlas_northness(30, 90), 0, tolerance = 1e-12)
})

test_that("a south-west slope carries more heat than a north-east one", {
  expect_gt(atlas_heat_load(45, 30, 225), atlas_heat_load(45, 30, 45))
  # The index folds aspect about south-west: south-east and north-west mirror.
  expect_equal(atlas_heat_load(45, 30, 135), atlas_heat_load(45, 30, 315))
})

test_that("on the flat, aspect makes no difference to heat load", {
  expect_equal(atlas_heat_load(45, 0, 0), atlas_heat_load(45, 0, 225))
})

test_that("wetness rises with the ground draining in and falls with slope", {
  expect_gt(atlas_wetness_index(100, 1000, 5), atlas_wetness_index(1, 1000, 5))
  expect_gt(atlas_wetness_index(10, 1000, 2), atlas_wetness_index(10, 1000, 20))
})

test_that("a flat cell gets a finite wetness, not infinity", {
  expect_true(is.finite(atlas_wetness_index(10, 1000, 0)))
})

# A valley running east-west: ground falls towards the middle row, so the
# floor gathers water, the north side faces south and the south side faces
# north.
valley <- function() {
  r <- terra::rast(nrows = 41, ncols = 41, xmin = 0, xmax = 41000,
                   ymin = 0, ymax = 41000, crs = ATLAS_CRS)
  y <- terra::init(r, "y")
  terra::values(r) <- 100 + abs(terra::values(y, mat = FALSE) - 20500) / 20
  names(r) <- "elevation"
  r
}

test_that("the valley floor is wetter than the ridges", {
  skip_if_not_installed("terra")
  out <- atlas_landform_from_elevation(valley())
  twi <- terra::as.matrix(out[["twi"]], wide = TRUE)
  expect_gt(stats::median(twi[21, 5:37]), stats::median(twi[3, 5:37]))
})

test_that("the valley side facing north reads as north-facing, and cooler", {
  skip_if_not_installed("terra")
  out <- atlas_landform_from_elevation(valley())
  north <- terra::as.matrix(out[["northness"]], wide = TRUE)
  heat <- terra::as.matrix(out[["heat_load"]], wide = TRUE)
  # Rows count from the top (north). The south side of the valley (row 30)
  # slopes down towards the floor to its north: it faces north.
  expect_gt(stats::median(north[30, 5:37]), 0)
  expect_lt(stats::median(north[10, 5:37]), 0)
  expect_lt(stats::median(heat[30, 5:37]), stats::median(heat[10, 5:37]))
})

test_that("sea stays sea: cells without elevation get no landform", {
  skip_if_not_installed("terra")
  r <- valley()
  r[1:41] <- NA
  out <- atlas_landform_from_elevation(r)
  expect_true(all(is.na(terra::values(out)[1:41, ])))
  # The row beside the sea keeps its values: sea counts as sea level, not as
  # nothing. (The raster's outer edge has no neighbours at all; on the real
  # grid that edge is open ocean.)
  second_row <- terra::as.matrix(out[["northness"]], wide = TRUE)[2, 2:40]
  expect_false(anyNA(second_row))
})

test_that("latitude is read from where a cell really is", {
  skip_if_not_installed("terra")
  # The grid's origin is latitude 40, longitude -96.
  r <- terra::rast(nrows = 3, ncols = 3, xmin = -15000, xmax = 15000,
                   ymin = -15000, ymax = 15000, crs = ATLAS_CRS)
  lat <- atlas_latitude_raster(r)
  expect_equal(terra::values(lat)[5], 40, tolerance = 0.02)
})
