# Survey sites: the unit every model counts in.
#
# A model compares places where a fungus was found with places people looked
# and did not find it. Both sides have to be counted in the same unit, or the
# comparison measures the counting rather than the fungus. An earlier design
# counted presences once per grid cell but drew the background once per
# record, so a much-collected wood was one presence and a hundred background
# points: for nearly every species, the best-surveyed ground looked worse than
# it was.
#
# So every record is first gathered into a survey site. Sites are made once
# from the whole pull, before any species is looked at: cells with records are
# thinned by distance, busiest first, so no two sites are closer than thin_km,
# and every other cell joins its nearest site. A site's effort is the number
# of records gathered into it. The spacing is in kilometres, not cells, so the
# 1 km grid does not turn one foray into five presences where the 5 km grid
# saw one. With a 5 km spacing on the 5 km grid, a site is exactly a cell:
# neighbouring cell centres are 5 km apart, which is not closer than 5 km.
#
# For one species, a site is a detection when any of its records is that
# species, and a non-detection otherwise. Effort goes into every model as a
# predictor (log records at the site) and is held at one value when a map is
# drawn or scored, so the map shows habitat and effort explains the rest
# (Warton, Renner & Ramp 2013; Fithian et al. 2015).

# Minimum distance between two sites, in km. A foray covers a few kilometres.
ATLAS_SITE_KM <- 5

#' Greedy distance thinning: which rows become site centres, and which centre
#' every row belongs to.
#'
#' Rows are visited busiest first (ties by cell), and a row becomes a centre
#' when no centre already chosen is closer than distance. Every row then joins
#' its nearest centre. Buckets of the thinning distance keep each check to the
#' nine buckets around a row, so this is linear in the number of cells.
atlas_thin_by_distance <- function(x, y, weight, distance, order_key = seq_along(x)) {
  n <- length(x)
  if (!n) return(list(centre = logical(), site_of = integer()))
  bx <- floor(x / distance)
  by <- floor(y / distance)
  key <- function(i, j) paste(i, j)
  buckets <- new.env(hash = TRUE, parent = emptyenv())
  visit <- order(-weight, order_key)
  centre <- logical(n)
  near <- function(i) {
    found <- integer()
    for (dx in -1:1) for (dy in -1:1) {
      found <- c(found, buckets[[key(bx[i] + dx, by[i] + dy)]])
    }
    found
  }
  for (i in visit) {
    others <- near(i)
    if (length(others) &&
        any((x[others] - x[i])^2 + (y[others] - y[i])^2 < distance^2)) {
      next
    }
    centre[i] <- TRUE
    k <- key(bx[i], by[i])
    buckets[[k]] <- c(buckets[[k]], i)
  }
  site_of <- integer(n)
  for (i in seq_len(n)) {
    if (centre[i]) {
      site_of[i] <- i
      next
    }
    others <- near(i)
    site_of[i] <- others[which.min((x[others] - x[i])^2 + (y[others] - y[i])^2)]
  }
  list(centre = centre, site_of = site_of)
}

#' Gather every record of the pull into survey sites.
#'
#' Returns the points with a site column added and the sites table attached as
#' attr(, "sites"): one row per site, with its centre cell and the records
#' (effort) gathered into it. Only the full table carries the attribute;
#' subsetting a data frame drops it.
atlas_attach_sites <- function(points, thin_km = ATLAS_SITE_KM) {
  if (!nrow(points)) {
    points$site <- integer()
    attr(points, "sites") <- data.frame(site = integer(), cell = numeric(),
                                        x = numeric(), y = numeric(),
                                        records = integer())
    attr(points, "thin_km") <- thin_km
    return(points)
  }
  first <- !duplicated(points$cell)
  cells <- points[first, c("cell", "x", "y"), drop = FALSE]
  cells$records <- as.integer(table(factor(points$cell, levels = cells$cell)))
  thinned <- atlas_thin_by_distance(
    cells$x, cells$y, cells$records, thin_km * 1000, order_key = cells$cell
  )
  centres <- which(thinned$centre)
  site_number <- match(thinned$site_of, centres)
  records <- as.integer(tapply(cells$records, site_number, sum)[as.character(seq_along(centres))])
  sites <- data.frame(
    site = seq_along(centres),
    cell = cells$cell[centres],
    x = cells$x[centres],
    y = cells$y[centres],
    records = records,
    stringsAsFactors = FALSE
  )
  points$site <- site_number[match(points$cell, cells$cell)]
  attr(points, "sites") <- sites
  attr(points, "thin_km") <- thin_km
  points
}

