# The README is the front door and points into docs/ for the detail. A link
# that leads nowhere strands a reader halfway, so every relative link in the
# documentation must name a file that exists, and a #section on another
# document must name one of its headings.

docs_root <- function() testthat::test_path("..", "..")

docs_files <- function(root) {
  top <- file.path(root, c("README.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md", "CLAUDE.md"))
  nested <- c(list.files(file.path(root, "docs"), "[.]md$", full.names = TRUE),
              list.files(file.path(root, "deploy"), "^README[.]md$", full.names = TRUE, recursive = TRUE))
  c(top[file.exists(top)], nested)
}

# GitHub's anchor for a heading: lower case, punctuation dropped, spaces to hyphens.
docs_heading_anchors <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  headings <- sub("^#+\\s+", "", grep("^#+\\s", lines, value = TRUE))
  anchors <- tolower(headings)
  anchors <- gsub("[^[:alnum:] _-]", "", anchors, perl = TRUE)
  gsub(" ", "-", anchors, fixed = TRUE)
}

docs_relative_links <- function(path) {
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  # Fenced code is not prose; a bracket in it is not a link.
  text <- gsub("(?s)```.*?```", "", text, perl = TRUE)
  targets <- regmatches(text, gregexpr("\\]\\(([^)\\s]+)\\)", text, perl = TRUE))[[1]]
  targets <- sub("^\\]\\((.*)\\)$", "\\1", targets)
  targets[!grepl("^(https?:|mailto:|#)", targets)]
}

test_that("every relative link in the documentation leads to a file and heading that exist", {
  root <- docs_root()
  # The release image carries no markdown; CI's R tests on the full checkout check this.
  testthat::skip_if_not(file.exists(file.path(root, "README.md")), "README.md is not here (release image)")
  files <- docs_files(root)
  expect_true(any(grepl("docs", files)), label = "the docs/ folder is read")
  broken <- character(0)
  for (f in files) {
    for (link in docs_relative_links(f)) {
      parts <- strsplit(link, "#", fixed = TRUE)[[1]]
      target <- normalizePath(file.path(dirname(f), parts[1]), mustWork = FALSE)
      if (!file.exists(target)) {
        broken <- c(broken, paste0(basename(f), ": ", link))
      } else if (length(parts) > 1 && grepl("[.]md$", target) &&
                 !(parts[2] %in% docs_heading_anchors(target))) {
        broken <- c(broken, paste0(basename(f), ": ", link, " (no such heading)"))
      }
    }
  }
  expect_equal(broken, character(0), label = "broken documentation links")
})

test_that("the link checker notices a missing file and a missing heading", {
  dir <- tempfile("docs-links-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  writeLines(c("# Running Atlas", "", "## Finishing a release"), file.path(dir, "running.md"))
  page <- file.path(dir, "page.md")
  writeLines(c("[ok](running.md#finishing-a-release) [gone](nowhere.md)",
               "[bad](running.md#no-such-part) [web](https://example.org)",
               "```", "[code](not-a-link.md)", "```"), page)
  expect_equal(docs_relative_links(page),
               c("running.md#finishing-a-release", "nowhere.md", "running.md#no-such-part"))
  expect_true("finishing-a-release" %in% docs_heading_anchors(file.path(dir, "running.md")))
  expect_false("no-such-part" %in% docs_heading_anchors(file.path(dir, "running.md")))
})
