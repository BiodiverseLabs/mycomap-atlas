# Null models that keep a taxon's clustering, a test that stops early, and
# a correction for testing thousands of taxa.
#
# The null test asks whether a map beats species that know nothing. The
# production nulls ("scatter") draw detection sites one by one, busier sites
# more often. Real detections are not scattered: a lineage named for the
# Pacific Northwest sits in the Pacific Northwest. Within a 500 km circle,
# almost any smooth predictor tells a cluster from the rest of the circle,
# and scattered nulls cannot do that (Hijmans 2012, spatial sorting bias). So
# a clustered taxon can pass the test on clustering alone.
#
# A "shift" null keeps the shape of the real pattern. Every detection is
# rotated by one random angle about their centre, and the whole pattern is
# moved to a random survey site (busier sites more often). Each moved point
# then snaps to a survey site, never two to the same one. A draw is rejected
# when more than a fifth of its points land further than ATLAS_NULL_SNAP_KM
# from any free site, which is moving a cluster into ground nobody surveyed.
# After ATLAS_NULL_SHIFT_TRIES rejections the null falls back to a scattered
# draw, and the fallback is counted. "shift-effort" snaps each point among the
# nearest free sites within snap distance in proportion to their records, so
# the nulls keep both the clustering and the pull of busy sites.
#
# With 19 nulls the smallest p is 0.05, so a single tie fails a map. The
# sequential test (Besag & Clifford 1991) draws up to 99, in batches, and
# stops once stop_after nulls have done at least as well as the map: p is
# then stop_after over the nulls drawn. Stopping after 5 gives the same pass
# or fail at 0.05 as drawing all 99, at a fraction of the cost for maps that
# fail.
#
# Across thousands of taxa, 5% of maps of species that know nothing would
# pass at p = 0.05. atlas_null_qvalues gives Benjamini-Hochberg q-values, the
# false discovery rate at which each map would pass.

ATLAS_NULL_DESIGNS <- c("scatter", "shift", "shift-effort")
# How far a moved point may land from a free survey site, in km, and the
# share of points that may land further before a draw is rejected.
ATLAS_NULL_SNAP_KM <- 25
ATLAS_NULL_FAR_SHARE <- 0.2
# Draws of a shift null before it falls back to a scattered one.
ATLAS_NULL_SHIFT_TRIES <- 200L
# Free sites a shift-effort point chooses among.
ATLAS_NULL_SNAP_CHOICES <- 5L

#' One null design, refusing names Atlas does not know.
atlas_null_design <- function(design) {
  design <- as.character(design %||% "scatter")[[1]]
  if (!design %in% ATLAS_NULL_DESIGNS) {
    stop("unknown null design '", design, "': use one of ",
         paste(ATLAS_NULL_DESIGNS, collapse = ", "), call. = FALSE)
  }
  design
}

#' Snap moved points to survey sites, one site each.
#'
#' Points are taken in random order; each takes the nearest free site, or,
#' with weight, one of the choices nearest free sites within snap_km (always
#' at least the nearest) in proportion to weight. Returns the row of each
#' point's site, or NULL when more than far_share of the points land further
#' than snap_km from a free site.
atlas_snap_to_sites <- function(px, py, sx, sy, weight = NULL, snap_km = ATLAS_NULL_SNAP_KM,
                                far_share = ATLAS_NULL_FAR_SHARE,
                                choices = ATLAS_NULL_SNAP_CHOICES) {
  n <- length(px)
  if (n > length(sx)) return(NULL)
  allowed_far <- floor(far_share * n)
  used <- logical(length(sx))
  chosen <- integer(n)
  far <- 0L
  for (i in sample.int(n)) {
    d <- sqrt((sx - px[[i]])^2 + (sy - py[[i]])^2) / 1000
    d[used] <- Inf
    nearest <- which.min(d)
    j <- nearest
    if (!is.null(weight)) {
      candidates <- utils::head(order(d), choices)
      candidates <- candidates[d[candidates] <= max(snap_km, d[[nearest]])]
      if (length(candidates) > 1L) j <- candidates[[sample.int(length(candidates), 1L, prob = weight[candidates])]]
    }
    if (d[[j]] > snap_km) {
      far <- far + 1L
      if (far > allowed_far) return(NULL)
    }
    used[[j]] <- TRUE
    chosen[[i]] <- j
  }
  chosen
}

#' One shifted null: the real detections rotated, moved and snapped to
#' sites. attr(, "tries") says how many draws it took; attr(, "fallback") is
#' TRUE when every draw was rejected and the null was scattered instead.
atlas_null_shift <- function(training, seed, effort = FALSE, tries = ATLAS_NULL_SHIFT_TRIES,
                             snap_km = ATLAS_NULL_SNAP_KM) {
  found <- which(training$presence == 1L)
  weight <- if (ATLAS_EFFORT_COLUMN %in% names(training)) {
    exp(training[[ATLAS_EFFORT_COLUMN]])
  } else {
    rep(1, nrow(training))
  }
  dx <- training$x[found] - mean(training$x[found])
  dy <- training$y[found] - mean(training$y[found])
  set.seed(seed)
  for (try in seq_len(tries)) {
    angle <- stats::runif(1, 0, 2 * pi)
    anchor <- sample.int(nrow(training), 1L, prob = weight)
    px <- training$x[[anchor]] + dx * cos(angle) - dy * sin(angle)
    py <- training$y[[anchor]] + dx * sin(angle) + dy * cos(angle)
    snapped <- atlas_snap_to_sites(px, py, training$x, training$y,
                                   weight = if (isTRUE(effort)) weight, snap_km = snap_km)
    if (!is.null(snapped)) {
      presence <- integer(nrow(training))
      presence[snapped] <- 1L
      attr(presence, "tries") <- try
      attr(presence, "fallback") <- FALSE
      return(presence)
    }
  }
  presence <- atlas_null_presence(training, length(found), seed = seed)
  attr(presence, "tries") <- tries
  attr(presence, "fallback") <- TRUE
  presence
}

