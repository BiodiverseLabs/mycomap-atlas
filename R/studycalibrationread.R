# Reading the null calibration (paper E1): the pre-registered tests, run on
# the pooled shards of the full study (R/studycalibration.R). Written and
# reviewed before the full run's results are opened (E1 prereg, Deviations,
# 2026-10-25); nothing here may change after.
#
# Every test reads the long rows (atlas_calibration_long): one row per
# species, learner and null design, with the learner's verdict. A geography
# species has no habitat, so its pass is a false pass; a habitat species'
# pass is power.
#
#   H1a  shift nulls hold false pass at or below 5%: per learner (Maxent, RF),
#        the pooled Wilson upper bound <= 5% and the rate <= 5% in every band.
#   H1b  scatter nulls exceed it: per learner, the pooled Wilson lower bound
#        > 20%, and the rate rises with band (Cochran-Armitage, one-sided
#        p < 0.05).
#   H1c  shift power differs with realised breadth: per learner, logistic
#        regression of pass on realised breadth, band (a factor) and signal
#        strength; two-sided p < 0.05 on breadth, its direction reported.
#   H1d  among narrow habitats, shift power rises with band
#        (Cochran-Armitage, one-sided p < 0.05).
#   H1f  shift power is higher for strong than weak signal: one-sided
#        p < 0.05 on strength in the H1c model.
#   H1e  among habitat species, map-to-truth rho is higher for shift-passed
#        maps: per learner, one-sided Wilcoxon p < 0.05, with the median
#        difference and its bootstrap interval (resampling species).
#
# C1 is supported when H1a, H1b and H1e hold for Maxent and for RF. As the
# prereg was amended before any outcome was read (2026-10-25), a learner that
# fails H1a is decided band by band: C1 holds in the bands where H1a holds in
# the band (shift false-pass upper bound <= 5%) and scatter's lower bound is
# above 20%, if H1e holds over those bands; every other band is reported as
# failing (atlas_calibration_c1_bands). Best-effort shifted nulls are
# reported by band. The ensembles (ESM, 3-19 sites) are read against the
# same criteria by band, as secondary results. The map tiers (E24) are a
# secondary analysis of the shift rows.

ATLAS_CALIBRATION_READ_REPS <- 10000L
ATLAS_CALIBRATION_READ_SEED <- 1L
ATLAS_CALIBRATION_FALSE_PASS_MAX <- 0.05
ATLAS_CALIBRATION_SCATTER_MIN <- 0.20
ATLAS_CALIBRATION_ALPHA <- 0.05
# The learners C1 is decided on, and the one read as secondary.
ATLAS_CALIBRATION_PRIMARY <- c("maxnet", "rf")
ATLAS_CALIBRATION_SECONDARY <- "esm"

#' Wilson 95% interval for k of n, unrounded (the decisions compare it with
#' 5% and 20%, so no rounding happens before them).
atlas_calibration_wilson <- function(k, n, z = 1.96) {
  if (!n) return(c(NA_real_, NA_real_))
  p <- k / n
  centre <- (p + z^2 / (2 * n)) / (1 + z^2 / n)
  half <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / (1 + z^2 / n)
  c(max(0, centre - half), min(1, centre + half))
}

#' Cochran-Armitage test for a rate rising over ordered groups: k passes of
#' n in each group, scored 1, 2, ... in order. Returns z and the one-sided p
#' for a rise (its square is stats::prop.trend.test's statistic).
atlas_calibration_trend <- function(k, n, scores = seq_along(n)) {
  keep <- n > 0
  k <- k[keep]
  n <- n[keep]
  scores <- scores[keep]
  total <- sum(n)
  p <- if (total) sum(k) / total else NA_real_
  variance <- p * (1 - p) * (sum(n * scores^2) - sum(n * scores)^2 / total)
  if (length(n) < 2L || !is.finite(variance) || variance <= 0) {
    return(list(z = NA_real_, p = NA_real_, groups = length(n)))
  }
  z <- sum(scores * (k - n * p)) / sqrt(variance)
  list(z = z, p = stats::pnorm(z, lower.tail = FALSE), groups = length(n))
}

