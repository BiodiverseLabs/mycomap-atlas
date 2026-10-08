# A taxon's map as one picture, for Excel's =IMAGE(), documents and slides.

png_size <- function(bytes) {
  if (is.character(bytes)) bytes <- readBin(bytes, "raw", file.info(bytes)$size)
  number <- function(at) sum(as.integer(bytes[at:(at + 3)]) * 256^(3:0))
  c(width = number(17), height = number(21))
}

# Pixels clearly green: the map's colour, not land, water or text.
green_pixels <- function(path) {
  v <- terra::values(terra::rast(path), mat = TRUE)
  sum(v[, 2] > v[, 1] + 30 & v[, 2] > v[, 3] + 30)
}

# A map around Indiana, drawn as the site draws it.
indiana_map <- function(dir) {
  r <- terra::rast(xmin = 7e5, xmax = 1e6, ymin = -1e5, ymax = 3e5, resolution = 5000, crs = ATLAS_CRS)
  terra::values(r) <- terra::xFromCell(r, seq_len(terra::ncell(r)))
  drawn <- atlas_write_map_png(r, file.path(dir, "map.png"))
  list(raster = r, overlay = drawn$path,
       metrics = list(taxon = "Trametes versicolor", algorithm = "maxnet", skill = "passed", grade = "strong",
                      bounds = drawn$bounds, map_drawn_at = drawn$drawn_at))
}

indiana_cells <- data.frame(lat = c(39.77, 41.08), lng = c(-86.16, -85.14), records = c(3L, 1L))

test_that("a picture opens on the collections widened by the colour's reach, inside the map", {
  view <- atlas_image_view(indiana_cells)
  expect_lt(view$south, 39.77 - 4)
  expect_gt(view$north, 41.08 + 4)
  raster <- list(south = 38, west = -90, north = 43, east = -80)
  inside <- atlas_image_view(indiana_cells, raster)
  expect_equal(unlist(inside), unlist(raster)[c("south", "west", "north", "east")])
  expect_equal(atlas_image_view(NULL, raster), raster)
  expect_equal(atlas_image_view(NULL, NULL)$west, -170)
})

test_that("a picture is drawn at the width asked, three quarters as tall, with the map's colour on it", {
  skip_if_not_installed("terra")
  dir <- tempfile("img-")
  dir.create(dir)
  m <- indiana_map(dir)
  with_map <- file.path(dir, "with.png")
  atlas_write_map_image(with_map, "Trametes versicolor", m$metrics, m$overlay, indiana_cells,
                        records = 4, width = 900L, site = "https://atlas.example.org")
  expect_equal(unname(png_size(with_map)), c(900, 675))

  without <- file.path(dir, "without.png")
  atlas_write_map_image(without, "Trametes versicolor", NULL, NULL, indiana_cells,
                        records = 4, width = 900L, site = "https://atlas.example.org")
  expect_gt(green_pixels(with_map), 5000)
  expect_lt(green_pixels(without), 500)
})

test_that("a map that failed its null test, or is only weak, is drawn faint in the picture", {
  skip_if_not_installed("terra")
  dir <- tempfile("img-")
  dir.create(dir)
  m <- indiana_map(dir)
  strong <- file.path(dir, "strong.png")
  faint <- file.path(dir, "faint.png")
  weak <- file.path(dir, "weak.png")
  atlas_write_map_image(strong, "T", m$metrics, m$overlay, indiana_cells, width = 600L)
  failed <- m$metrics
  failed$skill <- "failed"
  failed$grade <- "failed"
  atlas_write_map_image(faint, "T", failed, m$overlay, indiana_cells, width = 600L)
  expect_lt(green_pixels(faint), green_pixels(strong) / 2)
  # Passed, but only scattered nulls: as faint as a failed map.
  scatter <- m$metrics
  scatter$grade <- NULL
  scatter$null <- list(observed_auc = 0.8)
  atlas_write_map_image(weak, "T", scatter, m$overlay, indiana_cells, width = 600L)
  expect_lt(green_pixels(weak), green_pixels(strong) / 2)
})

