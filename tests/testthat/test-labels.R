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

test_that("by default a record with no approved named sequence is left out", {
  # Steve, 2026-10-11: only a name the DNA gives is modelled.
  out <- atlas_dna_names("Amanita muscaria", list(character()))
  expect_true(is.na(out$name))
  expect_equal(out$status, ATLAS_LABEL_NONE)
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
  # One arm per source, each joined on a plain key the index can use.
  for (source in names(ATLAS_SEQUENCE_KEY_PREFIXES)) {
    expect_match(sql, sprintf("JOIN sequences s ON s.observation = '%s:' || o.observation_id WHERE o.source = '%s' AND",
                              ATLAS_SEQUENCE_KEY_PREFIXES[[source]], source), fixed = TRUE)
  }
  expect_false(grepl("CASE", sql, fixed = TRUE))
  expect_match(sql, "JOIN linked_observations l ON l.database_id = 43 AND l.external_id = o.observation_id",
               fixed = TRUE)
  expect_match(sql, "JOIN sequences s ON s.com_inat_record_id = l.record_id WHERE o.source = 'iNaturalist' AND",
               fixed = TRUE)
  expect_true(startsWith(sql, "SELECT o.id, s.species_name FROM observations o JOIN sequences s ON s.observation = 'inat:'"))
  arms <- length(ATLAS_SEQUENCE_KEY_PREFIXES) + 1L
  count <- function(text) lengths(regmatches(sql, gregexpr(text, sql, fixed = TRUE)))
  # Approved, named sequences of green records in the page only, on every arm.
  expect_equal(count("s.approved = 1"), arms)
  # Never a sequence from the trash, on any arm.
  expect_equal(count("coalesce(s.category_id, 0) <> 169"), arms)
  # Nor one .com flags as a contaminant (non-target), set as true or 1.
  expect_equal(count("coalesce(s.flags ->> 'contaminant', '') NOT IN ('true', '1')"), arms)
  # Nor one flagged as on the wrong observation or specimen.
  expect_equal(count("coalesce(s.flags ->> 'wrong', '') NOT IN ('true', '1')"), arms)
  expect_equal(count("btrim(coalesce(s.species_name, '')) <> ''"), arms)
  expect_equal(count("o.id >= 100 AND o.id <= 200"), arms)
  expect_equal(count("'yes' IN (coalesce(o.validation_status_1, '')"), arms)
  expect_equal(count(" UNION "), arms - 1L)
  expect_false(grepl("UNION ALL", sql, fixed = TRUE))
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
    # The first-green side query (R/firstgreen.R): no validations here.
    if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
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

test_that("a section, a rank word or a name that is no taxon is not modelled; a species or a code is", {
  rank <- c("Amanita sect. Vaginatae", "Gymnopus subsect. Levipedes", "Entoloma subg. Claudopus", "Subgenus Lentoramaria",
            "Family Porotheleaceae", "Complex Pluteus glaucotinctus")
  taxon <- c("NA sample mixup", "sample mixup", "sequence mixup", "sample mix-up", "uncultured fungus", "Billie Jean",
             "Amanita Pers.", "Suillus Gray")
  expect_true(all(atlas_not_species(rank) == ATLAS_NOT_SPECIES_RANK))
  expect_true(all(atlas_not_species(taxon) == ATLAS_NOT_SPECIES_TAXON))
  expect_false(any(atlas_modelled_name(c(rank, taxon))))
  # Real names that look close to these stay, and so do the forms Atlas models.
  keep <- c("Amanita muscaria", "Mycena sp. 'IN10'", "Amanita muscaria var. guessowii", "Russula sp. 'section-IN01'",
            "Cortinarius Harrower135", "Lactarius subvernalis var. cokeri", "Agaricus approximans group",
            "Ganoderma multipileum complex", "Sectionis nomen", "Familia nova", "Conocybe sp. 'semiglobata-clade-4'")
  expect_true(all(atlas_modelled_name(keep)))
  expect_true(all(is.na(atlas_not_species(keep))))
  # What was never modelled still is not, and the older test is unchanged.
  expect_false(any(atlas_modelled_name(c("Mycena sp.", "Mycena", "Fungi", "Unknown", "", NA))))
  # E9 read the frozen pull as registered: its own test of a label does not move.
  expect_true(atlas_species_level("Amanita sect. Vaginatae"))
  expect_true(atlas_e9_modelled("Amanita sect. Vaginatae"))
})

test_that("a pull leaves out names that are no species, and its labels audit counts them by name", {
  page <- transform(fake_occurrences(), id = c("1", "2", "3"), scientific_name = "Amanita muscaria")
  names <- data.frame(id = c("1", "2", "3"), species_name = c("Amanita muscaria", "Amanita sect. Vaginatae", "sample mixup"))
  text <- function(df) paste(c(paste(names(df), collapse = "\t"), do.call(paste, c(df, sep = "\t"))), collapse = "\n")
  testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
    if (startsWith(sql, "SELECT o.id, s.species_name")) return(text(names))
    if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
    text(page)
  })
  with_data_dir({
    suppressWarnings(atlas_pull_occurrences(quiet = TRUE, host = "test"))
    pulled <- atlas_read_occurrences()
    expect_equal(pulled$scientific_name, "Amanita muscaria")
    audit <- jsonlite::fromJSON(atlas_label_audit_path())
    expect_equal(audit$pulled, 3L)
    expect_equal(audit$modelled, 1L)
    expect_equal(audit$not_species$records, 2L)
    expect_equal(audit$not_species$names$name, c("Amanita sect. Vaginatae", "sample mixup"))
    expect_equal(audit$not_species$names$why, c(ATLAS_NOT_SPECIES_RANK, ATLAS_NOT_SPECIES_TAXON))
    expect_equal(audit$not_species$names$records, c(1L, 1L))
    # None of it is a stop, and none of it is in the taxa the site reads.
    expect_false("Amanita sect. Vaginatae" %in% jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))$scientific_name)
  })
  # A pull with none says so.
  empty <- atlas_label_audit(data.frame(name_status = ATLAS_LABEL_SAME, source = "iNaturalist", scientific_name = "Amanita muscaria",
                                        record_name = "Amanita muscaria", stringsAsFactors = FALSE))
  expect_equal(empty$not_species$records, 0L)
  expect_equal(nrow(empty$not_species$names), 0L)
})
