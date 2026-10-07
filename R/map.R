# Turning a fitted surface into something a browser can draw.
#
# The map is rendered to a PNG in Web Mercator rather than served as tiles or
# as a grid of numbers. Leaflet places an image on a latitude/longitude
# rectangle but draws in Web Mercator, so an image already warped to Mercator
# lands exactly where it belongs, and a continental surface becomes a few
# hundred kilobytes instead of half a million JSON cells.
#
# The palette is mycomap.org's: pale where the model is unconvinced, the site's
# green through the middle, dark green where it is confident. Low-ranked
# ground is drawn faint, so a map does not imply precision it does not have.
#
# Ground outside the map's area of applicability (R/aoa.R), conditions no
# training site resembles, is not coloured at all: it is hatched grey and left
# out of the ranking, so the darkest green is the best tenth of the ground the
# model knows something about. Ranks are taken on the equal-area grid, before
# the map is warped to Mercator, so every cell counts for the same area.

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

ATLAS_MERCATOR_RADIUS <- 6378137

#' Web Mercator's formula, centred on a chosen meridian.
#'
#' A 500 km accessible area around Alaska reaches past 180 degrees into the
#' Aleutians. Projected to EPSG:3857 itself, those cells wrap to the far east
#' edge of the world, and the map's rectangle spans the globe or collapses to
#' nothing. Centred on the map's own longitude, the same formula keeps every
#' cell on one side, and the image is still Web Mercator: on a sphere, x is
#' linear in longitude, so moving the centre only slides the image along x.
atlas_map_mercator <- function(lon_0) {
  paste0(
    "+proj=merc +a=", ATLAS_MERCATOR_RADIUS, " +b=", ATLAS_MERCATOR_RADIUS,
    " +lat_ts=0 +lon_0=", format(lon_0), " +x_0=0 +y_0=0 +k=1 +units=m",
    " +nadgrids=@null +wktext +no_defs"
  )
}

#' The longitude at the middle of a raster, to the nearest degree.
atlas_map_centre_longitude <- function(raster) {
  extent <- as.vector(terra::ext(raster))
  centre <- cbind(
    x = mean(extent[c("xmin", "xmax")]), y = mean(extent[c("ymin", "ymax")])
  )
  lonlat <- terra::crds(
    terra::project(terra::vect(centre, crs = terra::crs(raster)), "EPSG:4326")
  )
  round(lonlat[1, 1])
}

