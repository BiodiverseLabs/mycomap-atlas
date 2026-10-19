test_that("a record must be green in at least one project, all three slots checked", {
  sql <- atlas_occurrence_sql()
  expect_match(sql, "'yes' IN (", fixed = TRUE)
  for (slot in 1:3) {
    expect_match(sql, sprintf("coalesce(o.validation_status_%d, '')", slot), fixed = TRUE)
  }
})

test_that("a red in another project does not rule out a record that is green in one", {
  # Steve, 2026-09-30: the green project settled the name.
  sql <- atlas_occurrence_sql()
  expect_false(grepl("'no'", sql, fixed = TRUE))
  expect_false(grepl("NOT IN (coalesce", sql, fixed = TRUE))
})

test_that("obscured and coarse coordinates are excluded", {
  sql <- atlas_occurrence_sql()
  expect_match(sql, "NOT EXISTS", fixed = TRUE)
  expect_match(sql, "c.coordinates_obscured = true", fixed = TRUE)
  expect_match(sql, "c.positional_accuracy > 1000", fixed = TRUE)
})

test_that("the obscured-coordinates check stays a per-record probe, inside the route's 60 s cap", {
  # As an anti join it rescanned every cached iNat answer per record and a
  # page timed out (2026-10-08); OFFSET 0 keeps the planner from flattening it.
  sql <- atlas_occurrence_sql()
  expect_match(sql, "OR c.positional_accuracy > 1000) OFFSET 0)", fixed = TRUE)
})

test_that("only an iNaturalist record is checked against cached iNaturalist answers", {
  # Sources number their records independently: matched by number alone, 20
  # MO records and 1 MyCoPortal record sharing a number with an obscured
  # iNaturalist observation were left out of every pull (2026-10-18).
  sql <- atlas_occurrence_sql()
  expect_match(sql, "AND (o.source <> 'iNaturalist' OR NOT EXISTS (SELECT 1 FROM observation_cache c", fixed = TRUE)
  expect_identical(lengths(regmatches(sql, gregexpr("observation_cache", sql, fixed = TRUE))), 1L)
})

test_that("only MyCoPortal records mark a point as carrying several labels", {
  # An MO record can carry a MyCoPortal record's number, and would lend its
  # point that record's label (28 MO rows did on 2026-10-18).
  clause <- atlas_mycoportal_location_clause()
  expect_match(clause, "WHERE o2.source IN ('MycoPortal', 'MyCoPortal') AND o2.latitude IS NOT NULL", fixed = TRUE)
})

test_that("a Mushroom Observer record needs a visible GPS point or a small named location", {
  sql <- atlas_occurrence_sql()
  clause <- atlas_mo_location_clause()
  expect_match(sql, clause, fixed = TRUE)
  # Only MO records are judged by it; every other source passes untouched.
  expect_match(clause, "AND (o.source <> 'MO Observations' OR ", fixed = TRUE)
  expect_match(clause, "FROM atlas.mo_points m WHERE m.source_observation_id = o.observation_id", fixed = TRUE)
  # A GPS point counts only when the observer shows it; a hidden one is no
  # GPS point (the view has none for it), and the location box decides.
  answer <- atlas_mo_answer_sql()
  expect_match(clause, sprintf("AND (%s OR %s))", answer$gps, answer$small), fixed = TRUE)
  expect_equal(answer$gps, "(m.latitude IS NOT NULL AND m.longitude IS NOT NULL)")
  expect_false(grepl("m.latitude IS", answer$small, fixed = TRUE))
  # Without one, half the location box's diagonal must be within the limit, in km.
  for (side in c("latitude_north", "latitude_south", "longitude_east", "longitude_west")) {
    expect_match(clause, sprintf("m.%s", side), fixed = TRUE)
  }
  expect_match(atlas_mo_location_clause(max_m = 5000), "/ 2 <= 5)", fixed = TRUE)
  expect_match(atlas_mo_location_clause(max_m = 1000), "/ 2 <= 1)", fixed = TRUE)
})

