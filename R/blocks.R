# Maps are drawn in whole blocks: 50 km squares of one fixed grid, origin at
# the Atlas grid's corner (ATLAS_GRID_EXTENT xmin, ymax), the same for every
# map and both grids. A block is drawn only when its whole 50 km square lies
# inside the accessible area (the union of the 500 km circles around the
# taxon's detection sites), and a block that runs past the grid's edge is
# dropped. Inside a kept block every cell the predictors cover is drawn, as
# predicted. A map's raster is then cropped to its kept blocks, so its
# extent, and the bounds its picture is laid at, lie on block lines.
#
# A fit has its area in hand. A map already stored is trimmed with its area
# built again from the records it was fitted on (atlas_block_area), and only
# after that area is shown to give exactly the map as stored
# (atlas_block_area_matches); a map whose area cannot be built again is not
# drawn. Scores are computed on the folds, never on the map, so trimming
# changes no score, null test or grade. Full-extent views are not trimmed:
# they cover the whole of North America on one scale.

ATLAS_BLOCK_KM <- 50

#' Where every predictor of a stack has a value: TRUE there, FALSE elsewhere,
#' on the stack's grid. Prediction skips any cell where a layer has no value
#' (atlas_predict_raster), so inside a map's area these are exactly the cells
#' a map can be drawn on.
atlas_block_land <- function(stack) {
  !is.na(terra::app(stack, fun = function(v) if (anyNA(v)) NA_real_ else 1))
}

#' The extent of the whole blocks that cover e: on block lines of the fixed
#' grid.
atlas_block_extent <- function(e, block_km = ATLAS_BLOCK_KM) {
  size <- block_km * 1000
  x0 <- ATLAS_GRID_EXTENT[["xmin"]]
  y1 <- ATLAS_GRID_EXTENT[["ymax"]]
  terra::ext(
    x0 + floor((terra::xmin(e) - x0) / size + 1e-9) * size,
    x0 + ceiling((terra::xmax(e) - x0) / size - 1e-9) * size,
    y1 - ceiling((y1 - terra::ymin(e)) / size - 1e-9) * size,
    y1 - floor((y1 - terra::ymax(e)) / size + 1e-9) * size
  )
}

#' Which blocks of a map to keep. r is the map (only its grid is read: where
#' it is drawn plays no part), area the accessible area as a polygon
#' (atlas_accessible_area). Returns a one-layer raster on r's cells over the
#' whole blocks around r: 1 in each kept block, NA elsewhere. A block is kept
#' when its whole square lies inside the area and inside the grid.
atlas_block_keep <- function(r, area, block_km = ATLAS_BLOCK_KM) {
  size <- block_km * 1000
  per <- round(size / terra::res(r)[[1]])
  if (abs(per * terra::res(r)[[1]] - size) > 1e-6) {
    stop("a ", block_km, " km block is not a whole number of ", terra::res(r)[[1]], " m cells", call. = FALSE)
  }
  whole <- atlas_block_extent(terra::ext(r), block_km)
  blocks <- terra::rast(whole, resolution = size, crs = terra::crs(r))
  terra::values(blocks) <- seq_len(terra::ncell(blocks))
  squares <- terra::as.polygons(blocks, aggregate = FALSE)
  if (nrow(area) > 1L) area <- terra::aggregate(area)
  within <- as.vector(terra::relate(squares, area, "coveredby"))
  # Each square back to its block, by the block's number.
  inside_area <- logical(terra::ncell(blocks))
  inside_area[as.integer(terra::values(squares)[[1]])] <- within
  # Blocks that run past the grid's edge are dropped.
  centres <- terra::xyFromCell(blocks, seq_len(terra::ncell(blocks)))
  half <- size / 2
  inside_grid <- centres[, 1] - half >= ATLAS_GRID_EXTENT[["xmin"]] - 1e-6 &
    centres[, 1] + half <= ATLAS_GRID_EXTENT[["xmax"]] + 1e-6 &
    centres[, 2] - half >= ATLAS_GRID_EXTENT[["ymin"]] - 1e-6 &
    centres[, 2] + half <= ATLAS_GRID_EXTENT[["ymax"]] + 1e-6
  terra::values(blocks) <- ifelse(inside_area & inside_grid, 1, NA_real_)
  terra::disagg(blocks, fact = per)
}

