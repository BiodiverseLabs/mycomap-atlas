# Jobs: one refit, split across machines.
#
# A job is how Atlas recomputes on hardware it does not keep. Three steps,
# each on whatever machine suits it:
#
#   plan    (the small always-on box) compare every taxon's record set with
#           what the current release holds, list the (taxon, model) pairs that
#           need fitting, split them into balanced shards, and put the job and
#           its inputs — the pull and the layers — in the store.
#   run     (a worker per shard) fetch the inputs, fit exactly the assigned
#           pairs, upload the results, and write the shard's record last, so a
#           record means the shard finished.
#   finish  (the small box again) check every shard reported, then build the
#           new release from the old one plus each shard's changes, and
#           promote it.
#
# Planning reads the current release's model index, not the models, so it
# needs no model files. A failed taxon keeps its previous model and is picked
# up by the next plan, because its record set still differs from the one its
# model was fitted on.
#
#   jobs/<grid>/<id>/job.json
#   jobs/<grid>/<id>/shards/<n>.json
#   jobs/<grid>/<id>/finished.json
#   layers/<grid>/<key>.json, layers/<grid>/current.json

# ---- layers in the store -------------------------------------------------

#' The files that make a grid's layer set: every built layer and its manifest.
atlas_layer_set_files <- function(grid = "draft") {
  dir <- atlas_layer_dir(grid)
  files <- c(list.files(dir, pattern = "[.]tif$"), if (file.exists(file.path(dir, "manifest.json"))) "manifest.json")
  if (!length(files)) return(character())
  file.path("layers", grid, files)
}

