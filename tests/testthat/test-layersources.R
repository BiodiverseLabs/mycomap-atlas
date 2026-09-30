# Readers for the layers that are not one download away: forest type, water balance.
# Each is checked on small synthetic rasters, never the real downloads.

test_that("the forest-type VRT reads each class as 1 in its own group only", {
  skip_if_not_installed("terra")
  dir <- tempfile("nalcms-")
  dir.create(dir)
  classes <- terra::rast(nrows = 4, ncols = 5, xmin = 0, xmax = 150, ymin = 0, ymax = 120,
                         crs = ATLAS_CRS)
  terra::values(classes) <- 0:19
  tif <- file.path(dir, "classes.tif")
  terra::writeRaster(classes, tif, datatype = "INT1U", NAflag = 255)

  groups <- terra::rast(atlas_nalcms_vrt(tif, file.path(dir, "groups.vrt")))
  values <- terra::values(groups)
  codes <- terra::values(classes, mat = FALSE)
  expect_equal(names(groups), names(ATLAS_NALCMS_GROUPS))
  for (group in names(ATLAS_NALCMS_GROUPS)) {
    inside <- codes %in% ATLAS_NALCMS_GROUPS[[group]]
    expect_true(all(values[inside, group] == 1), info = group)
    expect_true(all(values[!inside & codes != 0, group] == 0), info = group)
  }
})

test_that("class 0 is outside the survey, so it is missing rather than 'not forest'", {
  skip_if_not_installed("terra")
  dir <- tempfile("nalcms-")
  dir.create(dir)
  classes <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 60, ymin = 0, ymax = 30,
                         crs = ATLAS_CRS)
  terra::values(classes) <- c(0, 1)
  tif <- file.path(dir, "classes.tif")
  terra::writeRaster(classes, tif, datatype = "INT1U", NAflag = 255)
  groups <- terra::rast(atlas_nalcms_vrt(tif, file.path(dir, "groups.vrt")))
  expect_true(all(is.na(terra::values(groups)[1, ])))
  # And a cell half outside the survey averages only over what was surveyed.
  share <- terra::aggregate(groups, fact = 2, fun = "mean", na.rm = TRUE)
  expect_equal(unname(terra::values(share)[1, "forest_needleleaf"]), 1)
})

# --- Copernicus fills the forest type where NALCMS is silent ------------------

test_that("Copernicus classes become the three forest fractions, unknown forest counting for none", {
  skip_if_not_installed("terra")
  classes <- terra::rast(nrows = 2, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 2,
                         crs = "EPSG:4326")
  # closed evergreen needle, open deciduous broadleaf, mixed, unknown forest,
  # shrub, no data, crops, closed evergreen broadleaf
  terra::values(classes) <- c(111L, 124L, 115L, 116L, 20L, 0L, 40L, 112L)
  out <- atlas_copernicus_fractions(classes, fact = 1L)
  v <- terra::values(out)
  expect_equal(names(out), c("forest_needleleaf", "forest_broadleaf", "forest_mixed"))
  expect_equal(unname(v[1, ]), c(1, 0, 0))
  expect_equal(unname(v[2, ]), c(0, 1, 0))
  expect_equal(unname(v[3, ]), c(0, 0, 1))
  expect_equal(unname(v[4, ]), c(0, 0, 0))
  expect_equal(unname(v[5, ]), c(0, 0, 0))
  expect_true(all(is.na(v[6, ])))
  expect_equal(unname(v[8, ]), c(0, 1, 0))
  # Averaged up, a cell is the share of its pixels with data under each type:
  # here needleleaf, broadleaf, shrub and a no-data pixel.
  coarse <- atlas_copernicus_fractions(classes, fact = 2L)
  expect_equal(unname(terra::values(coarse)[1, ]), c(1 / 3, 1 / 3, 0), tolerance = 1e-6)
})

test_that("the windows read are Hawaii and the Caribbean, in longitude and latitude", {
  expect_setequal(names(ATLAS_COPERNICUS_WINDOWS), c("hawaii", "caribbean"))
  h <- ATLAS_COPERNICUS_WINDOWS$hawaii
  expect_true(h[["xmin"]] < -159.8 && h[["xmax"]] > -154.8)   # Kauai to Hawaii
  expect_true(h[["ymin"]] < 18.9 && h[["ymax"]] > 22.3)
  c <- ATLAS_COPERNICUS_WINDOWS$caribbean
  expect_true(c[["xmin"]] < -67.3 && c[["xmax"]] > -64.5)     # Puerto Rico and the Virgin Islands
  expect_true(c[["ymin"]] < 17.6 && c[["ymax"]] > 18.6)
})

test_that("the forest-type layer is supplemented from Copernicus and says where", {
  registry <- atlas_layer_registry()
  expect_true(is.function(registry$foresttype$supplement))
  expect_equal(registry$foresttype$supplement_known, "forest_known")
  expect_match(registry$foresttype$note, "Copernicus")
})

test_that("every candidate band has a place in the predictor order", {
  expect_true(all(c(names(ATLAS_NALCMS_GROUPS), unname(ATLAS_CLIMATENA_VARS),
                    "clim_aet", "clim_vpd") %in% ATLAS_PREDICTOR_PRIORITY))
  expect_true(all(ATLAS_HOST_BANDS %in% atlas_predictor_priority()))
})
