# The models bundle on Zenodo carries each model's 0/1 area-of-applicability
# mask, never its dissimilarity index. The index stays with the release: the
# site still masks and hatches with it, and nothing is refitted.

# Cells of the small test grid where the test index is set to 0.
AOA_ZERO_CELLS <- c(5L, 17L, 33L, 48L, 72L)

aoa_grid <- function(values) {
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 50000, ymin = 0, ymax = 50000, crs = ATLAS_CRS)
  terra::values(r) <- values
  r
}

# computed_data()'s two models, with real rasters: a suitability map, and an
# index that is 0 at a few cells, above 0 elsewhere and NA off the map.
# Maxent keeps a threshold and has a full view; the forest keeps no threshold
# unless combined = TRUE, when both are strong and keep one, and the taxon gets
# a combined map (R/ensemble.R) as a release's finishing step builds it.
computed_data_with_indexes <- function(threshold = 0.5, combined = FALSE) {
  computed_data()
  set.seed(7)
  index <- stats::runif(100, 0.0005, 2)
  index[AOA_ZERO_CELLS] <- 0
  index[c(91L, 92L)] <- NA
  suitability <- stats::runif(100)
  suitability[c(91L, 92L)] <- NA
  for (algorithm in c("maxnet", "rf")) {
    terra::writeRaster(aoa_grid(suitability), atlas_model_path("Amanita muscaria", "draft", ".tif", algorithm),
                       overwrite = TRUE)
    terra::writeRaster(aoa_grid(index), atlas_model_path("Amanita muscaria", "draft", ".di.tif", algorithm),
                       overwrite = TRUE)
    metrics <- list(taxon = "Amanita muscaria", algorithm = algorithm, auc_mean = 0.7)
    if (identical(algorithm, "maxnet") || isTRUE(combined)) metrics$applicability <- list(threshold = threshold)
    if (isTRUE(combined)) metrics$grade <- "strong"
    atlas_write_json(metrics, atlas_model_path("Amanita muscaria", "draft", ".json", algorithm))
  }
  if (isTRUE(combined)) {
    expect_false(is.null(atlas_build_ensemble("Amanita muscaria", "draft", force = TRUE)))
  }
  full <- index
  full[c(91L, 92L)] <- 3
  terra::writeRaster(aoa_grid(full), atlas_model_path("Amanita muscaria", "draft", ".full.di.tif", "maxnet"),
                     overwrite = TRUE)
  terra::writeRaster(aoa_grid(stats::runif(100)), atlas_model_path("Amanita muscaria", "draft", ".full.tif", "maxnet"),
                     overwrite = TRUE)
  list(index = index, full = full)
}

unpack_bundle <- function(bundle) {
  dir <- tempfile("unpacked-")
  dir.create(dir)
  for (name in names(bundle$sources)) {
    if (grepl("[.]tar", name)) utils::untar(bundle$sources[[name]], exdir = dir)
  }
  dir
}

test_that("a release's indexes stay out of the bundle, and every model with a threshold gets its mask", {
  with_data_dir({
    computed_data_with_indexes()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    released <- vapply(atlas_current_release(store, "draft")$files, function(f) f$path, character(1))
    expect_true(any(grepl("[.]di[.]tif$", released)))

    bundle <- atlas_archive_models_bundle(store, "draft", blocks = FALSE)
    maxnet <- utils::untar(bundle$sources[["maps-maxnet.tar"]], list = TRUE)
    rf <- utils::untar(bundle$sources[["maps-rf.tar"]], list = TRUE)
    expect_false(any(grepl("[.]di[.]tif$", c(maxnet, rf))))
    expect_true("models/draft/amanita-muscaria.aoa.tif" %in% maxnet)
    expect_true("models/draft/amanita-muscaria.full.aoa.tif" %in% maxnet)
    # The forest keeps no threshold, so it has no mask; its index is still left out.
    expect_false(any(grepl("[.]aoa[.]tif$", rf)))
    expect_true("models/draft/rf/amanita-muscaria.tif" %in% rf)

    release <- jsonlite::fromJSON(bundle$sources[["release.json"]], simplifyVector = FALSE)
    expect_equal(release$left_out$files, 3L)
    expect_equal(release$left_out$masks, 2L)
    expect_equal(release$left_out$without_mask, 1L)

    readme <- paste(atlas_archive_readme(bundle, atlas_archive_file_table(bundle$sources)), collapse = "\n")
    expect_match(readme, ".aoa.tif", fixed = TRUE)
    expect_false(grepl("(`.di.tif`)", readme, fixed = TRUE))
  })
})

test_that("a mask is the index cut at the model's threshold, cell for cell, and NA off the map", {
  with_data_dir({
    made <- computed_data_with_indexes(threshold = 0.5)
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    dir <- unpack_bundle(atlas_archive_models_bundle(store, "draft", blocks = FALSE))
    for (case in list(list(path = "models/draft/amanita-muscaria.aoa.tif", index = made$index),
                      list(path = "models/draft/amanita-muscaria.full.aoa.tif", index = made$full))) {
      mask <- terra::values(terra::rast(file.path(dir, case$path)), mat = FALSE)
      expected <- ifelse(is.na(case$index), NA, as.integer(case$index <= 0.5))
      expect_identical(as.integer(mask), as.integer(expected), info = case$path)
    }
  })
})

