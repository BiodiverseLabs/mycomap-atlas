# A taxon's spatial block is measured once and reused (Steve, 2026-10-21,
# after E12): by its other learners, by a later attempt of its shard, and by
# a refit of its released model. On another processor family the variogram
# can measure another block, and folds, tuning and grade follow it.

# A fit standing for one processor family: a block it measures itself is
# 100 km on family "A" and 150 on "B"; a recorded block it is given wins.
# It keeps what it was given, by "algorithm taxon".
family_fit <- function(family = "A", seen = new.env()) {
  seen$given <- list()
  function(name, fingerprint, grid = "draft", n_background = 10000, buffer_km = 500, algorithm = "maxnet",
           layers = NULL, recorded_block = NULL, ...) {
    seen$given[[paste(algorithm, name)]] <- recorded_block %||% "measured"
    out <- fake_fit(name, fingerprint, grid = grid, n_background = n_background, buffer_km = buffer_km,
                    algorithm = algorithm, layers = layers, ...)
    m <- out$metrics
    if (!is.null(recorded_block)) {
      m$block_km <- recorded_block$block_km
      m$block_range_km <- recorded_block$range_km
      m$block_source <- "recorded"
    } else {
      m$block_km <- c(A = 100, B = 150)[[family]]
      m$block_range_km <- m$block_km + 0.4
      m$block_source <- "blockCV"
    }
    m$settings <- atlas_fit_settings(grid = grid, n_background = n_background, buffer_km = buffer_km,
                                     algorithm = algorithm, layers = layers %||% atlas_layers_key(grid))
    atlas_write_json(m, atlas_model_path(name, grid, ".json", algorithm))
    list(metrics = m)
  }
}

# Each model's block in a release, by "algorithm taxon".
release_blocks <- function(store, release) {
  out <- list()
  for (e in release$index) {
    if (isTRUE(e$refused)) next
    sha <- release_hash(release, atlas_model_relpaths(e$taxon, "draft", e$algorithm, ".json"))
    file <- tempfile(fileext = ".json")
    store$get(atlas_object_key(sha), file)
    out[[paste(e$algorithm, e$taxon)]] <- jsonlite::fromJSON(file)$block_km
  }
  out
}

test_that("shards keep each taxon's tasks together, and stay balanced", {
  costs <- c(5, 5, 3, 3, 1, 1)
  taxa <- c("A", "A", "B", "B", "C", "C")
  shards <- atlas_assign_shards(costs, 2L, groups = taxa)
  expect_equal(length(unique(shards[taxa == "A"])), 1L)
  expect_equal(length(unique(shards[taxa == "B"])), 1L)
  expect_equal(length(unique(shards[taxa == "C"])), 1L)
  expect_setequal(unique(shards), 1:2)
  # Without groups, tasks are placed one by one, as before: a taxon's two
  # learners can land on two shards, so two machines.
  ungrouped <- atlas_assign_shards(costs, 2L)
  expect_equal(length(unique(ungrouped[taxa == "A"])), 2L)
})

test_that("a planned job puts every learner of a taxon on one shard", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(MORE_TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), shards = 4L, quiet = TRUE))
  shard_of <- split(vapply(job$tasks, function(t) t$shard, 0L), vapply(job$tasks, function(t) t$taxon, ""))
  expect_true(all(lengths(lapply(shard_of, unique)) == 1L))
  expect_gt(length(unique(unlist(shard_of))), 1L)
})

test_that("a taxon's later learners reuse the block its first learner measured", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  seen <- new.env()
  release <- full_cycle(store, boss, shards = 1L, fit = family_fit("A", seen))
  blocks <- release_blocks(store, release)
  expect_equal(blocks[["maxnet Taxon A"]], 100)
  expect_equal(blocks[["rf Taxon A"]], 100)
  expect_identical(seen$given[["maxnet Taxon A"]], "measured")
  expect_equal(seen$given[["rf Taxon A"]]$block_km, 100)
})

