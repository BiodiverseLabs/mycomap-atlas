# A model's continent-wide projection, for MycoMap Vision (its item 5; Vision
# spec docs/atlas-environment.md, arms P2c and H; Steve, 2026-10-12).
#
# A map is predicted only inside its 500 km accessible area (R/fit.R masks
# before predicting), so used as a range its edge is a 500 km cutoff. Vision
# wants to know what each strong model says about habitat beyond it, weighted
# by how far the model is extrapolating there. So a fit with continent = TRUE
# also predicts every 20 km cell of the grid, and writes beside its map
#
#   <taxon>.cont.tif   band 1 rank: the cell's suitability as a percentile
#                      (0-100) of the model's own suitability over its in-area
#                      cells inside its area of applicability, the ground its
#                      map is coloured over, so the scale matches the map's;
#                      band 2 dissimilarity: the cell's area-of-applicability
#                      index (R/aoa.R), inside where it is at most the model's
#                      own threshold.
#
# Both are predicted on predictors averaged over each 20 km cell (16 cells of
# the 5 km grid), not on 5 km cells averaged afterwards: a continent at 5 km
# is about two million cells per model, and the area-of-applicability index
# is a nearest-neighbour search over the training sites, so 5 km would cost
# minutes a model. Averaging smooths a cell's extremes, so its index is a
# little lower than the mean of its 5 km cells' would be, and its rank is not
# the mean of 5 km ranks the prior and the index use: in-area values here are
# close to theirs but not equal. Every predictor is a continuous value or a
# share, so a mean is meaningful. The index is compared with the model's own
# threshold, set at 5 km; a 20 km mean is never exactly a training site, so
# the index has a small floor there, and a model whose threshold is near zero
# can see ground it knows called outside. Real thresholds sit well above it.
#
# Only prior-only jobs set it (R/prioronly.R), and nothing it writes is
# public: the release allowlist refuses .cont.tif (R/release.R), and the
# products built from it are private. Values outside a model's area of
# applicability are extrapolation, which is why the maps hatch that ground.
# The in-area map, its dissimilarity layer and its scores are the same with
# continent on or off.

ATLAS_CONTINENT_EXT <- ".cont.tif"

# The aggregated predictors and their values, kept between fits in one
# process: every fit on a worker shares one stack.
atlas_continent_cache <- new.env(parent = emptyenv())

#' The predictor stack averaged over cell_km cells, with its values. Cached
#' for a stack read from files.
atlas_continent_stack <- function(stack, cell_km = ATLAS_HERE_CELL_KM) {
  sources <- terra::sources(stack)
  key <- if (all(nzchar(sources))) paste(c(sources, names(stack), cell_km), collapse = "|") else NULL
  if (!is.null(key) && identical(atlas_continent_cache$key, key)) return(atlas_continent_cache$value)
  fact <- max(1L, as.integer(round(cell_km * 1000 / terra::res(stack)[[1]])))
  coarse <- terra::aggregate(stack, fact = fact, fun = "mean", na.rm = TRUE)
  values <- terra::values(coarse, dataframe = TRUE)
  value <- list(stack = coarse, values = values, complete = stats::complete.cases(values))
  if (!is.null(key)) {
    atlas_continent_cache$key <- key
    atlas_continent_cache$value <- value
  }
  value
}

#' Where values fall among a reference, as atlas_rank_scale ranks the
#' reference itself: a value in it gets its rank, (rank - 1) / (n - 1) with
#' ties at their average; a value between two gets the midpoint of their
#' ranks; a value beyond the reference gets 0 or 1.
atlas_percentile_in <- function(values, reference) {
  reference <- sort(reference[is.finite(reference)])
  n <- length(reference)
  out <- rep(NA_real_, length(values))
  ok <- is.finite(values)
  if (!n || !any(ok)) return(out)
  if (n == 1L) {
    out[ok] <- 1
    return(out)
  }
  below <- findInterval(values[ok], reference, left.open = TRUE)
  through <- findInterval(values[ok], reference)
  equal <- through - below
  position <- ifelse(equal > 0, below + (equal - 1) / 2, below - 0.5)
  out[ok] <- pmin(1, pmax(0, position / (n - 1)))
  out
}

