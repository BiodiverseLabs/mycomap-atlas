# A taxon's map as one picture, for places that cannot run a web map:
# Excel's =IMAGE(), a Word document, a slide, an email.
#
# The map PNG the site lays over its slippy map is colour alone, with no land
# or borders under it. Here it is drawn over Natural Earth land, lakes and
# state lines (inst/boundaries), with the collections, the species' name, a
# legend and where it came from. Everything is in Web Mercator, as the site
# draws it, so the picture matches what people see on the taxon page.

ATLAS_IMAGE_WIDTHS <- c(600L, 900L, 1200L, 1600L)
# The map strength the site starts a map at (web/src/components/MapStrength.tsx).
ATLAS_IMAGE_OPACITY <- c(standard = 0.8, faint = 0.25)
ATLAS_REACH_KM <- 500

#' The area a taxon's map opens on, as web/src/lib/mapView.ts works it out:
#' the collections widened by the colour's reach, kept inside the raster when
#' they overlap it. With no collections, the raster; with neither, North
#' America. A list of south, west, north, east.
atlas_image_view <- function(points = NULL, raster = NULL) {
  ok <- !is.null(points) && nrow(points) > 0
  if (ok) points <- points[is.finite(points$lat) & is.finite(points$lng), , drop = FALSE]
  if (!ok || !nrow(points)) {
    if (!is.null(raster)) return(raster[c("south", "west", "north", "east")])
    return(list(south = 14, west = -170, north = 72, east = -52))
  }
  km_per_degree <- 111.32
  lat_pad <- ATLAS_REACH_KM / km_per_degree
  poleward <- min(max(abs(range(points$lat))) + lat_pad, 80)
  lng_pad <- ATLAS_REACH_KM / (km_per_degree * cos(poleward * pi / 180))
  view <- list(
    south = max(min(points$lat) - lat_pad, -85), west = min(points$lng) - lng_pad,
    north = min(max(points$lat) + lat_pad, 85), east = max(points$lng) + lng_pad
  )
  if (!is.null(raster)) {
    s <- max(view$south, raster$south)
    n <- min(view$north, raster$north)
    w <- max(view$west, raster$west)
    e <- min(view$east, raster$east)
    if (s < n && w < e) view <- list(south = s, west = w, north = n, east = e)
  }
  view
}

#' Longitude and latitude to Web Mercator metres, centred on lon_0.
atlas_mercator_xy <- function(lng, lat, lon_0) {
  rad <- pi / 180
  lat <- pmax(pmin(lat, 85), -85)
  cbind(
    x = ATLAS_MERCATOR_RADIUS * (lng - lon_0) * rad,
    y = ATLAS_MERCATOR_RADIUS * log(tan(pi / 4 + lat * rad / 2))
  )
}

#' Which map a picture shows when none is asked for: the small-model
#' ensemble for a sparse taxon, else the first full model fitted.
atlas_image_algorithm <- function(name, requested = "", grid = "draft") {
  has <- function(a) file.exists(atlas_model_path(name, grid, ".json", a))
  if (nzchar(requested %||% "")) return(if (requested %in% names(ATLAS_ALGORITHMS)) requested else NULL)
  for (a in c("esm", "maxnet", "xgboost", "rf")) if (has(a)) return(a)
  "maxnet"
}

# Draw a SpatVector already in the picture's coordinates onto the open plot.
atlas_draw_polygons <- function(v, col = NA, border = NA, lwd = 1) {
  if (nrow(v)) terra::plot(v, add = TRUE, col = col, border = border, lwd = lwd, axes = FALSE, legend = FALSE)
}

atlas_draw_lines <- function(v, col, lwd) {
  if (nrow(v)) terra::lines(v, col = col, lwd = lwd)
}

