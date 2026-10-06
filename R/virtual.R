# Virtual species: fungi whose habitat is written down before they are
# collected, so a model can be judged on whether it finds that habitat.
#
# Blocked AUC and the Boyce index score a model against held-out detections,
# and held-out detections carry the same sampling bias as the training ones:
# both lean towards the places people collect most. A model that learns where
# people collect can therefore score well on them. Telling a model that finds
# habitat from one that finds effort needs the habitat itself, which for a
# real fungus nobody knows.
#
# So a virtual species is given a habitat, a response to two or three real
# predictors read from the real layers, and is then collected the way
# MycoMap's records were. At every real survey site, each of the site's real
# records is the virtual species with a chance proportional to the habitat
# there, so a site worked a hundred times has a hundred chances. The records
# drawn are relabelled with the virtual species' name, and it goes through
# exactly the training table, folds and fits a real taxon does.
#
# Each model is then scored two ways: as production scores it (blocked AUC
# and Boyce on held-out detections) and against the truth (rank correlation
# of its map with the true habitat over cells of the accessible area). Where
# the two disagree about which model is better, the blocked scores are being
# fooled.
#
# Two kinds of species:
#   habitat    detections follow a habitat; the map should find it
#   geography  detections follow distance from one or two centres and ignore
#              the environment. Any map of one shows only the clustering, so
#              passing the null test is a false pass.
#
# Nothing here writes a model or touches a real taxon. It writes one results
# file under data/virtual-studies/.

ATLAS_VIRTUAL_PREFIX <- "virtual"

# Predictors a habitat is drawn from: ones a fungus plausibly answers to,
# across layers. Climate and soil get a bell-shaped response around an
# optimum; shares of cover and host trees a rising one. A habitat always has
# one climate driver.
ATLAS_VIRTUAL_CLIMATE <- c("bio1", "bio5", "bio6", "bio12", "bio15")
ATLAS_VIRTUAL_BELL <- c(ATLAS_VIRTUAL_CLIMATE, "soil_phh2o", "soil_soc", "elevation")
ATLAS_VIRTUAL_RISING <- c("cover_trees", "forest_needleleaf", "forest_broadleaf",
                          "host_quercus", "host_pinus", "host_populus")

# Detection sites a species is collected at, in expectation: across the
# bands production maps.
ATLAS_VIRTUAL_TARGETS <- c(25, 40, 70, 120, 200)

# The arms every species is fitted under. Maxent's four ways with effort
# (ATLAS_EFFORT_MODES), the detection model (R/detection.R) and the forest
# as production fits it. "maxnet:none" is production Maxent and the baseline.
ATLAS_VIRTUAL_ARMS <- c("maxnet:none", "maxnet:covariate", "maxnet:weights",
                        "maxnet:offset", "detection", "rf")
ATLAS_VIRTUAL_BASELINE <- "maxnet:none"

# Cells of the accessible area a map is compared with the truth on.
ATLAS_VIRTUAL_TRUTH_CELLS <- 50000

#' A virtual species' name: virtual-<kind>-<index>.
atlas_virtual_name <- function(kind, index) {
  sprintf("%s-%s-%03d", ATLAS_VIRTUAL_PREFIX, kind, as.integer(index))
}

#' The kind and index a virtual species' name carries.
atlas_virtual_parse <- function(name) {
  parts <- strsplit(as.character(name), "-", fixed = TRUE)[[1]]
  if (length(parts) != 3L || parts[[1]] != ATLAS_VIRTUAL_PREFIX ||
      !parts[[2]] %in% c("habitat", "geography") || is.na(suppressWarnings(as.integer(parts[[3]])))) {
    stop("not a virtual species name: ", name, call. = FALSE)
  }
  list(kind = parts[[2]], index = as.integer(parts[[3]]))
}

#' A seed for one virtual species of one study, as a fingerprint, so the
#' training table draws its background exactly as it would for a real taxon.
atlas_virtual_fingerprint <- function(name, seed = 1L) {
  key <- paste(name, seed)
  code <- sum(utf8ToInt(key) * seq_along(utf8ToInt(key))) * 7919 + as.integer(seed)
  sprintf("%07x", as.integer(code %% 268435399))
}

