# Each record's first green validation date: a private side column of the
# pull, computed exactly as MycoMap Vision computes validated_on.

slot_rows <- function(observation_id, s1 = NA, d1 = NA, s2 = NA, d2 = NA, s3 = NA, d3 = NA) {
  data.frame(observation_id = observation_id,
             validation_status_1 = s1, validation_date_1 = d1,
             validation_status_2 = s2, validation_date_2 = d2,
             validation_status_3 = s3, validation_date_3 = d3,
             stringsAsFactors = FALSE)
}

as_tsv <- function(df) {
  con <- textConnection("out", "w", local = TRUE)
  utils::write.table(df, con, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  close(con)
  paste(out, collapse = "\n")
}

test_that(".org's validation dates are read as Vision reads them", {
  # The cases in Vision's tests/test_records.py, and a few more.
  expect_equal(atlas_parse_validation_date("9/2/2026 14:03"), "2026-09-02")
  expect_equal(atlas_parse_validation_date("12/31/2025"), "2025-12-31")
  expect_equal(atlas_parse_validation_date("2026-01-05T00:00:00"), "2026-01-05")
  expect_true(is.na(atlas_parse_validation_date("13/40/2026")))
  expect_true(is.na(atlas_parse_validation_date("")))
  expect_true(is.na(atlas_parse_validation_date(NA)))
  expect_true(is.na(atlas_parse_validation_date("4/31/2026")))
  expect_true(is.na(atlas_parse_validation_date("2026-02-30")))
  expect_equal(atlas_parse_validation_date("  1/1/2020 "), "2020-01-01")
  expect_equal(atlas_parse_validation_date(c("01/02/2024", "garbage", "2024-1-5")),
               c("2024-01-02", NA, NA))
})

test_that("the first green date is the earliest green slot over all of an observation's rows", {
  slots <- rbind(
    # Vision's case: a red slot's earlier date does not count.
    slot_rows("100", "yes", "9/2/2026 14:03", "no", "1/1/2020", "yes", "3/1/2026"),
    # Two rows of one observation (two sequences): the earlier green wins.
    slot_rows("200", "yes", "6/1/2025"),
    slot_rows("200", " YES ", "5/20/2025"),
    # Green with no readable date, and red only: no date.
    slot_rows("300", "yes", "not a date"),
    slot_rows("400", "no", "1/1/2024"),
    # An id with stray spaces is the same observation, as Vision keys it.
    slot_rows(" 500 ", "yes", "2/2/2022")
  )
  first <- atlas_first_green_dates(slots)
  expect_equal(first[["100"]], "2026-03-01")
  expect_equal(first[["200"]], "2025-05-20")
  expect_false("300" %in% names(first))
  expect_false("400" %in% names(first))
  expect_equal(first[["500"]], "2022-02-02")
  page <- fake_occurrences()
  page$observation_id <- c("100", "200", "400")
  added <- atlas_add_first_green(page, slots)
  expect_equal(added$first_green_on, c("2026-03-01", "2025-05-20", NA))
})

test_that("the dates come from a query of their own, one line and safe for the SQL route", {
  sql <- atlas_first_green_sql(175002, 190000)
  expect_silent(atlas_assert_transport_safe(sql))
  for (slot in 1:3) {
    expect_match(sql, sprintf("g.validation_status_%d, g.validation_date_%d", slot, slot), fixed = TRUE)
  }
  # Every row of the page's observations, not only the page's own rows.
  expect_match(sql, "g.observation_id IN (SELECT o.observation_id FROM observations o WHERE o.id >= 175002 AND o.id <= 190000)",
               fixed = TRUE)
  # The pull's own query does not change.
  expect_false(grepl("validation_date", atlas_occurrence_sql(), fixed = TRUE))
})

test_that("the column changes no fingerprint: a record set's, a taxon's or the pull's", {
  plain <- fake_occurrences()
  dated <- atlas_add_first_green(plain, slot_rows(c("a", "b"), "yes", c("1/2/2025", "3/4/2026")))
  expect_true("first_green_on" %in% names(dated))
  expect_identical(atlas_fingerprint(dated), atlas_fingerprint(plain))
  expect_identical(atlas_taxon_fingerprints(dated), atlas_taxon_fingerprints(plain))
  expect_identical(atlas_fingerprints_for(dated, "Amanita muscaria"),
                   atlas_fingerprints_for(plain, "Amanita muscaria"))
})

# A pull through a stand-in for the SQL route: one page of records, and the
# slots of their observations.
pull_with_dates <- function(page = fake_occurrences(),
                            slots = slot_rows(c("a", "b", "c"), "yes", c("1/2/2025", "3/4/2026", NA))) {
  asked <- character()
  testthat::local_mocked_bindings(
    atlas_run_sql = function(sql, host = NULL) {
      asked <<- c(asked, sql)
      if (startsWith(sql, "SELECT g.observation_id")) return(as_tsv(slots))
      if (grepl("o.id > 0 ", sql, fixed = TRUE)) return(as_tsv(page))
      ""
    },
    .env = environment(atlas_pull_occurrences)
  )
  manifest <- atlas_pull_occurrences(quiet = TRUE)
  list(manifest = manifest, asked = asked)
}

test_that("a pull carries each record's first green date, and its fingerprints are as before", {
  with_data_dir({
    run <- pull_with_dates()
    pulled <- atlas_read_occurrences()
    expect_equal(pulled$first_green_on, c("2025-01-02", "2026-03-04", NA))
    # The main query asked is exactly the pull's own, unchanged.
    expect_equal(run$asked[[1]], atlas_occurrence_sql(0, 20000, NULL))
    expect_equal(run$manifest$fingerprint, atlas_fingerprint(fake_occurrences()))
    taxa <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
    expect_equal(taxa$fingerprint, atlas_taxon_fingerprints(fake_occurrences())$fingerprint)
    expect_equal(run$manifest$first_green$records_with_date, 2L)
    # The raw page is kept as .org sent it.
    raw <- list.files(atlas_path("raw", "occurrences"), recursive = TRUE, full.names = TRUE)
    expect_false("first_green_on" %in% names(utils::read.delim(gzfile(raw[[1]]), colClasses = "character")))
  })
})

test_that("the dates are never published: not in a release, its public files or the status", {
  skip_if_not_installed("terra")
  with_data_dir({
    pull_with_dates()
    manifest <- atlas_read_manifest()
    expect_null(atlas_release_pull_summary(manifest)$first_green)
    release <- atlas_publish_release(new_store(), quiet = TRUE)
    paths <- vapply(release$files, function(f) f$path, "")
    expect_false(any(grepl("^occurrences/occurrences-|^raw/", paths)))
    for (path in paths) {
      file <- file.path(atlas_data_dir(), path)
      text <- if (grepl("[.]gz$", path)) readLines(gzfile(file), warn = FALSE) else readLines(file, warn = FALSE)
      expect_false(any(grepl("first_green|2025-01-02|2026-03-04", text)), info = path)
    }
  })
})
