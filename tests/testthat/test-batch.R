# Batch fitting. Most of these use a stand-in for the fit itself, so they test
# the bookkeeping — who is fitted, skipped, refused or failed — in a second
# rather than a minute per taxon. The last few run real fits on a synthetic
# landscape.

test_that("repeat records in one cell count as one presence cell", {
  points <- data.frame(
    scientific_name = c("A a", "A a", "A a", "B b"),
    cell = c(1, 1, 2, 3), x = 0, y = 0, stringsAsFactors = FALSE
  )
  counts <- atlas_presence_cell_counts(points)
  expect_equal(counts$scientific_name, c("A a", "B b"))
  expect_equal(counts$cells, c(2L, 1L))
})

test_that("candidates are the taxa with enough cells, richest first", {
  world <- batch_world()
  candidates <- atlas_batch_candidates(world$points, min_presences = 20)
  expect_equal(candidates$scientific_name, c("Rich one", "Middle one"))
})

test_that("a limit keeps the richest candidates", {
  world <- batch_world()
  candidates <- atlas_batch_candidates(world$points, min_presences = 20, limit = 1)
  expect_equal(candidates$scientific_name, "Rich one")
})

test_that("a fingerprint is taken from the taxon's own records only", {
  world <- batch_world()
  prints <- atlas_fingerprints_for(world$occurrences, c("Rich one", "Middle one"))
  alone <- world$occurrences[world$occurrences$scientific_name == "Rich one", ]
  expect_equal(prints[["Rich one"]], atlas_fingerprint(alone))
  expect_false(prints[["Rich one"]] == prints[["Middle one"]])
})

test_that("the settings key changes with any setting, and not with their order", {
  base <- atlas_fit_settings(layers = "L1")
  expect_equal(atlas_settings_key(base), atlas_settings_key(rev(base)))
  expect_false(atlas_settings_key(base) ==
                 atlas_settings_key(atlas_fit_settings(layers = "L2")))
  expect_false(atlas_settings_key(base) ==
                 atlas_settings_key(atlas_fit_settings(correlation = 0.6, layers = "L1")))
  expect_false(atlas_settings_key(base) ==
                 atlas_settings_key(atlas_fit_settings(prune = FALSE, layers = "L1")))
})

test_that("rebuilding a layer changes the layers key, so every model goes stale", {
  before <- list(list(id = "bioclim", md5 = "aaa"), list(id = "soil", md5 = "bbb"))
  after <- list(list(id = "bioclim", md5 = "aaa"), list(id = "soil", md5 = "ccc"))
  added <- c(before, list(list(id = "landcover", md5 = "ddd")))
  expect_false(atlas_layers_key(manifest = before) == atlas_layers_key(manifest = after))
  expect_false(atlas_layers_key(manifest = before) == atlas_layers_key(manifest = added))
  expect_equal(atlas_layers_key(manifest = before), atlas_layers_key(manifest = rev(before)))
})

test_that("a stored fit is current only for the same records and settings", {
  with_data_dir({
    settings <- atlas_fit_settings(layers = "L1")
    metrics <- list(fingerprint = "abc", settings_key = atlas_settings_key(settings))
    expect_true(atlas_fit_is_current(metrics, "abc", settings, predict = FALSE))
    expect_false(atlas_fit_is_current(metrics, "abd", settings, predict = FALSE))
    expect_false(atlas_fit_is_current(
      metrics, "abc", atlas_fit_settings(layers = "L2"), predict = FALSE
    ))
    expect_false(atlas_fit_is_current(NULL, "abc", settings, predict = FALSE))
  })
})

test_that("a fit from before fingerprints were stored is never current", {
  settings <- atlas_fit_settings(layers = "L1")
  old <- list(seed = 55715061, settings_key = atlas_settings_key(settings))
  expect_false(atlas_fit_is_current(old, "abc", settings, predict = FALSE))
})

test_that("a scores-only fit is not current when a map is wanted", {
  with_data_dir({
    settings <- atlas_fit_settings(layers = "L1")
    metrics <- list(fingerprint = "abc", settings_key = atlas_settings_key(settings))
    expect_false(atlas_fit_is_current(metrics, "abc", settings, predict = TRUE))

    metrics$raster <- "some-taxon.tif"
    expect_false(atlas_fit_is_current(metrics, "abc", settings, predict = TRUE))
    dir.create(atlas_path("models", "draft"), recursive = TRUE)
    writeLines("x", atlas_path("models", "draft", "some-taxon.tif"))
    expect_true(atlas_fit_is_current(metrics, "abc", settings, predict = TRUE))
  })
})

test_that("one taxon failing does not stop the rest of the run", {
  with_data_dir({
    world <- batch_world(c("Broken one" = 50, "Rich one" = 40, "Middle one" = 25))
    result <- run_batch(world)
    expect_equal(
      statuses(result)[c("Broken one", "Rich one", "Middle one")],
      c("Broken one" = "failed", "Rich one" = "fitted", "Middle one" = "fitted")
    )
    broken <- result$taxa[[which(names(statuses(result)) == "Broken one")]]
    expect_match(broken$error, "on fire")
  })
})

