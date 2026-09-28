test_that("a tab-separated answer becomes a data frame", {
  df <- atlas_parse_tsv("id\tscientific_name\tlatitude\n7\tAmanita muscaria\t45.1")
  expect_equal(nrow(df), 1L)
  expect_equal(df$scientific_name, "Amanita muscaria")
})

test_that("every column stays character, so nothing is silently coerced", {
  df <- atlas_parse_tsv("id\tlatitude\n7\t45.1")
  expect_type(df$id, "character")
  expect_type(df$latitude, "character")
})

test_that("an empty answer is an empty frame", {
  expect_equal(nrow(atlas_parse_tsv("")), 0L)
  expect_equal(nrow(atlas_parse_tsv("   ")), 0L)
})

test_that("a header with no rows keeps its columns", {
  df <- atlas_parse_tsv("id\tscientific_name")
  expect_equal(nrow(df), 0L)
  expect_equal(names(df), c("id", "scientific_name"))
})

test_that("an empty field is NA rather than an empty string", {
  df <- atlas_parse_tsv("id\tobserved_on\n7\t")
  expect_true(is.na(df$observed_on))
})
