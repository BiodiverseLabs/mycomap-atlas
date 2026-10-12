# Map strength, ranking inside the area of applicability, and the ensemble.

# A 10 x 10 raster on the grid's projection with the given values.
tiny_raster <- function(values) {
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 5e4, ymin = 0, ymax = 5e4,
                   crs = ATLAS_CRS)
  terra::values(r) <- values
  r
}

test_that("map strength is 0 for a failed map and grows with how far a passed map beats its nulls", {
  expect_equal(atlas_map_strength(list(), "failed"), 0)
  expect_equal(atlas_map_strength(list(), "untested"), 0.5)
  expect_equal(atlas_map_strength(NULL, NULL), 0.5)
  just <- list(observed_auc = 0.5 + stats::qnorm(0.95) * 0.05, auc_mean = 0.5, auc_sd = 0.05, design = "shift")
  strong <- list(observed_auc = 0.80, auc_mean = 0.5, auc_sd = 0.05, design = "shift")
  middle <- list(observed_auc = 0.5 + 3.3 * 0.05, auc_mean = 0.5, auc_sd = 0.05, design = "shift")
  expect_equal(atlas_map_strength(just, "passed"), ATLAS_MAP_STRENGTH_FLOOR)
  expect_equal(atlas_map_strength(strong, "passed"), 1)
  expect_gt(atlas_map_strength(middle, "passed"), atlas_map_strength(just, "passed"))
  expect_lt(atlas_map_strength(middle, "passed"), 1)
  # A passed map without null spread still shows, at the floor.
  expect_equal(atlas_map_strength(list(observed_auc = 0.7, design = "shift"), "passed"), ATLAS_MAP_STRENGTH_FLOOR)
  # One that passed only scattered nulls (a fit from before the switch) is
  # weak, and drawn faint however far it beat them.
  expect_equal(atlas_map_strength(list(observed_auc = 0.80, auc_mean = 0.5, auc_sd = 0.05), "passed"), 0)
})

test_that("ground outside the area of applicability is left out of the ranking and flagged", {
  skip_if_not_installed("terra")
  suitability <- tiny_raster(seq_len(100) / 100)
  index <- tiny_raster(c(rep(0.1, 50), rep(0.9, 50)))
  layers <- atlas_map_layers(suitability, index, threshold = 0.5)
  rank <- terra::values(layers[["rank"]], mat = FALSE)
  outside <- terra::values(layers[["outside"]], mat = FALSE)
  expect_true(all(is.na(rank[51:100])))
  expect_equal(outside, rep(c(0, 1), each = 50))
  # The best cell inside the area takes the top rank, not the best cell overall.
  expect_equal(rank[[50]], 1)
  expect_equal(rank[[1]], 0)
  # Without a dissimilarity layer every cell with a value is ranked.
  plain <- atlas_map_layers(suitability)
  expect_equal(terra::values(plain[["rank"]], mat = FALSE)[[100]], 1)
})

test_that("hatched pixels are striped grey, and ranked pixels keep the ramp", {
  # A 3 x 3 image, all outside but the first pixel.
  rank <- c(0.5, rep(NA, 8))
  outside <- c(0, rep(1, 8))
  colours <- atlas_map_colours(rank, outside, ncol = 3)
  expect_true(colours[1, "alpha"] > 0)
  expect_equal(unname(colours[2:9, "red"]), rep(ATLAS_MAP_HATCH[["red"]], 8))
  expect_setequal(unname(colours[2:9, "alpha"]), c(ATLAS_MAP_WASH_ALPHA, ATLAS_MAP_HATCH_ALPHA))
  # Stripes run along one diagonal: every third pixel of a row, offset by row.
  stripes <- matrix(colours[, "alpha"] == ATLAS_MAP_HATCH_ALPHA, nrow = 3, byrow = TRUE)
  expect_equal(which(stripes[3, ]), 2L)
})

test_that("members that agree make an ensemble with no disagreement", {
  skip_if_not_installed("terra")
  a <- tiny_raster(seq_len(100))
  b <- tiny_raster(seq_len(100) * 3)
  layers <- atlas_ensemble_layers(list(a, b), list(NULL, NULL), c(NA, NA), c(0.2, 0.1))
  expect_equal(terra::values(layers[["disagreement"]], mat = FALSE), rep(0, 100))
  expect_equal(terra::values(layers[["rank"]], mat = FALSE), atlas_rank_scale(seq_len(100)))
  expect_equal(terra::values(layers[["known"]], mat = FALSE), rep(1, 100))
})

test_that("members at opposite ends disagree by half, and the heavier member leads", {
  skip_if_not_installed("terra")
  up <- tiny_raster(seq_len(100))
  down <- tiny_raster(rev(seq_len(100)))
  even <- atlas_ensemble_layers(list(up, down), list(NULL, NULL), c(NA, NA), c(0.1, 0.1))
  spread <- terra::values(even[["disagreement"]], mat = FALSE)
  expect_equal(spread[[1]], 0.5)
  expect_equal(spread[[100]], 0.5)
  heavy_up <- atlas_ensemble_layers(list(up, down), list(NULL, NULL), c(NA, NA), c(0.3, 0.1))
  rank <- terra::values(heavy_up[["rank"]], mat = FALSE)
  expect_gt(rank[[100]], rank[[1]])
})

