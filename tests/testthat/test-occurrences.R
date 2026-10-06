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

test_that("a Mushroom Observer record needs a visible GPS point or a small named location", {
  sql <- atlas_occurrence_sql()
  clause <- atlas_mo_location_clause()
  expect_match(sql, clause, fixed = TRUE)
  # Only MO records are judged by it; every other source passes untouched.
  expect_match(clause, "AND (o.source <> 'MO Observations' OR ", fixed = TRUE)
  expect_match(clause, "m.source = 'mo' AND m.source_observation_id = o.observation_id", fixed = TRUE)
  # A hidden GPS point is treated as obscured.
  expect_match(clause, "coalesce((CAST(m.api_response_json AS jsonb) ->> 'gps_hidden')::boolean, false) = false",
               fixed = TRUE)
  expect_match(clause, "(CAST(m.api_response_json AS jsonb) ->> 'latitude') IS NOT NULL", fixed = TRUE)
  # Without one, half the location box's diagonal must be within the limit, in km.
  for (side in c("latitude_north", "latitude_south", "longitude_east", "longitude_west")) {
    expect_match(clause, sprintf("'location' ->> '%s'", side), fixed = TRUE)
  }
  expect_match(atlas_mo_location_clause(max_m = 5000), "/ 2 <= 5)", fixed = TRUE)
  expect_match(atlas_mo_location_clause(max_m = 1000), "/ 2 <= 1)", fixed = TRUE)
})

test_that("an MO record .org has no MO answer for is kept or dropped as configured", {
  kept <- atlas_mo_location_clause(unknown = "keep")
  dropped <- atlas_mo_location_clause(unknown = "drop")
  expect_match(kept, "OR NOT EXISTS (SELECT 1 FROM observation_cache m", fixed = TRUE)
  expect_false(grepl("NOT EXISTS", dropped, fixed = TRUE))
  expect_error(atlas_mo_location_clause(unknown = "maybe"))
})

test_that("the MO condition survives the SQL route: one line, no double quote, no percent", {
  sql <- atlas_occurrence_sql()
  expect_false(grepl("\n", sql))
  expect_false(grepl("\"", sql, fixed = TRUE))
  expect_false(grepl("%", sql, fixed = TRUE))
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

test_that("genus-only and placeholder names are excluded", {
  sql <- atlas_occurrence_sql()
  expect_match(sql, "o.scientific_name NOT IN ('', 'Fungi', 'Unknown')", fixed = TRUE)
  expect_match(sql, "strpos(o.scientific_name, ' ') > 0", fixed = TRUE)
  expect_match(sql, "right(lower(o.scientific_name), 4) <> ' sp.'", fixed = TRUE)
  expect_match(sql, "right(lower(o.scientific_name), 3) <> ' sp'", fixed = TRUE)
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
