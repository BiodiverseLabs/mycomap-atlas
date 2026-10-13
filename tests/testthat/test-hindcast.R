# A private release: every taxon fitted and graded afresh on a variant of a
# release's pull (a hindcast at a cutoff, or records under their own names),
# finished privately, never a release.

test_that("a hindcast keeps the records first validated by the cutoff, never judged by observation date", {
  occ <- hindcast_occurrences()
  hind <- atlas_filter_validated_through(occ, HINDCAST_CUTOFF, undated = "exclude")
  kept <- hind$occurrences
  a <- occ[occ$scientific_name == "Taxon A", ]
  # Validated after the cutoff: out, however long ago it was observed.
  expect_false(any(a$observation_id[31:40] %in% kept$observation_id))
  # Validated before it: in, though observed after it.
  expect_true(all(a$observation_id[1:3] %in% kept$observation_id))
  # No first green date: out of a hindcast, and counted; kept by prior-only.
  expect_equal(hind$counts$records_undated_left_out, 5L)
  expect_equal(hind$counts$records_after_cutoff_kept, 0L)
  expect_equal(nrow(kept), nrow(occ) - 10L - 5L)
  prior_only <- atlas_filter_validated_through(occ, HINDCAST_CUTOFF)
  expect_equal(nrow(prior_only$occurrences), nrow(occ) - 10L)
  expect_equal(prior_only$counts$records_undated_left_out, 0L)
})

test_that("a hindcast plans every taxon afresh with the release's own settings, null tests and tuning included", {
  skip_if_not_installed("terra")
  setup <- hindcast_setup()
  job <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                           HINDCAST_CUTOFF, shards = 2L, quiet = TRUE))
  main_job <- atlas_read_job(setup$store, setup$main$job)
  expect_equal(job$kind, "private-release")
  expect_equal(job$purpose, "hindcast")
  expect_identical(job$fit, main_job$fit)
  expect_gt(job$fit$nulls, 0)
  # Every taxon with enough records in the hindcast pull, weak in R_main or
  # not: Taxon A has 30 left, B 25, C 22; none inherits a grade.
  expect_setequal(unique(vapply(job$tasks, function(t) t$taxon, "")), c("Taxon A", "Taxon B", "Taxon C"))
  expect_true(all(vapply(job$tasks, function(t) is.null(t$inherited_grade), logical(1))))
  expect_equal(job$filter$records_undated_left_out, 5L)
  pull <- job_pull(setup$store, job)
  expect_equal(nrow(pull), 92L - 15L)
  expect_true(all(!is.na(pull$first_green_on) & pull$first_green_on <= HINDCAST_CUTOFF))
  # Never a release, never current.
  expect_identical(atlas_current_release(setup$store)$id, setup$main$id)
})

test_that("survey sites, effort, background and accessible area come from the hindcast pull, not the release's", {
  skip_if_not_installed("terra")
  setup <- hindcast_setup()
  job <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                           HINDCAST_CUTOFF, shards = 1L, quiet = TRUE))
  seen <- new.env()
  fit <- map_fit()
  watching <- function(name, fingerprint, ..., points = NULL) {
    if (identical(name, "Taxon A")) seen$points <- points
    fit(name, fingerprint, ..., points = points)
  }
  on_machine(machine(), atlas_run_shard(setup$store, job$id, 1L, quiet = TRUE, fit = watching))
  points <- seen$points
  expect_false(is.null(points))
  occ <- hindcast_occurrences()
  left_out <- occ[(occ$scientific_name == "Taxon A" & occ$first_green_on > HINDCAST_CUTOFF) |
                    is.na(occ$first_green_on), ]
  gone <- atlas_occurrence_points(left_out)$cell
  # The worker's points are the hindcast pull's: the late and undated
  # records' cells (each at a place of its own here) are in no point and no
  # survey site, so no detection, effort count, background site or reach is
  # built from them.
  expect_equal(nrow(points), 92L - 15L)
  expect_false(any(gone %in% points$cell))
  expect_false(any(gone %in% attr(points, "sites")$cell))
  training <- atlas_training_table("Taxon A", points, n_background = 10000, buffer_km = 500)
  expect_equal(sum(training$presence == 1L), length(unique(points$site[points$scientific_name == "Taxon A"])))
})

