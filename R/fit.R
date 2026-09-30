# Fitting, and judging the fit honestly.
#
# Every model learns from one row per survey site (R/sites.R): detected or
# not, the site's predictors, and its effort. Evaluation is deliberately not a
# random split. Fungal records are clustered — a foray produces thirty
# collections from one wood — so a random hold-out puts near-neighbours on
# both sides and reports a score that says only "this model can interpolate
# between two points 200 m apart". Folds are therefore whole spatial blocks,
# as wide as blockCV measures the taxon's detections to be autocorrelated.
#
# Three things keep the scores honest:
#
# - Settings are tuned inside the folds. Each held-out region is scored by a
#   model whose settings were chosen on inner spatial folds of the other
#   regions only, so the choice never sees the ground it is judged on.
# - Effort is held at one value whenever a model is scored or mapped, so a
#   score measures habitat, not how hard a place was worked.
# - Every model is compared with null models: the same number of sites drawn
#   at random from the surveyed sites, busier sites more often, fitted and
#   scored the same way. A map that cannot beat a fungus that is merely a
#   random handful of collections says nothing about habitat, and is marked so
#   (Raes & ter Steege 2007; Kass et al. 2021). "The same way" is meant
#   strictly: the taxon and its nulls are both fitted at the algorithm's
#   untuned settings for this test. Settings tuned on the real detections and
#   then handed to the nulls would favour the real model, and tuning every
#   null would cost twenty times the fit.
# - The Boyce index is computed once, on the held-out scores of every fold
#   together. A taxon with twenty sites leaves four detections in a fold, and
#   a rank correlation on four points is noise; the mean of five such numbers
#   is still noise.
#
# Two statistics are reported. AUC is familiar but, against other surveyed
# sites rather than true absences, it measures separation from where people
# looked, not from where the species is truly absent — it cannot reach 1 and
# its ceiling depends on how widespread the species is. The Boyce index asks
# the question that suits these data: do higher predictions really hold
# proportionally more detections?

# The predictor that carries sampling effort: log(records at the site).
ATLAS_EFFORT_COLUMN <- "effort"

# Inner folds for tuning, inside each outer training set.
ATLAS_INNER_FOLDS <- 3L
# Null models per taxon. With 19, beating every one is p = 0.05.
ATLAS_NULL_REPS <- 19L
# A map is shown as skilled when its AUC beats the nulls at this level and its
# Boyce index is above zero.
ATLAS_SKILL_ALPHA <- 0.05
# Fewest blocks that must hold a detection. With five folds, fewer blocks than
# that leaves a fold with nothing to score.
ATLAS_MIN_BLOCKS <- 5L

#' Columns of a training table that are predictors, rather than bookkeeping.
atlas_predictor_columns <- function(training) {
  setdiff(names(training), c("presence", "cell", "x", "y"))
}

#' Feature classes for an untuned Maxent fit. Hinge features need records to
#' support them.
atlas_feature_classes <- function(n_presence) {
  if (n_presence < 30) "lq" else "lqh"
}

#' Assign each row to a fold by spatial block, so a fold holds out a region.
#'
#' Given presence, blocks holding detections are dealt first, busiest first,
#' each to the fold with the fewest detections so far (ties at random), so a
#' fold is never left with nothing to score while another has two blocks of
#' them. The remaining blocks are dealt at random, each to the fold with the
#' fewest blocks. Without presence, blocks are dealt at random in equal
#' numbers. Either way the deal comes from the seed.
atlas_spatial_folds <- function(x, y, k = 5, block_km = 200, seed = 1L,
                                presence = NULL) {
  block <- atlas_block_labels(x, y, block_km)
  blocks <- unique(block)
  k <- max(2L, min(as.integer(k), length(blocks)))
  set.seed(seed)
  if (is.null(presence)) {
    return(sample(rep_len(seq_len(k), length(blocks)))[match(block, blocks)])
  }
  found <- as.integer(tapply(presence == 1L, factor(block, levels = blocks), sum))
  fold_of <- integer(length(blocks))
  detections <- numeric(k)
  sizes <- numeric(k)
  pick <- function(load) {
    lightest <- which(load == min(load))
    if (length(lightest) == 1L) lightest else sample(lightest, 1L)
  }
  jitter <- stats::runif(length(blocks))
  for (i in order(-found, jitter)) {
    fold <- if (found[i] > 0) pick(detections) else pick(sizes)
    fold_of[i] <- fold
    detections[fold] <- detections[fold] + found[i]
    sizes[fold] <- sizes[fold] + 1
  }
  fold_of[match(block, blocks)]
}

