# A fit that fails at a named step keeps its previous model, says so, and is
# not planned again until its records or settings change (R/failedrefits.R).

# A stand-in fit that fails for one taxon at a named step, as glmnet does when
# it cannot complete Maxent's regularization path.
fails_at_step <- function(taxon = "Taxon B", stage = "final fit",
                          message = "Error: glmnet failed to complete regularization path.  Model may be infeasible.") {
  f <- function(name, ...) {
    if (name == taxon) mycomapatlas:::atlas_fit_stage(stage, stop(message, call. = FALSE)) else fake_fit(name, ...)
  }
  environment(f) <- list2env(list(taxon = taxon, stage = stage, message = message), parent = globalenv())
  f
}

index_entry <- function(release, taxon, algorithm) {
  Filter(function(e) identical(e$taxon, taxon) && identical(e$algorithm, algorithm), release$index)[[1]]
}

test_that("a fit step's failure names the step, and a refusal passes through as a refusal", {
  failed <- tryCatch(atlas_fit_stage("null test", stop("boom")), error = function(e) e)
  expect_s3_class(failed, "atlas_fit_failure")
  expect_equal(failed$stage, "null test")
  expect_equal(conditionMessage(failed), "null test: boom")
  # The step inside names it, not the one around it.
  nested <- tryCatch(atlas_fit_stage("outer", atlas_fit_stage("inner", stop("boom"))), error = function(e) e)
  expect_equal(nested$stage, "inner")
  refused <- tryCatch(atlas_fit_stage("block size", stop(atlas_refusal("Taxon A", 3, "too few sites"))),
                      error = function(e) e)
  expect_s3_class(refused, "atlas_insufficient_evidence")
  expect_false(inherits(refused, "atlas_fit_failure"))
})

test_that("a batch row of a failed fit carries the step it failed at, and a failure with no step carries none", {
  named <- atlas_batch_fit_one("Taxon B", "fp", fails_at_step(stage = "cross-validation"), list())
  expect_equal(named$status, "failed")
  expect_equal(named$stage, "cross-validation")
  expect_match(named$error, "^cross-validation: Error: glmnet failed")
  plain <- atlas_batch_fit_one("Taxon B", "fp", function(name, ...) stop("worker lost"), list())
  expect_equal(plain$status, "failed")
  expect_null(plain$stage)
})

test_that("only a failure at a named step, for known records and settings, and not for memory, is recorded", {
  base <- list(taxon = "Taxon B", algorithm = "maxnet", status = "failed", stage = "final fit",
               error = "final fit: Error: glmnet failed to complete regularization path.",
               fingerprint = "f1", settings_key = "s1")
  expect_true(atlas_failed_refit_recordable(base))
  expect_false(atlas_failed_refit_recordable(utils::modifyList(base, list(stage = NULL))))
  expect_false(atlas_failed_refit_recordable(utils::modifyList(base, list(status = "refused"))))
  expect_false(atlas_failed_refit_recordable(utils::modifyList(base, list(fingerprint = NULL))))
  expect_false(atlas_failed_refit_recordable(utils::modifyList(
    base, list(error = "cross-validation: cannot allocate vector of size 2.1 Gb"))))
})

test_that("a model whose refit fails at a named step is kept, marked, and not planned again on the same records", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  first <- full_cycle(store, boss)

  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-2], "Taxon B" = 31))))
  second <- full_cycle(store, boss, fit = fails_at_step())
  expect_equal(second$job_results$failed, 2L)
  # The previous model stays, and its entry says why it was not replaced.
  expect_identical(release_hash(first, "models/draft/taxon-b.json"), release_hash(second, "models/draft/taxon-b.json"))
  kept <- index_entry(second, "Taxon B", "maxnet")
  expect_true(isTRUE(kept$kept_after_failed_refit))
  expect_equal(kept$failed_refit_stage, "final fit")
  expect_null(index_entry(second, "Taxon A", "maxnet")$kept_after_failed_refit)

  # Recorded privately, against the new records' fingerprint.
  recorded <- atlas_read_failed_refits(store)
  expect_setequal(names(recorded), c("maxnet|Taxon B", "rf|Taxon B"))
  expect_equal(recorded[["maxnet|Taxon B"]]$stage, "final fit")
  expect_equal(recorded[["maxnet|Taxon B"]]$job, second$job)
  new_fingerprint <- recorded[["maxnet|Taxon B"]]$fingerprint
  expect_false(identical(new_fingerprint, kept$fingerprint))
  # Never in the release itself.
  release_text <- as.character(jsonlite::toJSON(atlas_store_text(store, paste0("releases/draft/", second$id, ".json")),
                                                auto_unbox = TRUE))
  expect_true(grepl(kept$fingerprint, release_text, fixed = TRUE))
  expect_false(grepl(new_fingerprint, release_text, fixed = TRUE))

  # Same records: nothing to plan.
  expect_null(on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE)))

  # New records: planned again, and a fit that works clears the record and the mark.
  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-2], "Taxon B" = 32))))
  again <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_setequal(vapply(again$tasks, function(t) t$taxon, ""), "Taxon B")
  for (n in seq_len(again$shards)) on_machine(machine(), atlas_run_shard(store, again$id, n, quiet = TRUE, fit = fake_fit))
  third <- on_machine(boss, atlas_finish_job(store, again$id, quiet = TRUE))
  expect_length(atlas_read_failed_refits(store), 0L)
  expect_null(index_entry(third, "Taxon B", "maxnet")$kept_after_failed_refit)
})

test_that("a refit that failed at a named step is planned again when the settings change", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)
  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-2], "Taxon B" = 31))))
  full_cycle(store, boss, fit = fails_at_step())
  # New layers change every model's settings.
  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-2], "Taxon B" = 31)), layer_md5 = "m2"))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_true("Taxon B" %in% vapply(job$tasks, function(t) t$taxon, ""))
  expect_equal(job$held_after_failure, 0L)
})
