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
      !is.null(entry$fetch) || !is.null(entry$derive) || !is.null(entry$build),
      info = paste(id, "can be neither fetched, derived nor built")
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

test_that("terrain keeps the coast, where slope would otherwise vanish", {
  skip_if_not_installed("terra")
  # Land on the left, ocean (NA) on the right, as a coastline is.
  elevation <- terra::rast(nrows = 6, ncols = 6, xmin = 0, xmax = 6000,
                           ymin = 0, ymax = 6000, crs = ATLAS_CRS)
  heights <- matrix(rep(c(300, 250, 200, 100, NA, NA), each = 6), nrow = 6, byrow = TRUE)
  terra::values(elevation) <- as.vector(t(heights))

  naive <- terra::terrain(elevation, v = "slope", unit = "degrees")
  derived <- atlas_layer_registry()$terrain$derive(elevation)

  land <- !is.na(terra::values(elevation)[, 1])
  kept <- sum(is.finite(terra::values(derived)[land, "slope"]))
  lost <- sum(is.finite(terra::values(naive)[land, 1]))
  expect_gt(kept, lost)

  # The sea has no elevation, so it keeps no slope either.
  sea <- is.na(terra::values(elevation)[, 1])
  expect_true(all(is.na(terra::values(derived)[sea, "slope"])))
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

test_that("a source in its own projection is cropped too, not warped whole", {
  skip_if_not_installed("terra")
  # A stand-in for SoilGrids: global, and not in longitude/latitude.
  world <- terra::rast(
    xmin = -20000000, xmax = 20000000, ymin = -8000000, ymax = 8000000,
    resolution = 50000, crs = "EPSG:3857"
  )
  cropped <- atlas_crop_to_region(world)
  expect_lt(terra::ncell(cropped), terra::ncell(world) / 4)
  expect_lt(terra::xmax(cropped), 0) # North America is west of the meridian
  expect_gt(terra::ymax(cropped), 0)
})

test_that("the region window lands in the right place in another projection", {
  skip_if_not_installed("terra")
  window <- as.vector(atlas_region_window("EPSG:3857"))
  expect_lt(window[["xmax"]], 0) # North America is west of the meridian
  expect_gt(window[["xmin"]], -20100000)
  expect_gt(window[["ymin"]], 0) # and north of the equator
})

test_that("a source that does not reach North America is refused", {
  skip_if_not_installed("terra")
  elsewhere <- terra::rast(
    xmin = 100, xmax = 140, ymin = -40, ymax = -10,
    resolution = 1, crs = "EPSG:4326"
  )
  expect_error(atlas_crop_to_region(elsewhere), "does not cover North America")
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

test_that("the host layer is built on the grid, with one band per host and conifer share", {
  entry <- atlas_layer_registry()$hosts
  expect_true(is.function(entry$build))
  expect_equal(ATLAS_HOST_BANDS[[1]], "host_conifer")
  expect_equal(ATLAS_HOST_BANDS[-1], paste0("host_", tolower(ATLAS_HOST_GENERA)))
  expect_false("host_corylus" %in% ATLAS_HOST_BANDS)
  expect_true("host_notholithocarpus" %in% ATLAS_HOST_BANDS)
  # Every source it draws on is named, and the empty regions are said out loud.
  expect_true(all(c(ATLAS_BIGMAP_URL, ATLAS_NFI_URL, ATLAS_CONUS_URL) %in% entry$urls))
  expect_match(entry$note, "Alaska, Hawaii, Puerto Rico and Mexico")
  expect_match(entry$citation, "Wilson BT")
  expect_match(entry$citation, "Beaudoin A")
})

test_that("a built layer is recorded with its provenance, whoever builds it", {
  skip_if_not_installed("terra")
  with_data_dir({
    fake <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2000, ymin = 0, ymax = 2000,
                        crs = ATLAS_CRS, nlyrs = length(ATLAS_HOST_BANDS))
    terra::values(fake) <- 0.5
    names(fake) <- ATLAS_HOST_BANDS
    # The host layer is filled up to the land the elevation layer knows.
    land <- fake[[1]]
    names(land) <- "elevation"
    dir.create(atlas_layer_dir("draft"), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(land, atlas_layer_path("elevation", "draft"))
    seen <- NULL
    testthat::local_mocked_bindings(atlas_build_hosts = function(raw_dir, grid) {
      seen <<- list(raw_dir = raw_dir, grid = grid)
      fake
    })
    record <- atlas_build_layer("hosts", "draft", quiet = TRUE)
    expect_equal(seen$grid, "draft")
    expect_match(seen$raw_dir, "layers/raw$")
    expect_equal(unlist(record$bands), c(ATLAS_HOST_BANDS, "host_known"))
    entry <- Filter(function(x) x$id == "hosts", atlas_layer_manifest("draft"))[[1]]
    for (field in c("title", "source", "url", "license", "citation", "method", "md5", "built_at")) {
      expect_true(is.character(entry[[field]]) && nzchar(entry[[field]]), info = field)
    }
    expect_equal(unlist(entry$urls), c(ATLAS_BIGMAP_URL, ATLAS_NFI_URL, ATLAS_CONUS_URL))
    expect_equal(unlist(entry$bands), c(ATLAS_HOST_BANDS, "host_known"))
    expect_equal(entry$md5, unname(tools::md5sum(atlas_layer_path("hosts", "draft"))))
    # Built, not fetched: there is no source resolution to speak of.
    expect_true(is.null(entry$source_arcmin) || is.na(entry$source_arcmin) || !length(entry$source_arcmin))
  })
})

# --- A layer's gap must not take ground from every model ---------------------

outside_setup <- function() {
  # Four cells in a row: described land, land the source is silent on, land
  # the source half describes, and sea.
  land <- terra::rast(nrows = 1, ncols = 4, xmin = 0, xmax = 4000, ymin = 0, ymax = 1000,
                      crs = ATLAS_CRS)
  terra::values(land) <- c(100, 200, 300, NA)
  source <- c(land, land)
  terra::values(source) <- cbind(c(0.4, NA, 0.2, 0.9), c(0.1, NA, NA, 0.9))
  names(source) <- c("host_pinus", "host_quercus")
  list(land = land, source = source)
}

test_that("land a layer's source is silent on is filled with 0 and flagged, not lost", {
  skip_if_not_installed("terra")
  s <- outside_setup()
  out <- atlas_fill_outside(s$source, s$land, known = "host_known")
  expect_equal(names(out), c("host_pinus", "host_quercus", "host_known"))
  v <- terra::values(out)
  expect_equal(unname(v[1, ]), c(0.4, 0.1, 1))
  expect_equal(unname(v[2, ]), c(0, 0, 0))
  # Half described is not described: no band keeps a value the others lack.
  expect_equal(unname(v[3, ]), c(0, 0, 0))
  # The sea stays empty, whatever the source says about it.
  expect_true(all(is.na(v[4, ])))
})

test_that("a filled layer costs a training table no rows", {
  skip_if_not_installed("terra")
  s <- outside_setup()
  table <- data.frame(presence = c(1L, 0L, 0L), cell = 1:3,
                      x = c(500, 1500, 2500), y = 500)
  unfilled <- atlas_add_predictors(table, stack = s$source)
  expect_equal(nrow(unfilled), 1L)
  filled <- atlas_add_predictors(
    table, stack = atlas_fill_outside(s$source, s$land, known = "host_known")
  )
  expect_equal(nrow(filled), 3L)
  expect_equal(filled$host_known, c(1, 0, 0))
})

test_that("the host layer is filled where the inventories are silent, with its flag", {
  registry <- atlas_layer_registry()
  expect_equal(registry$hosts$fill_outside, "host_known")
  expect_equal(ATLAS_HOST_KNOWN_BANDS, "host_known")
  filled <- Filter(function(x) !is.null(x$fill_outside), registry)
  expect_equal(names(filled), "hosts")
})

test_that("production fits on the five first layers plus host trees and forest type, and the dropped layers are gone", {
  registry <- atlas_layer_registry()
  expect_equal(ATLAS_PRODUCTION_LAYERS,
               c("elevation", "bioclim", "terrain", "soil", "landcover", "hosts", "foresttype"))
  expect_true(all(ATLAS_PRODUCTION_LAYERS %in% names(registry)))
  expect_false(any(c("bedrock", "landform", "hosts_wilson") %in% names(registry)))
  expect_equal(unlist(ATLAS_NEW_LAYER_GROUPS, use.names = FALSE),
               c("waterbalance", "soilnitrogen", "soilstructure", "soildepth"))
  expect_false(any(c("bedrock_carbonate", "twi", "northness", "heat_load") %in% ATLAS_PREDICTOR_PRIORITY))
})

test_that("a filled layer refuses to build before the land it is filled up to", {
  skip_if_not_installed("terra")
  with_data_dir({
    testthat::local_mocked_bindings(atlas_build_hosts = function(raw_dir, grid) {
      outside_setup()$source
    })
    expect_error(atlas_build_layer("hosts", "draft", quiet = TRUE), "build elevation")
  })
})

# --- Empty land cells are filled from their neighbours -------------------

near_setup <- function() {
  # A 5 x 5 grid of 1 km cells. Land is the left four columns; the right
  # column is sea. The layer is empty on the coast (column 4) and at one
  # inland cell, and has a value in the sea it should not keep.
  land <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 5000, ymin = 0, ymax = 5000,
                      crs = ATLAS_CRS)
  terra::values(land) <- rep(c(TRUE, TRUE, TRUE, TRUE, FALSE), 5)
  x <- land
  v <- rep(c(10, 20, 30, NA, 99), 5)
  v[12] <- NA   # row 3, column 2: an inland hole
  terra::values(x) <- v
  names(x) <- "soil_phh2o"
  list(land = land, x = x)
}

test_that("an empty land cell takes the mean of its neighbours, and cells with data keep theirs", {
  skip_if_not_installed("terra")
  s <- near_setup()
  out <- atlas_fill_near(s$x, s$land, max_km = 1)
  v <- matrix(terra::values(out), 5, byrow = TRUE)
  expect_equal(v[1, 1:3], c(10, 20, 30))
  # The coast: neighbours are 30 (left column) and, diagonally, 30s; the sea
  # (99) is empty by then, so it cannot leak in... unless it was there first.
  expect_true(is.finite(v[1, 4]))
  expect_equal(v[3, 2], mean(c(10, 10, 10, 20, 20, 30, 30, 30)))
  expect_equal(names(out), "soil_phh2o")
})

test_that("the sea stays empty, whatever the source said there", {
  skip_if_not_installed("terra")
  s <- near_setup()
  out <- atlas_fill_near(s$x, s$land, max_km = 3)
  v <- matrix(terra::values(out), 5, byrow = TRUE)
  expect_true(all(is.na(v[, 5])))
  expect_true(all(is.finite(v[, 1:4])))
})

test_that("a cell further than the limit from any data stays empty", {
  skip_if_not_installed("terra")
  land <- terra::rast(nrows = 2, ncols = 6, xmin = 0, xmax = 6000, ymin = 0, ymax = 2000,
                      crs = ATLAS_CRS)
  terra::values(land) <- TRUE
  x <- land
  terra::values(x) <- rep(c(5, NA, NA, NA, NA, NA), 2)
  one <- terra::values(atlas_fill_near(x, land, max_km = 1))
  expect_equal(as.numeric(one), rep(c(5, 5, NA, NA, NA, NA), 2))
  three <- terra::values(atlas_fill_near(x, land, max_km = 3))
  expect_equal(as.numeric(three), rep(c(5, 5, 5, 5, NA, NA), 2))
})

test_that("the current layers are averaged onto the grid, filled to the land, and land cover comes first", {
  registry <- atlas_layer_registry()
  for (id in c("elevation", "bioclim", "soil", "landcover", "terrain")) {
    expect_equal(registry[[id]]$method, "average", info = id)
  }
  expect_true(all(vapply(c("elevation", "bioclim", "soil"), function(id) isTRUE(registry[[id]]$fill_near), logical(1))))
  expect_false(isTRUE(registry$landcover$fill_near))
  expect_equal(ATLAS_FILL_NEAR_KM, 10)
})

test_that("a filled layer refuses to build before land cover, and land cover is built first", {
  skip_if_not_installed("terra")
  with_data_dir({
    built <- character()
    fake <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2000, ymin = 0, ymax = 2000,
                        crs = ATLAS_CRS)
    terra::values(fake) <- 1
    testthat::local_mocked_bindings(
      atlas_project_to_grid = function(x, grid, method) x,
      atlas_layer_registry = function() {
        list(
          soil = list(id = "soil", title = "Soil", source = "s", url = "u", license = "l",
                      citation = "c", method = "average", fill_near = TRUE,
                      fetch = function(path, res) { built <<- c(built, "soil"); fake }),
          landcover = list(id = "landcover", title = "Cover", source = "s", url = "u",
                           license = "l", citation = "c", method = "average",
                           fetch = function(path, res) { built <<- c(built, "landcover"); fake })
        )
      }
    )
    expect_error(atlas_build_layer("soil", "draft", quiet = TRUE), "build landcover")
    built <- character()
    atlas_build_layers(c("soil", "landcover"), "draft", quiet = TRUE)
    expect_equal(built, c("landcover", "soil"))
    expect_true(file.exists(atlas_layer_path("soil", "draft")))
  })
})

# --- A second source fills where the first is silent ---------------------------

test_that("a supplement fills only the cells the main source left empty, and is flagged", {
  skip_if_not_installed("terra")
  main <- terra::rast(nrows = 1, ncols = 4, xmin = 0, xmax = 4000, ymin = 0, ymax = 1000,
                      crs = ATLAS_CRS, nlyrs = 2)
  terra::values(main) <- cbind(c(0.5, NA, 0.2, NA), c(0.1, NA, NA, NA))
  names(main) <- c("forest_needleleaf", "forest_broadleaf")
  extra <- main
  terra::values(extra) <- cbind(c(0.9, 0.7, 0.9, NA), c(0.9, 0.3, 0.9, NA))
  out <- atlas_supplement(main, extra, known = "forest_known")
  v <- terra::values(out)
  expect_equal(names(out), c("forest_needleleaf", "forest_broadleaf", "forest_known"))
  # Described by the main source: kept, flagged 1.
  expect_equal(unname(v[1, ]), c(0.5, 0.1, 1))
  # Empty in the main source: the supplement's values, flagged 0.
  expect_equal(unname(v[2, ]), c(0.7, 0.3, 0), tolerance = 1e-6)
  # Half described counts as empty, so no cell mixes the two sources.
  expect_equal(unname(v[3, ]), c(0.9, 0.9, 0), tolerance = 1e-6)
  # Neither speaks: still empty.
  expect_true(all(is.na(v[4, ])))
})

test_that("building a supplemented layer projects the supplement and fills from it", {
  skip_if_not_installed("terra")
  with_data_dir({
    fake <- function(values) {
      r <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 2000, ymin = 0, ymax = 1000,
                       crs = ATLAS_CRS)
      terra::values(r) <- values
      names(r) <- "forest_mixed"
      r
    }
    testthat::local_mocked_bindings(
      atlas_project_to_grid = function(x, grid, method) x,
      atlas_layer_registry = function() list(
        foresttype = list(id = "foresttype", title = "Forest", source = "s", url = "u",
                          license = "l", citation = "c", method = "average",
                          fetch = function(path, res) fake(c(0.4, NA)),
                          supplement = function(path, res) fake(c(0.9, 0.6)),
                          supplement_known = "forest_known")
      )
    )
    record <- atlas_build_layer("foresttype", "draft", quiet = TRUE)
    expect_equal(unlist(record$bands), c("forest_mixed", "forest_known"))
    v <- terra::values(terra::rast(atlas_layer_path("foresttype", "draft")))
    expect_equal(unname(v[1, ]), c(0.4, 1))
    expect_equal(unname(v[2, ]), c(0.6, 0), tolerance = 1e-6)
  })
})
