# Maps are drawn in whole 50 km blocks of one fixed grid (R/blocks.R): a
# block is drawn only when its whole square lies inside the accessible area,
# and a map's raster is cropped to its kept blocks, so its extent lies on
# block lines.

BLOCK_M <- ATLAS_BLOCK_KM * 1000

# A window of the Atlas grid's 5 km cells, ncol x nrow cells from a corner
# given in cells from the grid's origin, TRUE where covered() is.
grid_land <- function(col0, row0, ncol, nrow, covered = function(x, y) TRUE) {
  xmin <- ATLAS_GRID_EXTENT[["xmin"]] + col0 * 5000
  ymax <- ATLAS_GRID_EXTENT[["ymax"]] - row0 * 5000
  r <- terra::rast(xmin = xmin, xmax = xmin + ncol * 5000, ymin = ymax - nrow * 5000, ymax = ymax,
                   resolution = 5000, crs = ATLAS_CRS)
  xy <- terra::xyFromCell(r, seq_len(terra::ncell(r)))
  terra::values(r) <- covered(xy[, 1], xy[, 2])
  r
}

# The accessible area of sites at these points: circles of radius_m.
circles <- function(x, y, radius_m) {
  terra::aggregate(terra::buffer(terra::vect(cbind(x, y), crs = ATLAS_CRS), width = radius_m))
}

# A map as a fit draws it: cropped to the area's window, drawn on the covered
# cells inside the area (atlas_predict_raster), each with its x in Mm.
map_of <- function(area, land) {
  window <- terra::crop(land, terra::ext(area))
  xy <- terra::xyFromCell(window, seq_len(terra::ncell(window)))
  out <- window
  terra::values(out) <- ifelse(terra::values(window, mat = FALSE) %in% c(TRUE, 1), xy[, 1] / 1e6, NA_real_)
  terra::mask(out, area)
}

on_block_line <- function(v, origin) abs(((v - origin) / BLOCK_M) - round((v - origin) / BLOCK_M)) < 1e-9

block_of <- function(x, y) {
  paste(floor((x - ATLAS_GRID_EXTENT[["xmin"]]) / BLOCK_M), floor((ATLAS_GRID_EXTENT[["ymax"]] - y) / BLOCK_M))
}

# The blocks of a trimmed map that hold a drawn cell.
drawn_blocks <- function(out) {
  if (is.null(out)) return(character())
  v <- terra::values(out, mat = FALSE)
  xy <- terra::xyFromCell(out, which(!is.na(v)))
  sort(unique(block_of(xy[, 1], xy[, 2])))
}

# The kept blocks, by name, whether or not they hold a drawn cell.
kept_blocks <- function(keep) {
  xy <- terra::xyFromCell(keep, which(!is.na(terra::values(keep, mat = FALSE))))
  sort(unique(block_of(xy[, 1], xy[, 2])))
}

# A block's square (col, row in blocks from the grid's origin) and its centre.
block_square <- function(col, row) {
  x0 <- ATLAS_GRID_EXTENT[["xmin"]] + col * BLOCK_M
  y1 <- ATLAS_GRID_EXTENT[["ymax"]] - row * BLOCK_M
  list(xmin = x0, xmax = x0 + BLOCK_M, ymin = y1 - BLOCK_M, ymax = y1,
       cx = x0 + BLOCK_M / 2, cy = y1 - BLOCK_M / 2, name = paste(col, row))
}

land <- grid_land(1440, 760, 160, 160)
centre <- terra::xyFromCell(land, terra::cellFromRowCol(land, 80, 80))

