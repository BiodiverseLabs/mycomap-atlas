# Jobs: plan on one machine, run shards on others, finish into a release.
#
# Every machine here is a separate data directory, and the store is a folder.
# The fit is the stand-in from helper-batch.R, so a whole cycle takes seconds.

test_that("shards share the work evenly and every task goes to exactly one", {
  costs <- c(9, 1, 1, 1, 4, 4, 3, 3, 2, 2)
  shard <- atlas_assign_shards(costs, 3)
  expect_length(shard, length(costs))
  expect_setequal(unique(shard), 1:3)
  load <- tapply(costs, shard, sum)
  expect_lte(max(load) - min(load), max(costs))
  expect_equal(atlas_assign_shards(c(5, 1), 8), c(1L, 2L))
})

test_that("a job runs on separate machines and finishes into a release", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))

  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), shards = 2L, quiet = TRUE))
  # Three taxa clear 20 cells, for two models; "Tiny" is never planned.
  expect_length(job$tasks, 6L)
  expect_false("Tiny" %in% vapply(job$tasks, function(t) t$taxon, ""))
  expect_equal(atlas_job_status(store, job$id)$missing, 1:2)
  expect_error(atlas_finish_job(store, job$id, quiet = TRUE), "not reported")

  for (n in 1:2) on_machine(machine(), atlas_run_shard(store, job$id, n, quiet = TRUE, fit = fake_fit))
  release <- on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))

  expect_equal(atlas_current_release(store)$id, release$id)
  expect_length(release$index, 6L)
  expect_true(all(c("models/draft/taxon-a.json", "models/draft/rf/taxon-c.json",
                    "public/cells.tsv.gz", "layers/draft/manifest.json") %in% release_paths(release)))
  expect_true(atlas_job_status(store, job$id)$finished)
  # Anyone can pull it.
  on_machine(machine(), {
    atlas_pull_release(store, quiet = TRUE)
    expect_true(file.exists(atlas_model_path("Taxon B", "draft", ".json", "rf")))
  })
})

test_that("with nothing changed there is nothing to plan", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)
  expect_null(on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE)))
})

test_that("new records refit only their taxon, and everything else stays as it was", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  first <- full_cycle(store, boss)

  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-2], "Taxon B" = 31))))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_setequal(vapply(job$tasks, function(t) t$taxon, ""), "Taxon B")
  for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(store, job$id, n, quiet = TRUE, fit = fake_fit))
  second <- on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))

  expect_equal(second$previous, first$id)
  expect_false(identical(release_hash(first, "models/draft/taxon-b.json"),
                         release_hash(second, "models/draft/taxon-b.json")))
  expect_identical(release_hash(first, "models/draft/rf/taxon-a.json"),
                   release_hash(second, "models/draft/rf/taxon-a.json"))
})

test_that("new layers make every model stale", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA), layer_md5 = "m2"))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_length(job$tasks, 6L)
})

test_that("a model that fails keeps its previous version, and is planned again", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  first <- full_cycle(store, boss)

  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-2], "Taxon B" = 31))))
  breaks_b <- local({
    f <- function(name, ...) if (name == "Taxon B") stop("worker ran out of memory") else fake_fit(name, ...)
    environment(f) <- globalenv()
    f
  })
  second <- full_cycle(store, boss, fit = breaks_b)
  expect_equal(second$job_results$failed, 2L)
  expect_identical(release_hash(first, "models/draft/taxon-b.json"),
                   release_hash(second, "models/draft/taxon-b.json"))
  again <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_setequal(vapply(again$tasks, function(t) t$taxon, ""), "Taxon B")
})

test_that("a taxon that drops under the line is retired from the release", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)

  on_machine(boss, orchestrator_data(synthetic_occurrences(c(TAXA[-3], "Taxon C" = 12))))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_length(job$tasks, 0L)
  expect_length(job$retire, 2L)
  release <- on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))
  expect_false(any(grepl("taxon-c", release_paths(release))))
  expect_false(any(vapply(release$index, function(e) e$taxon == "Taxon C", logical(1))))
})