#' Bands in their order, lowest first: the full models' then the ensembles'.
atlas_calibration_band_levels <- function(family = "full") {
  bands <- if (identical(family, "esm")) ATLAS_CALIBRATION_ESM_BANDS else ATLAS_CALIBRATION_FULL_BANDS
  vapply(bands, atlas_calibration_band_label, "")
}

#' Pass counts, rate and Wilson interval of a set of long rows, overall and
#' by band in order.
atlas_calibration_rate <- function(x, family) {
  levels <- atlas_calibration_band_levels(family)
  interval <- atlas_calibration_wilson(sum(x$passed), nrow(x))
  by_band <- lapply(levels, function(b) {
    y <- x[x$band == b, , drop = FALSE]
    i <- atlas_calibration_wilson(sum(y$passed), nrow(y))
    list(band = b, species = nrow(y), passed = sum(y$passed),
         rate = if (nrow(y)) sum(y$passed) / nrow(y) else NA_real_, low = i[[1]], high = i[[2]])
  })
  list(species = nrow(x), passed = sum(x$passed), rate = if (nrow(x)) sum(x$passed) / nrow(x) else NA_real_,
       low = interval[[1]], high = interval[[2]], by_band = by_band)
}

#' The trend over bands of a set of long rows.
atlas_calibration_band_trend <- function(x, family) {
  levels <- atlas_calibration_band_levels(family)
  k <- vapply(levels, function(b) sum(x$passed[x$band == b]), 0)
  n <- vapply(levels, function(b) sum(x$band == b), 0)
  atlas_calibration_trend(k, n)
}

#' The rows of one learner, design and kind.
atlas_calibration_rows <- function(long, learner, design, kind) {
  long[long$learner == learner & long$design == design & long$kind == kind, , drop = FALSE]
}

#' H1a: shift false pass at or below 5%.
atlas_calibration_h1a <- function(long, learner) {
  family <- if (learner == "esm") "esm" else "full"
  rate <- atlas_calibration_rate(atlas_calibration_rows(long, learner, "shift", "geography"), family)
  bands <- vapply(rate$by_band, function(b) b$rate, 0)
  holds <- rate$species > 0 && isTRUE(rate$high <= ATLAS_CALIBRATION_FALSE_PASS_MAX) &&
    all(is.finite(bands)) && all(bands <= ATLAS_CALIBRATION_FALSE_PASS_MAX)
  c(rate, list(holds = holds))
}

#' H1b: scatter false pass above 20%, rising with band.
atlas_calibration_h1b <- function(long, learner) {
  family <- if (learner == "esm") "esm" else "full"
  x <- atlas_calibration_rows(long, learner, "scatter", "geography")
  rate <- atlas_calibration_rate(x, family)
  trend <- atlas_calibration_band_trend(x, family)
  holds <- rate$species > 0 && isTRUE(rate$low > ATLAS_CALIBRATION_SCATTER_MIN) &&
    isTRUE(trend$p < ATLAS_CALIBRATION_ALPHA)
  c(rate, list(trend_z = trend$z, trend_p = trend$p, holds = holds))
}