test_that("a refusal is counted apart from a failure", {
  with_data_dir({
    world <- batch_world(c("Rich one" = 40, "Sparse one" = 25))
    result <- run_batch(world)
    expect_equal(result$counts$refused, 1L)
    expect_equal(result$counts$failed, 0L)
    expect_equal(result$counts$fitted, 1L)
  })
})

test_that("a second run skips taxa whose records have not changed", {
  with_data_dir({
    world <- batch_world()
    first <- run_batch(world)
    expect_equal(first$counts$fitted, 2L)

    again <- run_batch(world)
    expect_equal(again$counts$fitted, 0L)
    expect_equal(again$counts$skipped, 2L)
  })
})

test_that("a changed record set is refitted, and only that taxon", {
  with_data_dir({
    world <- batch_world()
    run_batch(world)
    edited <- world
    first_middle <- which(edited$occurrences$scientific_name == "Middle one")[1]
    edited$occurrences$observed_on[first_middle] <- "2026-05-05"

    result <- run_batch(edited)
    expect_equal(statuses(result)[["Middle one"]], "fitted")
    expect_equal(statuses(result)[["Rich one"]], "skipped")
  })
})

test_that("new layers make every stored model stale", {
  with_data_dir({
    world <- batch_world()
    run_batch(world)
    result <- atlas_fit_batch(
      occurrences = world$occurrences, points = world$points,
      layers = "rebuilt-layers", fit = fake_fit, quiet = TRUE
    )
    expect_equal(result$counts$fitted, 2L)
  })
})

test_that("force refits even what is current", {
  with_data_dir({
    world <- batch_world()
    run_batch(world)
    expect_equal(run_batch(world, force = TRUE)$counts$fitted, 2L)
  })
})

test_that("a scores-only run is not taken as current by a run that wants maps", {
  with_data_dir({
    world <- batch_world()
    run_batch(world, predict = FALSE)
    expect_equal(run_batch(world, predict = FALSE)$counts$skipped, 2L)
    expect_equal(run_batch(world, predict = TRUE)$counts$fitted, 2L)
  })
})

test_that("a trial run fits only as many taxa as its limit", {
  with_data_dir({
    result <- run_batch(batch_world(), limit = 1)
    expect_equal(names(statuses(result)), "Rich one")
  })
})

test_that("the batch summary is written, with counts and every taxon", {
  with_data_dir({
    result <- run_batch(batch_world(c("Broken one" = 50, "Rich one" = 40)))
    expect_true(file.exists(result$path))
    saved <- jsonlite::fromJSON(atlas_path("batches", "draft", "latest.json"),
                                simplifyVector = FALSE)
    expect_equal(saved$counts$fitted, 1L)
    expect_equal(saved$counts$failed, 1L)
    expect_equal(length(saved$taxa), 2L)
    expect_false(is.null(saved$finished_at))
    expect_equal(saved$settings$layers, "test-layers")
  })
})

test_that("the summary never carries a coordinate", {
  with_data_dir({
    result <- run_batch(batch_world())
    text <- paste(readLines(result$path), collapse = "\n")
    expect_false(grepl("latitude|longitude|\"x\"|\"y\"", text))
  })
})

test_that("workers fit in parallel and still keep one failure to itself", {
  skip_on_cran()
  root <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  skip_if_not(file.exists(file.path(root, "R", "batch.R")), "sources not found")
  with_env(c(ATLAS_ROOT = root), with_data_dir({
    world <- batch_world(c("Broken one" = 50, "Rich one" = 40, "Middle one" = 25))
    result <- run_batch(world, workers = 2L)
    expect_equal(
      statuses(result)[c("Broken one", "Rich one", "Middle one")],
      c("Broken one" = "failed", "Rich one" = "fitted", "Middle one" = "fitted")
    )
    # The workers wrote to the same data directory as this process.
    expect_true(file.exists(atlas_model_path("Rich one", "draft", ".json")))
  }))
})

test_that("a worker's result is recorded as soon as it is ready, not at the end", {
  skip_on_cran()
  cluster <- parallel::makePSOCKcluster(2L)
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  task <- function(name) {
    if (name == "slow") Sys.sleep(3)
    name
  }
  environment(task) <- globalenv()
  arrived <- character()
  atlas_run_on_workers(cluster, c("slow", "a", "b", "c"), task,
                       function(value) arrived <<- c(arrived, value))
  # All four came back, and the quick ones did not wait for the slow one.
  expect_setequal(arrived, c("slow", "a", "b", "c"))
  expect_equal(arrived[length(arrived)], "slow")
})