#' A bell-shaped response, 1 at the optimum.
atlas_virtual_bell <- function(value, optimum, width) {
  exp(-((value - optimum)^2) / (2 * width^2))
}

#' A rising response, 0.5 at the centre.
atlas_virtual_rising <- function(value, centre, scale) {
  stats::plogis((value - centre) / scale)
}

#' Write down a virtual species: its kind, how many detection sites it is
#' collected at in expectation, and its habitat.
#'
#' env holds the predictors at every survey site, and sites their centres and
#' records; a habitat's optimum is drawn from the conditions where people
#' actually collect, so the species can be found at all. A geography
#' species' centres are drawn among sites in proportion to their records.
atlas_virtual_spec <- function(kind, seed, env, sites) {
  set.seed(seed)
  target <- sample(ATLAS_VIRTUAL_TARGETS, 1L)
  spec <- list(kind = kind, target = target, seed = seed)
  if (identical(kind, "geography")) {
    n <- sample(1:2, 1L)
    picked <- sample.int(nrow(sites), n, prob = sites$records)
    spec$centres <- lapply(picked, function(i) {
      list(x = sites$x[[i]], y = sites$y[[i]], radius_km = round(stats::runif(1, 150, 400)))
    })
    return(spec)
  }
  climate <- intersect(ATLAS_VIRTUAL_CLIMATE, names(env))
  others <- setdiff(intersect(c(ATLAS_VIRTUAL_BELL, ATLAS_VIRTUAL_RISING), names(env)), climate)
  if (!length(climate)) {
    stop("no climate predictor to build a habitat on", call. = FALSE)
  }
  extra <- min(length(others), sample(1:2, 1L))
  drivers <- c(climate[sample.int(length(climate), 1L)],
               others[sample.int(length(others), extra)])
  spec$responses <- lapply(drivers, function(v) {
    values <- env[[v]][is.finite(env[[v]])]
    spread <- stats::sd(values)
    if (v %in% ATLAS_VIRTUAL_RISING) {
      list(predictor = v, shape = "rising",
           centre = unname(stats::quantile(values, stats::runif(1, 0.3, 0.8))),
           scale = spread * stats::runif(1, 0.1, 0.4))
    } else {
      list(predictor = v, shape = "bell",
           optimum = unname(stats::quantile(values, stats::runif(1, 0.1, 0.9))),
           width = spread * stats::runif(1, 0.3, 1))
    }
  })
  spec
}

#' The true habitat, from 0 to 1, wherever data has the predictors (and, for
#' a geography species, x and y). NA where a predictor is missing.
atlas_virtual_habitat <- function(spec, data) {
  if (identical(spec$kind, "geography")) {
    near <- vapply(spec$centres, function(centre) {
      d <- sqrt((data$x - centre$x)^2 + (data$y - centre$y)^2) / 1000
      exp(-(d / centre$radius_km)^2)
    }, numeric(nrow(data)))
    return(if (is.matrix(near)) apply(near, 1, max) else max(near))
  }
  parts <- vapply(spec$responses, function(r) {
    value <- data[[r$predictor]]
    if (identical(r$shape, "rising")) {
      atlas_virtual_rising(value, r$centre, r$scale)
    } else {
      atlas_virtual_bell(value, r$optimum, r$width)
    }
  }, numeric(nrow(data)))
  if (is.matrix(parts)) apply(parts, 1, prod) else prod(parts)
}

#' Collect a virtual species: at each site, how many of its records are it.
#'
#' Each record at a site is the species with chance rate * habitat, and rate
#' is set so the expected number of sites with at least one is target. A site
#' with no habitat (or no data) yields nothing. The rate is kept as
#' attr(, "rate").
atlas_virtual_collect <- function(habitat, records, target, seed = 1L) {
  habitat[!is.finite(habitat)] <- 0
  if (!any(habitat > 0)) {
    stop("the habitat is empty at every survey site", call. = FALSE)
  }
  expected <- function(rate) sum(1 - (1 - pmin(1, rate * habitat))^records)
  ceiling_rate <- 1 / max(habitat)
  rate <- if (expected(ceiling_rate) <= target) {
    ceiling_rate
  } else {
    exp(stats::uniroot(function(r) expected(exp(r)) - target,
                       c(log(1e-12), log(ceiling_rate)), tol = 1e-6)$root)
  }
  set.seed(seed)
  own <- stats::rbinom(length(records), records, pmin(1, rate * habitat))
  attr(own, "rate") <- rate
  own
}

