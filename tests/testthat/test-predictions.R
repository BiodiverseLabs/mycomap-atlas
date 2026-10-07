# Where a species is likely, by state: each map counted by state when drawn,
# the counts combined over the maps that beat their null models, and the
# verdict served beside the records.

# A suitability map on the Atlas grid east and north of Albers' origin (40N,
# 96W), 5 km cells, rising eastward: Iowa in the west of it, Indiana in the
# east.
eastward_map <- function(res = 5000) {
  r <- terra::rast(xmin = 0, xmax = 1e6, ymin = 0, ymax = 1e6, resolution = res, crs = ATLAS_CRS)
  terra::values(r) <- terra::xFromCell(r, seq_len(terra::ncell(r)))
  r
}

# Places found in the east of that map, about Indiana.
eastern_finds <- function(n = 40) {
  set.seed(3)
  data.frame(x = stats::runif(n, 8.2e5, 9.8e5), y = stats::runif(n, 1e5, 4e5))
}

code_at <- function(lat, lng) {
  grid <- atlas_region_grid()
  xy <- atlas_albers(lat, lng)
  grid$codes[terra::extract(grid$ids, xy)[, 1]]
}

test_that("the boundary file outlines every region the checklists know, and only those", {
  skip_if_not_installed("terra")
  outlines <- atlas_read_boundaries("regions")
  expect_setequal(outlines$code, vapply(atlas_region_list(), `[[`, "", "code"))
  for (name in c("regions", "countries", "lakes")) {
    expect_lt(file.size(atlas_boundaries_path(name)), 2e6)
  }
})

test_that("a grid cell belongs to the state its centre falls in, and the sea to none", {
  skip_if_not_installed("terra")
  expect_equal(code_at(39.77, -86.16), "US-IN")   # Indianapolis
  expect_equal(code_at(43.65, -79.38), "CA-ON")   # Toronto
  expect_equal(code_at(19.43, -99.13), "MX-CMX")  # Mexico City
  expect_equal(code_at(18.40, -66.06), "US-PR")   # San Juan
  expect_true(is.na(code_at(25.0, -90.0)))         # Gulf of Mexico
})

test_that("a map is cut where the poorer tenth of the places found sits, and counted by state", {
  skip_if_not_installed("terra")
  map <- eastward_map()
  finds <- eastern_finds()
  counts <- atlas_region_counts(map, finds$x, finds$y)
  values <- terra::extract(map, as.matrix(finds))[, 1]
  expect_equal(counts$threshold, signif(stats::quantile(values, 0.1, names = FALSE), 6))
  expect_equal(counts$presences, length(unique(terra::cellFromXY(map, as.matrix(finds)))))

  rows <- atlas_region_rows(counts)
  expect_true(all(rows$suitable <= rows$reach & rows$reach <= rows$cells))
  indiana <- rows[rows$code == "US-IN", ]
  iowa <- rows[rows$code == "US-IA", ]
  expect_gt(indiana$suitable, 0)
  expect_gt(iowa$reach, 0)
  expect_equal(iowa$suitable, 0L)
  # A state the map does not touch is left out.
  expect_false("US-CA" %in% rows$code)
})

test_that("a map none of whose places falls on it is not counted", {
  skip_if_not_installed("terra")
  expect_null(atlas_region_counts(eastward_map(), x = -3e6, y = -1e6))
})

test_that("a 1 km map is counted on the 5 km cells, as a 5 km one is", {
  skip_if_not_installed("terra")
  finds <- eastern_finds()
  coarse <- atlas_region_rows(atlas_region_counts(eastward_map(5000), finds$x, finds$y))
  fine <- atlas_region_rows(atlas_region_counts(eastward_map(1000), finds$x, finds$y))
  expect_equal(fine$cells, coarse$cells)
  expect_equal(fine$reach, coarse$reach)
})

