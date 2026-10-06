# The host-tree layer: two forest inventories brought to one unit, the share
# of a cell's trees in each genus. No test reaches the network; the HTTP layer
# is a stand-in throughout.

# ---- BIGMAP's species -----------------------------------------------------

BIGMAP_SAMPLE <- c(
  "SPCD_0000_Total", "None", "SPCD_0010_Abies_spp.", "SPCD_0068_Juniperus_virginiana",
  "SPCD_0202_Pseudotsuga_menziesii", "SPCD_0263_Tsuga_heterophylla",
  "SPCD_0316_Acer_rubrum", "SPCD_0631_Lithocarpus_densiflorus",
  "SPCD_0802_Quercus_alba", "SPCD_0999_Tree_unknown"
)

test_that("BIGMAP's raster functions are read as species, genus and softwood", {
  species <- atlas_bigmap_species(BIGMAP_SAMPLE)
  # The total and the placeholder function are not species.
  expect_false(any(c("SPCD_0000_Total", "None") %in% species$fn))
  by_fn <- split(species, species$fn)
  expect_equal(by_fn$SPCD_0202_Pseudotsuga_menziesii$genus, "Pseudotsuga")
  expect_equal(by_fn$SPCD_0202_Pseudotsuga_menziesii$spcd, 202L)
  # FIA codes under 300 are softwoods: juniper is a conifer, oak is not.
  expect_true(by_fn$SPCD_0068_Juniperus_virginiana$conifer)
  expect_false(by_fn$SPCD_0802_Quercus_alba$conifer)
  # Juniper is a conifer but not a host genus; maple is neither.
  expect_false(by_fn$SPCD_0068_Juniperus_virginiana$host)
  expect_false(by_fn$SPCD_0316_Acer_rubrum$host)
  expect_false(by_fn$SPCD_0999_Tree_unknown$host)
})

test_that("tanoak, filed by BIGMAP under Lithocarpus, counts as Notholithocarpus", {
  species <- atlas_bigmap_species(BIGMAP_SAMPLE)
  tanoak <- species[species$fn == "SPCD_0631_Lithocarpus_densiflorus", ]
  expect_equal(tanoak$genus, "Notholithocarpus")
  expect_true(tanoak$host)
  groups <- atlas_bigmap_groups(species)
  expect_equal(groups$notholithocarpus, "SPCD_0631_Lithocarpus_densiflorus")
})

test_that("the total a share is taken over is every species, not BIGMAP's own total", {
  species <- atlas_bigmap_species(BIGMAP_SAMPLE)
  needed <- atlas_bigmap_needed(species)
  # BIGMAP's total is modelled apart from its species and does not add up to
  # them, so it is never read.
  expect_false("SPCD_0000_Total" %in% needed)
  # Maple hosts nothing, but it is part of the trees a genus is a share of.
  expect_true("SPCD_0316_Acer_rubrum" %in% needed)
  groups <- atlas_bigmap_groups(species)
  expect_equal(names(groups), c("total", "conifer", tolower(ATLAS_HOST_GENERA)))
  expect_setequal(groups$total, species$fn)
  expect_setequal(groups$conifer, c("SPCD_0010_Abies_spp.", "SPCD_0068_Juniperus_virginiana",
                                    "SPCD_0202_Pseudotsuga_menziesii", "SPCD_0263_Tsuga_heterophylla"))
  # A host genus BIGMAP has no species for here is an empty group, not an error.
  expect_length(groups$fagus, 0L)
})

test_that("an export request draws one species onto the grid's own cells", {
  url <- atlas_bigmap_export_url(
    "SPCD_0202_Pseudotsuga_menziesii",
    bbox = c(xmin = -2000000, ymin = 500000, xmax = -1000000, ymax = 1500000),
    size = c(4000, 4000)
  )
  expect_true(startsWith(url, paste0(ATLAS_BIGMAP_URL, "/exportImage?")))
  query <- strsplit(sub("^[^?]*[?]", "", url), "&", fixed = TRUE)[[1]]
  params <- stats::setNames(
    vapply(query, function(q) utils::URLdecode(sub("^[^=]*=", "", q)), character(1)),
    sub("=.*$", "", query)
  )
  # Whole metres, never 1e+06.
  expect_equal(params[["bbox"]], "-2000000,500000,-1000000,1500000")
  expect_equal(params[["size"]], "4000,4000")
  expect_equal(jsonlite::fromJSON(params[["renderingRule"]])$rasterFunction,
               "SPCD_0202_Pseudotsuga_menziesii")
  expect_equal(jsonlite::fromJSON(params[["imageSR"]])$wkt, ATLAS_ESRI_WKT)
  expect_equal(params[["bboxSR"]], params[["imageSR"]])
  # Point samples, averaged here: the server's own averaging is not a block mean.
  expect_equal(params[["interpolation"]], "RSP_NearestNeighbor")
  expect_equal(params[["format"]], "tiff")
  expect_equal(params[["pixelType"]], "F32")
  expect_equal(params[["f"]], "image")
})

test_that("the ESRI projection sent to BIGMAP is the grid's projection", {
  skip_if_not_installed("terra")
  expect_true(terra::same.crs(terra::crs(ATLAS_ESRI_WKT), ATLAS_CRS))
  # A point lands on the same metres either way.
  p <- terra::vect(cbind(-122.2, 45.8), crs = "EPSG:4326")
  expect_equal(terra::crds(terra::project(p, ATLAS_ESRI_WKT)),
               terra::crds(terra::project(p, ATLAS_CRS)), tolerance = 1e-6)
})

test_that("tiles cover the window exactly, in whole sample pixels, without overlap", {
  window <- c(xmin = -2500000, xmax = 2300000, ymin = -1400000, ymax = 1500000)
  tiles <- atlas_bigmap_tiles(window, sample_m = 250, tile_px = 8000)
  expect_length(tiles, 3L * 2L)
  area <- sum(vapply(tiles, function(t) prod(t$size) * 250^2, numeric(1)))
  expect_equal(area, (window[["xmax"]] - window[["xmin"]]) * (window[["ymax"]] - window[["ymin"]]))
  for (t in tiles) {
    expect_lte(max(t$size), 8000)
    expect_equal(t$size, c(t$bbox[["xmax"]] - t$bbox[["xmin"]], t$bbox[["ymax"]] - t$bbox[["ymin"]]) / 250)
    expect_gte(t$bbox[["xmin"]], window[["xmin"]])
    expect_lte(t$bbox[["ymax"]], window[["ymax"]])
  }
  expect_error(atlas_bigmap_tiles(c(xmin = 0, xmax = 1100, ymin = 0, ymax = 1000), sample_m = 250),
               "whole number")
})

