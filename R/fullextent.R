# Full-extent maps: what a strong model says beyond its 500 km reach
# (Steve, 2026-10-12, session "Map distribution cutoff option").
#
# A model is fitted inside its accessible area (500 km around its sites), and
# its map is predicted only there (atlas_predict_raster masks first). That
# stays the default everywhere. A strong model is also predicted over the
# rest of North America (the states and provinces of the three countries
# Atlas maps), at the same 5 km cells, and written beside its map:
#
#   <taxon>.full.tif      suitability over the whole grid
#   <taxon>.full.di.tif   its area-of-applicability index over the whole grid
#   <taxon>.full.png      the full view, drawn as the map is
#
# One colour scale: inside the accessible area the full view has exactly the
# default map's ranks and hatching; beyond it each cell is placed on that
# same scale (its suitability ranked against the in-area cells inside the
# area of applicability, clamped to 0-1), and hatched where its index is
# above the model's threshold, which, far from the training sites, is most
# of the continent. The default .tif, .di.tif and .png are byte for byte what
# they were without this.
#
# Only the web map's "full extent" view reads these. Everything downstream
# reads the default files: counts by state and "beyond reach", the here
# index, the combined maps, the sitemap, the prior export, best-map and
# maps/best, and trained ids (tests hold them to that). Weak and failed
# models are not predicted beyond their reach: their maps make no claim.

ATLAS_FULL_EXTS <- c(".full.tif", ".full.di.tif", ".full.png")

# The widest a full view is drawn, in pixels: room for a continent at about
# its 5 km cells, where a 500 km map is drawn at up to 1,600.
ATLAS_FULL_MAX_PIXELS <- 4096

#' Whether a model gets a full-extent map: a strong one does; a refit job may
#' ask for it whatever the grade (full = TRUE), and a fit may refuse it
#' (full = FALSE).
atlas_full_extent_wanted <- function(grade, full = NULL) {
  if (!is.null(full)) return(isTRUE(full))
  identical(grade, "strong")
}

#' Predict over the whole stack, no mask.
atlas_predict_raster_full <- function(model, stack, score, name = "suitability") {
  predicted <- terra::predict(stack, model, fun = function(model, data, ...) score(model, data), na.rm = TRUE)
  names(predicted) <- name
  predicted
}

#' The full-extent suitability and dissimilarity, predicting only the ground
#' beyond the accessible area: inside it they are the default map's values,
#' already predicted (about half of a widespread taxon's continent, measured
#' 2026-10-12), so the full raster equals the default map there exactly.
atlas_predict_full_extent <- function(model, score, aoa, stack, area, suitability, dissimilarity) {
  template <- stack[[1]]
  in_area <- !is.na(terra::values(terra::rasterize(area, template), mat = FALSE))
  # Beyond the reach, North America only: the states and provinces of the
  # three countries Atlas maps (R/predictions.R), not every land cell of the
  # grid's rectangle, which runs from Siberia and Greenland to South America
  # (the 2026-10-12 pilot drew them). Inside the reach the map is as it is.
  regions <- atlas_region_grid()$ids
  if (!terra::compareGeom(regions, template, stopOnError = FALSE)) {
    regions <- terra::resample(regions, template, method = "near")
  }
  in_scope <- !is.na(terra::values(regions, mat = FALSE))
  cells <- which(!in_area & in_scope & !is.na(terra::values(template, mat = FALSE)))
  data <- terra::extract(stack, cells)
  data <- data[, setdiff(names(data), "ID"), drop = FALSE]
  ok <- stats::complete.cases(data)
  values <- rep(NA_real_, terra::ncell(template))
  index <- rep(NA_real_, terra::ncell(template))
  if (any(ok)) {
    values[cells[ok]] <- score(model, data[ok, , drop = FALSE])
    index[cells[ok]] <- atlas_aoa_index(aoa, data[ok, , drop = FALSE])
  }
  full <- terra::rast(template)
  full_index <- terra::rast(template)
  terra::values(full) <- values
  terra::values(full_index) <- index
  # Inside the accessible area: the default map's own values.
  full <- terra::cover(terra::extend(suitability, full), full)
  full_index <- terra::cover(terra::extend(dissimilarity, full_index), full_index)
  names(full) <- "suitability"
  names(full_index) <- "dissimilarity"
  list(suitability = full, dissimilarity = full_index)
}

