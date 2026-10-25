# A pull's QA report and its hard stops (R/qa.R).

qa_pull <- function(n_inat = 100, n_mo = 50) {
  data.frame(
    id = as.character(seq_len(n_inat + n_mo)),
    source = c(rep("iNaturalist", n_inat), rep("MO Observations", n_mo)),
    observation_id = as.character(c(seq_len(n_inat), seq_len(n_mo) + 5000)),
    scientific_name = rep(c("Amanita muscaria", "Russula emetica"), length.out = n_inat + n_mo),
    stringsAsFactors = FALSE
  )
}

qa_privacy <- function(pull, centres = 2, unknown = 1) {
  mo <- pull[pull$source == "MO Observations", , drop = FALSE]
  data.frame(source = c(mo$source[seq_len(centres)], pull$source[seq_len(unknown)]),
             observation_id = c(mo$observation_id[seq_len(centres)], pull$observation_id[seq_len(unknown)]),
             privacy = c(rep("place", centres), rep("unknown", unknown)), stringsAsFactors = FALSE)
}

qa_audit <- function(disagree = 10, pulled = 1000) {
  list(pulled = pulled, by_status = data.frame(status = c("dna_name", "sequences_disagree"),
                                               records = c(pulled - disagree, disagree)))
}

report_of <- function(pull = qa_pull(), ..., previous = NULL) {
  atlas_qa_report(pull, list(stamp = "20261101T070000Z"), audit = qa_audit(), privacy = qa_privacy(pull),
                  previous = previous, ...)
}

test_that("a clean pull stops nothing, and the report holds counts and shares, never a record", {
  report <- report_of(kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = "Fungi"))
  expect_length(report$stops, 0L)
  expect_equal(report$records, 150L)
  expect_setequal(names(report$checks), c("kingdom", "keys", "place_centres", "uncached", "privacy_list", "naming", "sources"))
  text <- jsonlite::toJSON(report, auto_unbox = TRUE)
  expect_false(grepl("5001", text, fixed = TRUE))
  expect_false(grepl("latitude|longitude", text))
})

test_that("a modelled name of another kingdom stops the pull, unless it is allowed", {
  kingdoms <- c("Amanita muscaria" = "Fungi", "Russula emetica" = "Animalia")
  report <- report_of(kingdoms = kingdoms)
  expect_equal(unlist(report$stops), "kingdom")
  expect_match(report$checks$kingdom$why, "Russula emetica")
  expect_length(report_of(kingdoms = kingdoms, allow = "Russula emetica")$stops, 0L)
  # A name GBIF could not place is counted, not a stop.
  unknown <- report_of(kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = NA))
  expect_length(unknown$stops, 0L)
  expect_equal(unknown$checks$kingdom$detail$unknown, 1L)
})

test_that("two records under one source:number key stop the pull; one number in two sources does not", {
  pull <- qa_pull()
  pull$observation_id[pull$source == "MO Observations"][1] <- "1"
  expect_length(report_of(pull)$stops, 0L)
  expect_equal(report_of(pull)$checks$keys$detail$numbers_shared_across_sources, 1L)
  pull$observation_id[2] <- "1"
  expect_equal(unlist(report_of(pull)$stops), "keys")
})

test_that("MO records at named-place centres stop the pull above 10%, or when their share rises 2 points", {
  pull <- qa_pull()
  high <- atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull, centres = 6))
  expect_true("place_centres" %in% unlist(high$stops))
  low <- atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull, centres = 3))
  expect_false("place_centres" %in% unlist(low$stops))
  rose <- atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull, centres = 3),
                          previous = list(checks = list(place_centres = list(value = 0.02))))
  expect_true("place_centres" %in% unlist(rose$stops))
})

test_that("uncached records stop the pull above 5%; the privacy list shrinking more than 5% does too", {
  pull <- qa_pull()
  uncached <- atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull, unknown = 9))
  expect_true("uncached" %in% unlist(uncached$stops))
  shrank <- atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull),
                            previous = list(detail = list(privacy_list = 10)))
  expect_true("privacy_list" %in% unlist(shrank$stops))
})