#' Put this machine's built layers in the store, so workers can fetch them.
atlas_publish_layers <- function(store = atlas_store(), grid = "draft", quiet = FALSE) {
  paths <- atlas_layer_set_files(grid)
  if (!length(paths)) stop("no layers built for the ", grid, " grid", call. = FALSE)
  entries <- atlas_file_entries(paths)
  uploaded <- atlas_upload_objects(store, entries)
  key <- atlas_layers_key(grid)
  set <- list(key = key, grid = grid, files = entries,
              published_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  atlas_store_json(store, paste0("layers/", grid, "/", key, ".json"), set)
  atlas_store_json(store, paste0("layers/", grid, "/current.json"), list(key = key))
  if (!isTRUE(quiet)) {
    message("layers for the ", grid, " grid: uploaded ", uploaded$count, " of ",
            length(paths), " files (", round(uploaded$bytes / 1048576, 1), " MB)")
  }
  invisible(set)
}

#' The layer set the store currently holds for a grid, or NULL.
atlas_current_layers <- function(store = atlas_store(), grid = "draft") {
  pointer <- paste0("layers/", grid, "/current.json")
  if (!store$exists(pointer)) return(NULL)
  key <- atlas_store_text(store, pointer)$key
  atlas_store_text(store, paste0("layers/", grid, "/", key, ".json"))
}

#' Bring files onto this machine from the store, checking each against its
#' hash, and skipping those already here with the right content.
atlas_fetch_entries <- function(store, entries) {
  fetched <- 0L
  bytes <- 0
  for (entry in entries) {
    dest <- file.path(atlas_data_dir(), entry$path)
    if (file.exists(dest) && identical(atlas_sha256(dest), entry$sha256)) next
    staging <- paste0(dest, ".part")
    store$get(atlas_object_key(entry$sha256), staging)
    if (!identical(atlas_sha256(staging), entry$sha256)) {
      unlink(staging)
      stop("the store's copy of ", entry$path, " does not match its hash; nothing replaced",
           call. = FALSE)
    }
    file.rename(staging, dest)
    fetched <- fetched + 1L
    bytes <- bytes + as.numeric(entry$bytes)
  }
  list(fetched = fetched, bytes = bytes)
}

# ---- planning ------------------------------------------------------------

# Rough relative cost of fitting and mapping one taxon, for balancing shards.
# Measured on a 40-taxon pilot of nested tuning plus 19 null models
# (2026-09-29, draft grid, scores only): median Maxent 427 s, forest 29 s,
# boosted trees 27 s. Maxent's glmnet path is fitted ~260 times per taxon;
# a forest's map adds about 2.5 minutes for a widespread taxon. A map's cost
# grows with its area.
# The small-model ensemble is not yet timed on its own; its taxa are small.
ATLAS_SHARD_WEIGHTS <- c(maxnet = 7, xgboost = 0.5, rf = 3, esm = 1)

#' The relative cost of one task.
atlas_task_cost <- function(algorithm, area_km2, typical_area = 5e6) {
  weight <- ATLAS_SHARD_WEIGHTS[[algorithm]] %||% 1
  area <- if (is.numeric(area_km2) && length(area_km2) == 1L && is.finite(area_km2)) area_km2 else typical_area
  weight * (0.25 + area / typical_area)
}

#' Split tasks into n shards of nearly equal cost: the costliest task goes to
#' the least-loaded shard, repeatedly. Returns a shard number per task.
atlas_assign_shards <- function(costs, n) {
  n <- max(1L, min(as.integer(n), length(costs)))
  load <- numeric(n)
  shard <- integer(length(costs))
  for (i in order(-costs, seq_along(costs))) {
    target <- which.min(load)
    shard[[i]] <- target
    load[[target]] <- load[[target]] + costs[[i]]
  }
  shard
}

#' Is an index entry still current for these records and settings? A
#' refusal is current while the record set and settings are unchanged: the
#' same records would be refused again.
atlas_index_current <- function(entry, fingerprint, settings, min_presences,
                                max_presences = Inf) {
  if (!is.null(entry) && isTRUE(entry$refused)) {
    return(identical(as.character(entry$fingerprint %||% ""), as.character(fingerprint)) &&
             identical(as.character(entry$settings_key %||% ""), atlas_settings_key(settings)))
  }
  !is.null(entry) &&
    identical(as.character(entry$fingerprint %||% ""), as.character(fingerprint)) &&
    identical(as.character(entry$settings_key %||% ""), atlas_settings_key(settings)) &&
    (isTRUE(entry$map) ||
       (isTRUE(entry$map_withheld) &&
          atlas_map_withheld_at(settings$algorithm %||% entry$algorithm %||% "maxnet",
                                as.numeric(entry$presences %||% NA)))) &&
    as.numeric(entry$presences %||% 0) >= min_presences &&
    as.numeric(entry$presences %||% 0) <= max_presences
}

#' Plan a job: what needs fitting, split into shards, with its inputs stored.
#'
#' Runs where the pull was made. Layers come from this machine when built
#' here, otherwise from the store. Returns the job, or NULL when there is
#' nothing to do.
atlas_plan_job <- function(store = atlas_store(), grid = "draft", algorithms = "all",
                           shards = 4L, min_presences = 20, n_background = 10000,
                           buffer_km = 500, folds = 5, block_km = "auto", regmult = 1,
                           correlation = 0.7, tasks_per_shard = NULL, limit = Inf, quiet = FALSE,
                           nulls = ATLAS_NULL_REPS, tune = TRUE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  algorithms <- if (length(algorithms) == 1L) atlas_parse_algorithms(algorithms) else algorithms
  if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) || limit < 1) {
    stop("limit must be a positive number of taxa", call. = FALSE)
  }

  # A machine without layers of its own (the small box) plans from the set in
  # the store. It needs only the manifest, for the layers' key: the rasters
  # are the workers' business, and would fill the box's disk. "Its own" means
  # rasters: the manifest such a machine fetched last time is not a layer set.
  local_layers <- atlas_layer_set_files(grid)
  if (any(grepl("[.]tif$", local_layers))) {
    layer_entries <- atlas_file_entries(local_layers)
  } else {
    set <- atlas_current_layers(store, grid)
    if (is.null(set)) stop("no layers here or in the store for the ", grid, " grid", call. = FALSE)
    layer_entries <- set$files
    atlas_fetch_entries(store, Filter(function(e) basename(e$path) == "manifest.json", layer_entries))
  }
  layers_key <- atlas_layers_key(grid)
  # Every raster the manifest names must go to the workers, or every fit fails.
  named <- file.path("layers", grid, vapply(atlas_layer_manifest(grid), function(x) x$file %||% "", ""))
  lacking <- setdiff(named[nzchar(basename(named))], vapply(layer_entries, function(e) e$path, ""))
  if (length(lacking)) {
    stop("the layer set for the ", grid, " grid lacks ", paste(lacking, collapse = ", "),
         "; nothing planned", call. = FALSE)
  }

  manifest <- atlas_refresh_public_files()
  if (is.null(manifest)) stop("nothing pulled yet: run ./atlas pull-occurrences", call. = FALSE)
  occurrences <- atlas_read_occurrences()
  points <- atlas_occurrence_points(occurrences, grid)

  base <- atlas_current_release(store, grid)
  index <- list()
  for (entry in base$index %||% list()) index[[paste(entry$algorithm, entry$taxon)]] <- entry
  areas <- vapply(base$index %||% list(), function(e) {
    if (is.numeric(e$area_km2) && length(e$area_km2) == 1L) e$area_km2 else NA_real_
  }, numeric(1))
  typical <- if (any(is.finite(areas))) stats::median(areas, na.rm = TRUE) else 5e6

  # The guild table is part of Maxent's settings (R/fit.R), so the workers
  # must fit with the same one this plan was checked against.
  fit <- list(min_presences = min_presences, n_background = n_background, buffer_km = buffer_km,
              folds = folds, block_km = block_km, regmult = regmult, correlation = correlation,
              nulls = nulls, tune = tune, guild_table = atlas_guild_table_key())
  tasks <- list()
  retire <- list()
  for (algorithm in algorithms) {
    algo <- atlas_algorithm(algorithm)
    minimum <- atlas_algorithm_min(algo, min_presences)
    settings <- atlas_fit_settings(
      grid = grid, n_background = n_background, buffer_km = buffer_km, folds = folds,
      block_km = block_km, regmult = regmult, correlation = correlation,
      prune = algo$prune, layers = layers_key, algorithm = algo$id,
      nulls = nulls, tune = tune
    )
    maximum <- atlas_algorithm_max(algo)
    candidates <- atlas_batch_candidates(points, minimum,
                                         max_presences = maximum + ATLAS_RANGE_MARGIN)$scientific_name
    fingerprints <- atlas_fingerprints_for(occurrences, candidates)
    for (name in candidates) {
      entry <- index[[paste(algorithm, name)]]
      if (atlas_index_current(entry, fingerprints[[name]], settings, minimum, maximum)) next
      tasks[[length(tasks) + 1L]] <- list(
        taxon = name, algorithm = algorithm, fingerprint = fingerprints[[name]],
        cost = atlas_task_cost(algorithm, entry$area_km2, typical)
      )
    }
    for (entry in base$index %||% list()) {
      if (identical(entry$algorithm, algorithm) && !entry$taxon %in% candidates) {
        retire[[length(retire) + 1L]] <- list(taxon = entry$taxon, algorithm = algorithm)
      }
    }
  }

  # A limited job fits only the richest few taxa that need it (a trial run).
  # It cuts only what is fitted: retiring still looks at every taxon, and the
  # taxa it leaves out stay stale, so the next plan picks them up.
  deferred <- 0L
  if (is.finite(limit) && length(tasks)) {
    keep <- utils::head(unique(vapply(tasks, function(t) t$taxon, "")), as.integer(limit))
    deferred <- sum(!vapply(tasks, function(t) t$taxon %in% keep, logical(1)))
    tasks <- Filter(function(t) t$taxon %in% keep, tasks)
  }

  public_paths <- c("occurrences/taxa-latest.json", "occurrences/name-merges.json",
                    "public/pull.json", "public/cells.tsv.gz")
  public <- atlas_file_entries(public_paths[file.exists(file.path(atlas_data_dir(), public_paths))])
  base_files <- stats::setNames(
    vapply(base$files %||% list(), function(f) f$sha256, ""),
    vapply(base$files %||% list(), function(f) f$path, "")
  )
  public_changed <- any(vapply(public, function(e) !identical(unname(base_files[e$path]), e$sha256), logical(1)))
  if (!length(tasks) && !length(retire) && !public_changed) {
    say("nothing to do: every model in release ", base$id %||% "(none)", " is current")
    return(invisible(NULL))
  }

  if (length(tasks)) {
    costs <- vapply(tasks, function(t) t$cost, numeric(1))
    # With tasks_per_shard, shards is a ceiling: a small job gets one worker.
    if (!is.null(tasks_per_shard)) shards <- atlas_shard_count(length(tasks), shards, tasks_per_shard)
    assignment <- atlas_assign_shards(costs, shards)
    for (i in seq_along(tasks)) tasks[[i]]$shard <- assignment[[i]]
    shards <- max(assignment)
  } else {
    shards <- 0L
  }

  pull_paths <- c(file.path("occurrences", manifest$file), "occurrences/latest.json")
  # The guild table goes to the workers through the store's private objects
  # like the pull does. It is never listed among a release's files.
  guild_path <- "reference/fungaltraits-genera.csv"
  if (file.exists(file.path(atlas_data_dir(), guild_path))) pull_paths <- c(pull_paths, guild_path)
  inputs <- c(atlas_file_entries(pull_paths), layer_entries)
  atlas_upload_objects(store, c(inputs, public))

  id <- atlas_release_id(digest::digest(list(tasks, retire, base$id), algo = "sha256"))
  job <- list(
    id = id, grid = grid,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    base_release = base$id,
    algorithms = as.list(algorithms),
    shards = shards,
    fit = fit,
    layers_key = layers_key,
    pull = atlas_release_pull_summary(manifest),
    inputs = inputs,
    public = public,
    tasks = tasks,
    retire = retire,
    deferred = deferred
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
  per_algorithm <- table(vapply(tasks, function(t) t$algorithm, ""))
  say("job ", id, ": ", length(tasks), " models to fit (",
      paste(names(per_algorithm), per_algorithm, sep = " ", collapse = ", "), ") in ",
      shards, " shard", if (shards == 1L) "" else "s", "; ", length(retire), " to retire",
      if (deferred) paste0("; ", deferred, " left for a later job (--limit)") else "")
  invisible(job)
}