#' Where values fall among a reference, as atlas_rank_scale ranks the
#' reference itself: a value in it gets its rank, (rank - 1) / (n - 1) with
#' ties at their average; a value between two gets the midpoint of their
#' ranks; a value beyond the reference gets 0 or 1.
atlas_percentile_in <- function(values, reference) {
  reference <- sort(reference[is.finite(reference)])
  n <- length(reference)
  out <- rep(NA_real_, length(values))
  ok <- is.finite(values)
  if (!n || !any(ok)) return(out)
  if (n == 1L) {
    out[ok] <- 1
    return(out)
  }
  below <- findInterval(values[ok], reference, left.open = TRUE)
  through <- findInterval(values[ok], reference)
  equal <- through - below
  position <- ifelse(equal > 0, below + (equal - 1) / 2, below - 0.5)
  out[ok] <- pmin(1, pmax(0, position / (n - 1)))
  out
}

#' The full view's rank and outside layers, on the full raster's grid. Inside
#' the accessible area they are the default map's (atlas_map_layers of the
#' masked rasters); beyond it, ranked on the same scale and hatched by the
#' full index.
atlas_full_map_layers <- function(full, full_dissimilarity, suitability, dissimilarity, threshold) {
  default <- atlas_map_layers(suitability, dissimilarity, threshold)
  # The masked rasters are windows of the same grid: extend them with NA.
  default_full <- terra::extend(default, full)
  if (!terra::compareGeom(default_full, full, stopOnError = FALSE)) {
    default_full <- terra::resample(default_full, full, method = "near")
  }
  rank <- terra::values(default_full[["rank"]], mat = FALSE)
  outside <- terra::values(default_full[["outside"]], mat = FALSE)
  values <- terra::values(full, mat = FALSE)
  index <- terra::values(full_dissimilarity, mat = FALSE)
  in_area <- is.finite(outside)
  inside_values <- terra::values(suitability, mat = FALSE)[
    terra::values(default[["outside"]], mat = FALSE) %in% 0
  ]
  beyond <- !in_area & is.finite(values)
  threshold <- as.numeric(threshold %||% NA)
  outside[beyond] <- if (length(threshold) == 1L && is.finite(threshold)) {
    as.numeric(is.finite(index[beyond]) & index[beyond] > threshold)
  } else {
    0
  }
  ranked <- beyond & outside == 0
  rank[ranked] <- atlas_percentile_in(values[ranked], inside_values)
  layers <- terra::rast(full, nlyrs = 2)
  terra::values(layers) <- cbind(rank, outside)
  names(layers) <- c("rank", "outside")
  layers
}

#' Write a model's full-extent files and say what they hold and cost.
atlas_write_full_map <- function(name, grid, algorithm, full, full_dissimilarity, suitability,
                                 dissimilarity, threshold, predict_seconds = NA_real_) {
  started <- Sys.time()
  paths <- atlas_model_path(name, grid, ATLAS_FULL_EXTS, algorithm = algorithm)
  dir.create(dirname(paths[[1]]), recursive = TRUE, showWarnings = FALSE)
  gdal <- c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES")
  terra::writeRaster(full, paths[[1]], overwrite = TRUE, gdal = gdal)
  terra::writeRaster(full_dissimilarity, paths[[2]], overwrite = TRUE, gdal = gdal)
  layers <- atlas_full_map_layers(full, full_dissimilarity, suitability, dissimilarity, threshold)
  # Drawn over the cells that have data, not the grid's whole rectangle: in
  # Albers its corners reach past the pole and the antimeridian, and the
  # picture became a tall sliver with North America a few pixels at its foot
  # (the 2026-10-12 pilot). Hatched cells have data and stay. At about the
  # grid's own 5 km (a continent is wider than the 1,600 pixels a 500 km map
  # never reaches).
  drawn <- atlas_write_map_png(full, paths[[3]], layers = terra::trim(layers),
                               max_pixels = ATLAS_FULL_MAX_PIXELS, trim = TRUE)
  rank <- terra::values(layers[["rank"]], mat = FALSE)
  outside <- terra::values(layers[["outside"]], mat = FALSE)
  in_area <- !is.na(terra::values(terra::extend(suitability, full), mat = FALSE))
  list(
    raster = basename(paths[[1]]),
    dissimilarity = basename(paths[[2]]),
    map = basename(drawn$path),
    bounds = drawn$bounds,
    width = drawn$width,
    height = drawn$height,
    cells = sum(is.finite(outside)),
    beyond_reach = sum(is.finite(outside) & !in_area),
    beyond_reach_ranked = sum(is.finite(rank) & !in_area),
    seconds = round(predict_seconds + as.numeric(difftime(Sys.time(), started, units = "secs")), 1),
    png_seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1),
    bytes = sum(file.info(c(paths[1:2], drawn$path))$size)
  )
}

#' Remove a model's full-extent files: a refit that makes none (a weak map
#' now) must not leave an old one to be drawn.
atlas_remove_full_map <- function(name, grid = "draft", algorithm = "maxnet") {
  paths <- atlas_model_path(name, grid, c(ATLAS_FULL_EXTS, ".full.png.aux.xml"), algorithm)
  unlink(paths[file.exists(paths)])
  invisible(paths)
}