#' The kept blocks of a keep raster (atlas_block_keep) as numbers: row *
#' 100000 + col, counted in blocks from the grid's origin.
atlas_block_ids <- function(keep, block_km = ATLAS_BLOCK_KM) {
  size <- block_km * 1000
  kept <- which(!is.na(terra::values(keep, mat = FALSE)))
  if (!length(kept)) return(numeric())
  xy <- terra::xyFromCell(keep, kept)
  col <- floor((xy[, 1] - ATLAS_GRID_EXTENT[["xmin"]]) / size + 1e-9)
  row <- floor((ATLAS_GRID_EXTENT[["ymax"]] - xy[, 2]) / size + 1e-9)
  sort(unique(row * 100000 + col))
}

#' A keep raster on r's cells from block numbers (atlas_block_ids).
atlas_block_keep_from_ids <- function(r, ids, block_km = ATLAS_BLOCK_KM) {
  size <- block_km * 1000
  whole <- atlas_block_extent(terra::ext(r), block_km)
  blocks <- terra::rast(whole, resolution = size, crs = terra::crs(r))
  xy <- terra::xyFromCell(blocks, seq_len(terra::ncell(blocks)))
  id <- floor((ATLAS_GRID_EXTENT[["ymax"]] - xy[, 2]) / size + 1e-9) * 100000 +
    floor((xy[, 1] - ATLAS_GRID_EXTENT[["xmin"]]) / size + 1e-9)
  terra::values(blocks) <- ifelse(id %in% ids, 1, NA_real_)
  terra::disagg(blocks, fact = round(size / terra::res(r)[[1]]))
}

#' A raster drawn only in the kept blocks: masked to them and cropped to
#' their extent, which lies on block lines. NULL when no kept block holds a
#' drawn cell.
atlas_block_apply <- function(x, keep) {
  drawn <- terra::crop(terra::extend(!is.na(x[[1]]), keep), keep)
  held <- which(!is.na(terra::values(keep, mat = FALSE)) & terra::values(drawn, mat = FALSE) %in% c(TRUE, 1))
  if (!length(held)) return(NULL)
  xy <- terra::xyFromCell(keep, held)
  half <- terra::res(keep)[[1]] / 2
  box <- atlas_block_extent(terra::ext(min(xy[, 1]) - half, max(xy[, 1]) + half,
                                       min(xy[, 2]) - half, max(xy[, 2]) + half))
  k <- terra::crop(keep, box)
  out <- terra::crop(terra::extend(x, box), box)
  # Same grid, so no resampling: values are kept exactly as they were.
  if (!terra::compareGeom(out, k, stopOnError = FALSE)) {
    stop("a map is not on the block grid's cells", call. = FALSE)
  }
  out <- terra::mask(out, k)
  names(out) <- names(x)
  out
}

#' Trim a map and its applicability index to whole blocks of its area. With
#' land (atlas_block_land, on the same grid), stops if a covered cell of a
#' kept block is not drawn: inside the area every covered cell is predicted,
#' so that would mean the area is not the one the map was drawn from.
#' Returns list(suitability, dissimilarity, keep), the first two NULL when
#' nothing is kept (or when given as NULL).
atlas_block_trim <- function(suitability, dissimilarity = NULL, area, land = NULL, block_km = ATLAS_BLOCK_KM) {
  keep <- atlas_block_keep(suitability, area, block_km)
  if (!is.null(land)) {
    k <- terra::values(keep, mat = FALSE)
    d <- terra::values(terra::crop(terra::extend(!is.na(suitability[[1]]), keep), keep), mat = FALSE)
    cvr <- terra::values(terra::crop(terra::extend(terra::crop(land, keep), keep), keep), mat = FALSE)
    if (any(!is.na(k) & cvr %in% c(TRUE, 1) & !(d %in% c(TRUE, 1)))) {
      stop("a covered cell inside a kept block is not drawn: the area is not the map's", call. = FALSE)
    }
  }
  list(
    suitability = atlas_block_apply(suitability, keep),
    dissimilarity = if (!is.null(dissimilarity)) atlas_block_apply(dissimilarity, keep),
    keep = keep
  )
}

