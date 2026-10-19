# .org's name-change log (R/namechanges.R): read after each pull from a cursor,
# its renames ahead of the guessed ones, and merges and splits named as the
# reason a taxon is refitted.

log_rows <- function(...) {
  rows <- list(...)
  base <- list(logged_at = "2026-10-18 12:00:00", batch_id = "", merge_group_id = "", request_id = "",
               source = "name_update", decision_ref = "", kind = "rename", respelling = "f",
               synonym_registered = "f", records_changed = "3", old_name_left = "0", new_name_before = "0")
  do.call(rbind, lapply(rows, function(r) {
    r <- utils::modifyList(base, r)
    as.data.frame(r[ATLAS_NAME_CHANGE_COLUMNS], stringsAsFactors = FALSE)
  }))
}

record_rows <- function(...) {
  rows <- list(...)
  data.frame(id = seq_along(rows), log_id = vapply(rows, `[[`, "", 1),
             record_ref = vapply(rows, `[[`, "", 2), stringsAsFactors = FALSE)
}

log_tsv <- function(df) {
  con <- textConnection("out", "w", local = TRUE)
  utils::write.table(df, con, sep = "\t", row.names = FALSE, quote = FALSE, na = "")
  close(con)
  paste(out, collapse = "\n")
}

change <- function(id, old, new, kind = "rename", at = "2026-10-18T12:00:00Z", records = character(),
                   moved = 3L) {
  list(id = as.integer(id), logged_at = at, old_name = old, new_name = new, kind = kind,
       records_changed = moved, records = records)
}

# A fake .org: the log and its records, answering only from the cursor asked for.
fake_log <- function(log, records = record_rows(), seen = new.env()) {
  seen$sql <- character()
  function(sql, host) {
    seen$sql <- c(seen$sql, sql)
    if (startsWith(sql, "SELECT l.id")) {
      after <- as.numeric(sub(".* l[.]id > ([0-9]+) .*", "\\1", sql))
      return(log_tsv(log[as.numeric(log$id) > after, , drop = FALSE]))
    }
    if (startsWith(sql, "SELECT r.id")) {
      lo <- as.numeric(sub(".* r[.]log_id >= ([0-9]+) .*", "\\1", sql))
      hi <- as.numeric(sub(".* r[.]log_id <= ([0-9]+) .*", "\\1", sql))
      keep <- as.numeric(records$log_id) >= lo & as.numeric(records$log_id) <= hi
      return(log_tsv(records[keep, , drop = FALSE]))
    }
    stop("unexpected statement: ", sql)
  }
}

test_that("the log is read from its stored cursor, so a second read asks only for what is new", {
  with_data_dir({
    log <- log_rows(list(id = "811", old_name = "Mycena sp. 'IN10'", new_name = "Mycena indianensis"),
                    list(id = "812", old_name = "Russula a", new_name = "Russula b", kind = "merge",
                         new_name_before = "9"))
    seen <- new.env()
    testthat::local_mocked_bindings(atlas_run_sql = fake_log(log, record_rows(c("812", "inat:5"), c("812", "mo:7")), seen))
    first <- atlas_pull_name_changes(host = "test", quiet = TRUE)
    expect_equal(first$cursor, 812)
    expect_equal(vapply(first$changes, function(r) r$id, 1L), c(811L, 812L))
    expect_equal(first$changes[[2]]$records, c("inat:5", "mo:7"))
    expect_equal(first$changes[[2]]$logged_at, "2026-10-18T12:00:00Z")
    expect_true(is.na(first$changes[[1]]$batch_id))

    seen$sql <- character()
    again <- atlas_pull_name_changes(host = "test", quiet = TRUE)
    expect_match(seen$sql[[1]], "l.id > 812 ", fixed = TRUE)
    expect_length(again$changes, 2L)
    # What was read survives on disk, records and all.
    kept <- atlas_read_name_changes()
    expect_equal(kept$cursor, 812)
    expect_equal(kept$changes[[2]]$kind, "merge")
    expect_equal(kept$changes[[2]]$records, c("inat:5", "mo:7"))
  })
})