#' The latitude/longitude rectangle a spherical Mercator raster covers.
#'
#' Worked out from the formula rather than by projecting the corners back,
#' because a projection hands longitudes back folded into -180 to 180. A map
#' that reaches past the antimeridian keeps a west edge below -180, which is
#' what Leaflet needs to draw it as one piece.
atlas_map_bounds <- function(mercator) {
  proj <- terra::crs(mercator, proj = TRUE)
  if (!grepl("+proj=merc", proj, fixed = TRUE) ||
      !grepl(paste0("+a=", ATLAS_MERCATOR_RADIUS), proj, fixed = TRUE)) {
    stop("map bounds need a spherical Mercator raster, not: ", proj, call. = FALSE)
  }
  centre <- regmatches(proj, regexpr("(?<=[+]lon_0=)[-0-9.eE]+", proj, perl = TRUE))
  lon_0 <- if (length(centre)) as.numeric(centre) else 0
  extent <- as.vector(terra::ext(mercator))
  degrees <- 180 / pi
  longitude <- function(x) lon_0 + x / ATLAS_MERCATOR_RADIUS * degrees
  latitude <- function(y) atan(sinh(y / ATLAS_MERCATOR_RADIUS)) * degrees
  west <- longitude(extent[["xmin"]])
  east <- longitude(extent[["xmax"]])
  # Atlas maps North America, which a browser shows around -100 degrees. A map
  # whose middle falls past 180 (one only of the Aleutians) is placed a turn
  # west, below -180, so it is drawn beside Alaska rather than a world away.
  shift <- if ((west + east) / 2 > 0) -360 else 0
  list(
    south = latitude(extent[["ymin"]]), west = west + shift,
    north = latitude(extent[["ymax"]]), east = east + shift
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
ATLAS_MAP_SCALE <- "rank, equal-area, within the area of applicability"

# Hatching for ground outside the area of applicability: grey stripes, one
# pixel diagonal in three, on a faint wash.
ATLAS_MAP_HATCH <- c(red = 140, green = 140, blue = 125)
ATLAS_MAP_HATCH_ALPHA <- 140
ATLAS_MAP_WASH_ALPHA <- 30

#' A map ready to draw, on the equal-area grid: each cell's rank among the
#' cells inside the area of applicability (NA outside it), and whether the
#' cell is outside (1) or inside (0). Without a dissimilarity layer, every
#' cell with a value is inside.
atlas_map_layers <- function(suitability, dissimilarity = NULL, threshold = NULL) {
  values <- terra::values(suitability, mat = FALSE)
  has_value <- is.finite(values)
  outside <- rep(FALSE, length(values))
  if (!is.null(dissimilarity) && length(threshold) == 1L && is.finite(threshold)) {
    index <- terra::values(dissimilarity, mat = FALSE)
    outside <- has_value & is.finite(index) & index > threshold
  }
  inside <- has_value & !outside
  rank <- rep(NA_real_, length(values))
  rank[inside] <- atlas_rank_scale(values[inside])
  flag <- ifelse(has_value, as.numeric(outside), NA_real_)
  layers <- terra::rast(suitability, nlyrs = 2)
  terra::values(layers) <- cbind(rank, flag)
  names(layers) <- c("rank", "outside")
  layers
}

#' RGBA bytes for a drawn map: ramp colours by rank, hatching where outside.
#' rank and outside are per pixel, in the row order of an image ncol wide.
atlas_map_colours <- function(rank, outside, ncol) {
  colours <- atlas_suitability_colours(rank)
  hatched <- which(is.finite(outside) & outside >= 0.5 & !is.finite(rank))
  if (length(hatched)) {
    pixel <- hatched - 1L
    stripe <- ((pixel %/% ncol) + (pixel %% ncol)) %% 3L == 0L
    colours[hatched, ] <- matrix(c(ATLAS_MAP_HATCH, ATLAS_MAP_WASH_ALPHA),
                                 nrow = length(hatched), ncol = 4, byrow = TRUE)
    colours[hatched[stripe], 4] <- ATLAS_MAP_HATCH_ALPHA
  }
  colours
}

#' Write a suitability raster as a PNG a browser can lay over a map. With a
#' dissimilarity layer and its threshold, ground outside the area of
#' applicability is hatched and left out of the ranking.
atlas_write_map_png <- function(suitability, path, max_pixels = 1600,
                                dissimilarity = NULL, threshold = NULL) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed to draw maps: install.packages('terra')", call. = FALSE)
  }
  if (is.character(suitability)) {
    suitability <- terra::rast(suitability)
  }
  if (is.character(dissimilarity)) {
    dissimilarity <- terra::rast(dissimilarity)
  }
  layers <- atlas_map_layers(suitability, dissimilarity, threshold)
  mercator <- atlas_map_warp(layers, max_pixels)
  values <- terra::values(mercator)
  colours <- atlas_map_colours(pmin(1, pmax(0, values[, 1])), values[, 2], terra::ncol(mercator))
  atlas_write_rgba_png(mercator, colours, path)
}

#' Warp equal-area layers to the spherical Mercator a browser draws in,
#' centred on the layers' own longitude, no wider than max_pixels.
atlas_map_warp <- function(layers, max_pixels = 1600) {
  mercator <- terra::project(
    layers, atlas_map_mercator(atlas_map_centre_longitude(layers)),
    method = "bilinear"
  )
  widest <- max(dim(mercator)[1:2])
  if (widest > max_pixels) {
    mercator <- terra::aggregate(
      mercator, fact = ceiling(widest / max_pixels), fun = "mean", na.rm = TRUE
    )
  }
  mercator
}