#' The pull's points with a virtual species' records relabelled.
#'
#' own[i] of site i's records take the name; rows_by_site[[i]] lists site
#' i's rows. Sites and their records are untouched, so effort is exactly the
#' real effort and the training table treats the species like any taxon.
atlas_virtual_points <- function(points, own, name, rows_by_site, seed = 1L) {
  set.seed(seed)
  chosen <- unlist(lapply(which(own > 0L), function(i) {
    rows <- rows_by_site[[i]]
    rows[sample.int(length(rows), own[[i]])]
  }), use.names = FALSE)
  points$scientific_name[chosen] <- name
  points
}

#' What every virtual species of a run shares: the sites, their predictors
#' and which rows belong to each. Built once per R process.
atlas_virtual_base <- function(points, stack) {
  key <- list(nrow(points), sum(as.numeric(points$cell)), sum(points$x), names(stack))
  cached <- get0(".atlas_virtual_base", envir = globalenv(), inherits = FALSE)
  if (!is.null(cached) && identical(cached$key, key)) {
    return(cached)
  }
  points <- atlas_ensure_sites(points)
  sites <- attr(points, "sites")
  env <- terra::extract(stack, as.matrix(sites[, c("x", "y")]))
  env <- env[, setdiff(names(env), "ID"), drop = FALSE]
  base <- list(
    key = key, points = points, sites = sites, env = env,
    rows_by_site = split(seq_len(nrow(points)), factor(points$site, levels = sites$site))
  )
  assign(".atlas_virtual_base", base, envir = globalenv())
  base
}

#' A sample of the accessible area's cells with their predictors, x and y:
#' where a map is compared with the truth.
atlas_virtual_cells <- function(stack, area, n = ATLAS_VIRTUAL_TRUTH_CELLS, seed = 1L) {
  window <- terra::mask(terra::crop(stack[[1]], terra::ext(area)), area)
  inside <- terra::cells(window)
  if (!length(inside)) {
    stop("the accessible area holds no cells with data", call. = FALSE)
  }
  set.seed(seed)
  if (length(inside) > n) inside <- sort(inside[sample.int(length(inside), n)])
  xy <- terra::xyFromCell(window, inside)
  values <- terra::extract(stack, xy)
  values <- values[, setdiff(names(values), "ID"), drop = FALSE]
  out <- data.frame(x = xy[, 1], y = xy[, 2], values)
  out[stats::complete.cases(out), , drop = FALSE]
}

#' How far a map ranks ground as the truth does: Spearman's rank
#' correlation over the cells, and the share of the truly best tenth that
#' the map also puts in its best tenth.
atlas_virtual_truth_scores <- function(predicted, truth) {
  ok <- is.finite(predicted) & is.finite(truth)
  if (sum(ok) < 10L || stats::sd(predicted[ok]) == 0) {
    return(list(truth_rho = NA_real_, truth_top = NA_real_))
  }
  p <- predicted[ok]
  t <- truth[ok]
  top_true <- t >= stats::quantile(t, 0.9)
  top_map <- p >= stats::quantile(p, 0.9)
  list(
    truth_rho = suppressWarnings(stats::cor(p, t, method = "spearman")),
    truth_top = sum(top_true & top_map) / sum(top_true)
  )
}