test_that("a window is rounded outward to whole grid cells, and never past the grid", {
  w <- atlas_snap_window(-2822762, 2844517, -1821967, 1456786)
  expect_equal(unname(w), c(-2825000, 2845000, -1825000, 1460000))
  far <- atlas_snap_window(-9e6, 9e6, -9e6, 9e6)
  expect_equal(far, ATLAS_GRID_EXTENT[c("xmin", "xmax", "ymin", "ymax")])
})

# ---- HTTP, politely -------------------------------------------------------

# A stand-in server: answers with the statuses given, in turn, writing body
# into the file each time.
scripted_http <- function(statuses, body = "II*\001payload") {
  calls <- 0L
  f <- function(url, dest) {
    calls <<- calls + 1L
    status <- statuses[[min(calls, length(statuses))]]
    writeBin(charToRaw(if (is.function(body)) body(calls) else body), dest)
    status
  }
  list(http = f, calls = function() calls)
}

tiff_body <- function(...) rawToChar(as.raw(c(0x49, 0x49, 0x2a, 0x2e)))

test_that("a busy server is retried, and the file appears only once it is whole", {
  dest <- tempfile(fileext = ".tif")
  server <- scripted_http(c(503L, 502L, 200L), body = tiff_body)
  atlas_fetch_file("https://example.test/x", dest, http = server$http,
                   check = function(p) TRUE, wait = 0)
  expect_equal(server$calls(), 3L)
  expect_true(file.exists(dest))
  expect_false(file.exists(paste0(dest, ".part")))
})

test_that("a refusal is not retried, and leaves no file behind", {
  dest <- tempfile(fileext = ".tif")
  server <- scripted_http(404L)
  expect_error(atlas_fetch_file("https://example.test/x", dest, http = server$http, wait = 0),
               "HTTP 404")
  expect_equal(server$calls(), 1L)
  expect_false(file.exists(dest))
  expect_false(file.exists(paste0(dest, ".part")))
})

test_that("an error reported as a 200 with a JSON body is retried, then given up", {
  dest <- tempfile(fileext = ".tif")
  server <- scripted_http(200L, body = '{"error":{"code":500,"message":"Error exporting image"}}')
  expect_error(atlas_fetch_file("https://example.test/x", dest, http = server$http,
                                check = atlas_is_tiff, tries = 3L, wait = 0),
               "gave up after 3 tries")
  expect_equal(server$calls(), 3L)
  expect_false(file.exists(dest))
})

test_that("a dropped connection counts as a failure to retry", {
  dest <- tempfile()
  calls <- 0L
  flaky <- function(url, dest) {
    calls <<- calls + 1L
    if (calls == 1L) stop("Recv failure: Connection was reset")
    writeLines("ok", dest)
    200L
  }
  atlas_fetch_file("https://example.test/x", dest, http = flaky, wait = 0)
  expect_equal(calls, 2L)
  expect_equal(readLines(dest), "ok")
})

test_that("TIFF and zip files are told from error pages by their first bytes", {
  tif <- tempfile()
  writeBin(as.raw(c(0x49, 0x49, 0x2a, 0x00, 1, 2)), tif)
  big <- tempfile()
  writeBin(as.raw(c(0x49, 0x49, 0x2b, 0x00, 1, 2)), big)
  json <- tempfile()
  writeLines('{"error":{}}', json)
  zip <- tempfile()
  writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04, 0)), zip)
  expect_true(atlas_is_tiff(tif))
  expect_true(atlas_is_tiff(big))
  expect_false(atlas_is_tiff(json))
  expect_true(atlas_is_zip(zip))
  expect_false(atlas_is_zip(json))
})

# ---- reading BIGMAP -------------------------------------------------------

# A stand-in ImageServer: every species is a raster whose value at a 250 m
# sample is its column number plus a per-species offset.
fake_bigmap <- function(offsets) {
  requested <- character()
  f <- function(url, dest) {
    query <- strsplit(sub("^[^?]*[?]", "", url), "&", fixed = TRUE)[[1]]
    params <- stats::setNames(vapply(query, function(q) utils::URLdecode(sub("^[^=]*=", "", q)), ""),
                              sub("=.*$", "", query))
    fn <- jsonlite::fromJSON(params[["renderingRule"]])$rasterFunction
    requested <<- c(requested, fn)
    size <- as.integer(strsplit(params[["size"]], ",")[[1]])
    bbox <- as.numeric(strsplit(params[["bbox"]], ",")[[1]])
    r <- terra::rast(ncols = size[[1]], nrows = size[[2]], xmin = bbox[[1]], ymin = bbox[[2]],
                     xmax = bbox[[3]], ymax = bbox[[4]], crs = ATLAS_CRS)
    columns <- terra::colFromCell(r, seq_len(terra::ncell(r)))
    terra::values(r) <- columns + offsets[[fn]]
    terra::writeRaster(r, dest, filetype = "GTiff", overwrite = TRUE)
    200L
  }
  list(http = f, requested = function() requested)
}

test_that("a species is averaged from 250 m samples onto 1 km cells, and reused next time", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("bigmap-", as.integer(stats::runif(1, 1, 1e9))))
  window <- c(xmin = 0, xmax = 4000, ymin = 0, ymax = 2000)
  server <- fake_bigmap(c(SPCD_0202_Pseudotsuga_menziesii = 0))
  got <- atlas_bigmap_fetch_species("SPCD_0202_Pseudotsuga_menziesii", window, dir,
                                    http = server$http, quiet = TRUE)
  out <- terra::rast(got$path)
  expect_equal(terra::res(out), c(1000, 1000))
  expect_equal(as.vector(terra::ext(out)), c(xmin = 0, xmax = 4000, ymin = 0, ymax = 2000))
  # Sample columns 1-4 average to 2.5 in the first cell, 5-8 to 6.5 in the next.
  expect_equal(terra::values(out)[1:4, 1], c(2.5, 6.5, 10.5, 14.5))
  # The tiles are gone; only the 1 km result is kept.
  expect_equal(list.files(dir), "SPCD_0202_Pseudotsuga_menziesii.tif")
  atlas_bigmap_fetch_species("SPCD_0202_Pseudotsuga_menziesii", window, dir,
                             http = server$http, quiet = TRUE)
  expect_length(server$requested(), 1L)
  unlink(dir, recursive = TRUE)
})

# A stand-in for BIGMAP's list of raster functions: one species of every host
# genus except pines and oaks (the test's own), all reading -2.5 so that with
# the column average of 2.5 they come to 0.
other_hosts <- function() {
  genera <- setdiff(ATLAS_HOST_GENERA, c("Pinus", "Quercus", "Notholithocarpus"))
  fns <- c(sprintf("SPCD_%04d_%s_testii", 500L + seq_along(genera), genera),
           "SPCD_0631_Lithocarpus_densiflorus")
  stats::setNames(rep(-2.5, length(fns)), fns)
}

