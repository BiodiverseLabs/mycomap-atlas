# The (source, number) key rule (R/keys.R): no join, lookup, match or set
# operation on records uses a record's number alone. Three lookups did, and
# each took one source's fact for another source's record.

test_that("a record's key is its source and number together", {
  expect_equal(atlas_record_key("iNaturalist", "500"), "iNaturalist:500")
  expect_false(atlas_record_key("iNaturalist", "500") == atlas_record_key("MO Observations", "500"))
  expect_equal(atlas_record_key(c("iNaturalist", "MycoPortal"), c("1", "1")), c("iNaturalist:1", "MycoPortal:1"))
})

# Lines of R code that look a record up by its number with no source beside
# it. A row index (x[[i]]) is not a lookup by number.
atlas_bare_number_lines <- function(files) {
  number <- "\\b(observation_id|source_observation_id|external_id)\\b"
  lookup <- "%in%|\\bmatch\\(|\\bmerge\\(|\\btapply\\(|\\bsplit\\(|\\bsetNames\\(|\\bduplicated\\(|\\bunique\\(|\\[\\[(?![a-z]\\]\\])"
  hits <- character()
  for (file in files) {
    lines <- readLines(file, warn = FALSE)
    code <- sub("#.*$", "", lines)
    without_source_column <- gsub("source_observation_id", "", code, fixed = TRUE)
    bad <- grepl(number, code, perl = TRUE) & grepl(lookup, code, perl = TRUE) &
      !grepl("source", without_source_column, fixed = TRUE) & !grepl("atlas_record_key", code, fixed = TRUE)
    if (any(bad)) hits <- c(hits, sprintf("%s:%d: %s", basename(file), which(bad), trimws(lines[bad])))
  }
  hits
}

test_that("no R code looks a record up by its number without its source", {
  root <- testthat::test_path("..", "..", "R")
  skip_if_not(dir.exists(root), "the package's R/ folder is not beside the tests")
  hits <- atlas_bare_number_lines(list.files(root, pattern = "[.]R$", full.names = TRUE))
  expect_identical(hits, character(), info = paste(hits, collapse = "\n"))
})

test_that("the R scan catches a lookup by number alone, and lets a keyed one pass", {
  file <- tempfile(fileext = ".R")
  writeLines(c(
    "first <- tapply(all$date, all$observation_id, min)",
    "keep <- !occurrences$observation_id %in% done",
    "keep <- !atlas_record_key(occurrences$source, occurrences$observation_id) %in% done",
    "list(source = s[[i]], observation_id = o[[i]])",
    "# a comment about observation_id %in% done"
  ), file)
  hits <- atlas_bare_number_lines(file)
  expect_length(hits, 2L)
  expect_match(hits[[1]], ":1: ")
  expect_match(hits[[2]], ":2: ")
})

# Every SQL builder whose statement compares a record's number with
# o.observation_id: the same statement must also hold the record's source,
# by an o.source condition or a (source, observation_id) pair.
test_that("every SQL that compares a record's number also holds its source", {
  built <- list(
    pull = atlas_occurrence_sql(),
    obscured = atlas_obscured_clause(),
    mo_location = atlas_mo_location_clause(),
    mycoportal = atlas_mycoportal_location_clause(),
    privacy = atlas_privacy_sql(0, 10),
    first_green = atlas_first_green_sql(1, 2),
    sequence_names = atlas_sequence_names_sql(1, 2),
    mo_left_out = atlas_mo_left_out_sql(1, 2)
  )
  compares <- "(observation_id|external_id)\\s*=\\s*o2?\\.observation_id|o2?\\.observation_id\\s*=|\\(\\w+\\.source,\\s*\\w+\\.observation_id\\)"
  sourced <- "\\bo2?\\.source\\b|\\(\\w+\\.source,\\s*\\w+\\.observation_id\\)"
  for (name in names(built)) {
    sql <- built[[name]]
    if (!grepl(compares, sql, perl = TRUE)) next
    expect_true(grepl(sourced, sql, perl = TRUE), info = name)
  }
  # And the check would see a clause that has no source: the bug as it was.
  expect_false(grepl(sourced, "AND NOT EXISTS (SELECT 1 FROM observation_cache c WHERE c.source_observation_id = o.observation_id)",
                     perl = TRUE))
})

# Against a real Postgres (ATLAS_TEST_PSQL, as test-source-numbers.R), the
# clauses that keyed on numbers before: an MO and an iNaturalist record that
# share a number each keep their own answer.
psql_rows <- function(sql) {
  out <- system(Sys.getenv("ATLAS_TEST_PSQL"), input = sql, intern = TRUE)
  out[nzchar(out) & !grepl("^(BEGIN|ROLLBACK|CREATE|INSERT)", out)]
}

test_that("the MO place rule reads only the MO record's answer, whatever else shares its number", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  sql <- paste(
    "BEGIN;",
    "CREATE TEMP TABLE observations (id integer, observation_id text, source text, latitude numeric,",
    "  longitude numeric, source_deleted_at timestamp);",
    "CREATE SCHEMA IF NOT EXISTS atlas;",
    "CREATE TEMP TABLE mo_points (source_observation_id text, latitude numeric, longitude numeric,",
    "  latitude_north numeric, latitude_south numeric, longitude_east numeric, longitude_west numeric);",
    "INSERT INTO observations VALUES",
    # 900: MO with a shown GPS point; an iNaturalist record shares it.
    "(1, '900', 'MO Observations', 45, -122, NULL), (2, '900', 'iNaturalist', 45, -122, NULL),",
    # 901: an iNaturalist record whose number only an MO answer with a huge box carries.
    "(3, '901', 'iNaturalist', 45, -122, NULL),",
    # 902: MO with a huge box and no point.
    "(4, '902', 'MO Observations', 45, -122, NULL);",
    "INSERT INTO mo_points VALUES ('900', 45, -122, 45.01, 44.99, -121.99, -122.01),",
    "('901', NULL, NULL, 47, 43, -118, -126), ('902', NULL, NULL, 47, 43, -118, -126);",
    sprintf("SELECT o.id FROM observations o WHERE true %s ORDER BY o.id;",
            gsub("atlas.mo_points", "pg_temp.mo_points", atlas_mo_location_clause(unknown = "drop"), fixed = TRUE)),
    "ROLLBACK;"
  )
  kept <- as.integer(grep("^[0-9]+$", psql_rows(sql), value = TRUE))
  # MO 900 is placed, the iNaturalist records are untouched by MO's rule,
  # and MO 902's box is too big.
  expect_identical(kept, c(1L, 2L, 3L))
})
