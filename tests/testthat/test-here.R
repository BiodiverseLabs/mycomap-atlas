# What could grow here: a place's index cell, the maps that rate it, ranked,
# with what has been collected nearby. Built from maps, never from records.

# A small model raster on the Atlas grid around Albers' origin (40N, 96W),
# its values rising eastward, or westward with rising = "west".
here_raster <- function(rising = "east") {
  r <- terra::rast(ncols = 40, nrows = 40, xmin = -100000, xmax = 100000,
                   ymin = -100000, ymax = 100000, crs = ATLAS_CRS)
  x <- terra::xFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- if (rising == "east") x else -x
  r
}

write_model <- function(taxon, algorithm, raster, skill = "passed") {
  dir.create(atlas_model_dir("draft", algorithm), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(raster, atlas_model_path(taxon, "draft", ".tif", algorithm), overwrite = TRUE)
  atlas_write_json(list(taxon = taxon, algorithm = algorithm, presences = 30, predictors = list("bio1"),
                        auc_mean = 0.7, boyce_mean = 0.5, built_at = "2026-09-29T00:00:00Z",
                        map = "x.png", skill = skill),
                   atlas_model_path(taxon, "draft", ".json", algorithm))
}

# East of the origin, about 43 km; and west, about 43 km.
EAST <- c(lat = 40, lng = -95.5)
WEST <- c(lat = 40, lng = -96.5)

test_that("the projection agrees with terra to within a metre across the continent", {
  testthat::skip_if_not_installed("terra")
  lat <- c(40, 25.8, 61.2, 49.3, 19.4, 44.9, 35.2)
  lng <- c(-96, -80.2, -149.9, -123.1, -99.1, -68.8, -111.7)
  mine <- atlas_albers(lat, lng)
  theirs <- atlas_project_points(lat, lng)
  expect_lt(max(abs(mine[, "x"] - theirs[, 1])), 1)
  expect_lt(max(abs(mine[, "y"] - theirs[, 2])), 1)
})

test_that("points in the same square share a cell, and a place off the grid has none", {
  # Squares align with the grid's origin, so their edges fall at -5, 15, 35 km...
  expect_equal(atlas_here_cell(-4000, 1000), atlas_here_cell(14000, 2000))
  expect_false(identical(atlas_here_cell(14000, 1000), atlas_here_cell(16000, 1000)))
  expect_true(is.na(atlas_here_cell(9e6, 0)))
})

test_that("a model contributes only the cells in the top half of its own map", {
  testthat::skip_if_not_installed("terra")
  cells <- atlas_here_model_cells(here_raster("east"))
  expect_true(all(cells$rank >= 50))
  xy <- atlas_albers(EAST[["lat"]], EAST[["lng"]])
  east_cell <- atlas_here_cell(xy[1, "x"], xy[1, "y"])
  xy <- atlas_albers(WEST[["lat"]], WEST[["lng"]])
  west_cell <- atlas_here_cell(xy[1, "x"], xy[1, "y"])
  expect_true(east_cell %in% cells$cell)
  expect_false(west_cell %in% cells$cell)
})

build_here_fixture <- function() {
  # Two taxa: one whose three models all like the east, one where only the
  # forest does; and one that likes the west.
  write_model("Eastern agreed", "maxnet", here_raster("east"))
  write_model("Eastern agreed", "rf", here_raster("east"))
  write_model("Eastern agreed", "xgboost", here_raster("east"))
  write_model("Eastern forest only", "maxnet", here_raster("west"))
  write_model("Eastern forest only", "rf", here_raster("east"))
  write_model("Western", "rf", here_raster("west"))
  atlas_build_here_index("draft", quiet = TRUE)
}

test_that("a place lists the taxa its maps rate highly, agreement first", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    index <- build_here_fixture()
    answer <- atlas_here(index, EAST[["lat"]], EAST[["lng"]])
    names <- vapply(answer$taxa, `[[`, character(1), "scientific_name")
    expect_equal(names, c("Eastern agreed", "Eastern forest only"))
    first <- answer$taxa[[1]]
    expect_length(first$fitted, 3)
    expect_true(first$score > answer$taxa[[2]]$score)
    # The forest-only taxon's Maxent map puts this ground in its bottom half.
    expect_null(answer$taxa[[2]]$models$maxnet)
    # A model that does not rate the place counts as zero: the score is the
    # forest's rank shared over both fitted models, not the forest's rank alone.
    expect_equal(answer$taxa[[2]]$score, round(answer$taxa[[2]]$models$rf / 2, 3), tolerance = 0.002)
    expect_equal(answer$taxa[[2]]$fitted, list("maxnet", "rf"))
    expect_false("Western" %in% names)
    west <- vapply(atlas_here(index, WEST[["lat"]], WEST[["lng"]])$taxa, `[[`, character(1), "scientific_name")
    expect_true("Western" %in% west)
  })
})

