# The public contact for every MycoMap site is info@mycomap.org. A personal
# address must not appear on a page, in the API spec, the package metadata or
# the security policy, where people would write to it.

contact_root <- function() testthat::test_path("..", "..")

contact_files <- function(root) {
  dirs <- c("R", "inst", "web/src", "web/public", "deploy")
  files <- unlist(lapply(file.path(root, dirs), list.files, full.names = TRUE, recursive = TRUE))
  top <- file.path(root, c("DESCRIPTION", "SECURITY.md", "README.md", "CONTRIBUTING.md",
                           "CHANGELOG.md", "web/index.html"))
  files <- c(files, top[file.exists(top)])
  files[grepl("[.](R|r|md|json|ts|tsx|html|txt|xml|sh|conf|example)$|DESCRIPTION$", files)]
}

test_that("no file names a personal email address instead of info@mycomap.org", {
  # Built in pieces so this file does not match itself.
  personal <- paste0("@", "biodiverselabs", "[.]io")
  root <- contact_root()
  testthat::skip_if_not(dir.exists(file.path(root, "web", "src")), "the release image carries no web sources")
  files <- contact_files(root)
  expect_gt(length(files), 0)
  hits <- Filter(function(f) any(grepl(personal, readLines(f, warn = FALSE), ignore.case = TRUE)), files)
  expect_equal(basename(hits), character(0), label = "files naming a personal address")
})

test_that("the package and the security policy give info@mycomap.org", {
  root <- contact_root()
  expect_match(paste(readLines(file.path(root, "DESCRIPTION")), collapse = "\n"), "info@mycomap.org", fixed = TRUE)
  security <- file.path(root, "SECURITY.md")
  testthat::skip_if_not(file.exists(security), "SECURITY.md is not in the release image")
  expect_match(paste(readLines(security), collapse = "\n"), "info@mycomap.org", fixed = TRUE)
})
