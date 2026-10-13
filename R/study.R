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
  args$stack <- get0(".atlas_stack", envir = globalenv())
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
atlas_run_study <- function(kind, file_prefix, taxon_fn, sample, fingerprints,
                            args, settings, baseline, grid = "draft",
                            workers = 1L, points, stack = NULL, quiet = FALSE,
                            opening = NULL, summarise = atlas_sweep_summary,
                            extra = NULL,
                            detail = function(arm) sprintf("%s:%s", atlas_arm_name(arm), arm$auc)) {
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
    described <- if (identical(row$status, "scored")) {
      paste(vapply(row$arms, function(a) paste(detail(a), collapse = ""), character(1)),
            collapse = " ")
    } else {
      row$error %||% paste(row$presences, "cells")
    }
    say(sprintf("[%d/%d] %s %s (%s cells, %ss) %s", length(rows), nrow(sample),
                row$status, row$taxon, row$presences %||% "?", row$seconds %||% NA, described))
  }

  names <- sample$scientific_name
  if (length(names) && workers > 1L) {
    cluster <- atlas_start_workers(min(workers, length(names)), grid, points)
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    task <- atlas_study_worker_task
    environment(task) <- globalenv()
    atlas_run_on_workers(cluster, names, task, record,
                         fingerprints = fingerprints, taxon_fn = taxon_fn, args = args)
  } else if (length(names)) {
    stack <- stack %||% atlas_predictor_stack(grid)
    for (name in names) {
      record(tryCatch(
        do.call(taxon_fn, c(list(name = name, fingerprint = fingerprints[[name]],
                                 points = points, stack = stack), args)),
        error = function(e) list(taxon = name, status = "failed", error = conditionMessage(e))
      ))
    }
  }

  save()
  summary <- summarise(rows, baseline = baseline)
  if (!isTRUE(quiet) && nrow(summary)) {
    print(summary, row.names = FALSE)
  }
  say("done in ", round(as.numeric(difftime(Sys.time(), started, units = "secs"))),
      "s -> ", path)
  invisible(list(summary = summary, taxa = rows, path = path))
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
ATLAS_STUDY_PREFIXES <- c("study/", "private/")

#' Refuse a store key outside the study prefixes, or one that climbs out of
#' them.
atlas_study_check_key <- function(key) {
  key <- as.character(key)
  if (length(key) != 1L || !nzchar(key) || grepl("(^|/)[.][.](/|$)", key) ||
      !any(startsWith(key, ATLAS_STUDY_PREFIXES))) {
    stop("a study writes only under ", paste(ATLAS_STUDY_PREFIXES, collapse = " or "),
         ", not '", key, "'", call. = FALSE)
  }
  key
}

#' Where a study run writes: a local directory, and the store prefix it is
#' copied to afterwards (atlas_study_publish). out is a store prefix under
#' study/ or private/, or NULL for data/<kind>/<grid>/ on this machine only.
atlas_study_out <- function(out, kind, grid, label) {
  stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")
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