# ---- the area of a map already stored ---------------------------------------

#' A taxon's accessible area built again as its fit built it: its detection
#' sites in the points of the pull it was fitted on (atlas_occurrence_points,
#' thinned at thin_km), those the predictors cover (land), and the circles
#' of buffer_km around them. NULL when none is left.
atlas_block_area <- function(name, points, land, buffer_km = 500, thin_km = ATLAS_SITE_KM) {
  points <- atlas_ensure_sites(points, thin_km)
  sites <- attr(points, "sites")
  found <- unique(points$site[points$scientific_name == name])
  if (!length(found)) return(NULL)
  presences <- sites[found, c("x", "y"), drop = FALSE]
  covered <- terra::extract(land, as.matrix(presences))[, 1]
  presences <- presences[covered %in% c(TRUE, 1), , drop = FALSE]
  if (!nrow(presences)) return(NULL)
  atlas_accessible_area(presences$x, presences$y, buffer_km)
}

#' Whether an area gives exactly a stored, untrimmed map: the map lies on
#' the area's window of the grid (atlas_predict_raster crops to it), and is
#' drawn on exactly the covered cells inside the area.
atlas_block_area_matches <- function(map, area, land) {
  window <- terra::crop(land, terra::ext(area))
  if (!terra::compareGeom(window, map, stopOnError = FALSE)) return(FALSE)
  expected <- terra::values(terra::mask(window, area), mat = FALSE) %in% c(TRUE, 1)
  drawn <- !is.na(terra::values(map[[1]], mat = FALSE))
  identical(expected, drawn)
}

# ---- maps already stored --------------------------------------------------

#' Take a stored map off: its raster, index and picture removed and its
#' metrics told so, as when a fit draws no map.
atlas_block_withdraw_stored <- function(raster_path, block_km = ATLAS_BLOCK_KM) {
  metrics_path <- sub("[.]tif$", ".json", raster_path)
  unlink(c(raster_path, sub("[.]tif$", ".di.tif", raster_path), sub("[.]tif$", ".png", raster_path)))
  if (file.exists(metrics_path)) {
    metrics <- jsonlite::fromJSON(metrics_path, simplifyVector = FALSE)
    for (field in c("raster", "dissimilarity", "map", "bounds", "md5", "regions")) metrics[[field]] <- NULL
    metrics$blocks_km <- block_km
    atlas_write_json(metrics, metrics_path)
  }
  invisible(TRUE)
}

#' Trim one stored map to whole blocks of its area, in place on this machine:
#' its .tif and .di.tif masked and cropped, its .png redrawn
#' (atlas_redraw_map, which records the new bounds), its md5 updated, and its
#' counts by state cleared so the next count redoes them from the trimmed
#' map. The area must first give exactly the map as stored
#' (atlas_block_area_matches). Returns "already" (drawn in blocks of this
#' size before), "mismatch" (left as it is, for the caller), "none" (no kept
#' block holds a drawn cell: taken off) or "trimmed". With blocks TRUE,
#' list(status, blocks): the kept blocks' numbers (atlas_block_ids) when it
#' was trimmed.
atlas_block_trim_stored <- function(raster_path, area, land, block_km = ATLAS_BLOCK_KM, blocks = FALSE) {
  if (isTRUE(blocks)) {
    ids <- NULL
    status <- atlas_block_trim_stored_(raster_path, area, land, block_km, function(keep) ids <<- atlas_block_ids(keep))
    return(list(status = status, blocks = if (identical(status, "trimmed")) ids))
  }
  atlas_block_trim_stored_(raster_path, area, land, block_km)
}

