# Paper E9 as a paired hindcast (plan-e9, 2026-10-25; R/e9pair.R): the
# hindcast's changed taxa, fitted under DNA names and under record names, in
# two jobs planned together.

# The hindcast fixture, with three of Taxon A's early records named "Taxon
# Cee" by their observers: under record names, A loses them and Cee (Taxon
# C's record name) gains them. Taxon B's record names are a genus only.
e9_occurrences <- function() {
  occ <- hindcast_occurrences()
  a <- which(occ$scientific_name == "Taxon A")
  occ$record_name[a[4:6]] <- "Taxon Cee"
  occ
}

e9_setup <- function(fit = seeded_fit(list("Taxon A" = "strong", "Taxon B" = "weak", "Taxon C" = "weak"))) {
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(e9_occurrences()))
  main <- full_cycle(store, boss, fit = map_fit(list("Taxon A" = "strong", "Taxon B" = "strong", "Taxon C" = "weak")))
  hind <- on_machine(boss, atlas_plan_private_release(store, main$id, "hindcast", HINDCAST_CUTOFF,
                                                      algorithms = "maxnet", shards = 1L, quiet = TRUE))
  run_private(store, hind, fit)
  finish_private(store, hind$id)
  list(store = store, boss = boss, main = main, hindcast = hind)
}

# The hindcast's models' recorded blocks, as atlas_release_blocks reads them
# from their metrics: the stand-in fits write none.
e9_blocks <- function(...) list("maxnet|Taxon A" = list(block_km = 75, range_km = 71),
                                "maxnet|Taxon C" = list(block_km = 40, range_km = 38))

plan_pair <- function(setup, ...) {
  testthat::local_mocked_bindings(atlas_release_blocks = e9_blocks)
  on_machine(setup$boss, atlas_plan_e9_pair(setup$store, setup$hindcast$id, quiet = TRUE, shards = 1L, ...))
}

task_of <- function(tasks, taxon) Filter(function(t) identical(t$taxon, taxon), tasks)[[1]]

test_that("E9 fits only the taxa whose records change, under each labelling, and counts the rest", {
  skip_if_not_installed("terra")
  setup <- e9_setup()
  before <- setup$store$list("jobs/")
  plan <- plan_pair(setup, dry_run = TRUE)
  taxa <- function(side) sort(unique(vapply(plan$tasks[[side]], function(t) t$taxon, "")))
  # A loses three records to Cee; B has no species-level record name; C is
  # Cee under record names.
  expect_equal(taxa("dna"), c("Taxon A", "Taxon B", "Taxon C"))
  expect_equal(taxa("record"), c("Taxon A", "Taxon Cee"))
  expect_equal(plan$counts$taxa_paired, 1L)
  expect_equal(plan$counts$taxa_dna_only, 2L)
  expect_equal(plan$counts$taxa_record_only, 1L)
  expect_equal(plan$counts$models_unchanged, 0L)
  # Nothing is written by a dry run.
  expect_identical(setup$store$list("jobs/"), before)
})

test_that("a taxon whose records are the same under both names is not fitted", {
  skip_if_not_installed("terra")
  setup <- e9_setup()
  testthat::local_mocked_bindings(atlas_release_blocks = e9_blocks)
  changed <- on_machine(setup$boss, {
    pulled <- job_pull(setup$store, setup$hindcast)
    same <- pulled
    same$record_name <- same$scientific_name
    atlas_e9_changed(pulled, atlas_record_named(same)$occurrences, "maxnet", 20)
  })
  expect_length(changed$maxnet$changed, 0L)
  expect_gt(changed$maxnet$unchanged, 0L)
})

