# Where a species is likely to occur, by state and province, from its maps.
#
# A list of states with DNA-validated records says where a species has been
# sequenced, not where it grows. Its maps say more, so each map is counted by
# state when it is drawn:
#
#   reach     the state's cells the map covers at all. A map makes no claim
#             past 500 km from a record, and draws nothing there.
#   suitable  the cells it rates at least as highly as the poorer tenth of the
#             places the species was found: the 10th-percentile training
#             presence threshold, the usual way a suitability map is read as
#             presence or absence. It adapts to the species, where a fixed
#             cut (its top quarter, say) would call a widespread fungus
#             unlikely in half the states it has been collected in.
#
# Then, over a species' maps that beat their null models (one that cannot
# tell it from a random handful of collections has no say), a state is:
#
#   likely        suitable ground covers at least a tenth of it (Steve,
#                 2026-10-06), as the mean over the maps: they agree;
#   possible      not that, but at least one map rates a tenth of it
#                 suitable (Steve, 2026-10-07): the maps disagree, and one
#                 sees habitat the others do not;
#   beyond reach  under a tenth of it lies within the maps' reach, so the
#                 maps cannot say;
#   unlikely      otherwise: the maps cover it and rate little of it highly.
#
# "Possible" is kept apart from "likely" rather than folded into it: on 40
# species with two or more maps, counting any one map's tenth as likely added
# 12% more likely states, and 94 of those 95 rested on a single map while the
# others rated the state near nothing.
#
# The shares are published with the verdict, so a narrow call can be seen.
# Counts are made on the 5 km draft grid whatever grid a map is fitted on.

ATLAS_REGION_MIN_SHARE <- 0.10
ATLAS_REGION_PRESENCE_QUANTILE <- 0.10
ATLAS_REGION_CELL_M <- 5000

# ---- boundaries ------------------------------------------------------------

#' A boundary file from inst/boundaries (tools/build-boundaries.R): regions,
#' countries or lakes. The source tree when running from it, the installed
#' package otherwise.
atlas_boundaries_path <- function(name, root = Sys.getenv("ATLAS_ROOT", unset = ".")) {
  source <- file.path(root, "inst", "boundaries", paste0(name, ".geojson"))
  if (file.exists(source)) return(source)
  system.file("boundaries", paste0(name, ".geojson"), package = "mycomapatlas")
}

atlas_read_boundaries <- local({
  cache <- list()
  function(name) {
    if (is.null(cache[[name]])) {
      path <- atlas_boundaries_path(name)
      if (!nzchar(path) || !file.exists(path)) stop("no boundary file ", name, call. = FALSE)
      cache[[name]] <<- terra::vect(path)
    }
    cache[[name]]
  }
})