test_that("a failed read keeps the cursor where it was and never raises", {
  with_data_dir({
    testthat::local_mocked_bindings(atlas_run_sql = fake_log(log_rows(list(id = "5", old_name = "A a", new_name = "B b"))))
    atlas_pull_name_changes(host = "test", quiet = TRUE)
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) stop("relation name_change_log does not exist"))
    expect_silent(out <- atlas_pull_name_changes(host = "test", quiet = TRUE))
    kept <- atlas_read_name_changes()
    expect_equal(kept$cursor, 5)
    expect_length(kept$changes, 1L)
    expect_match(kept$last_error, "does not exist")
    # A page of the log that does not look like the log is refused, not stored.
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) "id\tscientific_name\n9\tA a")
    atlas_pull_name_changes(host = "test", quiet = TRUE)
    expect_equal(atlas_read_name_changes()$cursor, 5)
    expect_match(atlas_read_name_changes()$last_error, "missing columns")
  })
})

test_that("the log's statements survive the SQL route and ask only for granted columns", {
  for (sql in c(atlas_name_change_log_sql(812), atlas_name_change_records_sql(1, 812, 4000))) {
    expect_true(atlas_assert_transport_safe(sql))
    # Who ran an update is withheld from atlas_ro.
    expect_false(grepl("run_by", sql, fixed = TRUE))
  }
  expect_match(atlas_name_change_log_sql(812), "WHERE l.id > 812 ORDER BY l.id", fixed = TRUE)
  expect_match(atlas_name_change_records_sql(3, 9, 40), "r.log_id >= 3 AND r.log_id <= 9 AND r.id > 40", fixed = TRUE)
})

test_that("the log's rename wins over the guess from record ids", {
  guessed <- data.frame(from = c("Russula sp. 'X1'", "Lactarius sp. 'Y'"), to = c("Russula a", "Lactarius z"),
                        records = 4L, moved = 3L, seen = "2026-10-01")
  existing <- atlas_update_renames(guessed, NULL, current_names = c("Russula a", "Russula b", "Lactarius z"))
  expect_equal(unique(existing$source), "detected")
  org <- atlas_org_renames(list(change(900, 'Russula "sp-X1"', "Russula b")), c("Russula a", "Russula b"))
  merged <- atlas_merge_org_renames(existing, org, c("Russula a", "Russula b", "Lactarius z"))
  # The log speaks for X1 in any spelling; Lactarius keeps its guess.
  x1 <- merged[merged$to %in% c("Russula a", "Russula b"), ]
  expect_equal(nrow(x1), 1L)
  expect_equal(x1$to, "Russula b")
  expect_equal(x1$source, "org")
  expect_equal(x1$change, 900L)
  expect_equal(merged$source[merged$from == "Lactarius sp. 'Y'"], "detected")
  # Merging again changes nothing.
  expect_identical(atlas_merge_org_renames(merged, org, c("Russula a", "Russula b", "Lactarius z")), merged)
})

test_that("a split that leaves records under the old name is no rename until the old name is gone", {
  split <- list(change(901, "Cortinarius sp. 'C1'", "Cortinarius fulvus", kind = "split"))
  still <- atlas_merge_org_renames(NULL, atlas_org_renames(split), c("Cortinarius sp. 'C1'", "Cortinarius fulvus"))
  expect_equal(nrow(still), 0L)
  gone <- atlas_merge_org_renames(NULL, atlas_org_renames(split), "Cortinarius fulvus")
  expect_equal(gone$to, "Cortinarius fulvus")
  expect_equal(atlas_resolve_name("Cortinarius sp. 'C1'", "Cortinarius fulvus", gone)$how, "renamed")
})

