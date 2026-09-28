test_that("every registered layer carries its provenance", {
  registry <- atlas_layer_registry()
  expect_gt(length(registry), 0)
  for (id in names(registry)) {
    entry <- registry[[id]]
    expect_equal(entry$id, id)
    for (field in c("title", "source", "license", "citation", "method")) {
      expect_true(
        is.character(entry[[field]]) && nzchar(entry[[field]]),
        info = paste(id, "is missing", field)
      )
    }
    expect_true(
      !is.null(entry$fetch) || !is.null(entry$derive),
      info = paste(id, "can neither be fetched nor derived")
    )
  }
})

test_that("a derived layer names what it derives from", {
  registry <- atlas_layer_registry()
  for (id in names(registry)) {
    entry <- registry[[id]]
    if (!is.null(entry$derive)) {
      expect_true(entry$depends %in% names(registry), info = id)
    }
  }
})

test_that("the production grid pulls finer source data than the draft grid", {
  expect_lt(atlas_source_resolution("production"), atlas_source_resolution("draft"))
  expect_error(atlas_source_resolution("enormous"), "grid must be one of")
})

test_that("an unknown layer is refused rather than silently skipped", {
  expect_error(atlas_build_layers("rainfall-vibes"), "unknown layer")
})

test_that("layers land in a directory per grid", {
  expect_match(atlas_layer_path("elevation", "draft"), "layers/draft/elevation.tif$")
  expect_match(atlas_layer_path("elevation", "production"), "layers/production/elevation.tif$")
})

test_that("recording a layer twice replaces it and keeps the others", {
  with_data_dir({
    atlas_record_layer(list(id = "elevation", md5 = "aaa"), "draft")
    atlas_record_layer(list(id = "bioclim", md5 = "bbb"), "draft")
    atlas_record_layer(list(id = "elevation", md5 = "ccc"), "draft")

    manifest <- atlas_layer_manifest("draft")
    ids <- vapply(manifest, function(x) as.character(x$id), character(1))
    expect_equal(sort(ids), c("bioclim", "elevation"))
    expect_equal(manifest[[which(ids == "elevation")]]$md5, "ccc")
  })
})

test_that("a grid's manifest does not leak into the other grid", {
  with_data_dir({
    atlas_record_layer(list(id = "elevation", md5 = "draft-one"), "draft")
    expect_equal(length(atlas_layer_manifest("production")), 0L)
  })
})

test_that("the overview lists every registered layer, built or not", {
  with_data_dir({
    atlas_record_layer(
      list(id = "elevation", bands = list("elevation"), cell_size_m = 5000,
           size_mb = 3.4, built_at = "2026-09-28T00:00:00Z"),
      "draft"
    )
    overview <- atlas_layer_overview("draft")
    expect_equal(length(overview), length(atlas_layer_registry()))

    built <- Filter(function(x) x$built, overview)
    expect_equal(length(built), 1L)
    expect_equal(built[[1]]$id, "elevation")
    # A list, so a one-band layer still serialises as a JSON array
    expect_equal(built[[1]]$bands, list("elevation"))
    expect_equal(built[[1]]$cellSizeM, 5000)

    pending <- Filter(function(x) !x$built, overview)
    expect_true(all(vapply(pending, function(x) is.null(x$bands), logical(1))))
    expect_true(all(vapply(pending, function(x) nzchar(x$license), logical(1))))
  })
})

test_that("an empty manifest reads as nothing built", {
  with_data_dir({
    expect_equal(length(atlas_layer_manifest("draft")), 0L)
    expect_false(any(atlas_layer_status("draft")$built))
  })
})

test_that("bioclim bands are renamed by their number, not their position", {
  skip_if_not_installed("terra")
  scrambled <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3)
  names(scrambled) <- c("wc2.1_2.5m_bio_10", "wc2.1_2.5m_bio_2", "wc2.1_2.5m_bio_1")
  terra::values(scrambled) <- cbind(rep(10, 4), rep(2, 4), rep(1, 4))

  renamed <- atlas_rename_bioclim(scrambled)
  expect_equal(names(renamed), c("bio1", "bio2", "bio10"))
  expect_equal(unname(terra::values(renamed)[1, ]), c(1, 2, 10))
})

test_that("bands that cannot be numbered are refused rather than guessed", {
  skip_if_not_installed("terra")
  odd <- terra::rast(nrows = 2, ncols = 2, nlyrs = 2)
  names(odd) <- c("temperature", "rainfall")
  expect_error(atlas_rename_bioclim(odd), "cannot read bioclim band numbers")
})

test_that("the crop window holds everything the grid can show", {
  expect_lt(ATLAS_SOURCE_WINDOW[["xmin"]], -170)
  expect_gt(ATLAS_SOURCE_WINDOW[["xmax"]], -52)
  expect_lt(ATLAS_SOURCE_WINDOW[["ymin"]], 14)
  expect_gt(ATLAS_SOURCE_WINDOW[["ymax"]], 72)
})

test_that("a worldwide source is cut to the region before projecting", {
  skip_if_not_installed("terra")
  world <- terra::rast(
    xmin = -180, xmax = 180, ymin = -90, ymax = 90,
    resolution = 1, crs = "EPSG:4326"
  )
  cropped <- atlas_crop_to_region(world)
  expect_lte(terra::xmax(cropped), ATLAS_SOURCE_WINDOW[["xmax"]])
  expect_gte(terra::ymin(cropped), ATLAS_SOURCE_WINDOW[["ymin"]])
  expect_lt(terra::ncell(cropped), terra::ncell(world))
})

test_that("a raster already on the grid is left alone by the crop", {
  skip_if_not_installed("terra")
  expect_equal(
    as.vector(terra::ext(atlas_crop_to_region(atlas_grid_template("draft")))),
    as.vector(terra::ext(atlas_grid_template("draft")))
  )
})

test_that("projecting a raster puts it exactly on the grid", {
  skip_if_not_installed("terra")
  source <- terra::rast(
    xmin = -180, xmax = 180, ymin = -90, ymax = 90,
    resolution = 1, crs = "EPSG:4326"
  )
  terra::values(source) <- seq_len(terra::ncell(source))

  onto <- atlas_project_to_grid(source, "draft")
  template <- atlas_grid_template("draft")

  expect_equal(terra::res(onto), terra::res(template))
  expect_equal(terra::xmin(onto), terra::xmin(template))
  expect_equal(terra::ymax(onto), terra::ymax(template))
  expect_equal(terra::ncell(onto), terra::ncell(template))
  expect_true(terra::same.crs(onto, template))
})