test_that("BIGMAP's sums put each species in its genus, conifers in the conifer band", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("bigmap-", as.integer(stats::runif(1, 1, 1e9))))
  offsets <- c(SPCD_0000_Total = 1000, SPCD_0122_Pinus_ponderosa = 10,
               SPCD_0131_Pinus_taeda = 20, SPCD_0068_Juniperus_virginiana = 30,
               SPCD_0802_Quercus_alba = 40, SPCD_0316_Acer_rubrum = 50, other_hosts())
  server <- fake_bigmap(offsets)
  window <- c(xmin = 0, xmax = 1000, ymin = 0, ymax = 1000)
  sums <- atlas_bigmap_sums(dir, window, http = server$http, quiet = TRUE, functions = names(offsets))
  expect_equal(names(sums), c("total", "conifer", tolower(ATLAS_HOST_GENERA)))
  # One cell, whose samples average to column 2.5 plus the offset.
  v <- terra::values(sums)[1, ]
  expect_equal(v[["total"]], 12.5 + 22.5 + 32.5 + 42.5 + 52.5)
  expect_equal(v[["pinus"]], 12.5 + 22.5)
  expect_equal(v[["conifer"]], 12.5 + 22.5 + 32.5)
  expect_equal(v[["quercus"]], 42.5)
  expect_equal(v[["fagus"]], 0)
  expect_false("SPCD_0000_Total" %in% server$requested())
  # The per-species files go once summed.
  expect_false(dir.exists(file.path(dir, "bigmap-species")))
  unlink(dir, recursive = TRUE)
})

test_that("a BIGMAP without one of the host genera is refused, not built with a hole", {
  dir <- file.path(tempdir(), paste0("bigmap-", as.integer(stats::runif(1, 1, 1e9))))
  functions <- c("SPCD_0122_Pinus_ponderosa", "SPCD_0802_Quercus_alba")
  expect_error(
    atlas_bigmap_sums(dir, c(xmin = 0, xmax = 1000, ymin = 0, ymax = 1000),
                      http = function(url, dest) stop("no network"), quiet = TRUE,
                      functions = functions),
    "missing: .*Picea"
  )
})

# ---- NFI's files ----------------------------------------------------------

NFI_SAMPLE <- paste0("NFI_MODIS250m_2011_kNN_", c(
  "Species_Pice_Mar", "Species_Pice_Gla", "Species_Pice_Spp", "Species_Betu_All",
  "Species_Betu_Pap", "Species_Betu_Spp", "Species_Acer_Rub", "Species_Genc_Spp",
  "SpeciesGroups_Needleleaf_Spp", "SpeciesGroups_Broadleaf_Spp", "SpeciesGroups_Unknown_Spp",
  "Structure_Biomass_TotalLiveAboveGround"
), "_v1.tif")

test_that("an NFI _Spp file is part of its genus, not a total for it", {
  catalog <- atlas_nfi_catalog(NFI_SAMPLE)
  groups <- atlas_nfi_groups(catalog)
  expect_setequal(groups$picea, paste0("NFI_MODIS250m_2011_kNN_Species_Pice_", c("Mar", "Gla", "Spp"), "_v1.tif"))
  # Betu_All is yellow birch, one species among the birches.
  expect_setequal(groups$betula, paste0("NFI_MODIS250m_2011_kNN_Species_Betu_", c("All", "Pap", "Spp"), "_v1.tif"))
})

test_that("only host genera and the two identified groups are needed from NFI", {
  needed <- atlas_nfi_needed(atlas_nfi_catalog(NFI_SAMPLE))$file
  expect_false(any(grepl("Acer_Rub|Genc_Spp|Unknown|Structure", needed)))
  expect_true(all(c("NFI_MODIS250m_2011_kNN_SpeciesGroups_Needleleaf_Spp_v1.tif",
                    "NFI_MODIS250m_2011_kNN_SpeciesGroups_Broadleaf_Spp_v1.tif") %in% needed))
})

test_that("genera NFI does not map are empty groups, so they read 0 in Canada", {
  groups <- atlas_nfi_groups(atlas_nfi_catalog(NFI_SAMPLE))
  expect_length(groups$castanea, 0L)
  expect_length(groups$notholithocarpus, 0L)
  expect_error(atlas_nfi_groups(atlas_nfi_catalog(NFI_SAMPLE[1:3])), "needleleaf or broadleaf")
})

test_that("NFI's listing is read from its directory page", {
  page <- paste0(
    '<a href="?C=N;O=D">Name</a><a href="NFI_MODIS250m_2011_kNN_Species_Pice_Mar_v1.tif">x</a>',
    '<a href="NFI_MODIS250m_2011_kNN_Species_Pice_Mar_v1.tif.aux.xml">x</a>',
    '<a href="NFI_MODIS250m_2011_kNN_SpeciesGroups_Broadleaf_Spp_v1.tif">x</a>'
  )
  http <- function(url, dest) {
    expect_equal(url, paste0(ATLAS_NFI_URL, "/"))
    writeLines(page, dest)
    200L
  }
  expect_equal(atlas_nfi_list(http), c("NFI_MODIS250m_2011_kNN_Species_Pice_Mar_v1.tif",
                                       "NFI_MODIS250m_2011_kNN_SpeciesGroups_Broadleaf_Spp_v1.tif"))
})

test_that("NFI's sums add a genus's species and its _Spp, over identified trees", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("nfi-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(file.path(dir, "nfi"), recursive = TRUE)
  # A small square of NFI's own Lambert grid in northern Ontario, every pixel
  # the same, so the averages are known.
  lcc <- "+proj=lcc +lat_0=0 +lon_0=-95 +lat_1=49 +lat_2=77 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs"
  values <- c(Species_Pice_Mar = 30, Species_Pice_Spp = 10, Species_Betu_Pap = 15,
              SpeciesGroups_Needleleaf_Spp = 60, SpeciesGroups_Broadleaf_Spp = 20)
  files <- paste0("NFI_MODIS250m_2011_kNN_", names(values), "_v1.tif")
  for (i in seq_along(values)) {
    r <- terra::rast(xmin = 0, xmax = 20000, ymin = 5700000, ymax = 5720000,
                     resolution = 250, crs = lcc)
    terra::values(r) <- values[[i]]
    terra::writeRaster(r, file.path(dir, "nfi", files[[i]]), overwrite = TRUE)
  }
  refuse <- function(url, dest) stop("no network in tests")
  sums <- atlas_nfi_sums(dir, http = refuse, quiet = TRUE, files = files)
  inside <- terra::values(sums)[stats::complete.cases(terra::values(sums)), , drop = FALSE]
  expect_gt(nrow(inside), 0L)
  expect_equal(unique(round(inside[, "picea"], 4)), 40)
  expect_equal(unique(round(inside[, "total"], 4)), 80)
  expect_equal(unique(round(inside[, "conifer"], 4)), 60)
  expect_equal(unique(round(inside[, "castanea"], 4)), 0)
  shares <- atlas_host_shares(sums)
  expect_equal(unique(round(stats::na.omit(terra::values(shares[["host_picea"]]))[, 1], 4)), 0.5)
  unlink(dir, recursive = TRUE)
})

