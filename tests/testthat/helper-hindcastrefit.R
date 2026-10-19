# Shared by the hindcast refit tests (test-hindcastrefit.R).

# A fit that does what a real one does with its inputs and nothing it does
# not need: builds the taxon's training table from the points it is handed
# (sites, effort, background drawn by the seed), draws with that seed as
# folds and null tests do, and writes a model whose every byte follows from
# them and from the settings it was called with. watch, when given, sees
# each call's taxon, points and training table; refuse names an algorithm
# whose model of a taxon is refused as too sparse.
seeded_fit <- function(grades = list(), watch = NULL, refuse = list()) {
  function(name, fingerprint, grid = "draft", algorithm = "maxnet", n_background = 10000, buffer_km = 500,
           points = NULL, seed_from = NULL, ...) {
    args <- list(...)
    if (identical(refuse[[name]], algorithm)) stop(atlas_insufficient_evidence(name, 5, grid, 20))
    training <- atlas_training_table(name, points, n_background = n_background, buffer_km = buffer_km,
                                     fingerprint = fingerprint, seed_from = seed_from)
    if (is.function(watch)) watch(name, algorithm, points, training)
    seed <- attr(training, "seed")
    # Drawn without moving the session's generator: machine() names fresh
    # data directories from it, and a reseeded one would hand a "fresh"
    # machine one already in use.
    state <- get0(".Random.seed", envir = globalenv(), inherits = FALSE)
    on.exit(if (is.null(state)) rm(".Random.seed", envir = globalenv()) else
      assign(".Random.seed", state, envir = globalenv()), add = TRUE)
    set.seed(seed)
    draws <- sample.int(1e6, 5)
    presences <- sum(training$presence == 1L)
    dir.create(atlas_model_dir(grid, algorithm), recursive = TRUE, showWarnings = FALSE)
    r <- terra::rast(ncols = 10, nrows = 10, xmin = -2.2e6, xmax = -2.1e6, ymin = 5e5, ymax = 6e5, crs = ATLAS_CRS)
    terra::values(r) <- (seq_len(100) * draws[[1]] + presences) %% 997
    raster <- atlas_model_path(name, grid, ".tif", algorithm)
    terra::writeRaster(r, raster, overwrite = TRUE)
    metrics <- list(
      taxon = name, algorithm = algorithm, fingerprint = fingerprint, presences = presences, seed = seed,
      draws = draws, training = digest::digest(as.data.frame(training), algo = "sha256"),
      settings = c(list(n_background = n_background, buffer_km = buffer_km),
                   args[intersect(names(args), c("nulls", "folds", "block_km", "regmult", "correlation",
                                                 "min_presences", "layers", "tune", "prune"))]),
      raster = basename(raster), map = "x.png",
      # Named as a real fit names them (R/fit.R): pooled Boyce is "boyce".
      auc_mean = round(0.6 + (draws[[2]] %% 300) / 1000, 3), boyce = round((draws[[3]] %% 900) / 1000, 3),
      boyce_mean = round((draws[[3]] %% 700) / 1000, 3),
      grade = grades[[name]] %||% "weak"
    )
    atlas_write_json(metrics, atlas_model_path(name, grid, ".json", algorithm))
    list(metrics = metrics)
  }
}

# Finish a private release as production does: on a worker that may not
# write private/, then the box places what it made.
finish_private <- function(store, id, ensembles = function(...) NULL) {
  on_machine(machine(), atlas_finish_private_release_work(
    worker_store(store), id, quiet = TRUE, count = function(...) 0L,
    ensembles = ensembles, build = stub_finish_build, defer = TRUE))
  record <- atlas_store_text(store, atlas_shard_key(atlas_finish_id(id), 1L))
  atlas_place_deferred(store, record$deferred)
  atlas_store_text(store, atlas_benchmark_key(id, "summary.json"))
}

run_private <- function(store, job, fit) {
  for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(store, job$id, n, quiet = TRUE, fit = fit))
}

# A finished hindcast, fitted with seeded_fit, ready to be refitted.
finished_hindcast <- function(grades = list("Taxon A" = "strong", "Taxon B" = "weak", "Taxon C" = "weak"),
                              refuse = list(), ensembles = function(...) NULL) {
  setup <- hindcast_setup()
  hind <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "hindcast",
                                                            HINDCAST_CUTOFF, shards = 1L, quiet = TRUE))
  run_private(setup$store, hind, seeded_fit(grades, refuse = refuse))
  finish_private(setup$store, hind$id, ensembles)
  c(setup, list(hindcast = hind))
}

# Plan a refit of the finished hindcast, as the box does.
plan_refit <- function(setup, taxa, leave_out = character(), ..., reason = "a test of the refit") {
  on_machine(setup$boss, atlas_plan_hindcast_refit(setup$store, setup$hindcast$id, taxa, leave_out,
                                                   reason = reason, quiet = TRUE, ...))
}

# A combined map for Taxon B, as finishing's ensembles would make one.
ensemble_for_b <- function(grid = "draft", quiet = TRUE) {
  dir <- atlas_path("models", grid, "ensemble")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("{}", file.path(dir, "taxon-b.json"))
}

# The hindcast's algorithms with a model of a taxon.
hindcast_algorithms <- function(setup, taxon) {
  manifest <- atlas_store_text(setup$store, atlas_benchmark_key(setup$hindcast$id, "release.json"))
  sort(unique(vapply(Filter(function(e) identical(e$taxon, taxon) && !isTRUE(e$refused), manifest$index),
                     function(e) e$algorithm, "")))
}

# The .org ids of a taxon's records in a job's pull.
pull_ids <- function(store, job, taxon) {
  pull <- job_pull(store, job)
  as.character(pull$id[pull$scientific_name == taxon])
}

# A taxon's model files and index entries as a job's shards uploaded them.
shard_models <- function(store, job, taxon) {
  records <- lapply(seq_len(job$shards), function(n) atlas_store_text(store, atlas_shard_key(job$id, n)))
  files <- unlist(lapply(records, function(r) r$files), recursive = FALSE)
  slug <- paste0("/", basename(atlas_model_path(taxon, extension = "")), ".")
  files <- Filter(function(f) grepl(slug, f$path, fixed = TRUE), files)
  index <- Filter(function(e) identical(e$taxon, taxon), unlist(lapply(records, function(r) r$index), recursive = FALSE))
  list(files = files[order(vapply(files, function(f) f$path, ""))],
       index = index[order(vapply(index, function(e) e$algorithm, ""))])
}

# Every key under some prefixes of a store (or at them), with the hash of
# what it holds.
store_snapshot <- function(store, prefixes) {
  keys <- sort(unlist(lapply(prefixes, function(p) {
    keys <- store$list(p)
    if (!length(keys) && store$exists(p)) p else keys
  })))
  stats::setNames(vapply(keys, function(k) {
    file <- tempfile()
    on.exit(unlink(file), add = TRUE)
    store$get(k, file)
    atlas_sha256(file)
  }, ""), keys)
}

# Every file under a directory, with its hash.
dir_snapshot <- function(dir) {
  files <- sort(list.files(dir, recursive = TRUE, all.files = TRUE))
  stats::setNames(vapply(file.path(dir, files), atlas_sha256, ""), files)
}