#' How an arm is fitted and scored. Maxent and the detection model get the
#' predictors production would give Maxent (keep, already chosen); the
#' forest takes every predictor and effort, as production fits it.
atlas_virtual_learner <- function(arm, seed = 1L) {
  if (startsWith(arm, "maxnet:")) {
    mode <- atlas_effort_mode(sub("^maxnet:", "", arm))
    return(list(
      columns = "pruned",
      fit = function(train) atlas_fit_maxnet(train, effort_mode = mode),
      score = atlas_suitability
    ))
  }
  switch(
    arm,
    detection = list(columns = "pruned", fit = function(train) atlas_fit_detection(train),
                     score = atlas_detection_suitability),
    rf = list(columns = "all",
              fit = function(train) atlas_fit_rf(train, seed = seed, num_trees = ATLAS_RF_TUNE_TREES),
              score = atlas_rf_suitability),
    stop("unknown arm '", arm, "'", call. = FALSE)
  )
}

#' Make, collect, fit and score one virtual species under every arm.
#'
#' Every arm shares the species' training table, folds and effort level, so
#' the comparison is paired. With nulls > 0, production Maxent also runs its
#' null test, and the result says whether the species would have passed.
atlas_virtual_taxon <- function(name, fingerprint, points, stack,
                                arms = ATLAS_VIRTUAL_ARMS, grid = "draft",
                                n_background = 10000, buffer_km = 500, folds = 5,
                                block_km = "auto", correlation = 0.7,
                                min_blocks = ATLAS_MIN_BLOCKS, nulls = 0L,
                                null_designs = "scatter", stop_after = NULL,
                                truth_cells = ATLAS_VIRTUAL_TRUTH_CELLS) {
  started <- Sys.time()
  parsed <- atlas_virtual_parse(name)
  seed <- atlas_seed_from_fingerprint(fingerprint)
  stack <- stack %||% atlas_predictor_stack(grid)
  base <- atlas_virtual_base(points, stack)
  spec <- atlas_virtual_spec(parsed$kind, seed, base$env, base$sites)
  habitat <- atlas_virtual_habitat(spec, data.frame(base$sites[, c("x", "y")], base$env))
  own <- atlas_virtual_collect(habitat, base$sites$records, spec$target, seed = seed + 1L)
  relabelled <- atlas_virtual_points(base$points, own, name, base$rows_by_site, seed = seed + 2L)

  training <- atlas_training_table(name, relabelled, n_background = n_background,
                                   buffer_km = buffer_km, fingerprint = fingerprint)
  training <- atlas_add_predictors(training, grid, stack = stack)
  presences <- sum(training$presence == 1L)
  row <- list(taxon = name, kind = parsed$kind, presences = presences,
              target = spec$target, band = atlas_presence_band(presences),
              rate = signif(attr(own, "rate"), 4), spec = spec)
  block <- if (atlas_block_is_auto(block_km)) {
    atlas_block_size(training, seed = seed)$block_km
  } else {
    as.numeric(block_km)
  }
  blocks <- atlas_presence_blocks(training, block)
  row$block_km <- block
  if (presences < 3L || blocks < min_blocks) {
    return(c(row, list(status = "refused", blocks = blocks,
                       seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1))))
  }
  fold_ids <- atlas_spatial_folds(training$x, training$y, k = folds, block_km = block,
                                  seed = seed, presence = training$presence)
  effort_at <- atlas_effort_level(training)

  keep <- atlas_choose_predictors(training, threshold = correlation,
                                  priority = atlas_predictor_priority(ATLAS_GUILD_UNKNOWN),
                                  host_share = atlas_host_allowance(ATLAS_GUILD_UNKNOWN))
  tables <- list(
    # keep ends with effort, which every arm's table carries for the null
    # models and the effort modes; Maxent leaves it out unless told otherwise.
    pruned = training[, c("presence", "cell", "x", "y", keep), drop = FALSE],
    all = training
  )
  occupied <- training[training$presence == 1L, , drop = FALSE]
  area <- atlas_accessible_area(occupied$x, occupied$y, buffer_km)
  cells <- atlas_virtual_cells(stack, area, n = truth_cells, seed = seed)
  truth <- atlas_virtual_habitat(spec, cells)
  # How strongly effort and habitat go together where this species was
  # looked for: the confounding the effort modes have to undo.
  row$effort_habitat_rho <- round(suppressWarnings(stats::cor(
    training[[ATLAS_EFFORT_COLUMN]],
    atlas_virtual_habitat(spec, training), method = "spearman")), 3)

  run_arm <- function(arm) {
    arm_started <- Sys.time()
    learner <- atlas_virtual_learner(arm, seed)
    table <- tables[[learner$columns]]
    scores <- atlas_cross_validate(table, fold_ids, fit = learner$fit, score = learner$score,
                                   effort_at = effort_at)
    model <- learner$fit(table)
    predicted <- atlas_score_at_effort(learner$score, effort_at)(model, cells)
    c(list(arm = arm,
           auc = round(mean(scores$auc, na.rm = TRUE), 4),
           boyce = round(atlas_pooled_boyce(scores), 4),
           folds_scored = sum(!is.na(scores$auc))),
      lapply(atlas_virtual_truth_scores(predicted, truth), round, 4),
      list(seconds = round(as.numeric(difftime(Sys.time(), arm_started, units = "secs")), 1)))
  }
  row$arms <- lapply(arms, function(arm) {
    tryCatch(run_arm(arm), error = function(e) {
      list(arm = arm, auc = NA_real_, boyce = NA_real_, truth_rho = NA_real_,
           truth_top = NA_real_, error = conditionMessage(e))
    })
  })

  if (nulls > 0L) {
    baseline <- Filter(function(a) identical(a$arm, ATLAS_VIRTUAL_BASELINE), row$arms)
    boyce <- if (length(baseline)) baseline[[1]]$boyce else NA_real_
    # Production's test exactly, unless a design or early stopping is asked
    # for; then the sequential test, which takes every design.
    row$nulls <- stats::setNames(lapply(null_designs, function(design) {
      tryCatch({
        null <- if (identical(design, "scatter") && is.null(stop_after)) {
          c(atlas_null_test(tables$pruned, fold_ids, atlas_algorithm("maxnet"),
                            reps = nulls, seed = seed), list(design = "scatter"))
        } else {
          atlas_null_test_sequential(tables$pruned, fold_ids, atlas_algorithm("maxnet"),
                                     reps = nulls, seed = seed, design = design,
                                     stop_after = stop_after %||% (nulls + 1L))
        }
        keep <- intersect(c("design", "reps", "observed_auc", "auc_mean", "auc_sd", "auc_p",
                            "stopped_early", "drawn", "fallbacks"), names(null))
        c(null[keep], list(boyce = boyce, skill = atlas_skill(null, boyce)))
      }, error = function(e) list(design = design, error = conditionMessage(e)))
    }), null_designs)
    row$null <- row$nulls[[1]]
  }
  c(row, list(status = "scored", blocks = blocks,
              seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)))
}

