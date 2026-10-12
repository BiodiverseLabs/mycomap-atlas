# A location prior: every strong map's ranks by 20 km cell, for a reader that
# weighs what a photo shows by where it was taken (MycoMap Vision).
#
# The "what could grow here" index (R/here.R) keeps only the top half of each
# map, because ground a map rates below its median is no answer to "could it
# grow here". A prior needs the rest: below the median, far outside the
# taxon's reach and "no map at all" are three different answers, and the
# index makes all three look the same (missing). So the prior keeps, for each
# taxon with a strong map,
#
#   - every 20 km cell its maps reach, with the mean of its strong models'
#     ranks there (0-100, the rank the maps are coloured by), or NA where the
#     cell is within reach but outside every model's area of applicability:
#     the maps cannot judge that ground;
#   - nothing for cells beyond its reach (500 km from any of its sites), which
#     is the strongest "unlikely" a map can give;
#
# and a taxa table, so a taxon that is not listed reads as "no information",
# not as "unlikely". It is built at finishing from the same per-model ranks as
# the index, so the index is exactly the prior's per-model ranks of 50 and up.
#
# A rank is a percentile within the taxon's own reach, not a probability of
# occurrence, and is not comparable between taxa as it stands: a reader
# calibrates it on held-out records of its own.
#
# One way only: Vision reads this, and Atlas never trains on Vision's output.
# Nothing here comes from records: ranks by 20 km cell, published with the
# maps like the index.

ATLAS_PRIOR_FILES <- c("ranks.parquet", "ranks.tsv.gz", "taxa.tsv", "grid.json",
                       "models.tsv", "aoa.parquet", "aoa.tsv.gz")

atlas_prior_dir <- function(grid = "draft") atlas_path("prior", grid)

atlas_prior_path <- function(file, grid = "draft") {
  if (!file %in% ATLAS_PRIOR_FILES) stop("no prior file called ", file, call. = FALSE)
  file.path(atlas_prior_dir(grid), file)
}

#' A taxon's prior from its strong models' ranks by cell: the union of the
#' cells they reach, each with the mean of the ranks the models give it there
#' (models outside their area of applicability there leave it out), NA when
#' none of them can judge it.
atlas_prior_taxon_ranks <- function(parts) {
  parts <- Filter(function(p) !is.null(p) && nrow(p), parts)
  if (!length(parts)) return(data.frame(cell = integer(), rank = integer(), models = integer(), rank_sd = integer()))
  all <- do.call(rbind, lapply(parts, function(p) p[, c("cell", "rank")]))
  known <- !is.na(all$rank)
  cells <- sort(unique(all$cell))
  out <- data.frame(cell = as.integer(cells), rank = NA_integer_, models = 0L, rank_sd = NA_integer_)
  if (any(known)) {
    r <- all$rank[known]
    at_cell <- all$cell[known]
    sums <- rowsum(r, at_cell)
    squares <- rowsum(r^2, at_cell)
    counts <- rowsum(rep(1, length(r)), at_cell)[, 1]
    at <- match(as.integer(rownames(sums)), out$cell)
    out$rank[at] <- as.integer(round(sums[, 1] / counts))
    # How many strong models judge the cell, and how far apart they are: one
    # model's word, or several that agree, or several that do not.
    out$models[at] <- as.integer(counts)
    variance <- ifelse(counts >= 2, (squares[, 1] - sums[, 1]^2 / counts) / (counts - 1), NA_real_)
    out$rank_sd[at] <- as.integer(round(sqrt(pmax(0, variance))))
  }
  out
}

