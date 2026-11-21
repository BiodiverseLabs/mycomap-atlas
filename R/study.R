# Running a study: the same question asked of many taxa, on many workers.
#
# The predictor sweep and the model benchmark share everything but the
# question — sample the candidates, fan the taxa out to workers, save the
# results after every taxon, log each one as it lands, summarise at the end —
# so that part lives here once.

#' What a worker runs for one taxon in a study. The per-taxon function is
#' named rather than shipped, so the worker uses its own copy.
atlas_study_worker_task <- function(name, fingerprints, taxon_fn, args) {
  args$points <- get(".atlas_points", envir = globalenv())
  stack <- get0(".atlas_stack", envir = globalenv())
  # A worker whose layers did not open says so. (Assigning NULL to a list
  # element drops it, and every taxon then failed on a missing argument,
  # E6b's first run, 2026-10-19.)
  if (is.null(stack)) {
    return(list(taxon = name, status = "failed",
                error = "the predictor layers did not open on this worker"))
  }
  args$stack <- stack
  tryCatch(
    do.call(taxon_fn, c(list(name = name, fingerprint = fingerprints[[name]]), args)),
    error = function(e) list(taxon = name, status = "failed", error = conditionMessage(e))
  )
}

#' Ask one question of every taxon in a sample.
#'
#' kind      names the output: data/<kind>/<grid>/<file_prefix>-<stamp>.json
#' taxon_fn  name of a function(name, fingerprint, points, stack, ...) that
#'           returns a row with status "scored" and a list of arms, each with
#'           arm, auc and boyce
#' baseline  the arm every other arm is compared with, taxon by taxon
#' summarise function(rows, baseline) giving the results file's summary
#' extra     function(rows) giving more named entries for the results file
#' detail    function(arm) giving the short text an arm is logged as
#' progress  on a study job's worker (atlas_run_study_shard sets it): where
#'           the rows scored so far are uploaded, at most every
#'           upload_seconds, and where a later attempt at the same shard
#'           resumes from, scoring only the taxa they do not hold
atlas_run_study <- function(kind, file_prefix, taxon_fn, sample, fingerprints,
                            args, settings, baseline, grid = "draft",
                            workers = 1L, points, stack = NULL, quiet = FALSE,
                            opening = NULL, summarise = atlas_sweep_summary,
                            extra = NULL,
                            detail = function(arm) sprintf("%s:%s", atlas_arm_name(arm), arm$auc),
                            progress = getOption("atlas.study_progress"),
                            upload_seconds = ATLAS_WORKER_LOG_SECONDS) {
  started <- Sys.time()
  stamp <- format(started, "%Y%m%dT%H%M%SZ", tz = "UTC")
  path <- atlas_path(kind, grid, paste0(file_prefix, "-", stamp, ".json"))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  log <- file(sub("[.]json$", ".log", path), open = "wt")
  on.exit(close(log), add = TRUE)
  say <- function(...) {
    line <- paste0(format(Sys.time(), "%H:%M:%S"), "  ", ...)
    writeLines(line, log)
    flush(log)
    if (!isTRUE(quiet)) message(line)
  }
  if (!is.null(opening)) say(opening)

  rows <- list()
  names <- sample$scientific_name
  # A study job's worker resumes what an earlier attempt at its shard saved
  # (a worker taken back or stopped mid-shard): those taxa are not scored
  # again, so a shard whose taxa take hours still gets through. Each taxon's
  # draws are seeded from its own fingerprint, so a resumed row is the row an
  # unbroken run would have scored.
  if (!is.null(progress)) {
    progress$kind <- kind
    progress$file_prefix <- file_prefix
    progress$settings <- settings
    resumed <- atlas_study_progress_rows(progress, names)
    if (length(resumed)) {
      rows <- resumed
      names <- setdiff(names, vapply(resumed, function(r) as.character(r$taxon), ""))
      say(length(resumed), " of ", nrow(sample), " taxa already scored by an earlier attempt at this shard; ",
          "resuming with the other ", length(names))
    }
  }
  uploaded_at <- NULL
  upload <- function() {
    if (is.null(progress)) return(invisible(NULL))
    # A failed upload costs the next attempt some taxa, never this run.
    tryCatch({
      atlas_study_progress_put(progress, rows, path)
      uploaded_at <<- Sys.time()
    }, error = function(e) say("could not upload this shard's progress: ", conditionMessage(e)))
  }
  save <- function() {
    atlas_write_json(
      c(list(started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
             settings = settings, layers = atlas_layers_key(grid),
             baseline = baseline,
             summary = summarise(rows, baseline = baseline)),
        if (is.function(extra)) extra(rows),
        list(taxa = rows)),
      path
    )
  }
  record <- function(row) {
    rows[[length(rows) + 1L]] <<- row
    save()
    if (is.null(uploaded_at) ||
        as.numeric(difftime(Sys.time(), uploaded_at, units = "secs")) >= upload_seconds) upload()
    described <- if (identical(row$status, "scored")) {
      paste(vapply(row$arms, function(a) paste(detail(a), collapse = ""), character(1)),
            collapse = " ")
    } else {
      row$error %||% paste(row$presences, "cells")
    }
    say(sprintf("[%d/%d] %s %s (%s cells, %ss) %s", length(rows), nrow(sample),
                row$status, row$taxon, row$presences %||% "?", row$seconds %||% NA, described))
  }

  # The layers must open here before any taxon is tried, with one worker or
  # many: a run without them stops at once rather than failing every taxon.
  if (length(names)) stack <- stack %||% atlas_predictor_stack(grid)
  if (length(names) && workers > 1L) {
    cluster <- atlas_start_workers(min(workers, length(names)), grid, points)
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    task <- atlas_study_worker_task
    environment(task) <- globalenv()
    atlas_run_on_workers(cluster, names, task, record,
                         fingerprints = fingerprints, taxon_fn = taxon_fn, args = args)
  } else if (length(names)) {
    for (name in names) {
      record(tryCatch(
        do.call(taxon_fn, c(list(name = name, fingerprint = fingerprints[[name]],
                                 points = points, stack = stack), args)),
        error = function(e) list(taxon = name, status = "failed", error = conditionMessage(e))
      ))
    }
  }

  save()
  upload()
  summary <- summarise(rows, baseline = baseline)
  if (!isTRUE(quiet) && nrow(summary)) {
    print(summary, row.names = FALSE)
  }
  say("done in ", round(as.numeric(difftime(Sys.time(), started, units = "secs"))),
      "s -> ", path)
  invisible(list(summary = summary, taxa = rows, path = path))
}

