# Places a source hides stay hidden in what Atlas publishes: the collection
# cells leave out records whose place their source hides or may hide.

test_that("the hidden-place query is one line the SQL route accepts, and asks for the four kinds", {
  sql <- atlas_privacy_sql(0, 100000)
  expect_false(grepl("\n", sql, fixed = TRUE))
  expect_false(grepl('"', sql, fixed = TRUE))
  expect_false(grepl("%", sql, fixed = TRUE))
  expect_match(sql, "o.id > 0 AND o.id <= 100000", fixed = TRUE)
  # iNaturalist with no cached answer; MO with no shown GPS point (whether
  # uncached, which reads as unknown, or placed at its place's centre).
  expect_match(sql, "o.source = 'iNaturalist' AND NOT EXISTS (SELECT 1 FROM observation_cache c", fixed = TRUE)
  expect_match(sql, "o.source = 'MO Observations' AND NOT EXISTS (SELECT 1 FROM atlas.mo_points m", fixed = TRUE)
  expect_match(sql, "m.latitude IS NOT NULL AND m.longitude IS NOT NULL", fixed = TRUE)
  # MO records .org marks as deleted at the source, whatever their answer
  # says; listed as deleted only when no other kind holds.
  expect_match(sql, "OR (o.source = 'MO Observations' AND o.source_deleted_at IS NOT NULL))", fixed = TRUE)
  expect_match(sql, "THEN 'place' ELSE 'deleted' END", fixed = TRUE)
  # The pull's own eligibility: green, with coordinates, in North America.
  expect_match(sql, atlas_status_columns(), fixed = TRUE)
  expect_match(sql, atlas_place_clause(), fixed = TRUE)
})

test_that("the hidden-place list is made a window of record ids at a time and kept privately", {
  with_data_dir({
    asked <- character()
    run <- function(sql, host) {
      asked <<- c(asked, sql)
      if (grepl("max\\(id\\)", sql)) return("top\n250000\n")
      if (grepl("o.id > 1e+05|o.id > 100000 ", sql)) return("source\tobservation_id\tprivacy\niNaturalist\t11\tunknown\nMO Observations\t22\tplace\n")
      "source\tobservation_id\tprivacy\n"
    }
    flagged <- atlas_pull_privacy(quiet = TRUE, window = 100000, run = run)
    expect_length(asked, 4L)                  # the top, then 0-100k, 100k-200k, 200k-300k
    expect_equal(nrow(flagged), 2L)
    expect_setequal(atlas_read_privacy(), c("iNaturalist:11", "MO Observations:22"))
    # Never a release file.
    expect_false(any(grepl("privacy", atlas_release_files("draft"))))
  })
})

test_that("the published collection cells leave out the hidden records, and nothing else", {
  occurrences <- data.frame(
    source = c("iNaturalist", "iNaturalist", "MO Observations", "iNaturalist"),
    observation_id = c("1", "2", "3", "4"),
    scientific_name = c("Taxon A", "Taxon A", "Taxon A", "Taxon B"),
    latitude = c(45.01, 45.02, 46.05, 45.01), longitude = c(-120.01, -120.02, -121.05, -120.01),
    stringsAsFactors = FALSE
  )
  all <- atlas_public_cells_table(occurrences)
  kept <- atlas_public_cells_table(occurrences, hidden = c("iNaturalist:2", "MO Observations:3"))
  expect_equal(sum(all$records), 4L)
  expect_equal(sum(kept$records), 2L)
  # Taxon A's MO cell is gone; its shared cell holds one record, not two.
  expect_equal(nrow(kept[kept$taxon == "Taxon A", ]), 1L)
  expect_equal(kept$records[kept$taxon == "Taxon A"], 1L)
  expect_equal(kept$records[kept$taxon == "Taxon B"], 1L)
  # With no list, nothing is left out (counting by state reads it so).
  expect_identical(atlas_public_cells_table(occurrences, hidden = NULL), all)
})

test_that("a full-view refresh publishes collection cells without the hidden records, from the release's own pull", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  pull <- on_machine(setup$boss, atlas_read_occurrences())
  hide <- pull[pull$scientific_name == "Taxon A", ][1:5, ]
  on_machine(setup$boss, atlas_write_tsv_gz(
    data.frame(source = hide$source, observation_id = hide$observation_id, privacy = "unknown"),
    atlas_privacy_path()))
  refreshed <- run_refresh(setup)$release
  expect_true(refreshed$full_refresh$public_cells$rebuilt)
  expect_equal(refreshed$full_refresh$public_cells$records_left_out, 5L)
  file <- tempfile(fileext = ".tsv.gz")
  setup$store$get(atlas_object_key(release_hash(refreshed, "public/cells.tsv.gz")), file)
  cells <- utils::read.delim(gzfile(file))
  before <- tempfile(fileext = ".tsv.gz")
  setup$store$get(atlas_object_key(release_hash(setup$main, "public/cells.tsv.gz")), before)
  expect_equal(sum(cells$records), sum(utils::read.delim(gzfile(before))$records) - 5L)
})