test_that("an MO record's coordinate comes from MO's own answer, not from .org's row", {
  sql <- atlas_occurrence_sql()
  answer <- atlas_mo_answer_sql()
  for (axis in c("latitude", "longitude")) {
    column <- atlas_mo_coordinate_sql(axis)
    expect_match(sql, column, fixed = TRUE)
    # The shown GPS point first, then the small location's centre; any other
    # source, or an MO record with no cached answer, keeps .org's coordinate.
    expect_match(column, sprintf("CASE WHEN %s THEN %s WHEN %s THEN %s END", answer$gps,
                                 answer$point[[axis]], answer$small, answer$centre[[axis]]), fixed = TRUE)
    expect_match(column, sprintf("CASE WHEN o.source = 'MO Observations' THEN coalesce((SELECT"), fixed = TRUE)
    expect_match(column, sprintf("LIMIT 1), o.%s) ELSE o.%s END AS %s", axis, axis, axis), fixed = TRUE)
  }
  # .org's own MO coordinate is never selected as is.
  expect_false(grepl("o.latitude, o.longitude", atlas_occurrence_columns_sql(), fixed = TRUE))
  expect_match(atlas_occurrence_columns_sql(), "^o.id, o.observation_id, o.source")
  expect_equal(answer$centre$latitude, "(m.latitude_north + m.latitude_south) / 2")
})

test_that("nothing Atlas asks .org for reads a cached API answer: MO places come from the view", {
  # The answer holds the observer's name and any GPS point they hid, and
  # Atlas's login cannot read it (.org deploy/readonly-sql/atlas-install.sh).
  asked <- c(atlas_occurrence_sql(), atlas_unvalidated_sql(), atlas_first_green_sql(1, 2),
             atlas_sequence_names_sql(1, 2))
  for (sql in asked) expect_false(grepl("api_response_json", sql, fixed = TRUE))
  expect_match(asked[[1]], "FROM atlas.mo_points m", fixed = TRUE)
  expect_false(grepl("observation_cache m", asked[[1]], fixed = TRUE))
})

test_that("an MO record .org has no MO answer for is kept or dropped as configured", {
  kept <- atlas_mo_location_clause(unknown = "keep")
  dropped <- atlas_mo_location_clause(unknown = "drop")
  expect_match(kept, "OR NOT EXISTS (SELECT 1 FROM atlas.mo_points m", fixed = TRUE)
  expect_false(grepl("NOT EXISTS", dropped, fixed = TRUE))
  expect_error(atlas_mo_location_clause(unknown = "maybe"))
})

test_that("the MO condition survives the SQL route: one line, no double quote, no percent", {
  sql <- atlas_occurrence_sql()
  expect_false(grepl("\n", sql))
  expect_false(grepl("\"", sql, fixed = TRUE))
  expect_false(grepl("%", sql, fixed = TRUE))
})

test_that("a MyCoPortal record needs MyCoPortal's own coordinates or a label no other label shares a point with", {
  sql <- atlas_occurrence_sql()
  clause <- atlas_mycoportal_location_clause()
  expect_match(sql, clause, fixed = TRUE)
  expect_match(clause, "AND (o.source NOT IN ('MycoPortal', 'MyCoPortal') OR ", fixed = TRUE)
  expect_match(clause, "p.sync_status = 'success'", fixed = TRUE)
  # Placed by MyCoPortal: within the limit, or no uncertainty recorded.
  expect_match(clause, "coalesce(p.coordinate_uncertainty_in_meters, 0) <= 5000", fixed = TRUE)
  expect_match(atlas_mycoportal_location_clause(max_m = 1000), "<= 1000)", fixed = TRUE)
  # Geocoded: not on a point that carries two or more labels, found once for
  # all records (test-mycoportal-parity.R holds it to the per-record form).
  expect_match(clause, "(o.latitude, o.longitude) NOT IN (SELECT o2.latitude, o2.longitude FROM observations o2",
               fixed = TRUE)
  expect_match(clause, "HAVING count(DISTINCT coalesce(p2.locality, '')) >= 2", fixed = TRUE)
  # NOT IN against a set with a NULL row would keep nothing: no NULL points.
  expect_match(clause, "AND o2.latitude IS NOT NULL AND o2.longitude IS NOT NULL GROUP BY", fixed = TRUE)
})

