# The rule (R/privacy.R): a record whose place its source hides or may hide is
# left out of the collection cells, wherever they are read. From the 2026-10-13
# cutover to this fix the API built cells from the pull wherever it could read
# one, so 2,769 listed records reached the live site though every published file
# left them out. These tests ask the real routes, with listed records planted.

# A taxon with two open records and one listed, a taxon only listed, and the
# file a release would publish from them.
with_listed_records <- function(code, published = TRUE, list_exists = TRUE) {
  with_data_dir({
    occurrences <- data.frame(
      id = c("1", "2", "3", "4"), source = "iNaturalist", observation_id = c("11", "12", "13", "14"),
      scientific_name = c("Taxon open", "Taxon open", "Taxon open", "Taxon listed"),
      latitude = c("45.0100", "45.0200", "45.1500", "45.2500"),
      longitude = c("-120.0100", "-120.0200", "-120.1500", "-120.2500"),
      state = "Oregon", country = "US", stringsAsFactors = FALSE
    )
    file <- "occurrences-20260101T000000Z.tsv.gz"
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(stamp = "20260101T000000Z", file = file, records = 4),
                     atlas_path("occurrences", "latest.json"))
    atlas_write_json(data.frame(scientific_name = c("Taxon open", "Taxon listed"), records = c(3L, 1L),
                                localities = c(3L, 1L), fingerprint = "f"),
                     atlas_path("occurrences", "taxa-latest.json"))
    listed <- data.frame(source = "iNaturalist", observation_id = c("13", "14"), privacy = "unknown",
                         stringsAsFactors = FALSE)
    if (isTRUE(published)) {
      atlas_write_tsv_gz(atlas_public_cells_table(occurrences, hidden = atlas_record_key(listed$source, listed$observation_id)),
                         atlas_public_cells_path())
    }
    if (isTRUE(list_exists)) atlas_write_tsv_gz(listed, atlas_privacy_path())
    force(code)
  })
}

cells_api <- function() test_api(c(ATLAS_DATA_DIR = atlas_data_dir(), ATLAS_PUBLIC_ORIGIN = "https://atlas.example.org"))

served_cells <- function(api, name) {
  answer <- call_api(api, paste0("/api/taxa/", utils::URLencode(name, reserved = TRUE), "/cells"))
  expect_equal(answer$status, 200L)
  jsonlite::fromJSON(answer$body)$cells
}

test_that("a listed record never reaches the cells route, where the machine holds its pull", {
  with_listed_records({
    api <- cells_api()
    open <- served_cells(api, "Taxon open")
    expect_equal(sum(open$records), 2L)
    expect_equal(nrow(open), 1L)
    # A taxon with only listed records has no cells, though it has records.
    expect_length(served_cells(api, "Taxon listed"), 0L)
  })
})

test_that("a listed record never reaches recorded-nearby", {
  with_listed_records({
    # An index of the whole grid with nothing in it: every taxon is unmapped here.
    dir.create(dirname(atlas_here_index_path("draft")), recursive = TRUE, showWarnings = FALSE)
    size <- 20 * 1000
    cells <- ceiling((ATLAS_GRID_EXTENT[["xmax"]] - ATLAS_GRID_EXTENT[["xmin"]]) / size) *
      ceiling((ATLAS_GRID_EXTENT[["ymax"]] - ATLAS_GRID_EXTENT[["ymin"]]) / size)
    saveRDS(list(grid = "draft", cell_km = 20, min_rank = 50L, built_at = "2026-01-01T00:00:00Z",
                 models = data.frame(taxon = "Mapped elsewhere", algorithm = "maxnet", stringsAsFactors = FALSE),
                 start = rep(1L, cells + 1L), model = integer(), rank = raw()),
            atlas_here_index_path("draft"))
    answer <- call_api(cells_api(), "/api/here", query = "lat=45.02&lng=-120.02&nearby_km=100")
    expect_equal(answer$status, 200L)
    nearby <- jsonlite::fromJSON(answer$body)$recorded_unmapped
    expect_equal(nearby$scientific_name, "Taxon open")
    # Its open records only; the taxon with only listed records is not here at all.
    expect_equal(nearby$nearby_records, 2L)
  })
})

test_that("with no release, the pull is served with the privacy list applied", {
  with_listed_records({
    api <- cells_api()
    expect_equal(sum(served_cells(api, "Taxon open")$records), 2L)
    expect_length(served_cells(api, "Taxon listed"), 0L)
  }, published = FALSE)
})

test_that("with neither a published file nor a privacy list, no cells are served, not the pull's", {
  with_listed_records({
    api <- cells_api()
    expect_length(served_cells(api, "Taxon open"), 0L)
    expect_length(served_cells(api, "Taxon listed"), 0L)
  }, published = FALSE, list_exists = FALSE)
})

test_that("a published file that cannot be read gives no cells, not the pull's", {
  with_listed_records({
    writeBin(raw(), atlas_public_cells_path())
    api <- cells_api()
    expect_length(served_cells(api, "Taxon open"), 0L)
    expect_length(served_cells(api, "Taxon listed"), 0L)
  })
})

test_that("the published file wins over the pull, whatever the pull holds", {
  with_listed_records({
    atlas_write_tsv_gz(data.frame(taxon = "Taxon open", lat = 10.05, lng = -10.05, records = 7L), atlas_public_cells_path())
    open <- served_cells(cells_api(), "Taxon open")
    expect_equal(open$records, 7L)
    expect_equal(open$lat, 10.05)
  })
})

test_that("regions still count every record: a state is no finer than the source shows", {
  with_listed_records({
    regions <- atlas_region_table(atlas_read_occurrences())
    expect_equal(sum(regions$records), 4L)
    expect_true("Taxon listed" %in% regions$taxon)
  })
})

test_that("no route builds cells from a pull's records itself", {
  api <- readLines(api_file())
  code <- sub("#.*$", "", api)
  expect_false(any(grepl("atlas_public_cells(_table)?[(]", code)))
  expect_false(any(grepl("atlas_taxon_cells[(][^)]*occurrences", code)))
})