test_that("a map's drawn footprint is a union of whole blocks of the fixed grid, and its extent lies on block lines", {
  area <- circles(centre[1], centre[2], 3e5)
  map <- map_of(area, land)
  out <- atlas_block_trim(map, NULL, area, land)$suitability
  e <- terra::ext(out)
  expect_true(on_block_line(terra::xmin(e), ATLAS_GRID_EXTENT[["xmin"]]))
  expect_true(on_block_line(terra::xmax(e), ATLAS_GRID_EXTENT[["xmin"]]))
  expect_true(on_block_line(terra::ymax(e), ATLAS_GRID_EXTENT[["ymax"]]))
  expect_true(on_block_line(terra::ymin(e), ATLAS_GRID_EXTENT[["ymax"]]))
  v <- terra::values(out, mat = FALSE)
  xy <- terra::xyFromCell(out, seq_len(terra::ncell(out)))
  blocks <- block_of(xy[, 1], xy[, 2])
  drawn <- tapply(!is.na(v), blocks, mean)
  # On covered ground every block is drawn whole or not at all, and the
  # drawn cells keep their values.
  expect_true(all(drawn %in% c(0, 1)))
  expect_gt(sum(drawn == 1), 0L)
  kept <- !is.na(v)
  expect_equal(v[kept], terra::extract(map, xy[kept, , drop = FALSE])[, 1])
  # Fewer cells than the circle: the blocks its edge cuts are left out.
  expect_lt(sum(kept), sum(!is.na(terra::values(map))))
})

test_that("two maps on different windows share the same block lines", {
  for (shift in c(0, 7 * 5000, 13 * 5000)) {
    area <- circles(centre[1] + shift, centre[2] - shift, 2.5e5)
    out <- atlas_block_trim(map_of(area, land), NULL, area, land)$suitability
    e <- terra::ext(out)
    expect_true(on_block_line(terra::xmin(e), ATLAS_GRID_EXTENT[["xmin"]]))
    expect_true(on_block_line(terra::ymax(e), ATLAS_GRID_EXTENT[["ymax"]]))
  }
})

test_that("a block is drawn only when its whole square lies inside the area, wherever its covered cells are", {
  # One block of the window, and a circle whose edge runs through its east half.
  b <- block_square(152, 84)
  stopifnot(b$xmin > terra::xmin(land) + 3e5, b$xmax < terra::xmax(land) - 3e5)
  r <- 2.6e5
  cut <- circles(b$cx - r + BLOCK_M / 4, b$cy, r)
  expect_false(terra::relate(terra::vect(terra::ext(b$xmin, b$xmax, b$ymin, b$ymax), crs = ATLAS_CRS), cut, "coveredby")[1, 1])
  # The block covered by the predictors on a single cell, near its west edge,
  # and that cell inside the area: still not drawn, as part of its square is
  # outside.
  one_cell <- function(x, y) !(x > b$xmin & x < b$xmax & y > b$ymin & y < b$ymax) |
    (abs(x - (b$xmin + 2500)) < 1 & abs(y - (b$cy + 2500)) < 1)
  sparse <- grid_land(1440, 760, 160, 160, one_cell)
  expect_true(terra::extract(map_of(cut, sparse), cbind(b$xmin + 2500, b$cy + 2500))[1, 1] > 0)
  out <- atlas_block_trim(map_of(cut, sparse), NULL, cut, sparse)$suitability
  expect_false(b$name %in% drawn_blocks(out))
  # A circle that holds the whole square: drawn, with one covered cell, with
  # all of them, or with a few anywhere in it.
  holds <- circles(b$cx, b$cy, 2.6e5)
  few <- function(x, y) !(x > b$xmin & x < b$xmax & y > b$ymin & y < b$ymax) |
    ((round((x - b$xmin - 2500) / 5000) %% 4) == 1 & (round((y - b$ymin - 2500) / 5000) %% 3) == 2)
  for (cover in list(one_cell, function(x, y) TRUE, few)) {
    g <- grid_land(1440, 760, 160, 160, cover)
    expect_true(b$name %in% drawn_blocks(atlas_block_trim(map_of(holds, g), NULL, holds, g)$suitability))
  }
  # Which blocks are kept never depends on where covered cells are: the same
  # area keeps the same blocks over every pattern of cover.
  sets <- lapply(list(one_cell, function(x, y) TRUE, few, function(x, y) (x + y) %% 2e5 < 1e5), function(cover) {
    g <- grid_land(1440, 760, 160, 160, cover)
    kept_blocks(atlas_block_trim(map_of(cut, g), NULL, cut, g)$keep)
  })
  for (s in sets[-1]) expect_identical(s, sets[[1]])
})

