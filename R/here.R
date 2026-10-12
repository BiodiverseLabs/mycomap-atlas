# What could grow here? Every fungus whose maps rate a place highly.
#
# Asking 2,700 map rasters about one point takes a minute, so the answer
# comes from an index built once from the published maps. The continent is
# cut into square cells (20 km on the draft grid) aligned with the Atlas
# grid, and for each model the index keeps the cells where that model ranks
# the ground in the top half of its own accessible area, with the rank as a
# whole percentage. The bottom half is left out: ground a model rates below
# its median is not an answer to "could it grow here", and dropping it halves
# the index.
#
# The rank is the one the maps are coloured by, taken among the cells inside
# each map's area of applicability (R/aoa.R), so "top 5% here" on this page
# and the darkest green on a species' map say the same thing, and ground a
# map knows nothing about is never "here". A taxon's score
# at a place is the mean of its models' ranks there, a model that does not
# rate the place in its top half counting as zero: one keen model among three
# indifferent ones does not put a species at the top of the list.
#
# Only maps that beat their null models go in (R/fit.R): a map that cannot
# tell a fungus from a random handful of collections still has a top half, and
# would put the species everywhere.
#
# The index holds ranks by cell, nothing about records, and is published
# with the maps. "Recorded nearby" comes from the 0.1 degree public cells,
# never from coordinates.

ATLAS_HERE_CELL_KM <- 20
ATLAS_HERE_MIN_RANK <- 50L

atlas_here_index_path <- function(grid = "draft") {
  atlas_path("index", grid, "here.rds")
}

# ---- projection ------------------------------------------------------------

#' Longitude/latitude to the Atlas grid's metres, without terra.
#'
#' North America Albers Equal Area Conic on the GRS80 ellipsoid (NAD83), by
#' Snyder's formulas (Map Projections: A Working Manual, 1987, pp. 101-102).
#' The API answers a click with this, so the web server needs no GDAL; a test
#' holds it to terra's answer.
atlas_albers <- function(lat, lng) {
  a <- 6378137
  f <- 1 / 298.257222101
  e2 <- 2 * f - f^2
  e <- sqrt(e2)
  rad <- pi / 180
  q <- function(phi) {
    s <- sin(phi)
    (1 - e2) * (s / (1 - e2 * s^2) - (1 / (2 * e)) * log((1 - e * s) / (1 + e * s)))
  }
  m <- function(phi) cos(phi) / sqrt(1 - e2 * sin(phi)^2)
  phi0 <- 40 * rad
  phi1 <- 20 * rad
  phi2 <- 60 * rad
  lambda0 <- -96 * rad
  n <- (m(phi1)^2 - m(phi2)^2) / (q(phi2) - q(phi1))
  C <- m(phi1)^2 + n * q(phi1)
  rho0 <- a * sqrt(C - n * q(phi0)) / n
  rho <- a * sqrt(C - n * q(lat * rad)) / n
  theta <- n * (lng * rad - lambda0)
  cbind(x = rho * sin(theta), y = rho0 - rho * cos(theta))
}

#' The index cell a grid coordinate falls in, or NA outside the grid.
atlas_here_cell <- function(x, y, cell_km = ATLAS_HERE_CELL_KM) {
  size <- cell_km * 1000
  ncol <- ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size)
  col <- floor((x - ATLAS_GRID_EXTENT[["xmin"]]) / size)
  row <- floor((ATLAS_GRID_EXTENT[["ymax"]] - y) / size)
  inside <- x >= ATLAS_GRID_EXTENT[["xmin"]] & x < ATLAS_GRID_EXTENT[["xmax"]] &
    y > ATLAS_GRID_EXTENT[["ymin"]] & y <= ATLAS_GRID_EXTENT[["ymax"]]
  ifelse(inside, row * ncol + col + 1, NA_real_)
}

# ---- building the index ----------------------------------------------------