#' Paired comparison of every arm with the baseline, against the truth and
#' against blocked scores, by kind and band of detection sites.
#'
#' For each group and arm: species, mean truth correlation and top-tenth
#' overlap, mean blocked AUC and Boyce, the paired difference from the
#' baseline in truth correlation and in blocked AUC with standard errors, and
#' how often the arm was the best by the truth and the best by blocked AUC.
#' "agree" is the share of species where the arm blocked AUC ranks first is
#' also the arm the truth ranks first.
atlas_virtual_summary <- function(rows, baseline = ATLAS_VIRTUAL_BASELINE) {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  if (!length(scored)) return(data.frame())
  long <- do.call(rbind, lapply(scored, function(r) {
    do.call(rbind, lapply(r$arms, function(a) data.frame(
      taxon = r$taxon, kind = r$kind %||% NA_character_,
      band = r$band %||% atlas_presence_band(r$presences), arm = a$arm,
      auc = as.numeric(a$auc %||% NA), boyce = as.numeric(a$boyce %||% NA),
      rho = as.numeric(a$truth_rho %||% NA), top = as.numeric(a$truth_top %||% NA),
      stringsAsFactors = FALSE
    )))
  }))
  for (column in c("auc", "boyce", "rho", "top")) long[[column]][is.nan(long[[column]])] <- NA
  base <- long[long$arm == baseline, c("taxon", "auc", "rho"), drop = FALSE]
  names(base)[2:3] <- c("base_auc", "base_rho")
  long <- merge(long, base, by = "taxon", all.x = TRUE)
  best_of <- function(v) if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE)
  long$best_truth <- !is.na(long$rho) & long$rho == stats::ave(long$rho, long$taxon, FUN = best_of)
  long$best_auc <- !is.na(long$auc) & long$auc == stats::ave(long$auc, long$taxon, FUN = best_of)
  agree <- vapply(split(long, long$taxon), function(x) {
    by_auc <- x$arm[x$best_auc]
    by_truth <- x$arm[x$best_truth]
    length(by_auc) > 0 && length(by_truth) > 0 && any(by_auc %in% by_truth)
  }, logical(1))

  groups <- list(all = rep(TRUE, nrow(long)))
  for (k in unique(long$kind)) groups[[k]] <- long$kind == k
  for (b in unique(long$band[order(as.numeric(sub("[^0-9].*$", "", long$band)))])) {
    groups[[paste0("band ", b)]] <- long$band == b
  }
  mean_se <- function(d) {
    d <- d[is.finite(d)]
    c(if (length(d)) round(mean(d), 4) else NA_real_,
      if (length(d) > 1L) round(stats::sd(d) / sqrt(length(d)), 4) else NA_real_)
  }
  out <- do.call(rbind, lapply(names(groups), function(g) {
    in_group <- long[groups[[g]], , drop = FALSE]
    do.call(rbind, lapply(unique(long$arm), function(a) {
      x <- in_group[in_group$arm == a, , drop = FALSE]
      d_rho <- mean_se(x$rho - x$base_rho)
      d_auc <- mean_se(x$auc - x$base_auc)
      data.frame(
        group = g, arm = a, species = nrow(x),
        truth_rho = round(mean(x$rho, na.rm = TRUE), 3),
        truth_top = round(mean(x$top, na.rm = TRUE), 3),
        auc = round(mean(x$auc, na.rm = TRUE), 3),
        boyce = round(mean(x$boyce, na.rm = TRUE), 3),
        delta_rho = d_rho[[1]], delta_rho_se = d_rho[[2]],
        delta_auc = d_auc[[1]], delta_auc_se = d_auc[[2]],
        best_truth = round(mean(x$best_truth), 2),
        best_auc = round(mean(x$best_auc), 2),
        agree = round(mean(agree[unique(x$taxon)]), 2),
        stringsAsFactors = FALSE
      )
    }))
  }))
  rownames(out) <- NULL
  out
}

