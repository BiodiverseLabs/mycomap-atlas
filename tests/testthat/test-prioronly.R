# A prior-only job: Vision's leave-validation-out benchmark (R_train). The
# main release's strong models refitted on its own pull without the records
# validated after a cutoff; its prior, trained ids and summary kept private,
# and never a release.

read_store_tsv <- function(store, key) {
  file <- tempfile(fileext = if (grepl("[.]gz$", key)) ".tsv.gz" else ".tsv")
  store$get(key, file)
  utils::read.delim(if (grepl("[.]gz$", key)) gzfile(file) else file, colClasses = "character", na.strings = "")
}

# Every key the store holds outside the content-addressed objects.
store_keys <- function(store) {
  sort(unlist(lapply(c("releases/", "current/", "archives/", "layers/", "jobs/", "private/"), store$list)))
}

run_prior_only <- function(setup, fit_grades = list(), build = stub_prior_build) {
  job <- on_machine(setup$boss, atlas_plan_prior_only(setup$store, setup$main$id, PRIOR_ONLY_CUTOFF,
                                                      shards = 2L, quiet = TRUE))
  seen <- new.env()
  fit <- map_fit(fit_grades, seen)
  for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(setup$store, job$id, n, quiet = TRUE, fit = fit))
  summary <- on_machine(machine(), atlas_finish_prior_only_work(setup$store, job$id, quiet = TRUE, build = build))
  list(job = job, seen = seen, summary = summary)
}

test_that("a record validated after the cutoff is left out; one validated before it or never dated stays", {
  occ <- dated_occurrences()
  out <- atlas_filter_validated_through(occ, PRIOR_ONLY_CUTOFF)
  expect_equal(out$counts$records_in_pull, 77L)
  expect_equal(out$counts$records_removed, 13L)
  expect_equal(out$counts$records_kept_undated, 6L)
  expect_equal(out$counts$records_after_cutoff_kept, 0L)
  expect_true(all(is.na(out$occurrences$first_green_on) | out$occurrences$first_green_on <= PRIOR_ONLY_CUTOFF))
  # The cutoff day itself is kept.
  occ$first_green_on[1] <- PRIOR_ONLY_CUTOFF
  expect_true(occ$id[1] %in% atlas_filter_validated_through(occ, PRIOR_ONLY_CUTOFF)$occurrences$id)
  # A pull made before first green dates were kept cannot be filtered.
  expect_error(atlas_filter_validated_through(synthetic_occurrences(c("Taxon A" = 3)), PRIOR_ONLY_CUTOFF),
               "no first green dates")
})

test_that("the plan refits only the main release's strong models, on the filtered pull, with its settings and no nulls", {
  skip_if_not_installed("terra")
  setup <- prior_only_setup()
  pull_before <- on_machine(setup$boss, atlas_read_manifest())
  run <- run_prior_only(setup)
  job <- run$job
  expect_true(atlas_is_prior_only(job))
  expect_setequal(vapply(job$tasks, function(t) paste(t$algorithm, t$taxon), ""),
                  c("maxnet Taxon A", "rf Taxon A", "maxnet Taxon B", "rf Taxon B"))
  expect_true(all(vapply(job$tasks, function(t) t$inherited_grade, "") == "strong"))
  expect_equal(job$fit$nulls, 0)
  expect_equal(job$filter$records_removed, 13L)
  # The fits ran with the main job's settings, except the nulls.
  main_job <- atlas_read_job(setup$store, setup$main$job)
  keys <- c("n_background", "buffer_km", "folds", "block_km", "regmult", "correlation")
  for (call in run$seen$calls) {
    expect_equal(call$nulls, 0)
    expect_equal(call[keys], main_job$fit[keys], info = call$taxon)
  }
  expect_identical(job$layers_key, main_job$layers_key)
  # The box's own pull is untouched: the filtered pull was made elsewhere.
  expect_identical(on_machine(setup$boss, atlas_read_manifest()), pull_before)
})