test_that("a limited job fits only the richest taxa that need it, and leaves the rest for later", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  trial <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), limit = 1, quiet = TRUE))
  # Taxon B has the most cells: both its models, nothing else.
  expect_setequal(vapply(trial$tasks, function(t) t$taxon, ""), "Taxon B")
  expect_length(trial$tasks, 2L)
  expect_equal(trial$deferred, 4L)
  for (n in seq_len(trial$shards)) on_machine(machine(), atlas_run_shard(store, trial$id, n, quiet = TRUE, fit = fake_fit))
  on_machine(boss, atlas_finish_job(store, trial$id, quiet = TRUE))

  rest <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_setequal(vapply(rest$tasks, function(t) t$taxon, ""), c("Taxon A", "Taxon C"))
  expect_error(on_machine(boss, atlas_plan_job(store, limit = 0, quiet = TRUE)), "positive number")
})

test_that("a limited job still retires taxa that fell under the line, and only those", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)

  # Taxon A gains records (stale); Taxon C falls under the line.
  on_machine(boss, orchestrator_data(synthetic_occurrences(c("Taxon A" = 28, "Taxon B" = 30, "Taxon C" = 12))))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", limit = 1, quiet = TRUE))
  expect_setequal(vapply(job$tasks, function(t) t$taxon, ""), "Taxon A")
  expect_equal(vapply(job$retire, function(r) r$taxon, ""), "Taxon C")
  release <- on_machine(boss, {
    for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(store, job$id, n, quiet = TRUE, fit = fake_fit))
    atlas_finish_job(store, job$id, quiet = TRUE)
  })
  # Taxon B was neither fitted nor retired: it keeps its model.
  expect_true("models/draft/taxon-b.json" %in% release_paths(release))
})

test_that("a job planned from an older release is refused at the finish", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", quiet = TRUE))
  for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(store, job$id, n, quiet = TRUE, fit = fake_fit))
  # Meanwhile someone published a release.
  on_machine(machine(), {
    dir.create(atlas_model_dir("draft"), recursive = TRUE)
    atlas_write_json(list(taxon = "Elsewhere"), atlas_model_path("Elsewhere", "draft", ".json"))
    atlas_publish_release(store, quiet = TRUE)
  })
  expect_error(on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE)), "plan again")
})

test_that("a shard that cannot get its inputs reports nothing", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  lost <- job$inputs[[1]]$sha256
  unlink(file.path(sub("^file://", "", store$uri), "objects", substr(lost, 1, 2), lost))
  expect_error(on_machine(machine(), atlas_run_shard(store, job$id, 1, quiet = TRUE, fit = fake_fit)))
  expect_equal(atlas_job_status(store, job$id)$done, integer())
})

test_that("workers never need the release's model files", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = "maxnet", shards = 1L, quiet = TRUE))
  paths <- vapply(job$inputs, function(f) f$path, "")
  expect_false(any(grepl("^models/", paths)))
  expect_true(any(grepl("^occurrences/occurrences-", paths)))
  expect_true("layers/draft/fake.tif" %in% paths)
})

test_that("a refusal is recorded, left alone while nothing changes, and retried when records do", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  # The stand-in fit refuses any taxon called "Sparse ...", as a real fit does
  # when cells without predictor data leave too few presences.
  taxa <- c("Taxon A" = 25, "Sparse one" = 24)
  on_machine(boss, orchestrator_data(synthetic_occurrences(taxa)))
  release <- full_cycle(store, boss)
  refusals <- Filter(function(e) isTRUE(e$refused), release$index)
  expect_length(refusals, 2L)
  expect_equal(release$models$maxnet, 1L)
  expect_false(any(grepl("sparse-one", release_paths(release))))

  expect_null(on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE)))

  on_machine(boss, orchestrator_data(synthetic_occurrences(c("Taxon A" = 25, "Sparse one" = 26))))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  expect_setequal(vapply(job$tasks, function(t) t$taxon, ""), "Sparse one")
})

test_that("a publish records the refusals its machine's batches made", {
  with_data_dir({
    world <- batch_world(c("Rich one" = 40, "Sparse one" = 25))
    run_batch(world)
    index <- atlas_models_index("draft")
    refused <- Filter(function(e) isTRUE(e$refused), index)
    expect_equal(vapply(refused, function(e) e$taxon, ""), "Sparse one")
    expect_false(is.null(refused[[1]]$fingerprint))
    expect_false(is.null(refused[[1]]$settings_key))
  })
})