test_that("a map that did not beat its null models is left out", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    write_model("Eastern agreed", "maxnet", here_raster("east"))
    write_model("Eastern by chance", "maxnet", here_raster("east"), skill = "failed")
    write_model("Eastern untested", "rf", here_raster("east"), skill = NULL)
    index <- atlas_build_here_index("draft", quiet = TRUE)
    names <- vapply(atlas_here(index, EAST[["lat"]], EAST[["lng"]])$taxa, `[[`, character(1),
                    "scientific_name")
    expect_equal(names, "Eastern agreed")
  })
})

test_that("with no map that beat its nulls there is nothing to index, and it says so", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    write_model("Eastern by chance", "maxnet", here_raster("east"), skill = "failed")
    expect_error(atlas_build_here_index("draft", quiet = TRUE), "null models")
  })
})

test_that("a minimum score and a limit trim the list", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    index <- build_here_fixture()
    all <- atlas_here(index, EAST[["lat"]], EAST[["lng"]])
    strict <- atlas_here(index, EAST[["lat"]], EAST[["lng"]], min_score = all$taxa[[1]]$score)
    expect_length(strict$taxa, 1)
    expect_length(atlas_here(index, EAST[["lat"]], EAST[["lng"]], limit = 1)$taxa, 1)
    expect_equal(atlas_here(index, EAST[["lat"]], EAST[["lng"]], limit = 1)$total, 2)
  })
})

test_that("what was collected nearby is counted, and taxa with no map are listed apart", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    index <- build_here_fixture()
    cells <- data.frame(
      taxon = c("Eastern agreed", "Eastern agreed", "Unmapped thing", "Far away"),
      lat = c(40.05, 39.95, 40.05, 45.05), lng = c(-95.45, -95.55, -95.45, -80.05),
      records = c(3L, 2L, 4L, 9L), stringsAsFactors = FALSE
    )
    answer <- atlas_here(index, EAST[["lat"]], EAST[["lng"]], cells = cells, nearby_km = 25)
    agreed <- Filter(function(t) t$scientific_name == "Eastern agreed", answer$taxa)[[1]]
    expect_equal(agreed$nearby_records, 5L)
    unmapped <- vapply(answer$recorded_unmapped, `[[`, character(1), "scientific_name")
    expect_equal(unmapped, "Unmapped thing")
  })
})

test_that("a place off the grid answers plainly instead of failing", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    index <- build_here_fixture()
    answer <- atlas_here(index, 51.5, -0.1)
    expect_false(answer$in_grid)
    expect_length(answer$taxa, 0)
    expect_error(atlas_here(index, 95, 0), "point on Earth")
  })
})

test_that("the index holds ranks by cell and nothing about records", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    index <- build_here_fixture()
    expect_setequal(names(index), c("grid", "cell_km", "min_rank", "built_at", "models", "start", "model", "rank"))
    expect_setequal(names(index$models), c("taxon", "algorithm"))
    expect_true(all(as.integer(index$rank) >= 50 & as.integer(index$rank) <= 100))
    expect_true(file.exists(atlas_here_index_path("draft")))
  })
})

test_that("distances are great-circle kilometres", {
  expect_equal(atlas_km_between(0, 0, 0, 1), 111.19, tolerance = 0.01)
  expect_equal(atlas_km_between(40, -96, 40, -96), 0)
})

test_that("the answer serialises without NA strings", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    index <- build_here_fixture()
    json <- as.character(jsonlite::toJSON(atlas_here(index, EAST[["lat"]], EAST[["lng"]]), auto_unbox = TRUE))
    expect_false(grepl("\"NA\"", json, fixed = TRUE))
  })
})