#' The H1c model: shift pass of habitat species on realised breadth, band
#' (a factor, lowest band the reference) and signal strength (weak the
#' reference). Returns the fit, its rows and any warning glm gave.
atlas_calibration_power_model <- function(long, learner) {
  family <- if (learner == "esm") "esm" else "full"
  x <- atlas_calibration_rows(long, learner, "shift", "habitat")
  dropped <- sum(!is.finite(x$realised_breadth))
  x <- x[is.finite(x$realised_breadth), , drop = FALSE]
  x$band <- factor(x$band, levels = atlas_calibration_band_levels(family))
  x$band <- droplevels(x$band)
  x$signal <- factor(x$signal, levels = c("weak", "strong"))
  x$y <- as.integer(x$passed)
  terms <- c("realised_breadth", if (nlevels(x$band) > 1L) "band", if (length(unique(x$signal)) > 1L) "signal")
  if (nrow(x) < length(terms) + 2L || length(unique(x$y)) < 2L) {
    return(list(model = NULL, rows = nrow(x), dropped = dropped, warning = "too few species or no variation in pass"))
  }
  warning <- NULL
  model <- withCallingHandlers(
    stats::glm(stats::reformulate(terms, "y"), family = stats::binomial(), data = x),
    warning = function(w) {
      warning <<- c(warning, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(model = model, rows = nrow(x), dropped = dropped, warning = warning, data = x)
}

#' One coefficient of the H1c model: estimate, z, two-sided and one-sided
#' (positive) p.
atlas_calibration_coefficient <- function(model, term) {
  table <- if (!is.null(model$model)) summary(model$model)$coefficients
  if (is.null(table) || !term %in% rownames(table)) {
    return(list(estimate = NA_real_, z = NA_real_, p_two_sided = NA_real_, p_greater = NA_real_))
  }
  z <- table[term, "z value"]
  list(estimate = table[term, "Estimate"], z = z, p_two_sided = table[term, "Pr(>|z|)"],
       p_greater = stats::pnorm(z, lower.tail = FALSE))
}

#' H1c and H1f from one model, and the power curve it gives: predicted shift
#' power by band and strength at the quartiles of realised breadth.
atlas_calibration_h1cf <- function(long, learner) {
  fit <- atlas_calibration_power_model(long, learner)
  base <- list(species = fit$rows, without_breadth = fit$dropped, warnings = as.list(fit$warning))
  if (is.null(fit$model)) {
    na <- list(estimate = NA_real_, z = NA_real_, p_two_sided = NA_real_, p_greater = NA_real_)
    return(list(model = base, h1c = c(na, list(direction = NA_character_, holds = FALSE)),
                h1f = c(na, list(holds = FALSE)), curve = list()))
  }
  breadth <- atlas_calibration_coefficient(fit, "realised_breadth")
  strength <- atlas_calibration_coefficient(fit, "signalstrong")
  data <- fit$data
  quartiles <- stats::quantile(data$realised_breadth, c(0.25, 0.5, 0.75), names = FALSE)
  grid <- expand.grid(realised_breadth = quartiles, band = levels(data$band),
                      signal = levels(droplevels(data$signal)), stringsAsFactors = FALSE)
  grid$band <- factor(grid$band, levels = levels(data$band))
  grid$signal <- factor(grid$signal, levels = levels(data$signal))
  grid$power <- as.numeric(stats::predict(fit$model, newdata = grid, type = "response"))
  grid$band <- as.character(grid$band)
  grid$signal <- as.character(grid$signal)
  list(
    model = base,
    h1c = c(breadth, list(direction = if (is.finite(breadth$estimate)) {
      if (breadth$estimate < 0) "lower for wider habitats" else "higher for wider habitats"
    } else NA_character_, holds = isTRUE(breadth$p_two_sided < ATLAS_CALIBRATION_ALPHA))),
    h1f = c(strength, list(holds = isTRUE(strength$p_greater < ATLAS_CALIBRATION_ALPHA))),
    curve = grid
  )
}

#' Shift power of a learner's habitat species by band and signal strength,
#' with Wilson intervals (reported; the ensembles' power at 3-19 sites is
#' what C4's small-site counts rest on).
atlas_calibration_power_table <- function(long, learner) {
  family <- if (learner == "esm") "esm" else "full"
  x <- atlas_calibration_rows(long, learner, "shift", "habitat")
  out <- do.call(rbind, lapply(atlas_calibration_band_levels(family), function(b) {
    do.call(rbind, lapply(ATLAS_CALIBRATION_SIGNALS, function(signal) {
      y <- x[x$band == b & x$signal %in% signal, , drop = FALSE]
      i <- atlas_calibration_wilson(sum(y$passed), nrow(y))
      data.frame(learner = learner, band = b, signal = signal, species = nrow(y), passed = sum(y$passed),
                 rate = if (nrow(y)) sum(y$passed) / nrow(y) else NA_real_, low = i[[1]], high = i[[2]],
                 stringsAsFactors = FALSE)
    }))
  }))
  rownames(out) <- NULL
  out
}

#' H1d: among narrow habitats, shift power rises with band.
atlas_calibration_h1d <- function(long, learner) {
  x <- atlas_calibration_rows(long, learner, "shift", "habitat")
  x <- x[!is.na(x$breadth) & x$breadth == "narrow", , drop = FALSE]
  rate <- atlas_calibration_rate(x, "full")
  trend <- atlas_calibration_band_trend(x, "full")
  c(rate, list(trend_z = trend$z, trend_p = trend$p, holds = isTRUE(trend$p < ATLAS_CALIBRATION_ALPHA)))
}

#' H1e: map-to-truth rho of shift-passed habitat maps against the rest. The
#' interval is for the difference in medians, from reps resamples of species
#' within each group.
atlas_calibration_h1e <- function(long, learner, reps = ATLAS_CALIBRATION_READ_REPS,
                                  seed = ATLAS_CALIBRATION_READ_SEED) {
  x <- atlas_calibration_rows(long, learner, "shift", "habitat")
  x <- x[is.finite(x$truth_rho), , drop = FALSE]
  passed <- x$truth_rho[x$passed]
  rest <- x$truth_rho[!x$passed]
  out <- list(passed = length(passed), rest = length(rest),
              median_passed = if (length(passed)) stats::median(passed) else NA_real_,
              median_rest = if (length(rest)) stats::median(rest) else NA_real_)
  if (!length(passed) || !length(rest)) {
    return(c(out, list(difference = NA_real_, low = NA_real_, high = NA_real_, p = NA_real_, holds = FALSE)))
  }
  test <- stats::wilcox.test(passed, rest, alternative = "greater", exact = FALSE)
  set.seed(seed)
  boot <- vapply(seq_len(reps), function(i) {
    stats::median(sample(passed, length(passed), replace = TRUE)) -
      stats::median(sample(rest, length(rest), replace = TRUE))
  }, 0)
  interval <- stats::quantile(boot, c(0.025, 0.975), names = FALSE)
  c(out, list(difference = out$median_passed - out$median_rest, low = interval[[1]], high = interval[[2]],
              p = test$p.value, holds = isTRUE(test$p.value < ATLAS_CALIBRATION_ALPHA)))
}

#' The map tiers (E24) on the shift rows: for each tier, the share of
#' geography species (false pass) and of habitat species (power), by
#' learner, kind, band, breadth and strength, with Wilson intervals, counted
#' two ways (column count): "at_or_better" (strong; strong or moderate;
#' strong or moderate-z; strong, moderate or indicative) and "exact" (the
#' tier alone, strong excluded from the others, as E2's H2d-H2f read them);
#' and map-to-truth rho of habitat species by their exact tier.
atlas_calibration_tiers <- function(long) {
  x <- long[long$design == "shift", , drop = FALSE]
  if (!nrow(x)) return(list(rates = data.frame(), rho = data.frame()))
  # At that tier or better, and at exactly that tier (as E2's H2d-H2f read
  # them): both are reported.
  reach <- list(
    at_or_better = list(
      strong = x$passed,
      moderate = x$passed | x$tier %in% "moderate",
      moderate_z = x$passed | x$moderate_z %in% TRUE,
      indicative = x$passed | x$tier %in% c("moderate", "indicative")
    ),
    exact = list(
      strong = x$passed,
      moderate = !x$passed & x$tier %in% "moderate",
      moderate_z = !x$passed & x$moderate_z %in% TRUE,
      indicative = !x$passed & x$tier %in% "indicative"
    )
  )
  x$breadth[is.na(x$breadth)] <- "-"
  x$signal[is.na(x$signal)] <- "-"
  groups <- split(seq_len(nrow(x)), list(x$learner, x$kind, x$band, x$breadth, x$signal), drop = TRUE)
  rates <- do.call(rbind, lapply(names(reach), function(count) {
    do.call(rbind, lapply(names(reach[[count]]), function(tier) {
      do.call(rbind, lapply(groups, function(i) {
        k <- sum(reach[[count]][[tier]][i])
        interval <- atlas_calibration_wilson(k, length(i))
        data.frame(count = count, tier = tier, learner = x$learner[i[[1]]], kind = x$kind[i[[1]]],
                   band = x$band[i[[1]]], breadth = x$breadth[i[[1]]], signal = x$signal[i[[1]]],
                   species = length(i), passed = k, rate = k / length(i), low = interval[[1]],
                   high = interval[[2]], stringsAsFactors = FALSE)
      }))
    }))
  }))
  rownames(rates) <- NULL
  habitat <- x[x$kind == "habitat" & is.finite(x$truth_rho), , drop = FALSE]
  rho <- if (nrow(habitat)) {
    groups <- split(habitat$truth_rho, list(habitat$learner, habitat$tier), drop = TRUE)
    do.call(rbind, lapply(names(groups), function(g) {
      parts <- strsplit(g, ".", fixed = TRUE)[[1]]
      data.frame(learner = parts[[1]], tier = parts[[2]], species = length(groups[[g]]),
                 median_rho = stats::median(groups[[g]]), stringsAsFactors = FALSE)
    }))
  } else data.frame()
  list(rates = rates, rho = rho)
}

#' C1 for one learner by band (prereg amendment, 2026-10-25): when H1a holds
#' as registered, the registered decision for every band; otherwise C1 is
#' supported in exactly the bands where H1a holds in the band (its shift
#' false-pass Wilson upper bound at most 5%) and the band's scatter lower
#' bound is above 20%, and only if H1e holds over those bands' habitat
#' species. Every other band is reported as failing, never dropped.
atlas_calibration_c1_bands <- function(long, learner, tests, reps = ATLAS_CALIBRATION_READ_REPS,
                                       seed = ATLAS_CALIBRATION_READ_SEED) {
  bands <- atlas_calibration_band_levels("full")
  if (isTRUE(tests$h1a$holds)) {
    supported <- isTRUE(tests$h1b$holds) && isTRUE(tests$h1e$holds)
    return(list(mode = "registered", supported = if (supported) bands else character(),
                failing = if (supported) character() else bands, h1e = NULL))
  }
  band_ok <- vapply(seq_along(bands), function(i) {
    shift <- tests$h1a$by_band[[i]]
    scatter <- tests$h1b$by_band[[i]]
    shift$species > 0 && isTRUE(shift$high <= ATLAS_CALIBRATION_FALSE_PASS_MAX) &&
      scatter$species > 0 && isTRUE(scatter$low > ATLAS_CALIBRATION_SCATTER_MIN)
  }, TRUE)
  candidates <- bands[band_ok]
  h1e <- if (length(candidates)) {
    atlas_calibration_h1e(long[long$band %in% candidates, , drop = FALSE], learner, reps = reps, seed = seed)
  }
  supported <- if (isTRUE(h1e$holds)) candidates else character()
  list(mode = "by band", supported = supported, failing = setdiff(bands, supported), h1e = h1e)
}

#' Best-effort shifted nulls (R/nulls.R keeps the least bad draw when all 200
#' are rejected), by learner and band: their share of the shifted nulls
#' drawn, and the share of species with any (prereg amendment, 2026-10-25).
#' Reported only; no verdict depends on it.
atlas_calibration_best_effort <- function(rows) {
  tests <- do.call(rbind, lapply(Filter(function(r) identical(r$status, "scored"), rows), function(r) {
    do.call(rbind, lapply(r$arms, function(a) {
      n <- a$nulls$shift
      if (is.null(n) || is.null(n$verdict)) return(NULL)
      data.frame(learner = sub(":.*$", "", a$arm), band = r$band,
                 best_effort = as.integer(n$best_effort %||% 0L), drawn = as.integer(n$drawn %||% NA),
                 stringsAsFactors = FALSE)
    }))
  }))
  if (is.null(tests)) return(data.frame())
  groups <- split(tests, list(tests$learner, tests$band), drop = TRUE)
  out <- do.call(rbind, lapply(groups, function(x) {
    data.frame(learner = x$learner[[1]], band = x$band[[1]], species = nrow(x),
               nulls_drawn = sum(x$drawn, na.rm = TRUE), best_effort = sum(x$best_effort),
               share_of_nulls = sum(x$best_effort) / sum(x$drawn, na.rm = TRUE),
               share_of_species = mean(x$best_effort > 0), stringsAsFactors = FALSE)
  }))
  rownames(out) <- NULL
  out
}

#' Nulls drawn per species and test, by learner, design and kind (the cost
#' of a test, reported).
atlas_calibration_drawn <- function(long) {
  if (!nrow(long)) return(data.frame())
  groups <- split(long$drawn, list(long$learner, long$design, long$kind), drop = TRUE)
  out <- do.call(rbind, lapply(names(groups), function(g) {
    parts <- strsplit(g, ".", fixed = TRUE)[[1]]
    d <- groups[[g]]
    data.frame(learner = parts[[1]], design = parts[[2]], kind = parts[[3]], tests = length(d),
               mean_drawn = mean(d, na.rm = TRUE), median_drawn = stats::median(d, na.rm = TRUE),
               stringsAsFactors = FALSE)
  }))
  rownames(out) <- NULL
  out
}

#' What the rows hold before any test: species by status, learners and null
#' designs that errored (and so have no verdict), and how each cell filled.
atlas_calibration_health <- function(rows) {
  status <- vapply(rows, function(r) as.character(r$status %||% "unknown"), "")
  arms <- do.call(c, lapply(Filter(function(r) identical(r$status, "scored"), rows), function(r) r$arms))
  arm_errors <- sum(vapply(arms, function(a) !is.null(a$error), TRUE))
  null_errors <- sum(vapply(arms, function(a) {
    sum(vapply(a$nulls %||% list(), function(n) is.null(n$verdict), TRUE))
  }, 0))
  list(species = length(rows), by_status = as.list(table(status)), arm_errors = arm_errors,
       null_errors = null_errors, fill = atlas_calibration_fill(rows))
}

#' Read the study: every pre-registered test, the C1 decision, the ensembles'
#' secondary results, the map tiers, and the nulls drawn. rows are the
#' pooled shards' species rows.
atlas_calibration_read <- function(rows, reps = ATLAS_CALIBRATION_READ_REPS, seed = ATLAS_CALIBRATION_READ_SEED) {
  long <- atlas_calibration_long(rows)
  learner_tests <- function(learner) {
    cf <- atlas_calibration_h1cf(long, learner)
    out <- list(h1a = atlas_calibration_h1a(long, learner), h1b = atlas_calibration_h1b(long, learner),
                h1c = cf$h1c, h1f = cf$h1f, power_model = cf$model, power_curve = cf$curve,
                power = atlas_calibration_power_table(long, learner),
                h1e = atlas_calibration_h1e(long, learner, reps = reps, seed = seed))
    # H1d is about the full models' narrow habitats; ensembles have no breadth.
    if (learner != "esm") out$h1d <- atlas_calibration_h1d(long, learner)
    out
  }
  primary <- stats::setNames(lapply(ATLAS_CALIBRATION_PRIMARY, learner_tests), ATLAS_CALIBRATION_PRIMARY)
  secondary <- stats::setNames(lapply(ATLAS_CALIBRATION_SECONDARY, function(l) {
    # The same criteria by band (secondary): H1a, H1b and H1e, and the power
    # the ensembles have, by strength (H1f, its curve, and power by band).
    t <- learner_tests(l)
    t[c("h1a", "h1b", "h1e", "h1f", "power_model", "power_curve", "power")]
  }), ATLAS_CALIBRATION_SECONDARY)
  holds <- vapply(primary, function(t) isTRUE(t$h1a$holds) && isTRUE(t$h1b$holds) && isTRUE(t$h1e$holds), TRUE)
  list(
    health = atlas_calibration_health(rows),
    c1 = list(supported_as_registered = all(holds), by_learner = as.list(holds),
              by_band = stats::setNames(lapply(ATLAS_CALIBRATION_PRIMARY, function(l) {
                atlas_calibration_c1_bands(long, l, primary[[l]], reps = reps, seed = seed)
              }), ATLAS_CALIBRATION_PRIMARY)),
    learners = primary,
    secondary = secondary,
    tiers = atlas_calibration_tiers(long),
    drawn = atlas_calibration_drawn(long),
    best_effort = atlas_calibration_best_effort(rows),
    summary = atlas_calibration_summary(rows),
    settings = list(reps = reps, seed = seed, false_pass_max = ATLAS_CALIBRATION_FALSE_PASS_MAX,
                    scatter_min = ATLAS_CALIBRATION_SCATTER_MIN, alpha = ATLAS_CALIBRATION_ALPHA)
  )
}

#' The shards of one calibration run read together. paths are the shards'
#' results files: they must share seed, nulls, stop rule, designs and
#' redraws, come from one split into n shards with every shard 1..n there
#' once, and hold no species twice. complete when they hold `expected`
#' species (the pre-registered layout's 2,840).
atlas_calibration_pool <- function(paths, expected = nrow(atlas_calibration_layout())) {
  results <- lapply(paths, function(p) jsonlite::fromJSON(p, simplifyVector = FALSE))
  key <- function(r) {
    s <- r$settings
    paste(s$seed, s$nulls, s$stop_after, paste(unlist(s$designs), collapse = ","), s$redraws)
  }
  if (length(unique(vapply(results, key, ""))) != 1L) {
    stop("the results files are not shards of one calibration run (seed, nulls, stop rule, designs or redraws differ)",
         call. = FALSE)
  }
  shards <- vapply(results, function(r) as.character(r$settings$shard %||% "1/1"), "")
  if (anyDuplicated(shards)) stop("a shard appears twice: ", paste(shards[duplicated(shards)], collapse = ", "),
                                  call. = FALSE)
  splits <- unique(sub("^.*/", "", shards))
  if (length(splits) != 1L) {
    stop("the shards come from different splits (", paste(sort(shards), collapse = ", "), ")", call. = FALSE)
  }
  rows <- do.call(c, lapply(results, function(r) r$taxa))
  names <- vapply(rows, function(r) as.character(r$taxon %||% NA), "")
  if (anyDuplicated(names)) stop("a species appears in two shards: ", names[duplicated(names)][[1]], call. = FALSE)
  every_shard <- setequal(as.integer(sub("/.*$", "", shards)), seq_len(as.integer(splits)))
  list(shards = sort(shards), species = length(rows), expected = expected,
       complete = every_shard && length(rows) == expected, rows = rows)
}

#' A study job's calibration shards, read from the store: every results file
#' under prefix (study/<id>/) is fetched and the shards pooled.
atlas_calibration_pool_from <- function(store, prefix, expected = nrow(atlas_calibration_layout())) {
  prefix <- atlas_study_check_key(paste0(sub("/*$", "/", as.character(prefix))))
  keys <- store$list(prefix)
  keys <- keys[grepl("/virtual-e1-[^/]*[.]json$", keys)]
  if (!length(keys)) stop("no calibration results under ", prefix, call. = FALSE)
  dir <- tempfile("calibration-pool-")
  dir.create(dir)
  paths <- vapply(seq_along(keys), function(i) {
    path <- file.path(dir, paste0(i, "-", basename(keys[[i]])))
    store$get(keys[[i]], path)
    path
  }, "")
  atlas_calibration_pool(unname(paths), expected = expected)
}

#' The headline of a reading, one line per test and learner.
atlas_calibration_report <- function(read) {
  pct <- function(x) if (is.finite(x)) sprintf("%.1f%%", 100 * x) else "NA"
  num <- function(x, d = 3) if (is.finite(x)) formatC(x, digits = d, format = "g") else "NA"
  yes <- function(x) if (isTRUE(x)) "holds" else "does not hold"
  lines <- character()
  for (l in names(read$learners)) {
    t <- read$learners[[l]]
    lines <- c(lines,
      sprintf("%s H1a: shift false pass %s [%s, %s] of %d; %s", l, pct(t$h1a$rate), pct(t$h1a$low),
              pct(t$h1a$high), t$h1a$species, yes(t$h1a$holds)),
      sprintf("%s H1b: scatter false pass %s [%s, %s] of %d; trend p %s; %s", l, pct(t$h1b$rate),
              pct(t$h1b$low), pct(t$h1b$high), t$h1b$species, num(t$h1b$trend_p), yes(t$h1b$holds)),
      sprintf("%s H1c: breadth %s, p %s (%s); %s", l, num(t$h1c$estimate), num(t$h1c$p_two_sided),
              t$h1c$direction, yes(t$h1c$holds)),
      sprintf("%s H1d: narrow-habitat trend p %s; %s", l, num(t$h1d$trend_p), yes(t$h1d$holds)),
      sprintf("%s H1f: strong vs weak %s, one-sided p %s; %s", l, num(t$h1f$estimate), num(t$h1f$p_greater),
              yes(t$h1f$holds)),
      sprintf("%s H1e: median rho %s passed vs %s rest, difference %s [%s, %s], p %s; %s", l,
              num(t$h1e$median_passed), num(t$h1e$median_rest), num(t$h1e$difference), num(t$h1e$low),
              num(t$h1e$high), num(t$h1e$p), yes(t$h1e$holds)))
  }
  for (l in names(read$c1$by_band)) {
    b <- read$c1$by_band[[l]]
    lines <- c(lines, sprintf("%s C1 (%s): supported in %s; failing in %s", l, b$mode,
                              if (length(b$supported)) paste(b$supported, collapse = ", ") else "no band",
                              if (length(b$failing)) paste(b$failing, collapse = ", ") else "no band"))
  }
  if (any(vapply(read$c1$by_band, function(b) identical(b$mode, "by band"), TRUE))) {
    lines <- c(lines, paste("Band decisions are uncorrected for testing 5 bands per learner",
                            "(prereg amendment, 2026-10-25): each band's bound is from its own count."))
  }
  bands <- function(b) if (length(b$supported)) paste(b$supported, collapse = ", ") else "no band"
  c(lines,
    sprintf("C1 as registered: %s", if (isTRUE(read$c1$supported_as_registered)) "supported" else "not supported"),
    sprintf("C1 by band (amendment 2026-10-25): %s",
            paste(vapply(names(read$c1$by_band), function(l) {
              sprintf("%s %s (%s)", l, bands(read$c1$by_band[[l]]), read$c1$by_band[[l]]$mode)
            }, ""), collapse = "; ")))
}
