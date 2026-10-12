# The set-based "another label on this point" check keeps exactly the records
# the per-record one did. Run against a real Postgres when ATLAS_TEST_PSQL
# names a command that reads SQL on stdin and prints tab-separated rows, e.g.
#   ATLAS_TEST_PSQL="docker exec -i mycomap-postgres psql -U mycomap -d mycomap -At -F ,"
# Temporary tables shadow the real ones, so nothing in that database changes.

# The clause as it was before 2026-10-12: a per-record scan, kept here as the
# reference the set-based one must match.
mycoportal_clause_before <- function(max_m = 5000) {
  answered <- "p.observation_id = o.observation_id AND p.sync_status = 'success'"
  placed <- sprintf(paste(
    "EXISTS (SELECT 1 FROM mycoportal_data p WHERE %s AND (",
    "(p.decimal_latitude IS NOT NULL AND coalesce(p.coordinate_uncertainty_in_meters, 0) <= %d)",
    "OR (p.decimal_latitude IS NULL AND NOT EXISTS (SELECT 1 FROM observations o2",
    "JOIN mycoportal_data p2 ON p2.observation_id = o2.observation_id",
    "WHERE o2.latitude = o.latitude AND o2.longitude = o.longitude",
    "AND o2.observation_id <> o.observation_id",
    "AND coalesce(p2.locality, '') <> coalesce(p.locality, '')))))"
  ), answered, as.integer(max_m))
  unanswered <- sprintf("NOT EXISTS (SELECT 1 FROM mycoportal_data p WHERE %s)", answered)
  sprintf("AND (o.source NOT IN ('MycoPortal', 'MyCoPortal') OR %s OR %s)", placed, unanswered)
}

# id, observation_id, source, latitude, longitude; and each observation's one
# MyCoPortal answer: locality, its own coordinates, uncertainty, status.
mycoportal_fixture_sql <- function() {
  paste(
    "CREATE TEMP TABLE observations (id integer, observation_id text, source text, latitude numeric, longitude numeric);",
    "CREATE TEMP TABLE mycoportal_data (observation_id text, locality text, decimal_latitude numeric,",
    "  coordinate_uncertainty_in_meters numeric, sync_status text);",
    "INSERT INTO observations VALUES",
    # Own coordinates, within and beyond the limit.
    "(1, 'a', 'MycoPortal', 40, -90), (2, 'b', 'MyCoPortal', 41, -91),",
    # Geocoded, alone on its point.
    "(3, 'c', 'MycoPortal', 42, -92),",
    # Geocoded, sharing a point with the same label: both kept.
    "(4, 'd', 'MycoPortal', 43, -93), (5, 'e', 'MycoPortal', 43, -93),",
    # Geocoded, sharing a point with another label: both left out.
    "(6, 'f', 'MycoPortal', 44, -94), (7, 'g', 'MycoPortal', 44, -94),",
    # The other label belongs to an answer that did not sync: still a second label.
    "(8, 'h', 'MycoPortal', 45, -95), (9, 'i', 'MycoPortal', 45, -95),",
    # One observation on two rows (two sequences), one label: kept.
    "(10, 'j', 'MycoPortal', 46, -96), (11, 'j', 'MycoPortal', 46, -96),",
    # No locality and an empty one are the same label.
    "(12, 'k', 'MycoPortal', 47, -97), (13, 'l', 'MycoPortal', 47, -97),",
    # No MyCoPortal answer yet: kept (unknown = keep).
    "(14, 'm', 'MycoPortal', 48, -98),",
    # Another source on a shared, multi-label point: untouched.
    "(15, 'n', 'iNaturalist', 44, -94),",
    # Three labels on one point, one shared by two records.
    "(16, 'o', 'MycoPortal', 49, -99), (17, 'p', 'MycoPortal', 49, -99), (18, 'q', 'MycoPortal', 49, -99),",
    # No locality beside a named one: two labels, both left out.
    "(19, 'r', 'MycoPortal', 50, -100), (20, 's', 'MycoPortal', 50, -100),",
    # Records with no coordinates (never pulled), two labels between them:
    # their missing point must not reach a NOT IN set, or nothing is kept.
    "(21, 't', 'MycoPortal', NULL, NULL), (22, 'u', 'MycoPortal', NULL, NULL);",
    "INSERT INTO mycoportal_data VALUES",
    "('a', 'Park', 40, 100, 'success'), ('b', 'Park', 41, 9000, 'success'),",
    "('c', 'Woods', NULL, NULL, 'success'),",
    "('d', 'County', NULL, NULL, 'success'), ('e', 'County', NULL, NULL, 'success'),",
    "('f', 'Lake', NULL, NULL, 'success'), ('g', 'River', NULL, NULL, 'success'),",
    "('h', 'Hill', NULL, NULL, 'success'), ('i', 'Dale', NULL, NULL, 'failed'),",
    "('j', 'Bog', NULL, NULL, 'success'),",
    "('k', NULL, NULL, NULL, 'success'), ('l', '', NULL, NULL, 'success'),",
    "('o', 'X', NULL, NULL, 'success'), ('p', 'X', NULL, NULL, 'success'), ('q', 'Y', NULL, NULL, 'success'),",
    "('r', NULL, NULL, NULL, 'success'), ('s', 'Z', NULL, NULL, 'success'),",
    "('t', 'T', NULL, NULL, 'success'), ('u', 'U', NULL, NULL, 'success');"
  )
}

