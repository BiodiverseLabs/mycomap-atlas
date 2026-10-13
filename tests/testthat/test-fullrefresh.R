# A full-view refresh: a release's strong models refitted for their full
# views alone, published as a new release that changes nothing else, and
# never published if a refit does not reproduce its model.

store_json <- function(store, release, path) {
  file <- tempfile(fileext = ".json")
  store$get(atlas_object_key(release_hash(release, path)), file)
  jsonlite::fromJSON(file, simplifyVector = FALSE)
}

test_that("a refresh replaces only the strong models' full views, and keeps everything else the release had", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  main <- setup$main
  out <- run_refresh(setup)
  job <- out$job
  refreshed <- out$release
  # The strong models only: Taxon A and B, Maxent and forest.
  expect_setequal(vapply(job$tasks, function(t) paste(t$algorithm, t$taxon), ""),
                  c("maxnet Taxon A", "rf Taxon A", "maxnet Taxon B", "rf Taxon B"))
  expect_equal(job$fit$nulls, 0)
  expect_true(job$fit$full)
  # The same files, the same model index.
  expect_setequal(release_paths(refreshed), release_paths(main))
  expect_identical(refreshed$index, main$index)
  strong_full <- unlist(lapply(job$tasks, function(t) atlas_model_relpaths(t$taxon, "draft", t$algorithm, ATLAS_FULL_EXTS)))
  strong_json <- unlist(lapply(job$tasks, function(t) atlas_model_relpaths(t$taxon, "draft", t$algorithm, ".json")))
  for (path in release_paths(main)) {
    if (path %in% strong_full) next
    if (path %in% strong_json) next
    expect_identical(release_hash(refreshed, path), release_hash(main, path), info = path)
  }
  # The new full views, and the metrics that describe them.
  for (path in strong_full[grepl("[.]full[.]png$", strong_full)]) {
    expect_false(identical(release_hash(refreshed, path), release_hash(main, path)), info = path)
  }
  for (path in strong_json) {
    before <- store_json(setup$store, main, path)
    after <- store_json(setup$store, refreshed, path)
    expect_null(after$full_map$bounds)          # the refit's description, not the old one
    expect_equal(after$grade, "strong")         # the release's grade, not the refit's
    before$full_map <- NULL
    after$full_map <- NULL
    expect_identical(after, before, info = path)
  }
  # A release of its own, promoted with a record of it.
  expect_equal(atlas_current_release(setup$store)$id, refreshed$id)
  history <- atlas_promotion_history(setup$store)
  expect_equal(utils::tail(history$release, 1), refreshed$id)
  expect_equal(utils::tail(history$previous, 1), main$id)
  expect_equal(refreshed$full_refresh$from, main$id)
  expect_equal(refreshed$job, main$job)
  # Trained on what R_main was.
  expect_true(setup$store$exists(atlas_trained_release_key(refreshed$id)))
})

test_that("a refit that does not reproduce its model's default map stops the refresh, and nothing is published", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  fit <- map_fit()
  drifted <- function(name, fingerprint, grid = "draft", algorithm = "maxnet", ...) {
    out <- fit(name, fingerprint, grid = grid, algorithm = algorithm, ...)
    if (identical(name, "Taxon A") && identical(algorithm, "maxnet")) {
      r <- terra::rast(atlas_model_path(name, grid, ".tif", algorithm))
      terra::writeRaster(r * 2, atlas_model_path(name, grid, ".tif", algorithm), overwrite = TRUE)
    }
    out
  }
  out <- run_refresh(setup, fit = drifted, publish = FALSE)
  expect_error(on_machine(setup$boss, atlas_finish_full_refresh(setup$store, out$job$id, quiet = TRUE)),
               "maxnet Taxon A: taxon-a[.]tif differs")
  expect_equal(atlas_current_release(setup$store)$id, setup$main$id)
  refused <- atlas_store_text(setup$store, paste0("jobs/draft/", out$job$id, "/refused.json"))
  expect_length(refused$problems, 1L)
})

