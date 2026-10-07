# Where a map knows what it is talking about: its area of applicability.
#
# A map is drawn across a 500 km circle around every detection, and parts of
# those circles hold conditions no survey site has: high Arctic, desert,
# mountain tops. There the model has learned nothing; Maxent clamps its
# features and trees hold their edge values, so the map shows a confident
# colour that rests on no data at all.
#
# The dissimilarity index of Meyer & Pebesma (2021) says how unlike a place is
# to every site the model learned from. Predictors are standardised by the
# training sites and weighted by how much the model used each one, measured
# on held-out ground (R/importance.R), so a difference in a predictor the
# model ignores does not count. A place's index is its distance to the
# nearest training site in that weighted space, divided by the mean distance
# between training sites. The threshold comes from the training sites
# themselves: each site's index against the sites of the other folds, as the
# cross-validation saw it, and the upper whisker of those (boxplot.stats, as
# CAST does). A place past the threshold is less like the training data than
# a held-out site ever was: outside the area of applicability.
#
# The index is kept as a layer of its own beside each map, not only as a
# yes/no mask, so a page can show how unfamiliar a place is.

# Sites sampled to estimate the mean distance between training sites.
ATLAS_AOA_PAIR_SITES <- 2000L
# Rows compared at once when searching for the nearest site.
ATLAS_AOA_CHUNK <- 2000L

#' Each predictor's weight: its mean fall in held-out AUC when shuffled,
#' never below zero. With nothing measured (no importance, or every fall at
#' or below zero), every predictor counts the same.
#'
#' falls is attr(, "falls") of atlas_nested_cross_validate: rows named
#' "predictor\r<name>" or "layer\r<name>", one column per fold.
atlas_aoa_weights <- function(falls, predictors) {
  weights <- stats::setNames(rep(0, length(predictors)), predictors)
  if (!is.null(falls) && length(falls)) {
    rows <- paste0("predictor\r", predictors)
    present <- rows %in% rownames(falls)
    weights[present] <- apply(falls[rows[present], , drop = FALSE], 1, function(v) {
      if (all(is.na(v))) 0 else mean(v, na.rm = TRUE)
    })
  }
  weights[!is.finite(weights)] <- 0
  weights <- pmax(weights, 0)
  if (!any(weights > 0)) {
    weights[] <- 1
    attr(weights, "source") <- "equal"
  } else {
    attr(weights, "source") <- "importance"
  }
  weights
}

#' Distance from each row of q to the nearest row of r (Euclidean), in
#' chunks so a map's worth of cells never builds one huge matrix.
atlas_nearest_rows <- function(q, r, chunk = ATLAS_AOA_CHUNK) {
  q <- as.matrix(q)
  r <- as.matrix(r)
  if (!nrow(q)) return(numeric())
  if (!nrow(r)) return(rep(NA_real_, nrow(q)))
  r2 <- rowSums(r^2)
  out <- numeric(nrow(q))
  for (start in seq(1L, nrow(q), by = chunk)) {
    rows <- start:min(nrow(q), start + chunk - 1L)
    block <- q[rows, , drop = FALSE]
    # |a - b|^2 = |a|^2 + |b|^2 - 2 a.b, smallest over the reference rows.
    d2 <- outer(rowSums(block^2), r2, "+") - 2 * tcrossprod(block, r)
    nearest <- max.col(-d2, ties.method = "first")
    out[rows] <- sqrt(pmax(0, d2[cbind(seq_along(rows), nearest)]))
  }
  out
}

#' Prepare a model's area of applicability from its training sites.
#'
#' training holds the sites the model was fitted on, folds their spatial
#' folds, predictors the columns the model used, and weights their weights
#' (atlas_aoa_weights). Returns what atlas_aoa_index needs: the scaling, the
#' weighted training sites, the mean distance between them and the
#' threshold.
atlas_aoa_train <- function(training, predictors, weights, folds,
                            pair_sites = ATLAS_AOA_PAIR_SITES, seed = 1L) {
  weights <- weights[predictors]
  used <- predictors[weights > 0]
  x <- as.matrix(training[, used, drop = FALSE])
  centre <- colMeans(x)
  spread <- apply(x, 2, stats::sd)
  spread[!is.finite(spread) | spread == 0] <- 1
  weighted <- function(m) sweep(sweep(m, 2, centre, "-"), 2, spread / weights[used], "/")
  z <- weighted(x)
  set.seed(seed)
  sample_rows <- sample.int(nrow(z), min(pair_sites, nrow(z)))
  mean_distance <- mean(stats::dist(z[sample_rows, , drop = FALSE]))
  if (!is.finite(mean_distance) || mean_distance <= 0) mean_distance <- 1
  cv_index <- numeric(nrow(z))
  for (fold in unique(folds)) {
    held <- folds == fold
    cv_index[held] <- atlas_nearest_rows(z[held, , drop = FALSE], z[!held, , drop = FALSE]) / mean_distance
  }
  finite <- cv_index[is.finite(cv_index)]
  threshold <- if (length(finite)) grDevices::boxplot.stats(finite)$stats[[5]] else NA_real_
  structure(list(
    predictors = used, centre = centre, spread = spread, weights = weights[used],
    weight_source = attr(weights, "source") %||% "given",
    sites = z, mean_distance = mean_distance, threshold = threshold,
    training_index = stats::quantile(finite, c(0.5, 0.95), names = FALSE)
  ), class = "atlas_aoa")
}

#' The dissimilarity index of every row of newdata.
atlas_aoa_index <- function(aoa, newdata) {
  x <- as.matrix(newdata[, aoa$predictors, drop = FALSE])
  z <- sweep(sweep(x, 2, aoa$centre, "-"), 2, aoa$spread / aoa$weights, "/")
  atlas_nearest_rows(z, aoa$sites) / aoa$mean_distance
}

#' What a model's metrics keep about its area of applicability.
atlas_aoa_summary <- function(aoa, index_raster = NULL) {
  inside <- if (!is.null(index_raster)) {
    values <- terra::values(index_raster, mat = FALSE)
    values <- values[is.finite(values)]
    if (length(values)) round(mean(values <= aoa$threshold), 4) else NA_real_
  } else {
    NA_real_
  }
  list(
    method = "dissimilarity index, Meyer & Pebesma 2021",
    threshold = round(aoa$threshold, 4),
    inside_share = inside,
    weights = aoa$weight_source,
    predictors = length(aoa$predictors),
    sites = nrow(aoa$sites),
    training_index_median = round(aoa$training_index[[1]], 4),
    training_index_95 = round(aoa$training_index[[2]], 4)
  )
}