test_that("moving the area's edge across ground the predictors do not cover changes which blocks are drawn", {
  # Covered ground ends at a coast through a block; east of it is uncovered.
  b <- block_square(152, 84)
  coast <- b$xmin + 20000
  g <- grid_land(1440, 760, 160, 160, function(x, y) x < coast)
  # Both circles hold the block's covered part; only the second holds its
  # uncovered part too.
  short <- circles(b$xmin - 2.4e5, b$cy, 2.4e5 + 30000)
  long <- circles(b$xmin - 2.4e5, b$cy, 2.4e5 + 80000)
  m_short <- map_of(short, g)
  m_long <- map_of(long, g)
  # The map as predicted is the same on the block's covered cells.
  probe <- cbind(b$xmin + 2500 + 5000 * (0:3), b$cy)
  expect_equal(terra::extract(m_short, probe)[, 1], terra::extract(m_long, probe)[, 1])
  expect_false(b$name %in% drawn_blocks(atlas_block_trim(m_short, NULL, short, g)$suitability))
  expect_true(b$name %in% drawn_blocks(atlas_block_trim(m_long, NULL, long, g)$suitability))
})

test_that("a block that runs past the grid's edge is dropped, and an area holding no whole block draws nothing", {
  ncol <- ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / 5000)
  edge_land <- grid_land(ncol - 30, 300, 30, 40)
  e <- terra::ext(edge_land)
  edge_area <- circles(terra::xmax(e) - 20000, (terra::ymin(e) + terra::ymax(e)) / 2, 1.2e5)
  out <- atlas_block_trim(map_of(edge_area, edge_land), NULL, edge_area, edge_land)$suitability
  if (!is.null(out)) expect_lte(terra::xmax(terra::ext(out)), ATLAS_GRID_EXTENT[["xmax"]])
  small <- circles(centre[1], centre[2], 30000)
  expect_null(atlas_block_trim(map_of(small, land), NULL, small, land)$suitability)
})

test_that("the map's index is masked to the same blocks as the map", {
  area <- circles(centre[1], centre[2], 3e5)
  map <- map_of(area, land)
  index <- map
  terra::values(index) <- ifelse(is.na(terra::values(map, mat = FALSE)), NA, 0.5)
  out <- atlas_block_trim(map, index, area, land)
  expect_true(terra::compareGeom(out$suitability, out$dissimilarity))
  expect_identical(is.na(terra::values(out$suitability, mat = FALSE)), is.na(terra::values(out$dissimilarity, mat = FALSE)))
})

test_that("an area that is not the map's is refused: the trim stops, and the stored map's check fails", {
  area <- circles(centre[1], centre[2], 3e5)
  map <- map_of(area, land)
  expect_true(atlas_block_area_matches(map, area, land))
  moved <- circles(centre[1] + 15000, centre[2], 3e5)
  expect_false(atlas_block_area_matches(map, moved, land))
  bigger <- circles(centre[1], centre[2], 3.2e5)
  expect_false(atlas_block_area_matches(map, bigger, land))
  expect_error(atlas_block_trim(map, NULL, bigger, land), "not drawn")
})

test_that("a stored map's area is built again from the sites of the pull it was fitted on", {
  with_data_dir({
    occurrences <- synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30))
    points <- atlas_occurrence_points(occurrences, "draft")
    big <- terra::rast(getOption("atlas.block_land"))
    area <- atlas_block_area("Taxon A", points, big, 500, ATLAS_SITE_KM)
    sites <- attr(atlas_ensure_sites(points, ATLAS_SITE_KM), "sites")
    own <- sites[unique(atlas_ensure_sites(points, ATLAS_SITE_KM)$site[points$scientific_name == "Taxon A"]), ]
    expect_equal(terra::expanse(area), terra::expanse(atlas_accessible_area(own$x, own$y, 500)), tolerance = 1e-9)
    # Sites the predictors do not cover play no part, as in a fit.
    none <- big
    terra::values(none) <- 0L
    expect_null(atlas_block_area("Taxon A", points, none, 500, ATLAS_SITE_KM))
    expect_null(atlas_block_area("Nobody", points, big, 500, ATLAS_SITE_KM))
  })
})