test_that("every location condition opens as many brackets as it closes", {
  # The other tests match fragments, which a stray bracket passes; Postgres
  # would refuse the whole pull.
  balanced <- function(x) {
    depth <- cumsum(ifelse(strsplit(x, "")[[1]] == "(", 1, ifelse(strsplit(x, "")[[1]] == ")", -1, 0)))
    all(depth >= 0) && depth[[length(depth)]] == 0
  }
  for (unknown in c("keep", "drop")) {
    expect_true(balanced(atlas_mo_location_clause(unknown = unknown)), label = paste("MO", unknown))
    expect_true(balanced(atlas_mycoportal_location_clause(unknown = unknown)),
                label = paste("MyCoPortal", unknown))
  }
  expect_true(balanced(atlas_occurrence_sql()))
  expect_true(balanced(atlas_mo_coordinate_sql("latitude")))
  expect_true(balanced(atlas_mo_coordinate_sql("longitude")))
})

test_that("a MyCoPortal record with no answer yet is kept or dropped as configured", {
  kept <- atlas_mycoportal_location_clause(unknown = "keep")
  dropped <- atlas_mycoportal_location_clause(unknown = "drop")
  expect_match(kept, "OR NOT EXISTS (SELECT 1 FROM mycoportal_data p WHERE", fixed = TRUE)
  expect_false(grepl("OR NOT EXISTS (SELECT 1 FROM mycoportal_data p WHERE", dropped, fixed = TRUE))
  expect_error(atlas_mycoportal_location_clause(unknown = "maybe"))
})

test_that("records without coordinates are excluded", {
  sql <- atlas_occurrence_sql()
  expect_match(sql, "o.latitude IS NOT NULL", fixed = TRUE)
  expect_match(sql, "o.longitude IS NOT NULL", fixed = TRUE)
})

test_that("the scope is North America, including blank-country Puerto Rico", {
  sql <- atlas_occurrence_sql()
  expect_match(sql, "o.country IN ('US', 'CA', 'MX', 'PR', 'VI')", fixed = TRUE)
  expect_match(sql, "o.state = 'Puerto Rico'", fixed = TRUE)
})

test_that("the record name does not decide eligibility: the sequences name the record", {
  # A genus-only record name with species-level sequences is modelled under
  # the species (R/labels.R), so the pull must not drop it on its record name.
  sql <- atlas_occurrence_sql()
  expect_false(grepl("strpos(o.scientific_name", sql, fixed = TRUE))
  expect_false(grepl("right(lower(o.scientific_name)", sql, fixed = TRUE))
  expect_false(grepl("o.scientific_name NOT IN", sql, fixed = TRUE))
})

test_that("paging keys off the record id", {
  sql <- atlas_occurrence_sql(after_id = 4200, limit = 10)
  expect_match(sql, "o.id > 4200", fixed = TRUE)
  expect_match(sql, "ORDER BY o.id", fixed = TRUE)
  expect_match(sql, "LIMIT 10", fixed = TRUE)
})

test_that("since must be a date, and filters on updated_at", {
  expect_error(atlas_occurrence_sql(since = "last tuesday"), "YYYY-MM-DD")
  expect_match(
    atlas_occurrence_sql(since = "2026-09-01"),
    "o.updated_at >= date '2026-09-01'",
    fixed = TRUE
  )
})

test_that("a full pull has no since clause", {
  expect_false(grepl("updated_at >=", atlas_occurrence_sql(), fixed = TRUE))
})

test_that("a pull that lost its coordinates is refused", {
  df <- fake_occurrences()
  df$latitude[2] <- NA
  expect_error(atlas_check_occurrences(df), "without coordinates")
})

test_that("a pull with a nameless record is refused", {
  df <- fake_occurrences()
  df$scientific_name[1] <- ""
  expect_error(atlas_check_occurrences(df), "without a name")
})

test_that("a pull with a duplicated record is refused", {
  df <- fake_occurrences()
  df$id[2] <- df$id[1]
  expect_error(atlas_check_occurrences(df), "duplicate record ids")
})

test_that("a clean pull passes", {
  expect_silent(atlas_check_occurrences(fake_occurrences()))
})