# ---- the arithmetic ---------------------------------------------------------

test_that("a genus's share is its part of the cell's trees", {
  expect_equal(atlas_host_share(c(25, 0, 10), c(100, 50, 10)), c(0.25, 0, 1))
})

test_that("a cell with no trees has a share of 0, not a missing value", {
  expect_equal(atlas_host_share(0, 0), 0)
  expect_equal(atlas_host_share(c(0, 0), c(0, 0)), c(0, 0))
})

test_that("a cell the inventory does not describe stays missing", {
  expect_true(is.na(atlas_host_share(5, NA)))
})

test_that("a share is kept between 0 and 1 even when samples overshoot", {
  expect_equal(atlas_host_share(12, 10), 1)
})

test_that("shares are named for their band and need a total", {
  shares <- atlas_host_shares(list(total = c(10, 0), conifer = c(4, 0), pinus = c(2, 0)))
  expect_equal(names(shares), c("host_conifer", "host_pinus"))
  expect_equal(shares$host_pinus, c(0.2, 0))
  expect_error(atlas_host_shares(list(pinus = 1)), "total")
})

test_that("group sums add every member, and an empty group is 0 where values exist", {
  values <- list(a = c(1, 2, NA), b = c(10, 20, NA), c = c(100, 200, NA))
  sums <- atlas_group_sums(values, list(ab = c("a", "b"), c = "c", none = character()))
  expect_equal(sums$ab, c(11, 22, NA))
  expect_equal(sums$c, c(100, 200, NA))
  expect_equal(sums$none, c(0, 0, NA))
  expect_error(atlas_group_sums(values, list(x = "zzz")), "no values for: zzz")
})

test_that("inside the lower 48 missing becomes 0, and outside everything is missing", {
  x <- c(0.4, NA, 0.2, NA)
  inside <- c(TRUE, TRUE, FALSE, FALSE)
  expect_equal(atlas_inventory_fill(x, inside), c(0.4, 0, NA, NA))
})

test_that("the inventory fill works on rasters too", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 1, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 1)
  terra::values(x) <- c(0.4, NA, 0.2, NA)
  inside <- terra::rast(x)
  terra::values(inside) <- c(TRUE, TRUE, FALSE, FALSE)
  expect_equal(terra::values(atlas_inventory_fill(x, inside))[, 1], c(0.4, 0, NA, NA))
})

test_that("each cell comes from the inventory that covers it, the US where its centre is", {
  us <- c(0.9, NA, 0.1, 0.3, 0.7, NA)
  canada <- c(NA, 0.5, 0.8, 0.8, NA, NA)
  first <- c(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE)
  expect_equal(atlas_mosaic_hosts(us, canada, first), c(0.9, 0.5, 0.1, 0.8, 0.7, NA))
})

test_that("the mosaic works band by band on rasters", {
  skip_if_not_installed("terra")
  template <- terra::rast(nrows = 1, ncols = 3, xmin = 0, xmax = 3, ymin = 0, ymax = 1, nlyrs = 2)
  us <- terra::rast(template)
  terra::values(us) <- cbind(c(0.9, NA, 0.1), c(0.8, NA, 0.2))
  names(us) <- c("host_conifer", "host_pinus")
  canada <- terra::rast(template)
  terra::values(canada) <- cbind(c(NA, 0.5, 0.6), c(NA, 0.4, 0.3))
  first <- terra::rast(template[[1]])
  terra::values(first) <- c(TRUE, FALSE, FALSE)
  out <- atlas_mosaic_hosts(us, canada, first)
  expect_equal(names(out), c("host_conifer", "host_pinus"))
  expect_equal(unname(terra::values(out)), cbind(c(0.9, 0.5, 0.6), c(0.8, 0.4, 0.3)))
})

# ---- the two together, on the grid -------------------------------------------

# Sums on 1 km cells, every band 0 except the given ones (a value, or one per
# cell from the top left).
fake_sums <- function(xmin, xmax, ymin, ymax, bands) {
  r <- terra::rast(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
                   resolution = 1000, crs = ATLAS_CRS, nlyrs = 2L + length(ATLAS_HOST_GENERA))
  names(r) <- c("total", "conifer", tolower(ATLAS_HOST_GENERA))
  values <- matrix(0, terra::ncell(r), terra::nlyr(r), dimnames = list(NULL, names(r)))
  for (b in names(bands)) values[, b] <- bands[[b]]
  terra::values(r) <- values
  r
}

test_that("the combined layer keeps the lower 48 and Canada, and nothing else", {
  skip_if_not_installed("terra")
  # The US is the square 0-10 km; BIGMAP's window runs to 20 km, as a real
  # window runs past the border into Mexico or the sea, where it reads 0.
  us_sums <- fake_sums(0, 20000, 0, 10000, list(total = 100, pinus = 25, conifer = 25))
  # Canada sits above, 10-20 km north, with its own numbers.
  ca_sums <- fake_sums(0, 20000, 10000, 20000, list(total = 80, picea = 40, conifer = 60))
  states <- terra::vect("POLYGON ((0 0, 10000 0, 10000 10000, 0 10000, 0 0))", crs = ATLAS_CRS)
  out <- atlas_combine_hosts(us_sums, ca_sums, states, res = 1000)
  expect_equal(names(out), ATLAS_HOST_BANDS)

  at <- function(x, y) unlist(terra::extract(out, cbind(x, y))[1, ])
  us_cell <- at(5500, 5500)
  expect_equal(us_cell[["host_pinus"]], 0.25)
  expect_equal(us_cell[["host_picea"]], 0)
  canada_cell <- at(5500, 15500)
  expect_equal(canada_cell[["host_picea"]], 0.5)
  expect_equal(canada_cell[["host_conifer"]], 0.75)
  # BIGMAP reads 0 past the border, but no inventory speaks for that ground.
  expect_true(all(is.na(at(15500, 5500))))
})

