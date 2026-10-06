# States and provinces: every spelling of a region lands in one row, the
# checklist opens in Excel, and no coordinate leaves in it.

region_published_paths <- function(release) vapply(release$files, function(f) f$path, character(1))

region_occurrences <- function() {
  data.frame(
    scientific_name = c("Amanita muscaria", "Amanita muscaria", "Amanita muscaria",
                        "Trametes versicolor", "Trametes versicolor", "Trametes versicolor"),
    latitude = c("45.1030", "45.1032", "45.9000", "46.8100", "18.2000", "39.7700"),
    longitude = c("-122.5050", "-122.5052", "-122.9000", "-71.2100", "-66.5000", "-86.1600"),
    state = c("Oregon", "Oregon", "OR", "Québec", "Mayagüez", "Indiana"),
    country = c("US", "US", "US", "CA", "PR", "US"),
    stringsAsFactors = FALSE
  )
}

test_that("every spelling of a region becomes one region", {
  out <- atlas_region_of(
    c("CA", "CA", "MX", "MX", "MX", "MX", "MX", "MX", "MX", "MX", "MX"),
    c("Quebec", "Québec", "VER", "Ver.", "Veracruz de Ignacio de la Llave", "Veracruz",
      "JAL", "QRO", "Querétaro", "San Luis Potosi", "San Luis Potosí")
  )
  expect_equal(out$code, c("CA-QC", "CA-QC", "MX-VER", "MX-VER", "MX-VER", "MX-VER",
                           "MX-JAL", "MX-QUE", "MX-QUE", "MX-SLP", "MX-SLP"))
  expect_equal(out$region[[2]], "Quebec")
  expect_equal(out$country[[3]], "Mexico")
})

test_that("Mexico City and the State of Mexico are told apart under all their names", {
  out <- atlas_region_of(rep("MX", 6), c("Distrito Federal", "Mexico City", "CDMX",
                                         "México", "Estado de México", "State of Mexico"))
  expect_equal(out$code, c(rep("MX-CMX", 3), rep("MX-MEX", 3)))
})

test_that("a recognised state decides the country, whatever the country field says", {
  out <- atlas_region_of(c("CA", "Pu"), c("New York", "Puerto Rico"))
  expect_equal(out$code, c("US-NY", "US-PR"))
  expect_equal(out$country, c("United States", "United States"))
})

test_that("Puerto Rican municipalities and Virgin Islands land in their territory", {
  out <- atlas_region_of(c("PR", "PR", "PR", "VI", "VI"),
                         c("Mayagüez", "San Juan", "", "Saint Croix", "Saint Thomas"))
  expect_equal(out$region, c(rep("Puerto Rico", 3), rep("U.S. Virgin Islands", 2)))
  expect_equal(out$code, c(rep("US-PR", 3), rep("US-VI", 2)))
})

test_that("a two-letter code shared by two countries follows the record's country", {
  out <- atlas_region_of(c("CA", "MX", "CA", "MX", "US"), c("BC", "BC", "NL", "NL", "BC"))
  expect_equal(out$region[1:4], c("British Columbia", "Baja California",
                                  "Newfoundland and Labrador", "Nuevo León"))
  # Neither country's: kept as written rather than guessed.
  expect_equal(out$region[[5]], "BC")
  expect_equal(out$code[[5]], "")
})

test_that("an unknown state keeps its own text, and a blank one says so", {
  out <- atlas_region_of(c("US", "US", "US"), c("Atlantis", "", NA))
  expect_equal(out$region, c("Atlantis", "Not recorded", "Not recorded"))
  expect_equal(out$country, rep("United States", 3))
  expect_equal(out$code, rep("", 3))
})

test_that("the region table counts records and localities per taxon per region, and holds no coordinate", {
  table <- atlas_region_table(region_occurrences())
  expect_setequal(names(table), c("taxon", "country", "country_code", "region", "code",
                                  "records", "localities"))
  oregon <- table[table$code == "US-OR", ]
  expect_equal(nrow(oregon), 1L)
  # Two of the three Oregon records share a 1 km locality.
  expect_equal(oregon$records, 3L)
  expect_equal(oregon$localities, 2L)
  expect_equal(sort(table$code[table$taxon == "Trametes versicolor"]), c("CA-QC", "US-IN", "US-PR"))
  # Sorted by country, then region, then name.
  expect_equal(table$country, sort(table$country))
})

test_that("a checklist is asked for by region code, region name, country, or taxon", {
  table <- atlas_region_table(region_occurrences())
  expect_equal(atlas_checklist(table, region = "us-in")$taxon, "Trametes versicolor")
  expect_equal(atlas_checklist(table, region = "Indiana")$code, "US-IN")
  expect_equal(atlas_checklist(table, region = "quebec")$code, "CA-QC")
  expect_setequal(atlas_checklist(table, region = "US")$code, c("US-OR", "US-IN", "US-PR"))
  expect_equal(nrow(atlas_checklist(table, taxon = "Trametes versicolor")), 3L)
  expect_equal(nrow(atlas_checklist(table)), nrow(table))
  expect_null(atlas_checklist(table, region = "Atlantis"))
  expect_equal(nrow(atlas_checklist(table, region = "US-OR", taxon = "Trametes versicolor")), 0L)
})

test_that("the regions summary counts each region's taxa and records", {
  summary <- atlas_regions_summary(atlas_region_table(region_occurrences()))
  oregon <- summary[summary$code == "US-OR", ]
  expect_equal(oregon$taxa, 1L)
  expect_equal(oregon$records, 3L)
  expect_equal(nrow(summary), 4L)
})

