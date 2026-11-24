# /api/status says whether the nightly's pull QA is letting pulls through
# (R/qa.R): state ok or stopped and, when stopped, the stopped pull's stamp,
# since when, how many pulls have stopped, and the stopped checks' names.
# Check names, stamps and counts only.

# One night's QA report, written as atlas_pull_qa writes it: dated and as
# qa-latest.json. why and detail carry free text, as real reports do.
qa_night <- function(stamp, stops = character()) {
  checks <- list(sources = list(stop = "sources" %in% stops, value = 1L,
                                why = "records by source moved past their limits: Amanita muscaria 31 -> 50",
                                detail = list(below_floor = list("Sequences 61 -> 43"))),
                 kingdom = list(stop = "kingdom" %in% stops, value = 0L,
                                why = "1 modelled names are neither fungi nor slime moulds: Turdus migratorius",
                                detail = list(other = list("Turdus migratorius"))))
  report <- list(pull = stamp, records = 150L, taxa = 2L, checks = checks, stops = as.list(stops),
                 detail = list(by_source = list(iNaturalist = 100L)))
  atlas_write_json(report, atlas_qa_path(stamp))
  atlas_write_json(report, atlas_qa_path())
  invisible(report)
}

pull_qa_of <- function() {
  manifest <- list(stamp = "20261120T070525Z", pulled_at = "2026-11-20T07:13:52Z", records = 150L, taxa = 2L)
  atlas_write_json(manifest, atlas_path("occurrences", "latest.json", create = TRUE))
  api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
  answer <- call_api(api, "/api/status")
  expect_equal(answer$status, 200L)
  body <- jsonlite::fromJSON(answer$body, simplifyVector = FALSE)
  if (is.null(body$pullQa)) return(NULL)
  structure(body$pullQa, raw = answer$body)
}

test_that("the status has no pull QA block until a QA report exists, and ok when the pull passed", {
  with_data_dir({
    expect_null(pull_qa_of())
    qa_night("20261120T070525Z")
    expect_equal(pull_qa_of()$state, "ok")
    # No baseline yet, and the pull passed: ok.
    expect_false(file.exists(atlas_qa_baseline_path()))
  })
})

test_that("a stopped pull shows as stopped on its first night and counts the nights after", {
  with_data_dir({
    report <- qa_night("20261120T070525Z")
    atlas_qa_write_baseline(report)
    qa_night("20261121T070500Z", stops = "sources")
    first <- pull_qa_of()
    expect_equal(first$state, "stopped")
    expect_equal(first$pull, "20261121T070500Z")
    expect_equal(first$since, "2026-11-21T07:05:00Z")
    expect_equal(first$nights, 1L)
    expect_equal(first$checks, list("sources"))
    qa_night("20261122T070500Z", stops = c("sources", "kingdom"))
    qa_night("20261123T070500Z", stops = c("sources", "kingdom"))
    later <- pull_qa_of()
    expect_equal(later$pull, "20261123T070500Z")
    expect_equal(later$since, "2026-11-21T07:05:00Z")
    expect_equal(later$nights, 3L)
    expect_setequal(unlist(later$checks), c("sources", "kingdom"))
  })
})

test_that("an accepted stop, or the first passing night, shows as ok", {
  with_data_dir({
    atlas_qa_write_baseline(qa_night("20261120T070525Z"))
    stopped <- qa_night("20261121T070500Z", stops = "sources")
    expect_equal(pull_qa_of()$state, "stopped")
    atlas_qa_write_baseline(stopped, accepted = "sources")
    expect_equal(pull_qa_of()$state, "ok")
    qa_night("20261122T070500Z", stops = "sources")
    expect_equal(pull_qa_of()$nights, 1L)
    qa_night("20261123T070500Z")
    expect_equal(pull_qa_of(), list(state = "ok"), ignore_attr = TRUE)
  })
})

test_that("with no baseline yet, the stopped run is counted back to the last pull that passed", {
  with_data_dir({
    qa_night("20261120T070525Z")
    qa_night("20261121T070500Z", stops = "kingdom")
    qa_night("20261122T070500Z", stops = "kingdom")
    block <- pull_qa_of()
    expect_equal(block$state, "stopped")
    expect_equal(block$nights, 2L)
    expect_equal(block$since, "2026-11-21T07:05:00Z")
  })
})

test_that("the block holds check names, stamps and counts, and nothing from a report's text or details", {
  with_data_dir({
    atlas_qa_write_baseline(qa_night("20261120T070525Z"))
    qa_night("20261121T070500Z", stops = c("sources", "kingdom"))
    block <- pull_qa_of()
    expect_setequal(names(block), c("state", "pull", "since", "nights", "checks"))
    raw <- attr(block, "raw")
    for (text in c("Turdus", "Amanita", "Sequences", "iNaturalist", "moved past", "below_floor", "why", "detail")) {
      expect_false(grepl(text, raw, fixed = TRUE), info = text)
    }
    # A check name that is not a plain identifier is left out, not served.
    qa_night("20261122T070500Z", stops = c("sources", "Turdus migratorius"))
    expect_equal(pull_qa_of()$checks, list("sources"))
  })
})