#' The points with their sites, gathering them first when that has not been
#' done at this spacing. A batch does it once and hands the result round.
atlas_ensure_sites <- function(points, thin_km = ATLAS_SITE_KM) {
  # The records gathered into the sites must be exactly these points: a
  # subset that somehow kept the attribute would otherwise use stale sites.
  sites <- attr(points, "sites")
  if (!is.null(sites) && "site" %in% names(points) &&
      identical(as.numeric(attr(points, "thin_km")), as.numeric(thin_km)) &&
      sum(sites$records) == nrow(points)) {
    return(points)
  }
  atlas_attach_sites(points, thin_km)
}

#' Detection sites per taxon, most first: the count a map's minimum is about.
atlas_presence_site_counts <- function(points, thin_km = ATLAS_SITE_KM) {
  if (is.null(points) || !nrow(points)) {
    return(data.frame(scientific_name = character(), cells = integer(),
                      stringsAsFactors = FALSE))
  }
  points <- atlas_ensure_sites(points, thin_km)
  distinct <- points[!duplicated(points[, c("scientific_name", "site")]), , drop = FALSE]
  counts <- table(distinct$scientific_name)
  # The column keeps the name "cells" that batches, studies and the API read.
  out <- data.frame(
    scientific_name = names(counts),
    cells = as.integer(counts),
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$cells, out$scientific_name), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# How far apart blocks for cross-validation should be, in km, when blockCV
# measures it. Below the floor, one foray's cluster could straddle a boundary;
# above the ceiling, a 500 km accessible area holds too few blocks to fold.
ATLAS_BLOCK_FLOOR_KM <- 50
ATLAS_BLOCK_CEILING_KM <- 300
# Used when blockCV is not installed or cannot fit a variogram.
ATLAS_BLOCK_FALLBACK_KM <- 200

#' Block size for cross-validation, from how far the taxon's detections are
#' spatially autocorrelated.
#'
#' blockCV fits a variogram to detection/non-detection across the taxon's
#' sites; beyond its range, two sites say little about each other, so a block
#' that wide keeps the held-out region honest (Roberts et al. 2017; Valavi et
#' al. 2019). Autocorrelation of the predictors was measured too, and over a
#' continent it runs to thousands of km for climate, which would leave no
#' blocks at all. The estimate is rounded to 5 km and held between the floor
#' and the ceiling; a variogram that does not settle gives the ceiling.
atlas_block_size <- function(training, seed = 1L, floor_km = ATLAS_BLOCK_FLOOR_KM,
                             ceiling_km = ATLAS_BLOCK_CEILING_KM,
                             fallback_km = ATLAS_BLOCK_FALLBACK_KM) {
  fallback <- list(block_km = fallback_km, range_km = NA_real_, source = "fallback")
  if (!requireNamespace("blockCV", quietly = TRUE) ||
      !requireNamespace("sf", quietly = TRUE)) {
    return(fallback)
  }
  if (length(unique(training$presence)) < 2L) {
    return(fallback)
  }
  points <- sf::st_as_sf(
    data.frame(x = training$x, y = training$y, presence = training$presence),
    coords = c("x", "y"), crs = ATLAS_CRS
  )
  set.seed(seed)
  # blockCV prints its variogram summary; the range is all that is kept.
  measured <- tryCatch(
    {
      utils::capture.output(result <- suppressMessages(suppressWarnings(
        blockCV::cv_spatial_autocor(
          x = points, column = "presence", plot = FALSE, progress = FALSE
        )
      )))
      result
    },
    error = function(e) NULL
  )
  range_km <- if (is.null(measured)) NA_real_ else as.numeric(measured$range) / 1000
  if (!length(range_km) || !is.finite(range_km) || range_km <= 0) {
    return(fallback)
  }
  block <- 5 * round(range_km / 5)
  list(
    block_km = min(ceiling_km, max(floor_km, block)),
    range_km = round(range_km, 1),
    source = "blockCV"
  )
}

#' The block each row falls in, as a label.
atlas_block_labels <- function(x, y, block_km) {
  paste(floor(x / (block_km * 1000)), floor(y / (block_km * 1000)), sep = ":")
}

#' How many blocks hold at least one detection.
atlas_presence_blocks <- function(training, block_km) {
  length(unique(atlas_block_labels(
    training$x[training$presence == 1L], training$y[training$presence == 1L], block_km
  )))
}
