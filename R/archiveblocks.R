# A deposit's maps drawn in whole 50 km blocks (R/blocks.R), in the bundle's
# own tree only: the release in the store, and this machine's data, are never
# written.
#
# In the tree, each model's map is drawn in blocks of its own accessible area,
# built again from the pull its job fitted it on, exactly as finishing does
# (atlas_block_trim_release), and its picture redrawn. Its scores keep every
# field as published but two: bounds, from the trimmed map, and regions,
# counted again from the trimmed map's cells (with the release's own
# collection cells). A combined map is drawn in its taxon's kept blocks. The
# prior and Explore tables keep the rows of 20 km cells wholly inside a
# map's kept blocks, each kept row as it was. A map whose area cannot be
# built again stops the bundle.

#' Where a release's predictors have values, written into dir: the layer set
#' is fetched into a data directory of its own under dir.
atlas_archive_block_land <- function(store, grid, layers_key, dir) {
  given <- getOption("atlas.block_land")
  if (!is.null(given)) return(given)
  atlas_with_data_dir(file.path(dir, "data"), atlas_block_land_file(store, grid, layers_key))
}

#' Run code with ATLAS_DATA_DIR set to dir, and set back after.
atlas_with_data_dir <- function(dir, code) {
  old <- Sys.getenv("ATLAS_DATA_DIR", unset = NA)
  Sys.setenv(ATLAS_DATA_DIR = dir)
  on.exit(if (is.na(old)) Sys.unsetenv("ATLAS_DATA_DIR") else Sys.setenv(ATLAS_DATA_DIR = old), add = TRUE)
  force(code)
}

#' A release's collection cells as its tree holds them (public/cells.tsv.gz),
#' or NULL.
atlas_archive_tree_cells <- function(tree) {
  path <- file.path(tree, "public", "cells.tsv.gz")
  if (!file.exists(path)) return(NULL)
  utils::read.delim(gzfile(path), sep = "\t", quote = "", comment.char = "",
                    colClasses = c("character", "numeric", "numeric", "integer"),
                    check.names = FALSE, stringsAsFactors = FALSE)
}

#' Draw a combined map's pictures again from its raster, beside it, as
#' atlas_build_ensemble draws them. Returns the map picture's bounds.
atlas_ensemble_redraw <- function(raster_path) {
  layers <- terra::rast(raster_path)
  outside <- terra::ifel(is.na(layers[["rank"]]) & !is.na(layers[["known"]]), 1, 0)
  drawn <- atlas_write_map_png(layers[["rank"]], sub("[.]tif$", ".png", raster_path),
                               dissimilarity = outside, threshold = 0.5)
  atlas_write_disagreement_png(layers[["disagreement"]], sub("[.]tif$", ".disagreement.png", raster_path))
  drawn$bounds
}

#' Whether each 20 km cell (numbered as the Explore index and the prior number
#' them) lies wholly inside the given blocks (atlas_block_ids).
atlas_archive_cells_inside <- function(cells, ids, cell_km = ATLAS_HERE_CELL_KM, block_km = ATLAS_BLOCK_KM) {
  if (!length(cells)) return(logical())
  size <- cell_km * 1000
  block <- block_km * 1000
  ncol <- ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size)
  row <- (as.numeric(cells) - 1) %/% ncol
  col <- (as.numeric(cells) - 1) %% ncol
  # The blocks a cell's square touches: its first and last metre on each axis.
  c0 <- floor(col * size / block); c1 <- floor(((col + 1) * size - 1) / block)
  r0 <- floor(row * size / block); r1 <- floor(((row + 1) * size - 1) / block)
  inside <- function(r, c) (r * 100000 + c) %in% ids
  inside(r0, c0) & inside(r0, c1) & inside(r1, c0) & inside(r1, c1)
}

#' Keep the rows of a gzipped table whose fields pass keep(row): every kept
#' line, the header among them, exactly as it was.
atlas_archive_filter_tsv_gz <- function(path, keep) {
  lines <- readLines(gzfile(path), encoding = "UTF-8", warn = FALSE)
  if (length(lines) < 2L) return(invisible(0L))
  fields <- strsplit(lines[-1L], "\t", fixed = TRUE)
  table <- as.data.frame(do.call(rbind, lapply(fields, function(f) f[seq_len(length(strsplit(lines[[1]], "\t")[[1]]))])),
                         stringsAsFactors = FALSE)
  names(table) <- strsplit(lines[[1]], "\t", fixed = TRUE)[[1]]
  kept <- keep(table)
  con <- gzfile(path, "wb")
  on.exit(close(con), add = TRUE)
  writeLines(c(lines[[1]], lines[-1L][kept]), con, useBytes = TRUE)
  invisible(sum(!kept))
}