#' How to find a point's cell, for a reader in another language: the
#' projection, the cell size, the numbering, and a numpy port of
#' atlas_albers and atlas_here_cell that a test holds to them.
atlas_prior_grid <- function(cell_km = ATLAS_HERE_CELL_KM) {
  size <- cell_km * 1000
  ncol <- ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size)
  nrow <- ceiling((ATLAS_GRID_EXTENT[["ymax"]] - ATLAS_GRID_EXTENT[["ymin"]]) / size)
  list(
    crs = ATLAS_CRS,
    crs_note = "North America Albers Equal Area Conic on NAD83 (as ESRI:102008): lat_0 40, lon_0 -96, standard parallels 20 and 60, metres",
    extent = as.list(ATLAS_GRID_EXTENT),
    cell_m = size,
    ncol = ncol,
    nrow = nrow,
    cell_id = paste(
      "col = floor((x - xmin) / cell_m), row = floor((ymax - y) / cell_m),",
      "cell_id = row * ncol + col + 1 (1-based, row-major from the north-west corner);",
      "a point with x outside [xmin, xmax) or y outside (ymin, ymax] has no cell"
    ),
    python = atlas_prior_python(),
    columns = list(
      ranks = list(
        taxon_id = "the taxon's id in taxa.tsv (this release only)",
        cell_id = "the 20 km cell",
        rank = paste(
          "0-100: the mean over the taxon's strong models of each one's rank there, the rank its map is",
          "coloured by (the mean percentile of its 5 km cells, among the cells inside its area of",
          "applicability). Empty (NA) where the cell is within the taxon's reach but outside every",
          "strong model's area of applicability. A cell with no row is beyond the taxon's reach."
        ),
        models = "how many of the taxon's strong models rank the cell (0 where none can judge it)",
        rank_sd = "the standard deviation of those models' ranks, 0-100; empty with fewer than two"
      ),
      models = list(
        model_id = "1, 2, ...: each strong model, for aoa",
        taxon_id = "its taxon in taxa.tsv",
        algorithm = "maxnet, rf, xgboost or esm",
        threshold = "its area-of-applicability threshold: a dissimilarity above it is outside",
        map_strength = "0-1: how far its map beat its null models (0.4 just strong, 1 far above)",
        auc_mean = "its blocked AUC",
        weight = "its weight in the combined map, AUC - 0.5"
      ),
      aoa = list(
        model_id = "the model in models.tsv",
        cell_id = "the 20 km cell",
        dissimilarity = paste("100 x the mean area-of-applicability index of the model's 5 km cells in it;",
                              "compare with 100 x its threshold")
      ),
      taxa = list(
        taxon_id = "1, 2, ... in name order",
        name = "the scientific name Atlas maps it under",
        grade = "strong: only maps that beat nulls keeping their own clustering are in the prior",
        models = "how many strong models it has",
        algorithms = "which, comma separated",
        sites = "independent sites (5 km) its richest model was fitted on",
        map_strength = "0-1: its strong models' map strength, weighted as the combined map weights them",
        reach_cells = "cells with a row in ranks",
        applicable_cells = "cells with a rank (not NA)"
      )
    ),
    reading = paste(
      "A taxon not in taxa.tsv has no strong map: no information, not unlikely.",
      "A rank is a percentile within the taxon's own reach, not a probability, and not comparable",
      "between taxa as it stands: calibrate it on held-out records before weighting by it.",
      "The what-could-grow-here index is the same per-model ranks, kept where they are 50 or more."
    )
  )
}

#' A numpy port of the cell lookup. Kept as text in grid.json; a test runs it
#' against atlas_albers and atlas_here_cell when Python and numpy are there.
atlas_prior_python <- function(cell_km = ATLAS_HERE_CELL_KM) {
  e <- ATLAS_GRID_EXTENT
  paste(c(
    "import numpy as np",
    "",
    "def atlas_cell(lat, lng):",
    "    \"\"\"20 km Atlas cell id (1-based) for WGS84/NAD83 degrees; 0 where off the grid.\"\"\"",
    "    lat = np.asarray(lat, dtype=float); lng = np.asarray(lng, dtype=float)",
    "    a = 6378137.0; f = 1 / 298.257222101; e2 = 2 * f - f * f; e = np.sqrt(e2); rad = np.pi / 180",
    "    def q(phi):",
    "        s = np.sin(phi)",
    "        return (1 - e2) * (s / (1 - e2 * s * s) - (1 / (2 * e)) * np.log((1 - e * s) / (1 + e * s)))",
    "    def m(phi):",
    "        return np.cos(phi) / np.sqrt(1 - e2 * np.sin(phi) ** 2)",
    "    phi0, phi1, phi2, lam0 = 40 * rad, 20 * rad, 60 * rad, -96 * rad",
    "    n = (m(phi1) ** 2 - m(phi2) ** 2) / (q(phi2) - q(phi1))",
    "    C = m(phi1) ** 2 + n * q(phi1)",
    "    rho0 = a * np.sqrt(C - n * q(phi0)) / n",
    "    rho = a * np.sqrt(C - n * q(lat * rad)) / n",
    "    theta = n * (lng * rad - lam0)",
    "    x = rho * np.sin(theta); y = rho0 - rho * np.cos(theta)",
    sprintf("    xmin, xmax, ymin, ymax, size = %s, %s, %s, %s, %s",
            format(e[["xmin"]], scientific = FALSE), format(e[["xmax"]], scientific = FALSE),
            format(e[["ymin"]], scientific = FALSE), format(e[["ymax"]], scientific = FALSE),
            format(cell_km * 1000, scientific = FALSE)),
    "    ncol = int(np.ceil((xmax - xmin) / size))",
    "    col = np.floor((x - xmin) / size); row = np.floor((ymax - y) / size)",
    "    inside = (x >= xmin) & (x < xmax) & (y > ymin) & (y <= ymax)",
    "    return np.where(inside, row * ncol + col + 1, 0).astype(np.int64)"
  ), collapse = "\n")
}