atlas_block_trim_stored_ <- function(raster_path, area, land, block_km = ATLAS_BLOCK_KM, kept = NULL) {
  metrics_path <- sub("[.]tif$", ".json", raster_path)
  metrics <- if (file.exists(metrics_path)) jsonlite::fromJSON(metrics_path, simplifyVector = FALSE)
  if (is.list(metrics) && identical(as.numeric(metrics$blocks_km %||% NA), as.numeric(block_km))) {
    return("already")
  }
  index_path <- sub("[.]tif$", ".di.tif", raster_path)
  map <- terra::rast(raster_path)
  if (is.null(area) || !atlas_block_area_matches(map, area, land)) return("mismatch")
  index <- if (file.exists(index_path)) terra::rast(index_path)
  trimmed <- atlas_block_trim(map, index, area, land, block_km)
  if (is.function(kept)) kept(trimmed$keep)
  if (is.null(trimmed$suitability)) {
    rm(map, index, trimmed)
    atlas_block_withdraw_stored(raster_path, block_km)
    return("none")
  }
  # Held in memory first, so the files they were read from can be replaced.
  suitability <- terra::toMemory(trimmed$suitability)
  dissimilarity <- if (!is.null(trimmed$dissimilarity)) terra::toMemory(trimmed$dissimilarity)
  rm(map, index, trimmed)
  write <- function(x, path) {
    terra::writeRaster(x, path, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES"))
    unlink(paste0(path, ".aux.xml"))
  }
  write(suitability, raster_path)
  if (!is.null(dissimilarity)) write(dissimilarity, index_path)
  atlas_redraw_map(raster_path)
  metrics <- jsonlite::fromJSON(metrics_path, simplifyVector = FALSE)
  metrics$md5 <- unname(tools::md5sum(raster_path))
  metrics$regions <- NULL
  metrics$blocks_km <- block_km
  atlas_write_json(metrics, metrics_path)
  "trimmed"
}

#' Where the predictors of a release's layer set have values, on this
#' machine: the set is fetched from the store when this machine lacks it
#' (a finishing worker holds no layers), and the mask is written once to a
#' file the pool's processes read.
atlas_block_land_file <- function(store, grid = "draft", layers_key = NULL) {
  # A file named by option atlas.block_land stands in (the tests' fixtures).
  given <- getOption("atlas.block_land")
  if (!is.null(given)) return(given)
  path <- atlas_path("blocks", grid, "complete-cases.tif", create = TRUE)
  if (file.exists(path)) return(path)
  if (!any(grepl("[.]tif$", atlas_layer_set_files(grid)))) {
    key <- layers_key %||% atlas_current_layers(store, grid)$key
    set <- atlas_store_text(store, paste0("layers/", grid, "/", key, ".json"))
    if (is.null(set)) stop("no layer set ", key, " in the store for the ", grid, " grid", call. = FALSE)
    atlas_fetch_entries(store, set$files)
  }
  land <- atlas_block_land(atlas_predictor_stack(grid))
  terra::writeRaster(land, path, overwrite = TRUE, datatype = "INT1U", gdal = c("COMPRESS=DEFLATE"))
  path
}

#' The pulls that fitted a grid's models, as the store keeps them: one entry
#' per job (its id, when it was planned, its pull's object hash, and the
#' taxon and algorithm of every model it fitted), newest first.
atlas_block_job_pulls <- function(store, grid = "draft") {
  keys <- grep("/job[.]json$", store$list(paste0("jobs/", grid, "/")), value = TRUE)
  out <- list()
  for (key in keys) {
    job <- tryCatch(atlas_store_text(store, key), error = function(e) NULL)
    if (!is.list(job)) next
    pulls <- Filter(function(e) grepl("^occurrences/occurrences-.*[.]tsv[.]gz$", e$path %||% ""),
                    job$inputs %||% list())
    if (!length(pulls)) next
    tasks <- job$tasks %||% list()
    out[[length(out) + 1L]] <- list(
      id = job$id, created_at = atlas_json_string(job$created_at) %||% "", sha256 = pulls[[1]]$sha256,
      fitted = vapply(tasks, function(t) paste(t$taxon, atlas_json_string(t$algorithm) %||% "maxnet", sep = "\x1f"), "")
    )
  }
  out[order(vapply(out, function(j) j$created_at, ""), decreasing = TRUE)]
}

#' The stored maps of a grid still to be drawn in blocks, with what finding
#' their area needs: path, taxon, algorithm, record-set fingerprint (the
#' release's index entry first, the metrics' own besides), when it was built,
#' and its buffer and thinning distances.
atlas_block_pending <- function(grid = "draft", index = list(), block_km = ATLAS_BLOCK_KM,
                                rasters = atlas_model_map_rasters(grid)) {
  fingerprints <- list()
  for (e in index) {
    if (is.character(e$fingerprint) && length(e$fingerprint) == 1L) {
      fingerprints[[paste(e$taxon, e$algorithm %||% "maxnet", sep = "\x1f")]] <- e$fingerprint
    }
  }
  rows <- list()
  for (path in rasters) {
    metrics <- tryCatch(jsonlite::fromJSON(sub("[.]tif$", ".json", path), simplifyVector = FALSE),
                        error = function(e) NULL)
    if (!is.list(metrics)) next
    if (identical(as.numeric(metrics$blocks_km %||% NA), as.numeric(block_km))) next
    algorithm <- atlas_json_string(metrics$algorithm) %||% "maxnet"
    key <- paste(metrics$taxon, algorithm, sep = "\x1f")
    settings <- if (is.list(metrics$settings)) metrics$settings else list()
    number <- function(x, default) {
      x <- suppressWarnings(as.numeric(unlist(x)))
      if (length(x) == 1L && is.finite(x)) x else default
    }
    rows[[length(rows) + 1L]] <- list(
      path = path, taxon = as.character(metrics$taxon), algorithm = algorithm, key = key,
      fingerprint = fingerprints[[key]] %||% atlas_json_string(metrics$fingerprint),
      built_at = atlas_json_string(metrics$built_at) %||% "",
      buffer_km = number(settings$buffer_km, 500),
      thin_km = number(settings$thin_km %||% metrics$thin_km, ATLAS_SITE_KM)
    )
  }
  rows
}

#' One map's trim as a worker runs it: item is list(path, area), the area
#' packed (terra::wrap) so it can be sent to another process.
atlas_block_trim_item <- function(item, land_path, blocks = FALSE) {
  area <- if (!is.null(item$area)) terra::unwrap(item$area)
  atlas_block_trim_stored(item$path, area, terra::rast(land_path), blocks = blocks)
}

#' A job's pull from the store, read and projected once: list(occurrences,
#' points), or NULL when the store does not hold it.
atlas_block_read_pull <- function(store, sha256, grid = "draft") {
  key <- atlas_object_key(sha256)
  if (!store$exists(key)) return(NULL)
  file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(file), add = TRUE)
  store$get(key, file)
  occurrences <- atlas_read_occurrences(file)
  list(occurrences = occurrences, points = atlas_occurrence_points(occurrences, grid))
}

