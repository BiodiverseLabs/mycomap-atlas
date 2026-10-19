# Calibrating the null test on virtual species (paper E1, pre-registered
# 2026-10-13 and amended before launch; docs/experiments on the paper branch).
#
# How often does each null design pass a species with no habitat signal
# (false pass), and one with a signal (power), by site band, habitat breadth,
# signal strength and learner? Virtual species (R/virtual.R) are collected at
# the real survey sites with the real effort, then fitted and null-tested as
# production fits and tests a taxon.
#
# The species come in cells, as pre-registered and amended before launch
# (sizes doubled, 2026-10-13; atlas_calibration_layout):
#
#   full models (Maxent and random forest), bands 20-29 .. 200+
#     habitat    2 breadths x 2 signal strengths x 60 per band   = 1,200
#     geography  1 or 2 centres x 80 per band                    =   800
#   small-model ensembles (ESM), bands 3-4, 5-9, 10-19
#     habitat    2 signal strengths x 80 per band                =   480
#     geography  120 per band                                    =   360
#
# A species belongs to the band of its realised detection sites. Its target
# is drawn uniformly inside the band; when the realised count lands outside
# (or the sites fall in too few blocks for its folds) it is drawn again from
# the next seed, at most ATLAS_CALIBRATION_REDRAWS times, and the draws are
# reported; a cell that cannot be filled is reported with its count, never
# padded. Each learner then gets its own blocked scores, its own
# map-to-truth correlation, and its own verdict under scattered and shifted
# nulls (99, stopping at 5), with production's pass rule (AUC p <= 0.05 and
# the learner's pooled Boyce above 0). Full-model species also get Maxent's
# three ways with effort (E14), without nulls.
#
# Learners are fitted at their untuned settings, as the pre-freeze study and
# the null test itself fit them. Nothing here writes a model or touches a
# real taxon.

ATLAS_CALIBRATION_FULL_BANDS <- list(c(20, 29), c(30, 49), c(50, 99), c(100, 199), c(200, Inf))
ATLAS_CALIBRATION_ESM_BANDS <- list(c(3, 4), c(5, 9), c(10, 19))
# The highest target drawn for the open top band.
ATLAS_CALIBRATION_TOP_TARGET <- 300
ATLAS_CALIBRATION_BREADTHS <- c(narrow = 0.5, wide = 2)
ATLAS_CALIBRATION_SIGNALS <- c("strong", "weak")
ATLAS_CALIBRATION_REDRAWS <- 20L
ATLAS_CALIBRATION_DESIGNS <- c("scatter", "shift")
ATLAS_CALIBRATION_NULLS <- 99L
ATLAS_CALIBRATION_STOP_AFTER <- 5L
ATLAS_CALIBRATION_EFFORT_ARMS <- c("maxnet:covariate", "maxnet:weights", "maxnet:offset")
# Habitat below this is "outside the habitat": a weak species' detections
# there are the flat half's doing. (A product of bells is never exactly 0.)
ATLAS_CALIBRATION_OUTSIDE_H <- 0.05

#' A band's label: "20-29", or "200+" for the open top band.
atlas_calibration_band_label <- function(band) {
  if (is.finite(band[[2]])) paste0(band[[1]], "-", band[[2]]) else paste0(band[[1]], "+")
}

