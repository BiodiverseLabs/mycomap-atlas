# Training data: presences, and the background they are compared against.
#
# Six states and provinces hold 61% of the records, and Indiana alone holds
# 12%. Drawn at random from the continent, background points would say that
# Indiana's climate is unusually good for almost every fungus, because that is
# where the sequencing happened.
#
# So the background is drawn from the records themselves — every DNA-validated
# collection of every taxon, the "target group". They share one process:
# somebody collected, somebody sequenced, somebody validated. A model fitted
# against that background answers a better question: given that a fungus was
# collected and sequenced here, what makes it this species rather than another?
#
# Two details matter. The background keeps its density, so a cell visited a
# hundred times counts a hundred times — that is the effort signal, not noise.
# And it is drawn from the focal taxon's accessible area, not the continent: a
# species is not absent from Yukon because nobody looked, and a model should
# not be asked about ground its subject could never reach.

#' Project every record onto the grid once, so a run over many taxa does not
#' reproject the whole pull for each of them.
atlas_occurrence_points <- function(occurrences, grid = "draft") {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed for training data: install.packages('terra')", call. = FALSE)
  }
  template <- atlas_grid_template(grid)
  xy <- atlas_project_points(occurrences$latitude, occurrences$longitude)
  cells <- terra::cellFromXY(template, xy)
  keep <- !is.na(cells)
  centres <- terra::xyFromCell(template, cells[keep])
  data.frame(
    scientific_name = occurrences$scientific_name[keep],
    cell = cells[keep],
    x = centres[, 1],
    y = centres[, 2],
    stringsAsFactors = FALSE
  )
}

#' One row per occupied cell. Repeat visits to a site are one presence, not
#' twenty, or the model learns the collector's habits.
atlas_thin_to_cells <- function(points) {
  points[!duplicated(points$cell), c("cell", "x", "y"), drop = FALSE]
}

#' The ground a taxon could plausibly have reached: its cells, buffered.
atlas_accessible_area <- function(x, y, buffer_km = 500) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed for training data: install.packages('terra')", call. = FALSE)
  }
  if (!length(x)) {
    stop("an accessible area needs at least one point", call. = FALSE)
  }
  points <- terra::vect(cbind(x, y), crs = ATLAS_CRS)
  terra::aggregate(terra::buffer(points, width = buffer_km * 1000))
}

#' Which points fall inside an area.
atlas_points_in_area <- function(x, y, area) {
  points <- terra::vect(cbind(x, y), crs = ATLAS_CRS)
  as.vector(terra::relate(points, area, "intersects"))
}

#' A seed tied to the data, not to the clock.
#'
#' The same taxon with the same records always draws the same background, and a
#' changed record set draws a new one — which is what a release manifest has to
#' be able to claim.
atlas_seed_from_fingerprint <- function(fingerprint) {
  if (is.null(fingerprint) || !length(fingerprint) || !nzchar(fingerprint[[1]])) {
    return(1L)
  }
  as.integer(strtoi(substr(as.character(fingerprint[[1]]), 1, 7), base = 16L))
}

#' Draw background records from the target group, inside the accessible area.
#'
#' Sampling records rather than cells is deliberate: a cell that was collected
#' from a hundred times should appear a hundred times as often.
atlas_background_sample <- function(pool, area, n = 10000, seed = 1L) {
  inside <- atlas_points_in_area(pool$x, pool$y, area)
  candidates <- pool[inside, , drop = FALSE]
  if (!nrow(candidates)) {
    stop("no target-group records inside the accessible area", call. = FALSE)
  }
  if (nrow(candidates) <= n) {
    return(candidates)
  }
  set.seed(seed)
  candidates[sample.int(nrow(candidates), n), , drop = FALSE]
}