#' A string field read back from JSON: NULL was written as {} and comes back
#' as an empty list, so anything but a single string is treated as absent.
atlas_json_string <- function(x) {
  if (is.character(x) && length(x) == 1L && nzchar(x)) x else NULL
}

atlas_read_job <- function(store, id, grid = "draft") {
  key <- paste0("jobs/", grid, "/", id, "/job.json")
  if (!store$exists(key)) stop("no job ", id, " for the ", grid, " grid", call. = FALSE)
  atlas_store_text(store, key)
}

# ---- running a shard -----------------------------------------------------

#' Where a shard's record goes, and where its progress is saved on the way.
atlas_shard_key <- function(id, shard, grid = "draft", progress = FALSE) {
  paste0("jobs/", grid, "/", id, "/shards/", shard, if (isTRUE(progress)) ".progress", ".json")
}

#' How often a shard saves what it has fitted so far. A spot worker can be
#' taken back at any moment; what it fitted since its last save is fitted
#' again by the worker that replaces it.
ATLAS_SHARD_SAVE_SECONDS <- 120

#' What a shard saved before its worker was lost: the results that need no
#' refit (fitted or refused; a failure is tried again), with their files and
#' index entries. Empty when nothing was saved.
atlas_shard_progress <- function(store, id, shard, grid = "draft") {
  empty <- list(results = list(), files = list(), index = list())
  key <- atlas_shard_key(id, shard, grid, progress = TRUE)
  if (!store$exists(key)) return(empty)
  saved <- atlas_store_text(store, key)
  if (!identical(saved$job, id) || !identical(as.integer(saved$shard), as.integer(shard))) return(empty)
  keep <- Filter(function(r) r$status %in% c("fitted", "refused"), saved$results %||% list())
  list(results = keep, files = saved$files %||% list(), index = saved$index %||% list())
}