#' Fit Maxent to a training table.
#'
#' maxnet adds presences to the background itself, but checks every presence
#' against every background row to do it, which was 90% of a fit's time. A
#' site is either a detection or not, so presences are simply appended.
#'
#' A predictor that does not vary among the sites being fitted is left out.
#' The predictors are chosen on all of a taxon's sites, but a model is fitted
#' on four fifths of them at a time, and a predictor that varies at two sites
#' in seven thousand (whether the tree inventories spoke for the ground, say)
#' is constant whenever both are held out; maxnet cannot build a hinge on it
#' and the fit fails. Left out, it simply has no say in that model.
atlas_fit_maxnet <- function(training, classes = NULL, regmult = 1) {
  if (!requireNamespace("maxnet", quietly = TRUE)) {
    stop("maxnet is needed to fit: install.packages('maxnet')", call. = FALSE)
  }
  predictors <- training[, atlas_predictor_columns(training), drop = FALSE]
  predictors <- predictors[, atlas_drop_constant(predictors), drop = FALSE]
  presence <- as.integer(training$presence)
  if (sum(presence == 1L) < 2L) {
    stop("a fit needs at least two presences", call. = FALSE)
  }
  classes <- classes %||% atlas_feature_classes(sum(presence == 1L))
  data <- rbind(predictors, predictors[presence == 1L, , drop = FALSE])
  p <- c(presence, rep(0L, sum(presence == 1L)))
  maxnet::maxnet(
    p = p,
    data = data,
    f = maxnet::maxnet.formula(p, data, classes = classes),
    regmult = regmult,
    addsamplestobackground = FALSE
  )
}

#' Suitability on the cloglog scale, clamped outside the training range.
atlas_suitability <- function(model, newdata) {
  as.numeric(stats::predict(model, newdata, type = "cloglog", clamp = TRUE))
}

#' The effort a map is drawn at: the median of the taxon's detection sites,
#' a place surveyed as thoroughly as a typical place it was found.
atlas_effort_level <- function(training) {
  if (!ATLAS_EFFORT_COLUMN %in% names(training)) {
    return(NULL)
  }
  found <- training[[ATLAS_EFFORT_COLUMN]][training$presence == 1L]
  if (!length(found)) {
    return(0)
  }
  stats::median(found)
}

#' A scoring function that holds effort at one value, whatever the data say.
#'
#' Rasters have no effort layer, so the column is added; tables have one, and
#' it is overwritten. With effort_at NULL the score is used as it is.
atlas_score_at_effort <- function(score, effort_at) {
  if (is.null(effort_at)) {
    return(score)
  }
  force(score)
  function(model, newdata) {
    newdata[[ATLAS_EFFORT_COLUMN]] <- rep(effort_at, nrow(newdata))
    score(model, newdata)
  }
}