region_rows <- function() {
  data.frame(
    taxon = c("A", "A", "A", "A", "B"),
    algorithm = c("maxnet", "maxnet", "rf", "xgboost", "maxnet"),
    skill = c("passed", "passed", "passed", "failed", "failed"),
    code = c("US-IN", "US-OH", "US-IN", "US-OH", "US-IN"),
    cells = c(200L, 400L, 200L, 400L, 200L),
    reach = c(200L, 100L, 200L, 400L, 200L),
    suitable = c(100L, 20L, 20L, 400L, 200L),
    stringsAsFactors = FALSE
  )
}

test_that("a species' maps that beat their null models are averaged; failed maps have no say", {
  p <- atlas_region_predictions(region_rows())
  expect_false("B" %in% p$taxon)
  indiana <- p[p$taxon == "A" & p$code == "US-IN", ]
  ohio <- p[p$taxon == "A" & p$code == "US-OH", ]
  expect_equal(indiana$maps, 2L)
  expect_equal(indiana$suitable_share, (100 / 200 + 20 / 200) / 2)
  # The forest does not reach Ohio, so it counts as finding none there; the
  # failed boosted trees, which liked all of Ohio, are ignored.
  expect_equal(ohio$suitable_share, (20 / 400) / 2)
  expect_equal(ohio$reach_share, 100 / 400)
  # The best single map is kept too, for "possible".
  expect_equal(indiana$best_share, 100 / 200)
  expect_equal(ohio$best_share, 20 / 400)
})

test_that("a state is likely at a tenth suitable, beyond reach under a tenth reached, else unlikely", {
  expect_equal(
    atlas_region_verdict(c(1, 1, 0.5, 0.05, NA), c(0.10, 0.099, 0.02, 0.0, NA)),
    c("likely", "unlikely", "unlikely", "beyond reach", "no map")
  )
})

test_that("a state only one map rates a tenth suitable is possible, not likely", {
  # Trametes versicolor in Montana: Maxent 4%, boosted trees 16%, forest 0%.
  expect_equal(atlas_region_verdict(0.47, (0.04 + 0.16 + 0) / 3, 0.16), "possible")
  # When the maps agree it stays likely, and when none reaches a tenth it is not listed.
  expect_equal(atlas_region_verdict(1, 0.30, 0.40), "likely")
  expect_equal(atlas_region_verdict(1, 0.03, 0.08), "unlikely")
  expect_equal(atlas_region_verdict(NA, NA, NA), "no map")
})

test_that("records and predictions combine: likely states join the recorded ones, with verdicts on both", {
  recorded <- data.frame(
    taxon = c("A", "A", "C"), country = c("United States", "Canada", "United States"),
    country_code = c("US", "CA", "US"), region = c("Indiana", "Quebec", "Indiana"),
    code = c("US-IN", "CA-QC", "US-IN"), records = c(5L, 1L, 2L), localities = c(4L, 1L, 2L),
    stringsAsFactors = FALSE
  )
  predictions <- data.frame(taxon = c("A", "A", "A", "A"), code = c("US-IN", "US-OH", "US-MT", "US-WY"),
                            maps = 3L, reach_share = c(1, 1, 0.47, 0.51),
                            suitable_share = c(0.3, 0.2, 0.07, 0.03), best_share = c(0.4, 0.3, 0.16, 0.05),
                            stringsAsFactors = FALSE)
  out <- atlas_region_status(recorded, predictions)
  a <- out[out$taxon == "A", ]
  # Montana is listed as possible (one map); Wyoming, with no map at a tenth, is not.
  expect_setequal(a$code, c("US-IN", "CA-QC", "US-OH", "US-MT"))
  expect_equal(a$model[a$code == "US-MT"], "possible")
  expect_equal(a$best_share[a$code == "US-MT"], 0.16)
  expect_equal(a$model[a$code == "US-IN"], "likely")
  expect_equal(a$model[a$code == "CA-QC"], "beyond reach")
  ohio <- a[a$code == "US-OH", ]
  expect_equal(ohio$records, 0L)
  expect_equal(ohio$region, "Ohio")
  expect_equal(ohio$country, "United States")
  # A species with no counted map says so, rather than "unlikely".
  expect_equal(out$model[out$taxon == "C"], "no map")
})