#' One task's line in a shard record.
atlas_shard_result <- function(name, algorithm, row, fingerprint, settings_key) {
  Filter(Negate(is.null), list(
    taxon = name, algorithm = algorithm, status = row$status,
    error = row$error %||% NULL,
    # A refusal is recorded against the record set and settings it was
    # made for, so the next plan does not try it again.
    fingerprint = fingerprint,
    settings_key = settings_key,
    presences = row$presences %||% NULL
  ))
}

#' Run one shard of a job on this machine, and record what it produced.
#'
#' Fits exactly the pairs assigned to the shard, whatever this machine's own
#' currency check would say: the plan decided. Uploads the results, then
#' writes the shard's record — last, so a record means the shard finished.
#' Running a shard again replaces its record.
#'
#' On the way it saves its progress every save_seconds: the models fitted so
#' far are uploaded and listed in a progress record. A worker that runs a
#' shard somebody else started fits only what that progress does not hold.
atlas_run_shard <- function(store = atlas_store(), id, shard, grid = "draft", workers = 1L,
                            quiet = FALSE, fit = atlas_fit_taxon,
                            save_seconds = ATLAS_SHARD_SAVE_SECONDS) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  job <- atlas_read_job(store, id, grid)
  shard <- as.integer(shard)
  mine <- Filter(function(t) identical(as.integer(t$shard), shard), job$tasks)
  if (!length(mine)) stop("shard ", shard, " of job ", id, " has no tasks", call. = FALSE)
  started <- Sys.time()

  fetched <- atlas_fetch_entries(store, job$inputs)
  saved <- atlas_shard_progress(store, id, shard, grid)
  say("shard ", shard, ": ", length(mine), " models to fit",
      if (length(saved$results)) paste0(" (", length(saved$results), " saved by an earlier worker)"),
      "; fetched ", fetched$fetched, " input files (", round(fetched$bytes / 1048576, 1), " MB)")
  # Fitted with another guild table, every Maxent model would carry settings
  # the plan did not check against, and the next plan would refit them all.
  planned <- job$fit$guild_table
  if (is.character(planned) && length(planned) == 1L && !identical(planned, atlas_guild_table_key())) {
    stop("this worker's FungalTraits table differs from the one job ", id,
         " was planned with; nothing fitted", call. = FALSE)
  }

  # What this worker has fitted and not yet saved, and what is saved. Files
  # are uploaded before the progress record that lists them, so a saved
  # record never names an object the store does not hold.
  results <- saved$results
  files <- saved$files
  index <- saved$index
  pending <- list(results = list(), files = list(), index = list())
  stored <- store$list("objects/")
  uploaded <- list(count = 0L, bytes = 0)
  last_save <- Sys.time()
  save <- function(progress = TRUE) {
    upload <- atlas_upload_objects(store, pending$files, stored)
    stored <<- c(stored, vapply(pending$files, function(e) atlas_object_key(e$sha256), ""))
    uploaded$count <<- uploaded$count + upload$count
    uploaded$bytes <<- uploaded$bytes + upload$bytes
    results <<- c(results, pending$results)
    files <<- c(files, pending$files)
    index <<- c(index, pending$index)
    pending <<- list(results = list(), files = list(), index = list())
    last_save <<- Sys.time()
    if (isTRUE(progress)) {
      atlas_store_json(store, atlas_shard_key(id, shard, grid, progress = TRUE), list(
        job = id, shard = shard,
        saved_at = format(last_save, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        results = results, files = files, index = index
      ))
    }
  }
  finish_task <- function(name, algorithm, row, fingerprint, settings_key) {
    pending$results[[length(pending$results) + 1L]] <<-
      atlas_shard_result(name, algorithm, row, fingerprint, settings_key)
    if (identical(row$status, "fitted")) {
      paths <- atlas_model_relpaths(name, grid, algorithm)
      paths <- paths[file.exists(file.path(atlas_data_dir(), paths))]
      pending$files <<- c(pending$files, atlas_file_entries(paths))
      metrics <- tryCatch(
        jsonlite::fromJSON(atlas_model_path(name, grid, ".json", algorithm), simplifyVector = FALSE),
        error = function(e) NULL
      )
      if (is.list(metrics) && !is.null(metrics$taxon)) {
        pending$index[[length(pending$index) + 1L]] <<- atlas_model_index_entry(metrics, algorithm)
      }
    }
  }

  for (algorithm in unique(vapply(mine, function(t) t$algorithm, ""))) {
    tasks <- Filter(function(t) t$algorithm == algorithm, mine)
    fingerprints <- stats::setNames(vapply(tasks, function(t) t$fingerprint, ""),
                                    vapply(tasks, function(t) t$taxon, ""))
    saved_here <- Filter(function(r) identical(r$algorithm, algorithm), saved$results)
    taxa <- setdiff(names(fingerprints), vapply(saved_here, function(r) r$taxon, ""))
    if (!length(taxa)) next
    reported <- character()
    batch <- atlas_fit_batch(
      grid = grid, force = TRUE, workers = workers, taxa = taxa, algorithm = algorithm,
      min_presences = job$fit$min_presences, n_background = job$fit$n_background,
      buffer_km = job$fit$buffer_km, folds = job$fit$folds, block_km = job$fit$block_km,
      regmult = job$fit$regmult, correlation = job$fit$correlation,
      nulls = job$fit$nulls %||% ATLAS_NULL_REPS, tune = job$fit$tune %||% TRUE,
      quiet = TRUE, fit = fit,
      on_row = function(row, settings_key) {
        if (!row$taxon %in% taxa || row$taxon %in% reported) return(invisible(NULL))
        reported <<- c(reported, row$taxon)
        finish_task(row$taxon, algorithm, row, fingerprints[[row$taxon]], settings_key)
        if (as.numeric(difftime(Sys.time(), last_save, units = "secs")) >= save_seconds) save()
      }
    )
    for (name in setdiff(taxa, reported)) {
      finish_task(name, algorithm, list(status = "failed", error = "not a candidate on this worker"),
                  fingerprints[[name]], batch$settings_key)
    }
    save()
  }
  save(progress = FALSE)

  statuses <- table(factor(vapply(results, function(r) r$status, ""),
                           levels = c("fitted", "refused", "failed")))
  record <- list(
    job = id, shard = shard,
    started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    counts = as.list(statuses),
    results = results,
    files = files,
    index = index
  )
  atlas_store_json(store, atlas_shard_key(id, shard, grid), record)
  say("shard ", shard, ": ", statuses[["fitted"]], " fitted, ", statuses[["refused"]], " refused, ",
      statuses[["failed"]], " failed; uploaded ", uploaded$count, " files (",
      round(uploaded$bytes / 1048576, 1), " MB)")
  invisible(record)
}

