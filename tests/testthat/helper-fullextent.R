# Shared by the full-extent and continent tests.

# A map whose values rise eastward, its dissimilarity rising away from the
# middle, and the accessible area: the middle strip, as atlas_predict_raster
# leaves it (a window of the same grid).
full_fixture <- function(threshold = 0.7) {
  full <- terra::rast(ncols = 40, nrows = 40, xmin = -1e5, xmax = 1e5, ymin = -1e5, ymax = 1e5, crs = ATLAS_CRS)
  x <- terra::xFromCell(full, seq_len(terra::ncell(full)))
  terra::values(full) <- x
  dissimilarity <- full
  terra::values(dissimilarity) <- abs(x) / 1e5
  window <- terra::ext(-5e4, 5e4, -1e5, 1e5)
  list(full = full, full_dissimilarity = dissimilarity, suitability = terra::crop(full, window),
       dissimilarity = terra::crop(dissimilarity, window), threshold = threshold)
}