kept_by <- function(clause) {
  sql <- paste(
    "BEGIN;", mycoportal_fixture_sql(),
    # As the pull asks: only records with coordinates.
    sprintf("SELECT o.id FROM observations o WHERE o.latitude IS NOT NULL AND o.longitude IS NOT NULL %s ORDER BY o.id;",
            clause),
    "ROLLBACK;"
  )
  command <- Sys.getenv("ATLAS_TEST_PSQL")
  out <- system(command, input = sql, intern = TRUE)
  as.integer(out[grepl("^[0-9]+$", out)])
}

test_that("the set-based MyCoPortal check keeps exactly the records the per-record one kept", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  before <- kept_by(mycoportal_clause_before())
  after <- kept_by(atlas_mycoportal_location_clause(max_m = 5000))
  expect_identical(after, before)
  # And the fixture says what it should: own coordinates within the limit, a
  # point alone, one label shared, one observation on two rows, empty and
  # missing localities alike, no answer yet (9's did not sync, though its label
  # still marks 8's point as shared), and another source.
  expect_identical(before, c(1L, 3L, 4L, 5L, 9L, 10L, 11L, 12L, 13L, 14L, 15L))
})

test_that("the not-yet-validated counts' name rule is the pull's: trimmed, species-level", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  names <- c("Russula emetica", "Russula ", "Russula sp. ", " Russula sp", "Russula sp.\t", "Fungi ",
             " Unknown", "", "Mycena sp. 'IN10'", "Amanita  muscaria ", "Trametes\tversicolor")
  values <- paste(sprintf("(%d, '%s', 'US')", seq_along(names), gsub("'", "''", names)), collapse = ", ")
  sql <- paste(
    "BEGIN;",
    "CREATE TEMP TABLE observations (id integer, scientific_name text, country text, state text);",
    sprintf("INSERT INTO observations (id, scientific_name, country) VALUES %s;", values),
    sprintf("SELECT o.id FROM observations o WHERE true %s ORDER BY o.id;", atlas_place_and_name_clause()),
    "ROLLBACK;"
  )
  out <- system(Sys.getenv("ATLAS_TEST_PSQL"), input = sql, intern = TRUE)
  counted <- as.integer(out[grepl("^[0-9]+$", out)])
  expect_identical(counted, which(atlas_species_level(names)))
  expect_false(2L %in% counted)
})
