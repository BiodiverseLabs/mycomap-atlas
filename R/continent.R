# The continent export, for MycoMap Vision (its item 5; Vision spec
# docs/atlas-environment.md, arms P2c and H; Steve, 2026-10-12): every strong
# model's rank across the whole grid by 20 km cell, with how far it is
# extrapolating there.
#
# It is built from the full-extent files a strong model's fit writes
# (R/fullextent.R): its suitability and area-of-applicability index over the
# whole grid at 5 km. For each model and 5 km cell the rank is on the model's
# own scale, the one its map is coloured on: inside its accessible area and
# area of applicability, exactly the map's rank; anywhere else, the cell's
# suitability placed among those in-area values (clamped). Unlike the drawn
# full view, no cell is left unranked: Vision weighs a rank by the index
# beside it, so it needs both. Per 20 km cell, as the prior does: the mean
# rank of its 5 km cells, and their mean index.
#
# Where it is built, and where it goes (never published):
#   - when a release is finished, from the release's strong maps:
#     private/atlas-continent/<release>/<grid>/ (R/finish.R files it);
#   - when a prior-only job is finished (R_train), from its refits:
#     private/vision-benchmark/<id>/continent/<grid>/ (R/prioronly.R).
#
# Values beyond a model's area of applicability are extrapolation, which is
# why the maps hatch that ground; that is why this stays private.

ATLAS_CONTINENT_FILES <- c("continent.parquet", "continent.tsv.gz", "taxa.tsv", "grid.json")

ATLAS_CONTINENT_PREFIX <- "private/atlas-continent"

atlas_continent_dir <- function(grid = "draft") atlas_path("unpublished", grid, "continent")

#' A model's rank over the whole grid, on its map's scale and with no cell
#' left unranked: the map's own rank where the map ranks, elsewhere the
#' suitability placed among the in-area values inside the area of
#' applicability.
atlas_full_ranks <- function(full, suitability, dissimilarity, threshold) {
  default <- atlas_map_layers(suitability, dissimilarity, threshold)
  default_full <- terra::extend(default[["rank"]], full)
  if (!terra::compareGeom(default_full, full, stopOnError = FALSE)) {
    default_full <- terra::resample(default_full, full, method = "near")
  }
  rank <- terra::values(default_full, mat = FALSE)
  values <- terra::values(full, mat = FALSE)
  reference <- terra::values(suitability, mat = FALSE)[terra::values(default[["outside"]], mat = FALSE) %in% 0]
  other <- !is.finite(rank) & is.finite(values)
  rank[other] <- atlas_percentile_in(values[other], reference)
  rank
}

#' One model's continent cells: per 20 km cell, the mean of its 5 km ranks
#' (0-100) and the mean of their area-of-applicability index.
atlas_continent_model_cells <- function(full, full_dissimilarity, suitability, dissimilarity, threshold,
                                        cell_km = ATLAS_HERE_CELL_KM) {
  rank <- atlas_full_ranks(full, suitability, dissimilarity, threshold)
  index <- terra::values(full_dissimilarity, mat = FALSE)
  known <- which(is.finite(rank))
  if (!length(known)) return(data.frame(cell = integer(), rank = integer(), dissimilarity = numeric()))
  xy <- terra::xyFromCell(full, known)
  cell <- atlas_here_cell(xy[, 1], xy[, 2], cell_km)
  keep <- !is.na(cell)
  cell <- cell[keep]
  rank <- rank[known][keep]
  index <- index[known][keep]
  counts <- rowsum(rep(1, length(cell)), cell)[, 1]
  out <- data.frame(cell = as.integer(names(counts)),
                    rank = as.integer(round(100 * rowsum(rank, cell)[, 1] / counts)),
                    dissimilarity = NA_real_)
  has <- is.finite(index)
  if (any(has)) {
    sums <- rowsum(index[has], cell[has])
    n <- rowsum(rep(1, sum(has)), cell[has])
    out$dissimilarity[match(as.integer(rownames(sums)), out$cell)] <- sums[, 1] / n[, 1]
  }
  out
}