test_that("a coarse cell's share is weighted by how many trees each part holds", {
  skip_if_not_installed("terra")
  # Five 1 km columns: one dense stand of pine, four sparse stands of oak.
  total <- rep(c(90, 10, 10, 10, 10), times = 5)
  pinus <- rep(c(90, 0, 0, 0, 0), times = 5)
  us_sums <- fake_sums(0, 5000, 0, 5000, list(total = total, pinus = pinus, quercus = total - pinus))
  ca_sums <- fake_sums(0, 5000, 5000, 10000, list(total = 1))
  states <- terra::vect("POLYGON ((0 0, 5000 0, 5000 5000, 0 5000, 0 0))", crs = ATLAS_CRS)
  out <- atlas_combine_hosts(us_sums, ca_sums, states, res = 5000)
  cell <- unlist(terra::extract(out, cbind(2500, 2500))[1, ])
  # 90 of 130 is pine; the mean of the five columns' shares would say 0.2.
  expect_equal(cell[["host_pinus"]], 90 / 130)
  expect_equal(cell[["host_quercus"]], 40 / 130)
})

test_that("a border cell goes to the country its centre is in", {
  skip_if_not_installed("terra")
  us_sums <- fake_sums(0, 3000, 0, 3000, list(total = 10, pinus = 10))
  ca_sums <- fake_sums(0, 3000, 0, 3000, list(total = 10, picea = 10))
  # The border runs across the middle row, below its centres: the lower 48
  # touch that row, but its centres are Canadian.
  states <- terra::vect("POLYGON ((0 0, 3000 0, 3000 1400, 0 1400, 0 0))", crs = ATLAS_CRS)
  out <- atlas_combine_hosts(us_sums, ca_sums, states, res = 1000)
  # Both inventories reach every cell here; the centre decides.
  expect_equal(terra::extract(out, cbind(1500, 500))$host_pinus, 1)
  expect_equal(terra::extract(out, cbind(1500, 500))$host_picea, 0)
  expect_equal(terra::extract(out, cbind(1500, 1500))$host_picea, 1)
  expect_equal(terra::extract(out, cbind(1500, 1500))$host_pinus, 0)
  expect_equal(terra::extract(out, cbind(1500, 2500))$host_picea, 1)
})

test_that("a cell the lower 48 only touch is still American when Canada has nothing there", {
  skip_if_not_installed("terra")
  us_sums <- fake_sums(0, 3000, 0, 3000, list(total = 10, pinus = 10))
  ca_sums <- fake_sums(0, 3000, 5000, 6000, list(total = 10, picea = 10))
  # A coastline: the polygon clips the corner of the middle row only.
  states <- terra::vect("POLYGON ((0 0, 3000 0, 3000 1400, 0 1400, 0 0))", crs = ATLAS_CRS)
  out <- atlas_combine_hosts(us_sums, ca_sums, states, res = 1000)
  expect_equal(terra::extract(out, cbind(1500, 1500))$host_pinus, 1)
  expect_true(is.na(terra::extract(out, cbind(1500, 2500))$host_pinus))
})

test_that("on rasters too, no trees is a share of 0 and no inventory stays missing", {
  skip_if_not_installed("terra")
  part <- terra::rast(nrows = 1, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 1)
  total <- terra::rast(part)
  terra::values(part) <- c(5, 0, 12, 3)
  terra::values(total) <- c(10, 0, 10, NA)
  expect_equal(terra::values(atlas_host_share(part, total))[, 1], c(0.5, 0, 1, NA))
})

test_that("a treeless cell in the lower 48 reads 0 for every host, not missing", {
  skip_if_not_installed("terra")
  us_sums <- fake_sums(0, 2000, 0, 1000, list(total = c(50, 0), pinus = c(50, 0), conifer = c(50, 0)))
  ca_sums <- fake_sums(0, 2000, 5000, 6000, list(total = 1))
  states <- terra::vect("POLYGON ((0 0, 2000 0, 2000 1000, 0 1000, 0 0))", crs = ATLAS_CRS)
  out <- atlas_combine_hosts(us_sums, ca_sums, states, res = 1000)
  prairie <- unlist(terra::extract(out, cbind(1500, 500))[1, ])
  expect_true(all(prairie == 0))
  expect_equal(unlist(terra::extract(out, cbind(500, 500))[1, ])[["host_pinus"]], 1)
})

# ---- the decay hosts, a second set beside the host layer ----------------

test_that("production's host builder still asks for exactly the same genera, bands and cache files", {
  set <- atlas_host_set("hosts")
  expect_equal(set$genera, c(
    "Pinus", "Quercus", "Picea", "Abies", "Pseudotsuga", "Tsuga", "Betula",
    "Populus", "Fagus", "Larix", "Castanea", "Notholithocarpus", "Carya",
    "Alnus", "Salix", "Tilia", "Carpinus", "Ostrya", "Arbutus"
  ))
  expect_identical(set$nfi_codes, ATLAS_NFI_GENERA)
  expect_true(set$totals)
  expect_equal(atlas_host_set_files(set), c("bigmap-1km.tif", "bigmap-species", "nfi-1km.tif", "nfi"))
  expect_equal(atlas_host_set_bands(set), ATLAS_HOST_BANDS)
  expect_equal(ATLAS_HOST_BANDS, c("host_conifer", paste0("host_", tolower(set$genera))))
  # The functions' defaults are production's.
  for (fn in c("atlas_bigmap_sums", "atlas_nfi_sums", "atlas_build_hosts")) {
    expect_identical(eval(formals(get(fn))$set), set, info = fn)
  }
  expect_equal(names(atlas_bigmap_groups(atlas_bigmap_species(BIGMAP_SAMPLE))),
               c("total", "conifer", tolower(set$genera)))

  # Built end to end on stand-ins: the same cache files, read by production's
  # set, and the same bands out.
  skip_if_not_installed("terra")
  seen <- list()
  sums <- function(bands, ymin, ymax) {
    r <- terra::rast(xmin = 0, xmax = 10000, ymin = ymin, ymax = ymax, resolution = 1000,
                     crs = ATLAS_CRS, nlyrs = length(bands))
    names(r) <- bands
    terra::values(r) <- 1
    r
  }
  testthat::local_mocked_bindings(
    atlas_conus_states = function(dir, http) {
      terra::vect("POLYGON ((0 0, 10000 0, 10000 10000, 0 10000, 0 0))", crs = ATLAS_CRS)
    },
    atlas_bigmap_sums = function(dir, window, http, quiet, set) {
      seen$bigmap <<- set
      sums(c("total", "conifer", tolower(ATLAS_HOST_GENERA)), 0, 10000)
    },
    atlas_nfi_sums = function(dir, http, quiet, set) {
      seen$nfi <<- set
      sums(c("total", "conifer", tolower(ATLAS_HOST_GENERA)), 10000, 20000)
    }
  )
  built <- atlas_build_hosts(tempdir(), "draft", http = function(url, dest) stop("no network"),
                             quiet = TRUE)
  expect_identical(seen$bigmap, set)
  expect_identical(seen$nfi, set)
  expect_equal(names(built), ATLAS_HOST_BANDS)
})