# Every layer of every raster in an unpacked bundle: no value is held by
# exactly the index's zero cells, and the cells at a layer's least value are
# not them either. Layer by layer, since a combined map holds three.
expect_no_index_values <- function(dir) {
  rasters <- list.files(dir, pattern = "[.]tif$", recursive = TRUE, full.names = TRUE)
  expect_gt(length(rasters), 0L)
  for (file in rasters) {
    r <- terra::rast(file)
    for (layer in seq_len(terra::nlyr(r))) {
      values <- terra::values(r[[layer]], mat = FALSE)
      what <- paste(basename(file), names(r)[[layer]])
      for (v in unique(values[is.finite(values)])) {
        expect_false(setequal(which(values == v), AOA_ZERO_CELLS), info = paste(what, v))
      }
      if (any(is.finite(values))) {
        least <- which(is.finite(values) & values <= min(values, na.rm = TRUE) + 1e-6)
        expect_false(setequal(least, AOA_ZERO_CELLS), info = what)
      }
    }
  }
  invisible(rasters)
}

test_that("bundle rasters carry no per-cell index values", {
  with_data_dir({
    computed_data_with_indexes()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    expect_no_index_values(unpack_bundle(atlas_archive_models_bundle(store, "draft", blocks = FALSE)))
  })
})

test_that("a combined map's layers in the bundle carry no per-cell index values either", {
  with_data_dir({
    computed_data_with_indexes(combined = TRUE)
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    bundle <- atlas_archive_models_bundle(store, "draft", blocks = FALSE)
    expect_true("maps-ensemble.tar" %in% names(bundle$sources))
    rasters <- expect_no_index_values(unpack_bundle(bundle))
    combined <- rasters[grepl("/ensemble/", rasters)]
    expect_length(combined, 1L)
    expect_equal(terra::nlyr(terra::rast(combined)), 3L)
  })
})

test_that("a bundle that would carry an index is refused before anything is uploaded", {
  dir <- tempfile("refuse-")
  dir.create(file.path(dir, "models", "draft"), recursive = TRUE)
  writeLines("index", file.path(dir, "models", "draft", "a.di.tif"))
  tar <- file.path(dir, "maps-maxnet.tar")
  atlas_archive_tar(normalizePath(tar, mustWork = FALSE), dir, "models/draft/a.di.tif", compression = "none")
  expect_error(atlas_archive_refuse_left_out(tar, character()), "leaves out would have been archived")
})

test_that("a release with indexes always packs to the same bytes, masks included", {
  with_data_dir({
    computed_data_with_indexes()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    first <- atlas_archive_models_bundle(store, "draft", blocks = FALSE)
    Sys.sleep(1.1)
    second <- atlas_archive_models_bundle(store, "draft", blocks = FALSE)
    hashes <- function(b) vapply(b$sources, atlas_sha256, character(1))
    expect_equal(hashes(first), hashes(second))
  })
})

test_that("the 20 km tables are unchanged by moving values within a 20 km cell", {
  # prior-aoa.tsv.gz and explore-index-20km are built from atlas_model_cell_ranks:
  # one row per 20 km cell, the mean index and mean rank of the 5 km cells in
  # it. Shuffling the index and the map together inside each 20 km cell leaves
  # every row as it was.
  r <- terra::rast(nrows = 8, ncols = 8, xmin = ATLAS_GRID_EXTENT[["xmin"]], xmax = ATLAS_GRID_EXTENT[["xmin"]] + 40000,
                   ymin = ATLAS_GRID_EXTENT[["ymax"]] - 40000, ymax = ATLAS_GRID_EXTENT[["ymax"]], crs = ATLAS_CRS)
  set.seed(11)
  index <- stats::runif(64, 0.0005, 2)
  index[c(1L, 2L, 10L, 30L, 45L)] <- 0
  suitability <- stats::runif(64)
  di <- r; terra::values(di) <- index
  map <- r; terra::values(map) <- suitability
  before <- atlas_model_cell_ranks(map, di, threshold = 0.5)
  expect_equal(nrow(before), 4L)
  xy <- terra::xyFromCell(r, seq_len(64))
  cell <- atlas_here_cell(xy[, 1], xy[, 2])
  shuffled_index <- index
  shuffled_map <- suitability
  for (k in unique(cell)) {
    at <- which(cell == k)
    order <- sample(length(at))
    shuffled_index[at] <- index[at][order]
    shuffled_map[at] <- suitability[at][order]
  }
  expect_false(identical(shuffled_index, index))
  di2 <- r; terra::values(di2) <- shuffled_index
  map2 <- r; terra::values(map2) <- shuffled_map
  after <- atlas_model_cell_ranks(map2, di2, threshold = 0.5)
  expect_equal(after$cell, before$cell)
  expect_equal(after$dissimilarity, before$dissimilarity)
  expect_equal(after$rank, before$rank)
})
