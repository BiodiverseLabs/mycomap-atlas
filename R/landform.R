# Landform: how wet, how shaded and how sun-baked a piece of ground is.
#
# Slope and roughness say how steep the ground is, not what that does to a
# fungus. Three derived measures say that more directly:
#
#   twi        topographic wetness index, ln(upslope area / tan(slope)): where
#              water gathers and lingers. Valley floors and hollows score high.
#   northness  cos(aspect) x sin(slope): +1 on a steep north-facing slope,
#              -1 on a steep south-facing one, 0 on the flat. Weighting by
#              slope keeps flat ground, whose aspect is noise, at zero.
#   heat_load  McCune & Keon (2002) heat load index, from latitude, slope and
#              aspect folded about the south-west, the warmest direction.
#
# All three are computed on the 1 km production elevation whatever grid they
# are built for, then averaged onto the grid. Terrain seen at 5 km is almost
# flat; averaging the 1 km values keeps the share of wet hollows and shaded
# slopes in a draft cell, which the 5 km elevation has already lost.
#
# Upslope area comes from D8 flow directions without pit filling, so a basin
# that drains through a sink stops accumulating there. At 1 km that caps what
# counts as "upslope" at the scale of a valley rather than a river basin, which
# is the scale that makes a hollow wet.

# Slope below this, in radians, is treated as this: tan(0) would put a flat
# cell's wetness at infinity.
ATLAS_TWI_MIN_SLOPE <- 0.001

#' Northness from slope and aspect, both in degrees.
atlas_northness <- function(slope_deg, aspect_deg) {
  cos(aspect_deg * pi / 180) * sin(slope_deg * pi / 180)
}

#' McCune & Keon (2002) heat load index, their equation 3.
#'
#' Latitude, slope and aspect are in degrees. Aspect is folded about 225
#' degrees, so south-west slopes score highest and north-east slopes lowest.
#' Valid for slopes up to 60 degrees and latitudes 0 to 60 north, which covers
#' the grid apart from the far Arctic; values there are extrapolated.
#'
#' One departure: the equation's -0.262 sin(lat) sin(aspect) term does not
#' vanish on flat ground, where aspect is noise, so a plain would get a random
#' +-20% from whichever way its last metre happens to tilt. That term is faded
#' in over the first two degrees of slope.
atlas_heat_load <- function(latitude_deg, slope_deg, aspect_deg) {
  lat <- latitude_deg * pi / 180
  slope <- slope_deg * pi / 180
  folded <- abs(pi - abs(aspect_deg * pi / 180 - 5 * pi / 4))
  fade <- pmin(1, slope_deg / 2)
  exp(-1.467 + 1.582 * cos(lat) * cos(slope) -
        1.5 * cos(folded) * sin(slope) * sin(lat) -
        0.262 * sin(lat) * sin(folded) * fade + 0.607 * sin(slope))
}

#' Topographic wetness index from upslope cell count, cell size and slope.
atlas_wetness_index <- function(upslope_cells, cell_m, slope_deg) {
  area <- (upslope_cells + 1) * cell_m
  slope <- pmax(slope_deg * pi / 180, ATLAS_TWI_MIN_SLOPE)
  log(area / tan(slope))
}

#' Latitude of every cell of a raster, in degrees.
#'
#' Latitude changes smoothly, so a tenth-of-a-degree field projected onto the
#' raster is exact to well under a kilometre, and far cheaper than projecting
#' ninety million cell centres one by one.
atlas_latitude_raster <- function(like) {
  window <- ATLAS_SOURCE_WINDOW
  field <- terra::rast(
    xmin = window[["xmin"]], xmax = window[["xmax"]],
    ymin = window[["ymin"]], ymax = window[["ymax"]],
    resolution = 0.1, crs = "EPSG:4326"
  )
  field <- terra::init(field, "y")
  out <- terra::project(field, like, method = "bilinear")
  names(out) <- "latitude"
  out
}

#' twi, northness and heat_load from an elevation raster in the grid's CRS.
#'
#' Sea is filled as 0 before anything that looks at a cell's neighbours, as
#' the terrain layer does, so a shoreline is not lost; the land mask is
#' restored at the end.
atlas_landform_from_elevation <- function(elevation) {
  land <- terra::ifel(is.na(elevation), 0, elevation)
  slope <- terra::terrain(land, v = "slope", unit = "degrees")
  aspect <- terra::terrain(land, v = "aspect", unit = "degrees")

  directions <- suppressWarnings(terra::flowDir(land))
  upslope <- terra::flowAccumulation(directions)
  twi <- terra::lapp(
    c(upslope, slope),
    function(u, s) atlas_wetness_index(u, terra::res(elevation)[[1]], s)
  )

  northness <- terra::lapp(c(slope, aspect), atlas_northness)

  heat <- terra::lapp(c(atlas_latitude_raster(elevation), slope, aspect), atlas_heat_load)

  out <- c(twi, northness, heat)
  names(out) <- c("twi", "northness", "heat_load")
  terra::mask(out, elevation)
}

#' The 1 km landform bands, computed once and kept with the raw downloads.
#'
#' Needs the production elevation layer, whichever grid is being built: see
#' the top of this file for why.
atlas_landform_source <- function(raw_dir) {
  cached <- file.path(raw_dir, "landform", "landform-1km.tif")
  if (file.exists(cached)) {
    return(terra::rast(cached))
  }
  elevation_path <- atlas_layer_path("elevation", "production")
  if (!file.exists(elevation_path)) {
    stop("landform is computed from the production elevation layer: ",
         "run atlas build-layers --grid=production elevation first", call. = FALSE)
  }
  dir.create(dirname(cached), recursive = TRUE, showWarnings = FALSE)
  out <- atlas_landform_from_elevation(terra::rast(elevation_path))
  terra::writeRaster(out, cached, overwrite = TRUE,
                     gdal = c("COMPRESS=DEFLATE", "TILED=YES", "BIGTIFF=IF_SAFER"))
  terra::rast(cached)
}