#' Draw a taxon's map picture to a PNG file.
#'
#' name, the taxon; metrics, its model's metrics (NULL for a taxon with no
#' map); overlay, the model's map PNG; cells, its 0.1 degree collection
#' cells (lat, lng, records); records, its record count for the caption.
atlas_write_map_image <- function(path, name, metrics = NULL, overlay = NULL, cells = NULL,
                                  records = NA, width = 1200L, points = TRUE,
                                  site = atlas_site_origin()) {
  width <- as.integer(width)
  height <- as.integer(round(width * 0.75))
  # Text, symbols and lines scale with the resolution, which follows the width.
  scale <- width / 1200
  bounds <- if (!is.null(metrics$bounds)) {
    lapply(metrics$bounds[c("south", "west", "north", "east")], as.numeric)
  } else {
    NULL
  }
  has_map <- !is.null(bounds) && !is.null(overlay) && file.exists(overlay) && !isTRUE(metrics$map_withheld)
  view <- atlas_image_view(cells, if (has_map) bounds else NULL)
  lon_0 <- round((view$west + view$east) / 2)
  corners <- atlas_mercator_xy(c(view$west, view$east), c(view$south, view$north), lon_0)

  type <- if (isTRUE(capabilities("cairo"))) "cairo" else getOption("bitmapType")
  grDevices::png(path, width = width, height = height, res = round(144 * scale),
                 type = type, bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  header <- 0.11
  footer <- 0.10

  # The map, in its own panel between the title and the legend.
  graphics::par(mar = c(0, 0, 0, 0), plt = c(0, 1, footer, 1 - header), xaxs = "i", yaxs = "i")
  graphics::plot.new()
  graphics::plot.window(corners[, "x"], corners[, "y"], asp = 1)
  usr <- graphics::par("usr")
  graphics::rect(usr[1], usr[3], usr[2], usr[4], col = "#dce8ef", border = NA)

  to_picture <- function(v) {
    terra::project(v, atlas_map_mercator(lon_0))
  }
  countries <- to_picture(atlas_read_boundaries("countries"))
  regions <- to_picture(atlas_read_boundaries("regions"))
  lakes <- to_picture(atlas_read_boundaries("lakes"))
  atlas_draw_polygons(countries, col = "#f6f3ec", border = NA)
  atlas_draw_polygons(lakes, col = "#dce8ef", border = NA)

  if (has_map) {
    image <- terra::rast(overlay)
    rgba <- terra::values(image, mat = TRUE)
    faint <- identical(metrics$skill, "failed")
    alpha <- rgba[, 4] * ATLAS_IMAGE_OPACITY[[if (faint) "faint" else "standard"]]
    colours <- grDevices::rgb(rgba[, 1], rgba[, 2], rgba[, 3], alpha, maxColorValue = 255)
    raster <- grDevices::as.raster(matrix(colours, nrow = terra::nrow(image), byrow = TRUE))
    at <- atlas_mercator_xy(c(bounds$west, bounds$east), c(bounds$south, bounds$north), lon_0)
    graphics::rasterImage(raster, at[1, "x"], at[1, "y"], at[2, "x"], at[2, "y"], interpolate = TRUE)
  }

  # Lines over the colour, so states read through it.
  atlas_draw_lines(regions, col = "#9a9184", lwd = 0.6)
  atlas_draw_lines(countries, col = "#6f6659", lwd = 1.0)

  if (isTRUE(points) && !is.null(cells) && nrow(cells)) {
    xy <- atlas_mercator_xy(cells$lng, cells$lat, lon_0)
    busiest <- max(cells$records, 1)
    graphics::points(xy[, "x"], xy[, "y"], pch = 21, bg = "#ffffffd9", col = "#4a3728",
                     lwd = 0.8, cex = 0.45 + 0.6 * cells$records / busiest)
  }

  note <- if (!has_map) {
    "No habitat map yet: these are the places it has been collected."
  } else if (identical(metrics$skill, "failed")) {
    "This map did no better than its null models, so it says little about habitat."
  } else {
    NULL
  }
  if (!is.null(note)) {
    graphics::legend("bottom", legend = note, bty = "o", box.col = NA, bg = "#ffffffe6",
                     cex = 0.75, inset = 0.02, text.col = "#5c4a3a")
  }
  graphics::box(col = "#d8d0c4")

  # Title above, legend and source below, on the whole picture.
  graphics::par(new = TRUE, plt = c(0, 1, 0, 1))
  graphics::plot.new()
  graphics::plot.window(c(0, 1), c(0, 1))
  graphics::text(0.015, 1 - header / 2, name, adj = c(0, 0.5), font = 3, cex = 1.35, col = "#4a3728")
  label <- if (has_map) ATLAS_ALGORITHMS[[metrics$algorithm %||% "maxnet"]]$label else NULL
  caption <- paste(c(
    if (is.finite(as.numeric(records))) paste(format(as.numeric(records), big.mark = ","), "DNA-validated records"),
    if (has_map) paste("habitat suitability,", label)
  ), collapse = " · ")
  graphics::text(0.985, 1 - header / 2, caption, adj = c(1, 0.5), cex = 0.75, col = "#7a6a5a")

  if (has_map) {
    ramp <- grDevices::colorRampPalette(ATLAS_MAP_RAMP)(100)
    graphics::rasterImage(grDevices::as.raster(matrix(ramp, nrow = 1)), 0.13, footer * 0.42, 0.33, footer * 0.62)
    graphics::text(0.125, footer * 0.52, "Less suitable", adj = c(1, 0.5), cex = 0.65, col = "#7a6a5a")
    graphics::text(0.335, footer * 0.52, "More", adj = c(0, 0.5), cex = 0.65, col = "#7a6a5a")
  }
  if (isTRUE(points)) {
    graphics::points(0.40, footer * 0.52, pch = 21, bg = "white", col = "#4a3728", cex = 0.8)
    graphics::text(0.41, footer * 0.52, "Collected (0.1° cells)", adj = c(0, 0.5), cex = 0.65, col = "#7a6a5a")
  }
  graphics::text(0.985, footer * 0.52,
                 paste0("MycoMap Atlas · ", sub("^https?://", "", site), " · boundaries: Natural Earth"),
                 adj = c(1, 0.5), cex = 0.65, col = "#7a6a5a")
  invisible(path)
}