#' The pre-registered cells, one row per species: its name, family (full or
#' esm), kind, band, breadth, signal and centres (NA where the cell leaves
#' it to the draw), and the cell it fills.
atlas_calibration_layout <- function(habitat_full = 60L, geography_full = 80L,
                                     habitat_esm = 80L, geography_esm = 120L) {
  rows <- list()
  add <- function(n, family, kind, band, breadth = NA_character_, signal = NA_character_,
                  centres = NA_integer_) {
    if (n < 1L) return(invisible())
    rows[[length(rows) + 1L]] <<- data.frame(
      family = family, kind = kind, band_lo = band[[1]], band_hi = band[[2]],
      band = atlas_calibration_band_label(band), breadth = breadth, signal = signal,
      centres = centres, stringsAsFactors = FALSE
    )[rep(1L, n), , drop = FALSE]
  }
  for (band in ATLAS_CALIBRATION_FULL_BANDS) {
    for (breadth in names(ATLAS_CALIBRATION_BREADTHS)) {
      for (signal in ATLAS_CALIBRATION_SIGNALS) add(habitat_full, "full", "habitat", band, breadth, signal)
    }
    for (centres in 1:2) add(geography_full, "full", "geography", band, centres = centres)
  }
  for (band in ATLAS_CALIBRATION_ESM_BANDS) {
    for (signal in ATLAS_CALIBRATION_SIGNALS) add(habitat_esm, "esm", "habitat", band, signal = signal)
    add(geography_esm, "esm", "geography", band)
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out$cell <- with(out, paste(family, kind, band,
                              ifelse(is.na(breadth), "-", breadth),
                              ifelse(is.na(signal), "-", signal),
                              ifelse(is.na(centres), "-", paste0(centres, "c")), sep = "/"))
  index <- stats::ave(seq_len(nrow(out)), out$kind, FUN = seq_along)
  out$name <- sprintf("%s-%s-%04d", ATLAS_VIRTUAL_PREFIX, out$kind, index)
  out
}

#' The learners a family is fitted with, and the folds it is scored on:
#' production's design for each (R/algorithms.R).
atlas_calibration_learners <- function(family) {
  if (identical(family, "esm")) "esm" else c("maxnet", "rf")
}

atlas_calibration_design <- function(family) {
  atlas_algorithm_design(atlas_algorithm(if (identical(family, "esm")) "esm" else "maxnet"))
}

#' The seed of a species' r-th draw.
atlas_calibration_draw_seed <- function(seed, draw) {
  as.integer((as.numeric(seed) + 7919 * draw) %% 2147483647)
}

#' A target inside a band, drawn from the draw's seed.
atlas_calibration_target <- function(band_lo, band_hi, seed) {
  hi <- if (is.finite(band_hi)) band_hi else ATLAS_CALIBRATION_TOP_TARGET
  set.seed(seed + 3L)
  as.integer(band_lo + sample.int(as.integer(hi - band_lo + 1L), 1L) - 1L)
}

#' The share of the accessible area's survey sites with true suitability at
#' or above 0.5, on the habitat's own scale (peak 1): realised breadth.
atlas_calibration_breadth <- function(habitat_at_sites, sites, area) {
  inside <- atlas_points_in_area(sites$x, sites$y, area)
  h <- habitat_at_sites[inside]
  h <- h[is.finite(h)]
  if (!length(h)) return(NA_real_)
  mean(h >= 0.5)
}

#' Draw a species of a cell until its realised detection sites land in the
#' cell's band and fall in enough blocks for its folds. Returns the training
#' table, folds, spec and what the draws took, or a refusal after the last.
atlas_calibration_draw <- function(cell, name, seed, base, stack, grid = "draft",
                                   n_background = 10000, buffer_km = 500,
                                   redraws = ATLAS_CALIBRATION_REDRAWS) {
  design <- atlas_calibration_design(cell$family)
  breadth <- if (is.na(cell$breadth)) 1 else ATLAS_CALIBRATION_BREADTHS[[cell$breadth]]
  signal <- if (is.na(cell$signal)) "strong" else cell$signal
  site_data <- data.frame(base$sites[, c("x", "y")], base$env)
  realised <- integer()
  for (draw in 0:redraws) {
    s <- atlas_calibration_draw_seed(seed, draw)
    target <- atlas_calibration_target(cell$band_lo, cell$band_hi, s)
    spec <- atlas_virtual_spec(cell$kind, s, base$env, base$sites, target = target,
                               breadth = breadth, centres = if (is.na(cell$centres)) NULL else cell$centres)
    habitat <- atlas_virtual_habitat(spec, site_data)
    own <- tryCatch(atlas_virtual_collect(habitat, base$sites$records, target, seed = s + 1L,
                                          signal = signal),
                    error = function(e) NULL)
    if (is.null(own) || !any(own > 0L)) {
      realised <- c(realised, 0L)
      next
    }
    relabelled <- atlas_virtual_points(base$points, own, name, base$rows_by_site, seed = s + 2L)
    training <- atlas_training_table(name, relabelled, n_background = n_background,
                                     buffer_km = buffer_km, fingerprint = sprintf("%07x", s %% 268435399L))
    training <- atlas_add_predictors(training, grid, stack = stack)
    presences <- sum(training$presence == 1L)
    realised <- c(realised, presences)
    if (presences < cell$band_lo || presences > cell$band_hi) next
    block_km <- if (atlas_block_is_auto(design$block_km)) {
      atlas_block_size(training, seed = s)$block_km
    } else {
      as.numeric(design$block_km)
    }
    if (atlas_presence_blocks(training, block_km) < design$min_blocks) next
    folds <- atlas_spatial_folds(training$x, training$y, k = design$folds, block_km = block_km,
                                 seed = s, presence = training$presence)
    detected <- own > 0L
    return(list(ok = TRUE, draws = draw + 1L, realised = realised, seed = s, spec = spec,
                training = training, folds = folds, block_km = block_km, habitat = habitat,
                own = own, rate = attr(own, "rate"),
                outside_share = mean(habitat[detected] < ATLAS_CALIBRATION_OUTSIDE_H, na.rm = TRUE)))
  }
  list(ok = FALSE, draws = redraws + 1L, realised = realised)
}

#' The table a learner is fitted on: Maxent its pruned predictors (and effort,
#' which it leaves out unless an effort arm asks), the forest every predictor
#' and effort, the ensemble the predictors it chooses. As production does,
#' with the unknown guild's order.
atlas_calibration_table <- function(training, learner, correlation = 0.7) {
  priority <- atlas_predictor_priority(ATLAS_GUILD_UNKNOWN)
  host_share <- atlas_host_allowance(ATLAS_GUILD_UNKNOWN)
  keep <- switch(
    learner,
    maxnet = atlas_choose_predictors(training, threshold = correlation, priority = priority,
                                     host_share = host_share),
    esm = atlas_algorithm("esm")$choose(training, correlation, priority, host_share),
    rf = NULL,
    stop("unknown learner '", learner, "'", call. = FALSE)
  )
  if (is.null(keep)) return(training)
  training[, c("presence", "cell", "x", "y", keep), drop = FALSE]
}

#' One learner (or effort arm) of a species: blocked scores, map-to-truth,
#' and, unless nulls is 0, its verdict under each null design.
atlas_calibration_learner <- function(arm, table, folds, seed, cells, truth, nulls,
                                      designs = ATLAS_CALIBRATION_DESIGNS,
                                      stop_after = ATLAS_CALIBRATION_STOP_AFTER) {
  started <- Sys.time()
  learner <- atlas_virtual_learner(arm, seed)
  effort_at <- atlas_effort_level(table)
  scores <- atlas_cross_validate(table, folds, fit = learner$fit, score = learner$score,
                                 effort_at = effort_at)
  boyce <- atlas_pooled_boyce(scores)
  model <- learner$fit(table)
  predicted <- atlas_score_at_effort(learner$score, effort_at)(model, cells)
  out <- c(list(arm = arm, auc = round(mean(scores$auc, na.rm = TRUE), 4),
                boyce = round(boyce, 4), folds_scored = sum(is.finite(scores$auc))),
           lapply(atlas_virtual_truth_scores(predicted, truth), round, 4))
  if (nulls > 0L) {
    algo <- atlas_algorithm(sub(":.*$", "", arm))
    out$nulls <- stats::setNames(lapply(designs, function(design) {
      tryCatch({
        null <- atlas_null_test_sequential(table, folds, algo, reps = nulls, seed = seed,
                                           design = design, stop_after = stop_after)
        # The null AUCs' mean and spread as well as p: the looser map tiers
        # (plan-map-tiers, E24) are scored on them as a secondary analysis.
        list(design = design, p = null$auc_p, observed_auc = null$observed_auc,
             auc_mean = null$auc_mean, auc_sd = null$auc_sd, observed_boyce = null$observed_boyce,
             drawn = null$drawn, reps = null$reps, stopped_early = null$stopped_early,
             best_effort = null$best_effort, far_share = null$far_share,
             verdict = atlas_skill(null, boyce))
      }, error = function(e) list(design = design, error = conditionMessage(e)))
    }), designs)
  }
  out$seconds <- round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  out
}

#' One species of the study.
atlas_calibration_taxon <- function(name, fingerprint, points, stack, cells, grid = "draft",
                                    n_background = 10000, buffer_km = 500, correlation = 0.7,
                                    nulls = ATLAS_CALIBRATION_NULLS,
                                    designs = ATLAS_CALIBRATION_DESIGNS,
                                    stop_after = ATLAS_CALIBRATION_STOP_AFTER,
                                    effort_arms = ATLAS_CALIBRATION_EFFORT_ARMS,
                                    redraws = ATLAS_CALIBRATION_REDRAWS,
                                    truth_cells = ATLAS_VIRTUAL_TRUTH_CELLS) {
  started <- Sys.time()
  seconds <- function() round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  cell <- cells[[name]]
  stack <- stack %||% atlas_predictor_stack(grid)
  base <- atlas_virtual_base(points, stack)
  drawn <- atlas_calibration_draw(cell, name, atlas_seed_from_fingerprint(fingerprint), base, stack,
                                  grid = grid, n_background = n_background, buffer_km = buffer_km,
                                  redraws = redraws)
  row <- list(taxon = name, family = cell$family, kind = cell$kind, cell = cell$cell,
              band = cell$band, breadth = cell$breadth, signal = cell$signal,
              centres = cell$centres, draws = drawn$draws, realised = as.list(drawn$realised))
  if (!isTRUE(drawn$ok)) {
    return(c(row, list(status = "unfilled", seconds = seconds())))
  }
  training <- drawn$training
  row$presences <- sum(training$presence == 1L)
  row$block_km <- drawn$block_km
  row$spec <- drawn$spec
  row$rate <- signif(drawn$rate, 4)
  row$outside_share <- round(drawn$outside_share, 4)
  occupied <- training[training$presence == 1L, , drop = FALSE]
  area <- atlas_accessible_area(occupied$x, occupied$y, buffer_km)
  if (identical(cell$kind, "habitat")) {
    row$realised_breadth <- round(atlas_calibration_breadth(drawn$habitat, base$sites, area), 4)
  }
  truth_at <- atlas_virtual_cells(stack, area, n = truth_cells, seed = drawn$seed)
  truth <- atlas_virtual_habitat(drawn$spec, truth_at)
  row$effort_habitat_rho <- round(suppressWarnings(stats::cor(
    training[[ATLAS_EFFORT_COLUMN]], atlas_virtual_habitat(drawn$spec, training), method = "spearman")), 3)

  run <- function(arm, learner, with_nulls) {
    tryCatch(
      atlas_calibration_learner(arm, atlas_calibration_table(training, learner, correlation),
                                drawn$folds, drawn$seed, truth_at, truth,
                                nulls = if (with_nulls) as.integer(nulls) else 0L,
                                designs = designs, stop_after = stop_after),
      error = function(e) list(arm = arm, error = conditionMessage(e))
    )
  }
  learners <- atlas_calibration_learners(cell$family)
  arms <- lapply(learners, function(l) run(if (l == "maxnet") "maxnet:none" else l, l, TRUE))
  if (identical(cell$family, "full")) {
    arms <- c(arms, lapply(effort_arms, function(a) run(a, "maxnet", FALSE)))
  }
  c(row, list(status = "scored", arms = arms, seconds = seconds()))
}

#' One row per species, learner and null design: what the pre-registered
#' tests read. passed is the learner's verdict; a pass of a geography species
#' is a false pass.
atlas_calibration_long <- function(rows) {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  out <- do.call(rbind, lapply(scored, function(r) {
    do.call(rbind, lapply(Filter(function(a) length(a$nulls), r$arms), function(a) {
      do.call(rbind, lapply(a$nulls, function(n) {
        if (is.null(n$verdict)) return(NULL)
        data.frame(
          taxon = r$taxon, family = r$family, kind = r$kind, band = r$band,
          breadth = r$breadth %||% NA_character_, signal = r$signal %||% NA_character_,
          centres = as.integer(r$centres %||% NA), presences = as.integer(r$presences),
          realised_breadth = as.numeric(r$realised_breadth %||% NA),
          learner = sub(":.*$", "", a$arm), design = n$design, p = as.numeric(n$p %||% NA),
          drawn = as.integer(n$drawn %||% NA), nulls = as.integer(n$reps %||% NA),
          auc = as.numeric(a$auc %||% NA),
          observed_auc = as.numeric(n$observed_auc %||% NA), null_mean = as.numeric(n$auc_mean %||% NA),
          null_sd = as.numeric(n$auc_sd %||% NA), boyce = as.numeric(a$boyce %||% NA),
          passed = identical(n$verdict, "passed"),
          truth_rho = as.numeric(a$truth_rho %||% NA), stringsAsFactors = FALSE
        )
      }))
    }))
  }))
  if (is.null(out)) {
    out <- data.frame(taxon = character(), family = character(), kind = character(),
                      band = character(), learner = character(), design = character(),
                      passed = logical(), stringsAsFactors = FALSE)
  } else {
    # The looser map tiers (E24) under each design's null test: a pass of a
    # geography species in a tier is a false pass for that tier. The signal
    # line reads the learner's held-out AUC; the shift rows are the headline.
    out$tier <- atlas_map_tier(out$p, out$nulls, out$auc, out$boyce, strong = out$passed)
    out$moderate_z <- atlas_map_tier_z(out$observed_auc, out$null_mean, out$null_sd, out$boyce, out$passed)
  }
  out
}

#' Pass rates with Wilson intervals by learner x design x kind x band (and,
#' for habitat species, breadth and signal): false pass for geography, power
#' for habitat. A check while it runs; the tests are read from the long rows.
atlas_calibration_summary <- function(rows, baseline = NULL) {
  long <- atlas_calibration_long(rows)
  if (!nrow(long)) return(data.frame())
  long$breadth[is.na(long$breadth)] <- "-"
  long$signal[is.na(long$signal)] <- "-"
  groups <- split(long, list(long$learner, long$design, long$kind, long$band, long$breadth,
                             long$signal), drop = TRUE)
  out <- do.call(rbind, lapply(groups, function(x) {
    k <- sum(x$passed)
    n <- nrow(x)
    interval <- atlas_tracker_wilson(k, n)
    data.frame(learner = x$learner[[1]], design = x$design[[1]], kind = x$kind[[1]],
               band = x$band[[1]], breadth = x$breadth[[1]], signal = x$signal[[1]],
               species = n, passed = k, rate = round(k / n, 3),
               low = round(interval[[1]], 3), high = round(interval[[2]], 3),
               stringsAsFactors = FALSE)
  }))
  rownames(out) <- NULL
  out[order(out$learner, out$design, out$kind, out$band), , drop = FALSE]
}

#' How each cell filled: species, scored, unfilled, and the draws they took.
atlas_calibration_fill <- function(rows) {
  if (!length(rows)) return(list())
  cells <- vapply(rows, function(r) as.character(r$cell %||% "?"), "")
  lapply(split(rows, cells), function(group) list(
    species = length(group),
    scored = sum(vapply(group, function(r) identical(r$status, "scored"), TRUE)),
    unfilled = sum(vapply(group, function(r) identical(r$status, "unfilled"), TRUE)),
    redraws = sum(vapply(group, function(r) as.integer(r$draws %||% 1L) - 1L, 0L))
  ))
}

# Planning figures, per fit at untuned settings on one core (seconds), and
# the nulls a test draws on average: about 99 when it passes, about 10 when
# five nulls soon match the map.
ATLAS_CALIBRATION_PLAN_FIT_SECONDS <- c(maxnet = 1.0, rf = 0.6, esm = 0.6)

#' Rough CPU-hours for a layout: every learner's folds, for the taxon and
#' every null drawn, under each design, plus the effort arms.
atlas_calibration_plan <- function(layout, seconds = ATLAS_CALIBRATION_PLAN_FIT_SECONDS) {
  per_species <- vapply(seq_len(nrow(layout)), function(i) {
    cell <- layout[i, ]
    design <- atlas_calibration_design(cell$family)
    # Scatter passes most species of either kind (E1b); shift passes few.
    drawn <- c(scatter = 99, shift = if (identical(cell$kind, "habitat")) 40 else 12)
    total <- 0
    for (learner in atlas_calibration_learners(cell$family)) {
      fits <- design$folds * (1 + sum(drawn + 1)) + design$folds + 1
      total <- total + fits * seconds[[learner]]
    }
    if (identical(cell$family, "full")) {
      total <- total + length(ATLAS_CALIBRATION_EFFORT_ARMS) * (design$folds + 1) * seconds[["maxnet"]]
    }
    total
  }, numeric(1))
  list(species = nrow(layout), by_family = as.list(table(paste(layout$family, layout$kind))),
       cpu_hours = round(sum(per_species) / 3600, 0))
}

#' Run the calibration study.
#'
#' points and stack are the frozen pull's points and the frozen layers.
#' shard "i/n" takes every n-th species from the i-th; plan_only prints the
#' work and stops. layout is atlas_calibration_layout() unless a smaller one
#' is given for a pilot.
atlas_calibration_study <- function(grid = "draft", layout = atlas_calibration_layout(),
                                    seed = 1L, shard = "1/1", workers = 1L, out = NULL,
                                    nulls = ATLAS_CALIBRATION_NULLS, n_background = 10000,
                                    buffer_km = 500, plan_only = FALSE, quiet = FALSE,
                                    occurrences = NULL, points = NULL, stack = NULL, store = NULL) {
  names <- atlas_study_shard(layout$name, shard)
  layout <- layout[layout$name %in% names, , drop = FALSE]
  plan <- atlas_calibration_plan(layout)
  if (isTRUE(plan_only)) {
    if (!isTRUE(quiet)) {
      message("null calibration (E1), shard ", shard, ": ", plan$species,
              " virtual species, about ", plan$cpu_hours, " CPU-hours")
      print(unlist(plan$by_family))
    }
    return(invisible(plan))
  }
  if (is.null(points)) {
    occurrences <- occurrences %||% atlas_read_occurrences()
    points <- atlas_occurrence_points(occurrences, grid)
  }
  out <- atlas_study_out(out, "virtual-studies", grid, paste0("e1-seed", seed, "-shard-", sub("/", "of", shard)))
  cells <- lapply(stats::setNames(seq_len(nrow(layout)), layout$name), function(i) as.list(layout[i, ]))
  fingerprints <- stats::setNames(lapply(layout$name, atlas_virtual_fingerprint, seed = seed), layout$name)
  args <- list(cells = cells, grid = grid, n_background = n_background, buffer_km = buffer_km,
               nulls = as.integer(nulls))
  settings <- list(seed = seed, shard = shard, nulls = nulls, stop_after = ATLAS_CALIBRATION_STOP_AFTER,
                   designs = ATLAS_CALIBRATION_DESIGNS, redraws = ATLAS_CALIBRATION_REDRAWS,
                   breadths = as.list(ATLAS_CALIBRATION_BREADTHS), top_target = ATLAS_CALIBRATION_TOP_TARGET,
                   outside_h = ATLAS_CALIBRATION_OUTSIDE_H, effort_arms = ATLAS_CALIBRATION_EFFORT_ARMS,
                   truth_cells = ATLAS_VIRTUAL_TRUTH_CELLS, design = atlas_design(),
                   drivers = list(climate = ATLAS_VIRTUAL_CLIMATE, bell = ATLAS_VIRTUAL_BELL,
                                  rising = ATLAS_VIRTUAL_RISING))
  result <- atlas_run_study(
    kind = "virtual-studies", file_prefix = out$prefix, taxon_fn = "atlas_calibration_taxon",
    sample = data.frame(scientific_name = layout$name, stringsAsFactors = FALSE),
    fingerprints = fingerprints, args = args, settings = settings, baseline = "maxnet:none",
    grid = grid, workers = workers, points = points, stack = stack, quiet = quiet,
    summarise = atlas_calibration_summary,
    extra = function(rows) list(fill = atlas_calibration_fill(rows), counts = atlas_study_counts(rows)),
    detail = function(arm) {
      verdicts <- vapply(arm$nulls %||% list(), function(n) paste0(n$design, "=", n$verdict %||% "error"), "")
      sprintf("%s:rho=%s%s", arm$arm, arm$truth_rho %||% NA,
              if (length(verdicts)) paste0("[", paste(verdicts, collapse = ","), "]") else "")
    },
    opening = paste0(nrow(layout), " virtual species (shard ", shard, ", seed ", seed,
                     "), collected at the real survey sites with their real effort; nulls ",
                     paste(ATLAS_CALIBRATION_DESIGNS, collapse = " and "), " x", nulls,
                     ", stopping at ", ATLAS_CALIBRATION_STOP_AFTER)
  )
  if (!is.null(out$key) && !is.null(store)) {
    files <- c(result$path, sub("[.]json$", ".log", result$path))
    atlas_study_publish(store, files[file.exists(files)], out$key, root = dirname(out$dir))
  }
  atlas_study_guard(result$taxa, "calibration study")
  invisible(result)
}
