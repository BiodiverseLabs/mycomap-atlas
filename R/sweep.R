# Measuring how many predictors a taxon should be given.
#
# The cap in atlas_choose_predictors — roughly one predictor per four presence
# cells — was set from three taxa. This refits a sample of taxa several ways,
# changing only that ratio, and scores each way on the same spatial folds.
#
# Everything else is held fixed on purpose: the same training table, the same
# background, the same folds, the same correlation pruning. A difference
# between two arms for one taxon can then only come from the cap, and the
# comparison is paired — each taxon is compared with itself, so a hard taxon
# and an easy one do not wash each other out.
#
# Nothing here writes a model. It writes one results file under data/sweeps/.

# Presence-cell bands the sample is stratified by. The cap only matters where
# records are few, so the small bands are where the answer is decided.
ATLAS_SWEEP_BANDS <- c(20, 30, 50, 100, 200)

#' The band a presence count falls in, as a label such as "30-49".
atlas_presence_band <- function(n, breaks = ATLAS_SWEEP_BANDS) {
  index <- findInterval(n, breaks)
  lower <- breaks[pmax(index, 1L)]
  upper <- c(breaks[-1] - 1, Inf)[pmax(index, 1L)]
  label <- ifelse(is.finite(upper), paste0(lower, "-", upper), paste0(lower, "+"))
  ifelse(index == 0L, paste0("<", breaks[1]), label)
}

#' Up to per_band taxa from each band, drawn reproducibly.
atlas_sweep_sample <- function(candidates, per_band = 40, seed = 1L,
                               breaks = ATLAS_SWEEP_BANDS) {
  band <- atlas_presence_band(candidates$cells, breaks)
  set.seed(seed)
  picked <- unlist(lapply(split(seq_len(nrow(candidates)), band), function(rows) {
    if (length(rows) <= per_band) rows else sort(sample(rows, per_band))
  }), use.names = FALSE)
  out <- candidates[sort(picked), , drop = FALSE]
  out$band <- atlas_presence_band(out$cells, breaks)
  rownames(out) <- NULL
  out
}

#' Label for an arm of the sweep.
atlas_arm_label <- function(per_presence) {
  ifelse(is.finite(per_presence), paste0("1 per ", per_presence), "no cap")
}

#' Score one taxon under every ratio, on one set of folds.
atlas_sweep_taxon <- function(name, fingerprint, points, stack,
                              constants = c(2, 3, 4, 6, Inf), grid = "draft",
                              n_background = 10000, buffer_km = 500, folds = 5,
                              block_km = 200, regmult = 1, correlation = 0.7,
                              min_presences = 20) {
  started <- Sys.time()
  training <- atlas_build_training(
    name, grid, n_background = n_background, buffer_km = buffer_km,
    write = FALSE, quiet = TRUE, points = points, stack = stack,
    fingerprint = fingerprint
  )
  presences <- sum(training$presence == 1L)
  if (presences < min_presences) {
    return(list(taxon = name, status = "refused", presences = presences))
  }
  # One set of folds for every arm: that is what makes the comparison paired.
  fold_ids <- atlas_spatial_folds(
    training$x, training$y, k = folds, block_km = block_km,
    seed = attr(training, "seed")
  )
  arms <- lapply(constants, function(per_presence) {
    keep <- atlas_choose_predictors(
      training, threshold = correlation, per_presence = per_presence
    )
    table <- training[, c("presence", "cell", "x", "y", keep), drop = FALSE]
    scores <- atlas_cross_validate(table, fold_ids, regmult = regmult)
    list(
      per_presence = if (is.finite(per_presence)) per_presence else "none",
      predictors = length(keep),
      auc = round(mean(scores$auc, na.rm = TRUE), 4),
      boyce = round(mean(scores$boyce, na.rm = TRUE), 4),
      folds_scored = sum(!is.na(scores$auc))
    )
  })
  list(
    taxon = name, status = "scored", presences = presences,
    band = atlas_presence_band(presences),
    arms = arms,
    seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  )
}

#' What a worker runs for one taxon in a sweep.
atlas_sweep_worker_task <- function(name, fingerprints, args) {
  args$points <- get(".atlas_points", envir = globalenv())
  args$stack <- get0(".atlas_stack", envir = globalenv())
  tryCatch(
    do.call(atlas_sweep_taxon, c(list(name = name, fingerprint = fingerprints[[name]]), args)),
    error = function(e) list(taxon = name, status = "failed", error = conditionMessage(e))
  )
}