test_that("a model that was not refitted stops the refresh: it is published whole or not at all", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  fit <- map_fit()
  failing <- function(name, ...) {
    if (identical(name, "Taxon B")) stop("a worker's bad day")
    fit(name, ...)
  }
  out <- run_refresh(setup, fit = failing, publish = FALSE)
  expect_error(on_machine(setup$boss, atlas_finish_full_refresh(setup$store, out$job$id, quiet = TRUE)),
               "Taxon B: not refitted")
  expect_equal(atlas_current_release(setup$store)$id, setup$main$id)
})

test_that("a refresh is never finished as a job is, nor published over a release that moved on", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  out <- run_refresh(setup, publish = FALSE)
  expect_error(on_machine(setup$boss, atlas_finish_job(setup$store, out$job$id, quiet = TRUE)),
               "full-view refresh")
  # Another release made current after the plan. Its files differ from
  # R_main's: a release id is the second it was made and its files' hash, so
  # the same files in the same second would be R_main itself, not another.
  other <- atlas_write_release(setup$store, "draft", setup$main$files[-1], setup$main$index,
                               previous = setup$main$id, note = "another", quiet = TRUE,
                               extra = list(job = setup$main$job, moved = TRUE))
  expect_error(on_machine(setup$boss, atlas_finish_full_refresh(setup$store, out$job$id, quiet = TRUE)),
               "plan again")
})

test_that("a refresh is planned only for models fitted on the release's own pull", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  index <- lapply(setup$main$index, function(e) {
    if (identical(e$taxon, "Taxon A") && identical(e$algorithm, "rf")) e$fingerprint <- "an older pull"
    e
  })
  carried <- atlas_write_release(setup$store, "draft", setup$main$files, index, previous = setup$main$id,
                                 quiet = TRUE, extra = list(job = setup$main$job))
  expect_error(on_machine(setup$boss, atlas_plan_full_refresh(setup$store, carried$id, quiet = TRUE)),
               "rf Taxon A")
})

test_that("a dry run says what a refresh would refit and cost, and writes nothing", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  before <- setup$store$list("jobs/")
  dry <- on_machine(setup$boss, atlas_plan_full_refresh(setup$store, setup$main$id, quiet = TRUE, dry_run = TRUE))
  expect_identical(setup$store$list("jobs/"), before)
  expect_equal(dry$estimate$models, 4L)
  expect_equal(dry$estimate$taxa, 2L)
  expect_equal(dry$estimate$cpu_hours,
               round(2 * (ATLAS_REFRESH_MINUTES[["maxnet"]] + ATLAS_REFRESH_MINUTES[["rf"]]) / 60, 1))
})

test_that("the new-find tracker sees nothing new in a refresh: the same maps, versions and grades", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  refreshed <- run_refresh(setup)$release
  cache <- file.path(tempdir(), paste0("tracker-cache-", as.integer(stats::runif(1, 1, 1e9))))
  before <- atlas_tracker_view(setup$store, setup$main$id, "draft", cache)
  after <- atlas_tracker_view(setup$store, refreshed$id, "draft", cache)
  for (taxon in c("Taxon A", "Taxon B", "Taxon C")) {
    expect_identical(atlas_tracker_version(after, taxon), atlas_tracker_version(before, taxon), info = taxon)
    a <- atlas_tracker_maps(after, taxon)
    b <- atlas_tracker_maps(before, taxon)
    expect_identical(a$grade, b$grade, info = taxon)
    for (algorithm in names(b$models)) {
      expect_identical(a$models[[algorithm]]$rank, b$models[[algorithm]]$rank, info = paste(taxon, algorithm))
      expect_identical(a$models[[algorithm]]$outside, b$models[[algorithm]]$outside, info = paste(taxon, algorithm))
    }
  }
})