test_that("a worker that throws is recorded as a failure, not a crash", {
  skip_on_cran()
  cluster <- parallel::makePSOCKcluster(1L)
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  task <- function(name) if (name == "bad") stop("boom") else list(taxon = name, status = "fitted")
  environment(task) <- globalenv()
  rows <- list()
  atlas_run_on_workers(cluster, c("bad", "good"), task,
                       function(value) rows[[length(rows) + 1L]] <<- value)
  expect_equal(vapply(rows, function(r) r$status, character(1)), c("failed", "fitted"))
  expect_equal(rows[[1]]$taxon, "bad")
})

# --- Real fits on a synthetic landscape -------------------------------------

test_that("a real fit records its fingerprint, and a scores-only fit draws no map", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    fit <- function(predict) {
      atlas_fit_taxon(
        "Eastern fungus", points = world$points, stack = world$stack,
        fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
        buffer_km = 300, predict = predict, quiet = TRUE
      )
    }
    with_map <- fit(TRUE)
    expect_equal(with_map$metrics$fingerprint, "f00dfeed")
    expect_true(file.exists(atlas_model_path("Eastern fungus")))
    expect_gt(with_map$metrics$auc_mean, 0.6)

    settings <- atlas_fit_settings(n_background = 500, buffer_km = 300, layers = "synthetic")
    stored <- atlas_read_metrics("Eastern fungus")
    expect_true(atlas_fit_is_current(stored, "f00dfeed", settings, predict = TRUE))

    scores_only <- fit(FALSE)
    expect_null(scores_only$metrics$raster)
    expect_null(scores_only$suitability)
    # The old map would sit beside scores it does not belong to, so it is gone.
    expect_false(file.exists(atlas_model_path("Eastern fungus")))
    expect_false(file.exists(atlas_model_path("Eastern fungus", "draft", ".png")))
  })
})

test_that("a batch of real fits skips what it has already fitted", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    occurrences <- data.frame(
      id = as.character(seq_len(nrow(world$points))),
      scientific_name = world$points$scientific_name,
      latitude = "45", longitude = "-100", observed_on = "2025-01-01",
      stringsAsFactors = FALSE
    )
    batch <- function() {
      atlas_fit_batch(
        occurrences = occurrences, points = world$points, stack = world$stack,
        layers = "synthetic", n_background = 500, buffer_km = 300,
        predict = FALSE, quiet = TRUE
      )
    }
    first <- batch()
    expect_equal(first$counts$fitted, 2L)
    expect_equal(first$counts$failed, 0L)
    expect_equal(batch()$counts$skipped, 2L)
  })
})

test_that("too few presence cells is a refusal a batch can recognise", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    condition <- tryCatch(
      atlas_fit_taxon(
        "Eastern fungus", points = world$points, stack = world$stack,
        fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
        min_presences = 1000, quiet = TRUE
      ),
      error = function(e) e
    )
    expect_s3_class(condition, "atlas_insufficient_evidence")
    expect_match(conditionMessage(condition), "survey target, not a model")
  })
})

test_that("a worker that dies costs its taxa, not the run", {
  skip_on_cran()
  cluster <- parallel::makePSOCKcluster(2L)
  on.exit(try(parallel::stopCluster(cluster), silent = TRUE), add = TRUE)
  # "crash" kills its worker outright, as running out of memory would.
  task <- function(name) {
    if (name == "crash") quit(save = "no", status = 1)
    Sys.sleep(0.3)
    list(taxon = name, status = "fitted")
  }
  environment(task) <- globalenv()
  rows <- list()
  expect_no_error(
    atlas_run_on_workers(cluster, c("a", "crash", "b", "c", "d"), task,
                         function(value) rows[[length(rows) + 1L]] <<- value)
  )
  reported <- vapply(rows, function(r) r$taxon, character(1))
  expect_setequal(reported, c("a", "crash", "b", "c", "d"))
  expect_equal(anyDuplicated(reported), 0L)
  crash <- rows[[which(reported == "crash")]]
  expect_equal(crash$status, "failed")
  expect_match(crash$error, "worker lost")
})

test_that("a full run clears out models for taxa no longer eligible", {
  with_data_dir({
    world <- batch_world(c("Rich one" = 60, "Thirty cells" = 30))
    # Tree maps fitted for both, before trees had a 50-cell minimum.
    fake_fit("Thirty cells", fingerprint = "old", algorithm = "xgboost")
    result <- run_batch(world, algorithm = "xgboost")
    expect_equal(unlist(result$removed), "Thirty cells")
    expect_false(file.exists(atlas_model_path("Thirty cells", "draft", ".json", "xgboost")))
    expect_equal(statuses(result)[["Rich one"]], "fitted")
    # Maxent has no such minimum: the same taxon is still mapped there.
    expect_equal(statuses(run_batch(world))[["Thirty cells"]], "fitted")
  })
})

test_that("a trial run never deletes anything", {
  with_data_dir({
    world <- batch_world(c("Rich one" = 60, "Thirty cells" = 30))
    fake_fit("Thirty cells", fingerprint = "old", algorithm = "xgboost")
    run_batch(world, algorithm = "xgboost", limit = 1)
    expect_true(file.exists(atlas_model_path("Thirty cells", "draft", ".json", "xgboost")))
  })
})