#' Trim every stored map of a grid to whole blocks of its own area.
#'
#' Each map's area is built again from the pull it was fitted on: the pull of
#' the job that fitted it (the newest job planned before the map was built
#' that lists it), then any other job's pull in which the taxon's record set
#' is the same. A pull's area is used only when it gives exactly the stored
#' map (atlas_block_area_matches). A map whose record set is in no pull the
#' store keeps ("not found"), or whose area matches from none ("mismatch"),
#' is taken off and named in the result: it is never drawn untrimmed. pulls
#' and read_pull are replaceable for tests.
#'
#' The areas are built here, one pull at a time; the trims run on workers
#' processes when workers > 1, in one pool started once.
#'
#' rasters are the maps to trim (by default every map of the grid on this
#' machine; a deposit passes its tree's). With blocks TRUE the result also
#' holds blocks: each trimmed map's kept blocks (atlas_block_ids), by path,
#' kept in memory only.
#'
#' Returns list(trimmed, already, not_found, mismatch, none, not_drawn = a
#' list of {path, taxon, algorithm, reason}).
atlas_block_trim_release <- function(store, land_path, grid = "draft", index = list(), workers = 1L,
                                     quiet = FALSE, pulls = atlas_block_job_pulls(store, grid),
                                     read_pull = atlas_block_read_pull, rasters = atlas_model_map_rasters(grid),
                                     blocks = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  land <- terra::rast(land_path)
  all_maps <- length(rasters)
  pending <- atlas_block_pending(grid, index, rasters = rasters)
  kept <- list()
  status <- rep("not found", length(pending))
  # The pulls each map tries, in order: its fitting job's first.
  plan <- lapply(pending, function(p) {
    fitted_by <- which(vapply(pulls, function(j) p$key %in% j$fitted && j$created_at <= p$built_at, logical(1)))
    first <- utils::head(fitted_by, 1L)
    c(first, setdiff(seq_along(pulls), first))
  })
  pool <- NULL
  if (as.integer(workers) > 1L && length(pending) >= 2L) {
    pool <- atlas_package_pool(min(as.integer(workers), length(pending)))
    on.exit(parallel::stopCluster(pool), add = TRUE)
  }
  trim_all <- function(items) {
    if (is.null(pool)) return(lapply(items, atlas_block_trim_item, land_path = land_path, blocks = blocks))
    run <- function(item, land_path, blocks) atlas_block_trim_item(item, land_path, blocks)
    environment(run) <- globalenv()
    parallel::clusterApplyLB(pool, items, run, land_path = land_path, blocks = blocks)
  }
  for (round in seq_along(pulls)) {
    waiting <- which(status %in% c("not found", "mismatch"))
    if (!length(waiting)) break
    turn <- vapply(waiting, function(i) plan[[i]][round], 1L)
    for (j in unique(turn)) {
      mine <- waiting[turn == j]
      pull <- read_pull(store, pulls[[j]]$sha256, grid)
      if (is.null(pull)) next
      prints <- atlas_fingerprints_for(pull$occurrences, unique(vapply(pending[mine], `[[`, "", "taxon")))
      same <- mine[vapply(mine, function(i) identical(unname(prints[[pending[[i]]$taxon]]), pending[[i]]$fingerprint),
                          logical(1))]
      items <- lapply(same, function(i) {
        p <- pending[[i]]
        area <- atlas_block_area(p$taxon, pull$points, land, p$buffer_km, p$thin_km)
        list(path = p$path, area = if (!is.null(area)) terra::wrap(area))
      })
      if (length(items)) {
        results <- trim_all(items)
        status[same] <- vapply(results, function(r) if (is.list(r)) r$status else r, "")
        if (isTRUE(blocks)) {
          for (k in seq_along(same)) {
            if (!is.null(results[[k]]$blocks)) kept[[pending[[same[[k]]]]$path]] <- results[[k]]$blocks
          }
        }
      }
      rm(pull)
      gc(verbose = FALSE)
    }
  }
  not_drawn <- list()
  for (i in which(status %in% c("not found", "mismatch", "none"))) {
    if (status[[i]] != "none") atlas_block_withdraw_stored(pending[[i]]$path)
    not_drawn[[length(not_drawn) + 1L]] <- list(path = pending[[i]]$path, taxon = pending[[i]]$taxon,
                                                algorithm = pending[[i]]$algorithm, reason = status[[i]])
  }
  out <- list(trimmed = sum(status == "trimmed"), already = all_maps - length(pending),
              not_found = sum(status == "not found"), mismatch = sum(status == "mismatch"),
              none = sum(status == "none"), not_drawn = not_drawn)
  if (isTRUE(blocks)) out$blocks <- kept
  say("drawn in whole ", ATLAS_BLOCK_KM, " km blocks: ", out$trimmed, " of ", all_maps, " maps (",
      out$already, " already); not drawn: ", out$not_found, " whose record set no kept pull holds, ",
      out$mismatch, " whose area did not give the map as stored",
      if (out$none) paste0(", ", out$none, " with no kept block") else "")
  invisible(out)
}

