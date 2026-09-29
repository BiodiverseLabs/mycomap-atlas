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

#' Paired comparison of every arm with the baseline, band by band.
#'
#' For each band and arm: how many taxa, mean AUC and Boyce, mean predictors
#' kept, the mean paired difference in AUC and in Boyce from the baseline arm
#' with their standard errors, and how often the arm had the best AUC.
atlas_sweep_summary <- function(rows, baseline = "4") {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  if (!length(scored)) {
    return(data.frame())
  }
  long <- do.call(rbind, lapply(scored, function(r) {
    do.call(rbind, lapply(r$arms, function(a) data.frame(
      taxon = r$taxon, band = r$band %||% atlas_presence_band(r$presences),
      arm = atlas_arm_name(a), predictors = as.numeric(a$predictors %||% NA),
      auc = as.numeric(a$auc %||% NA), boyce = as.numeric(a$boyce %||% NA),
      stringsAsFactors = FALSE
    )))
  }))
  long$auc[is.nan(long$auc)] <- NA
  long$boyce[is.nan(long$boyce)] <- NA

  base <- long[long$arm == baseline, c("taxon", "auc", "boyce"), drop = FALSE]
  names(base)[2:3] <- c("base_auc", "base_boyce")
  long <- merge(long, base, by = "taxon", all.x = TRUE)
  long$delta <- long$auc - long$base_auc
  long$delta_b <- long$boyce - long$base_boyce
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
      db <- x$delta_b[is.finite(x$delta_b)]
      data.frame(
        band = b, arm = a, taxa = nrow(x),
        predictors = round(mean(x$predictors, na.rm = TRUE), 1),
        auc = round(mean(x$auc, na.rm = TRUE), 3),
        boyce = round(mean(x$boyce, na.rm = TRUE), 3),
        delta_auc = if (length(d)) round(mean(d), 4) else NA_real_,
        delta_se = if (length(d) > 1L) round(stats::sd(d) / sqrt(length(d)), 4) else NA_real_,
        delta_boyce = if (length(db)) round(mean(db), 4) else NA_real_,
        delta_boyce_se = if (length(db) > 1L) round(stats::sd(db) / sqrt(length(db)), 4) else NA_real_,
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
  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  candidates <- atlas_batch_candidates(points, min_presences, taxa = taxa)
  sample <- atlas_sweep_sample(candidates, per_band = per_band, seed = seed)
  fingerprints <- atlas_fingerprints_for(occurrences, sample$scientific_name)

  args <- list(
    constants = constants, grid = grid, n_background = n_background,
    buffer_km = buffer_km, folds = folds, block_km = block_km,
    regmult = regmult, correlation = correlation, min_presences = min_presences
  )
  settings <- c(args[setdiff(names(args), "constants")],
                list(constants = as.list(ifelse(is.finite(constants), constants, "none")),
                     per_band = per_band, seed = seed))
  atlas_run_study(
    kind = "sweeps", file_prefix = "predictors", taxon_fn = "atlas_sweep_taxon",
    sample = sample, fingerprints = fingerprints, args = args,
    settings = settings, baseline = "4", grid = grid, workers = workers,
    points = points, stack = stack, quiet = quiet,
    opening = paste0(
      nrow(sample), " taxa sampled from ", nrow(candidates), " candidates (",
      atlas_band_counts(sample), "); arms: ",
      paste(atlas_arm_label(constants), collapse = ", ")
    )
  )
}

#' "20-29: 40, 30-49: 40" for a sample, in band order.
atlas_band_counts <- function(sample) {
  counts <- table(sample$band)
  order <- order(as.numeric(sub("[^0-9].*$", "", names(counts))))
  paste(names(counts)[order], counts[order], sep = ": ", collapse = ", ")
}
