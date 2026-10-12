# Full-extent maps: a strong model predicted over the whole grid, for the
# map's full view. One colour scale with the default map, which stays byte
# for byte as it was, and nothing downstream reads the full-extent files.

# A map whose values rise eastward, its dissimilarity rising away from the
# middle, and the accessible area: the middle strip, as atlas_predict_raster
# leaves it (a window of the same grid).
full_fixture <- function(threshold = 0.7) {
  full <- terra::rast(ncols = 40, nrows = 40, xmin = -1e5, xmax = 1e5, ymin = -1e5, ymax = 1e5, crs = ATLAS_CRS)
  x <- terra::xFromCell(full, seq_len(terra::ncell(full)))
  terra::values(full) <- x
  dissimilarity <- full
  terra::values(dissimilarity) <- abs(x) / 1e5
  window <- terra::ext(-5e4, 5e4, -1e5, 1e5)
  list(full = full, full_dissimilarity = dissimilarity, suitability = terra::crop(full, window),
       dissimilarity = terra::crop(dissimilarity, window), threshold = threshold)
}

test_that("the full view keeps the default map's ranks inside the reach, and puts the rest on that scale", {
  skip_if_not_installed("terra")
  f <- full_fixture()
  layers <- atlas_full_map_layers(f$full, f$full_dissimilarity, f$suitability, f$dissimilarity, f$threshold)
  default <- terra::extend(atlas_map_layers(f$suitability, f$dissimilarity, f$threshold), f$full)
  rank <- terra::values(layers[["rank"]], mat = FALSE)
  outside <- terra::values(layers[["outside"]], mat = FALSE)
  x <- terra::xFromCell(f$full, seq_len(terra::ncell(f$full)))
  inside <- abs(x) < 5e4
  # Inside the reach: exactly the default map.
  expect_identical(rank[inside], terra::values(default[["rank"]], mat = FALSE)[inside])
  expect_identical(outside[inside], terra::values(default[["outside"]], mat = FALSE)[inside])
  # Beyond it: east is better than anything inside (rank 1), west worse (0),
  # and ground past the area-of-applicability threshold is hatched, unranked.
  near_east <- x > 5e4 & abs(x) / 1e5 <= f$threshold
  near_west <- x < -5e4 & abs(x) / 1e5 <= f$threshold
  far <- abs(x) / 1e5 > f$threshold
  expect_true(all(rank[near_east] == 1))
  expect_true(all(rank[near_west] == 0))
  expect_true(all(outside[far] == 1))
  expect_true(all(is.na(rank[far])))
})

test_that("the full picture is drawn from those layers, on the default map's scale", {
  skip_if_not_installed("terra")
  f <- full_fixture()
  drawn_with <- NULL
  testthat::local_mocked_bindings(atlas_write_map_png = function(suitability, path, ..., layers = NULL) {
    drawn_with <<- layers
    list(path = path, bounds = list())
  })
  with_data_dir({
    atlas_write_full_map("Eastern", "draft", "maxnet", f$full, f$full_dissimilarity, f$suitability,
                         f$dissimilarity, f$threshold)
  })
  expected <- atlas_full_map_layers(f$full, f$full_dissimilarity, f$suitability, f$dissimilarity, f$threshold)
  expect_false(is.null(drawn_with))
  expect_identical(terra::values(drawn_with), terra::values(expected))
})

fit_synthetic <- function(full) {
  with_data_dir({
    world <- synthetic_landscape()
    atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                    fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                    buffer_km = 300, quiet = TRUE, nulls = 0, tune = FALSE,
                    guilds = stats::setNames(character(), character()), full = full)
    paths <- atlas_model_path("Eastern fungus", "draft", c(".tif", ".di.tif", ".png", ATLAS_FULL_EXTS))
    list(sha = vapply(paths, function(p) if (file.exists(p)) atlas_sha256(p) else NA_character_, "", USE.NAMES = FALSE),
         # Read now: the data directory goes when this returns.
         values = if (file.exists(paths[[4]])) {
           full <- terra::rast(paths[[4]])
           list(full = terra::values(full, mat = FALSE),
                default = terra::values(terra::extend(terra::rast(paths[[1]]), full), mat = FALSE))
         },
         metrics = atlas_read_metrics("Eastern fungus", "draft"))
  })
}

test_that("a full view only adds ground: the default map, its layer and its picture are byte for byte as without", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  without <- fit_synthetic(FALSE)
  with <- fit_synthetic(TRUE)
  expect_identical(with$sha[1:3], without$sha[1:3])
  expect_true(all(is.na(without$sha[4:6])))
  expect_true(all(!is.na(with$sha[4:6])))
  expect_null(without$metrics$full_map)
  expect_equal(with$metrics$full_map$map, "eastern-fungus.full.png")
  # Inside the reach the full raster is the default map, cell for cell.
  same <- !is.na(with$values$default)
  expect_gt(sum(same), 0L)
  expect_identical(with$values$full[same], with$values$default[same])
  # The whole landscape, not only the 300 km around the finds.
  expect_equal(with$metrics$full_map$cells, 200L * 200L)
  expect_gt(with$metrics$full_map$beyond_reach, 0L)
})