#' Area under the ROC curve, from ranks.
#'
#' Against other surveyed sites rather than true absences this is a measure
#' of separation from where people looked. Read it as a comparison between
#' models of the same species, not as a probability of being right.
atlas_auc <- function(presence, background) {
  presence <- presence[is.finite(presence)]
  background <- background[is.finite(background)]
  if (!length(presence) || !length(background)) {
    return(NA_real_)
  }
  ranks <- rank(c(presence, background))
  n1 <- length(presence)
  n0 <- length(background)
  (sum(ranks[seq_len(n1)]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

#' Continuous Boyce index.
#'
#' Slides a window across the predicted range and asks how many presences fall
#' in it against how much landscape it covers. A model that ranks honestly
#' gives a rising ratio, and the index is the rank correlation of that ratio
#' with the prediction: 1 is consistent, 0 is no better than the background,
#' negative means it is upside down.
atlas_boyce <- function(presence, background, windows = 100, width = 0.1) {
  presence <- presence[is.finite(presence)]
  background <- background[is.finite(background)]
  if (length(presence) < 3L || length(background) < 3L) {
    return(NA_real_)
  }
  all_values <- c(presence, background)
  low <- min(all_values)
  high <- max(all_values)
  if (!is.finite(low) || !is.finite(high) || high <= low) {
    return(NA_real_)
  }
  span <- width * (high - low)
  starts <- seq(low, high - span, length.out = windows)
  middles <- starts + span / 2
  ratio <- vapply(starts, function(start) {
    covered <- mean(background >= start & background <= start + span)
    if (covered == 0) {
      return(NA_real_)
    }
    mean(presence >= start & presence <= start + span) / covered
  }, numeric(1))
  usable <- is.finite(ratio)
  if (sum(usable) < 3L) {
    return(NA_real_)
  }
  suppressWarnings(
    stats::cor(middles[usable], ratio[usable], method = "spearman")
  )
}

#' Fit on all but one spatial block at a time, and score the held-out region.
#'
#' fit and score default to Maxent; the studies pass other learners through
#' the same loop, so every arm is scored on exactly the same folds. Effort is
#' held at effort_at when scoring, so a held-out region is judged on habitat.
atlas_cross_validate <- function(training, folds, classes = NULL, regmult = 1,
                                 fit = function(train) {
                                   atlas_fit_maxnet(train, classes = classes, regmult = regmult)
                                 },
                                 score = atlas_suitability,
                                 effort_at = atlas_effort_level(training)) {
  held_score <- atlas_score_at_effort(score, effort_at)
  results <- lapply(sort(unique(folds)), function(fold) {
    held <- folds == fold
    train <- training[!held, , drop = FALSE]
    test <- training[held, , drop = FALSE]
    presences_held <- sum(test$presence == 1L)
    if (sum(train$presence == 1L) < 2L || presences_held < 1L ||
        sum(test$presence == 0L) < 3L) {
      return(data.frame(
        fold = fold, presences = presences_held,
        auc = NA_real_, boyce = NA_real_
      ))
    }
    model <- fit(train)
    scores <- held_score(model, test[, atlas_predictor_columns(test), drop = FALSE])
    row <- data.frame(
      fold = fold,
      presences = presences_held,
      auc = atlas_auc(scores[test$presence == 1L], scores[test$presence == 0L]),
      boyce = atlas_boyce(scores[test$presence == 1L], scores[test$presence == 0L])
    )
    attr(row, "held") <- data.frame(fold = fold, presence = test$presence, score = scores)
    row
  })
  atlas_bind_folds(results)
}

#' Bind the per-fold rows, keeping every held-out score as attr(, "held").
atlas_bind_folds <- function(results) {
  held <- do.call(rbind, lapply(results, attr, "held"))
  out <- do.call(rbind, results)
  rownames(out) <- NULL
  attr(out, "held") <- held
  out
}

#' The Boyce index of every fold's held-out scores together.
#'
#' scores is what atlas_cross_validate or atlas_nested_cross_validate returns.
#' NA when nothing was held out.
atlas_pooled_boyce <- function(scores) {
  held <- attr(scores, "held")
  if (is.null(held) || !nrow(held)) {
    return(NA_real_)
  }
  atlas_boyce(held$score[held$presence == 1L], held$score[held$presence == 0L])
}

#' Choose an algorithm's settings on the given folds.
#'
#' Each candidate in the algorithm's grid is cross-validated on the folds and
#' the one with the best mean AUC wins; ties go to the earlier, simpler
#' candidate. An algorithm can bring its own tuner (boosted trees tune depth
#' and tree count together through early stopping). When nothing can be
#' scored, the algorithm's default stands.
atlas_tune <- function(training, folds, algo, seed = 1L,
                       effort_at = atlas_effort_level(training)) {
  default <- algo$default(training)
  if (!is.null(algo$tune)) {
    tuned <- tryCatch(algo$tune(training, folds, seed), error = function(e) NULL)
    return(list(params = tuned %||% default, tried = NULL))
  }
  candidates <- algo$grid(training)
  if (length(candidates) <= 1L) {
    return(list(params = candidates[[1]] %||% default, tried = NULL))
  }
  aucs <- vapply(candidates, function(params) {
    scores <- tryCatch(
      atlas_cross_validate(
        training, folds,
        fit = function(train) algo$fit(train, params, seed, tuning = TRUE),
        score = algo$score, effort_at = effort_at
      ),
      error = function(e) NULL
    )
    if (is.null(scores) || all(is.na(scores$auc))) NA_real_ else mean(scores$auc, na.rm = TRUE)
  }, numeric(1))
  if (all(is.na(aucs))) {
    return(list(params = default, tried = aucs))
  }
  list(params = candidates[[which.max(aucs)]], tried = round(aucs, 4))
}

#' Nested cross-validation: settings chosen inside each outer fold.
#'
#' For every outer fold, the other regions are split again into inner
#' spatial folds, settings are tuned there, a model with those settings is
#' fitted on all the other regions, and the held-out region is scored. The
#' scores are therefore what a model tuned without this ground makes of it.
atlas_nested_cross_validate <- function(training, folds, algo, block_km, seed = 1L,
                                        inner_folds = ATLAS_INNER_FOLDS,
                                        effort_at = atlas_effort_level(training),
                                        tune = TRUE) {
  held_score <- atlas_score_at_effort(algo$score, effort_at)
  rows <- lapply(sort(unique(folds)), function(fold) {
    held <- folds == fold
    train <- training[!held, , drop = FALSE]
    test <- training[held, , drop = FALSE]
    presences_held <- sum(test$presence == 1L)
    empty <- data.frame(fold = fold, presences = presences_held,
                        auc = NA_real_, boyce = NA_real_, params = "")
    if (sum(train$presence == 1L) < 2L || presences_held < 1L ||
        sum(test$presence == 0L) < 3L) {
      return(empty)
    }
    params <- if (isTRUE(tune)) {
      inner <- atlas_spatial_folds(
        train$x, train$y, k = inner_folds, block_km = block_km,
        seed = seed + fold, presence = train$presence
      )
      atlas_tune(train, inner, algo, seed, effort_at)$params
    } else {
      algo$default(train)
    }
    model <- algo$fit(train, params, seed)
    scores <- held_score(model, test[, atlas_predictor_columns(test), drop = FALSE])
    row <- data.frame(
      fold = fold,
      presences = presences_held,
      auc = atlas_auc(scores[test$presence == 1L], scores[test$presence == 0L]),
      boyce = atlas_boyce(scores[test$presence == 1L], scores[test$presence == 0L]),
      params = atlas_params_label(params)
    )
    attr(row, "held") <- data.frame(fold = fold, presence = test$presence, score = scores)
    row
  })
  atlas_bind_folds(rows)
}

#' Settings as a short readable label, for logs and the stored folds.
atlas_params_label <- function(params) {
  if (!length(params)) return("")
  paste(names(params), vapply(params, function(v) paste(v, collapse = "+"), character(1)),
        sep = "=", collapse = " ")
}

#' Draw one set of null detections: n sites, busier sites more often.
#'
#' The null species is a random handful of collections. A site holding more
#' records is more likely to hold any given fungus, so sites are drawn in
#' proportion to their records (effort is log records).
atlas_null_presence <- function(training, n, seed) {
  weight <- if (ATLAS_EFFORT_COLUMN %in% names(training)) {
    exp(training[[ATLAS_EFFORT_COLUMN]])
  } else {
    rep(1, nrow(training))
  }
  set.seed(seed)
  chosen <- sample.int(nrow(training), min(n, nrow(training)), prob = weight)
  presence <- integer(nrow(training))
  presence[chosen] <- 1L
  presence
}

#' The settings the null test fits at: the algorithm's own untuned ones.
atlas_null_params <- function(algo, training) {
  if (!is.null(algo$null_params)) algo$null_params(training) else algo$default(training)
}

#' Compare a taxon with null models, fitted and scored the same way.
#'
#' The taxon and every null go through one procedure: the same sites, folds
#' and predictors, the algorithm's untuned settings, fits at tuning size. The
#' only thing that differs is which sites are detections. p is the share of
#' nulls (counting the taxon itself) that score at least as well: with 19
#' nulls, beating all of them is p = 0.05. The observed scores here are the
#' test's own, not the tuned, nested scores a map reports.
atlas_null_test <- function(training, folds, algo, reps = ATLAS_NULL_REPS, seed = 1L) {
  if (!reps) {
    return(list(reps = 0L))
  }
  params <- atlas_null_params(algo, training)
  run <- function(table) {
    scores <- tryCatch(
      atlas_cross_validate(
        table, folds,
        # Tuning size (250 trees for a forest, which ranks within 0.994 of
        # 1,000): 100 fits per taxon.
        fit = function(train) algo$fit(train, params, seed, tuning = TRUE),
        score = algo$score, effort_at = atlas_effort_level(table)
      ),
      error = function(e) NULL
    )
    if (is.null(scores)) return(c(auc = NA_real_, boyce = NA_real_))
    c(auc = mean(scores$auc, na.rm = TRUE), boyce = atlas_pooled_boyce(scores))
  }
  observed <- run(training)
  observed_auc <- observed[["auc"]]
  observed_boyce <- observed[["boyce"]]
  if (!is.finite(observed_auc)) {
    return(list(reps = 0L))
  }
  n <- sum(training$presence == 1L)
  runs <- lapply(seq_len(reps), function(r) {
    null <- training
    null$presence <- atlas_null_presence(training, n, seed = seed + 1000L + r)
    run(null)
  })
  runs <- do.call(rbind, runs)
  auc <- runs[, "auc"][is.finite(runs[, "auc"])]
  boyce <- runs[, "boyce"][is.finite(runs[, "boyce"])]
  p_value <- function(null, observed) {
    if (!length(null) || !is.finite(observed)) return(NA_real_)
    (1 + sum(null >= observed)) / (1 + length(null))
  }
  list(
    reps = length(auc),
    settings = atlas_params_label(params),
    observed_auc = round(observed_auc, 3),
    observed_boyce = round(observed_boyce, 3),
    auc_mean = round(mean(auc), 3),
    auc_sd = round(stats::sd(auc), 3),
    auc_p = round(p_value(auc, observed_auc), 3),
    boyce_mean = if (length(boyce)) round(mean(boyce), 3) else NA_real_,
    boyce_p = round(p_value(boyce, observed_boyce), 3)
  )
}

#' Whether a map has shown it knows something: its AUC beats the null models
#' and its Boyce index, over every held-out score together, says higher ground
#' holds more detections. "untested" when no nulls were run.
atlas_skill <- function(null, boyce, alpha = ATLAS_SKILL_ALPHA) {
  if (is.null(null) || !isTRUE(null$reps > 0) || !is.finite(null$auc_p %||% NA_real_)) {
    return("untested")
  }
  if (null$auc_p <= alpha && is.finite(boyce) && boyce > 0) "passed" else "failed"
}

#' Where a taxon's fitted map and its scores are written.
atlas_model_path <- function(name, grid = "draft", extension = ".tif", algorithm = "maxnet") {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  file.path(atlas_model_dir(grid, algorithm), paste0(slug, extension))
}

#' A refusal to model, as opposed to a failure: the taxon is fine, there is
#' just not enough of it, or not spread widely enough to be scored. Classed so
#' a batch run can count the two apart.
atlas_insufficient_evidence <- function(name, presences, grid, min_presences,
                                        blocks = NULL, min_blocks = NULL,
                                        block_km = NULL) {
  reason <- if (!is.null(blocks)) {
    paste0(presences, " detection sites in ", blocks, " blocks of ", block_km,
           " km on the ", grid, " grid, and a map needs them in ", min_blocks,
           " blocks to be scored on ground it did not learn from")
  } else {
    paste0(presences, " detection sites on the ", grid, " grid, and a map needs ",
           min_presences)
  }
  structure(
    class = c("atlas_insufficient_evidence", "error", "condition"),
    list(
      message = paste0(
        "insufficient evidence for ", name, ": ", reason,
        ". This taxon is a survey target, not a model."
      ),
      call = NULL,
      presences = presences
    )
  )
}

#' How the analysis is designed, as recorded in every model's settings. A
#' change to any of this makes every stored model stale. A function, because
#' the block limits live in R/sites.R, which loads after this file.
atlas_design <- function() list(
  unit = "survey sites, detection/non-detection",
  effort = "log(records at the site, the taxon's own counted once), held at the median of detection sites",
  block = list(method = "blockCV detection autocorrelation range",
               floor_km = ATLAS_BLOCK_FLOOR_KM, ceiling_km = ATLAS_BLOCK_CEILING_KM,
               fallback_km = ATLAS_BLOCK_FALLBACK_KM),
  tuning = "nested spatial folds",
  inner_folds = ATLAS_INNER_FOLDS,
  skill = list(alpha = ATLAS_SKILL_ALPHA, boyce_above = 0,
               boyce = "held-out scores of every fold together",
               nulls = "taxon and nulls both at untuned settings")
)

#' Everything that decides a fit apart from the records themselves.
#'
#' A stored model is current only when both its record set and these match.
#' The layers are in here because a model fitted before soil was built has the
#' same records as one fitted after, and is still out of date. block_km is
#' "auto" when blockCV sets it per taxon.
#'
#' The predictor order depends on each taxon's guild (R/guilds.R), so a pruned
#' model's settings hold the rule — the order for each kind of guild — and a
#' hash of the guild table, not any one taxon's guild. Keeping the settings the
#' same for every taxon is what lets a batch check them once. The table is the
#' only thing that can change a taxon's guild while its records stay the same,
#' so hashing it is enough to be correct: a changed table stales every Maxent
#' model and they all refit, including the many whose guild did not change.
#' That is wasted work only in principle; the table is a published supplement
#' that changes about never. Recording a guild per model and comparing it at
#' each check would refit only the affected taxa, at the cost of carrying the
#' guild through planning, sharding and the release index. The boosted trees
#' and the forest take every predictor in any order, so their settings leave
#' the table out and it never stales them.
atlas_fit_settings <- function(grid = "draft", n_background = 10000,
                               buffer_km = 500, folds = 5, block_km = "auto",
                               regmult = 1, correlation = 0.7, prune = TRUE,
                               layers = atlas_layers_key(grid),
                               algorithm = "maxnet", thin_km = ATLAS_SITE_KM,
                               nulls = ATLAS_NULL_REPS, tune = TRUE,
                               min_blocks = ATLAS_MIN_BLOCKS,
                               guild_table = atlas_guild_table_key()) {
  algo <- atlas_algorithm(algorithm)
  list(
    grid = grid,
    algorithm = algo$id,
    n_background = as.numeric(n_background),
    buffer_km = as.numeric(buffer_km),
    folds = as.numeric(folds),
    block_km = if (atlas_block_is_auto(block_km)) "auto" else as.numeric(block_km),
    thin_km = as.numeric(thin_km),
    min_blocks = as.numeric(min_blocks),
    correlation = if (isTRUE(prune)) as.numeric(correlation) else "none",
    priority = if (isTRUE(prune)) {
      list(
        rule = "host bands after soil pH for ectomycorrhizal genera, after temperature otherwise",
        ectomycorrhizal = atlas_predictor_priority("ectomycorrhizal"),
        other = atlas_predictor_priority(ATLAS_GUILD_UNKNOWN),
        host_share = ATLAS_HOST_SHARE,
        host_order = "conifer share, then share of the region's trees",
        guild_table = guild_table
      )
    } else {
      "none"
    },
    tuning = if (isTRUE(tune)) algo$grid_description() else list(default = TRUE, regmult = regmult),
    learner = algo$learner(),
    nulls = as.numeric(nulls),
    design = atlas_design(),
    layers = layers
  )
}

#' Whether a block size means "let blockCV decide".
atlas_block_is_auto <- function(block_km) {
  is.null(block_km) || identical(block_km, "auto") || (is.list(block_km) && !length(block_km)) ||
    (length(block_km) == 1L && is.na(suppressWarnings(as.numeric(block_km))))
}

#' One string standing for a set of fit settings.
atlas_settings_key <- function(settings) {
  settings <- settings[order(names(settings))]
  digest::digest(
    as.character(jsonlite::toJSON(settings, auto_unbox = TRUE, digits = NA)),
    algo = "sha256"
  )
}

#' Which layers, and which build of each, a grid's stack is made of.
atlas_layers_key <- function(grid = "draft", manifest = atlas_layer_manifest(grid)) {
  if (!length(manifest)) {
    return("none")
  }
  entries <- vapply(manifest, function(x) {
    paste0(x$id, "=", x$md5 %||% x$built_at %||% "")
  }, character(1))
  digest::digest(paste(sort(entries), collapse = ";"), algo = "sha256")
}

#' Fit one taxon end to end: training sites, block size, tuned and nested
#' blocked scores, null models, map, metrics.
#'
#' With predict = FALSE the scores are still computed and written, but no map
#' is drawn: that is the cheap way to score hundreds of taxa.
#'
#' guilds is the genus-to-lifestyle table (R/guilds.R); it decides where the
#' host-tree bands sit in Maxent's predictor order.
atlas_fit_taxon <- function(name, grid = "draft", n_background = 10000,
                            buffer_km = 500, folds = 5, block_km = "auto",
                            regmult = 1, min_presences = 20, correlation = 0.7,
                            prune = NULL, write = TRUE, predict = TRUE,
                            quiet = FALSE, points = NULL, stack = NULL,
                            occurrences = NULL, fingerprint = NULL,
                            layers = NULL, algorithm = "maxnet",
                            thin_km = ATLAS_SITE_KM, nulls = ATLAS_NULL_REPS,
                            tune = TRUE, min_blocks = ATLAS_MIN_BLOCKS,
                            guilds = atlas_guild_table()) {
  algo <- atlas_algorithm(algorithm)
  # Each algorithm has its own habit about correlated predictors; an explicit
  # prune overrides it.
  prune <- prune %||% algo$prune
  min_presences <- atlas_algorithm_min(algo, min_presences)
  stack <- stack %||% atlas_predictor_stack(grid)
  settings <- atlas_fit_settings(
    grid = grid, n_background = n_background, buffer_km = buffer_km,
    folds = folds, block_km = block_km, regmult = regmult,
    correlation = correlation, prune = prune,
    layers = layers %||% atlas_layers_key(grid), algorithm = algo$id,
    thin_km = thin_km, nulls = nulls, tune = tune, min_blocks = min_blocks,
    guild_table = atlas_guild_table_key(guilds)
  )
  guild <- atlas_taxon_guild(name, guilds)
  priority <- atlas_predictor_priority(guild)
  training <- atlas_build_training(
    name, grid,
    n_background = n_background, buffer_km = buffer_km,
    write = FALSE, quiet = TRUE, points = points, stack = stack,
    occurrences = occurrences, fingerprint = fingerprint, thin_km = thin_km
  )
  presences <- sum(training$presence == 1L)
  refuse <- function(condition) {
    # A model left from when the taxon had more sites, or from before the
    # algorithm had a minimum, would still be shown; it goes.
    if (isTRUE(write)) atlas_remove_model(name, grid, algo$id)
    stop(condition)
  }
  if (presences < min_presences) {
    refuse(atlas_insufficient_evidence(name, presences, grid, min_presences))
  }

  considered <- setdiff(atlas_predictor_columns(training), ATLAS_EFFORT_COLUMN)
  if (isTRUE(prune)) {
    keep <- atlas_choose_predictors(training, threshold = correlation, priority = priority,
                                    host_share = atlas_host_allowance(guild))
    kept_attributes <- attributes(training)[c("area_km2", "seed", "fingerprint", "dropped", "thin_km")]
    training <- training[, c("presence", "cell", "x", "y", keep), drop = FALSE]
    attributes(training)[names(kept_attributes)] <- kept_attributes
  }

  seed <- attr(training, "seed")
  block <- if (atlas_block_is_auto(block_km)) {
    atlas_block_size(training, seed = seed)
  } else {
    list(block_km = as.numeric(block_km), range_km = NA_real_, source = "fixed")
  }
  blocks <- atlas_presence_blocks(training, block$block_km)
  if (blocks < min_blocks) {
    refuse(atlas_insufficient_evidence(
      name, presences, grid, min_presences,
      blocks = blocks, min_blocks = min_blocks, block_km = block$block_km
    ))
  }
  fold_ids <- atlas_spatial_folds(
    training$x, training$y, k = folds, block_km = block$block_km, seed = seed,
    presence = training$presence
  )
  effort_at <- atlas_effort_level(training)

  scores <- atlas_nested_cross_validate(
    training, fold_ids, algo, block_km = block$block_km, seed = seed,
    effort_at = effort_at, tune = tune
  )
  final <- if (isTRUE(tune)) {
    atlas_tune(training, fold_ids, algo, seed, effort_at)
  } else {
    list(params = algo$default(training), tried = NULL)
  }
  model <- algo$fit(training, final$params, seed)
  auc_mean <- mean(scores$auc, na.rm = TRUE)
  boyce_mean <- mean(scores$boyce, na.rm = TRUE)
  boyce_pooled <- atlas_pooled_boyce(scores)
  null <- if (is.finite(auc_mean)) {
    atlas_null_test(training, fold_ids, algo, reps = nulls, seed = seed)
  } else {
    list(reps = 0L)
  }
  skill <- atlas_skill(null, boyce_pooled)

  held_score <- atlas_score_at_effort(algo$score, effort_at)
  suitability <- NULL
  if (isTRUE(predict)) {
    occupied <- training[training$presence == 1L, , drop = FALSE]
    area <- atlas_accessible_area(occupied$x, occupied$y, buffer_km)
    suitability <- atlas_predict_raster(model, stack, area, score = held_score)
  } else if (isTRUE(write)) {
    # A map left over from an older fit would be drawn beside scores it does
    # not belong to, so it goes.
    atlas_remove_map(name, grid, algo$id)
  }

  # Two names that make the same file name would overwrite each other's map
  # without a word. Refuse instead: it means two spellings need merging.
  if (isTRUE(write)) {
    existing <- atlas_read_metrics(name, grid, algo$id)
    if (!is.null(existing) && is.character(existing$taxon) && !identical(existing$taxon, name)) {
      stop("the file for ", name, " already holds ", existing$taxon,
           "; two names share a file name", call. = FALSE)
    }
  }

  raster_path <- NULL
  drawn <- NULL
  if (isTRUE(write) && !is.null(suitability)) {
    raster_path <- atlas_model_path(name, grid, algorithm = algo$id)
    dir.create(dirname(raster_path), recursive = TRUE, showWarnings = FALSE)
    terra::writeRaster(
      suitability, raster_path, overwrite = TRUE,
      gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "TILED=YES")
    )
    # Draw it too, so a new fit shows up in the app without a second command.
    drawn <- atlas_write_map_png(suitability, sub("[.]tif$", ".png", raster_path))
  }

  metrics <- list(
    taxon = name,
    algorithm = algo$id,
    algorithm_label = algo$label,
    grid = grid,
    presences = presences,
    background = sum(training$presence == 0L),
    area_km2 = round(attr(training, "area_km2")),
    cells_without_data = attr(training, "dropped"),
    predictors = as.list(setdiff(atlas_predictor_columns(training), ATLAS_EFFORT_COLUMN)),
    predictors_considered = length(considered),
    genus = atlas_taxon_genus(name),
    guild = guild,
    # The order the predictors were pruned in; the trees take them all.
    priority = if (isTRUE(prune)) as.list(priority) else NULL,
    effort_at = round(effort_at %||% NA_real_, 4),
    correlation = if (isTRUE(prune)) correlation else NA,
    params = final$params,
    tuning = final$tried,
    nrounds = attr(model, "nrounds"),
    block_km = block$block_km,
    block_range_km = block$range_km,
    block_source = block$source,
    presence_blocks = blocks,
    thin_km = thin_km,
    seed = seed,
    fingerprint = attr(training, "fingerprint"),
    settings = settings,
    settings_key = atlas_settings_key(settings),
    folds = lapply(seq_len(nrow(scores)), function(i) as.list(scores[i, ])),
    auc_mean = round(auc_mean, 3),
    auc_sd = round(stats::sd(scores$auc, na.rm = TRUE), 3),
    # boyce is the index of every fold's held-out scores together, and the
    # one a map is judged by; boyce_mean, the mean over folds, is kept for
    # comparison with models fitted before it.
    boyce = round(boyce_pooled, 3),
    boyce_mean = round(boyce_mean, 3),
    boyce_sd = round(stats::sd(scores$boyce, na.rm = TRUE), 3),
    null = null,
    skill = skill,
    raster = if (is.null(raster_path)) NULL else basename(raster_path),
    md5 = if (is.null(raster_path)) NULL else unname(tools::md5sum(raster_path)),
    map = if (is.null(drawn)) NULL else basename(drawn$path),
    bounds = if (is.null(drawn)) NULL else drawn$bounds,
    map_scale = if (is.null(drawn)) NULL else drawn$scale,
    map_drawn_at = if (is.null(drawn)) NULL else drawn$drawn_at,
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    r_version = as.character(getRversion()),
    package = algo$package,
    package_version = as.character(utils::packageVersion(algo$package)),
    terra_version = as.character(utils::packageVersion("terra"))
  )
  if (isTRUE(write)) {
    atlas_write_json(metrics, atlas_model_path(name, grid, ".json", algo$id))
  }

  if (!isTRUE(quiet)) {
    message(name, " (", algo$label, ")")
    message("  detection sites:    ", metrics$presences, " in ", blocks, " blocks")
    message("  other sites:        ", metrics$background)
    message("  predictors:         ", length(metrics$predictors), " of ",
            metrics$predictors_considered, " (+ effort)")
    message("  guild:              ", guild,
            if (isTRUE(prune)) paste0(" (host trees ", if (guild %in% ATLAS_HOST_FIRST_GUILDS) {
              "after soil pH)"
            } else {
              "after temperature)"
            }) else "")
    message("  block:              ", block$block_km, " km (", block$source,
            if (is.finite(block$range_km)) paste0(", range ", block$range_km, " km") else "", ")")
    message("  settings:           ", atlas_params_label(final$params))
    message("  blocked AUC:        ", metrics$auc_mean, " (sd ", metrics$auc_sd, ")")
    message("  blocked Boyce:      ", metrics$boyce, " (fold mean ", metrics$boyce_mean,
            ", sd ", metrics$boyce_sd, ")")
    message("  folds scored:       ", sum(!is.na(scores$auc)), " of ", nrow(scores))
    if (isTRUE(null$reps > 0)) {
      message("  null AUC:           ", null$auc_mean, " (sd ", null$auc_sd, ", ",
              null$reps, " nulls) against ", null$observed_auc,
              " at untuned settings, p = ", null$auc_p)
    }
    message("  skill:              ", skill)
    if (!is.null(raster_path)) message("  map:                ", raster_path)
  }

  invisible(list(model = model, metrics = metrics, scores = scores,
                 suitability = suitability))
}

#' Delete a taxon's map, leaving its scores.
atlas_remove_map <- function(name, grid = "draft", algorithm = "maxnet") {
  paths <- atlas_model_path(name, grid, c(".tif", ".png", ".png.aux.xml"), algorithm)
  unlink(paths[file.exists(paths)])
  invisible(paths)
}

#' The stored metrics for a taxon, or NULL when it has never been fitted.
atlas_read_metrics <- function(name, grid = "draft", algorithm = "maxnet") {
  path <- atlas_model_path(name, grid, ".json", algorithm)
  if (!file.exists(path)) {
    return(NULL)
  }
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

#' Whether a stored fit still stands for these records and these settings.
#'
#' The name alone never decides it: a provisional name can be kept while
#' FungAI moves records in or out of it, and then the model is stale.
atlas_fit_is_current <- function(metrics, fingerprint, settings, predict = TRUE) {
  if (is.null(metrics) || is.null(fingerprint) || is.na(fingerprint)) {
    return(FALSE)
  }
  if (!identical(as.character(metrics$fingerprint %||% ""), as.character(fingerprint))) {
    return(FALSE)
  }
  if (!identical(as.character(metrics$settings_key %||% ""), atlas_settings_key(settings))) {
    return(FALSE)
  }
  if (isTRUE(predict)) {
    # A fit without a map stores its raster as an empty JSON object, which
    # comes back as an empty list rather than NULL.
    raster <- metrics$raster
    if (!is.character(raster) || length(raster) != 1L || !nzchar(raster) ||
        !file.exists(file.path(
          atlas_model_dir(settings$grid %||% "draft", settings$algorithm %||% "maxnet"),
          raster
        ))) {
      return(FALSE)
    }
  }
  TRUE
}

#' Predict suitability across the accessible area.
atlas_predict_raster <- function(model, stack, area, score = atlas_suitability) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("terra is needed to predict: install.packages('terra')", call. = FALSE)
  }
  # Mask before predicting, not after: the rectangle around the circles can be
  # twice their area, and a thousand-tree forest spends minutes on cells that
  # would only be thrown away. Masked cells are NA, which predict skips.
  window <- terra::mask(terra::crop(stack, terra::ext(area)), area)
  predicted <- terra::predict(
    window, model,
    fun = function(model, data, ...) score(model, data),
    na.rm = TRUE
  )
  names(predicted) <- "suitability"
  terra::mask(predicted, area)
}
