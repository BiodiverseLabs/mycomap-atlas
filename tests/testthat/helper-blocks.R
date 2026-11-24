# Where the predictors have values, for tests that finish a release: every
# cell of a wide box over the fixtures' ground (atlas_block_land_file reads
# the file the option names instead of fetching a layer set).
local({
  land <- terra::rast(xmin = -3.5e6, xmax = 5e5, ymin = -1e6, ymax = 3e6, resolution = 5000, crs = ATLAS_CRS)
  terra::values(land) <- 1L
  path <- file.path(tempdir(), "atlas-test-block-land.tif")
  terra::writeRaster(land, path, overwrite = TRUE, datatype = "INT1U")
  options(atlas.block_land = path)
})

# For tests of what finishing does besides the blocks (counts, combined maps,
# the index): a trim that leaves every map as it is. Finishing's own trim is
# tested in test-blocks.R.
no_trim <- function(...) list(trimmed = 0L)
