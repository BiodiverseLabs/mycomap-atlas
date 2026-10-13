# A full-view refresh: a release's strong models refitted for their
# full-extent views alone (Steve, 2026-10-13).
#
# The 2026-10-13 rebuild drew every strong map's full view with thin streaks
# of missing ground, where the states and provinces of the boundary file do
# not meet (R/fullextent.R, atlas_full_scope). The default maps were right.
# A release keeps no fitted models, only their rasters, so the missing ground
# can be predicted only by fitting again. This job does that for the strong
# models alone, and changes nothing else:
#
#   - plan from a release (R_main): its strong (taxon, algorithm) models,
#     each on the very pull, layers and FungalTraits table of the job that
#     fitted it (a release can hold models of several jobs: the 2026-10-13
#     rebuild was stopped and finished by a second job, on the same pull),
#     found by walking back through the releases before it. Their settings,
#     but no null tests (the grades are R_main's) and a full view for every
#     one;
#   - check each refit against R_main: it must be the same model. The same
#     data, settings, layers, seeds and image make the same model, and the
#     null test leaves the random stream where it found it, so on one
#     machine its default .tif, .di.tif and .png come out byte for byte
#     R_main's (tested for Maxent, forests and boosted trees, tuned or not).
#     Across machines the last bits can differ: OpenBLAS picks its matrix
#     kernels by processor (Intel and AMD workers both fit the rebuild), and
#     the area-of-applicability index is a sum of squares through one of
#     them. So where the bytes differ the worker compares the values
#     (ATLAS_REFRESH_TOLERANCE), and anything beyond the tolerance, or any
#     model not refitted, and nothing is published, and the job says which.
#     The published default files are R_main's own in every case;
#   - publish a new release: R_main's files and model index, with each
#     refitted model's .full.tif, .full.di.tif and .full.png replaced, and its
#     metrics' description of the full view (full_map: bounds, size, cells)
#     replaced, since the web map places the picture by it. Nothing else in
#     its metrics changes: the grade stays R_main's. Promoted as any release
#     is, with its own promotion record;
#   - rebuild its collection cells (public/cells.tsv.gz) without the records
#     whose place their source hides or may hide (R/privacy.R), when the box
#     holds the release's own pull and a hidden-place list (pull-privacy):
#     the only published file built record by record. Otherwise the base's
#     stays, and the release says why;
#   - finish it as any release is finished (R/finish.R): counts, the
#     combined maps, the index and the prior come out as R_main's, from the
#     same default maps, and the continent export for Vision is built afresh
#     from the new full views and filed under the finished release.
#
# The new-find tracker scores a find on a model's default rasters, grade and
# combined map; a refresh changes none of them, so its tally carries on.
#
#   ./atlas plan-job --full-refresh --from-release=<R_main> [--dry-run]
#   ./atlas run-job-ec2 --job=<ID>      (fits the shards, publishes, finishes)
#   ./atlas finish-full-refresh --job=<ID>  (the publishing step on its own)

atlas_is_full_refresh <- function(job) identical(job$kind, "full-refresh")

# The default files a refit must reproduce, and the full-extent files it
# replaces.
ATLAS_REFRESH_SAME <- c(".tif", ".di.tif", ".png")

# How far a refit's default rasters may differ from the release's, where
# their bytes differ, and still be the same model. Floating point only:
# another model differs by far more (a regularisation step apart, Maxent's
# suitability moves in the third or fourth decimal).
#
# The rasters are stored as 32-bit floats (FLT4S), so a difference in the
# computation's last bits (about 1e-15 of a value) shows only where it tips a
# value across a float32 rounding boundary, and then by one step: 2^-24 to
# 2^-23 of the value, about 6e-8 to 1.2e-7. The tolerances allow four.
#   suitability (.tif): relative, 5e-7. Maxent's is exp() of a dot product;
#     forests' and boosted trees' involve no BLAS at all.
#   index (.di.tif): absolute 1e-6, or 5e-7 of the value where that is more,
#     on a scale whose threshold is about 0.3 to 1. The index is the square
#     root of a squared distance computed as |a|^2 + |b|^2 - 2a.b (R/aoa.R):
#     near a training site those cancel, and a 1e-15 relative difference in
#     the terms becomes up to about 1e-7 in the root.
# The .png is drawn from the .tif: it is compared only where the .tif's
# bytes match.
ATLAS_REFRESH_TOLERANCE <- list(suitability = 5e-7, dissimilarity = 1e-6)