test_that("a fitted map is drawn in whole blocks; its scores are those of the map as predicted, and its full view is unchanged", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  fit <- function(blocks) {
    if (!blocks) local_mocked_bindings(atlas_block_trim = function(suitability, dissimilarity = NULL, area, land = NULL, ...) {
      list(suitability = suitability, dissimilarity = dissimilarity)
    })
    with_data_dir({
      world <- synthetic_landscape()
      atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                      fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                      buffer_km = 300, quiet = TRUE, nulls = 0, tune = FALSE,
                      guilds = stats::setNames(character(), character()), full = TRUE)
      tif <- atlas_model_path("Eastern fungus", "draft", ".tif")
      full <- atlas_model_path("Eastern fungus", "draft", ATLAS_FULL_EXTS)
      list(metrics = atlas_read_metrics("Eastern fungus", "draft"), extent = as.vector(terra::ext(terra::rast(tif))),
           cells = sum(!is.na(terra::values(terra::rast(tif)))),
           index_na = is.na(terra::values(terra::rast(sub("[.]tif$", ".di.tif", tif)), mat = FALSE)),
           map_na = is.na(terra::values(terra::rast(tif), mat = FALSE)),
           full = vapply(full, atlas_sha256, ""))
    })
  }
  with <- fit(TRUE)
  without <- fit(FALSE)
  expect_true(on_block_line(with$extent[["xmin"]], ATLAS_GRID_EXTENT[["xmin"]]))
  expect_true(on_block_line(with$extent[["ymax"]], ATLAS_GRID_EXTENT[["ymax"]]))
  expect_lt(with$cells, without$cells)
  expect_identical(with$index_na, with$map_na)
  # The bounds the picture is laid at come from the trimmed map.
  expect_false(identical(with$metrics$bounds, without$metrics$bounds))
  for (field in c("auc_mean", "auc_sd", "boyce", "folds", "null", "skill", "grade", "presences", "params")) {
    expect_identical(with$metrics[[field]], without$metrics[[field]], info = field)
  }
  expect_identical(unname(with$full), unname(without$full))
})

# ---- finishing again -------------------------------------------------------