# ---- resuming a study job's shard ------------------------------------------

#' Where one study run of a study job's shard keeps its progress: beside the
#' shard's record (a worker may write there), one pair of files per study
#' run, as a shard's command may run more than one.
atlas_study_progress_key <- function(progress, ext = "rds") {
  slug <- gsub("(^-|-$)", "", gsub("[^A-Za-z0-9]+", "-", paste(progress$kind, progress$file_prefix)))
  paste0("jobs/", progress$grid %||% "draft", "/", progress$job, "/shards/", as.integer(progress$shard),
         ".study-", slug, ".progress.", ext)
}

#' Upload a study run's rows so far: an .rds a later attempt resumes from,
#' exactly as scored, and the run's results file as it stands, to read.
atlas_study_progress_put <- function(progress, rows, results_path = NULL) {
  file <- tempfile(fileext = ".rds")
  on.exit(unlink(file), add = TRUE)
  saveRDS(list(job = progress$job, shard = as.integer(progress$shard), kind = progress$kind,
               file_prefix = progress$file_prefix, settings = progress$settings,
               saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), rows = rows), file)
  progress$store$put(atlas_study_progress_key(progress, "rds"), file)
  if (!is.null(results_path) && file.exists(results_path)) {
    progress$store$put(atlas_study_progress_key(progress, "json"), results_path)
  }
  invisible(length(rows))
}

#' The rows an earlier attempt at this shard saved that this run may keep:
#' the same job, shard, study and settings, taxa of this sample, and not
#' failed (a failed taxon is tried again). Empty when there are none, or
#' when what was saved belongs to another run.
atlas_study_progress_rows <- function(progress, names = NULL) {
  saved <- atlas_study_progress_read(progress$store, atlas_study_progress_key(progress, "rds"))
  if (is.null(saved) || !identical(saved$job, progress$job) ||
      !identical(saved$shard, as.integer(progress$shard)) || !identical(saved$kind, progress$kind) ||
      !identical(saved$file_prefix, progress$file_prefix) || !identical(saved$settings, progress$settings)) {
    return(list())
  }
  keep <- Filter(function(r) !identical(as.character(r$status %||% "unknown"), "failed") &&
                   (is.null(names) || as.character(r$taxon %||% "") %in% names), saved$rows %||% list())
  # One row per taxon.
  taxa <- vapply(keep, function(r) as.character(r$taxon), "")
  keep[!duplicated(taxa)]
}

atlas_study_progress_read <- function(store, key) {
  if (!store$exists(key)) return(NULL)
  file <- tempfile(fileext = ".rds")
  on.exit(unlink(file), add = TRUE)
  store$get(key, file)
  tryCatch(readRDS(file), error = function(e) NULL)
}

#' How many taxa a study job's shard has saved across its study runs, not
#' counting failed ones: the orchestrator tells a worker that was lost after
#' saving from one that never got going.
atlas_study_saved_count <- function(store, id, shard, grid = "draft") {
  keys <- store$list(paste0("jobs/", grid, "/", id, "/shards/"))
  mine <- keys[grepl(paste0("^", as.integer(shard), "[.]study-.*[.]progress[.]rds$"), basename(keys))]
  sum(vapply(mine, function(key) {
    saved <- atlas_study_progress_read(store, key)
    if (is.null(saved)) return(0L)
    sum(vapply(saved$rows %||% list(), function(r) !identical(as.character(r$status %||% "unknown"), "failed"), FALSE))
  }, 0L))
}