test_that("a release two jobs built is refreshed model by model from the job that fitted each", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 22))))
  fit <- map_fit(REFRESH_GRADES)
  # The first job loses Taxon B (its workers died); a second job fits it.
  losing <- function(name, ...) {
    if (identical(name, "Taxon B")) stop("worker lost")
    fit(name, ...)
  }
  first <- full_cycle(store, boss, fit = losing)
  second <- full_cycle(store, boss, fit = fit)
  expect_false(identical(first$job, second$job))
  job <- on_machine(boss, atlas_plan_full_refresh(store, second$id, shards = 4L, quiet = TRUE))
  sources <- stats::setNames(vapply(job$tasks, function(t) t$source_job, ""),
                             vapply(job$tasks, function(t) paste(t$algorithm, t$taxon), ""))
  expect_equal(unname(sources[c("maxnet Taxon A", "rf Taxon A")]), rep(first$job, 2))
  expect_equal(unname(sources[c("maxnet Taxon B", "rf Taxon B")]), rep(second$job, 2))
  # No shard mixes the two jobs' models, and each fetches its own job's inputs.
  for (s in seq_len(job$shards)) {
    mine <- Filter(function(t) identical(as.integer(t$shard), s), job$tasks)
    expect_length(unique(vapply(mine, function(t) t$source_job, "")), 1L)
    owner <- atlas_read_job(store, mine[[1]]$source_job)
    expect_identical(job$shard_inputs[[as.character(s)]], owner$inputs)
  }
  for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(store, job$id, n, quiet = TRUE, fit = map_fit()))
  refreshed <- on_machine(boss, atlas_finish_full_refresh(store, job$id, quiet = TRUE))
  expect_identical(refreshed$index, second$index)
})

test_that("a refit that differs from its model only in floating point's last bits is the same model", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  fit <- map_fit()
  # As another processor's matrix kernels would leave it, once stored as
  # float32: the suitability two rounding steps off, the index 4e-7 off.
  nudged <- function(name, fingerprint, grid = "draft", algorithm = "maxnet", ...) {
    out <- fit(name, fingerprint, grid = grid, algorithm = algorithm, ...)
    path <- atlas_model_path(name, grid, ".tif", algorithm)
    r <- terra::rast(path)
    terra::writeRaster(r * (1 + 2.4e-7), path, overwrite = TRUE)
    di <- atlas_model_path(name, grid, ".di.tif", algorithm)
    if (file.exists(di)) terra::writeRaster(terra::rast(di) + 4e-7, di, overwrite = TRUE)
    out
  }
  out <- run_refresh(setup, fit = nudged, publish = FALSE)
  record <- atlas_store_text(setup$store, atlas_shard_key(out$job$id, 1L))
  verdict <- record$results[[1]]$identity[[".tif"]]
  expect_equal(verdict$status, "within")
  expect_gt(verdict$largest, 0)
  refreshed <- on_machine(setup$boss, atlas_finish_full_refresh(setup$store, out$job$id, quiet = TRUE))
  # The release's own default files, not the nudged ones.
  for (t in out$job$tasks) {
    path <- atlas_model_relpaths(t$taxon, "draft", t$algorithm, ".tif")
    expect_identical(release_hash(refreshed, path), release_hash(setup$main, path))
  }
})

test_that("each shard says which machine fitted it", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  out <- with_env(c(ATLAS_INSTANCE_TYPE = "r7i.8xlarge"), run_refresh(setup, publish = FALSE))
  record <- atlas_store_text(setup$store, atlas_shard_key(out$job$id, 1L))
  expect_equal(record$machine$instance_type, "r7i.8xlarge")
})

test_that("tracing models back through releases ends, even at a release that names itself as its previous", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  looped <- setup$main
  looped$previous <- looped$id
  atlas_store_json(setup$store, paste0("releases/draft/", looped$id, ".json"), looped)
  tasks <- atlas_refresh_tasks(looped)
  tasks[[1]]$fingerprint <- "nowhere"
  sources <- atlas_refresh_sources(setup$store, looped, tasks)
  expect_equal(sources$unresolved, paste(tasks[[1]]$algorithm, tasks[[1]]$taxon))
})

test_that("a refit whose raster cannot be read is refused, not a crashed shard", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  fit <- map_fit()
  broken <- function(name, fingerprint, grid = "draft", algorithm = "maxnet", ...) {
    out <- fit(name, fingerprint, grid = grid, algorithm = algorithm, ...)
    if (identical(name, "Taxon A") && identical(algorithm, "rf")) {
      writeLines("not a raster", atlas_model_path(name, grid, ".tif", algorithm))
    }
    out
  }
  out <- run_refresh(setup, fit = broken, publish = FALSE)
  expect_error(on_machine(setup$boss, atlas_finish_full_refresh(setup$store, out$job$id, quiet = TRUE)),
               "rf Taxon A: taxon-a[.]tif differs from the release's [(]unreadable")
})
