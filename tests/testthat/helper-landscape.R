# A 1,000 km square in the grid's projection with two predictors: v1 rises
# west to east, v2 is noise. The taxon lives only in the east.
synthetic_landscape <- function() {
  set.seed(7)
  stack <- terra::rast(
    nrows = 200, ncols = 200, xmin = 0, xmax = 1e6, ymin = 0, ymax = 1e6,
    crs = ATLAS_CRS, nlyrs = 2
  )
  names(stack) <- c("v1", "v2")
  xy <- terra::xyFromCell(stack, seq_len(terra::ncell(stack)))
  terra::values(stack) <- cbind(xy[, 1] / 1e5, stats::runif(nrow(xy)))

  background <- data.frame(
    scientific_name = "Everything else",
    x = stats::runif(800, 0, 1e6), y = stats::runif(800, 0, 1e6)
  )
  focal <- data.frame(
    scientific_name = "Eastern fungus",
    x = stats::runif(60, 8e5, 1e6), y = stats::runif(60, 0, 1e6)
  )
  points <- rbind(background, focal)
  points$cell <- terra::cellFromXY(stack, as.matrix(points[, c("x", "y")]))
  centres <- terra::xyFromCell(stack, points$cell)
  points$x <- centres[, 1]
  points$y <- centres[, 2]
  list(stack = stack, points = points[, c("scientific_name", "cell", "x", "y")])
}
