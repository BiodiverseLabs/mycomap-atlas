# A synthetic world where the answer is known: suitability peaks at v1 = 1 and
# falls away from it, and v2 says nothing at all. A fit that cannot recover
# that is broken, however plausible its output looks.
simulated_training <- function(n_background = 2000, n_presence = 200, seed = 42) {
  set.seed(seed)
  background <- data.frame(
    v1 = stats::runif(n_background, -3, 3),
    v2 = stats::runif(n_background, -3, 3)
  )
  truth <- exp(-((background$v1 - 1)^2) / 0.5)
  drawn <- sample.int(n_background, n_presence, replace = TRUE, prob = truth)
  rbind(
    data.frame(presence = 1L, cell = seq_len(n_presence), x = 0, y = 0,
               background[drawn, , drop = FALSE]),
    data.frame(presence = 0L, cell = seq_len(n_background) + n_presence,
               x = 0, y = 0, background)
  )
}

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

# A synthetic pool on the grid: cell centres in the projected CRS, so no test
# here needs a layer, a network or the real pull.
fake_points <- function(x, y, names = "Target group", cells = NULL) {
  data.frame(
    scientific_name = rep_len(names, length(x)),
    cell = if (is.null(cells)) seq_along(x) else cells,
    x = x, y = y,
    stringsAsFactors = FALSE
  )
}