test_that("the checklist CSV opens in Excel with its accents, quotes and links intact", {
  rows <- data.frame(
    taxon = c("Cortinarius sp. \"IN01\"", "Amanita muscaria"),
    country = c("Mexico", "Canada"), country_code = c("MX", "CA"),
    region = c("Michoacán", "Quebec"), code = c("MX-MIC", "CA-QC"),
    records = c(2L, 10L), localities = c(1L, 7L), stringsAsFactors = FALSE
  )
  csv <- atlas_checklist_csv(rows, origin = "https://atlas.example.org")
  # A byte-order mark, or Excel reads UTF-8 as Windows-1252 and mangles accents.
  expect_true(startsWith(csv, "\ufeff"))
  lines <- strsplit(sub("^\ufeff", "", csv), "\r\n", fixed = TRUE)[[1]]
  expect_equal(lines[[1]], paste0("\"country\",\"state_province\",\"region_code\",\"scientific_name\",",
                                  "\"status\",\"validated_records\",\"independent_localities\",\"model\",",
                                  "\"suitable_area_pct\",\"within_reach_pct\",\"atlas_page\""))
  expect_length(lines, 3L)
  parsed <- utils::read.csv(text = sub("^\ufeff", "", csv), stringsAsFactors = FALSE, encoding = "UTF-8")
  expect_equal(parsed$scientific_name[[1]], "Cortinarius sp. \"IN01\"")
  expect_equal(parsed$state_province[[1]], "Michoacán")
  expect_equal(parsed$validated_records, c(2L, 10L))
  expect_equal(parsed$atlas_page[[2]], "https://atlas.example.org/taxa/Amanita%20muscaria")
})

test_that("an empty checklist is still a CSV with its header", {
  csv <- atlas_checklist_csv(atlas_region_table(NULL), origin = "https://atlas.example.org")
  expect_equal(length(strsplit(csv, "\r\n", fixed = TRUE)[[1]]), 1L)
})

test_that("a checklist file is named for what is in it", {
  expect_equal(atlas_checklist_filename(), "mycomap-atlas-checklist.csv")
  expect_equal(atlas_checklist_filename("US-IN"), "mycomap-atlas-checklist-us-in.csv")
  expect_equal(atlas_checklist_filename("", "Amanita muscaria"), "mycomap-atlas-checklist-amanita-muscaria.csv")
})

test_that("a release publishes the region table, and a machine holding only the release reads it back unchanged", {
  store <- new_store()
  from_pull <- with_data_dir({
    computed_data()
    release <- atlas_publish_release(store, quiet = TRUE)
    expect_true("public/regions.tsv.gz" %in% region_published_paths(release))
    atlas_region_table(atlas_read_occurrences())
  })
  with_data_dir({
    atlas_pull_release(store, quiet = TRUE)
    expect_equal(atlas_read_public_regions(), from_pull, ignore_attr = TRUE)
  })
})

test_that("accented region names survive the published file", {
  with_data_dir({
    table <- atlas_region_table(region_occurrences())
    atlas_write_tsv_gz(table, atlas_public_regions_path())
    back <- atlas_read_public_regions()
    expect_equal(back, table, ignore_attr = TRUE)
  })
})

# ---- through the API --------------------------------------------------------

region_api <- function() test_api(c(ATLAS_PUBLIC_ORIGIN = "https://atlas.example.org"))

with_region_pull <- function(code) {
  with_data_dir({
    occurrences <- region_occurrences()
    occurrences$id <- as.character(seq_len(nrow(occurrences)))
    stamp <- "20260101T000000Z"
    file <- paste0("occurrences-", stamp, ".tsv.gz")
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(stamp = stamp, file = file, records = nrow(occurrences)),
                     atlas_path("occurrences", "latest.json"))
    force(code)
  })
}

test_that("the checklist route sends a CSV download that anyone may fetch", {
  with_region_pull({
    api <- region_api()
    out <- call_api(api, "/api/checklist.csv", query = "region=US-IN")
    expect_equal(out$status, 200L)
    expect_match(header_values(out, "Content-Type"), "^text/csv")
    expect_match(header_values(out, "Content-Disposition"),
                 "attachment; filename=\"mycomap-atlas-checklist-us-in.csv\"", fixed = TRUE)
    parsed <- utils::read.csv(text = sub("^\ufeff", "", out$body), stringsAsFactors = FALSE)
    expect_equal(parsed$scientific_name, "Trametes versicolor")
    expect_equal(parsed$state_province, "Indiana")
    expect_equal(parsed$atlas_page, "https://atlas.example.org/taxa/Trametes%20versicolor")
  })
})

test_that("the checklist route refuses a region that is not in the records with 404", {
  with_region_pull({
    out <- call_api(region_api(), "/api/checklist.csv", query = "region=Atlantis")
    expect_equal(out$status, 404L)
    expect_match(out$body, "no such state")
  })
})

test_that("the regions route lists every region with its taxa", {
  with_region_pull({
    out <- call_api(region_api(), "/api/regions")
    expect_equal(out$status, 200L)
    regions <- jsonlite::fromJSON(out$body)$regions
    expect_setequal(regions$code, c("US-OR", "US-IN", "US-PR", "CA-QC"))
  })
})

test_that("a taxon's regions route lists where it was recorded, and never a coordinate", {
  with_region_pull({
    out <- call_api(region_api(), "/api/taxa/Trametes%20versicolor/regions")
    expect_equal(out$status, 200L)
    body <- jsonlite::fromJSON(out$body)
    expect_equal(body$name, "Trametes versicolor")
    expect_setequal(body$regions$region, c("Quebec", "Puerto Rico", "Indiana"))
    for (value in region_occurrences()$latitude) expect_false(grepl(value, out$body, fixed = TRUE))
  })
})