# ---- through the API --------------------------------------------------------

with_image_data <- function(code) {
  with_data_dir({
    atlas_write_json(data.frame(scientific_name = "Trametes versicolor", records = 4L,
                                localities = 2L, fingerprint = "f"),
                     atlas_path("occurrences", "taxa-latest.json"))
    occurrences <- data.frame(
      id = c("1", "2"), scientific_name = "Trametes versicolor",
      latitude = c("39.7700", "41.0800"), longitude = c("-86.1600", "-85.1400"),
      state = "Indiana", country = "US", stringsAsFactors = FALSE
    )
    file <- "occurrences-20260101T000000Z.tsv.gz"
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(stamp = "20260101T000000Z", file = file, records = 2),
                     atlas_path("occurrences", "latest.json"))
    dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE, showWarnings = FALSE)
    m <- indiana_map(tempdir())
    file.copy(m$overlay, atlas_model_path("Trametes versicolor", "draft", ".png", "maxnet"), overwrite = TRUE)
    atlas_write_json(m$metrics, atlas_model_path("Trametes versicolor", "draft", ".json", "maxnet"))
    force(code)
  })
}

image_api <- function() test_api(c(ATLAS_PUBLIC_ORIGIN = "https://atlas.example.org"))

call_image <- function(api, path, query = "") {
  # call_api turns a body into text; a picture stays bytes.
  req <- new.env()
  req$REQUEST_METHOD <- "GET"
  req$PATH_INFO <- path
  req$QUERY_STRING <- if (nzchar(query)) paste0("?", query) else ""
  req$REMOTE_ADDR <- "203.0.113.5"
  req$SERVER_NAME <- "127.0.0.1"
  req$SERVER_PORT <- "5100"
  req$HTTP_HOST <- "atlas.example.org"
  req$rook.input <- list(read = function(...) raw(), rewind = function() invisible(), read_lines = function() character())
  suppressMessages(api$call(req))
}

test_that("anyone can fetch a taxon's picture, at a width rounded to one of four", {
  skip_if_not_installed("terra")
  with_image_data({
    out <- call_image(image_api(), "/api/taxa/Trametes%20versicolor/image.png", "width=1000")
    expect_equal(out$status, 200L)
    expect_equal(out$headers[["Content-Type"]], "image/png")
    expect_equal(out$body[1:4], as.raw(c(0x89, 0x50, 0x4e, 0x47)))
    expect_equal(unname(png_size(out$body)), c(900, 675))
  })
})

test_that("a picture of an unknown taxon is 404 and of an unknown model 400", {
  with_image_data({
    api <- image_api()
    expect_equal(call_image(api, "/api/taxa/Nothing%20here/image.png")$status, 404L)
    expect_equal(call_image(api, "/api/taxa/Trametes%20versicolor/image.png", "algorithm=magic")$status, 400L)
  })
})

test_that("a picture shows Maxent when none is asked for, else the ensemble, and refuses an unknown model", {
  with_data_dir({
    fit <- function(algorithm) {
      dir.create(atlas_model_dir("draft", algorithm), recursive = TRUE, showWarnings = FALSE)
      atlas_write_json(list(taxon = "T"), atlas_model_path("T", "draft", ".json", algorithm))
    }
    fit("esm")
    expect_equal(atlas_image_algorithm("T"), "esm")
    # 20 to 49 sites: Maxent, the ensemble and the forest; Maxent comes first,
    # as on the taxon page.
    fit("maxnet")
    fit("rf")
    expect_equal(atlas_image_algorithm("T"), "maxnet")
    expect_equal(atlas_image_algorithm("T", "rf"), "rf")
    expect_null(atlas_image_algorithm("T", "magic"))
  })
})