#' Paired comparison of every arm with the baseline, band by band.
#'
#' For each band and arm: how many taxa, mean AUC and Boyce, mean predictors
#' kept, the mean paired difference in AUC from the baseline arm with its
#' standard error, and how often the arm was the best of all arms for a taxon.
atlas_sweep_summary <- function(rows, baseline = "4") {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  if (!length(scored)) {
    return(data.frame())
  }
  long <- do.call(rbind, lapply(scored, function(r) {
    do.call(rbind, lapply(r$arms, function(a) data.frame(
      taxon = r$taxon, band = r$band %||% atlas_presence_band(r$presences),
      arm = as.character(a$per_presence), predictors = a$predictors,
      auc = as.numeric(a$auc %||% NA), boyce = as.numeric(a$boyce %||% NA),
      stringsAsFactors = FALSE
    )))
  }))
  long$auc[is.nan(long$auc)] <- NA
  long$boyce[is.nan(long$boyce)] <- NA

  base <- long[long$arm == baseline, c("taxon", "auc"), drop = FALSE]
  names(base)[2] <- "base_auc"
  long <- merge(long, base, by = "taxon", all.x = TRUE)
  long$delta <- long$auc - long$base_auc
  best <- stats::ave(long$auc, long$taxon, FUN = function(v) {
    if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE)
  })
  long$is_best <- !is.na(long$auc) & long$auc == best

  arms <- unique(long$arm)
  bands <- c(unique(long$band[order(as.numeric(sub("[^0-9].*$", "", long$band)))]), "all")
  out <- do.call(rbind, lapply(bands, function(b) {
    in_band <- if (b == "all") long else long[long$band == b, , drop = FALSE]
    do.call(rbind, lapply(arms, function(a) {
      x <- in_band[in_band$arm == a, , drop = FALSE]
      d <- x$delta[is.finite(x$delta)]
      data.frame(
        band = b, arm = a, taxa = nrow(x),
        predictors = round(mean(x$predictors), 1),
        auc = round(mean(x$auc, na.rm = TRUE), 3),
        boyce = round(mean(x$boyce, na.rm = TRUE), 3),
        delta_auc = if (length(d)) round(mean(d), 4) else NA_real_,
        delta_se = if (length(d) > 1L) round(stats::sd(d) / sqrt(length(d)), 4) else NA_real_,
        best_share = round(mean(x$is_best), 2),
        stringsAsFactors = FALSE
      )
    }))
  }))
  rownames(out) <- NULL
  out
}

#' Run the sweep over a stratified sample of the batch candidates.
atlas_predictor_sweep <- function(grid = "draft", per_band = 40,
                                  constants = c(2, 3, 4, 6, Inf), workers = 1L,
                                  seed = 1L, min_presences = 20,
                                  n_background = 10000, buffer_km = 500,
                                  folds = 5, block_km = 200, regmult = 1,
                                  correlation = 0.7, quiet = FALSE,
                                  occurrences = NULL, points = NULL,
                                  stack = NULL, taxa = NULL) {
  started <- Sys.time()
  stamp <- format(started, "%Y%m%dT%H%M%SZ", tz = "UTC")
  path <- atlas_path("sweeps", grid, paste0("predictors-", stamp, ".json"))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  log <- file(sub("[.]json$", ".log", path), open = "wt")
  on.exit(close(log), add = TRUE)
  say <- function(...) {
    line <- paste0(format(Sys.time(), "%H:%M:%S"), "  ", ...)
    writeLines(line, log)
    flush(log)
    if (!isTRUE(quiet)) message(line)
  }

  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  candidates <- atlas_batch_candidates(points, min_presences, taxa = taxa)
  sample <- atlas_sweep_sample(candidates, per_band = per_band, seed = seed)
  fingerprints <- atlas_fingerprints_for(occurrences, sample$scientific_name)
  say(nrow(sample), " taxa sampled from ", nrow(candidates), " candidates (",
      paste(names(table(sample$band)), table(sample$band), sep = ": ", collapse = ", "),
      "); arms: ", paste(atlas_arm_label(constants), collapse = ", "))

  args <- list(
    constants = constants, grid = grid, n_background = n_background,
    buffer_km = buffer_km, folds = folds, block_km = block_km,
    regmult = regmult, correlation = correlation, min_presences = min_presences
  )
  settings <- c(args[setdiff(names(args), "constants")],
                list(constants = as.list(ifelse(is.finite(constants), constants, "none")),
                     per_band = per_band, seed = seed))
  rows <- list()
  save <- function() {
    atlas_write_json(
      list(started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
           settings = settings, layers = atlas_layers_key(grid),
           summary = atlas_sweep_summary(rows), taxa = rows),
      path
    )
  }
  record <- function(row) {
    rows[[length(rows) + 1L]] <<- row
    save()
    detail <- if (identical(row$status, "scored")) {
      paste(vapply(row$arms, function(a) sprintf("%s:%s", a$per_presence, a$auc),
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
    task <- atlas_sweep_worker_task
    environment(task) <- globalenv()
    atlas_run_on_workers(cluster, names, task, record,
                         fingerprints = fingerprints, args = args)
  } else if (length(names)) {
    stack <- stack %||% atlas_predictor_stack(grid)
    for (name in names) {
      record(tryCatch(
        do.call(atlas_sweep_taxon, c(list(name = name, fingerprint = fingerprints[[name]],
                                          points = points, stack = stack), args)),
        error = function(e) list(taxon = name, status = "failed", error = conditionMessage(e))
      ))
    }
  }

  save()
  summary <- atlas_sweep_summary(rows)
  if (!isTRUE(quiet) && nrow(summary)) {
    print(summary, row.names = FALSE)
  }
  say("done in ", round(as.numeric(difftime(Sys.time(), started, units = "secs"))),
      "s -> ", path)
  invisible(list(summary = summary, taxa = rows, path = path))
}
