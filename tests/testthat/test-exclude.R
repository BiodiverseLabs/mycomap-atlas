# The box's drop list: rows Atlas leaves out of the current pull and every
# later one, and a plan on the cleaned pull refits only what changed.

# As test-unvalidated.R makes them: a canned SQL answer and count rows.
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

# A pull with the 2026-10-13 case in small: Clitocybe deceptiva with one
# bogus row (.org id 202906, iNaturalist 489483), a mallard that exists only
# by a bogus row, and an MO record that shares the bogus row's number.
exclude_pull <- function() {
  occ <- synthetic_occurrences(c("Clitocybe deceptiva" = 30, "Taxon B" = 25, "Anas platyrhynchos" = 1))
  occ$id <- as.character(200000L + seq_len(nrow(occ)))
  c1 <- which(occ$scientific_name == "Clitocybe deceptiva")[1]
  occ$id[c1] <- "202906"
  occ$observation_id[c1] <- "489483"
  bird <- which(occ$scientific_name == "Anas platyrhynchos")
  occ$id[bird] <- "202862"
  occ$observation_id[bird] <- "519965"
  mo <- which(occ$scientific_name == "Taxon B")[1]
  occ$source[mo] <- "MO Observations"
  occ$observation_id[mo] <- "489483"
  occ$first_green_on <- "2026-05-01"
  occ
}

test_that("a listed row is left out of the pull and nothing else changes", {
  with_data_dir({
    orchestrator_data(exclude_pull())
    before <- atlas_read_manifest()
    frozen <- atlas_path("occurrences", before$file)
    frozen_sha <- atlas_sha256(frozen)
    rows <- atlas_read_occurrences()
    out <- atlas_exclude_records("202906, 202862, 175024", quiet = TRUE, reason = "bogus iNat link")
    after <- atlas_read_manifest()
    cleaned <- atlas_read_occurrences()
    # Exactly the two listed rows in the pull are gone; every other row is
    # as it was, column for column.
    expect_equal(out$removed, 2L)
    expect_setequal(unlist(out$removed_ids), c("202906", "202862"))
    expect_equal(unlist(out$not_in_pull), "175024")
    expected <- rows[!rows$id %in% c("202906", "202862"), , drop = FALSE]
    rownames(expected) <- NULL
    expect_identical(cleaned, expected)
    # The MO record numbered 489483 too is still there.
    expect_true(any(cleaned$source == "MO Observations" & cleaned$observation_id == "489483"))
    # The mallard's name is gone from the taxa summary; the pull it was made
    # from is untouched and named, and the pull's time is its own.
    taxa <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
    expect_false("Anas platyrhynchos" %in% taxa$scientific_name)
    expect_equal(unlist(out$names_gone), "Anas platyrhynchos")
    expect_identical(atlas_sha256(frozen), frozen_sha)
    expect_equal(after$from_sha256, frozen_sha)
    expect_equal(after$from_file, before$file)
    expect_equal(after$pulled_at, before$pulled_at)
    expect_false(identical(after$file, before$file))
    expect_equal(after$records, before$records - 2L)
    expect_equal(after$exclusions$removed, 2L)
    expect_equal(after$exclusions$sha256, atlas_sha256(atlas_exclude_path()))
  })
})

test_that("a row named by source and number is that source's only", {
  with_data_dir({
    orchestrator_data(exclude_pull())
    out <- atlas_exclude_records("iNaturalist:489483", by = "source_observation", quiet = TRUE)
    cleaned <- atlas_read_occurrences()
    expect_equal(out$removed, 1L)
    expect_false("202906" %in% cleaned$id)
    expect_true(any(cleaned$source == "MO Observations" & cleaned$observation_id == "489483"))
    expect_error(atlas_exclude_records("489483", by = "observation_id", quiet = TRUE), "should be one of")
  })
})

test_that("every pull applies the drop list until it is cleared, deliberately", {
  records <- exclude_pull()
  pull <- function() {
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
      if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
      if (startsWith(sql, "SELECT o.id, s.species_name")) {
        return(tsv_text(data.frame(id = records$id, species_name = records$scientific_name)))
      }
      if (grepl("not_yet_validated", sql, fixed = TRUE)) return(tsv_text(raw_counts(list("Taxon B", 1, 1))))
      if (grepl("max(id)", sql, fixed = TRUE)) return("top\n1\n")
      if (grepl("AS privacy", sql, fixed = TRUE)) return("source\tobservation_id\tprivacy\n")
      tsv_text(records[, setdiff(names(records), "first_green_on")])
    })
    atlas_pull_occurrences(host = "test", quiet = TRUE)
  }
  with_data_dir({
    first <- pull()
    expect_equal(first$exclusions$list, "none")
    expect_true("202906" %in% atlas_read_occurrences()$id)
    orchestrator_data(atlas_read_occurrences())
    atlas_exclude_records(c("202906", "202862"), quiet = TRUE)
    # A fresh pull brings the rows back from .org, and the list takes them out.
    second <- pull()
    expect_false(any(c("202906", "202862") %in% atlas_read_occurrences()$id))
    expect_equal(second$exclusions$removed, 2L)
    expect_equal(second$exclusions$sha256, atlas_sha256(atlas_exclude_path()))
    expect_equal(second$records, first$records - 2L)
    # Clearing is a deliberate step, and the list is kept, retired.
    expect_error(atlas_clear_exclusions(), "--confirm")
    expect_true(file.exists(atlas_exclude_path()))
    atlas_clear_exclusions(confirm = TRUE, quiet = TRUE)
    expect_false(file.exists(atlas_exclude_path()))
    expect_length(list.files(atlas_path("occurrences"), pattern = "^exclude-cleared-"), 1L)
    third <- pull()
    expect_equal(third$exclusions$list, "none")
    expect_true("202906" %in% atlas_read_occurrences()$id)
  })
})

test_that("a plan on the cleaned pull refits only the taxon that lost a row, retires nothing, and drops the name with no model", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(exclude_pull()))
  main <- full_cycle(store, boss)
  on_machine(boss, atlas_exclude_records(c("202906", "202862"), quiet = TRUE))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  planned <- unique(vapply(job$tasks, function(t) paste(t$algorithm, t$taxon), ""))
  had <- vapply(Filter(function(e) identical(e$taxon, "Clitocybe deceptiva") && !isTRUE(e$refused), main$index),
                function(e) paste(e$algorithm, e$taxon), "")
  expect_setequal(planned, had)
  expect_length(job$retire, 0L)
  # The published cells and taxa no longer name the mallard.
  cells <- on_machine(boss, utils::read.delim(gzfile(atlas_public_cells_path())))
  expect_false("Anas platyrhynchos" %in% cells$taxon)
  # It never had a model to retire: one site is no candidate.
  expect_false("Anas platyrhynchos" %in% vapply(main$index, function(e) e$taxon, ""))
})
