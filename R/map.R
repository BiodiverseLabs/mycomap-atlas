# Turning a fitted surface into something a browser can draw.
#
# The map is rendered to a PNG in Web Mercator rather than served as tiles or
# as a grid of numbers. Leaflet places an image on a latitude/longitude
# rectangle but draws in Web Mercator, so an image already warped to Mercator
# lands exactly where it belongs, and a continental surface becomes a few
# hundred kilobytes instead of half a million JSON cells.
#
# The palette is mycomap.org's: pale where the model is unconvinced, the site's
# green through the middle, dark green where it is confident. Low suitability
# is drawn faint, so a map does not imply precision it does not have.

ATLAS_MAP_RAMP <- c("#f7f7e8", "#94c440", "#2e5a17")

#' Colour a vector of suitabilities as RGBA bytes. Missing values are clear.
atlas_suitability_colours <- function(values) {
  ramp <- grDevices::colorRamp(ATLAS_MAP_RAMP, space = "Lab")
  scaled <- pmin(1, pmax(0, as.numeric(values)))
  usable <- is.finite(scaled)

  rgb <- matrix(0, nrow = length(scaled), ncol = 3)
  if (any(usable)) {
    rgb[usable, ] <- ramp(scaled[usable])
  }
  alpha <- ifelse(usable, round(40 + 200 * scaled), 0)
  alpha[!usable] <- 0

  out <- cbind(round(rgb), alpha)
  colnames(out) <- c("red", "green", "blue", "alpha")
  out
}

#' The latitude/longitude rectangle a Web Mercator raster covers.
atlas_map_bounds <- function(mercator) {
  extent <- as.vector(terra::ext(mercator))
  corners <- cbind(
    x = c(extent[["xmin"]], extent[["xmax"]]),
    y = c(extent[["ymin"]], extent[["ymax"]])
  )
  lonlat <- terra::crds(
    terra::project(terra::vect(corners, crs = "EPSG:3857"), "EPSG:4326")
  )
  list(
    south = lonlat[1, 2], west = lonlat[1, 1],
    north = lonlat[2, 2], east = lonlat[2, 1]
  )
}

#' Write a suitability raster as a PNG a browser can lay over a map.
atlas_write_map_png <- function(suitability, path, max_pixels = 1600) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed to draw maps: install.packages('terra')", call. = FALSE)
  }
  if (is.character(suitability)) {
    suitability <- terra::rast(suitability)
  }
  mercator <- terra::project(suitability, "EPSG:3857", method = "bilinear")

  widest <- max(dim(mercator)[1:2])
  if (widest > max_pixels) {
    mercator <- terra::aggregate(
      mercator, fact = ceiling(widest / max_pixels), fun = "mean", na.rm = TRUE
    )
  }

  colours <- atlas_suitability_colours(terra::values(mercator)[, 1])
  image <- terra::rast(mercator, nlyrs = 4)
  terra::values(image) <- colours

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(
    image, path, overwrite = TRUE, datatype = "INT1U", filetype = "PNG"
  )

  list(
    path = path,
    bounds = atlas_map_bounds(mercator),
    width = terra::ncol(mercator),
    height = terra::nrow(mercator)
  )
}

#' The few fields a list of models needs.
#'
#' A list of every model used to send each one's full metrics — folds,
#' settings, bounds — and with nine hundred models, turning that into JSON took
#' ten seconds. A list needs a name and a score, not the whole record.
atlas_model_summary <- function(metrics) {
  number <- function(x) {
    if (is.numeric(x) && length(x) == 1L && is.finite(x)) x else NA_real_
  }
  data.frame(
    taxon = as.character(metrics$taxon %||% NA_character_),
    presences = number(metrics$presences),
    predictors = length(metrics$predictors),
    auc_mean = number(metrics$auc_mean),
    boyce_mean = number(metrics$boyce_mean),
    map = is.character(metrics$map) && length(metrics$map) == 1L,
    built_at = as.character(metrics$built_at %||% ""),
    stringsAsFactors = FALSE
  )
}

#' A summary of every fitted model on a grid, newest first.
#'
#' Pass the same environment as cache on every call and only files that are
#' new or have changed since the last call are read again, which matters while
#' a batch is writing hundreds of them. A file caught half-written is skipped,
#' and read on a later call once its timestamp moves.
atlas_model_index <- function(grid = "draft", cache = new.env(parent = emptyenv())) {
  directory <- atlas_path("models", grid)
  files <- list.files(directory, pattern = "[.]json$", full.names = TRUE)
  info <- file.info(files, extra_cols = FALSE)
  stamps <- paste(as.numeric(info$mtime), info$size)
  known <- cache$entries %||% list()

  entries <- vector("list", length(files))
  names(entries) <- files
  for (i in seq_along(files)) {
    entry <- known[[files[[i]]]]
    if (is.null(entry) || !identical(entry$stamp, stamps[[i]])) {
      metrics <- tryCatch(
        jsonlite::fromJSON(files[[i]], simplifyVector = FALSE),
        error = function(e) NULL
      )
      cache$reads <- (cache$reads %||% 0L) + 1L
      entry <- list(
        stamp = stamps[[i]],
        summary = if (is.list(metrics)) atlas_model_summary(metrics) else NULL
      )
    }
    entries[[i]] <- entry
  }
  cache$entries <- entries

  rows <- Filter(Negate(is.null), lapply(entries, function(e) e$summary))
  if (!length(rows)) {
    return(atlas_model_summary(list())[0, , drop = FALSE])
  }
  out <- do.call(rbind, rows)
  out <- out[order(out$built_at, decreasing = TRUE), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Redraw every fitted taxon's PNG from its stored raster, and record the
#' bounds, so a change of palette does not mean refitting anything.
atlas_rebuild_maps <- function(grid = "draft", quiet = FALSE) {
  directory <- atlas_path("models", grid)
  rasters <- list.files(directory, pattern = "[.]tif$", full.names = TRUE)
  if (!length(rasters)) {
    message("no fitted models on the ", grid, " grid")
    return(invisible(NULL))
  }
  for (raster_path in rasters) {
    metrics_path <- sub("[.]tif$", ".json", raster_path)
    png_path <- sub("[.]tif$", ".png", raster_path)
    drawn <- atlas_write_map_png(raster_path, png_path)
    if (file.exists(metrics_path)) {
      metrics <- jsonlite::fromJSON(metrics_path, simplifyVector = FALSE)
      metrics$map <- basename(png_path)
      metrics$bounds <- drawn$bounds
      atlas_write_json(metrics, metrics_path)
    }
    if (!quiet) {
      message("  ", basename(png_path), ": ", drawn$width, "x", drawn$height,
              ", ", round(file.info(png_path)$size / 1024), " KB")
    }
  }
  invisible(NULL)
}
