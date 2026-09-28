test_that("the two grids nest, so draft work transfers to production", {
  expect_equal(atlas_resolution("draft") %% atlas_resolution("production"), 0)
  expect_equal(ATLAS_GRID_EXTENT[["xmax"]] %% atlas_resolution("draft"), 0)
  expect_equal(ATLAS_GRID_EXTENT[["ymin"]] %% atlas_resolution("draft"), 0)
})

test_that("an unknown grid name is refused rather than guessed", {
  expect_error(atlas_resolution("hi-res"), "grid must be one of")
  expect_error(atlas_resolution(c("draft", "production")), "grid must be one of")
})

test_that("grid sizes are whole numbers of cells", {
  for (grid in names(ATLAS_GRID_RESOLUTIONS)) {
    size <- atlas_grid_size(grid)
    expect_equal(size$nrow %% 1, 0)
    expect_equal(size$ncol %% 1, 0)
  }
})

test_that("the production grid is 1 km and the draft grid is coarser", {
  expect_equal(atlas_resolution("production"), 1000)
  expect_gt(atlas_resolution("draft"), atlas_resolution("production"))
  expect_lt(atlas_grid_size("draft")$cells, atlas_grid_size("production")$cells)
})

test_that("the template raster matches the declared grid", {
  skip_if_not_installed("terra")
  template <- atlas_grid_template("draft")
  expect_equal(terra::xmin(template), ATLAS_GRID_EXTENT[["xmin"]])
  expect_equal(terra::ymax(template), ATLAS_GRID_EXTENT[["ymax"]])
  expect_equal(terra::res(template)[[1]], atlas_resolution("draft"))
  expect_equal(terra::ncell(template), atlas_grid_size("draft")$cells)
})

test_that("the grid holds North America, including the far corners", {
  skip_if_not_installed("terra")
  inside <- atlas_grid_covers(
    lat = c(18.2, 61.2, 25.8, 62.4, 19.4, 49.3, 19.6, 71.3),
    lng = c(-66.5, -149.9, -80.2, -114.4, -99.1, -123.1, -155.5, -156.8)
  )
  expect_true(all(inside))
})

test_that("somewhere else is outside the grid", {
  skip_if_not_installed("terra")
  outside <- atlas_grid_covers(
    lat = c(51.5, -33.9, 35.7),
    lng = c(-0.1, 151.2, 139.7)
  )
  expect_false(any(outside))
})

test_that("projecting a point gives metres, not degrees", {
  skip_if_not_installed("terra")
  xy <- atlas_project_points(lat = 40, lng = -96)
  expect_lt(abs(xy[1, 1]), 1)
  expect_lt(abs(xy[1, 2]), 1)
})