test_that("a second host set can never share production's files, nor name raw/hosts itself", {
  sets <- atlas_host_sets()
  expect_length(intersect(atlas_host_set_files(sets$hostsdecay), atlas_host_set_files(sets$hosts)), 0L)
  clash <- sets
  clash$hostsdecay$species_dir <- "bigmap-species"
  expect_error(atlas_host_set("hostsdecay", clash), "share production's files: bigmap-species")
  clash <- sets
  clash$hostsdecay$bigmap <- "bigmap-1km.tif"
  expect_error(atlas_host_set("hostsdecay", clash), "share production's files")
  empty <- sets
  empty$hostsdecay$species_dir <- ""
  expect_error(atlas_host_set("hostsdecay", empty), "plainly")
  up <- sets
  up$hostsdecay$species_dir <- "../hosts"
  expect_error(atlas_host_set("hostsdecay", up), "plainly")
  expect_error(atlas_host_set("nothing"), "unknown host set")
})

test_that("the decay-host layer reads only its own genera, into its own files, and leaves production's caches alone", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("decay-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(file.path(dir, "bigmap-species"), recursive = TRUE)
  # Production's caches, and a species file of an interrupted production read.
  sentinels <- file.path(dir, c("bigmap-1km.tif", "nfi-1km.tif",
                                "bigmap-species/SPCD_0122_Pinus_ponderosa.tif"))
  for (f in sentinels) writeBin(as.raw(1:64), f)
  before <- tools::md5sum(sentinels)

  set <- atlas_host_set("hostsdecay")
  decay_fns <- sprintf("SPCD_%04d_%s_testii", 300L + seq_along(set$genera), set$genera)
  offsets <- c(stats::setNames(rep(-2.5, length(decay_fns)), decay_fns),
               SPCD_0316_Acer_rubrum = 7.5, SPCD_0122_Pinus_ponderosa = 10,
               SPCD_0802_Quercus_alba = 40)
  server <- fake_bigmap(offsets)
  window <- c(xmin = 0, xmax = 1000, ymin = 0, ymax = 1000)
  sums <- atlas_bigmap_sums(dir, window, http = server$http, quiet = TRUE,
                            functions = names(offsets), set = set)
  # Only the decay genera are read: the total is production's.
  expect_setequal(server$requested(), c(decay_fns, "SPCD_0316_Acer_rubrum"))
  expect_equal(names(sums), tolower(set$genera))
  # Two maples: 0 for the stand-in, 10 for red maple (column 2.5 plus 7.5).
  expect_equal(unname(terra::values(sums)[1, "acer"]), 10)
  expect_equal(unname(terra::values(sums)[1, "robinia"]), 0)
  expect_true(file.exists(file.path(dir, "bigmap-decay-1km.tif")))
  # Its own species folder is gone; production's are untouched.
  expect_false(dir.exists(file.path(dir, "bigmap-species-decay")))
  expect_true(all(file.exists(sentinels)))
  expect_equal(tools::md5sum(sentinels), before)
  unlink(dir, recursive = TRUE)
})

test_that("the decay-host layer needs only its genera from NFI, and a genus NFI does not map is 0 in Canada", {
  files <- paste0("NFI_MODIS250m_2011_kNN_", c(
    "Species_Acer_Rub", "Species_Acer_Spp", "Species_Thuj_Occ", "Species_Pice_Mar",
    "SpeciesGroups_Needleleaf_Spp", "SpeciesGroups_Broadleaf_Spp"
  ), "_v1.tif")
  set <- atlas_host_set("hostsdecay")
  catalog <- atlas_nfi_needed(atlas_nfi_catalog(files, set$nfi_codes), groups = set$totals)
  expect_setequal(catalog$file, files[1:3])
  groups <- atlas_nfi_groups(catalog, set$genera, totals = set$totals)
  expect_equal(names(groups), tolower(set$genera))
  expect_setequal(groups$acer, files[1:2])
  expect_length(groups$liriodendron, 0L)
  # Production still reads its genera and both groups, and no maple.
  production <- atlas_nfi_needed(atlas_nfi_catalog(files))
  expect_setequal(production$file, files[4:6])

  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("nfi-decay-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(file.path(dir, "nfi-decay"), recursive = TRUE)
  lcc <- "+proj=lcc +lat_0=0 +lon_0=-95 +lat_1=49 +lat_2=77 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs"
  values <- c(Species_Acer_Rub = 30, Species_Acer_Spp = 10, Species_Thuj_Occ = 5)
  for (i in seq_along(values)) {
    r <- terra::rast(xmin = 0, xmax = 20000, ymin = 5700000, ymax = 5720000, resolution = 250, crs = lcc)
    terra::values(r) <- values[[i]]
    terra::writeRaster(r, file.path(dir, "nfi-decay", files[[i]]), overwrite = TRUE)
  }
  sums <- atlas_nfi_sums(dir, http = function(url, dest) stop("no network"), quiet = TRUE,
                         files = files, set = set)
  expect_equal(names(sums), tolower(set$genera))
  inside <- terra::values(sums)[stats::complete.cases(terra::values(sums)), , drop = FALSE]
  expect_gt(nrow(inside), 0L)
  expect_equal(unique(round(inside[, "acer"], 4)), 40)
  expect_equal(unique(round(inside[, "liriodendron"], 4)), 0)
  expect_true(file.exists(file.path(dir, "nfi-decay-1km.tif")))
  expect_false(file.exists(file.path(dir, "nfi-1km.tif")))
  unlink(dir, recursive = TRUE)
})

test_that("each decay genus is a share of the host layer's own tree total", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("decay-build-", as.integer(stats::runif(1, 1, 1e9))))
  hosts_dir <- file.path(dir, "hosts")
  dir.create(hosts_dir, recursive = TRUE)
  set <- atlas_host_set("hostsdecay")
  write_sums <- function(file, bands, ymin, ymax) {
    r <- terra::rast(xmin = 0, xmax = 10000, ymin = ymin, ymax = ymax, resolution = 1000,
                     crs = ATLAS_CRS, nlyrs = length(bands))
    names(r) <- names(bands)
    terra::values(r) <- matrix(unlist(bands), terra::ncell(r), length(bands), byrow = TRUE)
    terra::writeRaster(r, file.path(hosts_dir, file))
  }
  production_genera <- as.list(stats::setNames(rep(1, length(ATLAS_HOST_GENERA)),
                                               tolower(ATLAS_HOST_GENERA)))
  # Production's caches: the United States below 10 km, Canada above.
  write_sums("bigmap-1km.tif", c(list(total = 100, conifer = 10), production_genera), 0, 10000)
  write_sums("nfi-1km.tif", c(list(total = 80, conifer = 40), production_genera), 10000, 20000)
  decay <- stats::setNames(as.list(rep(0, length(set$genera))), tolower(set$genera))
  us <- decay
  us$acer <- 25
  us$liriodendron <- 10
  ca <- decay
  ca$acer <- 40
  write_sums("bigmap-decay-1km.tif", us, 0, 10000)
  write_sums("nfi-decay-1km.tif", ca, 10000, 20000)
  before <- tools::md5sum(file.path(hosts_dir, c("bigmap-1km.tif", "nfi-1km.tif")))
  testthat::local_mocked_bindings(atlas_conus_states = function(dir, http) {
    terra::vect("POLYGON ((0 0, 10000 0, 10000 10000, 0 10000, 0 0))", crs = ATLAS_CRS)
  })
  built <- atlas_build_hosts(dir, "draft", http = function(url, dest) stop("no network"),
                             quiet = TRUE, set = set)
  expect_equal(names(built), ATLAS_HOST_DECAY_BANDS)
  at <- function(x, y) unlist(terra::extract(built, cbind(x, y))[1, ])
  # 25 of the United States' 100, 40 of Canada's 80.
  expect_equal(at(2500, 2500)[["host_acer"]], 0.25)
  expect_equal(at(2500, 2500)[["host_liriodendron"]], 0.1)
  expect_equal(at(2500, 12500)[["host_acer"]], 0.5)
  expect_equal(at(2500, 12500)[["host_liriodendron"]], 0)
  expect_equal(tools::md5sum(file.path(hosts_dir, c("bigmap-1km.tif", "nfi-1km.tif"))), before)
  unlink(dir, recursive = TRUE)
})

