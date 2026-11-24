# A pull is compared with the baseline: the last pull the QA gate let through,
# stopping nothing or with its stops accepted by name (R/qa.R; Steve,
# 2026-11-23). A stopped pull's change stays a stop every night until someone
# accepts it, instead of becoming the next night's baseline by itself.

kingdoms_ok <- c("Amanita muscaria" = "Fungi", "Russula emetica" = "Fungi")

# One night's pull: its manifest is the current pull, and its QA report is
# written as the nightly writes it.
night <- function(stamp, n_mo = 100) {
  atlas_write_json(list(stamp = stamp), atlas_path("occurrences", "latest.json", create = TRUE))
  atlas_pull_qa(qa_pull(n_mo = n_mo), list(stamp = stamp), kingdoms = kingdoms_ok, quiet = TRUE)
}

baseline <- function() jsonlite::fromJSON(atlas_qa_baseline_path(), simplifyVector = TRUE)

test_that("a stopped pull's change stays a stop every night after, until it is accepted", {
  with_data_dir({
    night("a")
    atlas_qa_gate(quiet = TRUE)
    expect_equal(baseline()$pull, "a")
    # MO 100 -> 160: past 15% and 60 records, so a stop.
    b <- night("b", n_mo = 160)
    expect_true("sources" %in% unlist(b$stops))
    expect_error(atlas_qa_gate(quiet = TRUE), "stopped its QA")
    expect_equal(baseline()$pull, "a")
    # The next night holds the same records. Compared with the stopped pull it
    # would pass; compared with the baseline it stops again.
    c <- night("c", n_mo = 160)
    expect_equal(c$compared_with, list(pull = "a", file = "qa-baseline.json"))
    expect_true("sources" %in% unlist(c$stops))
    expect_error(atlas_qa_gate(quiet = TRUE), "accept-qa --accept-qa=c:sources")
  })
})

test_that("a stop accepted by name becomes the baseline, and the next night passes and is planned", {
  with_data_dir({
    night("a")
    atlas_qa_gate(quiet = TRUE)
    night("b", n_mo = 160)
    accepted <- atlas_qa_accept("b:sources", quiet = TRUE)
    expect_equal(accepted$accepted, list("sources"))
    expect_equal(baseline()$pull, "b")
    expect_equal(baseline()$baseline$accepted, "sources")
    c <- night("c", n_mo = 160)
    expect_equal(c$compared_with$pull, "b")
    expect_length(unlist(c$stops), 0L)
    planned <- FALSE
    local_mocked_bindings(atlas_plan_job = function(...) { planned <<- TRUE; NULL },
                          atlas_finish_on_ec2 = function(...) NULL)
    atlas_nightly(pull = FALSE, config = list(max_workers = 4), store = list(), quiet = TRUE)
    expect_true(planned)
    expect_equal(baseline()$pull, "c")
  })
})

test_that("planning past a stop by name makes that pull the baseline too", {
  with_data_dir({
    night("a")
    atlas_qa_gate(quiet = TRUE)
    night("b", n_mo = 160)
    atlas_qa_gate(accept = "b:sources", quiet = TRUE)
    expect_equal(baseline()$pull, "b")
    expect_equal(baseline()$baseline$accepted, "sources")
  })
})

test_that("accepting refuses another pull's stamp, a stop left unnamed, and a pull that stopped nothing", {
  with_data_dir({
    night("a")
    expect_error(atlas_qa_accept("a:sources", quiet = TRUE), "stopped nothing")
    atlas_qa_gate(quiet = TRUE)
    night("b", n_mo = 160)
    expect_error(atlas_qa_accept("a:sources", quiet = TRUE), "stopped its QA")
    expect_error(atlas_qa_accept("b:keys", quiet = TRUE), "stopped its QA")
    expect_error(atlas_qa_accept(NULL, quiet = TRUE), "needs --accept-qa")
    expect_equal(baseline()$pull, "a")
  })
})

test_that("a pull with no report of its own leaves the baseline as it was", {
  with_data_dir({
    night("a")
    atlas_qa_gate(quiet = TRUE)
    atlas_write_json(list(stamp = "b"), atlas_path("occurrences", "latest.json", create = TRUE))
    expect_length(atlas_qa_gate(quiet = TRUE), 0L)
    expect_equal(baseline()$pull, "a")
  })
})

test_that("MyCoPortal records moving between its two labels are no change; a real rise still stops", {
  portal <- function(n, label) {
    data.frame(id = paste0(label, seq_len(n)), source = rep(label, n), observation_id = paste0(label, seq_len(n)),
               scientific_name = "Amanita muscaria", stringsAsFactors = FALSE)
  }
  pull <- rbind(qa_pull(), portal(371, "MyCoPortal"))
  # 300 records were labelled the other way at the baseline: the same 371 in all.
  moved <- atlas_qa_report(pull, list(stamp = "x"), previous = list(detail = list(by_source = list(
    iNaturalist = 100, "MO Observations" = 50, MycoPortal = 300, MyCoPortal = 71))))
  expect_false("sources" %in% unlist(moved$stops))
  # Each label's own count stays in the report.
  expect_equal(moved$detail$by_source$MyCoPortal, 371L)
  # A real rise across both labels, past 15% and 50 records, still stops.
  rose <- atlas_qa_report(rbind(qa_pull(), portal(466, "MyCoPortal"), portal(54, "MycoPortal")), list(stamp = "x"),
                          previous = list(detail = list(by_source = list(
                            iNaturalist = 100, "MO Observations" = 50, MycoPortal = 54, MyCoPortal = 317))))
  expect_true("sources" %in% unlist(rose$stops))
  expect_match(rose$checks$sources$why, "MyCoPortal 371 -> 520")
})
