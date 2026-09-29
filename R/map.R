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

#' Each value's place among a map's own values, from 0 (lowest) to 1 (highest).
#'
#' Maps are coloured by rank, not by raw suitability. The three models put
#' their numbers on different scales — boosted trees rarely pass 0.65 where
#' Maxent reaches 1 — so on one raw scale the tree maps look washed out and
#' read as "unsuitable everywhere". By rank, the darkest green on every map is
#' that model's best tenth of the ground, and three maps side by side show
#' where each puts its high ground. The stored rasters keep the raw values.
atlas_rank_scale <- function(values) {
  out <- rep(NA_real_, length(values))
  usable <- is.finite(values)
  n <- sum(usable)
  if (n == 1L) {
    out[usable] <- 1
  } else if (n > 1L) {
    out[usable] <- (rank(values[usable], ties.method = "average") - 1) / (n - 1)
  }
  out
}

#' How a PNG's colours are scaled. Recorded with the metrics so a map drawn
#' under an older rule can be found and redrawn.
ATLAS_MAP_SCALE <- "rank"

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

  colours <- atlas_suitability_colours(atlas_rank_scale(terra::values(mercator)[, 1]))
  image <- terra::rast(mercator, nlyrs = 4)
  terra::values(image) <- colours

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(
    image, path, overwrite = TRUE, datatype = "INT1U", filetype = "PNG"
  )

  list(
    path = path,
    bounds = atlas_map_bounds(mercator),
    scale = ATLAS_MAP_SCALE,
    drawn_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
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
    # Metrics written before there was a choice of model are Maxent's.
    algorithm = as.character(metrics$algorithm %||% "maxnet"),
    presences = number(metrics$presences),
    predictors = length(metrics$predictors),
    auc_mean = number(metrics$auc_mean),
    boyce_mean = number(metrics$boyce_mean),
    # Fits from before null models were run have no verdict.
    skill = if (is.character(metrics$skill) && length(metrics$skill) == 1L) metrics$skill else "untested",
    map = is.character(metrics$map) && length(metrics$map) == 1L,
    built_at = as.character(metrics$built_at %||% ""),
    stringsAsFactors = FALSE
  )
}

#' A summary of every fitted model on a grid, every algorithm, newest first.
#'
#' Pass the same environment as cache on every call and only files that are
#' new or have changed since the last call are read again, which matters while
#' a batch is writing hundreds of them. A file caught half-written is skipped,
#' and read on a later call once its timestamp moves.
atlas_model_index <- function(grid = "draft", cache = new.env(parent = emptyenv()),
                              algorithms = names(ATLAS_ALGORITHMS)) {
  # The folder a file sits in says which model it is: that is where its map is
  # looked up, whatever the file itself claims.
  by_algorithm <- lapply(algorithms, function(algorithm) {
    list.files(atlas_model_dir(grid, algorithm), pattern = "[.]json$", full.names = TRUE)
  })
  files <- unlist(by_algorithm, use.names = FALSE)
  owner <- rep(algorithms, lengths(by_algorithm))
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
      summary <- if (is.list(metrics)) atlas_model_summary(metrics) else NULL
      if (!is.null(summary)) summary$algorithm <- owner[[i]]
      entry <- list(stamp = stamps[[i]], summary = summary)
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

#' Redraw one taxon's PNG from its stored raster and record how it was drawn.
atlas_redraw_map <- function(raster_path) {
  metrics_path <- sub("[.]tif$", ".json", raster_path)
  png_path <- sub("[.]tif$", ".png", raster_path)
  drawn <- atlas_write_map_png(raster_path, png_path)
  if (file.exists(metrics_path)) {
    metrics <- jsonlite::fromJSON(metrics_path, simplifyVector = FALSE)
    metrics$map <- basename(png_path)
    metrics$bounds <- drawn$bounds
    metrics$map_scale <- drawn$scale
    metrics$map_drawn_at <- drawn$drawn_at
    atlas_write_json(metrics, metrics_path)
  }
  list(path = png_path, width = drawn$width, height = drawn$height)
}

#' Redraw every fitted taxon's PNG from its stored raster, and record the
#' bounds, so a change of palette or scale does not mean refitting anything.
atlas_rebuild_maps <- function(grid = "draft", quiet = FALSE, workers = 1L) {
  rasters <- unlist(lapply(names(ATLAS_ALGORITHMS), function(algorithm) {
    list.files(atlas_model_dir(grid, algorithm), pattern = "[.]tif$", full.names = TRUE)
  }), use.names = FALSE)
  if (!length(rasters)) {
    message("no fitted models on the ", grid, " grid")
    return(invisible(0L))
  }
  done <- 0L
  report <- function(drawn) {
    done <<- done + 1L
    if (!quiet && (done %% 100L == 0L || done == length(rasters))) {
      message("  redrawn ", done, " of ", length(rasters))
    }
  }
  if (workers > 1L) {
    cluster <- atlas_start_workers(min(workers, length(rasters)), grid, points = NULL)
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    task <- function(raster_path) atlas_redraw_map(raster_path)
    environment(task) <- globalenv()
    atlas_run_on_workers(cluster, rasters, task, report)
  } else {
    for (raster_path in rasters) report(atlas_redraw_map(raster_path))
  }
  invisible(length(rasters))
}
