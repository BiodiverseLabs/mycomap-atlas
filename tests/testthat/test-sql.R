test_that("a statement is collapsed onto one line", {
  expect_equal(
    atlas_one_line("select 1\n  from t\twhere x = 2"),
    "select 1 from t where x = 2"
  )
})

test_that("characters that cannot survive the SQL route are refused", {
  expect_error(atlas_assert_transport_safe('select "x" from t'), "double quote")
  expect_error(atlas_assert_transport_safe("select a from t where b like 'c%'"), "percent")
  expect_error(atlas_assert_transport_safe("select 1\nfrom t"), "single line")
})

test_that("an ordinary statement with quoted literals is allowed", {
  expect_true(atlas_assert_transport_safe("select 1 from t where name = 'Amanita muscaria'"))
})

test_that("the occurrence query is safe to send", {
  expect_true(atlas_assert_transport_safe(atlas_occurrence_sql()))
  expect_true(atlas_assert_transport_safe(atlas_occurrence_sql(since = "2026-09-01")))
})