test_that("a record-name model draws with its DNA pair's seed and fits on its DNA pair's block", {
  skip_if_not_installed("terra")
  setup <- e9_setup()
  plan <- plan_pair(setup, dry_run = TRUE)
  dna_a <- task_of(plan$tasks$dna, "Taxon A")
  record_a <- task_of(plan$tasks$record, "Taxon A")
  # The DNA model is the hindcast's: its own records, seed and block.
  hindcast_a <- task_of(setup$hindcast$tasks, "Taxon A")
  expect_identical(dna_a$fingerprint, hindcast_a$fingerprint)
  expect_identical(dna_a$seed_from, hindcast_a$fingerprint)
  expect_equal(dna_a$block$block_km, 75)
  # The record model has other records, but its pair's seed and block.
  expect_false(identical(record_a$fingerprint, dna_a$fingerprint))
  expect_identical(record_a$seed_from, dna_a$fingerprint)
  expect_equal(record_a$block, list(block_km = 75, range_km = 71))
  # A record-only taxon has no pair: its own seed and a block of its own.
  cee <- task_of(plan$tasks$record, "Taxon Cee")
  expect_null(cee$seed_from)
  expect_null(cee$block)
  expect_equal(plan$counts$models_with_dna_block, 1L)
})

test_that("the two jobs carry each labelling's pull, the hindcast's cutoff and settings, and name each other", {
  skip_if_not_installed("terra")
  setup <- e9_setup()
  jobs <- plan_pair(setup)
  expect_setequal(names(jobs), c("dna", "record"))
  expect_equal(jobs$dna$e9$partner, jobs$record$id)
  expect_equal(jobs$record$e9$partner, jobs$dna$id)
  expect_equal(jobs$dna$purpose, "hindcast")
  expect_equal(jobs$record$purpose, "hindcast-record-names")
  for (job in jobs) {
    expect_equal(job$validated_through, HINDCAST_CUTOFF)
    expect_identical(job$fit, setup$hindcast$fit)
    expect_true(setup$store$exists(paste0("jobs/draft/", job$id, "/job.json")))
  }
  dna <- job_pull(setup$store, jobs$dna)
  record <- job_pull(setup$store, jobs$record)
  hindcast <- job_pull(setup$store, setup$hindcast)
  expect_identical(atlas_fingerprint(dna), atlas_fingerprint(hindcast))
  expect_equal(sum(record$scientific_name == "Taxon A"), sum(hindcast$scientific_name == "Taxon A") - 3L)
  expect_false("Taxon B" %in% record$scientific_name)
})

test_that("a job's tasks' blocks reach the fit, before any other block", {
  skip_if_not_installed("terra")
  setup <- e9_setup()
  jobs <- plan_pair(setup)
  seen <- new.env()
  inner <- seeded_fit()
  watching <- function(name, fingerprint, ..., recorded_block = NULL) {
    assign(name, recorded_block, envir = seen)
    inner(name, fingerprint, ...)
  }
  environment(watching) <- list2env(list(inner = inner, seen = seen), parent = globalenv())
  run_private(setup$store, jobs$record, watching)
  expect_equal(get("Taxon A", envir = seen)$block_km, 75)
  expect_null(get0("Taxon Cee", envir = seen, inherits = FALSE))
})

test_that("the DNA side refits the hindcast's model on its own records and seed", {
  skip_if_not_installed("terra")
  fit <- seeded_fit(list("Taxon A" = "strong", "Taxon B" = "weak", "Taxon C" = "weak"))
  setup <- e9_setup(fit)
  jobs <- plan_pair(setup)
  run_private(setup$store, jobs$dna, fit)
  record <- atlas_store_text(setup$store, atlas_shard_key(jobs$dna$id, 1L))
  hindcast <- atlas_store_text(setup$store, atlas_shard_key(setup$hindcast$id, 1L))
  saved <- function(r, taxon) Filter(function(x) identical(x$taxon, taxon), r$results)[[1]]
  expect_identical(saved(record, "Taxon A")$fingerprint, saved(hindcast, "Taxon A")$fingerprint)
  expect_identical(saved(record, "Taxon A")$status, "fitted")
})

test_that("E9 refuses anything but a finished hindcast", {
  setup <- list(store = fresh_store(), boss = machine())
  expect_error(on_machine(setup$boss, atlas_plan_e9_pair(setup$store, "priv-none", quiet = TRUE)),
               "no finished private release")
  expect_error(atlas_main(c("plan-job", "--e9-pair")), "needs --from-release")
})