#' One model's ranks by index cell: for each 20 km cell its map reaches, the
#' mean rank of its 5 km cells inside the area of applicability, as a whole
#' percentage, or NA where all of them are outside it.
#'
#' The rank is the one the map is coloured by (atlas_map_layers): taken among
#' the cells inside the area of applicability, so ground the model knows
#' nothing about neither scores nor shifts the ranks of ground it does. Without
#' a dissimilarity layer every cell with a value is inside.
atlas_model_cell_ranks <- function(raster, dissimilarity = NULL, threshold = NULL,
                                   cell_km = ATLAS_HERE_CELL_KM) {
  r <- if (is.character(raster)) terra::rast(raster) else raster
  if (is.character(dissimilarity)) {
    dissimilarity <- if (file.exists(dissimilarity)) terra::rast(dissimilarity) else NULL
  }
  layers <- atlas_map_layers(r, dissimilarity, threshold)
  rank <- terra::values(layers[["rank"]], mat = FALSE)
  reached <- which(is.finite(terra::values(layers[["outside"]], mat = FALSE)))
  empty <- data.frame(cell = integer(), rank = integer())
  if (!length(reached)) return(empty)
  xy <- terra::xyFromCell(r, reached)
  cell <- atlas_here_cell(xy[, 1], xy[, 2], cell_km)
  rank <- rank[reached]
  keep <- !is.na(cell)
  cell <- cell[keep]
  rank <- rank[keep]
  if (!length(cell)) return(empty)
  out <- data.frame(cell = as.integer(sort(unique(cell))), rank = NA_integer_)
  inside <- is.finite(rank)
  if (any(inside)) {
    sums <- rowsum(rank[inside], cell[inside])
    counts <- rowsum(rep(1, sum(inside)), cell[inside])
    out$rank[match(as.integer(rownames(sums)), out$cell)] <- as.integer(round(100 * sums[, 1] / counts[, 1]))
  }
  out
}

#' One model's contribution to the index: the cells where it ranks the
#' ground at least min_rank.
atlas_here_model_cells <- function(raster, cell_km = ATLAS_HERE_CELL_KM,
                                   min_rank = ATLAS_HERE_MIN_RANK,
                                   dissimilarity = NULL, threshold = NULL) {
  ranks <- atlas_model_cell_ranks(raster, dissimilarity, threshold, cell_km)
  ranks <- ranks[!is.na(ranks$rank) & ranks$rank >= min_rank, , drop = FALSE]
  rownames(ranks) <- NULL
  ranks
}

#' The maps the index and the prior are built from: every strong map, with
#' where its raster, dissimilarity layer and threshold are.
#'
#' Only strong maps, which beat nulls that keep their clustering: one that
#' cannot tell a fungus from its own collecting pattern moved elsewhere has
#' nothing to say about a place (atlas_map_grade).
atlas_strong_maps <- function(grid = "draft") {
  models <- atlas_model_index(grid)
  models <- models[models$map & models$grade %in% "strong", c("taxon", "algorithm", "presences"), drop = FALSE]
  rownames(models) <- NULL
  if (!nrow(models)) return(models)
  models$raster <- vapply(seq_len(nrow(models)), function(i) {
    atlas_model_path(models$taxon[[i]], grid, ".tif", models$algorithm[[i]])
  }, "")
  models$dissimilarity <- vapply(seq_len(nrow(models)), function(i) {
    atlas_model_path(models$taxon[[i]], grid, ".di.tif", models$algorithm[[i]])
  }, "")
  models$threshold <- vapply(seq_len(nrow(models)), function(i) {
    metrics <- atlas_read_metrics(models$taxon[[i]], grid, models$algorithm[[i]])
    as.numeric(metrics$applicability$threshold %||% NA)
  }, numeric(1))
  models
}