test_that("the decay-host layer refuses before reading anything when production's totals are not built", {
  dir <- file.path(tempdir(), paste0("decay-empty-", as.integer(stats::runif(1, 1, 1e9))))
  asked <- character()
  refuse <- function(url, dest) {
    asked <<- c(asked, url)
    stop("no network")
  }
  expect_error(atlas_build_hosts(dir, "draft", http = refuse, quiet = TRUE,
                                 set = atlas_host_set("hostsdecay")),
               "build hosts first")
  expect_length(asked, 0L)
  expect_equal(list.files(file.path(dir, "hosts")), character())
  unlink(dir, recursive = TRUE)
})

# ---- raw caches are whole or absent ---------------------------------------------

test_that("a cache write that fails leaves no cache file for the next run to trust", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("half-", as.integer(stats::runif(1, 1, 1e9))))
  offsets <- c(SPCD_0122_Pinus_ponderosa = 10, SPCD_0802_Quercus_alba = 40, other_hosts())
  server <- fake_bigmap(offsets)
  window <- c(xmin = 0, xmax = 1000, ymin = 0, ymax = 1000)
  # Species files write; the sums die halfway through their file, as an
  # out-of-memory write did on 2026-09-30, leaving an 8-byte stub.
  real_write <- terra::writeRaster
  testthat::local_mocked_bindings(
    writeRaster = function(x, filename, ...) {
      if (grepl("bigmap-1km", filename)) {
        writeBin(as.raw(1:8), filename)
        stop("std::bad_alloc")
      }
      real_write(x, filename, ...)
    },
    .package = "terra"
  )
  expect_error(atlas_bigmap_sums(dir, window, http = server$http, quiet = TRUE,
                                 functions = names(offsets), keep_species = TRUE),
               "bad_alloc")
  expect_false(file.exists(file.path(dir, "bigmap-1km.tif")))
  expect_false(file.exists(file.path(dir, "bigmap-1km.tif.part")))
  # The species files that did finish are whole and kept for the next run.
  expect_true(file.exists(file.path(dir, "bigmap-species", "SPCD_0122_Pinus_ponderosa.tif")))
  expect_length(list.files(dir, pattern = "[.]part$", recursive = TRUE), 0L)

  # The same guard for every raster cache: NFI's sums and the NALCMS,
  # Copernicus and water-balance caches all write through it.
  r <- terra::rast(nrows = 2, ncols = 2)
  terra::values(r) <- 1:4
  cached <- file.path(dir, "nalcms", "bigmap-1km.tif")
  expect_error(atlas_write_cached(r, cached), "bad_alloc")
  expect_false(file.exists(cached))
  expect_false(file.exists(paste0(cached, ".part")))
  unlink(dir, recursive = TRUE)
})

test_that("a leftover .part is never read as the cache, and the next write replaces it", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("part-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(dir, recursive = TRUE)
  writeBin(as.raw(1:8), file.path(dir, "bigmap-1km.tif.part"))
  offsets <- c(SPCD_0122_Pinus_ponderosa = 10, SPCD_0802_Quercus_alba = 40, other_hosts())
  server <- fake_bigmap(offsets)
  sums <- atlas_bigmap_sums(dir, c(xmin = 0, xmax = 1000, ymin = 0, ymax = 1000),
                            http = server$http, quiet = TRUE, functions = names(offsets))
  expect_true(length(server$requested()) > 0)
  expect_equal(names(sums), c("total", "conifer", tolower(ATLAS_HOST_GENERA)))
  expect_equal(unname(terra::values(sums)[1, "pinus"]), 12.5)
  expect_false(file.exists(file.path(dir, "bigmap-1km.tif.part")))
  unlink(dir, recursive = TRUE)
})

# ---- tree species -------------------------------------------------------------

test_that("the species layer carries every BIGMAP species FIA names past the genus, each its own band", {
  table <- atlas_tree_species()
  expect_equal(nrow(table), 327L)
  named <- table$spcd[!grepl(" spp[.]$", table$scientific_name)]
  expect_setequal(ATLAS_HOST_SPECIES, named)
  bands <- atlas_host_species_bands()
  expect_equal(anyDuplicated(bands), 0L)
  expect_true(all(atlas_is_host_share(bands)))
  # No species band is a genus band under another name.
  expect_length(intersect(bands, c(ATLAS_HOST_BANDS, ATLAS_HOST_DECAY_BANDS)), 0L)
  # A subspecies with a code of its own is a band of its own: black
  # cottonwood is not balsam poplar.
  expect_true(all(c("host_populus_balsamifera", "host_populus_balsamifera_trichocarpa") %in% bands))
  # Oaks are species, not one genus: 48 of them.
  expect_equal(sum(startsWith(bands, "host_quercus_")), 48L)
})

