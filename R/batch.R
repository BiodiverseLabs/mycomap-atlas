# Fitting every eligible taxon in one run.
#
# The expensive shared work is done once: the pull is read and projected onto
# the grid once, and the predictor stack is opened once. Each taxon then costs
# only its own fits.
#
# A run refits only what changed. A stored model is skipped when its record-set
# fingerprint and its settings (layers included) both match, so a nightly run
# after a quiet day fits almost nothing, and a run after a layer rebuild fits
# everything.
#
# Measured on the draft grid (2026-09-28), a fit is dominated by maxnet itself,
# not by the map: Armillaria nabsnona spent 37 s fitting (five blocked folds
# and the final model) against 5 s predicting and drawing. A full run over
# ~800 taxa is therefore hours in series, which is why it can use workers.
#
# One taxon failing never stops the run. Refusals (too few presence cells) and
# failures (anything else) are counted separately in the batch summary.

#' Presence cells per taxon on the grid, most first.
atlas_presence_cell_counts <- function(points) {
  if (is.null(points) || !nrow(points)) {
    return(data.frame(scientific_name = character(), cells = integer(),
                      stringsAsFactors = FALSE))
  }
  distinct <- points[!duplicated(points[, c("scientific_name", "cell")]), , drop = FALSE]
  counts <- table(distinct$scientific_name)
  out <- data.frame(
    scientific_name = names(counts),
    cells = as.integer(counts),
    stringsAsFactors = FALSE
  )
  out <- out[order(-out$cells, out$scientific_name), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The taxa a batch will consider: enough presence cells, richest first.
#'
#' The cell count here is before cells without predictor data are dropped, so
#' a taxon just over the line can still be refused by the fit itself.
atlas_batch_candidates <- function(points, min_presences = 20, limit = Inf,
                                   taxa = NULL) {
  counts <- atlas_presence_cell_counts(points)
  counts <- counts[counts$cells >= min_presences, , drop = FALSE]
  if (!is.null(taxa)) {
    counts <- counts[counts$scientific_name %in% taxa, , drop = FALSE]
  }
  if (is.finite(limit)) {
    counts <- utils::head(counts, max(0L, as.integer(limit)))
  }
  rownames(counts) <- NULL
  counts
}

#' Record-set fingerprints for just the named taxa.
atlas_fingerprints_for <- function(occurrences, names) {
  rows <- split(seq_len(nrow(occurrences)), occurrences$scientific_name)
  vapply(names, function(name) {
    atlas_fingerprint(occurrences[rows[[name]] %||% integer(), , drop = FALSE])
  }, character(1), USE.NAMES = TRUE)
}

#' Fit one taxon inside a batch, turning every outcome into a row.
#'
#' A refusal and a failure are both caught, so one bad taxon cannot halt a run
#' of eight hundred.
atlas_batch_fit_one <- function(name, fingerprint, fit, args) {
  started <- Sys.time()
  row <- tryCatch(
    {
      result <- do.call(fit, c(list(name = name, fingerprint = fingerprint), args))
      m <- result$metrics
      list(
        status = "fitted",
        presences = m$presences,
        predictors = length(m$predictors),
        auc_mean = m$auc_mean,
        boyce_mean = m$boyce_mean,
        map = !is.null(m$raster)
      )
    },
    atlas_insufficient_evidence = function(e) {
      list(status = "refused", presences = e$presences, error = conditionMessage(e))
    },
    error = function(e) {
      list(status = "failed", error = conditionMessage(e))
    }
  )
  c(
    list(taxon = name, fingerprint = fingerprint),
    row,
    list(seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1))
  )
}

#' Counts by outcome, for the summary and the closing message.
atlas_batch_counts <- function(rows) {
  statuses <- vapply(rows, function(r) as.character(r$status), character(1))
  list(
    considered = length(rows),
    fitted = sum(statuses == "fitted"),
    skipped = sum(statuses == "skipped"),
    refused = sum(statuses == "refused"),
    failed = sum(statuses == "failed")
  )
}

#' Where a batch writes its summary and its progress log.
atlas_batch_path <- function(grid, stamp, extension = ".json") {
  atlas_path("batches", grid, paste0("batch-", stamp, extension))
}

#' Write the summary so far. Called after every taxon, so a run that is
#' stopped halfway still says what it finished.
atlas_write_batch_summary <- function(summary, rows, grid, stamp) {
  summary$counts <- atlas_batch_counts(rows)
  summary$taxa <- rows
  path <- atlas_batch_path(grid, stamp)
  atlas_write_json(summary, path)
  atlas_write_json(summary, atlas_path("batches", grid, "latest.json"))
  invisible(path)
}

#' What a worker runs for one taxon, using the points and stack it holds.
#'
#' fit is NULL for the usual fit, which the worker already has: a function
#' shipped from here would drag its namespace along with it.
atlas_batch_worker_task <- function(name, fingerprints, fit, args) {
  args$points <- get(".atlas_points", envir = globalenv())
  args$stack <- get0(".atlas_stack", envir = globalenv())
  atlas_batch_fit_one(name, fingerprints[[name]], fit %||% atlas_fit_taxon, args)
}

#' Start a pool of R processes, each with Atlas loaded and its own stack.
#'
#' A terra raster cannot be sent between processes, so every worker opens the
#' stack itself; the projected points are small enough to copy.
atlas_start_workers <- function(workers, grid, points) {
  cluster <- parallel::makePSOCKcluster(workers)
  root <- normalizePath(Sys.getenv("ATLAS_ROOT", unset = "."), winslash = "/")
  data_dir <- normalizePath(atlas_data_dir(), winslash = "/", mustWork = FALSE)
  setup <- function(root, data_dir, grid, points) {
    Sys.setenv(ATLAS_ROOT = root, ATLAS_DATA_DIR = data_dir)
    if (requireNamespace("mycomapatlas", quietly = TRUE)) {
      attach(asNamespace("mycomapatlas"), name = "atlas", warn.conflicts = FALSE)
    } else {
      for (file in list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) {
        sys.source(file, envir = globalenv())
      }
    }
    assign(".atlas_points", points, envir = globalenv())
    # Without layers the stack cannot open; each fit then says so itself,
    # rather than the whole pool failing to start.
    stack <- tryCatch(atlas_predictor_stack(grid), error = function(e) NULL)
    assign(".atlas_stack", stack, envir = globalenv())
    TRUE
  }
  # A function sent to a worker takes its enclosing frame with it; cut that
  # loose, or every worker is sent a copy of the whole pull.
  environment(setup) <- globalenv()
  parallel::clusterCall(cluster, setup, root, data_dir, grid, points)
  cluster
}

#' Run task(name, ...) for every name across a pool, handing a worker its next
#' name the moment it finishes, and passing each result to on_result as it
#' arrives.
#'
#' This is how parallel::clusterApplyLB schedules too, but that returns
#' nothing until every call is done, so a run of hundreds would log nothing
#' and save nothing for hours. sendCall and recvOneResult are the functions it
#' is built on; parallel does not export them.
atlas_run_on_workers <- function(cluster, names, task, on_result, ...) {
  send_call <- utils::getFromNamespace("sendCall", "parallel")
  receive <- utils::getFromNamespace("recvOneResult", "parallel")
  extra <- list(...)
  following <- 1L
  send <- function(node) {
    send_call(cluster[[node]], task, c(list(names[[following]]), extra),
              tag = names[[following]])
    following <<- following + 1L
  }
  for (node in seq_len(min(length(cluster), length(names)))) {
    send(node)
  }
  for (i in seq_along(names)) {
    result <- receive(cluster)
    if (following <= length(names)) {
      send(result$node)
    }
    value <- result$value
    if (inherits(value, "try-error")) {
      value <- list(taxon = result$tag, status = "failed",
                    error = as.character(value))
    }
    on_result(value)
  }
  invisible(NULL)
}

#' Fit every eligible taxon.
#'
#' limit      fit at most this many candidates (richest first): for trial runs
#' predict    draw maps; FALSE writes scores only
#' force      refit even when the stored model is current
#' workers    R processes to fit in parallel; 1 fits in this process
#' fit        the per-taxon fitting function, replaceable in tests
atlas_fit_batch <- function(grid = "draft", limit = Inf, predict = TRUE,
                            force = FALSE, workers = 1L, min_presences = 20,
                            n_background = 10000, buffer_km = 500, folds = 5,
                            block_km = 200, regmult = 1, correlation = 0.7,
                            prune = TRUE, taxa = NULL, quiet = FALSE,
                            occurrences = NULL, points = NULL, stack = NULL,
                            layers = NULL, fit = atlas_fit_taxon) {
  started <- Sys.time()
  stamp <- format(started, "%Y%m%dT%H%M%SZ", tz = "UTC")
  log_path <- atlas_batch_path(grid, stamp, ".log")
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)
  log <- file(log_path, open = "wt")
  on.exit(close(log), add = TRUE)
  # R holds back console output when it is piped, so a long run also writes
  # its progress to a file, flushed line by line, that can be watched.
  say <- function(...) {
    line <- paste0(format(Sys.time(), "%H:%M:%S"), "  ", ...)
    writeLines(line, log)
    flush(log)
    if (!isTRUE(quiet)) message(line)
  }

  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  layers <- layers %||% atlas_layers_key(grid)
  settings <- atlas_fit_settings(
    grid = grid, n_background = n_background, buffer_km = buffer_km,
    folds = folds, block_km = block_km, regmult = regmult,
    correlation = correlation, prune = prune, layers = layers
  )

  candidates <- atlas_batch_candidates(points, min_presences, limit, taxa)
  fingerprints <- atlas_fingerprints_for(occurrences, candidates$scientific_name)
  current <- vapply(candidates$scientific_name, function(name) {
    !isTRUE(force) && atlas_fit_is_current(
      atlas_read_metrics(name, grid), fingerprints[[name]], settings, predict
    )
  }, logical(1))
  to_fit <- candidates$scientific_name[!current]

  say(nrow(candidates), " candidates with ", min_presences, "+ presence cells; ",
      sum(current), " current, ", length(to_fit), " to fit",
      if (workers > 1L) paste0(" on ", workers, " workers") else "")

  rows <- lapply(candidates$scientific_name[current], function(name) {
    list(taxon = name, fingerprint = fingerprints[[name]], status = "skipped")
  })
  summary <- list(
    grid = grid,
    started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    finished_at = NULL,
    settings = settings,
    settings_key = atlas_settings_key(settings),
    predict = isTRUE(predict),
    force = isTRUE(force),
    workers = as.integer(workers),
    limit = if (is.finite(limit)) limit else NULL,
    min_presences = min_presences
  )
  atlas_write_batch_summary(summary, rows, grid, stamp)

  args <- list(
    grid = grid, n_background = n_background, buffer_km = buffer_km,
    folds = folds, block_km = block_km, regmult = regmult,
    min_presences = min_presences, correlation = correlation, prune = prune,
    predict = predict, quiet = TRUE, layers = layers
  )
  record <- function(row) {
    rows[[length(rows) + 1L]] <<- row
    atlas_write_batch_summary(summary, rows, grid, stamp)
    done <- sum(vapply(rows, function(r) r$status != "skipped", logical(1)))
    detail <- switch(
      row$status,
      fitted = sprintf("AUC %s, Boyce %s, %s cells", row$auc_mean, row$boyce_mean, row$presences),
      refused = sprintf("%s cells", row$presences),
      row$error %||% ""
    )
    say(sprintf("[%d/%d] %s %s (%ss) %s", done, length(to_fit), row$status,
                row$taxon, row$seconds %||% NA, detail))
  }

  if (length(to_fit) && workers > 1L) {
    cluster <- atlas_start_workers(min(workers, length(to_fit)), grid, points)
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    task <- atlas_batch_worker_task
    environment(task) <- globalenv()
    shipped_fit <- if (identical(fit, atlas_fit_taxon)) NULL else fit
    atlas_run_on_workers(
      cluster, to_fit, task, record,
      fingerprints = fingerprints, fit = shipped_fit, args = args
    )
  } else {
    if (length(to_fit)) {
      # As on a worker: if the stack cannot open, each fit reports it.
      stack <- stack %||% tryCatch(atlas_predictor_stack(grid), error = function(e) NULL)
    }
    local_args <- c(args, list(points = points, stack = stack))
    for (name in to_fit) {
      record(atlas_batch_fit_one(name, fingerprints[[name]], fit, local_args))
    }
  }

  summary$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  summary$seconds <- round(as.numeric(difftime(Sys.time(), started, units = "secs")))
  path <- atlas_write_batch_summary(summary, rows, grid, stamp)
  counts <- atlas_batch_counts(rows)
  say(sprintf("done in %ss: %d fitted, %d skipped, %d refused, %d failed -> %s",
              summary$seconds, counts$fitted, counts$skipped, counts$refused,
              counts$failed, path))
  invisible(c(summary, list(counts = counts, taxa = rows, path = path)))
}