#' Every strong map's ranks by index cell, read once: the "what could grow
#' here" index and the location prior (R/prior.R) are both built from this.
atlas_strong_map_cells <- function(grid = "draft", cell_km = ATLAS_HERE_CELL_KM,
                                   models = atlas_strong_maps(grid), quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  cells <- vector("list", nrow(models))
  for (i in seq_len(nrow(models))) {
    if (file.exists(models$raster[[i]])) {
      cells[[i]] <- atlas_model_cell_ranks(models$raster[[i]], models$dissimilarity[[i]],
                                           models$threshold[[i]], cell_km)
    }
    if (i %% 250 == 0) say("  read ", i, " of ", nrow(models), " maps")
  }
  list(models = models, cells = cells, cell_km = cell_km)
}

#' Build the index from every strong map on a grid.
#'
#' Stored cell by cell: for index cell i, entries start[i] to start[i+1]-1
#' of model and rank. A lookup is then two numbers and a slice. strong is
#' atlas_strong_map_cells(), read here unless it is passed in.
atlas_build_here_index <- function(grid = "draft", cell_km = ATLAS_HERE_CELL_KM,
                                   min_rank = ATLAS_HERE_MIN_RANK, quiet = FALSE,
                                   strong = NULL) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  started <- Sys.time()
  strong <- strong %||% atlas_strong_map_cells(grid, cell_km, quiet = quiet)
  cell_km <- strong$cell_km
  models <- strong$models[, c("taxon", "algorithm"), drop = FALSE]
  if (!nrow(models)) stop("no maps that beat their null models on the ", grid, " grid to index", call. = FALSE)

  pieces <- lapply(seq_len(nrow(models)), function(i) {
    part <- strong$cells[[i]]
    if (is.null(part)) return(NULL)
    part <- part[!is.na(part$rank) & part$rank >= min_rank, , drop = FALSE]
    if (!nrow(part)) return(NULL)
    part$model <- i
    part
  })
  all <- do.call(rbind, pieces)
  if (is.null(all)) all <- data.frame(cell = integer(), rank = integer(), model = integer())
  all <- all[order(all$cell, -all$rank), , drop = FALSE]

  size <- cell_km * 1000
  ncol <- ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size)
  nrow <- ceiling((ATLAS_GRID_EXTENT[["ymax"]] - ATLAS_GRID_EXTENT[["ymin"]]) / size)
  n_cells <- ncol * nrow
  counts <- tabulate(all$cell, nbins = n_cells)
  index <- list(
    grid = grid,
    cell_km = cell_km,
    min_rank = min_rank,
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    models = models,
    start = c(1L, cumsum(counts) + 1L),
    model = as.integer(all$model),
    rank = as.raw(all$rank)
  )
  path <- atlas_here_index_path(grid)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(index, path, compress = "xz")
  say(sprintf("indexed %d maps into %s entries over %d km cells in %.0f s; %.1f MB",
              nrow(models), format(length(index$model), big.mark = ","), cell_km,
              as.numeric(difftime(Sys.time(), started, units = "secs")),
              file.info(path)$size / 1048576))
  invisible(index)
}