#' The prior in a tree, with only the rows of 20 km cells wholly inside a
#' map's kept blocks: ranks (by taxon) inside its maps' blocks, applicability
#' (by model) inside that model's. Kept rows are as they were; grid.json
#' counts the rows kept.
atlas_archive_prior_rows <- function(dir, taxa_blocks, model_blocks) {
  if (!dir.exists(dir)) return(invisible(NULL))
  read_tsv <- function(name) utils::read.delim(file.path(dir, name), stringsAsFactors = FALSE, quote = "")
  taxa <- if (file.exists(file.path(dir, "taxa.tsv"))) read_tsv("taxa.tsv")
  models <- if (file.exists(file.path(dir, "models.tsv"))) read_tsv("models.tsv")
  keep_rank <- function(t) {
    name <- taxa$name[match(as.integer(t$taxon_id), taxa$taxon_id)]
    out <- logical(nrow(t))
    for (n in unique(name)) {
      at <- which(name == n)
      out[at] <- atlas_archive_cells_inside(t$cell_id[at], taxa_blocks[[n]] %||% numeric())
    }
    out
  }
  keep_aoa <- function(t) {
    m <- match(as.integer(t$model_id), models$model_id)
    key <- paste(taxa$name[match(models$taxon_id[m], taxa$taxon_id)], models$algorithm[m], sep = "\x1f")
    out <- logical(nrow(t))
    for (k in unique(key)) {
      at <- which(key == k)
      out[at] <- atlas_archive_cells_inside(t$cell_id[at], model_blocks[[k]] %||% numeric())
    }
    out
  }
  dropped <- c(ranks = 0L, aoa = 0L)
  if (file.exists(file.path(dir, "ranks.tsv.gz")) && !is.null(taxa)) {
    dropped[["ranks"]] <- atlas_archive_filter_tsv_gz(file.path(dir, "ranks.tsv.gz"), keep_rank)
  }
  if (file.exists(file.path(dir, "aoa.tsv.gz")) && !is.null(models)) {
    dropped[["aoa"]] <- atlas_archive_filter_tsv_gz(file.path(dir, "aoa.tsv.gz"), keep_aoa)
  }
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    for (name in c("ranks", "aoa")) {
      parquet <- file.path(dir, paste0(name, ".parquet"))
      if (!file.exists(parquet)) next
      table <- as.data.frame(nanoparquet::read_parquet(parquet))
      kept <- if (name == "ranks") keep_rank(table) else keep_aoa(table)
      atlas_prior_write_parquet(table[kept, , drop = FALSE], parquet, name)
    }
  }
  grid_json <- file.path(dir, "grid.json")
  if (file.exists(grid_json) && file.exists(file.path(dir, "ranks.tsv.gz"))) {
    grid_def <- jsonlite::fromJSON(grid_json, simplifyVector = FALSE)
    grid_def$rows <- length(readLines(gzfile(file.path(dir, "ranks.tsv.gz")), warn = FALSE)) - 1L
    atlas_write_json(grid_def, grid_json)
  }
  invisible(dropped)
}

#' The Explore index in a tree, with only the entries of 20 km cells wholly
#' inside the entry's map's kept blocks (a combined map's: its taxon's).
atlas_archive_here_rows <- function(path, taxa_blocks, model_blocks) {
  if (!file.exists(path)) return(invisible(0L))
  index <- readRDS(path)
  counts <- diff(as.integer(index$start))
  cells <- rep(seq_along(counts), counts)
  entries <- as.integer(index$model)
  taxon <- as.character(index$models$taxon[entries])
  algorithm <- as.character(index$models$algorithm[entries])
  key <- paste(taxon, algorithm, sep = "\x1f")
  keep <- logical(length(entries))
  for (k in unique(key)) {
    at <- which(key == k)
    ids <- model_blocks[[k]] %||% taxa_blocks[[taxon[at[[1]]]]] %||% numeric()
    keep[at] <- atlas_archive_cells_inside(cells[at], ids, index$cell_km %||% ATLAS_HERE_CELL_KM)
  }
  kept_cells <- cells[keep]
  index$model <- index$model[keep]
  index$rank <- index$rank[keep]
  index$start <- as.integer(c(1L, 1L + cumsum(tabulate(kept_cells, nbins = length(counts)))))
  saveRDS(index, path)
  invisible(sum(!keep))
}