test_that("a fit counts its map by state from its own detection sites", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    fit <- atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                           fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                           buffer_km = 300, quiet = TRUE, nulls = 0, tune = FALSE)
    metrics <- jsonlite::fromJSON(atlas_model_path("Eastern fungus", "draft", ".json", "maxnet"),
                                  simplifyVector = FALSE)
    expect_equal(metrics$regions$from, "detection sites")
    rows <- atlas_region_rows(metrics$regions)
    expect_gt(nrow(rows), 0)
    expect_true(all(rows$suitable <= rows$reach & rows$reach <= rows$cells))
  })
})

test_that("stored maps are counted afterwards from their rasters and the public collection cells", {
  skip_if_not_installed("terra")
  with_data_dir({
    dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(eastward_map(), atlas_model_path("Eastern fungus", "draft", ".tif", "maxnet"))
    atlas_write_json(list(taxon = "Eastern fungus", skill = "passed"),
                     atlas_model_path("Eastern fungus", "draft", ".json", "maxnet"))
    finds <- eastern_finds()
    # Collection cells in degrees, as the release publishes them.
    lonlat <- terra::project(terra::vect(as.matrix(finds), crs = ATLAS_CRS), "EPSG:4326")
    cells <- data.frame(taxon = "Eastern fungus", lat = terra::crds(lonlat)[, 2],
                        lng = terra::crds(lonlat)[, 1], records = 1L)
    atlas_write_tsv_gz(cells, atlas_public_cells_path())

    atlas_count_regions(quiet = TRUE)
    metrics <- jsonlite::fromJSON(atlas_model_path("Eastern fungus", "draft", ".json", "maxnet"),
                                  simplifyVector = FALSE)
    expect_equal(metrics$regions$from, "collection cells")
    expect_true("US-IN" %in% atlas_region_rows(metrics$regions)$code)
    # The rest of the metrics are kept.
    expect_equal(metrics$skill, "passed")
  })
})

test_that("the model index keeps every model's state counts for the API", {
  with_data_dir({
    dir.create(atlas_model_dir("draft", "rf"), recursive = TRUE, showWarnings = FALSE)
    atlas_write_json(list(taxon = "A", skill = "passed", built_at = "2026-10-06T00:00:00Z",
                          regions = list(threshold = 0.4, presences = 10,
                                         cells = list(`US-IN` = c(200, 150, 80)))),
                     atlas_model_path("A", "draft", ".json", "rf"))
    cache <- new.env(parent = emptyenv())
    atlas_model_index("draft", cache)
    rows <- atlas_model_region_rows(cache)
    expect_equal(rows$algorithm, "rf")
    expect_equal(rows$code, "US-IN")
    expect_equal(c(rows$cells, rows$reach, rows$suitable), c(200L, 150L, 80L))
  })
})

# ---- through the API --------------------------------------------------------

prediction_api <- function() test_api(c(ATLAS_PUBLIC_ORIGIN = "https://atlas.example.org"))

