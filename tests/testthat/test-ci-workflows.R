# The workflows that publish images (.github/workflows): a production job's
# workers pull the image tagged with the orchestrator's commit (R/ec2.R), so
# only main's commits may carry a bare commit tag, and a study image only
# ever its own study-<sha> tag. Run where the repository is checked out (CI's
# R tests); the image leaves .github out, so there it is skipped.

workflow_lines <- function(name) {
  path <- testthat::test_path("..", "..", ".github", "workflows", name)
  testthat::skip_if_not(file.exists(path), "no .github here (inside the image)")
  readLines(path, warn = FALSE)
}

test_that("the study image is built by hand only, for a validated full SHA, and pushed as study-<sha> alone", {
  lines <- workflow_lines("study-image.yml")
  text <- paste(lines, collapse = "\n")
  on_block <- sub("\njobs:.*$", "", sub("^.*\non:\n", "", text))
  expect_match(on_block, "workflow_dispatch:", fixed = TRUE)
  expect_false(grepl("push:|pull_request|schedule|workflow_run", on_block))
  # The input reaches a shell only through the environment, after it is
  # checked as a full SHA, and is the commit checked out.
  uses <- grep("${{ inputs.commit }}", lines, fixed = TRUE, value = TRUE)
  expect_setequal(trimws(uses), c("COMMIT: ${{ inputs.commit }}", "ref: ${{ inputs.commit }}"))
  check <- grep("^[[:space:]]*if ! \\[\\[ \"\\$COMMIT\" =~ \\^\\[0-9a-f\\]\\{40\\}\\$ \\]\\]", lines)
  checkout <- grep("actions/checkout@", lines)
  expect_length(check, 1L)
  expect_lt(check, checkout)
  expect_match(text, 'test "$(git rev-parse HEAD)" = "$COMMIT"', fixed = TRUE)
  # One push, of the study tag, and no other tag anywhere.
  expect_length(grep("docker push", lines, fixed = TRUE), 1L)
  expect_match(text, 'image="ghcr.io/${GITHUB_REPOSITORY,,}:study-$COMMIT"', fixed = TRUE)
  expect_false(grepl(":latest|:main\\b|:\\$GITHUB_SHA|:\\$COMMIT\"", text))
  expect_match(text, "packages: write", fixed = TRUE)
})

test_that("only main's commits get the bare commit tag production workers pull", {
  text <- paste(workflow_lines("ci.yml"), collapse = "\n")
  expect_match(text, "if: github.event_name == 'push' && github.ref == 'refs/heads/main'", fixed = TRUE)
  expect_match(text, 'image="ghcr.io/${GITHUB_REPOSITORY,,}:$GITHUB_SHA"', fixed = TRUE)
  expect_false(grepl("workflow_dispatch", text, fixed = TRUE))
})
