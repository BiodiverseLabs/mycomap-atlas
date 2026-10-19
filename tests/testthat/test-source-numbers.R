# .org's sources number their records independently: an MO, MyCoPortal or
# Sequences record can carry the same number as an iNaturalist observation.
# A lookup keyed on observation_id must also check the source, or one
# source's answer decides another source's record. Run against a real
# Postgres when ATLAS_TEST_PSQL names a command that reads SQL on stdin and
# prints tab-separated rows (see test-mycoportal-parity.R). Temporary tables
# shadow the real ones, so nothing in that database changes.

ids_kept <- function(fixture, clause) {
  sql <- paste(
    "BEGIN;", fixture,
    sprintf("SELECT o.id FROM observations o WHERE o.latitude IS NOT NULL AND o.longitude IS NOT NULL %s ORDER BY o.id;",
            clause),
    "ROLLBACK;"
  )
  out <- system(Sys.getenv("ATLAS_TEST_PSQL"), input = sql, intern = TRUE)
  as.integer(out[grepl("^[0-9]+$", out)])
}

test_that("an obscured iNaturalist answer leaves out only the iNaturalist record with that number", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  fixture <- paste(
    "CREATE TEMP TABLE observations (id integer, observation_id text, source text, latitude numeric, longitude numeric);",
    "CREATE TEMP TABLE observation_cache (source text, source_observation_id text,",
    "  coordinates_obscured boolean, positional_accuracy integer);",
    "INSERT INTO observations VALUES",
    # Number 500: obscured on iNaturalist; three other sources share it.
    "(1, '500', 'iNaturalist', 45, -122), (2, '500', 'MO Observations', 45, -122),",
    "(3, '500', 'MycoPortal', 45, -122), (4, '500', 'Sequences', 45, -122),",
    # Number 600: placed no better than 5 km on iNaturalist; MO shares it.
    "(5, '600', 'iNaturalist', 45, -122), (6, '600', 'MO Observations', 45, -122),",
    # A precise iNaturalist record, and one with no cached answer whose
    # number an MO answer happens to share.
    "(7, '700', 'iNaturalist', 45, -122), (8, '800', 'iNaturalist', 45, -122);",
    "INSERT INTO observation_cache VALUES",
    "('inat', '500', true, 10), ('inat', '600', false, 5000), ('inat', '700', false, 10),",
    "('mo', '800', true, 99999);"
  )
  expect_identical(ids_kept(fixture, atlas_obscured_clause(max_m = 1000)), c(2L, 3L, 4L, 6L, 7L, 8L))
})

test_that("another source's record never lends its point a MyCoPortal record's label", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  fixture <- paste(
    "CREATE TEMP TABLE observations (id integer, observation_id text, source text, latitude numeric, longitude numeric);",
    "CREATE TEMP TABLE mycoportal_data (observation_id text, locality text, decimal_latitude numeric,",
    "  coordinate_uncertainty_in_meters numeric, sync_status text);",
    "INSERT INTO observations VALUES",
    # A geocoded MyCoPortal record alone on its point, and an MO record on
    # the same point carrying the number of a MyCoPortal record elsewhere.
    "(1, 'c', 'MycoPortal', 42, -92), (2, 'v', 'MO Observations', 42, -92),",
    "(3, 'v', 'MyCoPortal', 60, -120);",
    "INSERT INTO mycoportal_data VALUES",
    "('c', 'Woods', NULL, NULL, 'success'), ('v', 'Elsewhere', NULL, NULL, 'success');"
  )
  expect_identical(ids_kept(fixture, atlas_mycoportal_location_clause(max_m = 5000)), c(1L, 2L, 3L))
})