#' How many of a shard's tasks its saved progress holds: the orchestrator
#' tells a worker that was lost after saving from one that never got going.
atlas_shard_saved_count <- function(store, id, shard, grid = "draft") {
  length(tryCatch(atlas_shard_progress(store, id, shard, grid)$results, error = function(e) list()))
}

# ---- finishing -----------------------------------------------------------

#' Which shards of a job have reported.
atlas_job_status <- function(store = atlas_store(), id, grid = "draft") {
  job <- atlas_read_job(store, id, grid)
  keys <- store$list(paste0("jobs/", grid, "/", id, "/shards/"))
  # Only a shard's record says it finished; its progress record sits beside it.
  names <- basename(keys)
  done <- sort(as.integer(sub("[.]json$", "", names[grepl("^[0-9]+[.]json$", names)])))
  list(job = id, shards = job$shards, done = done,
       missing = setdiff(seq_len(job$shards), done),
       finished = store$exists(paste0("jobs/", grid, "/", id, "/finished.json")))
}

#' Finish a job: every shard must have reported. The new release is the base
#' release with retired and refused models removed, refitted ones replaced,
#' and the public files refreshed. A failed model keeps its previous version.
#' Refuses if another release became current after the job was planned.
#'
#' partial = TRUE finishes a job whose shards did not all report, from what
#' the missing ones saved on the way (atlas_shard_progress): a job stopped by
#' its deadline still publishes every model it fitted, and the next job plans
#' only what is left. A task no shard saved keeps its previous model, as a
#' failed one does.
atlas_finish_job <- function(store = atlas_store(), id, grid = "draft", promote = TRUE,
                             note = NULL, quiet = FALSE, partial = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  job <- atlas_read_job(store, id, grid)
  status <- atlas_job_status(store, id, grid)
  if (length(status$missing) && !isTRUE(partial)) {
    stop("job ", id, " is not finished: shard", if (length(status$missing) > 1L) "s " else " ",
         paste(status$missing, collapse = ", "), " not reported", call. = FALSE)
  }
  current <- atlas_current_release(store, grid)
  base <- atlas_json_string(job$base_release)
  if (!identical(atlas_json_string(current$id), base)) {
    stop("release ", current$id %||% "(none)", " became current after job ", id,
         " was planned from ", base %||% "(none)", "; plan again", call. = FALSE)
  }

  files <- list()
  for (f in current$files %||% list()) files[[f$path]] <- f
  index <- list()
  for (e in current$index %||% list()) index[[paste(e$algorithm, e$taxon)]] <- e
  drop <- function(taxon, algorithm) {
    for (p in atlas_model_relpaths(taxon, grid, algorithm)) files[[p]] <<- NULL
    index[[paste(algorithm, taxon)]] <<- NULL
  }

  for (r in job$retire) drop(r$taxon, r$algorithm)
  counts <- c(fitted = 0L, refused = 0L, failed = 0L)
  for (n in seq_len(job$shards)) {
    record <- if (n %in% status$missing) {
      atlas_shard_progress(store, id, n, grid)
    } else {
      atlas_store_text(store, atlas_shard_key(id, n, grid))
    }
    shard_files <- list()
    for (f in record$files) shard_files[[f$path]] <- f
    for (r in record$results) {
      if (!r$status %in% names(counts)) next
      counts[[r$status]] <- counts[[r$status]] + 1L
      if (identical(r$status, "refused")) {
        drop(r$taxon, r$algorithm)
        index[[paste(r$algorithm, r$taxon)]] <- atlas_refusal_entry(
          r$taxon, r$algorithm, r$fingerprint, r$settings_key, r$presences
        )
      }
      if (identical(r$status, "fitted")) {
        drop(r$taxon, r$algorithm)
        for (p in atlas_model_relpaths(r$taxon, grid, r$algorithm)) {
          if (!is.null(shard_files[[p]])) files[[p]] <- shard_files[[p]]
        }
      }
    }
    for (e in record$index) index[[paste(e$algorithm, e$taxon)]] <- e
  }
  for (f in job$public) files[[f$path]] <- f
  layer_manifest <- Filter(function(f) grepl("manifest[.]json$", f$path), job$inputs)
  for (f in layer_manifest) files[[f$path]] <- f

  release <- atlas_write_release(
    store, grid, unname(files), unname(index),
    previous = current$id, note = note %||% paste("job", id),
    pull = job$pull, layers_key = job$layers_key, promote = promote, quiet = quiet,
    extra = c(
      list(job = id, job_results = as.list(counts), retired = length(job$retire)),
      if (length(status$missing)) list(partial = TRUE, unreported_shards = as.list(status$missing))
    )
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/finished.json"),
                   list(release = release$id, finished_at = release$created_at))
  say("job ", id, " finished", if (length(status$missing)) " in part" else "", ": ",
      counts[["fitted"]], " fitted, ", counts[["refused"]], " refused, ",
      counts[["failed"]], " failed (kept their previous models), ", length(job$retire), " retired",
      if (length(status$missing)) paste0("; shard", if (length(status$missing) > 1L) "s " else " ",
                                         paste(status$missing, collapse = ", "),
                                         " did not report, so only what they saved is in it"))
  invisible(release)
}
