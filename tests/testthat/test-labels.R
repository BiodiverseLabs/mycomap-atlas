test_that("a record is named by its approved sequences, not its record name", {
  # Vision's 2026-10-08 finding: record names lag the sequences.
  out <- atlas_dna_names(
    c("Tubaria sp. 'IN01'", "Leucoagaricus leucothites", "Amanita muscaria"),
    list("Tubaria hiemalis", "Leucocoprinus leucothites", "Amanita muscaria")
  )
  expect_equal(out$name, c("Tubaria hiemalis", "Leucocoprinus leucothites", "Amanita muscaria"))
  expect_equal(out$status, c(ATLAS_LABEL_OTHER_SPECIES, ATLAS_LABEL_OTHER_GENUS, ATLAS_LABEL_SAME))
})

test_that("spellings of one sequence name are one name, and the record keeps the DNA's spelling", {
  out <- atlas_dna_names(c("Mycena sp. 'IN10'", "Mycena sp. 'IN10'"),
                         list(c("Mycena \"sp-IN10\"", "Mycena sp. 'IN10'"), "Mycena \"sp-IN10\""))
  expect_false(anyNA(out$name))
  expect_equal(out$status[[1]], ATLAS_LABEL_SAME)
  expect_equal(out$status[[2]], ATLAS_LABEL_SPELLING)
  expect_equal(out$name[[2]], "Mycena \"sp-IN10\"")
})

test_that("sequences that name two species leave the record out", {
  out <- atlas_dna_names("Russula variata", list(c("Russula variata", "Russula sp. 'IN67'")))
  expect_true(is.na(out$name))
  expect_equal(out$status, ATLAS_LABEL_DISAGREE)
})

test_that("a one-word sequence name leaves a species-named record out", {
  # The DNA settles the genus only; Atlas models species.
  out <- atlas_dna_names("Hymenoscyphus sp. 'BC02'", list("Mycena"))
  expect_true(is.na(out$name))
  expect_equal(out$status, ATLAS_LABEL_SEQUENCE_GENUS)
})

test_that("a genus-only record whose sequence names a species is modelled under the species", {
  out <- atlas_dna_names(c("Polyporales", NA), list("Trametes gibbosa", "Trametes gibbosa"))
  expect_equal(out$name, c("Trametes gibbosa", "Trametes gibbosa"))
  expect_equal(out$status, rep(ATLAS_LABEL_RECORD_GENUS, 2))
})

test_that("a record with no approved named sequence is kept or dropped as configured", {
  kept <- atlas_dna_names("Amanita muscaria", list(character()), no_sequence = "keep")
  dropped <- atlas_dna_names("Amanita muscaria", list(c("", NA)), no_sequence = "drop")
  expect_equal(kept$name, "Amanita muscaria")
  expect_true(is.na(dropped$name))
  expect_equal(c(kept$status, dropped$status), rep(ATLAS_LABEL_NONE, 2))
  expect_error(atlas_dna_names("x y", list("x y"), no_sequence = "maybe"))
})

test_that("only species-level names are modelled", {
  expect_equal(
    atlas_species_level(c("Amanita muscaria", "Mycena sp. 'IN10'", "Mycena sp.", "Mycena sp",
                          "Mycena", "Fungi", "Unknown", "", NA)),
    c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE)
  )
})

test_that("sequence names come from the record's key and, for iNat, from its linked .com records", {
  sql <- atlas_sequence_names_sql(100, 200)
  expect_match(sql, "JOIN sequences s ON s.observation = (CASE o.source WHEN 'iNaturalist' THEN 'inat'",
               fixed = TRUE)
  expect_match(sql, "WHEN 'MO Observations' THEN 'mo'", fixed = TRUE)
  expect_match(sql, "END || ':' || o.observation_id)", fixed = TRUE)
  expect_match(sql, "JOIN linked_observations l ON l.database_id = 43 AND l.external_id = o.observation_id",
               fixed = TRUE)
  expect_match(sql, "JOIN sequences s ON s.com_inat_record_id = l.record_id", fixed = TRUE)
  # Approved, named sequences of green records in the page only, on both arms.
  expect_equal(lengths(regmatches(sql, gregexpr("s.approved = 1", sql, fixed = TRUE))), 2L)
  expect_equal(lengths(regmatches(sql, gregexpr("o.id >= 100 AND o.id <= 200", sql, fixed = TRUE))), 2L)
  expect_match(sql, "'yes' IN (coalesce(o.validation_status_1, '')", fixed = TRUE)
  expect_false(grepl("\n", sql))
  expect_false(grepl("\"", sql, fixed = TRUE))
  expect_false(grepl("%", sql, fixed = TRUE))
})

test_that("the pull names records by their sequences and leaves out what the DNA does not settle", {
  dir <- withr::local_tempdir()
  withr::local_envvar(ATLAS_DATA_DIR = dir)
  page <- fake_occurrences()
  page$scientific_name <- c("Tubaria sp. 'IN01'", "Russula variata", "Polyporales")
  names <- data.frame(
    id = c("1", "2", "2", "3"),
    species_name = c("Tubaria hiemalis", "Russula variata", "Russula sp. 'IN67'", "Trametes gibbosa"),
    stringsAsFactors = FALSE
  )
  tsv <- function(df) {
    paste(c(paste(names(df), collapse = "\t"),
            do.call(paste, c(unname(as.list(df)), sep = "\t"))), collapse = "\n")
  }
  testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
    if (startsWith(sql, "SELECT o.id, s.species_name")) return(tsv(names))
    tsv(page)
  })
  atlas_pull_occurrences(quiet = TRUE, host = "test")
  pulled <- atlas_read_occurrences()
  expect_equal(sort(pulled$scientific_name), c("Trametes gibbosa", "Tubaria hiemalis"))
  expect_equal(pulled$record_name[pulled$id == "1"], "Tubaria sp. 'IN01'")
  audit <- jsonlite::fromJSON(atlas_label_audit_path())
  expect_equal(audit$pulled, 3L)
  expect_equal(audit$modelled, 2L)
  counts <- stats::setNames(audit$by_status$records, audit$by_status$status)
  expect_equal(unname(counts[ATLAS_LABEL_DISAGREE]), 1L)
  expect_equal(audit$changes$dna_name, "Tubaria hiemalis")
  taxa <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
  expect_false("Tubaria sp. 'IN01'" %in% taxa$scientific_name)
})