#' Before a finish, read only: for each map of a release still to be drawn
#' in blocks (its index entry has a map and no blocks yet), whether its
#' record set is in a pull the store keeps, as the finish looks for it. A map
#' found here can still fail the finish's match check; one not found here is
#' taken off by the finish. Prints the counts and returns them, with the
#' maps not found.
atlas_block_plan <- function(store, grid = "draft", release = NULL, quiet = FALSE,
                             pulls = atlas_block_job_pulls(store, grid), read_pull = atlas_block_read_pull) {
  manifest <- if (is.null(release)) {
    atlas_current_release(store, grid)
  } else {
    atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  }
  if (is.null(manifest)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)
  if (atlas_release_finished(manifest)) {
    if (!isTRUE(quiet)) message("release ", manifest$id, " is finished under version ", ATLAS_FINISH_VERSION,
                                " or later: nothing to draw again")
    return(invisible(list(release = manifest$id, maps = 0L, found = 0L, by_fitting_job = 0L,
                          not_found = 0L, missing = list())))
  }
  entries <- Filter(function(e) isTRUE(e$map) && is.character(e$fingerprint) && length(e$fingerprint) == 1L,
                    manifest$index %||% list())
  keys <- vapply(entries, function(e) paste(e$taxon, e$algorithm %||% "maxnet", sep = "\x1f"), "")
  found <- rep(FALSE, length(entries))
  by_job <- vapply(keys, function(k) any(vapply(pulls, function(j) k %in% j$fitted, logical(1))), logical(1))
  for (j in seq_along(pulls)) {
    if (all(found)) break
    pull <- read_pull(store, pulls[[j]]$sha256, grid)
    if (is.null(pull)) next
    open <- which(!found)
    prints <- atlas_fingerprints_for(pull$occurrences, unique(vapply(entries[open], function(e) e$taxon, "")))
    for (i in open) {
      if (identical(unname(prints[[entries[[i]]$taxon]]), entries[[i]]$fingerprint)) found[[i]] <- TRUE
    }
    rm(pull)
  }
  out <- list(release = manifest$id, maps = length(entries), found = sum(found),
              by_fitting_job = sum(found & by_job), not_found = sum(!found),
              missing = lapply(entries[!found], function(e) list(taxon = e$taxon, algorithm = e$algorithm)))
  if (!isTRUE(quiet)) {
    message("release ", out$release, ": ", out$maps, " maps to draw again in blocks; record set in a kept pull: ",
            out$found, " (", out$by_fitting_job, " listed by a kept job); not found, so taken off by the finish: ",
            out$not_found)
  }
  invisible(out)
}