#' Every 5 km cell of the Atlas grid, numbered by the region its centre falls
#' in (NA at sea and outside the three countries), with each region's code
#' and its cell count. Made once per process.
atlas_region_grid <- local({
  made <- NULL
  function() {
    if (!is.null(made)) return(made)
    size <- ATLAS_REGION_CELL_M
    template <- terra::rast(
      ncols = (ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size,
      nrows = (ATLAS_GRID_EXTENT[["ymax"]] - ATLAS_GRID_EXTENT[["ymin"]]) / size,
      xmin = ATLAS_GRID_EXTENT[["xmin"]], xmax = ATLAS_GRID_EXTENT[["xmax"]],
      ymin = ATLAS_GRID_EXTENT[["ymin"]], ymax = ATLAS_GRID_EXTENT[["ymax"]],
      crs = ATLAS_CRS
    )
    regions <- terra::project(atlas_read_boundaries("regions"), ATLAS_CRS)
    regions$id <- seq_len(nrow(regions))
    ids <- terra::rasterize(regions, template, field = "id")
    made <<- list(
      ids = ids,
      codes = regions$code,
      cells = tabulate(terra::values(ids, mat = FALSE), nbins = nrow(regions))
    )
    made
  }
})

# ---- counting one map --------------------------------------------------------

#' Count one suitability map by state: each region's cells, the cells the map
#' reaches, and the cells at or above the threshold set by the places the
#' species was found (x, y on the Atlas grid).
#'
#' Returns NULL when none of those places falls on the map. Otherwise a list:
#' threshold (raw suitability), presences (cells it was set from), and cells,
#' a named list of [cells, reach, suitable] for each region the map reaches.
atlas_region_counts <- function(suitability, x, y,
                                quantile = ATLAS_REGION_PRESENCE_QUANTILE) {
  r <- if (is.character(suitability)) terra::rast(suitability) else suitability
  factor <- round(ATLAS_REGION_CELL_M / terra::res(r)[[1]])
  if (factor > 1) r <- terra::aggregate(r, fact = factor, fun = "mean", na.rm = TRUE)

  at <- unique(stats::na.omit(terra::cellFromXY(r, cbind(as.numeric(x), as.numeric(y)))))
  found <- terra::values(r, mat = FALSE)[at]
  found <- found[is.finite(found)]
  if (!length(found)) return(NULL)
  threshold <- as.numeric(stats::quantile(found, quantile, names = FALSE, type = 7))

  grid <- atlas_region_grid()
  ids <- terra::values(terra::crop(grid$ids, r, snap = "near"), mat = FALSE)
  values <- terra::values(r, mat = FALSE)
  if (length(ids) != length(values)) stop("the map is not on the Atlas grid", call. = FALSE)
  n <- length(grid$codes)
  reach <- tabulate(ids[is.finite(values)], nbins = n)
  suitable <- tabulate(ids[is.finite(values) & values >= threshold], nbins = n)
  hit <- which(reach > 0)
  list(
    threshold = signif(threshold, 6),
    presences = length(found),
    cells = stats::setNames(
      lapply(hit, function(i) c(grid$cells[[i]], reach[[i]], suitable[[i]])),
      grid$codes[hit]
    )
  )
}

#' A model's state counts as rows: code, cells, reach, suitable.
atlas_region_rows <- function(regions) {
  cells <- regions$cells
  if (is.null(cells) || !length(cells)) {
    return(data.frame(code = character(), cells = integer(), reach = integer(),
                      suitable = integer(), stringsAsFactors = FALSE))
  }
  counts <- matrix(as.integer(unlist(cells, use.names = FALSE)), ncol = 3, byrow = TRUE)
  data.frame(code = names(cells), cells = counts[, 1], reach = counts[, 2],
             suitable = counts[, 3], stringsAsFactors = FALSE)
}

#' Count a stored map again, from its raster and the places the species was
#' collected (the public 0.1 degree cells), and write the counts into its
#' metrics. For maps drawn before maps were counted by state.
atlas_recount_regions <- function(raster_path, cells) {
  metrics_path <- sub("[.]tif$", ".json", raster_path)
  if (!file.exists(metrics_path)) return(invisible(NULL))
  metrics <- jsonlite::fromJSON(metrics_path, simplifyVector = FALSE)
  mine <- cells[cells$taxon == metrics$taxon, , drop = FALSE]
  xy <- atlas_albers(mine$lat, mine$lng)
  regions <- atlas_region_counts(raster_path, xy[, "x"], xy[, "y"])
  if (!is.null(regions)) regions$from <- "collection cells"
  metrics$regions <- regions
  atlas_write_json(metrics, metrics_path)
  invisible(regions)
}

#' Count every stored map on a grid by state. Needs the rasters (a pull of a
#' release with them, or the machine that fitted them) and the public cells.
atlas_count_regions <- function(grid = "draft", quiet = FALSE, workers = 1L, only_missing = FALSE) {
  rasters <- unlist(lapply(names(ATLAS_ALGORITHMS), function(algorithm) {
    list.files(atlas_model_dir(grid, algorithm), pattern = "[.]tif$", full.names = TRUE)
  }), use.names = FALSE)
  if (isTRUE(only_missing)) {
    # Maps fitted since counting began carry their counts already.
    uncounted <- vapply(rasters, function(path) {
      metrics <- tryCatch(jsonlite::fromJSON(sub("[.]tif$", ".json", path), simplifyVector = FALSE),
                          error = function(e) NULL)
      is.list(metrics) && is.null(metrics$regions)
    }, logical(1))
    rasters <- rasters[uncounted]
  }
  if (!length(rasters)) {
    if (!quiet) message("no maps to count on the ", grid, " grid")
    return(invisible(0L))
  }
  occurrences <- tryCatch(atlas_read_occurrences(), error = function(e) NULL)
  cells <- if (!is.null(occurrences)) atlas_public_cells_table(occurrences) else atlas_read_public_cells()
  if (is.null(cells)) stop("no collection cells: pull occurrences or a release first", call. = FALSE)

  done <- 0L
  report <- function(counted) {
    # Forced: on one worker the count itself is this argument, and R would
    # otherwise never evaluate it (as atlas_rebuild_maps once did).
    force(counted)
    done <<- done + 1L
    if (!quiet && (done %% 100L == 0L || done == length(rasters))) {
      message("  counted ", done, " of ", length(rasters))
    }
  }
  if (workers > 1L) {
    cluster <- atlas_start_workers(min(workers, length(rasters)), grid, points = NULL)
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    parallel::clusterExport(cluster, "cells", envir = environment())
    task <- function(raster_path) atlas_recount_regions(raster_path, cells)
    environment(task) <- globalenv()
    atlas_run_on_workers(cluster, rasters, task, report)
  } else {
    for (raster_path in rasters) report(atlas_recount_regions(raster_path, cells))
  }
  invisible(length(rasters))
}

# ---- what the maps say together ----------------------------------------------

#' Per species and state, what its maps say together.
#'
#' rows has one row per map and state: taxon, algorithm, skill, code, cells,
#' reach, suitable. Only maps that beat their null models count. Returns
#' taxon, code, maps, reach_share (the most any map reaches), suitable_share
#' (the mean over the species' counted maps, a map that does not reach the
#' state counting as none) and best_share (the most any one map rates
#' suitable).
atlas_region_predictions <- function(rows) {
  empty <- data.frame(taxon = character(), code = character(), maps = integer(),
                      reach_share = numeric(), suitable_share = numeric(),
                      best_share = numeric(), stringsAsFactors = FALSE)
  if (is.null(rows) || !nrow(rows)) return(empty)
  rows <- rows[rows$skill == "passed", , drop = FALSE]
  if (!nrow(rows)) return(empty)
  maps <- tapply(rows$algorithm, rows$taxon, function(a) length(unique(a)))
  key <- paste(rows$taxon, rows$code, sep = "\t")
  first <- !duplicated(key)
  out <- data.frame(taxon = rows$taxon[first], code = rows$code[first], stringsAsFactors = FALSE)
  out$maps <- as.integer(maps[out$taxon])
  out$reach_share <- as.numeric(tapply(rows$reach / rows$cells, key, max)[key[first]])
  suitable <- tapply(rows$suitable / rows$cells, key, sum)[key[first]]
  out$suitable_share <- as.numeric(suitable) / out$maps
  out$best_share <- as.numeric(tapply(rows$suitable / rows$cells, key, max)[key[first]])
  rownames(out) <- NULL
  out
}

#' The verdict on a species in a state: likely, possible, beyond reach,
#' unlikely, or no map when the species has no counted map that beat its null
#' models. best_share defaults to the mean, which makes nothing "possible".
atlas_region_verdict <- function(reach_share, suitable_share, best_share = suitable_share,
                                 min_share = ATLAS_REGION_MIN_SHARE) {
  at_least <- function(x) !is.na(x) & x >= min_share - 1e-9
  ifelse(is.na(suitable_share), "no map",
         ifelse(at_least(suitable_share), "likely",
                ifelse(at_least(best_share), "possible",
                       ifelse(reach_share < min_share - 1e-9, "beyond reach", "unlikely"))))
}

#' Recorded and predicted together: one row per species per region where it
#' has records or its maps say it is likely or possible.
#'
#' recorded is atlas_region_table's; predictions atlas_region_predictions'.
#' A species with predictions somewhere has a verdict in every state; one
#' with none has "no map". Adds reach_share, suitable_share, best_share and
#' model.
atlas_region_status <- function(recorded, predictions = NULL, min_share = ATLAS_REGION_MIN_SHARE) {
  recorded <- if (is.null(recorded)) atlas_region_table(NULL) else recorded
  predictions <- if (is.null(predictions)) atlas_region_predictions(NULL) else predictions
  if (is.null(predictions$best_share)) predictions$best_share <- predictions$suitable_share
  likely <- predictions[predictions$best_share >= min_share - 1e-9, , drop = FALSE]

  key_recorded <- paste(recorded$taxon, recorded$code, sep = "\t")
  extra <- likely[!paste(likely$taxon, likely$code, sep = "\t") %in% key_recorded, , drop = FALSE]
  out <- recorded
  if (nrow(extra)) {
    known <- atlas_region_list()
    at <- match(extra$code, vapply(known, `[[`, "", "code"))
    country_code <- vapply(known[at], `[[`, "", "country")
    out <- rbind(out, data.frame(
      taxon = extra$taxon,
      country = unname(ATLAS_COUNTRY_NAMES[country_code]),
      country_code = country_code,
      region = vapply(known[at], `[[`, "", "name"),
      code = extra$code,
      records = 0L, localities = 0L,
      stringsAsFactors = FALSE
    ))
  }

  key <- paste(out$taxon, out$code, sep = "\t")
  at <- match(key, paste(predictions$taxon, predictions$code, sep = "\t"))
  mapped <- out$taxon %in% predictions$taxon & nzchar(out$code)
  out$reach_share <- ifelse(mapped, ifelse(is.na(at), 0, predictions$reach_share[at]), NA_real_)
  out$suitable_share <- ifelse(mapped, ifelse(is.na(at), 0, predictions$suitable_share[at]), NA_real_)
  out$best_share <- ifelse(mapped, ifelse(is.na(at), 0, predictions$best_share[at]), NA_real_)
  out$model <- atlas_region_verdict(out$reach_share, out$suitable_share, out$best_share, min_share)
  out <- out[order(out$country, out$region, out$taxon), , drop = FALSE]
  rownames(out) <- NULL
  out
}
