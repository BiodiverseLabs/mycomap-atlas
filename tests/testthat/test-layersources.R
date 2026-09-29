# Readers for the candidate layers: forest type, host trees, carbonate rock.
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

# A 2 x 2 world of basal area. Species 1 and 2 are pines, 3 is an oak, 4 is
# a maple (not a host genus, but part of the stand).
basal_area_files <- function() {
  dir <- tempfile("wilson-")
  dir.create(dir)
  one <- function(v, name) {
    r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 500, ymin = 0, ymax = 500,
                     crs = ATLAS_CRS)
    terra::values(r) <- v
    path <- file.path(dir, paste0(name, ".tif"))
    terra::writeRaster(r, path)
    path
  }
  list(
    files = c(one(c(10, 0, 0, NA), "pine1"), one(c(10, 0, 0, NA), "pine2"),
              one(c(20, 5, 0, NA), "oak"), one(c(0, 15, 0, NA), "maple")),
    genus = c("Pinus", "Pinus", "Quercus", "Acer")
  )
}

test_that("a genus share counts every species of the genus against the whole stand", {
  skip_if_not_installed("terra")
  ba <- basal_area_files()
  shares <- atlas_basal_area_shares(ba$files, ba$genus, genera = c("Pinus", "Quercus", "Fagus"),
                                    fact = 1L)
  v <- as.data.frame(terra::values(shares))
  # Cell 1: 20 pine + 20 oak of 40. Cell 2: 5 oak + 15 maple of 20.
  expect_equal(v[1, "host_pinus"], 0.5)
  expect_equal(v[1, "host_quercus"], 0.5)
  expect_equal(v[2, "host_quercus"], 0.25)
  expect_equal(v[2, "host_pinus"], 0)
  # A genus with no species raster is 0 wherever there are trees.
  expect_equal(v[1, "host_fagus"], 0)
})

test_that("treeless ground is share 0, and ground outside the map stays missing", {
  skip_if_not_installed("terra")
  ba <- basal_area_files()
  v <- as.data.frame(terra::values(atlas_basal_area_shares(ba$files, ba$genus, genera = "Pinus", fact = 1L)))
  expect_equal(v[3, "host_pinus"], 0)
  expect_true(is.na(v[4, "host_pinus"]))
})

test_that("a Canadian genus is its unidentified class plus every named species", {
  skip_if_not_installed("terra")
  dir <- tempfile("knn-")
  dir.create(dir)
  one <- function(v, name) {
    r <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 500, ymin = 0, ymax = 250,
                     crs = ATLAS_CRS)
    terra::values(r) <- v
    path <- file.path(dir, paste0(name, ".tif"))
    terra::writeRaster(r, path)
    path
  }
  # "Tsug_Spp" is the kNN's unidentified-hemlock class, 5% here. Read as the
  # genus total it would miss the 60% that are named species.
  paths <- list(Tsuga = c(one(c(5, 0), "Tsug_Spp"), one(c(40, 0), "Tsug_Het"),
                          one(c(20, 10), "Tsug_Mer")))
  v <- terra::values(atlas_composition_shares(paths, fact = 1L))
  expect_equal(v[, "host_tsuga"], c(0.65, 0.10))
})

test_that("every host genus lists its Canadian classes under its own prefix", {
  for (genus in names(ATLAS_HOST_GENERA)) {
    prefix <- substr(genus, 1, 4)
    expect_true(all(startsWith(ATLAS_HOST_GENERA[[genus]], prefix)), info = genus)
  }
  expect_equal(atlas_host_band("Pseudotsuga"), "host_pseudotsuga")
})

test_that("every host band has a place in the predictor order", {
  bands <- atlas_host_band(names(ATLAS_HOST_GENERA))
  expect_true(all(bands %in% ATLAS_PREDICTOR_PRIORITY))
  expect_true(all(c(names(ATLAS_NALCMS_GROUPS), unname(ATLAS_CLIMATENA_VARS),
                    "clim_aet", "clim_vpd", "bedrock_carbonate",
                    "twi", "northness", "heat_load") %in% ATLAS_PREDICTOR_PRIORITY))
})

test_that("carbonate cover is the share of each land cell the rock covers", {
  skip_if_not_installed("terra")
  land <- terra::rast(nrows = 1, ncols = 3, xmin = 0, xmax = 3000, ymin = 0, ymax = 1000,
                      crs = ATLAS_CRS)
  terra::values(land) <- c(100, 200, NA)
  # Limestone over the whole first cell and half the second.
  rock <- terra::vect("POLYGON ((0 0, 1500 0, 1500 1000, 0 1000, 0 0))", crs = ATLAS_CRS)
  v <- terra::values(atlas_carbonate_cover(rock, land), mat = FALSE)
  expect_equal(v[1:2], c(1, 0.5), tolerance = 0.02)
  # The third cell is sea.
  expect_true(is.na(v[3]))
})
