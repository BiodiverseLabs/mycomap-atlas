# Studies that fail on most of their taxa fail as a whole (E6b's first run,
# 2026-10-19: every taxon failed on a missing argument and the shard
# "succeeded" with nothing scored).

test_that("a shard with more than a few failed taxa stops, naming how many and the commonest error", {
  rows <- c(replicate(19, list(status = "scored"), simplify = FALSE),
            list(list(status = "failed", error = "boom")))
  expect_silent(atlas_study_guard(rows))                          # 1 of 20: 5%, not more
  rows[[1]] <- list(status = "failed", error = "boom")
  expect_error(atlas_study_guard(rows, "a study"), "a study: 2 of 20 taxa failed.*commonest error: boom")
  all_failed <- replicate(4, list(status = "failed", error = 'argument "stack" is missing, with no default'),
                          simplify = FALSE)
  expect_error(atlas_study_guard(all_failed), "4 of 4 taxa failed.*stack")
  # Refusals are answers, not failures.
  expect_silent(atlas_study_guard(replicate(5, list(status = "refused"), simplify = FALSE)))
  expect_silent(atlas_study_guard(list()))
})

test_that("a worker whose layers did not open fails each taxon with that reason, never a missing argument", {
  had <- exists(".atlas_stack", envir = globalenv())
  old <- if (had) get(".atlas_stack", envir = globalenv())
  assign(".atlas_points", data.frame(), envir = globalenv())
  assign(".atlas_stack", NULL, envir = globalenv())
  on.exit({
    if (had) assign(".atlas_stack", old, envir = globalenv()) else rm(".atlas_stack", envir = globalenv())
    rm(".atlas_points", envir = globalenv())
  }, add = TRUE)
  row <- atlas_study_worker_task("A", list(A = "f"), "atlas_distance_taxon", list())
  expect_equal(row$status, "failed")
  expect_match(row$error, "predictor layers did not open")
})

test_that("the distance study fetches its release's layers, never the pull, and never over other layers", {
  with_data_dir({
    store <- fresh_store()
    put <- function(path, text) {
      file <- tempfile()
      writeLines(text, file)
      sha <- atlas_sha256(file)
      store$put(atlas_object_key(sha), file)
      list(path = path, sha256 = sha, bytes = file.info(file)$size)
    }
    layer <- put("layers/draft/bio.tif", "a layer")
    pull <- put("occurrences/occurrences-x.tsv.gz", "a pull")
    atlas_store_json(store, "jobs/draft/h1/job.json", list(id = "h1", inputs = list(layer, pull)))
    expect_equal(atlas_distance_fetch_layers(store, list(job = "h1")), 1L)
    expect_true(file.exists(file.path(atlas_data_dir(), "layers/draft/bio.tif")))
    expect_false(file.exists(file.path(atlas_data_dir(), "occurrences/occurrences-x.tsv.gz")))
    expect_equal(atlas_distance_fetch_layers(store, list(job = "h1")), 0L)   # already here: nothing fetched
    writeLines("this machine's own layer", file.path(atlas_data_dir(), "layers/draft/bio.tif"))
    expect_error(atlas_distance_fetch_layers(store, list(job = "h1")), "not the one job h1 fitted on")
    expect_error(atlas_distance_fetch_layers(store, list()), "names no job")
  })
})

test_that("the distance study fails its shard when its taxa fail, after writing its results", {
  local_mocked_bindings(
    atlas_distance_fetch_layers = function(...) 0L,
    atlas_tracker_release_pull = function(...) data.frame(),
    atlas_occurrence_points = function(...) data.frame(),
    atlas_fingerprints_for = function(...) c(A = "f"),
    atlas_distance_record = function(...) NULL,
    atlas_run_study = function(...) list(taxa = list(list(status = "failed", error = "boom")), path = tempfile()),
    atlas_distance_expected = function(view) list(A = 4L)
  )
  view <- list(grid = "draft", modelled = "A", manifest = list(job = "j"), cache = tempfile())
  with_data_dir({
    expect_error(atlas_distance_study(NULL, "h1", view = view, quiet = TRUE),
                 "distance baseline: 1 of 1 taxa failed.*boom")
  })
})

test_that("--taxa runs only the taxa named, and refuses one the release does not model", {
  asked <- NULL
  local_mocked_bindings(
    atlas_distance_fetch_layers = function(...) 0L,
    atlas_tracker_release_pull = function(...) data.frame(),
    atlas_occurrence_points = function(...) data.frame(),
    atlas_fingerprints_for = function(pull, taxa) stats::setNames(rep("f", length(taxa)), taxa),
    atlas_distance_record = function(...) NULL,
    atlas_run_study = function(sample, settings, ...) {
      asked <<- list(taxa = sample$scientific_name, only = settings$only_taxa)
      list(taxa = lapply(sample$scientific_name, function(t) list(status = "scored")), path = tempfile())
    },
    atlas_distance_expected = function(view) list(A = 4L, B = 5L, C = 6L)
  )
  view <- list(grid = "draft", modelled = c("C", "A", "B"), manifest = list(job = "j"), cache = tempfile())
  with_data_dir({
    atlas_distance_study(NULL, "h1", view = view, quiet = TRUE, only_taxa = c("C", "A"))
    expect_equal(asked$taxa, c("A", "C"))
    expect_equal(asked$only, c("C", "A"))
    asked <- NULL
    expect_error(atlas_distance_study(NULL, "h1", view = view, quiet = TRUE, only_taxa = c("A", "Z")),
                 "--taxa names taxa release h1 does not model: Z")
    expect_null(asked)
  })
  # As the CLI reads it: percent-encoded, since study args split on spaces.
  expect_equal(atlas_repro_taxa("Lyophyllaceae%20sp.%20%27PNW01%27|Stropharia%20hardii", "study-distance"),
               c("Lyophyllaceae sp. 'PNW01'", "Stropharia hardii"))
  expect_error(atlas_repro_taxa("", "study-distance"), "study-distance needs --taxa")
})

test_that("--limit takes only the shard's first taxa, for a smoke run", {
  asked <- NULL
  local_mocked_bindings(
    atlas_distance_fetch_layers = function(...) 0L,
    atlas_tracker_release_pull = function(...) data.frame(),
    atlas_occurrence_points = function(...) data.frame(),
    atlas_fingerprints_for = function(pull, taxa) stats::setNames(rep("f", length(taxa)), taxa),
    atlas_distance_record = function(...) NULL,
    atlas_run_study = function(sample, ...) {
      asked <<- sample$scientific_name
      list(taxa = lapply(sample$scientific_name, function(t) list(status = "scored")), path = tempfile())
    },
    atlas_distance_expected = function(view) list(A = 4L, B = 5L, C = 6L)
  )
  view <- list(grid = "draft", modelled = c("C", "A", "B"), manifest = list(job = "j"), cache = tempfile())
  with_data_dir({
    atlas_distance_study(NULL, "h1", view = view, quiet = TRUE, limit = 2)
    expect_equal(asked, c("A", "B"))
    atlas_distance_study(NULL, "h1", view = view, quiet = TRUE)
    expect_equal(asked, c("A", "B", "C"))
  })
})
