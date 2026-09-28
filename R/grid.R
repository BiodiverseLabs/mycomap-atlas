# The modelling grid.
#
# North America Albers Equal Area Conic, so a cell covers the same ground
# everywhere. That matters twice over: predicted habitat is reported in km²,
# and spatial blocking needs real distances. A degree grid would make a cell in
# northern Canada a third the size of one in Mexico, which is how .org's
# current area-of-occupancy figures drift.
#
# The extent is the projection of longitudes -170 to -52 and latitudes 14 to
# 72, rounded outward to 5 km. It holds the mainland, Alaska (except the far
# western Aleutians), Hawaii, Puerto Rico and the Virgin Islands.

ATLAS_CRS <- paste(
  "+proj=aea +lat_0=40 +lon_0=-96 +lat_1=20 +lat_2=60",
  "+x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs"
)

ATLAS_GRID_EXTENT <- c(
  xmin = -7445000, xmax = 4735000,
  ymin = -2955000, ymax = 4740000
)

# Two grids over the same extent and origin, so their cells nest exactly: a
# draft grid to develop the pipeline against, and the production grid that
# releases are built on.
ATLAS_GRID_RESOLUTIONS <- c(draft = 5000, production = 1000)

#' Cell size in metres for a named grid.
atlas_resolution <- function(grid = "draft") {
  if (!is.character(grid) || length(grid) != 1 || !grid %in% names(ATLAS_GRID_RESOLUTIONS)) {
    stop("grid must be one of: ", paste(names(ATLAS_GRID_RESOLUTIONS), collapse = ", "),
         call. = FALSE)
  }
  unname(ATLAS_GRID_RESOLUTIONS[[grid]])
}

#' Rows, columns and cell count for a named grid.
atlas_grid_size <- function(grid = "draft") {
  res <- atlas_resolution(grid)
  ncol <- (ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / res
  nrow <- (ATLAS_GRID_EXTENT[["ymax"]] - ATLAS_GRID_EXTENT[["ymin"]]) / res
  list(nrow = nrow, ncol = ncol, cells = nrow * ncol)
}

#' An empty raster on a named grid, used as the target for every layer.
atlas_grid_template <- function(grid = "draft") {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed for grid work: install.packages('terra')", call. = FALSE)
  }
  terra::rast(
    xmin = ATLAS_GRID_EXTENT[["xmin"]], xmax = ATLAS_GRID_EXTENT[["xmax"]],
    ymin = ATLAS_GRID_EXTENT[["ymin"]], ymax = ATLAS_GRID_EXTENT[["ymax"]],
    resolution = atlas_resolution(grid),
    crs = ATLAS_CRS
  )
}

#' Project longitude/latitude onto the grid's coordinates, in metres.
atlas_project_points <- function(lat, lng) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed for grid work: install.packages('terra')", call. = FALSE)
  }
  points <- cbind(x = as.numeric(lng), y = as.numeric(lat))
  colnames(points) <- c("x", "y")
  projected <- terra::project(
    terra::vect(points, crs = "EPSG:4326"), ATLAS_CRS
  )
  terra::crds(projected)
}

#' Which records fall inside the grid. A record outside it cannot be modelled.
atlas_grid_covers <- function(lat, lng) {
  xy <- atlas_project_points(lat, lng)
  xy[, 1] >= ATLAS_GRID_EXTENT[["xmin"]] & xy[, 1] <= ATLAS_GRID_EXTENT[["xmax"]] &
    xy[, 2] >= ATLAS_GRID_EXTENT[["ymin"]] & xy[, 2] <= ATLAS_GRID_EXTENT[["ymax"]]
}