# A pull with records in Indiana, Quebec and Puerto Rico, and two maps that
# beat their null models: both like Indiana, one likes Ohio.
with_predicted_pull <- function(code) {
  with_data_dir({
    occurrences <- data.frame(
      id = as.character(1:3), scientific_name = "Trametes versicolor",
      latitude = c("39.7700", "46.8100", "18.2000"), longitude = c("-86.1600", "-71.2100", "-66.5000"),
      state = c("Indiana", "Quebec", "Puerto Rico"), country = c("US", "CA", "PR"),
      stringsAsFactors = FALSE
    )
    stamp <- "20260101T000000Z"
    file <- paste0("occurrences-", stamp, ".tsv.gz")
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(stamp = stamp, file = file, records = 3), atlas_path("occurrences", "latest.json"))
    model <- function(algorithm, cells) {
      dir.create(atlas_model_dir("draft", algorithm), recursive = TRUE, showWarnings = FALSE)
      atlas_write_json(list(taxon = "Trametes versicolor", skill = "passed", built_at = "2026-10-06T00:00:00Z",
                            regions = list(threshold = 0.4, presences = 3, cells = cells)),
                       atlas_model_path("Trametes versicolor", "draft", ".json", algorithm))
    }
    model("maxnet", list(`US-IN` = c(236, 236, 200), `US-OH` = c(300, 300, 150), `US-NE` = c(500, 100, 0),
                         `US-IA` = c(400, 400, 60)))
    model("rf", list(`US-IN` = c(236, 236, 100), `US-OH` = c(300, 300, 30)))
    force(code)
  })
}

test_that("a taxon's regions route gives each state a verdict, with likely states not yet recorded", {
  with_predicted_pull({
    out <- call_api(prediction_api(), "/api/taxa/Trametes%20versicolor/regions")
    expect_equal(out$status, 200L)
    body <- jsonlite::fromJSON(out$body)
    expect_true(body$mapped)
    expect_equal(body$min_share, ATLAS_REGION_MIN_SHARE)
    regions <- body$regions
    expect_setequal(regions$code, c("US-IN", "US-OH", "CA-QC", "US-PR", "US-IA"))
    # Iowa: Maxent rates 15% suitable, the forest nothing, so 7.5% on average.
    expect_equal(regions$model[regions$code == "US-IA"], "possible")
    expect_equal(regions$best_share[regions$code == "US-IA"], 60 / 400)
    expect_equal(regions$model[regions$code == "US-IN"], "likely")
    expect_equal(regions$model[regions$code == "US-OH"], "likely")
    expect_equal(regions$records[regions$code == "US-OH"], 0L)
    expect_equal(regions$suitable_share[regions$code == "US-OH"], (150 / 300 + 30 / 300) / 2)
    expect_equal(regions$model[regions$code == "CA-QC"], "beyond reach")
    # Rated, but not likely and not recorded: left off the list.
    expect_false("US-NE" %in% regions$code)
  })
})

test_that("a state's checklist lists the taxa its maps call likely, marked as not yet recorded", {
  with_predicted_pull({
    out <- call_api(prediction_api(), "/api/checklist.csv", query = "region=US-OH")
    expect_equal(out$status, 200L)
    parsed <- utils::read.csv(text = sub("^\ufeff", "", out$body), stringsAsFactors = FALSE)
    expect_equal(parsed$scientific_name, "Trametes versicolor")
    expect_equal(parsed$status, "likely, not yet recorded")
    expect_equal(parsed$model, "likely")
    expect_equal(parsed$suitable_area_pct, 30L)
    expect_equal(parsed$validated_records, 0L)

    summary <- jsonlite::fromJSON(call_api(prediction_api(), "/api/regions")$body)$regions
    ohio <- summary[summary$code == "US-OH", ]
    expect_equal(c(ohio$taxa, ohio$likely, ohio$possible), c(0L, 1L, 0L))
    iowa <- summary[summary$code == "US-IA", ]
    expect_equal(c(iowa$taxa, iowa$likely, iowa$possible), c(0L, 0L, 1L))

    out <- call_api(prediction_api(), "/api/checklist.csv", query = "region=US-IA")
    parsed <- utils::read.csv(text = sub("^\ufeff", "", out$body), stringsAsFactors = FALSE)
    expect_equal(parsed$status, "possible, not yet recorded")
    expect_equal(parsed$best_map_suitable_pct, 15L)
  })
})
