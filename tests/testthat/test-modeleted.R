# MO records with no cached MO answer, and those deleted on MO (Steve,
# 2026-10-18): left out of the pull unless their place can be read from MO's
# own answer, and counted, by reason, in the pull's manifest.

tsv_of <- function(df) {
  con <- textConnection("out", "w", local = TRUE)
  utils::write.table(df, con, sep = "\t", quote = FALSE, row.names = FALSE, na = "")
  close(con)
  paste(out, collapse = "\n")
}

test_that("an MO record with no cached answer is left out by default, and one deleted on MO even when kept", {
  expect_equal(ATLAS_MO_UNKNOWN, "drop")
  answer <- atlas_mo_answer_sql()
  placed <- sprintf("AND (%s OR %s))", answer$gps, answer$small)
  dropped <- atlas_mo_location_clause()
  # Drop: only a placed record passes, and the marker is not needed.
  expect_match(dropped, placed, fixed = TRUE)
  expect_false(grepl("NOT EXISTS", dropped, fixed = TRUE))
  expect_false(grepl("source_deleted_at", dropped, fixed = TRUE))
  expect_false(grepl("source_deleted_at", atlas_occurrence_sql(), fixed = TRUE))
  # Keep: an uncached record passes only when .org does not know it deleted.
  kept <- atlas_mo_location_clause(unknown = "keep")
  expect_match(kept, paste0(placed, " OR (NOT EXISTS (SELECT 1 FROM atlas.mo_points m ",
                            "WHERE m.source_observation_id = o.observation_id) AND o.source_deleted_at IS NULL)"),
               fixed = TRUE)
  # A deleted record WITH a cached answer passes on that answer either way:
  # the placed test does not look at the marker.
  expect_false(grepl("source_deleted_at", placed, fixed = TRUE))
})

test_that("the left-out count reads the pull's own filters, for MO records only, in an id window", {
  sql <- atlas_mo_left_out_sql(100, 250, since = "2026-10-01")
  expect_match(sql, "WHERE o.source = 'MO Observations'", fixed = TRUE)
  expect_match(sql, sprintf("'yes' IN (%s)", atlas_status_columns()), fixed = TRUE)
  expect_match(sql, atlas_one_line(atlas_place_clause()), fixed = TRUE)
  expect_match(sql, "AND o.updated_at >= date '2026-10-01'", fixed = TRUE)
  expect_match(sql, "AND o.id > 100 AND o.id <= 250", fixed = TRUE)
  expect_match(sql, "o.source_deleted_at IS NOT NULL AS deleted", fixed = TRUE)
  answer <- atlas_mo_answer_sql()
  expect_match(sql, sprintf("AND (%s OR %s)) AS placed", answer$gps, answer$small), fixed = TRUE)
  for (k in c("deleted_at_source_uncached", "uncached", "too_coarse")) expect_match(sql, paste0("AS ", k), fixed = TRUE)
  # The last window is open.
  expect_false(grepl("o.id <=", atlas_mo_left_out_sql(250), fixed = TRUE))
})

# A pull through a stand-in for the SQL route: one page of records, and a
# left-out count of 2 deleted, 3 uncached and 1 too coarse per window asked.
pull_counting <- function(counts = data.frame(deleted_at_source_uncached = 2, uncached = 3, too_coarse = 1),
                          fail = FALSE) {
  page <- fake_occurrences()
  asked <- character()
  testthat::local_mocked_bindings(
    atlas_run_sql = function(sql, host = NULL) {
      asked <<- c(asked, sql)
      if (startsWith(sql, "SELECT count(*) FILTER")) {
        if (fail) stop("permission denied for column source_deleted_at")
        return(tsv_of(counts))
      }
      if (startsWith(sql, "SELECT o.id, s.species_name")) {
        return(tsv_of(data.frame(id = page$id, species_name = page$scientific_name)))
      }
      if (grepl("o.id > 0 ", sql, fixed = TRUE)) return(tsv_of(page))
      ""
    },
    .env = environment(atlas_pull_occurrences)
  )
  manifest <- atlas_pull_occurrences(quiet = TRUE)
  list(manifest = manifest, asked = asked, last = max(as.numeric(page$id)))
}

test_that("a pull counts the MO records it left out, by reason, over every id window", {
  with_data_dir({
    run <- pull_counting()
    counted <- run$asked[startsWith(run$asked, "SELECT count(*) FILTER")]
    # The page's window and the open one after it: no id unread.
    expect_length(counted, 2L)
    expect_match(counted[[1]], sprintf("AND o.id > 0 AND o.id <= %d", as.integer(run$last)), fixed = TRUE)
    expect_match(counted[[2]], sprintf("AND o.id > %d *[)] x$", as.integer(run$last)))
    expect_false(grepl("o.id <=", counted[[2]], fixed = TRUE))
    left <- run$manifest$mo_left_out
    expect_equal(left$unknown, "drop")
    expect_equal(left$deleted_at_source_uncached, 4L)
    expect_equal(left$uncached, 6L)
    expect_equal(left$uncached_kept, 0L)
    expect_equal(left$too_coarse, 2L)
    expect_true(left$complete)
    # Written with the manifest.
    expect_equal(atlas_read_manifest()$mo_left_out$deleted_at_source_uncached, 4L)
  })
})

test_that("kept uncached records are counted as kept, deleted ones still as left out", {
  left <- testthat::with_mocked_bindings(
    atlas_mo_left_out(c(10), TRUE, unknown = "keep"),
    atlas_run_sql = function(sql, host = NULL) tsv_of(data.frame(deleted_at_source_uncached = 1, uncached = 5, too_coarse = 0))
  )
  expect_equal(left$uncached, 0L)
  expect_equal(left$uncached_kept, 10L)
  expect_equal(left$deleted_at_source_uncached, 2L)
})

test_that("a count that fails never fails the pull: the manifest says why it has none", {
  with_data_dir({
    expect_warning(run <- pull_counting(fail = TRUE), "MO records left out not counted")
    expect_match(run$manifest$mo_left_out$error, "permission denied", fixed = TRUE)
    expect_equal(run$manifest$records, nrow(fake_occurrences()))
  })
})