#' Build the export from every strong model with full-extent files: for each
#' taxon and 20 km cell, rank is the mean over its models (0-100), and aoa the
#' lowest over its models of the cell's mean index over that model's
#' threshold, as a percentage (capped at 255): 100 or less is inside at least
#' one model's area of applicability. NULL when no strong map has a full view.
atlas_build_continent <- function(grid = "draft", quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  dir <- atlas_continent_dir(grid)
  unlink(file.path(dir, ATLAS_CONTINENT_FILES))
  models <- atlas_strong_maps(grid)
  if (!nrow(models)) return(invisible(NULL))
  models$full <- vapply(seq_len(nrow(models)), function(i) {
    atlas_model_path(models$taxon[[i]], grid, ".full.tif", models$algorithm[[i]])
  }, "")
  models <- models[file.exists(models$full), , drop = FALSE]
  if (!nrow(models)) return(invisible(NULL))

  names <- sort(unique(models$taxon))
  pieces <- vector("list", length(names))
  for (k in seq_along(names)) {
    parts <- lapply(which(models$taxon == names[[k]]), function(i) {
      full_index <- sub("[.]full[.]tif$", ".full.di.tif", models$full[[i]])
      cells <- atlas_continent_model_cells(
        terra::rast(models$full[[i]]), terra::rast(full_index), terra::rast(models$raster[[i]]),
        if (file.exists(models$dissimilarity[[i]])) terra::rast(models$dissimilarity[[i]]),
        models$threshold[[i]]
      )
      threshold <- models$threshold[[i]]
      cells$ratio <- if (is.finite(threshold) && threshold > 0) cells$dissimilarity / threshold else 0
      cells
    })
    all <- do.call(rbind, parts)
    if (is.null(all) || !nrow(all)) next
    counts <- rowsum(rep(1, nrow(all)), all$cell)[, 1]
    lowest <- tapply(all$ratio, all$cell, function(x) if (any(is.finite(x))) min(x, na.rm = TRUE) else NA_real_)
    cells <- as.integer(names(counts))
    pieces[[k]] <- data.frame(
      taxon_id = k, cell_id = cells,
      rank = as.integer(round(rowsum(all$rank, all$cell)[, 1] / counts)),
      aoa = as.integer(pmin(255, round(100 * ifelse(is.finite(lowest[as.character(cells)]),
                                                    lowest[as.character(cells)], 2.55))))
    )
  }
  table <- do.call(rbind, pieces)
  if (is.null(table)) return(invisible(NULL))
  for (column in names(table)) table[[column]] <- as.integer(table[[column]])
  rownames(table) <- NULL
  taxa <- data.frame(taxon_id = seq_along(names), name = names, grade = "strong",
                     models = vapply(names, function(n) sum(models$taxon == n), 0L),
                     algorithms = vapply(names, function(n) paste(models$algorithm[models$taxon == n], collapse = ","), ""),
                     stringsAsFactors = FALSE)
  rownames(taxa) <- NULL

  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
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
      rank = paste("0-100: the mean over the taxon's strong models of the mean rank of the cell's 5 km cells,",
                   "each on its model's own scale (the one its map is coloured on): the map's rank where the",
                   "map ranks, elsewhere the suitability placed among the in-area values"),
      aoa = paste("the lowest over the taxon's models of the cell's mean area-of-applicability index over",
                  "that model's threshold, as a percentage (capped at 255): 100 or less is inside at least",
                  "one model's area of applicability; above, the models are extrapolating")
    ),
    taxa = list(taxon_id = "1, 2, ... in name order", name = "the name Atlas maps it under",
                grade = "strong", models = "strong models with a full view", algorithms = "which")
  )
  definition$reading <- paste(
    "Continent-wide: every land cell of the grid has a row for every listed taxon. Beyond the area of",
    "applicability (aoa above 100) a rank is extrapolation: weigh it down or leave it out. Where a cell",
    "lies wholly inside the accessible area and the area of applicability its rank is the prior's.",
    "Private: never published."
  )
  definition$taxa <- nrow(taxa)
  definition$rows <- nrow(table)
  atlas_write_json(definition, file.path(dir, "grid.json"))
  say(sprintf("continent: %d taxa, %s rows", nrow(taxa), format(nrow(table), big.mark = ",")))
  invisible(list(table = table, taxa = taxa))
}