#' Project a fitted model over the whole grid at cell_km. suitability and
#' dissimilarity are its in-area 5 km layers, the reference for the rank.
atlas_continent_projection <- function(model, score, aoa, stack, suitability, dissimilarity,
                                       cell_km = ATLAS_HERE_CELL_KM) {
  coarse <- atlas_continent_stack(stack, cell_km)
  in_area <- terra::values(suitability, mat = FALSE)
  index <- if (is.null(dissimilarity)) rep(NA_real_, length(in_area)) else terra::values(dissimilarity, mat = FALSE)
  threshold <- as.numeric(aoa$threshold %||% NA)
  inside <- is.finite(in_area) & (!is.finite(threshold) | (is.finite(index) & index <= threshold))
  reference <- if (any(inside)) in_area[inside] else in_area[is.finite(in_area)]

  rows <- which(coarse$complete)
  newdata <- coarse$values[rows, , drop = FALSE]
  rank <- rep(NA_real_, nrow(coarse$values))
  dissim <- rep(NA_real_, nrow(coarse$values))
  rank[rows] <- round(100 * atlas_percentile_in(score(model, newdata), reference))
  dissim[rows] <- atlas_aoa_index(aoa, newdata)

  layers <- terra::rast(coarse$stack, nlyrs = 2)
  terra::values(layers) <- cbind(rank, dissim)
  names(layers) <- c("rank", "dissimilarity")
  list(
    layers = layers,
    summary = list(
      cell_km = cell_km,
      cells = length(rows),
      inside_cells = if (is.finite(threshold)) sum(dissim[rows] <= threshold, na.rm = TRUE) else length(rows),
      threshold = if (is.finite(threshold)) threshold else NULL,
      reference = "in-area suitability inside the area of applicability, as the map is coloured",
      predictors = "averaged over each cell"
    )
  )
}