test_that("only a strong map gets a full view unless a refit job asks", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  # With no null test the map is untested: no full view.
  untested <- fit_synthetic(NULL)
  expect_true(all(is.na(untested$sha[4:6])))
  # Graded strong, it gets one.
  testthat::local_mocked_bindings(atlas_map_grade = function(...) "strong")
  strong <- fit_synthetic(NULL)
  expect_true(all(!is.na(strong$sha[4:6])))
  expect_equal(strong$metrics$grade, "strong")
})

test_that("nothing downstream reads a full-extent file: index, prior, combined maps, counts and redraws", {
  skip_if_not_installed("terra")
  with_data_dir({
    write_model("Eastern agreed", "maxnet", here_raster("east"))
    write_model("Eastern agreed", "rf", here_raster("east"))
    write_model("Western", "rf", here_raster("west"))
    built <- function() {
      atlas_build_finish_indexes("draft", quiet = TRUE)
      atlas_build_ensembles("draft", force = TRUE, quiet = TRUE)
      index <- atlas_read_here_index("draft")
      prior <- file.path(atlas_prior_dir("draft"), c("ranks.tsv.gz", "taxa.tsv", "grid.json"))
      list(index = index[c("models", "start", "model", "rank")],
           prior = vapply(prior, atlas_sha256, ""),
           ensemble = atlas_sha256(atlas_path("models", "draft", "ensemble", "eastern-agreed.tif")))
    }
    before <- built()
    # Full-extent files with values no default map has, beside every map.
    wild <- terra::rast(ncols = 80, nrows = 80, xmin = -2e5, xmax = 2e5, ymin = -2e5, ymax = 2e5, crs = ATLAS_CRS)
    terra::values(wild) <- 1e6
    for (a in c("maxnet", "rf")) for (taxon in c("Eastern agreed", "Western")) {
      if (!file.exists(atlas_model_path(taxon, "draft", ".tif", a))) next
      paths <- atlas_model_path(taxon, "draft", ATLAS_FULL_EXTS, a)
      terra::writeRaster(wild, paths[[1]], overwrite = TRUE)
      terra::writeRaster(wild * 0, paths[[2]], overwrite = TRUE)
      writeLines("not a map", paths[[3]])
    }
    expect_identical(built(), before)
    # The count by state and the redraw do not take them for maps.
    expect_false(any(grepl("full|[.]di[.]", atlas_model_map_rasters("draft"))))
    expect_length(atlas_model_map_rasters("draft"), 3L)
  })
})

test_that("a job's release carries a strong map's full view, a pull for serving brings its picture, and a refit without one drops it", {
  skip_if_not_installed("terra")
  with_full <- local({
    f <- function(name, fingerprint, grid = "draft", algorithm = "maxnet", ...) {
      out <- fake_fit(name, fingerprint, grid = grid, algorithm = algorithm, ...)
      paths <- atlas_model_path(name, grid, ATLAS_FULL_EXTS, algorithm)
      for (p in paths) writeLines(paste("full", name), p)
      metrics <- out$metrics
      metrics$full_map <- list(map = basename(paths[[3]]), seconds = 2, bytes = 1048576)
      atlas_write_json(metrics, atlas_model_path(name, grid, ".json", algorithm))
      list(metrics = metrics)
    }
    environment(f) <- globalenv()
    f
  })
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  release <- full_cycle(store, boss, fit = with_full)
  paths <- release_paths(release)
  expect_true(all(paste0("models/draft/taxon-a", ATLAS_FULL_EXTS) %in% paths))
  # A web server pulls without rasters: the full picture comes, the rasters do not.
  on_machine(machine(), {
    atlas_pull_release(store, rasters = FALSE, quiet = TRUE)
    expect_true(file.exists(atlas_model_path("Taxon A", "draft", ".full.png")))
    expect_false(file.exists(atlas_model_path("Taxon A", "draft", ".full.tif")))
  })
  # The timing says what the full views cost.
  timing <- atlas_job_timing(store, release$job)
  expect_equal(timing$extent$models, timing$timed)
  expect_equal(timing$extent$mean_mb, 1)
  # Refitted without one (weak now), the old full view goes.
  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-1], "Taxon A" = 26))))
  again <- full_cycle(store, boss, fit = fake_fit)
  expect_false(any(paste0("models/draft/taxon-a", ATLAS_FULL_EXTS) %in% release_paths(again)))
  expect_true("models/draft/taxon-b.full.png" %in% release_paths(again))
})

test_that("removing a map removes its full view too", {
  with_data_dir({
    dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE, showWarnings = FALSE)
    paths <- atlas_model_path("Gone", "draft", c(".tif", ATLAS_FULL_EXTS))
    for (p in paths) writeLines("x", p)
    atlas_remove_map("Gone", "draft", "maxnet")
    expect_false(any(file.exists(paths)))
  })
})
