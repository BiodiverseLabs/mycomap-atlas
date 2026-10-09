# Shared by the here index and location prior tests: small strong maps on
# the Atlas grid.

# A small model raster on the Atlas grid around Albers' origin (40N, 96W),
# its values rising eastward, or westward with rising = "west".
here_raster <- function(rising = "east") {
  r <- terra::rast(ncols = 40, nrows = 40, xmin = -100000, xmax = 100000,
                   ymin = -100000, ymax = 100000, crs = ATLAS_CRS)
  x <- terra::xFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- if (rising == "east") x else -x
  r
}

# A model's files as a fit leaves them. With dissimilarity (a raster) and a
# threshold, cells whose dissimilarity is above it are outside the model's
# area of applicability.
write_model <- function(taxon, algorithm, raster, skill = "passed", presences = 30,
                        dissimilarity = NULL, threshold = NULL) {
  dir.create(atlas_model_dir("draft", algorithm), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(raster, atlas_model_path(taxon, "draft", ".tif", algorithm), overwrite = TRUE)
  if (!is.null(dissimilarity)) {
    terra::writeRaster(dissimilarity, atlas_model_path(taxon, "draft", ".di.tif", algorithm), overwrite = TRUE)
  }
  atlas_write_json(c(list(taxon = taxon, algorithm = algorithm, presences = presences, predictors = list("bio1"),
                          auc_mean = 0.7, boyce_mean = 0.5, built_at = "2026-09-29T00:00:00Z",
                          map = "x.png", skill = skill,
                          null = list(design = ATLAS_NULL_DESIGN, observed_auc = 0.7, observed_boyce = 0.5)),
                     if (!is.null(threshold)) list(applicability = list(threshold = threshold))),
                   atlas_model_path(taxon, "draft", ".json", algorithm))
}

# A dissimilarity layer for here_raster's grid that puts everything east of
# x = 0 outside the area of applicability at threshold 0.5.
east_outside <- function() {
  r <- here_raster("east")
  terra::values(r) <- ifelse(terra::xFromCell(r, seq_len(terra::ncell(r))) > 0, 1, 0)
  r
}