# A store whose current release has maps of Taxon A and Taxon B drawn as
# their fits drew them, never finished, and the job that fitted them, with its
# pull. unknown gives Taxon A a record set no pull holds; shifted draws its
# stored map from an area 15 km off the one its sites give; holed leaves a
# patch of covered cells in the middle of its area undrawn (the same window,
# other cells).
blocks_published <- function(unknown = FALSE, shifted = FALSE, holed = FALSE) {
  store <- fresh_store()
  boss <- machine()
  release <- on_machine(boss, {
    occurrences <- synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30))
    orchestrator_data(occurrences)
    big <- terra::rast(getOption("atlas.block_land"))
    points <- atlas_occurrence_points(occurrences, "draft")
    dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE, showWarnings = FALSE)
    for (name in c("Taxon A", "Taxon B")) {
      area <- atlas_block_area(name, points, big, 500, ATLAS_SITE_KM)
      if (shifted && name == "Taxon A") area <- terra::shift(area, dx = 15000)
      r <- map_of(area, big)
      if (holed && name == "Taxon A") {
        middle <- terra::centroids(area)
        patch <- terra::cellFromXY(r, terra::crds(middle)[rep(1, 9), , drop = FALSE] +
                                     cbind(rep(c(-5000, 0, 5000), 3), rep(c(-5000, 0, 5000), each = 3)))
        r[patch] <- NA
      }
      tif <- atlas_model_path(name, "draft", ".tif", "maxnet")
      terra::writeRaster(r, tif, overwrite = TRUE)
      drawn <- atlas_write_map_png(r, sub("[.]tif$", ".png", tif))
      fingerprint <- if (unknown && name == "Taxon A") "0000000" else unname(atlas_fingerprints_for(occurrences, name))
      atlas_write_json(list(taxon = name, algorithm = "maxnet", skill = "passed", grade = "strong", presences = 25,
                            fingerprint = fingerprint, settings = list(buffer_km = 500, thin_km = ATLAS_SITE_KM),
                            raster = basename(tif), map = basename(drawn$path), bounds = drawn$bounds,
                            built_at = "2026-10-06T00:00:00Z"),
                       sub("[.]tif$", ".json", tif))
    }
    pull <- atlas_file_entries(file.path("occurrences", "occurrences-20260101T000000Z.tsv.gz"))
    atlas_upload_objects(store, pull)
    atlas_store_json(store, "jobs/draft/20261005T000000Z-job/job.json", list(
      id = "20261005T000000Z-job", created_at = "2026-10-05T00:00:00Z", inputs = pull,
      tasks = list(list(taxon = "Taxon A", algorithm = "maxnet"), list(taxon = "Taxon B", algorithm = "maxnet"))
    ))
    atlas_publish_release(store, quiet = TRUE)
  })
  list(store = store, boss = boss, release = release)
}

entry_of <- function(index, name) Filter(function(e) identical(e$taxon, name), index)[[1]]

store_objects <- function(store, release) {
  manifest <- atlas_store_text(store, paste0("releases/draft/", release$id, ".json"))
  c(manifest = digest::digest(manifest),
    vapply(manifest$files, function(f) {
      file <- tempfile()
      store$get(atlas_object_key(f$sha256), file)
      atlas_sha256(file)
    }, ""))
}

test_that("finishing again draws every map in whole blocks of its own area, in a new release that leaves the old one as it was", {
  skip_if_not_installed("terra")
  setup <- blocks_published()
  before <- store_objects(setup$store, setup$release)
  record <- on_machine(machine(), {
    out <- atlas_finish_release_work(setup$store, setup$release$id, quiet = TRUE)
    tif <- atlas_model_path("Taxon A", "draft", ".tif", "maxnet")
    out$extent <- as.vector(terra::ext(terra::rast(tif)))
    out$metrics <- atlas_read_metrics("Taxon A", "draft", "maxnet")
    out
  })
  expect_equal(record$trimmed, 2L)
  expect_equal(record$not_drawn$not_found, 0L)
  expect_equal(record$not_drawn$mismatch, 0L)
  paths <- vapply(record$files, `[[`, "", "path")
  expect_true(all(c("models/draft/taxon-a.tif", "models/draft/taxon-a.png", "models/draft/taxon-a.json") %in% paths))
  expect_true(on_block_line(record$extent[["xmin"]], ATLAS_GRID_EXTENT[["xmin"]]))
  expect_equal(record$metrics$blocks_km, ATLAS_BLOCK_KM)
  # Counted by state again, from the drawn cells.
  expect_false(is.null(record$metrics$regions))
  finished <- on_machine(setup$boss, atlas_apply_finish(setup$store, setup$release$id, quiet = TRUE))
  expect_equal(finished$previous, setup$release$id)
  expect_equal(finished$finished$version, ATLAS_FINISH_VERSION)
  expect_true(entry_of(finished$index, "Taxon A")$map)
  # The release it came from is exactly as it was.
  expect_identical(store_objects(setup$store, setup$release), before)
  # And it is the way back: promoting it serves its own files again.
  on_machine(setup$boss, atlas_promote_release(setup$store, setup$release$id, "draft"))
  expect_equal(atlas_current_release(setup$store, "draft")$id, setup$release$id)
})

