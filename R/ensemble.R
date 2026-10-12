# One map from several: the ensemble, and where its members disagree.
#
# Atlas fits up to three models per taxon (Maxent, boosted trees, a forest),
# or the small-model ensemble for a sparse taxon. Shown side by side, they
# leave the reader to judge where they agree. The ensemble does that for
# them. Each member that passed its null test is ranked over the ground inside
# its own area of applicability (R/aoa.R), and the ranks are averaged, each
# member weighted by how far its blocked AUC is above chance (AUC - 0.5).
#
# Beside the average is a disagreement layer: the weighted standard deviation
# of the members' ranks at each cell. It is 0 where they agree and reaches 0.5
# where two members put the cell at opposite ends of their ranking.
#
# A cell takes its average only from members whose area of applicability
# holds it. A cell no member knows is outside the ensemble's area as well and
# is hatched. With fewer than ATLAS_ENSEMBLE_MIN_MEMBERS passing members there
# is no ensemble: the one map is the answer.
#
# Ensembles are built after the models, from their stored rasters, and are
# built again whenever a member's raster changes; each member's md5 is kept.

ATLAS_ENSEMBLE_MIN_MEMBERS <- 2L
# The disagreement map runs from clear (members agree) to this colour at 0.5.
ATLAS_DISAGREEMENT_COLOUR <- c(red = 168, green = 113, blue = 70)

#' Where a taxon's ensemble files live.
atlas_ensemble_path <- function(name, grid = "draft", extension = ".tif") {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  atlas_path("models", grid, "ensemble", paste0(slug, extension))
}

#' A taxon's models that can join its ensemble: strong ones (atlas_map_grade)
#' with a map, with their weights.
atlas_ensemble_members <- function(name, grid = "draft") {
  members <- lapply(names(ATLAS_ALGORITHMS), function(algorithm) {
    metrics <- atlas_read_metrics(name, grid, algorithm)
    raster <- atlas_model_path(name, grid, ".tif", algorithm)
    if (is.null(metrics) || !identical(atlas_metrics_grade(metrics), "strong") || !file.exists(raster)) {
      return(NULL)
    }
    auc <- as.numeric(metrics$auc_mean %||% NA)
    weight <- if (is.finite(auc)) max(0, auc - 0.5) else 0
    if (weight <= 0) return(NULL)
    dissimilarity <- atlas_model_path(name, grid, ".di.tif", algorithm)
    list(
      algorithm = algorithm, weight = round(weight, 4), auc_mean = auc,
      map_strength = as.numeric(metrics$map_strength %||% atlas_map_strength(metrics$null, metrics$skill)),
      raster = raster, md5 = unname(tools::md5sum(raster)),
      dissimilarity = if (file.exists(dissimilarity)) dissimilarity,
      threshold = as.numeric(metrics$applicability$threshold %||% NA)
    )
  })
  Filter(Negate(is.null), members)
}

#' Combine members' surfaces into the ensemble's layers.
#'
#' surfaces is a list of single-layer rasters on one grid; dissimilarity a
#' list of their dissimilarity layers (or NULL entries); thresholds and
#' weights one per member. Returns three layers: rank (the weighted mean of
#' the members' ranks), disagreement (the weighted standard deviation, where
#' two or more members know the cell) and known (the share of the members'
#' weight whose area holds the cell).
atlas_ensemble_layers <- function(surfaces, dissimilarity, thresholds, weights) {
  extent <- Reduce(terra::union, lapply(surfaces, terra::ext))
  surfaces <- lapply(surfaces, terra::extend, y = extent)
  ranks <- vapply(seq_along(surfaces), function(i) {
    values <- terra::values(surfaces[[i]], mat = FALSE)
    inside <- is.finite(values)
    layer <- dissimilarity[[i]]
    if (!is.null(layer) && is.finite(thresholds[[i]])) {
      index <- terra::values(terra::extend(layer, extent), mat = FALSE)
      inside <- inside & !(is.finite(index) & index > thresholds[[i]])
    }
    out <- rep(NA_real_, length(values))
    out[inside] <- atlas_rank_scale(values[inside])
    out
  }, numeric(terra::ncell(surfaces[[1]])))
  ranks <- matrix(ranks, ncol = length(surfaces))
  known <- is.finite(ranks)
  w <- matrix(weights, nrow = nrow(ranks), ncol = ncol(ranks), byrow = TRUE) * known
  total <- rowSums(w)
  filled <- ranks
  filled[!known] <- 0
  mean_rank <- ifelse(total > 0, rowSums(w * filled) / total, NA_real_)
  spread <- ifelse(rowSums(known) >= 2L,
                   sqrt(pmax(0, rowSums(w * (filled - mean_rank)^2) / total)), NA_real_)
  any_value <- rowSums(vapply(surfaces, function(r) is.finite(terra::values(r, mat = FALSE)),
                              logical(terra::ncell(surfaces[[1]])))) > 0
  share <- ifelse(any_value, total / sum(weights), NA_real_)
  out <- terra::rast(surfaces[[1]], nlyrs = 3)
  terra::values(out) <- cbind(mean_rank, spread, share)
  names(out) <- c("rank", "disagreement", "known")
  out
}