atlas_read_here_index <- function(grid = "draft") {
  path <- atlas_here_index_path(grid)
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

# ---- answering -------------------------------------------------------------

#' Distance in km between one point and many, on a sphere.
atlas_km_between <- function(lat, lng, lats, lngs) {
  rad <- pi / 180
  dlat <- (lats - lat) * rad
  dlng <- (lngs - lng) * rad
  h <- sin(dlat / 2)^2 + cos(lat * rad) * cos(lats * rad) * sin(dlng / 2)^2
  2 * 6371 * asin(pmin(1, sqrt(h)))
}

#' Taxa collected within km of a point, from the 0.1 degree public cells:
#' taxon -> records. A cell counts when its centre is within reach.
atlas_recorded_near <- function(cells, lat, lng, km = 25) {
  if (is.null(cells) || !nrow(cells)) return(integer())
  near <- abs(cells$lat - lat) < km / 111 + 0.1 &
    abs(cells$lng - lng) < km / (111 * max(cos(lat * pi / 180), 0.05)) + 0.1
  cells <- cells[near, , drop = FALSE]
  cells <- cells[atlas_km_between(lat, lng, cells$lat, cells$lng) <= km, , drop = FALSE]
  if (!nrow(cells)) return(integer())
  counts <- rowsum(cells$records, cells$taxon)
  stats::setNames(as.integer(counts[, 1]), rownames(counts))
}

#' Every mapped taxon a place suits, best first.
#'
#' index from atlas_build_here_index, cells the public 0.1 degree cells
#' (taxon, lat, lng, records), taxa the per-taxon counts.
atlas_here <- function(index, lat, lng, cells = NULL, taxa = NULL, limit = 50L,
                       min_score = 0, nearby_km = 25) {
  lat <- as.numeric(lat)
  lng <- as.numeric(lng)
  if (!is.finite(lat) || !is.finite(lng) || abs(lat) > 90 || abs(lng) > 180) {
    stop("lat and lng must be a point on Earth", call. = FALSE)
  }
  xy <- atlas_albers(lat, lng)
  cell <- atlas_here_cell(xy[1, "x"], xy[1, "y"], index$cell_km)
  nearby <- atlas_recorded_near(cells, lat, lng, nearby_km)
  answer <- list(
    point = list(lat = lat, lng = lng),
    cell_km = index$cell_km,
    in_grid = !is.na(cell),
    nearby_km = nearby_km,
    taxa = list(),
    recorded_unmapped = list(),
    total = 0L
  )

  entries <- if (is.na(cell)) integer() else seq.int(index$start[[cell]], length.out = index$start[[cell + 1]] - index$start[[cell]])
  models <- index$models
  fitted <- split(models$algorithm, models$taxon)
  if (length(entries)) {
    here <- data.frame(
      taxon = models$taxon[index$model[entries]],
      algorithm = models$algorithm[index$model[entries]],
      rank = as.integer(index$rank[entries]) / 100,
      stringsAsFactors = FALSE
    )
    by_taxon <- split(here, here$taxon)
    rows <- lapply(names(by_taxon), function(name) {
      mine <- by_taxon[[name]]
      algorithms <- fitted[[name]]
      ranks <- stats::setNames(rep(NA_real_, length(algorithms)), algorithms)
      ranks[mine$algorithm] <- mine$rank
      list(
        scientific_name = name,
        score = round(sum(ranks, na.rm = TRUE) / length(algorithms), 3),
        # Only models that rate this place in their top half; a model missing
        # here rates it lower, or does not reach this far.
        models = as.list(ranks[!is.na(ranks)]),
        agree = sum(ranks >= 0.9, na.rm = TRUE),
        fitted = as.list(algorithms),
        nearby_records = if (name %in% names(nearby)) nearby[[name]] else 0L
      )
    })
    scores <- vapply(rows, `[[`, numeric(1), "score")
    rows <- rows[scores >= min_score]
    scores <- scores[scores >= min_score]
    localities <- if (!is.null(taxa)) {
      taxa$localities[match(vapply(rows, `[[`, character(1), "scientific_name"), taxa$scientific_name)]
    } else {
      rep(0, length(rows))
    }
    localities[is.na(localities)] <- 0
    for (i in seq_along(rows)) rows[[i]]$localities <- localities[[i]]
    rows <- rows[order(-scores, -localities)]
    answer$total <- length(rows)
    answer$taxa <- utils::head(rows, limit)
  }

  # Collected nearby but without a map yet: survey targets on this ground.
  unmapped <- setdiff(names(nearby), models$taxon)
  if (length(unmapped)) {
    counts <- nearby[unmapped]
    counts <- counts[order(-counts, names(counts))]
    answer$recorded_unmapped <- lapply(utils::head(names(counts), 25), function(n) {
      list(scientific_name = n, nearby_records = counts[[n]])
    })
  }
  answer
}