test_that("finishing on several processes draws the same maps as on one", {
  skip_if_not_installed("terra")
  one <- blocks_published()
  two <- blocks_published()
  files <- function(setup, workers) on_machine(machine(), {
    atlas_finish_release_work(setup$store, setup$release$id, workers = workers, quiet = TRUE)
    vapply(atlas_model_path(c("Taxon A", "Taxon B"), "draft", ".tif", "maxnet"),
           function(p) digest::digest(terra::values(terra::rast(p), mat = FALSE)), "")
  })
  expect_identical(unname(files(one, 1L)), unname(files(two, 2L)))
})

test_that("a map whose record set no kept pull holds, or whose area does not give it, is taken off with its reason, never drawn as it was", {
  skip_if_not_installed("terra")
  for (case in list(list(unknown = TRUE, shifted = FALSE, holed = FALSE, reason = "not found"),
                    list(unknown = FALSE, shifted = TRUE, holed = FALSE, reason = "mismatch"),
                    list(unknown = FALSE, shifted = FALSE, holed = TRUE, reason = "mismatch"))) {
    setup <- blocks_published(unknown = case$unknown, shifted = case$shifted, holed = case$holed)
    record <- on_machine(machine(), {
      out <- atlas_finish_release_work(setup$store, setup$release$id, quiet = TRUE)
      out$left <- file.exists(atlas_model_path("Taxon A", "draft", c(".tif", ".di.tif", ".png"), "maxnet"))
      out
    })
    # The other map is drawn in blocks as ever.
    expect_equal(record$trimmed, 1L, info = case$reason)
    expect_equal(record$not_drawn$not_found, as.integer(case$reason == "not found"), info = case$reason)
    expect_equal(record$not_drawn$mismatch, as.integer(case$reason == "mismatch"), info = case$reason)
    expect_equal(record$not_drawn$models[[1]]$reason, case$reason)
    expect_false(any(record$left), info = case$reason)
    expect_true("models/draft/taxon-a.tif" %in% unlist(record$removed), info = case$reason)
    finished <- on_machine(setup$boss, atlas_apply_finish(setup$store, setup$release$id, quiet = TRUE))
    paths <- vapply(finished$files, `[[`, "", "path")
    expect_false("models/draft/taxon-a.tif" %in% paths, info = case$reason)
    expect_false(entry_of(finished$index, "Taxon A")$map, info = case$reason)
    expect_true(entry_of(finished$index, "Taxon B")$map, info = case$reason)
    expect_true("models/draft/taxon-b.tif" %in% paths, info = case$reason)
    expect_equal(finished$finished$not_drawn[[sub(" ", "_", case$reason)]], 1L, info = case$reason)
  }
})

test_that("before a finish, the plan counts the maps whose record set a kept pull holds and those it does not, and writes nothing", {
  skip_if_not_installed("terra")
  setup <- blocks_published(unknown = TRUE)
  listing <- sort(list.files(sub("^file://", "", setup$store$uri), recursive = TRUE))
  plan <- atlas_block_plan(setup$store, "draft", quiet = TRUE)
  expect_equal(plan$maps, 2L)
  expect_equal(plan$found, 1L)
  expect_equal(plan$by_fitting_job, 1L)
  expect_equal(plan$not_found, 1L)
  expect_equal(plan$missing[[1]]$taxon, "Taxon A")
  expect_identical(sort(list.files(sub("^file://", "", setup$store$uri), recursive = TRUE)), listing)
  expect_equal(atlas_block_plan(blocks_published()$store, "draft", quiet = TRUE)$not_found, 0L)
})

test_that("a store can put, get, list and say what it holds, and has no way to delete", {
  for (store in list(atlas_local_store(machine()), atlas_s3_store("bucket", client = list()))) {
    expect_setequal(names(store), c("uri", "put", "get", "exists", "list"))
  }
})