# The share of a shard's taxa that may fail (an error, not a refusal) before
# the shard itself is marked failed.
ATLAS_STUDY_MAX_FAILED_SHARE <- 0.05

#' Stop, after a study has written and published its results, when more of
#' its taxa failed than ATLAS_STUDY_MAX_FAILED_SHARE: a study job's shard
#' then records "failed" instead of succeeding with nothing scored. The
#' error names how many failed and the commonest error.
atlas_study_guard <- function(rows, what = "study", max_share = ATLAS_STUDY_MAX_FAILED_SHARE) {
  status <- vapply(rows, function(r) as.character(r$status %||% "unknown"), "")
  failed <- status == "failed"
  if (length(rows) && mean(failed) > max_share) {
    errors <- vapply(rows[failed], function(r) as.character(r$error %||% "no message"), "")
    commonest <- names(sort(table(errors), decreasing = TRUE))[[1]]
    stop(sprintf("%s: %d of %d taxa failed, more than %g of them; commonest error: %s",
                 what, sum(failed), length(rows), max_share, commonest), call. = FALSE)
  }
  invisible(rows)
}

#' One shard of a study's names: "i/n" takes every n-th name from the i-th,
#' so n machines given 1/n .. n/n split the names without overlap or gap.
atlas_study_shard <- function(names, shard = "1/1") {
  parts <- suppressWarnings(as.integer(strsplit(as.character(shard %||% "1/1"), "/", fixed = TRUE)[[1]]))
  if (length(parts) != 2L || anyNA(parts) || parts[[2]] < 1L || parts[[1]] < 1L ||
      parts[[1]] > parts[[2]]) {
    stop("a shard is i/n with 1 <= i <= n, not '", shard, "'", call. = FALSE)
  }
  names[(seq_along(names) - 1L) %% parts[[2]] == parts[[1]] - 1L]
}

# Store prefixes a study may write under. A study never writes a release,
# the current pointer or anything public.
# private/study/ only: production reads other private/ prefixes (the
# tracker's ledger, trained ids, private releases), and a study must never
# overwrite them.
ATLAS_STUDY_PREFIXES <- c("study/", "private/study/")

#' Refuse a store key outside the study prefixes, or one that could climb out
#' of them: any "..", and any backslash (a local store on Windows would read
#' study/..\releases as a way out).
atlas_study_check_key <- function(key) {
  key <- as.character(key)
  if (length(key) != 1L || is.na(key) || !nzchar(key) || grepl("..", key, fixed = TRUE) ||
      grepl("\\", key, fixed = TRUE) || !any(startsWith(key, ATLAS_STUDY_PREFIXES))) {
    stop("a study writes only under ", paste(ATLAS_STUDY_PREFIXES, collapse = " or "),
         ", not '", key, "'", call. = FALSE)
  }
  key
}

#' Where a study run writes: a local directory, and the store prefix it is
#' copied to afterwards (atlas_study_publish). out is a store prefix under
#' study/ or private/study/, or NULL for data/<kind>/<grid>/ on this machine
#' only. shard ("i/n") goes into the name as shard-<i>of<n>: a study job's
#' shards publish to one prefix, and names that differ only by their start
#' second overwrite each other when two shards start in the same second.
atlas_study_out <- function(out, kind, grid, label, shard = NULL,
                            stamp = format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")) {
  if (!is.null(shard)) label <- paste(label, "shard", sub("/", "of", as.character(shard)))
  slug <- gsub("(^-|-$)", "", gsub("[^A-Za-z0-9]+", "-", as.character(label)))
  # The results file is <prefix>-<stamp>.json (atlas_run_study adds the
  # stamp); the run's other files go in the directory beside it.
  prefix <- paste0(sub("-studies$", "", kind), "-", slug)
  key <- if (!is.null(out)) {
    atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
  }
  dir <- atlas_path(kind, grid, paste0(prefix, "-", stamp))
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  list(dir = dir, prefix = prefix, key = key)
}

#' Copy a study's local files to its store prefix, every key checked first,
#' so a bad prefix writes nothing at all.
atlas_study_publish <- function(store, files, prefix, root) {
  keys <- vapply(files, function(f) {
    rel <- substring(normalizePath(f, winslash = "/"), nchar(normalizePath(root, winslash = "/")) + 2L)
    atlas_study_check_key(paste0(sub("/*$", "/", prefix), rel))
  }, character(1))
  for (i in seq_along(files)) store$put(keys[[i]], files[[i]])
  invisible(unname(keys))
}

#' How many rows of a study ended each way.
atlas_study_counts <- function(rows) {
  status <- vapply(rows, function(r) as.character(r$status %||% "unknown"), "")
  as.list(table(factor(status, levels = unique(c("scored", "refused", "mismatch", "failed", status)))))
}

#' An arm's name: arm for a benchmark, per_presence for the predictor sweep.
atlas_arm_name <- function(arm) {
  as.character(arm$arm %||% arm$per_presence)
}