#' A null's detections under any design.
atlas_null_draw <- function(training, n, seed, design = "scatter") {
  switch(
    atlas_null_design(design),
    scatter = atlas_null_presence(training, n, seed),
    shift = atlas_null_shift(training, seed, effort = FALSE),
    "shift-effort" = atlas_null_shift(training, seed, effort = TRUE)
  )
}

#' The null test with any design, drawing nulls in batches until reps are
#' scored or stop_after of them have done at least as well as the taxon.
#'
#' Same procedure as atlas_null_test (same sites, folds and untuned
#' settings; a failed null is replaced, up to 2 x reps draws), and the same
#' result, with the design, how many nulls were drawn, whether the test
#' stopped early and how many shifted nulls fell back to scattered ones.
atlas_null_test_sequential <- function(training, folds, algo, reps = 99L, seed = 1L,
                                       design = "scatter", stop_after = 5L, batch = 10L) {
  design <- atlas_null_design(design)
  if (!reps) return(list(reps = 0L))
  params <- atlas_null_params(algo, training)
  n <- sum(training$presence == 1L)
  summarise <- function(scores) {
    if (is.null(scores)) return(c(auc = NA_real_, boyce = NA_real_))
    c(auc = mean(scores$auc, na.rm = TRUE), boyce = atlas_pooled_boyce(scores))
  }
  fallbacks <- 0L
  null_table <- function(draw) {
    null <- training
    null$presence <- atlas_null_draw(training, n, seed + 1000L + draw, design)
    if (isTRUE(attr(null$presence, "fallback"))) fallbacks <<- fallbacks + 1L
    attributes(null$presence) <- NULL
    null
  }
  run_tables <- function(tables) {
    if (atlas_shares_features(algo)) {
      features <- atlas_feature_cache()
      fit <- atlas_fit_sharing(algo, params, seed, features)
      runs <- lapply(tables, function(table) {
        list(training = table, fit = fit, score = algo$score, effort_at = atlas_effort_level(table))
      })
      lapply(atlas_cross_validate_by_fold(runs, folds, features), summarise)
    } else {
      lapply(tables, function(table) summarise(tryCatch(
        atlas_cross_validate(table, folds,
                             fit = function(train) algo$fit(train, params, seed, tuning = TRUE),
                             score = algo$score, effort_at = atlas_effort_level(table)),
        error = function(e) NULL
      )))
    }
  }
  stream <- atlas_rng_state()
  observed <- run_tables(list(training))[[1]]
  if (!is.finite(observed[["auc"]])) {
    atlas_rng_restore(stream)
    return(list(reps = 0L))
  }
  aucs <- numeric()
  boyces <- numeric()
  above <- 0L
  draw <- 0L
  while (length(aucs) < reps && above < stop_after && draw < 2L * reps) {
    take <- seq.int(draw + 1L, min(draw + batch, 2L * reps))
    draw <- take[[length(take)]]
    # Results are taken in draw order and the count stops exactly where a
    # one-at-a-time test would, so the batch size changes nothing but speed.
    for (result in run_tables(lapply(take, null_table))) {
      if (length(aucs) >= reps || above >= stop_after) break
      if (!is.finite(result[["auc"]])) next
      aucs <- c(aucs, result[["auc"]])
      boyces <- c(boyces, result[["boyce"]])
      if (result[["auc"]] >= observed[["auc"]]) above <- above + 1L
    }
  }
  stopped <- above >= stop_after
  p <- if (!length(aucs)) {
    NA_real_
  } else if (stopped) {
    stop_after / length(aucs)
  } else {
    (1 + above) / (1 + length(aucs))
  }
  boyces <- boyces[is.finite(boyces)]
  list(
    reps = length(aucs),
    design = design,
    settings = atlas_params_label(params),
    observed_auc = round(observed[["auc"]], 3),
    observed_boyce = round(observed[["boyce"]], 3),
    auc_mean = round(mean(aucs), 3),
    auc_sd = round(stats::sd(aucs), 3),
    auc_p = round(p, 4),
    boyce_mean = if (length(boyces)) round(mean(boyces), 3) else NA_real_,
    stopped_early = stopped,
    drawn = draw,
    fallbacks = fallbacks
  )
}

#' Benjamini-Hochberg q-values: for each p, the false discovery rate at
#' which it would pass. NA stays NA and is not counted as a test (p.adjust
#' counts only the p-values it is given that are not NA).
atlas_null_qvalues <- function(p) {
  stats::p.adjust(as.numeric(p), method = "BH")
}