#' Write RGBA bytes as a PNG on a warped raster's grid, and say where it sits.
atlas_write_rgba_png <- function(mercator, colours, path) {
  image <- terra::rast(mercator[[1]], nlyrs = 4)
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

#' How strongly a map is drawn, from 0 to 1: how far its blocked AUC sits
#' above its null models', in their standard deviations. A map that failed its
#' null test is 0; one that passed starts at ATLAS_MAP_STRENGTH_FLOOR and
#' reaches 1 at ATLAS_MAP_STRENGTH_FULL_Z. An untested map sits at 0.5. The
#' site turns this into the overlay's opacity.
ATLAS_MAP_STRENGTH_FLOOR <- 0.4
ATLAS_MAP_STRENGTH_FULL_Z <- 5
atlas_map_strength <- function(null, skill) {
  if (!is.character(skill) || length(skill) != 1L) return(0.5)
  if (identical(skill, "failed")) return(0)
  if (!identical(skill, "passed")) return(0.5)
  observed <- as.numeric(null$observed_auc %||% NA)
  mean_auc <- as.numeric(null$auc_mean %||% NA)
  spread <- as.numeric(null$auc_sd %||% NA)
  if (!all(is.finite(c(observed, mean_auc, spread))) || spread <= 0) {
    return(ATLAS_MAP_STRENGTH_FLOOR)
  }
  z <- (observed - mean_auc) / spread
  pass_z <- stats::qnorm(1 - ATLAS_SKILL_ALPHA)
  share <- (z - pass_z) / (ATLAS_MAP_STRENGTH_FULL_Z - pass_z)
  round(ATLAS_MAP_STRENGTH_FLOOR + (1 - ATLAS_MAP_STRENGTH_FLOOR) * min(1, max(0, share)), 3)
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
    # Fits from before the index was taken over every fold together have
    # only the mean over folds.
    boyce = number(metrics$boyce %||% metrics$boyce_mean),
    boyce_mean = number(metrics$boyce_mean),
    # Fits from before null models were run have no verdict.
    skill = if (is.character(metrics$skill) && length(metrics$skill) == 1L) metrics$skill else "untested",
    map_strength = number(metrics$map_strength %||% atlas_map_strength(metrics$null, metrics$skill)),
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
      # Its counts by state too (R/predictions.R), kept beside the summary
      # rather than in it: one row per state, not one per model.
      regions <- if (is.list(metrics) && is.list(metrics$regions)) {
        atlas_region_rows(metrics$regions)
      } else {
        NULL
      }
      entry <- list(stamp = stamps[[i]], summary = summary, regions = regions)
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

#' Every model's counts by state, from the entries atlas_model_index read
#' into cache: taxon, algorithm, skill, code, cells, reach, suitable.
atlas_model_region_rows <- function(cache) {
  keep <- Filter(function(e) !is.null(e$summary) && !is.null(e$regions) && nrow(e$regions),
                 cache$entries %||% list())
  if (!length(keep)) return(NULL)
  # Column by column: binding thousands of small data frames takes seconds.
  n <- vapply(keep, function(e) nrow(e$regions), 1L)
  pick <- function(f) unlist(lapply(keep, f), use.names = FALSE)
  data.frame(
    taxon = rep(pick(function(e) e$summary$taxon), n),
    algorithm = rep(pick(function(e) e$summary$algorithm), n),
    skill = rep(pick(function(e) e$summary$skill), n),
    code = pick(function(e) e$regions$code),
    cells = pick(function(e) e$regions$cells),
    reach = pick(function(e) e$regions$reach),
    suitable = pick(function(e) e$regions$suitable),
    stringsAsFactors = FALSE
  )
}

#' Redraw one taxon's PNG from its stored raster and record how it was drawn.
atlas_redraw_map <- function(raster_path) {
  metrics_path <- sub("[.]tif$", ".json", raster_path)
  png_path <- sub("[.]tif$", ".png", raster_path)
  dissimilarity_path <- sub("[.]tif$", ".di.tif", raster_path)
  metrics <- if (file.exists(metrics_path)) {
    jsonlite::fromJSON(metrics_path, simplifyVector = FALSE)
  }
  drawn <- atlas_write_map_png(
    raster_path, png_path,
    dissimilarity = if (file.exists(dissimilarity_path)) dissimilarity_path,
    threshold = as.numeric(metrics$applicability$threshold %||% NA)
  )
  if (!is.null(metrics)) {
    metrics$map_strength <- atlas_map_strength(metrics$null, metrics$skill)
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
  # A map's dissimilarity layer sits beside it and is drawn with it, not as a
  # map of its own.
  rasters <- rasters[!grepl("[.]di[.]tif$", rasters)]
  if (!length(rasters)) {
    message("no fitted models on the ", grid, " grid")
    return(invisible(0L))
  }
  done <- 0L
  report <- function(drawn) {
    # Forced: R evaluates an argument only when it is used, and on one worker
    # the redraw itself is this argument. Unforced, nothing was redrawn.
    force(drawn)
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
