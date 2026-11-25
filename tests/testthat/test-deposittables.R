# The tables deposited with a models version (R/deposittables.R): the
# training-record table, built from the release's training records, and the
# lineage table.

test_that("the training-record table lists each modelled taxon's training records once, and no other taxon's", {
  fx <- tables_fixture()
  before <- store_hashes(fx$store)
  built <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land)
  out <- built$table
  expect_identical(names(out), ATLAS_TRAINING_COLUMNS)
  expect_setequal(unique(out$taxon), c("Taxon A", "Taxon B"))
  expect_equal(nrow(out), 56L)
  expect_false(any(duplicated(paste(out$source, out$source_id))))
  expect_setequal(paste(out$source, out$source_id),
                  with(fx$occurrences[fx$occurrences$scientific_name != "Taxon C", ], paste(source, observation_id)))
  expect_equal(built$summary$models, 3L)
  expect_equal(built$summary$models_found_by_their_job, 3L)
  expect_equal(built$summary$taxa, 2L)
  # Read only: the store is as it was.
  expect_identical(store_hashes(fx$store), before)
})

test_that("sites are numbered in the table's own order, and records share a number exactly when they share a site", {
  fx <- tables_fixture()
  out <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land)$table
  ids <- as.integer(out$site_id)
  # First appearances run 1, 2, 3, ... down the table.
  expect_identical(unique(ids), seq_along(unique(ids)))
  points <- atlas_occurrence_points(fx$occurrences, "draft")
  site_of <- stats::setNames(paste(points$scientific_name, points$site),
                             paste(fx$occurrences$source, fx$occurrences$observation_id))
  pull_site <- site_of[paste(out$source, out$source_id)]
  for (i in seq_len(nrow(out))) {
    expect_identical(ids == ids[[i]], unname(pull_site == pull_site[[i]]))
  }
  # The twin shares its site's number; no other record does.
  expect_equal(sum(ids == ids[out$source_id == "twin-1"]), 2L)
})

test_that("a hidden record keeps its row and has no site, and a record its source no longer holds is left out and counted", {
  fx <- tables_fixture()
  a <- fx$occurrences[fx$occurrences$scientific_name == "Taxon A", ]
  privacy <- data.frame(source = a$source[1:3], observation_id = a$observation_id[1:3], privacy = "place")
  deleted <- data.frame(source = a$source[c(3, 4)], observation_id = a$observation_id[c(3, 4)])
  built <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land, privacy = privacy,
                                        deleted = deleted, deleted_on = "2026-11-24")
  out <- built$table
  key <- paste(out$source, out$source_id)
  expect_true(all(paste(a$source[1:2], a$observation_id[1:2]) %in% key))
  expect_identical(out$site_id[key %in% paste(a$source[1:2], a$observation_id[1:2])], c("", ""))
  expect_false(any(paste(a$source[3:4], a$observation_id[3:4]) %in% key))
  expect_equal(built$summary$deleted_at_source$left_out, 2L)
  expect_equal(built$summary$deleted_at_source$in_another_privacy_group, 1L)
  expect_identical(built$summary$deleted_at_source$list_read_on, "2026-11-24")
  expect_equal(built$summary$rows_without_site, 2L)
})

test_that("a sequence id is listed only where its approval is 1; any other value, an id not in the approvals, or none, is blank", {
  fx <- tables_fixture(sequences = TRUE)
  none <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land)
  expect_true(all(none$table$sequence_id == ""))
  # seq-1 .. seq-4 approved 1, 0, -1 and -2; seq-5 not in the approvals; Taxon B's first two have no sequence.
  approvals <- data.frame(sequence_id = paste0("seq-", 1:4), approved = c("1", "0", "-1", "-2"))
  built <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land, sequences = approvals,
                                        sequences_exported_on = "2026-11-25")
  out <- built$table
  given <- stats::setNames(out$sequence_id, out$source_id)
  ids <- stats::setNames(fx$occurrences$sequence_id, fx$occurrences$observation_id)
  expect_identical(unname(given[names(ids)[ids == "seq-1"]]), "seq-1")
  for (blank in paste0("seq-", 2:5)) expect_identical(unname(given[names(ids)[ids == blank]]), "")
  expect_equal(sum(nzchar(out$sequence_id)), 1L)
  s <- built$summary$sequence_ids
  expect_identical(s$exported_on, "2026-11-25")
  expect_equal(c(s$filled, s$blank_not_approved, s$blank_no_sequence), c(1L, 3L, 2L))
  expect_equal(s$blank_not_in_the_approvals, nrow(out) - 6L)
})

test_that("the table is not built when a taxon's models trained on other records, or a model's record set is in no kept pull", {
  fx <- tables_fixture()
  calls <- 0L
  real <- atlas_deposit_taxon_records
  local_mocked_bindings(atlas_deposit_taxon_records = function(...) {
    calls <<- calls + 1L
    out <- real(...)
    if (calls == 2L) out[-1, , drop = FALSE] else out
  })
  expect_error(atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land),
               "1 models were trained on other records")
  gone <- tables_fixture()
  gone$manifest$index[[3]]$fingerprint <- "0000000"
  expect_error(atlas_deposit_training_table(gone$store, gone$manifest, gone$tree, gone$land),
               "the record sets of 1 models are in no kept pull")
})

test_that("a deposited table with another column, a coordinate or a taxon's fingerprint is refused", {
  fx <- tables_fixture()
  out <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land)$table
  expect_error(atlas_deposit_refuse(cbind(out, latitude = "45.1234"), ATLAS_TRAINING_COLUMNS, fx$manifest), "columns")
  bad <- out; bad$sequence_id[[1]] <- "45.12345"
  expect_error(atlas_deposit_refuse(bad, ATLAS_TRAINING_COLUMNS, fx$manifest), "coordinate")
  bad <- out; bad$sequence_id[[1]] <- fx$manifest$index[[1]]$fingerprint
  expect_error(atlas_deposit_refuse(bad, ATLAS_TRAINING_COLUMNS, fx$manifest), "fingerprint")
  expect_true(atlas_deposit_refuse(out, ATLAS_TRAINING_COLUMNS, fx$manifest))
})

test_that("the lineage table names each model's fitting job and pull, and a pull can have more than one job", {
  fx <- tables_fixture(second_job = TRUE)
  built <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land)
  lineage <- atlas_deposit_lineage(built$fitting, atlas_deposit_jobs(fx$store))
  expect_identical(names(lineage$models), ATLAS_LINEAGE_MODEL_COLUMNS)
  expect_identical(names(lineage$pulls), ATLAS_LINEAGE_PULL_COLUMNS)
  expect_equal(nrow(lineage$models), 3L)
  expect_identical(lineage$models$job[lineage$models$taxon == "Taxon B"], "20261007T000000Z-refresh")
  expect_identical(unique(lineage$models$job[lineage$models$taxon == "Taxon A"]), "20261005T000000Z-job")
  expect_true(all(lineage$models$pull_fingerprint == strrep("ab", 32)))
  expect_equal(nrow(lineage$pulls), 2L)
  expect_setequal(lineage$pulls$models, c(2L, 1L))
  for (t in list(lineage$models, lineage$pulls)) expect_true(atlas_deposit_refuse(t, names(t), fx$manifest))
})