#' Draw a bundle tree's maps in blocks (see the top of this file). Returns
#' what it did, in counts.
atlas_archive_block_tree <- function(store, tree, manifest, grid = "draft", workers = 1L, quiet = FALSE,
                                     dir = dirname(tree), trim = atlas_block_trim_release) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  land_path <- atlas_archive_block_land(store, grid, manifest$layers_key, dir)
  rasters <- atlas_with_data_dir(tree, atlas_model_map_rasters(grid))
  json_of <- function(p) sub("[.]tif$", ".json", p)
  published <- stats::setNames(lapply(rasters, function(p) jsonlite::fromJSON(json_of(p), simplifyVector = FALSE)),
                               rasters)
  done <- trim(store, land_path, grid, index = manifest$index, workers = workers, quiet = quiet,
               rasters = rasters, blocks = TRUE)
  if (length(done$not_drawn) || isTRUE(done$none > 0)) {
    stop("the deposit is not built: ", length(done$not_drawn), " maps could not be drawn in blocks (",
         done$not_found, " whose record set no kept pull holds, ", done$mismatch,
         " whose area did not give the map as stored)", call. = FALSE)
  }
  cells <- atlas_archive_tree_cells(tree)
  taxa_blocks <- list()
  model_blocks <- list()
  for (path in rasters) {
    before <- published[[path]]
    after <- jsonlite::fromJSON(json_of(path), simplifyVector = FALSE)
    out <- before
    out$bounds <- after$bounds
    if (!is.null(before$regions)) {
      mine <- if (is.null(cells)) cells else cells[cells$taxon == before$taxon, , drop = FALSE]
      xy <- atlas_albers(mine$lat, mine$lng)
      regions <- atlas_region_counts(path, xy[, "x"], xy[, "y"])
      if (!is.null(regions)) regions$from <- before$regions$from %||% "collection cells"
      out$regions <- regions
    }
    atlas_write_json(out, json_of(path))
    ids <- done$blocks[[path]] %||% numeric()
    algorithm <- atlas_json_string(before$algorithm) %||% "maxnet"
    model_blocks[[paste(before$taxon, algorithm, sep = "\x1f")]] <- ids
    taxa_blocks[[before$taxon]] <- sort(unique(c(taxa_blocks[[before$taxon]], ids)))
  }
  ensembles <- list.files(file.path(tree, "models", grid, "ensemble"), pattern = "[.]tif$", full.names = TRUE)
  for (path in ensembles) {
    before <- jsonlite::fromJSON(json_of(path), simplifyVector = FALSE)
    ids <- taxa_blocks[[before$taxon]]
    if (is.null(ids)) stop("the combined map of ", before$taxon, " has no member drawn in blocks", call. = FALSE)
    r <- terra::rast(path)
    trimmed <- atlas_block_apply(r, atlas_block_keep_from_ids(r, ids))
    if (is.null(trimmed)) stop("the combined map of ", before$taxon, " keeps no block", call. = FALSE)
    trimmed <- terra::toMemory(trimmed)
    rm(r)
    terra::writeRaster(trimmed, path, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES"))
    unlink(paste0(path, ".aux.xml"))
    out <- before
    out$bounds <- atlas_ensemble_redraw(path)
    atlas_write_json(out, json_of(path))
  }
  unlink(list.files(tree, pattern = "[.]png[.]aux[.]xml$", recursive = TRUE, full.names = TRUE))
  prior <- atlas_archive_prior_rows(file.path(tree, "prior", grid), taxa_blocks, model_blocks)
  here <- atlas_archive_here_rows(file.path(tree, "index", grid, "here.rds"), taxa_blocks, model_blocks)
  say("deposit tree: ", length(rasters), " maps and ", length(ensembles), " combined maps drawn in whole ",
      ATLAS_BLOCK_KM, " km blocks")
  invisible(list(maps = length(rasters), ensembles = length(ensembles), prior_dropped = prior,
                 here_dropped = here))
}