#' Write a projection beside the model's map.
atlas_write_continent <- function(projection, name, grid, algorithm) {
  path <- atlas_model_path(name, grid, ATLAS_CONTINENT_EXT, algorithm = algorithm)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(projection$layers, path, overwrite = TRUE, datatype = "FLT4S",
                     gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES"))
  invisible(path)
}

# ---- the export ------------------------------------------------------------

ATLAS_CONTINENT_FILES <- c("continent.parquet", "continent.tsv.gz", "taxa.tsv", "grid.json")

atlas_continent_dir <- function(grid = "draft") atlas_path("continent", grid)

#' Every strong model's projection, combined per taxon: for each taxon with a
#' strong map and each 20 km cell, rank is the mean of its models' ranks there
#' (0-100), and aoa the lowest of its models' dissimilarity over threshold,
#' as a percentage: 100 or less means inside at least one model's area of
#' applicability. Written as Parquet when nanoparquet is installed, and as TSV
#' when it is not (the table is large: taxa x land cells).
atlas_build_continent <- function(grid = "draft", quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  models <- atlas_strong_maps(grid)
  models$continent <- vapply(seq_len(nrow(models)), function(i) {
    atlas_model_path(models$taxon[[i]], grid, ATLAS_CONTINENT_EXT, models$algorithm[[i]])
  }, "")
  models <- models[file.exists(models$continent), , drop = FALSE]
  if (!nrow(models)) stop("no strong maps with a continent projection on the ", grid, " grid", call. = FALSE)

  names <- sort(unique(models$taxon))
  pieces <- vector("list", length(names))
  cell_ids <- NULL
  for (k in seq_along(names)) {
    mine <- which(models$taxon == names[[k]])
    ranks <- NULL
    ratio <- NULL
    for (i in mine) {
      r <- terra::rast(models$continent[[i]])
      if (is.null(cell_ids)) {
        xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
        cell_ids <- atlas_here_cell(xy[, 1], xy[, 2], round(terra::res(r)[[1]] / 1000))
      }
      v <- terra::values(r, mat = TRUE)
      threshold <- models$threshold[[i]]
      this_ratio <- if (is.finite(threshold) && threshold > 0) v[, 2] / threshold else rep(0, nrow(v))
      ranks <- cbind(ranks, v[, 1])
      ratio <- cbind(ratio, this_ratio)
    }
    rank <- rowMeans(ranks, na.rm = TRUE)
    lowest <- suppressWarnings(apply(ratio, 1, min, na.rm = TRUE))
    keep <- is.finite(rank) & !is.na(cell_ids)
    pieces[[k]] <- data.frame(
      taxon_id = k, cell_id = as.integer(cell_ids[keep]),
      rank = as.integer(round(rank[keep])),
      aoa = as.integer(pmin(255, round(100 * ifelse(is.finite(lowest[keep]), lowest[keep], 2.55))))
    )
  }
  table <- do.call(rbind, pieces)
  table$taxon_id <- as.integer(table$taxon_id)
  taxa <- data.frame(taxon_id = seq_along(names), name = names, grade = "strong",
                     models = vapply(names, function(n) sum(models$taxon == n), 0L),
                     algorithms = vapply(names, function(n) paste(models$algorithm[models$taxon == n], collapse = ","), ""),
                     stringsAsFactors = FALSE)
  rownames(taxa) <- NULL

  dir <- atlas_continent_dir(grid)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  unlink(file.path(dir, ATLAS_CONTINENT_FILES))
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    schema <- nanoparquet::parquet_schema(
      taxon_id = list("INT", bit_width = 16L, is_signed = FALSE),
      cell_id = "INT32",
      rank = list("INT", bit_width = 8L, is_signed = FALSE),
      aoa = list("INT", bit_width = 8L, is_signed = FALSE)
    )
    nanoparquet::write_parquet(table, file.path(dir, "continent.parquet"), schema = schema, compression = "zstd")
  } else {
    atlas_write_tsv_gz(table, file.path(dir, "continent.tsv.gz"))
  }
  utils::write.table(taxa, file.path(dir, "taxa.tsv"), sep = "\t", quote = FALSE, row.names = FALSE,
                     fileEncoding = "UTF-8")
  definition <- atlas_prior_grid()
  definition$columns <- list(
    continent = list(
      taxon_id = "the taxon's id in taxa.tsv (this build only)",
      cell_id = "the 20 km cell (numbering as in python)",
      rank = paste("0-100: the mean over the taxon's strong models of the cell's suitability as a percentile of",
                   "each model's own in-area suitability inside its area of applicability (the scale its map",
                   "is coloured on), predicted on predictors averaged over the 20 km cell"),
      aoa = paste("the lowest over the taxon's models of the cell's area-of-applicability index divided by that",
                  "model's threshold, as a percentage (capped at 255): 100 or less is inside at least one",
                  "model's area of applicability; above, the models are extrapolating")
    ),
    taxa = list(taxon_id = "1, 2, ... in name order", name = "the name Atlas maps it under",
                grade = "strong", models = "strong models with a projection", algorithms = "which")
  )
  definition$reading <- paste(
    "Continent-wide, every land cell of the grid has a row for every listed taxon, inside the taxon's",
    "reach or not. Beyond the area of applicability (aoa above 100) a rank is extrapolation: weigh it down",
    "or leave it out. In-area cells are close to, not equal to, the prior's ranks, which average 5 km ranks.",
    "Private: never published."
  )
  definition$taxa <- nrow(taxa)
  definition$rows <- nrow(table)
  atlas_write_json(definition, file.path(dir, "grid.json"))
  say(sprintf("continent: %d taxa, %s rows", nrow(taxa), format(nrow(table), big.mark = ",")))
  invisible(list(table = table, taxa = taxa))
}