test_that("a species band is named and labelled from FIA's scientific and common names", {
  expect_equal(atlas_species_band("Quercus rubra"), "host_quercus_rubra")
  expect_equal(atlas_species_band("Populus balsamifera ssp. trichocarpa"),
               "host_populus_balsamifera_trichocarpa")
  expect_equal(atlas_species_band("Abies lasiocarpa var. arizonica"), "host_abies_lasiocarpa_arizonica")
  expect_equal(atlas_species_band("Carya carolinae-septentrionalis"),
               "host_carya_carolinae_septentrionalis")
  expect_equal(atlas_label("host_quercus_rubra"), "Northern red oak (Quercus rubra)")
  expect_equal(atlas_label("host_quercus_virginiana"), "Live oak (Quercus virginiana)")
  # A label for every band, and the genus labels are untouched.
  bands <- atlas_host_species_bands()
  expect_false(any(atlas_label(bands) == bands))
  expect_equal(atlas_label("host_quercus"), "Oak")
})

test_that("Canada's species files map to the FIA species they are", {
  table <- atlas_tree_species()
  expect_true(all(ATLAS_NFI_SPECIES %in% table$spcd))
  expect_equal(anyDuplicated(unname(ATLAS_NFI_SPECIES)), 0L)
  rows <- table[match(ATLAS_NFI_SPECIES, table$spcd), ]
  # Each file's four letters are its species' genus, Chamaecyparis included.
  expect_equal(substr(names(ATLAS_NFI_SPECIES), 1, 4), substr(rows$genus, 1, 4))
  name_of <- function(code) table$common_name[table$spcd == ATLAS_NFI_SPECIES[[code]]]
  expect_equal(name_of("Acer_Sac"), "sugar maple")
  expect_equal(name_of("Acer_Sah"), "silver maple")
  expect_equal(name_of("Pinu_Str"), "eastern white pine")
  expect_equal(name_of("Pinu_Mon"), "western white pine")
  expect_equal(name_of("Popu_Tri"), "black cottonwood")
  expect_equal(name_of("Popu_Bal"), "balsam poplar")
})

test_that("the species layer sums each species on its own, keeps its species files, and leaves production's caches alone", {
  skip_if_not_installed("terra")
  dir <- file.path(tempdir(), paste0("species-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(dir, recursive = TRUE)
  sentinels <- file.path(dir, c("bigmap-1km.tif", "nfi-1km.tif"))
  for (f in sentinels) writeBin(as.raw(1:64), f)
  before <- tools::md5sum(sentinels)
  set <- atlas_host_set("hostspecies")
  set$species <- c(833L, 838L, 741L, 747L)
  offsets <- c(SPCD_0833_Quercus_rubra = 10, SPCD_0838_Quercus_virginiana = 20,
               SPCD_0741_Populus_balsamifera = 30, SPCD_0747_Populus_balsamifera = 40,
               SPCD_0800_Quercus_spp. = 50, SPCD_0802_Quercus_alba = 60)
  server <- fake_bigmap(offsets)
  window <- c(xmin = 0, xmax = 1000, ymin = 0, ymax = 1000)
  sums <- atlas_bigmap_sums(dir, window, http = server$http, quiet = TRUE,
                            functions = names(offsets), set = set)
  # Only the set's species are read; the oaks FIA could not name are not a species.
  expect_setequal(server$requested(), names(offsets)[1:4])
  expect_equal(names(sums), c("quercus_rubra", "quercus_virginiana", "populus_balsamifera",
                              "populus_balsamifera_trichocarpa"))
  v <- terra::values(sums)[1, ]
  # One cell: column 2.5 plus each species' own offset, never two summed.
  expect_equal(unname(v), c(12.5, 22.5, 32.5, 42.5))
  # Its species files stay for the next choice of species; production's are untouched.
  expect_equal(length(list.files(file.path(dir, "bigmap-species-all"))), 4L)
  expect_equal(tools::md5sum(sentinels), before)
  # A species BIGMAP stops offering is an error, not a silent zero.
  set$species <- c(833L, 999L)
  unlink(file.path(dir, set$bigmap))
  expect_error(atlas_bigmap_sums(dir, window, http = server$http, quiet = TRUE,
                                 functions = names(offsets), set = set), "SPCD 999")
  unlink(dir, recursive = TRUE)
})

test_that("in Canada a species band is its own NFI file, and trees named only to genus stay out of it", {
  files <- paste0("NFI_MODIS250m_2011_kNN_", c(
    "Species_Quer_Rub", "Species_Quer_Mac", "Species_Quer_Spp", "Species_Popu_Tri",
    "SpeciesGroups_Needleleaf_Spp", "SpeciesGroups_Broadleaf_Spp"
  ), "_v1.tif")
  set <- atlas_host_set("hostspecies")
  set$species <- c(833L, 838L, 747L)
  catalog <- atlas_nfi_needed(atlas_nfi_catalog(files, set$nfi_codes, species_codes = set$nfi_species),
                              groups = set$totals)
  # Bur oak is mapped, but not a species of this set: it is still read only
  # if the set carries it, which the groups decide.
  expect_true(all(c(files[1], files[4]) %in% catalog$file))
  expect_false(files[3] %in% catalog$file)
  groups <- atlas_nfi_groups(catalog, set$genera, totals = set$totals, spcd = set$species)
  expect_equal(names(groups), c("quercus_rubra", "quercus_virginiana", "populus_balsamifera_trichocarpa"))
  expect_equal(groups$quercus_rubra, files[1])
  expect_length(groups$quercus_virginiana, 0L)
  expect_equal(groups$populus_balsamifera_trichocarpa, files[4])
  # The genus sets read as they did: no species code, no species column used.
  production <- atlas_nfi_needed(atlas_nfi_catalog(files))
  expect_true(all(is.na(production$spcd)))
})

test_that("the further host genera include walnut, hackberry, bald cypress, redwoods and incense-cedar", {
  expect_true(all(c("Juglans", "Celtis", "Taxodium", "Sequoia", "Sequoiadendron", "Calocedrus") %in%
                    ATLAS_DECAY_HOST_GENERA))
  expect_equal(ATLAS_NFI_DECAY_GENERA[["Jugl"]], "Juglans")
  # Every one is a genus BIGMAP maps.
  expect_true(all(ATLAS_DECAY_HOST_GENERA %in% atlas_tree_species()$genus))
  for (band in ATLAS_HOST_DECAY_BANDS) {
    expect_true(band %in% names(ATLAS_PREDICTOR_LABELS), label = paste(band, "has a label"))
  }
})