#' Draw the disagreement layer: clear where the members agree, brown where
#' they are at opposite ends.
atlas_write_disagreement_png <- function(disagreement, path, max_pixels = 1600) {
  mercator <- atlas_map_warp(disagreement, max_pixels)
  values <- pmin(1, pmax(0, terra::values(mercator)[, 1] / 0.5))
  usable <- is.finite(values)
  colours <- cbind(
    matrix(ATLAS_DISAGREEMENT_COLOUR, nrow = length(values), ncol = 3, byrow = TRUE),
    ifelse(usable, round(220 * values), 0)
  )
  colnames(colours) <- c("red", "green", "blue", "alpha")
  atlas_write_rgba_png(mercator, colours, path)
}

#' Whether a stored ensemble was built from exactly these members.
atlas_ensemble_is_current <- function(metrics, members) {
  if (is.null(metrics) || !length(metrics$members)) return(FALSE)
  stored <- vapply(metrics$members, function(m) paste(m$algorithm, m$md5), character(1))
  now <- vapply(members, function(m) paste(m$algorithm, m$md5), character(1))
  setequal(stored, now) && file.exists(atlas_ensemble_path(metrics$taxon, metrics$grid %||% "draft"))
}

#' Remove a taxon's ensemble files.
atlas_remove_ensemble <- function(name, grid = "draft") {
  paths <- atlas_ensemble_path(name, grid, c(".json", ".tif", ".png", ".disagreement.png",
                                              ".png.aux.xml", ".disagreement.png.aux.xml"))
  existed <- file.exists(paths)
  unlink(paths[existed])
  invisible(any(existed))
}

#' Build, or rebuild, one taxon's ensemble. Returns its metrics, or NULL when
#' the taxon has too few passing members (any old ensemble is removed).
atlas_build_ensemble <- function(name, grid = "draft", force = FALSE) {
  members <- atlas_ensemble_members(name, grid)
  if (length(members) < ATLAS_ENSEMBLE_MIN_MEMBERS) {
    atlas_remove_ensemble(name, grid)
    return(NULL)
  }
  json <- atlas_ensemble_path(name, grid, ".json")
  existing <- if (file.exists(json)) tryCatch(jsonlite::fromJSON(json, simplifyVector = FALSE),
                                              error = function(e) NULL)
  if (!isTRUE(force) && atlas_ensemble_is_current(existing, members)) {
    return(existing)
  }
  layers <- atlas_ensemble_layers(
    lapply(members, function(m) terra::rast(m$raster)),
    lapply(members, function(m) if (!is.null(m$dissimilarity)) terra::rast(m$dissimilarity)),
    vapply(members, function(m) m$threshold, numeric(1)),
    vapply(members, function(m) m$weight, numeric(1))
  )
  raster <- atlas_ensemble_path(name, grid, ".tif")
  dir.create(dirname(raster), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(layers, raster, overwrite = TRUE,
                     gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES"))
  # Ground no member knows is drawn hatched: its "dissimilarity" is whether
  # any member's area holds it.
  outside <- terra::ifel(is.na(layers[["rank"]]) & !is.na(layers[["known"]]), 1, 0)
  drawn <- atlas_write_map_png(layers[["rank"]], atlas_ensemble_path(name, grid, ".png"),
                               dissimilarity = outside, threshold = 0.5)
  disagreement <- atlas_write_disagreement_png(layers[["disagreement"]],
                                               atlas_ensemble_path(name, grid, ".disagreement.png"))
  spread <- terra::values(layers[["disagreement"]], mat = FALSE)
  spread <- spread[is.finite(spread)]
  known <- terra::values(layers[["known"]], mat = FALSE)
  known <- known[is.finite(known)]
  weights <- vapply(members, function(m) m$weight, numeric(1))
  metrics <- list(
    taxon = name, grid = grid,
    method = "weighted mean of members' ranks inside their areas of applicability; weight = blocked AUC - 0.5",
    members = lapply(members, function(m) m[c("algorithm", "weight", "auc_mean", "map_strength", "md5")]),
    map_strength = round(sum(weights * vapply(members, function(m) m$map_strength, numeric(1))) /
                           sum(weights), 3),
    known_share = if (length(known)) round(mean(known > 0), 4) else NA_real_,
    disagreement_mean = if (length(spread)) round(mean(spread), 4) else NA_real_,
    disagreement_high_share = if (length(spread)) round(mean(spread > 0.25), 4) else NA_real_,
    map = basename(drawn$path), bounds = drawn$bounds, map_scale = drawn$scale,
    disagreement_map = basename(disagreement$path),
    raster = basename(raster),
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  atlas_write_json(metrics, json)
  metrics
}

#' Build the ensemble of every taxon with two or more passing members.
atlas_build_ensembles <- function(grid = "draft", force = FALSE, quiet = FALSE) {
  index <- atlas_model_index(grid)
  passed <- index[index$grade %in% "strong" & index$map, , drop = FALSE]
  counts <- table(passed$taxon)
  taxa <- names(counts)[counts >= ATLAS_ENSEMBLE_MIN_MEMBERS]
  # A taxon that has dropped below two passing members loses its ensemble.
  stale <- setdiff(unique(index$taxon), taxa)
  for (name in stale) atlas_remove_ensemble(name, grid)
  built <- 0L
  for (name in taxa) {
    result <- tryCatch(atlas_build_ensemble(name, grid, force = force), error = function(e) {
      message("  ensemble failed for ", name, ": ", conditionMessage(e))
      NULL
    })
    if (!is.null(result)) built <- built + 1L
  }
  if (!isTRUE(quiet)) message(built, " ensembles on the ", grid, " grid")
  invisible(built)
}