#' Build the prior from every strong map. strong is atlas_strong_map_cells(),
#' read here unless it is passed in (finishing reads the maps once for the
#' index and the prior). Writes ranks.parquet when nanoparquet is installed,
#' and the other files always.
atlas_build_prior <- function(grid = "draft", quiet = FALSE, strong = NULL) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  started <- Sys.time()
  strong <- strong %||% atlas_strong_map_cells(grid, quiet = quiet)
  models <- strong$models
  if (!nrow(models)) stop("no strong maps on the ", grid, " grid to build a prior from", call. = FALSE)

  names <- sort(unique(models$taxon))
  ranks <- vector("list", length(names))
  taxa <- data.frame(taxon_id = seq_along(names), name = names, grade = "strong",
                     models = 0L, algorithms = "", sites = NA_integer_,
                     reach_cells = 0L, applicable_cells = 0L, map_strength = NA_real_,
                     stringsAsFactors = FALSE)
  weight <- pmax(0, as.numeric(models$auc_mean) - 0.5)
  for (k in seq_along(names)) {
    mine <- which(models$taxon == names[[k]])
    taxon <- atlas_prior_taxon_ranks(strong$cells[mine])
    if (nrow(taxon)) {
      ranks[[k]] <- data.frame(taxon_id = k, cell_id = taxon$cell, rank = taxon$rank,
                               models = taxon$models, rank_sd = taxon$rank_sd)
    }
    strength <- as.numeric(models$map_strength[mine])
    w <- weight[mine]
    usable <- is.finite(strength) & is.finite(w) & w > 0
    taxa$map_strength[[k]] <- if (any(usable)) {
      round(sum(w[usable] * strength[usable]) / sum(w[usable]), 3)
    } else if (any(is.finite(strength))) {
      round(mean(strength[is.finite(strength)]), 3)
    } else {
      NA_real_
    }
    taxa$models[[k]] <- length(mine)
    taxa$algorithms[[k]] <- paste(models$algorithm[mine], collapse = ",")
    presences <- suppressWarnings(max(models$presences[mine], na.rm = TRUE))
    taxa$sites[[k]] <- if (is.finite(presences)) as.integer(presences) else NA_integer_
    taxa$reach_cells[[k]] <- nrow(taxon)
    taxa$applicable_cells[[k]] <- sum(!is.na(taxon$rank))
  }
  ranks <- do.call(rbind, ranks)
  if (is.null(ranks)) {
    ranks <- data.frame(taxon_id = integer(), cell_id = integer(), rank = integer(),
                        models = integer(), rank_sd = integer())
  }
  for (column in names(ranks)) ranks[[column]] <- as.integer(ranks[[column]])
  rownames(ranks) <- NULL

  # Each strong model, and the area-of-applicability index of every cell it
  # reaches, beside its own threshold.
  taxon_of <- match(models$taxon, names)
  model_table <- data.frame(
    model_id = seq_len(nrow(models)), taxon_id = taxon_of, algorithm = models$algorithm,
    threshold = round(as.numeric(models$threshold), 4), map_strength = round(as.numeric(models$map_strength), 3),
    auc_mean = round(as.numeric(models$auc_mean), 4), weight = round(weight, 4), stringsAsFactors = FALSE
  )
  aoa <- do.call(rbind, lapply(seq_len(nrow(models)), function(i) {
    part <- strong$cells[[i]]
    if (is.null(part) || !nrow(part) || is.null(part$dissimilarity)) return(NULL)
    data.frame(model_id = i, cell_id = part$cell,
               dissimilarity = as.integer(pmin(65535, round(100 * part$dissimilarity))))
  }))
  if (is.null(aoa)) aoa <- data.frame(model_id = integer(), cell_id = integer(), dissimilarity = integer())
  for (column in names(aoa)) aoa[[column]] <- as.integer(aoa[[column]])
  rownames(aoa) <- NULL

  dir <- atlas_prior_dir(grid)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  # Whatever a previous build left must not outlive it: a Parquet file from an
  # older build beside a newer TSV would disagree with it.
  unlink(file.path(dir, ATLAS_PRIOR_FILES))
  atlas_write_tsv_gz(ranks, atlas_prior_path("ranks.tsv.gz", grid))
  atlas_write_tsv_gz(aoa, atlas_prior_path("aoa.tsv.gz", grid))
  utils::write.table(model_table, atlas_prior_path("models.tsv", grid), sep = "\t", quote = FALSE,
                     row.names = FALSE, na = "", fileEncoding = "UTF-8")
  utils::write.table(taxa, atlas_prior_path("taxa.tsv", grid), sep = "\t", quote = FALSE,
                     row.names = FALSE, na = "", fileEncoding = "UTF-8")
  # No build time: the same maps make the same files, byte for byte.
  grid_def <- c(atlas_prior_grid(strong$cell_km), list(taxa = nrow(taxa), rows = nrow(ranks)))
  atlas_write_json(grid_def, atlas_prior_path("grid.json", grid))
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    schema <- nanoparquet::parquet_schema(
      taxon_id = list("INT", bit_width = 16L, is_signed = FALSE),
      cell_id = "INT32",
      rank = list("INT", bit_width = 8L, is_signed = FALSE),
      models = list("INT", bit_width = 8L, is_signed = FALSE),
      rank_sd = list("INT", bit_width = 8L, is_signed = FALSE)
    )
    nanoparquet::write_parquet(ranks, atlas_prior_path("ranks.parquet", grid), schema = schema,
                               compression = "zstd")
    nanoparquet::write_parquet(aoa, atlas_prior_path("aoa.parquet", grid), compression = "zstd",
                               schema = nanoparquet::parquet_schema(
                                 model_id = list("INT", bit_width = 16L, is_signed = FALSE),
                                 cell_id = "INT32",
                                 dissimilarity = list("INT", bit_width = 16L, is_signed = FALSE)))
  } else {
    say("nanoparquet is not installed: the prior has no Parquet file this time")
  }
  say(sprintf("prior: %d taxa, %s cells in %.0f s",
              nrow(taxa), format(nrow(ranks), big.mark = ","),
              as.numeric(difftime(Sys.time(), started, units = "secs"))))
  invisible(list(ranks = ranks, taxa = taxa, models = model_table, aoa = aoa))
}