# Minutes per model for a refit with tuning, no null tests and its full view,
# for the plan's estimate. One core, 2026-10-12/13, with the short-path pass
# budget (R/fit.R): Maxent tuned and fitted in 2-7 minutes (Trametes
# versicolor, among the richest, 6.5), the full view 1.5-4 more (Suillus
# caerulescens 1.6; a forest's, measured earlier, 4.1); forests and boosted
# trees fit in well under a minute before their maps.
ATLAS_REFRESH_MINUTES <- c(maxnet = 7, rf = 6, xgboost = 3, esm = 2)

#' The models a refresh would refit, and what it would cost, from a release
#' alone: strong ones, with their tasks and an estimate in CPU-hours.
atlas_refresh_tasks <- function(base, fingerprints = NULL) {
  strong <- Filter(function(e) !isTRUE(e$refused) && identical(e$grade, "strong"), base$index %||% list())
  areas <- vapply(base$index %||% list(), function(e) {
    if (is.numeric(e$area_km2) && length(e$area_km2) == 1L) e$area_km2 else NA_real_
  }, numeric(1))
  typical <- if (any(is.finite(areas))) stats::median(areas, na.rm = TRUE) else 5e6
  lapply(strong, function(e) list(
    taxon = e$taxon, algorithm = e$algorithm,
    fingerprint = if (is.null(fingerprints)) e$fingerprint else fingerprints[[e$taxon]],
    cost = atlas_task_cost(e$algorithm, e$area_km2, typical),
    inherited_grade = e$grade
  ))
}

#' What a refresh of these tasks costs, roughly: CPU-hours, and wall hours
#' on the EC2 setup (fits_at_once, as atlas_job_timing counts it).
atlas_refresh_estimate <- function(tasks, fits_at_once = 84) {
  algorithms <- vapply(tasks, function(t) t$algorithm, "")
  minutes <- vapply(algorithms, function(a) ATLAS_REFRESH_MINUTES[[a]] %||% 5, numeric(1))
  per <- table(factor(algorithms, levels = names(ATLAS_REFRESH_MINUTES)))
  cpu_hours <- sum(minutes) / 60
  list(
    models = length(tasks),
    taxa = length(unique(vapply(tasks, function(t) t$taxon, ""))),
    per_algorithm = as.list(per[per > 0]),
    cpu_hours = round(cpu_hours, 1),
    wall_hours = round(cpu_hours / fits_at_once, 1),
    basis = "minutes per model with tuning, no null tests and a full view (ATLAS_REFRESH_MINUTES); an estimate"
  )
}

