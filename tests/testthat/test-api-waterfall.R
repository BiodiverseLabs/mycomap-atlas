# Where mycomap.org's records went before the pull kept them (the Methods
# page's "Where the records go"). /api/status serves the pull's waterfall only
# when every bar adds up: total less every step is used, and each step's parts
# make its count. A wrong bar is worse than none, so anything else is left out.

waterfall <- function() {
  list(
    version = 1L, total = 1000L, pulled = 900L, used = 850L, max_accuracy_m = 1000L,
    pulled_at = "2026-11-20T07:13:52Z", adds_up = TRUE,
    steps = list(
      list(id = "dna", removed = 60L),
      list(id = "coordinates", removed = 10L),
      list(id = "other_coarse", removed = 30L, parts = list(
        list(id = "mo_place_centre", count = 25L), list(id = "mo_deleted", count = 5L)
      )),
      list(id = "name", removed = 45L, parts = list(
        list(id = "disagree", count = 40L), list(id = "no_named_sequence", count = 5L),
        list(id = "genus_only", count = 0L)
      )),
      list(id = "excluded", removed = 5L)
    )
  )
}

status_with <- function(w, where = "latest") {
  with_data_dir({
    manifest <- list(stamp = "20261120T070525Z", pulled_at = "2026-11-20T07:13:52Z", records = 850L, taxa = 10L)
    if (!is.null(w)) manifest$waterfall <- w
    path <- if (identical(where, "latest")) atlas_path("occurrences", "latest.json") else atlas_public_pull_path()
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    atlas_write_json(manifest, path)
    api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
    answer <- call_api(api, "/api/status")
    expect_equal(answer$status, 200L)
    jsonlite::fromJSON(answer$body, simplifyVector = FALSE)
  })
}

test_that("the status serves the pull's waterfall when every bar adds up", {
  served <- status_with(waterfall())$waterfall
  expect_false(is.null(served))
  expect_equal(served$total, 1000L)
  expect_equal(served$used, 850L)
  expect_equal(served$max_accuracy_m, 1000L)
  expect_equal(served$pulled_at, "2026-11-20T07:13:52Z")
  expect_equal(vapply(served$steps, function(s) s$id, ""), c("dna", "coordinates", "other_coarse", "name", "excluded"))
  # Total less every step is exactly the records used.
  expect_equal(served$total - sum(vapply(served$steps, function(s) s$removed, 0)), served$used)
  # A part of 0 stays a part, and parts stay a list even when there is one.
  expect_equal(vapply(served$steps[[4]]$parts, function(p) p$count, 0), c(40, 5, 0))
  # Counts only: the reference count and the pull's own flag stay behind.
  expect_null(served[["pulled"]])
  expect_null(served[["adds_up"]])
})

test_that("a release's pull summary serves it too, where this machine made no pull", {
  expect_equal(status_with(waterfall(), where = "public")$waterfall$used, 850L)
})

test_that("a waterfall whose steps do not reach the records used is left out", {
  w <- waterfall()
  w$used <- 851L
  status <- status_with(w)
  expect_null(status$waterfall)
  # The rest of the status is untouched.
  expect_equal(status$records, 850L)
})

test_that("a step whose parts do not make its count is left out", {
  w <- waterfall()
  w$steps[[3]]$parts[[2]]$count <- 4L
  expect_null(status_with(w)$waterfall)
})

test_that("a waterfall the pull did not vouch for is left out", {
  w <- waterfall()
  w$adds_up <- FALSE
  expect_null(status_with(w)$waterfall)
  expect_null(status_with(list(skipped = "not a full pull"))$waterfall)
  expect_null(status_with(list(error = "a count failed"))$waterfall)
  expect_null(status_with(NULL)$waterfall)
})

test_that("another version, a negative or fractional count, or a strange id is left out", {
  w <- waterfall(); w$version <- 2L
  expect_null(atlas_waterfall_checked(w))
  w <- waterfall(); w$steps[[1]]$removed <- -60L; w$used <- 970L
  expect_null(atlas_waterfall_checked(w))
  w <- waterfall(); w$steps[[2]]$removed <- 10.5
  expect_null(atlas_waterfall_checked(w))
  w <- waterfall(); w$steps[[1]]$id <- "DNA; drop"
  expect_null(atlas_waterfall_checked(w))
  expect_false(is.null(atlas_waterfall_checked(waterfall())))
})