test_that("an old name's latest change wins, and a spelling Atlas already folds is no rename", {
  changes <- list(change(10, "Mycena sp. 'OLD'", "Mycena sp. 'MID'"),
                  change(14, "Mycena sp. 'OLD'", "Mycena sp. 'NEW'"),
                  change(15, "Mycena sp. 'IN 10'", "Mycena sp. 'IN-10'", kind = "respelling"),
                  change(16, "Mycena sp. 'IN1'", "Mycena sp. 'IN01'", kind = "respelling"))
  org <- atlas_org_renames(changes, current_names = c("Mycena sp. 'NEW'", "Mycena sp. 'IN01'"))
  expect_equal(org$from, c("Mycena sp. 'IN1'", "Mycena sp. 'OLD'"))
  expect_equal(org$to, c("Mycena sp. 'IN01'", "Mycena sp. 'NEW'"))
  expect_equal(org$change, c(16L, 14L))
  expect_equal(org$seen, c("2026-10-18", "2026-10-18"))
})

test_that("the new name is given in the spelling the pull models it under", {
  org <- atlas_org_renames(list(change(20, "Gymnopilus sp. 'G1'", 'Gymnopilus "sp-G2"')),
                           current_names = "Gymnopilus sp. 'G2'")
  expect_equal(org$to, "Gymnopilus sp. 'G2'")
})

test_that("an org row counts the pull's records, never .org's total, which it keeps apart", {
  occurrences <- data.frame(
    scientific_name = c("Russula b", "Russula b", "Russula b", "Russula c"),
    source = c("iNaturalist", "MO Observations", "iNaturalist", "iNaturalist"),
    observation_id = c("1", "2", "3", "4"), stringsAsFactors = FALSE
  )
  # .org renamed 40 records; the pull holds three of them (a sequence ref and
  # records outside the pull are not here), two still under the new name.
  renamed <- change(900, "Russula a", "Russula b", moved = 40L, records = c("inat:1", "mo:2", "inat:4", "seq:77"))
  org <- atlas_org_renames(list(renamed), unique(occurrences$scientific_name), occurrences)
  expect_equal(org$records, 3L)
  expect_equal(org$moved, 2L)
  expect_equal(org$org_records_changed, 40L)
  # It survives the merge into renames.json, and a detected row has none.
  merged <- atlas_merge_org_renames(data.frame(from = "Lactarius y", to = "Lactarius z", records = 4L, moved = 3L,
                                               seen = "2026-10-01"),
                                    org, unique(occurrences$scientific_name))
  expect_equal(merged$org_records_changed[merged$source == "org"], 40L)
  expect_true(is.na(merged$org_records_changed[merged$source == "detected"]))
  # Without a pull to count, the counts are unknown rather than .org's.
  expect_true(is.na(atlas_org_renames(list(renamed))$records))
})

test_that("a merge or split since the base release names the refit's reason; older changes and renames do not", {
  occurrences <- data.frame(
    scientific_name = c("Russula b", "Russula b", "Cortinarius sp. 'C1'", "Cortinarius fulvus", "Amanita x", "Boletus y"),
    source = c("iNaturalist", "iNaturalist", "iNaturalist", "MO Observations", "iNaturalist", "iNaturalist"),
    observation_id = c("1", "2", "3", "4", "5", "6"), stringsAsFactors = FALSE
  )
  changes <- list(
    change(812, "Russula a", "Russula b", kind = "merge"),
    change(813, "Cortinarius sp. 'C1'", "Cortinarius fulvus", kind = "split", records = "mo:4"),
    change(814, "Amanita old", "Amanita x", kind = "rename"),
    change(815, "Boletus z", "Boletus y", kind = "merge", at = "2026-09-01T00:00:00Z"),
    # A record that moved is found where the pull holds it, whatever its name there.
    change(816, "Lactarius q", "Lactarius r", kind = "merge", records = "inat:6")
  )
  reasons <- atlas_name_change_reasons(changes, occurrences, since = "2026-10-01T00:00:00Z")
  expect_equal(reasons[["Russula b"]], "refit: name merged (org change 812)")
  expect_equal(reasons[["Cortinarius fulvus"]], "refit: name split (org change 813)")
  expect_equal(reasons[["Cortinarius sp. 'C1'"]], "refit: name split (org change 813)")
  expect_equal(reasons[["Boletus y"]], "refit: name merged (org change 816)")
  expect_false("Amanita x" %in% names(reasons))
  # With no base release every change counts.
  all <- atlas_name_change_reasons(changes, occurrences)
  expect_equal(all[["Boletus y"]], "refit: name merged (org changes 815, 816)")
})