# ---- releases that are never finished again ---------------------------------

# Releases kept exactly as published: the paper's frozen release. Finishing
# never runs on them; a promotion to one says so.
ATLAS_FROZEN_RELEASES <- c("20261013T191324Z-fa1b4198")

#' Refuse to finish a frozen release.
atlas_refuse_frozen <- function(release, what = "finished") {
  if (as.character(release %||% "") %in% ATLAS_FROZEN_RELEASES) {
    stop("release ", release, " is frozen (ATLAS_FROZEN_RELEASES) and is never ", what, call. = FALSE)
  }
  invisible(TRUE)
}

# ---- one orchestrator on the box at a time -----------------------------------

#' Hold the box's orchestrator lock while code runs: the nightly, a job run on
#' EC2 and a finish run by hand each take it, and a second one refuses to
#' start while it is held. A lock older than its hours plus two is taken to be
#' left by a run that was killed, and is taken over.
atlas_with_orchestrator_lock <- function(name, hours, code, now = Sys.time()) {
  dir <- atlas_path("locks", "orchestrator")
  dir.create(dirname(dir), recursive = TRUE, showWarnings = FALSE)
  info <- file.path(dir, "held.json")
  if (!dir.create(dir, showWarnings = FALSE)) {
    held <- tryCatch(jsonlite::fromJSON(info, simplifyVector = TRUE), error = function(e) NULL)
    until <- if (is.list(held)) as.POSIXct(held$until %||% NA, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else NA
    if (!is.na(until) && now < until) {
      stop(held$name %||% "another run", " has held the box's orchestrator lock since ", held$since %||% "?",
           "; ", name, " does not start until it ends", call. = FALSE)
    }
    message("taking over the orchestrator lock left by ", (if (is.list(held)) held$name) %||% "a run", " since ",
            (if (is.list(held)) held$since) %||% "?")
  }
  stamp <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  atlas_write_json(list(name = name, since = stamp(now), until = stamp(now + (as.numeric(hours) + 2) * 3600)), info)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  force(code)
}

#' Finish the current release on EC2 now, by hand and under watch, as the
#' nightly would (atlas_finish_on_ec2), holding the orchestrator lock.
atlas_finish_current <- function(store = atlas_store(), grid = "draft", config = atlas_ec2_config(), quiet = FALSE) {
  atlas_with_orchestrator_lock("finish-current", config$finish_hours %||% 3,
                               atlas_finish_on_ec2(store, grid, config = config, quiet = quiet))
}