test_that("a private release is finished privately, with its own grades, and nothing reaches releases/ or current/", {
  skip_if_not_installed("terra")
  setup <- hindcast_setup()
  job <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                           HINDCAST_CUTOFF, shards = 2L, quiet = TRUE))
  # Its own grades: Taxon C, weak in R_main, is strong here.
  grades <- list("Taxon A" = "strong", "Taxon B" = "weak", "Taxon C" = "strong")
  for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(setup$store, job$id, n, quiet = TRUE,
                                                                         fit = map_fit(grades)))
  releases_before <- setup$store$list("releases/")
  current_before <- atlas_current_release(setup$store)$id
  stub_build <- function(grid, quiet) {
    stub_prior_build(grid)
    stub_continent_build(grid)
    dir.create(dirname(atlas_here_index_path(grid)), recursive = TRUE, showWarnings = FALSE)
    saveRDS(list(stub = TRUE), atlas_here_index_path(grid))
  }
  # On a worker, which may not write private/: the box places what it made.
  summary <- on_machine(machine(), atlas_finish_private_release_work(
    worker_store(setup$store), job$id, quiet = TRUE, count = function(...) 0L,
    ensembles = function(...) NULL, build = stub_build, defer = TRUE))
  record <- atlas_store_text(setup$store, atlas_shard_key(atlas_finish_id(job$id), 1L))
  atlas_place_deferred(setup$store, record$deferred)
  for (k in c("summary.json", "release.json", "models.tsv.gz", "prior/draft/taxa.tsv", "continent/draft/taxa.tsv")) {
    expect_true(setup$store$exists(atlas_benchmark_key(job$id, k)), info = k)
  }
  expect_true(setup$store$exists(atlas_trained_release_key(job$id)))
  models_file <- tempfile(fileext = ".tsv.gz")
  setup$store$get(atlas_benchmark_key(job$id, "models.tsv.gz"), models_file)
  models <- utils::read.delim(gzfile(models_file))
  expect_equal(unique(models$grade[models$taxon == "Taxon C"]), "strong")
  expect_equal(summary$grades$maxnet$strong, 2L)
  manifest <- atlas_store_text(setup$store, atlas_benchmark_key(job$id, "release.json"))
  expect_equal(manifest$kind, "private-release")
  expect_true(length(manifest$files) > 0L)
  expect_identical(setup$store$list("releases/"), releases_before)
  expect_identical(atlas_current_release(setup$store)$id, current_before)
})

test_that("a private release is never finished in part, nor as a job", {
  skip_if_not_installed("terra")
  setup <- hindcast_setup()
  job <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                           HINDCAST_CUTOFF, shards = 2L, quiet = TRUE))
  on_machine(machine(), atlas_run_shard(setup$store, job$id, 1L, quiet = TRUE, fit = map_fit()))
  expect_error(on_machine(machine(), atlas_finish_private_release_work(setup$store, job$id, quiet = TRUE)),
               "never finished in part")
  expect_error(on_machine(setup$boss, atlas_finish_job(setup$store, job$id, quiet = TRUE)),
               "private release")
})

test_that("a record-names release models the records under their own .org names", {
  skip_if_not_installed("terra")
  setup <- hindcast_setup()
  expect_error(on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "record-names",
                                                                 HINDCAST_CUTOFF, quiet = TRUE)),
               "only a hindcast takes a cutoff")
  # The algorithms the fixture's R_main fitted (production's fits them all).
  job <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "record-names",
                                                           algorithms = c("maxnet", "rf"), shards = 1L,
                                                           quiet = TRUE))
  pull <- job_pull(setup$store, job)
  # Taxon B's records, a genus only by their own names, are left out; Taxon
  # C's are under their record name.
  expect_setequal(unique(pull$scientific_name), c("Taxon A", "Taxon Cee"))
  expect_equal(job$filter$records_not_species_level, 30L)
  # Taxon A's records and name are R_main's: its models would be R_main's,
  # so only Taxon Cee is fitted.
  expect_setequal(unique(vapply(job$tasks, function(t) t$taxon, "")), "Taxon Cee")
  expect_equal(job$filter$models_unchanged, 2L)
})

test_that("a dry run says what a private release would fit and cost, and writes nothing", {
  skip_if_not_installed("terra")
  setup <- hindcast_setup()
  before <- c(setup$store$list("jobs/"), setup$store$list("objects/"), setup$store$list("private/"))
  expect_error(on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                                 quiet = TRUE, dry_run = TRUE)),
               "needs --validated-through")
  dry <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                           HINDCAST_CUTOFF, quiet = TRUE, dry_run = TRUE))
  expect_identical(c(setup$store$list("jobs/"), setup$store$list("objects/"), setup$store$list("private/")), before)
  expect_equal(dry$filter$records_undated_left_out, 5L)
  expect_equal(dry$estimate$models, length(dry$tasks))
  expect_gt(dry$estimate$cpu_hours, 0)
})
