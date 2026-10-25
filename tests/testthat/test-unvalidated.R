# Sequenced but not yet validated (R/unvalidated.R): counted beside the pull,
# shown on the taxon page, and never part of what a model is fitted on.

raw_counts <- function(...) {
  rows <- list(...)
  data.frame(
    taxon = vapply(rows, `[[`, "", 1),
    not_yet_validated = vapply(rows, function(r) as.character(r[[2]]), ""),
    with_coordinates = vapply(rows, function(r) as.character(r[[3]]), ""),
    stringsAsFactors = FALSE
  )
}

tsv_text <- function(df) {
  con <- textConnection("out", "w", local = TRUE)
  utils::write.table(df, con, sep = "\t", row.names = FALSE, quote = FALSE, na = "")
  close(con)
  paste(out, collapse = "\n")
}

test_that("two spellings of one taxon fold into its one count", {
  raw <- raw_counts(
    list("Gymnopilus hybridus", 20, 18),
    list("Gymnopilus hybridus (Fr.) Maire", 7, 7),
    list("Mycena sp. 'IN 10'", 2, 1),
    list("Mycena sp. 'IN_10'", 3, 3)
  )
  table <- atlas_unvalidated_table(raw, c("Gymnopilus hybridus", "Mycena sp. 'IN-10'"))
  expect_equal(table$taxon, c("Gymnopilus hybridus", "Mycena sp. 'IN-10'"))
  expect_equal(table$not_yet_validated, c(27L, 5L))
  expect_equal(table$with_coordinates, c(25L, 4L))
})

test_that("a taxon with none waiting has no row, and a spelling of no modelled taxon is dropped", {
  raw <- raw_counts(list("Rhodotus reticeps", 0, 0), list("Nobody knowsius", 9, 9),
                    list("Trametes versicolor", 23, 20))
  table <- atlas_unvalidated_table(raw, c("Rhodotus reticeps", "Trametes versicolor"))
  expect_equal(table$taxon, "Trametes versicolor")
  expect_equal(atlas_unvalidated_for(table, "Trametes versicolor"), 23L)
  expect_equal(atlas_unvalidated_for(table, "Rhodotus reticeps"), 0L)
  # No table at all means not counted yet, which is not the same as none.
  expect_null(atlas_unvalidated_for(NULL, "Trametes versicolor"))
  expect_equal(nrow(atlas_unvalidated_table(NULL, "Trametes versicolor")), 0L)
})

test_that("the count reads the backlog from .org's view of the mirror, not .org's validated observations", {
  # .org's observations holds validated records only, so counting records
  # with no verdict there read near zero; the backlog is in the mirror, which
  # .org's atlas.unvalidated_counts counts (deploy/readonly-sql/atlas-install.sh).
  sql <- atlas_unvalidated_sql()
  expect_match(sql, "FROM atlas.unvalidated_counts", fixed = TRUE)
  expect_false(grepl("observations", sql, fixed = TRUE))
  expect_false(grepl("validation_status", sql, fixed = TRUE))
  # The columns atlas_pull_unvalidated requires, by name.
  for (column in c("taxon", "not_yet_validated", "with_coordinates")) expect_match(sql, column, fixed = TRUE)
})

test_that("a pull's counts leave its fingerprint alone, and a failed count never fails the pull", {
  records <- synthetic_occurrences(c("Taxon A" = 12, "Taxon B" = 8))
  # Numeric, as .org's are: the pull's first-green query spans a page's id range.
  records$id <- as.character(seq_len(nrow(records)))
  pull_with <- function(counts) {
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
      if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
      # Each record's approved sequence names it as the record does.
      if (startsWith(sql, "SELECT o.id, s.species_name")) {
        return(tsv_text(data.frame(id = records$id, species_name = records$scientific_name)))
      }
      if (grepl("not_yet_validated", sql, fixed = TRUE)) {
        if (is.null(counts)) stop("the database went away")
        return(tsv_text(counts))
      }
      tsv_text(records)
    })
    atlas_pull_occurrences(host = "test", quiet = TRUE)
  }
  with_data_dir({
    first <- pull_with(raw_counts(list("Taxon A", 4, 4)))
    taxa_first <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
    expect_true(file.exists(atlas_unvalidated_raw_path()))

    second <- pull_with(raw_counts(list("Taxon A", 40, 31), list("Taxon B", 6, 6)))
    taxa_second <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
    expect_identical(second$fingerprint, first$fingerprint)
    expect_identical(taxa_second$fingerprint, taxa_first$fingerprint)
    expect_false("unvalidated" %in% names(second))

    expect_warning(third <- pull_with(NULL), "not-yet-validated counts not refreshed")
    expect_identical(third$fingerprint, first$fingerprint)
    # The last good counts stay until a count succeeds again.
    kept <- utils::read.delim(gzfile(atlas_unvalidated_raw_path()), colClasses = "character")
    expect_equal(kept$not_yet_validated, c("40", "6"))
  })
})

test_that("new counts publish a release and refit nothing", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  first <- full_cycle(store, boss)

  on_machine(boss, atlas_write_tsv_gz(raw_counts(list("Taxon A", 17, 15)), atlas_unvalidated_raw_path()))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_length(job$tasks, 0L)
  expect_equal(job$shards, 0L)
  second <- on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))

  expect_true("public/unvalidated.tsv.gz" %in% release_paths(second))
  for (path in grep("^models/", release_paths(first), value = TRUE)) {
    expect_identical(release_hash(second, path), release_hash(first, path), label = path)
  }
  table <- on_machine(boss, atlas_read_public_unvalidated())
  expect_equal(atlas_unvalidated_for(table, "Taxon A"), 17L)
})

test_that("a taxon's answer carries its count, and leaves it out before any are taken", {
  with_data_dir({
    atlas_write_json(data.frame(scientific_name = c("Taxon A", "Taxon B"), records = c(12L, 8L),
                                localities = c(12L, 8L), fingerprint = c("fa", "fb")),
                     atlas_path("occurrences", "taxa-latest.json"))
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      before <- jsonlite::fromJSON(call_api(test_api(c(ATLAS_DATA_DIR = atlas_data_dir())),
                                            "/api/taxa/Taxon%20A")$body)
      expect_false("not_yet_validated" %in% names(before))

      atlas_write_tsv_gz(atlas_unvalidated_table(raw_counts(list("Taxon A", 9, 7)), c("Taxon A", "Taxon B")),
                         atlas_public_unvalidated_path())
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      a <- jsonlite::fromJSON(call_api(api, "/api/taxa/Taxon%20A")$body)
      b <- jsonlite::fromJSON(call_api(api, "/api/taxa/Taxon%20B")$body)
      expect_equal(a$not_yet_validated, 9L)
      expect_equal(b$not_yet_validated, 0L)
      expect_equal(a$fingerprint, "fa")
    })
  })
})
