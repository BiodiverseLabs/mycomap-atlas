# Training data: where a taxon was found, and where people looked and did not.
#
# Six states and provinces hold 61% of the records, and Indiana alone holds
# 12%. Drawn at random from the continent, background points would say that
# Indiana's climate is unusually good for almost every fungus, because that is
# where the sequencing happened.
#
# So the comparison is drawn from the records themselves — every DNA-validated
# collection of every taxon, the "target group". They share one process:
# somebody collected, somebody sequenced, somebody validated. A model fitted
# against them answers a better question: given that people collected and
# sequenced here, was this species among what they found?
#
# Both sides are counted in survey sites (R/sites.R): a detection is a site
# where the taxon was collected, a non-detection a site where other things
# were collected but not it. How hard a site was worked is not counted by
# repeating it, which confused effort with habitat, but carried as its own
# predictor, effort = log(records at the site), and held at one value when a
# map is drawn. Sites are drawn only from the taxon's accessible area, not the
# continent: a species is not absent from Yukon because nobody looked there.

#' Project every record onto the grid once, and gather the records into survey
#' sites, so a run over many taxa does neither for each of them.
atlas_occurrence_points <- function(occurrences, grid = "draft", thin_km = ATLAS_SITE_KM) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed for training data: install.packages('terra')", call. = FALSE)
  }
  template <- atlas_grid_template(grid)
  xy <- atlas_project_points(occurrences$latitude, occurrences$longitude)
  cells <- terra::cellFromXY(template, xy)
  keep <- !is.na(cells)
  centres <- terra::xyFromCell(template, cells[keep])
  points <- data.frame(
    scientific_name = occurrences$scientific_name[keep],
    cell = cells[keep],
    x = centres[, 1],
    y = centres[, 2],
    stringsAsFactors = FALSE
  )
  atlas_attach_sites(points, thin_km)
}

#' The ground a taxon could plausibly have reached: its sites, buffered.
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
#' The same taxon with the same records always draws the same sites, and a
#' changed record set draws a new one — which is what a release manifest has to
#' be able to claim.
atlas_seed_from_fingerprint <- function(fingerprint) {
  if (is.null(fingerprint) || !length(fingerprint) || !nzchar(fingerprint[[1]])) {
    return(1L)
  }
  as.integer(strtoi(substr(as.character(fingerprint[[1]]), 1, 7), base = 16L))
}

#' Draw non-detection sites inside the accessible area.
#'
#' Every site counts once, however many records it holds: effort is a
#' predictor now, not a weight. Past n, sites are drawn at random.
atlas_background_sample <- function(pool, area, n = 10000, seed = 1L) {
  inside <- atlas_points_in_area(pool$x, pool$y, area)
  candidates <- pool[inside, , drop = FALSE]
  if (!nrow(candidates)) {
    stop("no surveyed sites inside the accessible area", call. = FALSE)
  }
  if (nrow(candidates) <= n) {
    return(candidates)
  }
  set.seed(seed)
  candidates[sort(sample.int(nrow(candidates), n)), , drop = FALSE]
}

#' Detections and non-detections for one taxon, ready to fit.
#'
#' One row per site: presence is 1 where the taxon was collected, effort is
#' log(records at the site), and cell, x and y are the site's centre, where
#' its predictors are read.
atlas_training_table <- function(name, points, n_background = 10000,
                                 buffer_km = 500, fingerprint = NULL,
                                 thin_km = ATLAS_SITE_KM) {
  points <- atlas_ensure_sites(points, thin_km)
  sites <- attr(points, "sites")
  found <- unique(points$site[points$scientific_name == name])
  if (!length(found)) {
    stop("no records on the grid for ", name, call. = FALSE)
  }
  columns <- c("cell", "x", "y")
  presences <- sites[found, , drop = FALSE]
  area <- atlas_accessible_area(presences$x, presences$y, buffer_km)
  seed <- atlas_seed_from_fingerprint(fingerprint)
  others <- sites[-found, , drop = FALSE]
  background <- if (nrow(others)) {
    atlas_background_sample(others, area, n = n_background, seed = seed)
  } else {
    others
  }
  out <- rbind(
    data.frame(presence = rep(1L, nrow(presences)), presences[, columns, drop = FALSE],
               effort = log(presences$records), stringsAsFactors = FALSE),
    data.frame(presence = rep(0L, nrow(background)), background[, columns, drop = FALSE],
               effort = log(background$records), stringsAsFactors = FALSE)
  )
  rownames(out) <- NULL
  attr(out, "area_km2") <- unname(terra::expanse(area, unit = "km"))
  attr(out, "seed") <- seed
  attr(out, "fingerprint") <- if (is.null(fingerprint)) NA_character_ else fingerprint
  attr(out, "thin_km") <- thin_km
  out
}

#' Where a taxon's training table is written. Provisional names carry quotes
#' and full stops, so the file name is built from the letters and digits.
atlas_training_path <- function(name, grid = "draft") {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  atlas_path("training", grid, paste0(slug, ".tsv.gz"))
}

#' Pull, project, draw the background and attach the predictors, for one taxon.
#'
#' A batch run passes in the projected points, the stack and the taxon's
#' fingerprint, all computed once, so nothing here rereads the pull.
atlas_build_training <- function(name, grid = "draft", n_background = 10000,
                                 buffer_km = 500, write = TRUE, quiet = FALSE,
                                 points = NULL, stack = NULL,
                                 occurrences = NULL, fingerprint = NULL,
                                 thin_km = ATLAS_SITE_KM) {
  if (is.null(points) || is.null(fingerprint)) {
    occurrences <- occurrences %||% atlas_read_occurrences()
    focal <- occurrences[occurrences$scientific_name == name, , drop = FALSE]
    if (!nrow(focal)) {
      stop("no records for ", name, " in the current pull", call. = FALSE)
    }
    fingerprint <- fingerprint %||% atlas_fingerprint(focal)
    points <- points %||% atlas_occurrence_points(occurrences, grid)
  }
  table <- atlas_training_table(
    name, points,
    n_background = n_background, buffer_km = buffer_km,
    fingerprint = fingerprint, thin_km = thin_km
  )
  table <- atlas_add_predictors(table, grid, stack = stack)

  path <- NULL
  if (isTRUE(write)) {
    path <- atlas_training_path(name, grid)
    atlas_write_tsv_gz(table, path)
  }

  if (!isTRUE(quiet)) {
    message(name)
    message("  detection sites:    ", sum(table$presence == 1L))
    message("  other sites:        ", sum(table$presence == 0L))
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
  attr(out, "fingerprint") <- attr(table, "fingerprint")
  attr(out, "thin_km") <- attr(table, "thin_km")
  attr(out, "dropped") <- sum(!complete)
  out
}