#' Plan a full-view refresh of a release. dry_run = TRUE reads the store and
#' says what it would refit and cost, and writes nothing.
atlas_plan_full_refresh <- function(store = atlas_store(), from_release, grid = "draft", shards = 4L,
                                    tasks_per_shard = NULL, quiet = FALSE, dry_run = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  key <- paste0("releases/", grid, "/", from_release, ".json")
  if (!store$exists(key)) stop("no release ", from_release, " for the ", grid, " grid", call. = FALSE)
  base <- atlas_store_text(store, key)
  tasks <- atlas_refresh_tasks(base)
  if (!length(tasks)) stop("release ", from_release, " has no strong models to refresh", call. = FALSE)

  # The job that fitted each model, and so its pull, layers and FungalTraits
  # table. A model no job in the release's history planned on its record set
  # (carried over from a release with no job, or its job gone) cannot be
  # made again, so its full view could not be either.
  sources <- atlas_refresh_sources(store, base, tasks, grid)
  if (length(sources$unresolved)) {
    stop(length(sources$unresolved), " strong model", if (length(sources$unresolved) > 1L) "s" else "",
         " of ", from_release, " could not be traced to a job that fitted ",
         if (length(sources$unresolved) > 1L) "them" else "it", " on its record set, so ",
         if (length(sources$unresolved) > 1L) "they" else "it", " cannot be made again: ",
         paste(utils::head(sources$unresolved, 10), collapse = "; "),
         if (length(sources$unresolved) > 10L) "; ..." else "", call. = FALSE)
  }
  for (i in seq_along(tasks)) tasks[[i]]$source_job <- sources$source[[paste(tasks[[i]]$algorithm, tasks[[i]]$taxon)]]
  # Those jobs must have fitted alike: one set of settings for every refit.
  fits <- lapply(sources$jobs, function(j) {
    list(fit = j$fit[setdiff(names(j$fit), c("nulls", "full"))], layers_key = j$layers_key)
  })
  if (length(unique(fits)) > 1L) {
    stop("the jobs behind ", from_release, " (", paste(names(sources$jobs), collapse = ", "),
         ") fitted with different settings or layers; a refresh cannot make all of them again", call. = FALSE)
  }
  main_job <- sources$jobs[[1]]
  estimate <- atlas_refresh_estimate(tasks)
  per_job <- table(vapply(tasks, function(t) t$source_job, ""))
  if (isTRUE(dry_run)) {
    say("full-view refresh of ", from_release, " (dry run, nothing written): ", estimate$models,
        " strong models of ", estimate$taxa, " taxa (",
        paste(names(estimate$per_algorithm), unlist(estimate$per_algorithm), collapse = ", "),
        ") fitted by ", paste(names(per_job), per_job, sep = ": ", collapse = ", "),
        "; about ", estimate$cpu_hours, " CPU-h, ", estimate$wall_hours, " h on EC2")
    return(invisible(list(from_release = from_release, from_jobs = as.list(per_job), estimate = estimate,
                          tasks = tasks)))
  }

  # Shards by source job, so each fetches one job's inputs: every job gets at
  # least one, the rest go by cost.
  groups <- split(seq_along(tasks), vapply(tasks, function(t) t$source_job, ""))
  if (!is.null(tasks_per_shard)) shards <- atlas_shard_count(length(tasks), shards, tasks_per_shard)
  cost_of <- vapply(groups, function(g) sum(vapply(tasks[g], function(t) t$cost, numeric(1))), numeric(1))
  per_group <- pmin(lengths(groups), pmax(1L, floor(max(shards, length(groups)) * cost_of / sum(cost_of))))
  shard_inputs <- list()
  offset <- 0L
  for (k in seq_along(groups)) {
    g <- groups[[k]]
    assignment <- atlas_assign_shards(vapply(tasks[g], function(t) t$cost, numeric(1)), per_group[[k]])
    for (i in seq_along(g)) tasks[[g[[i]]]]$shard <- offset + assignment[[i]]
    for (s in unique(assignment)) shard_inputs[[as.character(offset + s)]] <- sources$jobs[[names(groups)[[k]]]]$inputs
    offset <- offset + max(assignment)
  }
  id <- paste0("full-", atlas_release_id(digest::digest(list(tasks, from_release, "full-refresh"),
                                                        algo = "sha256")))
  job <- list(
    id = id, grid = grid, kind = "full-refresh",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    from_release = from_release, from_jobs = as.list(per_job), base_release = from_release,
    algorithms = as.list(unique(vapply(tasks, function(t) t$algorithm, ""))),
    shards = offset,
    # R_main's settings, with no null tests and a full view for every model.
    fit = utils::modifyList(main_job$fit, list(nulls = 0, full = TRUE)),
    layers_key = main_job$layers_key,
    pull = base$pull,
    # Each shard's inputs: the very pull, layers and FungalTraits table of
    # the job that fitted its models (atlas_run_shard reads shard_inputs).
    inputs = main_job$inputs,
    shard_inputs = shard_inputs,
    tolerance = ATLAS_REFRESH_TOLERANCE,
    public = list(), tasks = tasks, retire = list(), deferred = 0L,
    estimate = estimate,
    declared = paste("Full views refreshed for", from_release, "'s strong models; their default maps,",
                     "grades and everything else are", from_release, "'s.")
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
  say("full-view refresh ", id, " of ", from_release, ": ", length(tasks), " strong models in ", job$shards,
      " shard", if (job$shards == 1L) "" else "s", "; about ", estimate$cpu_hours, " CPU-h")
  invisible(job)
}

#' The job that fitted each model of a release: walking back through the
#' releases before it (previous, previous, ...), the newest job whose plan
#' had that (taxon, algorithm) on the same record set (fingerprint). Returns
#' the job id per model, the jobs, and the models it could not trace.
atlas_refresh_sources <- function(store, base, tasks, grid = "draft") {
  want <- stats::setNames(vapply(tasks, function(t) as.character(t$fingerprint %||% ""), ""),
                          vapply(tasks, function(t) paste(t$algorithm, t$taxon), ""))
  source <- list()
  jobs <- list()
  seen <- character()
  visited <- character()
  release <- base
  # A release can name itself as its previous (two published the same second
  # with the same files share an id): each is read once.
  while (!is.null(release) && !(release$id %||% "") %in% visited &&
         length(setdiff(names(want), names(source)))) {
    visited <- c(visited, release$id %||% "")
    job_id <- atlas_json_string(release$job)
    if (!is.null(job_id) && !job_id %in% seen) {
      seen <- c(seen, job_id)
      job <- tryCatch(atlas_read_job(store, job_id, grid), error = function(e) NULL)
      if (!is.null(job) && is.null(job$kind) && !is.null(atlas_job_pull_entry(job))) {
        planned <- stats::setNames(vapply(job$tasks, function(t) as.character(t$fingerprint %||% ""), ""),
                                   vapply(job$tasks, function(t) paste(t$algorithm, t$taxon), ""))
        for (model in setdiff(names(want), names(source))) {
          if (nzchar(want[[model]]) && identical(unname(planned[model]), want[[model]])) {
            source[[model]] <- job_id
            jobs[[job_id]] <- job
          }
        }
      }
    }
    previous <- atlas_json_string(release$previous)
    key <- if (!is.null(previous)) paste0("releases/", grid, "/", previous, ".json")
    release <- if (!is.null(key) && store$exists(key)) atlas_store_text(store, key)
  }
  list(source = source, jobs = jobs, unresolved = setdiff(names(want), names(source)))
}

#' On the worker, as a refresh's model is fitted: is it the release's model?
#' For the default suitability and index, "identical" where the bytes match,
#' else "within" or "differs" by their values (ATLAS_REFRESH_TOLERANCE), with
#' the largest difference.
atlas_refresh_verdict <- function(store, published, name, grid, algorithm, tolerance = ATLAS_REFRESH_TOLERANCE) {
  out <- list()
  kinds <- c(".tif" = "suitability", ".di.tif" = "dissimilarity")
  for (ext in names(kinds)) {
    relative <- atlas_model_relpaths(name, grid, algorithm, ext)
    local <- file.path(atlas_data_dir(), relative)
    before <- unname(published[relative])
    if (is.na(before) || !file.exists(local)) {
      out[[ext]] <- list(status = if (is.na(before) && !file.exists(local)) "identical" else "differs",
                         why = "present on one side only")
      next
    }
    if (identical(atlas_sha256(local), before)) {
      out[[ext]] <- list(status = "identical")
      next
    }
    file <- tempfile(fileext = ".tif")
    # A raster that cannot be read is not the release's model: say so, and
    # let the box refuse it, rather than stop the shard.
    out[[ext]] <- tryCatch({
      store$get(atlas_object_key(before), file)
      atlas_refresh_compare(terra::rast(file), terra::rast(local), kinds[[ext]], tolerance[[kinds[[ext]]]])
    }, error = function(e) list(status = "differs", why = paste("unreadable:", conditionMessage(e))))
    unlink(file)
  }
  out
}

#' Compare two rasters' values: the same grid, the same cells with data, and
#' every value within the tolerance (relative for suitability, absolute for
#' the index).
atlas_refresh_compare <- function(before, after, kind, tolerance) {
  if (!terra::compareGeom(before, after, stopOnError = FALSE)) return(list(status = "differs", why = "grid"))
  a <- terra::values(before, mat = FALSE)
  b <- terra::values(after, mat = FALSE)
  if (!identical(is.na(a), is.na(b))) return(list(status = "differs", why = "cells with data"))
  ok <- !is.na(a)
  difference <- abs(a[ok] - b[ok])
  scale <- pmax(abs(a[ok]), abs(b[ok]))
  allowed <- if (identical(kind, "suitability")) {
    tolerance * scale
  } else {
    pmax(tolerance, ATLAS_REFRESH_TOLERANCE$suitability * scale)
  }
  largest <- if (length(difference)) max(difference) else 0
  list(status = if (all(difference <= allowed)) "within" else "differs", largest = largest)
}

#' Check a refresh's refits against its base release, from the shard
#' records alone: every planned model refitted, the same model as the
#' base's (its default files' bytes, or the worker's verdict on their
#' values), and a full view of its own. Returns the problems (empty when
#' there are none) and the refitted files by path.
atlas_refresh_check <- function(store, job, base, grid = "draft") {
  published <- stats::setNames(vapply(base$files, function(f) f$sha256, ""),
                               vapply(base$files, function(f) f$path, ""))
  records <- lapply(seq_len(job$shards), function(n) atlas_store_text(store, atlas_shard_key(job$id, n, grid)))
  results <- list()
  for (r in unlist(lapply(records, function(x) x$results), recursive = FALSE)) {
    results[[paste(r$algorithm, r$taxon)]] <- r
  }
  files <- list()
  for (f in unlist(lapply(records, function(x) x$files), recursive = FALSE)) files[[f$path]] <- f
  problems <- character()
  for (t in job$tasks) {
    label <- paste(t$algorithm, t$taxon)
    r <- results[[label]]
    if (is.null(r) || !identical(r$status, "fitted")) {
      problems <- c(problems, paste0(label, ": not refitted (", r$status %||% "no result",
                                     if (!is.null(r$error)) paste0(": ", r$error), ")"))
      next
    }
    same_bytes <- TRUE
    for (ext in ATLAS_REFRESH_SAME) {
      p <- atlas_model_relpaths(t$taxon, grid, t$algorithm, ext)
      before <- unname(published[p])
      after <- files[[p]]$sha256
      if (is.na(before) && is.null(after)) next
      if (identical(before, after)) next
      if (identical(ext, ".png")) {
        # Drawn from the .tif: only a .tif that matched byte for byte says
        # the picture should have too.
        if (same_bytes) problems <- c(problems, paste0(label, ": ", basename(p), " differs from the release's"))
        next
      }
      same_bytes <- FALSE
      verdict <- r$identity[[ext]]
      if (!identical(verdict$status, "within")) {
        problems <- c(problems, paste0(label, ": ", basename(p), " differs from the release's (",
                                       if (is.null(verdict)) "no verdict from its worker" else
                                         paste0(verdict$why %||% "values", ", largest difference ",
                                                signif(as.numeric(verdict$largest %||% NA), 3)), ")"))
      }
    }
    lacking <- atlas_model_relpaths(t$taxon, grid, t$algorithm, ATLAS_FULL_EXTS)
    lacking <- lacking[!lacking %in% names(files)]
    if (length(lacking)) problems <- c(problems, paste0(label, ": no ", paste(basename(lacking), collapse = ", ")))
  }
  list(problems = problems, files = files)
}

#' The base release's metrics for a model with only its full view's
#' description taken from the refit, as a file entry in the store.
atlas_refresh_metrics <- function(store, base_entry, refit_entry, path) {
  read <- function(entry) {
    file <- tempfile(fileext = ".json")
    on.exit(unlink(file), add = TRUE)
    store$get(atlas_object_key(entry$sha256), file)
    jsonlite::fromJSON(file, simplifyVector = FALSE)
  }
  metrics <- read(base_entry)
  metrics$full_map <- read(refit_entry)$full_map
  file <- tempfile(fileext = ".json")
  on.exit(unlink(file), add = TRUE)
  atlas_write_json(metrics, file)
  sha <- atlas_sha256(file)
  if (!store$exists(atlas_object_key(sha))) store$put(atlas_object_key(sha), file)
  list(path = path, sha256 = sha, bytes = file.info(file)$size)
}

#' On the box: the release's collection cells without the records whose
#' place their source hides (R/privacy.R), built from the release's own pull
#' when this machine holds it and a hidden-place list. Returns rebuilt (and
#' the file's entry, and how many records it leaves out), or the reason not.
atlas_refresh_public_cells <- function(store, base, grid = "draft") {
  hidden <- atlas_read_privacy()
  if (is.null(hidden)) return(list(rebuilt = FALSE, reason = "no hidden-place list on the box (pull-privacy)"))
  job <- tryCatch(atlas_read_job(store, atlas_json_string(base$job), grid), error = function(e) NULL)
  pull <- if (!is.null(job)) atlas_job_pull_entry(job)
  manifest <- tryCatch(atlas_read_manifest(), error = function(e) NULL)
  local <- if (!is.null(manifest$file)) file.path(atlas_data_dir(), "occurrences", manifest$file)
  if (is.null(pull) || is.null(local) || !file.exists(local) || !identical(atlas_sha256(local), pull$sha256)) {
    return(list(rebuilt = FALSE, reason = "the box's pull is not the one the release was fitted on"))
  }
  occurrences <- atlas_read_occurrences(local)
  atlas_write_tsv_gz(atlas_public_cells_table(occurrences, hidden = hidden), atlas_public_cells_path())
  entry <- atlas_file_entries("public/cells.tsv.gz")
  atlas_upload_objects(store, entry)
  list(rebuilt = TRUE, entry = entry[[1]],
       records_left_out = sum(paste(occurrences$source, occurrences$observation_id, sep = ":") %in% hidden))
}

#' On the box: publish a refresh's release from its shards, once every one
#' has reported and every refit checks out against the release it refreshes.
#' Refuses, publishing nothing, if any does not, or if another release became
#' current after the job was planned.
atlas_finish_full_refresh <- function(store = atlas_store(), id, grid = "draft", promote = TRUE, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  job <- atlas_read_job(store, id, grid)
  if (!atlas_is_full_refresh(job)) stop("job ", id, " is not a full-view refresh", call. = FALSE)
  status <- atlas_job_status(store, id, grid)
  if (length(status$missing)) {
    stop("job ", id, " is not finished: shard", if (length(status$missing) > 1L) "s " else " ",
         paste(status$missing, collapse = ", "), " not reported; a refresh is never published in part",
         call. = FALSE)
  }
  current <- atlas_current_release(store, grid)
  if (!identical(atlas_json_string(current$id), job$from_release)) {
    stop("release ", current$id %||% "(none)", " became current after job ", id, " was planned from ",
         job$from_release, "; plan again", call. = FALSE)
  }
  base <- current
  checked <- atlas_refresh_check(store, job, base, grid)
  if (length(checked$problems)) {
    atlas_store_json(store, paste0("jobs/", grid, "/", id, "/refused.json"),
                     list(job = id, from_release = job$from_release, problems = as.list(checked$problems),
                          at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
    stop("full-view refresh ", id, " is not published: ", length(checked$problems), " model",
         if (length(checked$problems) > 1L) "s do" else " does", " not match ", job$from_release, ": ",
         paste(utils::head(checked$problems, 10), collapse = "; "),
         if (length(checked$problems) > 10L) "; ..." else "",
         " (all of them in jobs/", grid, "/", id, "/refused.json)", call. = FALSE)
  }

  files <- list()
  for (f in base$files) files[[f$path]] <- f
  for (t in job$tasks) {
    for (p in atlas_model_relpaths(t$taxon, grid, t$algorithm, ATLAS_FULL_EXTS)) files[[p]] <- checked$files[[p]]
    json <- atlas_model_relpaths(t$taxon, grid, t$algorithm, ".json")
    if (!is.null(files[[json]]) && !is.null(checked$files[[json]])) {
      files[[json]] <- atlas_refresh_metrics(store, files[[json]], checked$files[[json]], json)
    }
  }
  public <- atlas_refresh_public_cells(store, base, grid)
  if (!is.null(public$entry)) files[[public$entry$path]] <- public$entry
  kept <- base[intersect(names(base), c("job", "job_results", "retired", "partial", "unreported_shards"))]
  release <- atlas_write_release(
    store, grid, unname(files), base$index,
    previous = base$id, note = paste("full views refreshed for", base$id, "by job", id),
    pull = base$pull, layers_key = base$layers_key, promote = promote, quiet = quiet,
    extra = c(kept, list(full_refresh = list(job = id, from = base$id, models = length(job$tasks),
                                             public_cells = public[setdiff(names(public), "entry")])))
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/finished.json"),
                   list(release = release$id, finished_at = release$created_at))
  # A refresh trains nothing new: its release was trained on what its base was.
  atlas_trained_ids_quietly(atlas_copy_trained_ids(store, grid, base$id, release$id), release$id)
  say("full-view refresh ", id, ": ", length(job$tasks), " models' full views replaced in release ",
      release$id, " (from ", base$id, ")")
  invisible(release)
}