#' Presences and background for one taxon, ready to fit.
atlas_training_table <- function(name, points, n_background = 10000,
                                 buffer_km = 500, fingerprint = NULL) {
  focal <- points[points$scientific_name == name, , drop = FALSE]
  if (!nrow(focal)) {
    stop("no records on the grid for ", name, call. = FALSE)
  }
  presences <- atlas_thin_to_cells(focal)
  area <- atlas_accessible_area(presences$x, presences$y, buffer_km)
  seed <- atlas_seed_from_fingerprint(fingerprint)
  background <- atlas_background_sample(
    pool = points[, c("cell", "x", "y"), drop = FALSE],
    area = area, n = n_background, seed = seed
  )
  out <- rbind(
    data.frame(presence = 1L, presences, stringsAsFactors = FALSE),
    data.frame(presence = 0L, background, stringsAsFactors = FALSE)
  )
  rownames(out) <- NULL
  attr(out, "area_km2") <- unname(terra::expanse(area, unit = "km"))
  attr(out, "seed") <- seed
  out
}

#' Where a taxon's training table is written. Provisional names carry quotes
#' and full stops, so the file name is built from the letters and digits.
atlas_training_path <- function(name, grid = "draft") {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  atlas_path("training", grid, paste0(slug, ".tsv.gz"))
}

#' Pull, project, draw the background and attach the predictors, for one taxon.
atlas_build_training <- function(name, grid = "draft", n_background = 10000,
                                 buffer_km = 500, write = TRUE, quiet = FALSE,
                                 points = NULL, stack = NULL) {
  occurrences <- atlas_read_occurrences()
  focal <- occurrences[occurrences$scientific_name == name, , drop = FALSE]
  if (!nrow(focal)) {
    stop("no records for ", name, " in the current pull", call. = FALSE)
  }
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  table <- atlas_training_table(
    name, points,
    n_background = n_background, buffer_km = buffer_km,
    fingerprint = atlas_fingerprint(focal)
  )
  table <- atlas_add_predictors(table, grid, stack = stack)

  path <- NULL
  if (isTRUE(write)) {
    path <- atlas_training_path(name, grid)
    atlas_write_tsv_gz(table, path)
  }

  if (!isTRUE(quiet)) {
    message(name)
    message("  presences (cells):  ", sum(table$presence == 1L))
    message("  background:         ", sum(table$presence == 0L))
    message("  accessible area:    ",
            format(round(attr(table, "area_km2")), big.mark = ","), " km2")
    message("  predictors:         ",
            ncol(table) - 4L)
    message("  cells without data: ", attr(table, "dropped"))
    message("  seed:               ", attr(table, "seed"))
    if (!is.null(path)) message("  written:            ", path)
  }
  invisible(table)
}

#' Every built layer for a grid, as one stack.
atlas_predictor_stack <- function(grid = "draft") {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed for training data: install.packages('terra')", call. = FALSE)
  }
  manifest <- atlas_layer_manifest(grid)
  if (!length(manifest)) {
    stop("no layers built for the ", grid, " grid: run atlas build-layers", call. = FALSE)
  }
  ids <- vapply(manifest, function(x) as.character(x$id), character(1))
  terra::rast(vapply(ids, atlas_layer_path, character(1), grid = grid, USE.NAMES = FALSE))
}

#' Add the predictors to a training table, dropping rows the layers cannot
#' describe — coastal and island cells, mostly.
atlas_add_predictors <- function(table, grid = "draft", stack = NULL) {
  stack <- stack %||% atlas_predictor_stack(grid)
  values <- terra::extract(stack, as.matrix(table[, c("x", "y")]))
  values <- values[, setdiff(names(values), "ID"), drop = FALSE]
  complete <- stats::complete.cases(values)

  out <- cbind(table, values)[complete, , drop = FALSE]
  rownames(out) <- NULL
  attr(out, "area_km2") <- attr(table, "area_km2")
  attr(out, "seed") <- attr(table, "seed")
  attr(out, "dropped") <- sum(!complete)
  out
}