test_that("a cell takes its rank only from members whose area holds it", {
  skip_if_not_installed("terra")
  a <- tiny_raster(seq_len(100))
  b <- tiny_raster(rev(seq_len(100)))
  # b knows nothing about the first half of the ground.
  b_index <- tiny_raster(c(rep(9, 50), rep(0, 50)))
  layers <- atlas_ensemble_layers(list(a, b), list(NULL, b_index), c(NA, 1), c(0.1, 0.1))
  known <- terra::values(layers[["known"]], mat = FALSE)
  spread <- terra::values(layers[["disagreement"]], mat = FALSE)
  expect_equal(known[1:50], rep(0.5, 50))
  expect_equal(known[51:100], rep(1, 50))
  # One member alone cannot disagree with anything.
  expect_true(all(is.na(spread[1:50])))
  expect_equal(terra::values(layers[["rank"]], mat = FALSE)[1:50],
               atlas_rank_scale(seq_len(100))[1:50])
})

# Write a fake fitted model: raster, map-ready metrics.
fake_model <- function(name, algorithm, values, skill = "passed", auc = 0.75) {
  raster <- atlas_model_path(name, "draft", ".tif", algorithm)
  dir.create(dirname(raster), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(tiny_raster(values), raster, overwrite = TRUE)
  atlas_write_json(list(taxon = name, algorithm = algorithm, skill = skill, auc_mean = auc,
                        raster = basename(raster), map = sub("[.]tif$", ".png", basename(raster)),
                        null = list(observed_auc = auc, auc_mean = 0.5, auc_sd = 0.05,
                                    design = ATLAS_NULL_DESIGN)),
                   atlas_model_path(name, "draft", ".json", algorithm))
}

test_that("an ensemble is built from passing members, kept while they stand, and removed when they do not", {
  skip_if_not_installed("terra")
  with_data_dir({
    fake_model("Eastern fungus", "maxnet", seq_len(100), auc = 0.70)
    fake_model("Eastern fungus", "rf", seq_len(100) * 2, auc = 0.80)
    fake_model("Eastern fungus", "xgboost", rev(seq_len(100)), skill = "failed")
    built <- atlas_build_ensemble("Eastern fungus")
    expect_setequal(vapply(built$members, function(m) m$algorithm, character(1)), c("maxnet", "rf"))
    expect_equal(vapply(built$members, function(m) m$weight, numeric(1)), c(0.2, 0.3))
    for (ext in c(".json", ".tif", ".png", ".disagreement.png")) {
      expect_true(file.exists(atlas_ensemble_path("Eastern fungus", "draft", ext)))
    }
    expect_equal(built$disagreement_mean, 0)
    # Nothing changed: the stored ensemble stands.
    stamp <- file.mtime(atlas_ensemble_path("Eastern fungus", "draft", ".tif"))
    Sys.sleep(1.1)
    again <- atlas_build_ensemble("Eastern fungus")
    # Compared exactly: expect_equal's relative tolerance would let a rebuild
    # a second later through.
    expect_identical(as.numeric(file.mtime(atlas_ensemble_path("Eastern fungus", "draft", ".tif"))),
                     as.numeric(stamp))
    # A member's map changes: built again.
    fake_model("Eastern fungus", "rf", rev(seq_len(100)), auc = 0.80)
    rebuilt <- atlas_build_ensemble("Eastern fungus")
    expect_gt(rebuilt$disagreement_mean, 0)
    # A member fails: one passing map is not an ensemble.
    fake_model("Eastern fungus", "rf", rev(seq_len(100)), skill = "failed")
    expect_null(atlas_build_ensemble("Eastern fungus"))
    expect_false(file.exists(atlas_ensemble_path("Eastern fungus", "draft", ".tif")))
  })
})

test_that("releases carry the ensembles beside the models", {
  skip_if_not_installed("terra")
  with_data_dir({
    fake_model("Eastern fungus", "maxnet", seq_len(100), auc = 0.70)
    fake_model("Eastern fungus", "rf", seq_len(100) * 2, auc = 0.80)
    atlas_build_ensembles(quiet = TRUE)
    files <- atlas_release_files("draft")
    expect_true("models/draft/ensemble/eastern-fungus.tif" %in% files)
    expect_true("models/draft/ensemble/eastern-fungus.disagreement.png" %in% files)
  })
})

test_that("a weak member, which passed only scattered nulls, does not join an ensemble", {
  skip_if_not_installed("terra")
  with_data_dir({
    fake_model("Two fungi", "maxnet", seq_len(100), auc = 0.70)
    fake_model("Two fungi", "rf", rev(seq_len(100)), auc = 0.72)
    path <- atlas_model_path("Two fungi", "draft", ".json", "rf")
    metrics <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    metrics$null$design <- NULL
    atlas_write_json(metrics, path)
    members <- atlas_ensemble_members("Two fungi", "draft")
    expect_equal(vapply(members, `[[`, "", "algorithm"), "maxnet")
    atlas_build_ensembles("draft", quiet = TRUE)
    expect_false(file.exists(atlas_ensemble_path("Two fungi", "draft", ".json")))
  })
})
