# The API's promise to its callers is written in three places: the version in
# inst/api/openapi.json, the notice period in CHANGELOG.md, and the Stability
# section of the Developers page. These keep the three saying the same thing.

changelog_root <- function() testthat::test_path("..", "..")

read_changelog <- function() {
  path <- file.path(changelog_root(), "CHANGELOG.md")
  # The release image carries neither the changelog nor the web sources; CI's
  # R tests on the full checkout are where this is checked.
  skip_if_not(file.exists(path), "CHANGELOG.md is not here (release image)")
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

test_that("the changelog names the API version the spec carries", {
  changelog <- read_changelog()
  spec <- jsonlite::fromJSON(file.path(changelog_root(), "inst", "api", "openapi.json"), simplifyVector = FALSE)
  expect_true(grepl(paste0("`", spec$info$version, "`"), changelog, fixed = TRUE),
              label = paste("CHANGELOG.md mentions version", spec$info$version))
})

test_that("the changelog and the Developers page promise the same notice for a breaking change", {
  changelog <- read_changelog()
  page <- file.path(changelog_root(), "web", "src", "pages", "Developers.tsx")
  skip_if_not(file.exists(page), "the web app's sources are not here (release image)")
  days_page <- sub(".*BREAKING_NOTICE_DAYS = ([0-9]+);.*", "\\1",
                   paste(readLines(page, warn = FALSE), collapse = "\n"))
  days_changelog <- regmatches(changelog, regexpr("at least\\s+[0-9]+\\s+days", changelog))
  expect_length(days_changelog, 1L)
  expect_equal(sub("\\D*([0-9]+)\\D*", "\\1", days_changelog), days_page)
  expect_true(as.integer(days_page) >= 30L, label = "at least 30 days' notice")
})