test_that("a refresh keeps the release's collection cells when the box has no list, or another pull", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  refreshed <- run_refresh(setup)$release
  expect_false(refreshed$full_refresh$public_cells$rebuilt)
  expect_match(refreshed$full_refresh$public_cells$reason, "no hidden-place list")
  expect_identical(release_hash(refreshed, "public/cells.tsv.gz"), release_hash(setup$main, "public/cells.tsv.gz"))
  # A list, but the box has pulled again since.
  again <- refresh_setup()
  on_machine(again$boss, {
    orchestrator_data(synthetic_occurrences(c("Taxon A" = 26, "Taxon B" = 30, "Taxon C" = 22)))
    atlas_write_tsv_gz(data.frame(source = "iNaturalist", observation_id = "1", privacy = "unknown"),
                       atlas_privacy_path())
  })
  later <- run_refresh(again)$release
  expect_false(later$full_refresh$public_cells$rebuilt)
  expect_match(later$full_refresh$public_cells$reason, "not the one the release was fitted on")
})

test_that("an MO record deleted at the source stays out of the collection cells, though the pull keeps it", {
  with_data_dir({
    run <- function(sql, host) {
      if (grepl("max\\(id\\)", sql)) return("top\n10\n")
      "source\tobservation_id\tprivacy\nMO Observations\t3\tdeleted\n"
    }
    atlas_pull_privacy(quiet = TRUE, window = 100000, run = run)
    expect_identical(atlas_read_privacy(), "MO Observations:3")
    # The pull still holds it (models train on it); its cell is not published.
    occurrences <- data.frame(
      source = c("iNaturalist", "MO Observations"), observation_id = c("1", "3"),
      scientific_name = c("Taxon A", "Taxon A"), latitude = c(45.01, 46.05), longitude = c(-120.01, -121.05),
      stringsAsFactors = FALSE
    )
    cells <- atlas_public_cells_table(occurrences, hidden = atlas_read_privacy())
    expect_equal(sum(cells$records), 1L)
    expect_equal(nrow(cells), 1L)
  })
})

# Against a real Postgres (ATLAS_TEST_PSQL, as test-record-keys.R): which
# records the query lists, and as which kind.
test_that("the privacy query lists MO records deleted at the source, as deleted only when no other kind holds", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  row <- function(id, number, source, deleted = FALSE) {
    sprintf("(%d, '%s', '%s', 45, -122, 'yes', NULL, NULL, 'US', NULL, %s)", id, number, source,
            if (deleted) "now()" else "NULL")
  }
  sql <- paste(
    "BEGIN;",
    "CREATE TEMP TABLE observations (id integer, observation_id text, source text, latitude numeric,",
    "  longitude numeric, validation_status_1 text, validation_status_2 text, validation_status_3 text,",
    "  country text, state text, source_deleted_at timestamp);",
    "CREATE TEMP TABLE mo_points (source_observation_id text, latitude numeric, longitude numeric);",
    "CREATE TEMP TABLE observation_cache (source text, source_observation_id text);",
    "INSERT INTO observations VALUES",
    paste(c(
      row(1, "100", "iNaturalist"),                       # no cached answer: unknown
      row(2, "101", "iNaturalist"),                       # answered: not listed
      row(3, "200", "MO Observations"),                   # no cached answer: unknown
      row(4, "201", "MO Observations"),                   # no shown point: place
      row(5, "202", "MO Observations"),                   # shown point: not listed
      row(6, "203", "MO Observations", deleted = TRUE),   # shown point, deleted: deleted
      row(7, "204", "MO Observations", deleted = TRUE),   # no shown point, deleted: place
      row(8, "205", "MO Observations", deleted = TRUE),   # no cached answer, deleted: unknown
      row(9, "206", "iNaturalist", deleted = TRUE)        # answered iNaturalist: not listed
    ), collapse = ", "), ";",
    "INSERT INTO mo_points VALUES ('201', NULL, NULL), ('202', 45, -122), ('203', 45, -122), ('204', NULL, NULL);",
    "INSERT INTO observation_cache VALUES ('inat', '101'), ('inat', '206');",
    paste0(gsub("atlas.mo_points", "pg_temp.mo_points", atlas_privacy_sql(0, 100), fixed = TRUE), ";"),
    "ROLLBACK;"
  )
  out <- system(Sys.getenv("ATLAS_TEST_PSQL"), input = sql, intern = TRUE)
  listed <- grep("[|]", out, value = TRUE)
  expect_identical(listed, c(
    "iNaturalist|100|unknown", "MO Observations|200|unknown", "MO Observations|201|place",
    "MO Observations|203|deleted", "MO Observations|204|place", "MO Observations|205|unknown"
  ))
})
