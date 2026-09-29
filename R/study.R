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
atlas_run_study <- function(kind, file_prefix, taxon_fn, sample, fingerprints,
                            args, settings, baseline, grid = "draft",
                            workers = 1L, points, stack = NULL, quiet = FALSE,
                            opening = NULL) {
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
      list(started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
           settings = settings, layers = atlas_layers_key(grid),
           baseline = baseline,
           summary = atlas_sweep_summary(rows, baseline = baseline), taxa = rows),
      path
    )
  }
  record <- function(row) {
    rows[[length(rows) + 1L]] <<- row
    save()
    detail <- if (identical(row$status, "scored")) {
      paste(vapply(row$arms, function(a) sprintf("%s:%s", atlas_arm_name(a), a$auc),
                   character(1)), collapse = " ")
    } else {
      row$error %||% paste(row$presences, "cells")
    }
    say(sprintf("[%d/%d] %s %s (%s cells, %ss) %s", length(rows), nrow(sample),
                row$status, row$taxon, row$presences %||% "?", row$seconds %||% NA, detail))
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
  summary <- atlas_sweep_summary(rows, baseline = baseline)
  if (!isTRUE(quiet) && nrow(summary)) {
    print(summary, row.names = FALSE)
  }
  say("done in ", round(as.numeric(difftime(Sys.time(), started, units = "secs"))),
      "s -> ", path)
  invisible(list(summary = summary, taxa = rows, path = path))
}

#' An arm's name: arm for a benchmark, per_presence for the predictor sweep.
atlas_arm_name <- function(arm) {
  as.character(arm$arm %||% arm$per_presence)
}
