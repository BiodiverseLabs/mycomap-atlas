test_that("flags with values are parsed", {
  flags <- atlas_parse_flags(c("--since=2026-09-01", "--chunk-size=500"))
  expect_equal(flags$since, "2026-09-01")
  expect_equal(flags$chunk_size, "500")
})

test_that("a flag without a value is TRUE", {
  expect_true(atlas_parse_flags("--dry-run")$dry_run)
})

test_that("a bare argument is refused, so a typo never runs a full pull", {
  expect_error(atlas_parse_flags("since=2026-09-01"), "unexpected argument")
})

test_that("no flags gives an empty list", {
  expect_equal(length(atlas_parse_flags(character())), 0L)
})