#' How often the null test passed, by design and kind: a pass is a false
#' pass for a geography species and a true pass for a habitat species.
#'
#' passed uses each map's own p at ATLAS_SKILL_ALPHA; fdr_passed uses
#' Benjamini-Hochberg q-values over every species tested with that design
#' (both kinds together, as a release would test every taxon), with the same
#' Boyce condition. nulls is the mean number of nulls drawn, and fallback the
#' share of shifted nulls that had to be scattered.
atlas_virtual_null_summary <- function(rows) {
  tested <- Filter(function(r) identical(r$status, "scored") && length(r$nulls %||% r$null), rows)
  if (!length(tested)) return(data.frame())
  long <- do.call(rbind, lapply(tested, function(r) {
    results <- r$nulls %||% list(scatter = r$null)
    do.call(rbind, lapply(results, function(n) {
      if (!is.character(n$skill)) return(NULL)
      data.frame(
        kind = r$kind, design = n$design %||% "scatter",
        p = as.numeric(n$auc_p %||% NA), boyce = as.numeric(n$boyce %||% NA),
        passed = identical(n$skill, "passed"),
        drawn = as.numeric(n$drawn %||% n$reps %||% NA),
        fallbacks = as.numeric(n$fallbacks %||% 0),
        stringsAsFactors = FALSE
      )
    }))
  }))
  if (is.null(long) || !nrow(long)) return(data.frame())
  long$q <- stats::ave(long$p, long$design, FUN = atlas_null_qvalues)
  long$fdr_passed <- is.finite(long$q) & long$q <= ATLAS_SKILL_ALPHA &
    is.finite(long$boyce) & long$boyce > 0
  out <- do.call(rbind, lapply(split(long, list(long$design, long$kind), drop = TRUE), function(x) {
    rate <- mean(x$passed)
    data.frame(
      design = x$design[[1]], kind = x$kind[[1]], species = nrow(x),
      passed = sum(x$passed), pass_rate = round(rate, 3),
      pass_se = round(sqrt(rate * (1 - rate) / nrow(x)), 3),
      fdr_passed = sum(x$fdr_passed), fdr_rate = round(mean(x$fdr_passed), 3),
      median_p = round(stats::median(x$p, na.rm = TRUE), 3),
      nulls = round(mean(x$drawn, na.rm = TRUE), 1),
      fallback = round(sum(x$fallbacks) / max(1, sum(x$drawn, na.rm = TRUE)), 3),
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

#' Run the virtual-species study: species of each kind, every arm.
atlas_virtual_study <- function(grid = "draft", species = 40, kinds = "habitat",
                                arms = ATLAS_VIRTUAL_ARMS, nulls = 0L,
                                null_designs = "scatter", stop_after = NULL, workers = 1L,
                                seed = 1L, n_background = 10000, buffer_km = 500,
                                folds = 5, block_km = "auto", correlation = 0.7,
                                quiet = FALSE, occurrences = NULL, points = NULL,
                                stack = NULL) {
  for (arm in arms) atlas_virtual_learner(arm)
  for (design in null_designs) atlas_null_design(design)
  if (is.null(points)) {
    occurrences <- occurrences %||% atlas_read_occurrences()
    points <- atlas_occurrence_points(occurrences, grid)
  }
  names <- unlist(lapply(kinds, function(kind) atlas_virtual_name(kind, seq_len(species))))
  sample <- data.frame(scientific_name = names, stringsAsFactors = FALSE)
  fingerprints <- stats::setNames(lapply(names, atlas_virtual_fingerprint, seed = seed), names)
  args <- list(arms = arms, grid = grid, n_background = n_background, buffer_km = buffer_km,
               folds = folds, block_km = block_km, correlation = correlation,
               nulls = as.integer(nulls), null_designs = null_designs,
               stop_after = if (!is.null(stop_after)) as.integer(stop_after))
  settings <- c(args, list(
    species = species, kinds = as.list(kinds), seed = seed, design = atlas_design(),
    truth_cells = ATLAS_VIRTUAL_TRUTH_CELLS, targets = ATLAS_VIRTUAL_TARGETS,
    drivers = list(climate = ATLAS_VIRTUAL_CLIMATE, bell = ATLAS_VIRTUAL_BELL,
                   rising = ATLAS_VIRTUAL_RISING)
  ))
  result <- atlas_run_study(
    kind = "virtual-studies", file_prefix = "virtual", taxon_fn = "atlas_virtual_taxon",
    sample = sample, fingerprints = fingerprints, args = args, settings = settings,
    baseline = ATLAS_VIRTUAL_BASELINE, grid = grid, workers = workers, points = points,
    stack = stack, quiet = quiet, summarise = atlas_virtual_summary,
    extra = function(rows) list(nulls = atlas_virtual_null_summary(rows)),
    opening = paste0(length(names), " virtual species (", paste(kinds, collapse = ", "),
                     ", ", species, " each), collected at the real survey sites with their ",
                     "real effort; arms: ", paste(arms, collapse = ", "),
                     if (nulls > 0L) paste0("; up to ", nulls, " nulls for production Maxent (",
                                            paste(null_designs, collapse = ", "),
                                            if (!is.null(stop_after)) paste0(", stopping after ",
                                                                             stop_after, " as good"),
                                            ")") else "")
  )
  nulls_table <- atlas_virtual_null_summary(result$taxa)
  if (!isTRUE(quiet) && nrow(nulls_table)) print(nulls_table, row.names = FALSE)
  invisible(c(result, list(nulls = nulls_table)))
}