test_that("a card is framed at the bounds of the map drawn in blocks, and the card list holds only files", {
  skip_if_not_installed("terra")
  setup <- blocks_published()
  out <- on_machine(machine(), {
    atlas_finish_release_work(setup$store, setup$release$id, quiet = TRUE)
    framed <- NULL
    draw <- function(path, title, metrics = list(), ...) {
      framed <<- metrics$bounds
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      writeLines("card", path)
    }
    built <- atlas_build_cards("draft", store = setup$store, quiet = TRUE, taxa = "Taxon A", draw = draw)
    list(framed = framed, bounds = atlas_read_metrics("Taxon A", "draft", "maxnet")$bounds,
         list = atlas_store_text(setup$store, built$key))
  })
  published <- on_machine(setup$boss, atlas_read_metrics("Taxon A", "draft", "maxnet")$bounds)
  expect_false(is.null(out$framed))
  expect_equal(out$framed, out$bounds)
  expect_false(isTRUE(all.equal(out$framed, published)))
  expect_setequal(names(out$list), c("release", "grid", "commit", "built_at", "files"))
  for (f in out$list$files) expect_setequal(names(f), c("path", "sha256", "bytes"))
})

test_that("a map already drawn in blocks is left as it is when finished again", {
  skip_if_not_installed("terra")
  setup <- blocks_published()
  on_machine(machine(), {
    atlas_finish_release_work(setup$store, setup$release$id, quiet = TRUE)
    tif <- atlas_model_path("Taxon A", "draft", ".tif", "maxnet")
    before <- atlas_sha256(tif)
    expect_equal(atlas_block_trim_stored(tif, NULL, terra::rast(getOption("atlas.block_land"))), "already")
    expect_identical(atlas_sha256(tif), before)
  })
})

test_that("a frozen release is never finished, and a release finished under a later rule counts as finished", {
  frozen <- ATLAS_FROZEN_RELEASES[[1]]
  expect_error(atlas_refuse_frozen(frozen), "frozen")
  expect_error(atlas_finish_release_work(fresh_store(), frozen, quiet = TRUE), "frozen")
  expect_error(atlas_apply_finish(fresh_store(), frozen, quiet = TRUE), "frozen")
  expect_true(atlas_release_finished(list(finished = list(version = ATLAS_FINISH_VERSION + 1L))))
  expect_false(atlas_release_finished(list(finished = list(version = ATLAS_FINISH_VERSION - 1L))))
  # The nightly passes a frozen current release by.
  with_data_dir({
    launched <- FALSE
    local_mocked_bindings(atlas_current_release = function(...) list(id = frozen),
                          atlas_one_worker_on_ec2 = function(...) { launched <<- TRUE; NULL })
    expect_message(out <- atlas_finish_on_ec2(fresh_store(), "draft", config = list(finish_hours = 1), quiet = FALSE),
                   "frozen")
    expect_null(out)
    expect_false(launched)
  })
})

test_that("one orchestrator on the box at a time: a second refuses while the first runs, and a dead run's lock is taken over", {
  with_data_dir({
    inner <- NULL
    atlas_with_orchestrator_lock("nightly", 6, {
      inner <- tryCatch(atlas_with_orchestrator_lock("finish-current", 3, "ran"), error = function(e) conditionMessage(e))
    })
    expect_match(inner, "nightly has held the box's orchestrator lock")
    # Released when the run ends, even by an error.
    expect_equal(atlas_with_orchestrator_lock("finish-current", 3, "ran"), "ran")
    expect_error(atlas_with_orchestrator_lock("nightly", 6, stop("boom")), "boom")
    expect_equal(atlas_with_orchestrator_lock("finish-current", 3, "ran"), "ran")
    # A lock left by a killed run is taken over once its hours have passed.
    dir <- atlas_path("locks", "orchestrator")
    dir.create(dir, recursive = TRUE)
    atlas_write_json(list(name = "nightly", since = "2026-11-01T07:00:00Z", until = "2026-11-01T15:00:00Z"),
                     file.path(dir, "held.json"))
    expect_message(out <- atlas_with_orchestrator_lock("finish-current", 3, "ran"), "taking over")
    expect_equal(out, "ran")
  })
})