test_that("its summary lists the taxa that fell below their minimum and says what it cost", {
  skip_if_not_installed("terra")
  run <- run_prior_only(prior_only_setup())
  s <- run$summary
  expect_equal(s$filter$records_after_cutoff_kept, 0L)
  expect_equal(s$taxa_planned, 2L)
  expect_equal(s$taxa_refitted, 1L)
  expect_equal(vapply(s$taxa_lost, function(t) t$taxon, ""), "Taxon A")
  expect_equal(s$models_fitted, 2L)
  expect_true(is.numeric(s$cpu_hours) && is.numeric(s$cost_estimate_usd))
  expect_match(s$declared, "inherited", fixed = TRUE)
})

test_that("its prior holds the refitted strong maps with their inherited grade, and its trained ids leave the held-out records out", {
  skip_if_not_installed("terra")
  setup <- prior_only_setup()
  run <- run_prior_only(setup, build = atlas_build_prior)
  id <- run$job$id
  taxa <- read_store_tsv(setup$store, atlas_benchmark_key(id, "prior", "draft", "taxa.tsv"))
  expect_equal(taxa$name, "Taxon B")
  expect_equal(taxa$grade, "strong")
  expect_true(setup$store$exists(atlas_benchmark_key(id, "prior", "draft", "ranks.tsv.gz")))
  trained <- read_store_tsv(setup$store, atlas_trained_release_key(id))
  occ <- dated_occurrences()
  held_out <- occ$observation_id[!is.na(occ$first_green_on) & occ$first_green_on > PRIOR_ONLY_CUTOFF]
  kept_b <- occ$observation_id[occ$scientific_name == "Taxon B" &
                                 (is.na(occ$first_green_on) | occ$first_green_on <= PRIOR_ONLY_CUTOFF)]
  # The check Vision runs: none of its held-out records, and its training ones there.
  expect_length(intersect(trained$source_id, held_out), 0L)
  expect_setequal(trained$source_id, kept_b)
  # Taxon A lost its map, so none of its records trained anything here.
  expect_false("Taxon A" %in% trained$taxon)
})

test_that("a prior-only job is never a release: nothing promoted, published or archived", {
  skip_if_not_installed("terra")
  setup <- prior_only_setup()
  before <- store_keys(setup$store)
  current <- atlas_current_release(setup$store)
  run <- run_prior_only(setup)
  id <- run$job$id
  expect_error(atlas_finish_job(setup$store, id, quiet = TRUE), "never becomes a release")
  added <- setdiff(store_keys(setup$store), before)
  # Its keys are its job's and the private ones, and nothing else.
  expect_true(all(startsWith(added, paste0("jobs/draft/", id, "/")) |
                    startsWith(added, paste0("jobs/draft/finish-", id, "/")) |
                    startsWith(added, "private/")), info = paste(added, collapse = ", "))
  expect_false(any(startsWith(added, "releases/") | startsWith(added, "current/") | startsWith(added, "archives/")))
  expect_identical(atlas_current_release(setup$store), current)
  expect_true(all(startsWith(grep("prior|summary", added, value = TRUE), "private/")))
  # A machine pulling the current release gets none of it.
  on_machine(machine(), {
    atlas_pull_release(setup$store, quiet = TRUE)
    expect_false(dir.exists(atlas_prior_dir("draft")))
  })
})

test_that("a plan needs a dated pull, a real release made by a job, and a date", {
  skip_if_not_installed("terra")
  setup <- prior_only_setup()
  expect_error(atlas_plan_prior_only(setup$store, setup$main$id, "31/08/2026", quiet = TRUE), "YYYY-MM-DD")
  expect_error(atlas_plan_prior_only(setup$store, "no-such-release", PRIOR_ONLY_CUTOFF, quiet = TRUE), "no release")
  # A main release fitted on a pull from before first green dates were kept.
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  undated <- full_cycle(store, boss, fit = map_fit(list("Taxon A" = "strong")))
  expect_error(on_machine(boss, atlas_plan_prior_only(store, undated$id, PRIOR_ONLY_CUTOFF, quiet = TRUE)),
               "no first green dates")
})