test_that("a plan gives a merged taxon's refit its reason, and adds no task of its own", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)

  # Taxon B took records in a merge after the release's pull (2026-01-01);
  # Taxon C's change is older than that pull; Taxon A was merged into on .org
  # but its records here did not change, so it is not refitted at all.
  on_machine(boss, {
    orchestrator_data(synthetic_occurrences(c(TAXA[c("Taxon A", "Tiny")], "Taxon B" = 31, "Taxon C" = 23)))
    atlas_write_json(list(cursor = 830, changes = list(
      change(812, "Taxon Bb", "Taxon B", kind = "merge"),
      change(813, "Taxon Cc", "Taxon C", kind = "merge", at = "2025-12-01T00:00:00Z"),
      change(814, "Taxon Aa", "Taxon A", kind = "merge")
    )), atlas_name_changes_path())
  })
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_setequal(vapply(job$tasks, function(t) t$taxon, ""), c("Taxon B", "Taxon C"))
  for (t in job$tasks) {
    if (t$taxon == "Taxon B") expect_equal(t$reason, "refit: name merged (org change 812)")
    else expect_null(t$reason)
  }
  stored <- atlas_read_job(store, job$id)
  expect_true(any(vapply(stored$tasks, function(t) identical(t$reason, "refit: name merged (org change 812)"), logical(1))))
})

test_that("a pull reads the log after its own files, puts its renames in renames.json, and a failed read fails nothing", {
  records <- synthetic_occurrences(c("Taxon A" = 12, "Taxon B" = 8))
  records$id <- as.character(seq_len(nrow(records)))
  log <- log_rows(list(id = "40", old_name = "Taxon Old", new_name = "Taxon B"))
  pull_with <- function(answer_log) {
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
      if (startsWith(sql, "SELECT l.id") || startsWith(sql, "SELECT r.id")) return(answer_log(sql, host))
      if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
      if (startsWith(sql, "SELECT o.id, s.species_name")) {
        return(log_tsv(data.frame(id = records$id, species_name = records$scientific_name)))
      }
      if (grepl("not_yet_validated", sql, fixed = TRUE)) return("taxon\tnot_yet_validated\twith_coordinates")
      log_tsv(records)
    })
    suppressWarnings(atlas_pull_occurrences(host = "test", quiet = TRUE))
  }
  with_data_dir({
    first <- pull_with(fake_log(log))
    expect_equal(atlas_read_name_changes()$cursor, 40)
    renames <- atlas_read_renames()
    expect_equal(renames$from, "Taxon Old")
    expect_equal(renames$to, "Taxon B")
    expect_equal(renames$source, "org")
    expect_equal(renames$org_records_changed, 3L)
    expect_equal(renames$records, 0L)

    second <- pull_with(function(sql, host) stop("permission denied for table name_change_log"))
    expect_identical(second$fingerprint, first$fingerprint)
    expect_equal(atlas_read_name_changes()$cursor, 40)
    expect_equal(atlas_read_renames()$source, "org")
  })
})

test_that("the log stays on this machine: a release never carries it", {
  with_data_dir({
    atlas_write_json(list(cursor = 1, changes = list()), atlas_name_changes_path())
    expect_false(any(grepl("name-changes", atlas_release_files("draft"), fixed = TRUE)))
  })
})