test_that("disagreeing sequence names rising a point, a drop-list row, or a source moving stop the pull", {
  pull <- qa_pull()
  naming <- atlas_qa_report(pull, list(stamp = "x"), audit = qa_audit(disagree = 30),
                            previous = list(checks = list(naming = list(value = 0.01))))
  expect_true("naming" %in% unlist(naming$stops))
  dropped <- atlas_qa_report(pull, list(stamp = "x"), exclusions = c("7", "MO Observations:5003"))
  expect_equal(dropped$checks$drop_list$value, 2L)
  expect_true("drop_list" %in% unlist(dropped$stops))
  moved <- atlas_qa_report(pull, list(stamp = "x"),
                           previous = list(detail = list(by_source = list(iNaturalist = 100, "MO Observations" = 60))))
  expect_true("sources" %in% unlist(moved$stops))
  expect_match(moved$checks$sources$why, "MO Observations 60 -> 50")
})

test_that("nothing is planned from a stopped pull unless its stop is accepted by name, for that pull", {
  with_data_dir({
    atlas_write_json(list(stamp = "20261101T070000Z"), atlas_path("occurrences", "latest.json", create = TRUE))
    report <- list(pull = "20261101T070000Z", stops = list("kingdom"),
                   checks = list(kingdom = list(stop = TRUE, why = "1 modelled names are not fungi: Turdus")))
    expect_error(atlas_qa_gate(report = report, quiet = TRUE), "stopped its QA: 1 modelled names are not fungi")
    expect_error(atlas_qa_gate(accept = "20261031T070000Z:kingdom", report = report, quiet = TRUE), "stopped its QA")
    expect_error(atlas_qa_gate(accept = "20261101T070000Z:keys", report = report, quiet = TRUE), "stopped its QA")
    accepted <- atlas_qa_gate(accept = "20261101T070000Z:kingdom", report = report, quiet = TRUE)
    expect_equal(accepted$accepted, list("kingdom"))
    # A report of another pull is not this pull's.
    expect_length(atlas_qa_gate(report = list(pull = "older", stops = list("kingdom")), quiet = TRUE), 0L)
  })
})

test_that("a QA report is written beside each pull and read as the last one by the next", {
  with_data_dir({
    pull <- qa_pull()
    first <- atlas_pull_qa(pull, list(stamp = "a"), kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = "Fungi"),
                           quiet = TRUE)
    expect_true(file.exists(atlas_qa_path("a")))
    expect_true(file.exists(atlas_qa_path()))
    second <- atlas_pull_qa(pull[1:120, ], list(stamp = "b"), quiet = TRUE)
    expect_true("sources" %in% unlist(second$stops))
  })
})

test_that("kingdoms come from the cache, a new name is looked up once, and an unplaced one is asked again later", {
  with_data_dir({
    asked <- character()
    lookup <- function(name) { asked <<- c(asked, name); if (name == "Turdus migratorius") "Animalia" else NA_character_ }
    k <- atlas_name_kingdoms(c("Turdus migratorius", "Nonesuch fungus"), lookup = lookup, today = as.Date("2026-11-01"))
    expect_equal(unname(k), c(NA, "Animalia"))
    expect_setequal(asked, c("Turdus migratorius", "Nonesuch fungus"))
    asked <- character()
    atlas_name_kingdoms(c("Turdus migratorius", "Nonesuch fungus"), lookup = lookup, today = as.Date("2026-11-10"))
    expect_length(asked, 0L)
    atlas_name_kingdoms(c("Turdus migratorius", "Nonesuch fungus"), lookup = lookup, today = as.Date("2026-12-15"))
    expect_equal(asked, "Nonesuch fungus")
    # With no lookup allowed (max_new 0), nothing is asked.
    asked <- character()
    atlas_name_kingdoms("Brand new name", lookup = lookup, max_new = 0L)
    expect_length(asked, 0L)
  })
})

test_that("the nightly plans nothing from a pull that stopped its QA", {
  with_data_dir({
    atlas_write_json(list(stamp = "20261101T070000Z"), atlas_path("occurrences", "latest.json", create = TRUE))
    atlas_write_json(list(pull = "20261101T070000Z", stops = list("keys"),
                          checks = list(keys = list(stop = TRUE, why = "3 records share a source:number key"))),
                     atlas_qa_path())
    planned <- FALSE
    local_mocked_bindings(atlas_plan_job = function(...) { planned <<- TRUE; NULL },
                          atlas_finish_on_ec2 = function(...) NULL)
    expect_error(atlas_nightly(pull = FALSE, config = list(max_workers = 4), store = list(), quiet = TRUE),
                 "3 records share a source:number key")
    expect_false(planned)
  })
})