#' Read the prior's ranks and taxa back, from the TSV files every build writes.
atlas_read_prior <- function(grid = "draft") {
  ranks_path <- atlas_prior_path("ranks.tsv.gz", grid)
  taxa_path <- atlas_prior_path("taxa.tsv", grid)
  if (!file.exists(ranks_path) || !file.exists(taxa_path)) return(NULL)
  ranks <- utils::read.delim(gzfile(ranks_path), colClasses = "integer", na.strings = "")
  taxa <- utils::read.delim(taxa_path, stringsAsFactors = FALSE, na.strings = "",
                            colClasses = c(name = "character", algorithms = "character"))
  list(ranks = ranks, taxa = taxa)
}

#' Finishing builds both from one read of the maps.
atlas_build_finish_indexes <- function(grid = "draft", quiet = FALSE) {
  strong <- atlas_strong_map_cells(grid, quiet = quiet)
  index <- atlas_build_here_index(grid, quiet = quiet, strong = strong)
  atlas_build_prior(grid, quiet = quiet, strong = strong)
  atlas_build_weak_ranks(grid, quiet = quiet)
  invisible(index)
}

# ---- weak maps, privately ---------------------------------------------------

#' Where finishing leaves the weak maps' ranks for the box to file privately.
#' Not under any path a release's allowlist publishes (R/release.R).
atlas_weak_ranks_path <- function(grid = "draft") {
  atlas_path("unpublished", grid, "weak-ranks.tsv.gz")
}

#' The weak maps' ranks by 20 km cell, flagged weak: taxon, algorithm, cell,
#' rank, as the prior gives strong maps'. For Vision's research only, never
#' published: a weak map has not been shown to beat its own collecting
#' pattern, so the public prior leaves it out. Finishing files it under
#' private/atlas-weak/<release>/ (atlas_apply_finish). NULL when no map is weak.
atlas_build_weak_ranks <- function(grid = "draft", quiet = FALSE) {
  path <- atlas_weak_ranks_path(grid)
  unlink(path)
  models <- atlas_model_index(grid)
  weak <- models[models$map & models$grade %in% "weak", c("taxon", "algorithm"), drop = FALSE]
  if (!nrow(weak)) return(invisible(NULL))
  rows <- lapply(seq_len(nrow(weak)), function(i) {
    raster <- atlas_model_path(weak$taxon[[i]], grid, ".tif", weak$algorithm[[i]])
    if (!file.exists(raster)) return(NULL)
    metrics <- atlas_read_metrics(weak$taxon[[i]], grid, weak$algorithm[[i]])
    cells <- atlas_model_cell_ranks(raster, atlas_model_path(weak$taxon[[i]], grid, ".di.tif", weak$algorithm[[i]]),
                                    as.numeric(metrics$applicability$threshold %||% NA))
    if (!nrow(cells)) return(NULL)
    data.frame(taxon = weak$taxon[[i]], algorithm = weak$algorithm[[i]], grade = "weak",
               cell_id = cells$cell, rank = cells$rank, stringsAsFactors = FALSE)
  })
  table <- do.call(rbind, rows)
  if (is.null(table)) return(invisible(NULL))
  atlas_write_tsv_gz(table, path)
  if (!isTRUE(quiet)) message("weak maps: ", length(unique(table$taxon)), " taxa, ", nrow(table), " rows, kept private")
  invisible(table)
}