test_that("a later attempt of a shard reuses the blocks an earlier one saved, on another machine", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), shards = 1L, quiet = TRUE))
  first <- vapply(Filter(function(t) t$algorithm == "maxnet", job$tasks), function(t) t$taxon, "")[[1]]
  # Family A fits one Maxent model, saves it, and is reclaimed.
  run_until_lost(store, job, 1L, lost_after(1L, family_fit("A")), save_seconds = 0)
  # Family B finishes the shard: its own measurements are 150 km, but the
  # taxon the first attempt saved keeps that attempt's block.
  seen <- new.env()
  on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = family_fit("B", seen)))
  expect_equal(seen$given[[paste("rf", first)]]$block_km, 100)
  others <- setdiff(names(TAXA), c(first, "Tiny"))
  for (taxon in others) expect_equal(seen$given[[paste("rf", taxon)]]$block_km, 150, info = taxon)
})

test_that("a refit on another machine reuses each released model's block, unless its records or layers changed", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss, shards = 1L, fit = family_fit("A"))
  # Other nulls refit every model on the same records and training table.
  seen <- new.env()
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), shards = 1L, nulls = 9L, quiet = TRUE))
  on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = family_fit("B", seen)))
  for (task in Filter(function(t) t$taxon != "Tiny", job$tasks)) {
    expect_equal(seen$given[[paste(task$algorithm, task$taxon)]]$block_km, 100, info = paste(task$algorithm, task$taxon))
  }
  on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))
  # New records for Taxon A: its block is measured again; the others' are not.
  more <- TAXA
  more[["Taxon A"]] <- 27
  on_machine(boss, orchestrator_data(synthetic_occurrences(more)))
  seen <- new.env()
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), shards = 1L, nulls = 7L, quiet = TRUE))
  on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = family_fit("B", seen)))
  expect_identical(seen$given[["maxnet Taxon A"]], "measured")
  expect_equal(seen$given[["rf Taxon A"]]$block_km, 150)
  expect_equal(seen$given[["maxnet Taxon B"]]$block_km, 100)
  on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))
  # Other layers: another training table, so every block is measured again.
  on_machine(boss, orchestrator_data(synthetic_occurrences(more), layer_md5 = "m2"))
  seen <- new.env()
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), shards = 1L, nulls = 7L, quiet = TRUE))
  on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = family_fit("B", seen)))
  expect_identical(seen$given[["maxnet Taxon B"]], "measured")
})

test_that("a refit given its released block reproduces the released model, where measuring again would not", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  fit <- function(...) {
    atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack, fingerprint = "f00dfeed",
                    layers = "synthetic", n_background = 500, buffer_km = 300, write = TRUE, predict = TRUE,
                    quiet = TRUE, nulls = 0, tune = FALSE, importance = FALSE, ...)
  }
  with_data_dir({
    released <- fit()
    map <- atlas_sha256(atlas_model_path("Eastern fungus", "draft", ".tif", "maxnet"))
    recorded <- list(block_km = released$metrics$block_km, range_km = released$metrics$block_range_km)
    # Another processor family's variogram: another block.
    local_mocked_bindings(atlas_block_size = function(training, seed = 1L, ...) {
      list(block_km = 120, range_km = 121.3, source = "blockCV")
    })
    measured <- fit()
    expect_false(identical(measured$metrics$block_km, released$metrics$block_km))
    refit <- fit(recorded_block = recorded)
    expect_equal(refit$metrics$block_source, "recorded")
    expect_equal(refit$metrics$block_km, released$metrics$block_km)
    for (part in c("presences", "auc_mean", "boyce", "params", "folds", "settings_key")) {
      expect_identical(refit$metrics[[part]], released$metrics[[part]], info = part)
    }
    expect_identical(atlas_sha256(atlas_model_path("Eastern fungus", "draft", ".tif", "maxnet")), map)
  })
})
