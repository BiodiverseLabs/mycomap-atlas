# How few sites can carry a map?
#
# Atlas refuses a taxon with fewer than twenty detection sites, and three
# quarters of the taxa have fewer than five localities. Whether a model of a
# taxon with eight sites is worth drawing cannot be learned from taxa with
# eight sites: with so few detections held out, their scores are noise. It can
# be learned from taxa with plenty, by taking most of their sites away.
#
# For each well-recorded taxon, and each size (5, 8, 12 and 16 sites), the
# training regions of every spatial fold are thinned to that many detection
# sites, drawn at random; every non-detection site stays. Each learner is
# fitted on the thinned table and scored on the held-out region, which keeps
# all of its detections. So a model of eight sites is judged on dozens, in
# ground it never saw. The same taxon fitted on all of its sites is the
# yardstick: what the map would be if the taxon were well recorded.
#
# A size is drawn afresh for each fold, from that fold's training detections,
# with a seed from the taxon's records, the size and the fold.
#
# Nothing here writes a model. It writes one results file under
# data/sparse-studies/.

# The sizes taxa are thinned to.
ATLAS_SPARSE_SIZES <- c(5L, 8L, 12L, 16L)
# The learners compared at each size.
ATLAS_SPARSE_LEARNERS <- c("esm", "maxnet", "rf")
# The arm every other is compared with: Maxent on every site.
ATLAS_SPARSE_BASELINE <- "maxnet@all"

#' The arms of the study: every learner at every size, and on every site.
atlas_sparse_arms <- function(sizes = ATLAS_SPARSE_SIZES, learners = ATLAS_SPARSE_LEARNERS) {
  arms <- expand.grid(learner = learners, size = c(as.character(sizes), "all"),
                      stringsAsFactors = FALSE)
  lapply(seq_len(nrow(arms)), function(i) {
    list(arm = paste0(arms$learner[i], "@", arms$size[i]), learner = arms$learner[i],
         size = if (arms$size[i] == "all") Inf else as.numeric(arms$size[i]))
  })
}

#' A training table thinned to n detection sites, every non-detection kept.
atlas_thin_detections <- function(train, n, seed = 1L) {
  found <- which(train$presence == 1L)
  if (!is.finite(n) || length(found) <= n) {
    return(train)
  }
  set.seed(seed)
  keep <- sort(found[sample.int(length(found), n)])
  out <- train[c(keep, which(train$presence == 0L)), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' How a learner of the study is fitted and scored.
#'
#' Maxent gets the predictors production would give it for the sites it has
#' left: pruned, in the guild's order, one for every four sites, at least
#' five. The forest takes every predictor. The ensemble draws its pairs from
#' the first ten of the pruned list.
atlas_sparse_learner <- function(learner, guild = ATLAS_GUILD_UNKNOWN, correlation = 0.7,
                                 seed = 1L) {
  priority <- atlas_predictor_priority(guild)
  allowance <- atlas_host_allowance(guild)
  switch(
    learner,
    esm = list(
      fit = function(train) {
        atlas_fit_esm(train, seed = seed, predictors = atlas_esm_predictors(
          train, correlation = correlation, priority = priority, host_share = allowance
        ))
      },
      score = atlas_esm_suitability
    ),
    maxnet = list(
      fit = function(train) {
        keep <- atlas_choose_predictors(train, threshold = correlation, priority = priority,
                                        host_share = allowance)
        model <- atlas_fit_maxnet(train[, c("presence", "cell", "x", "y", keep), drop = FALSE])
        attr(model, "predictors") <- keep
        model
      },
      score = function(model, newdata) {
        atlas_suitability(model, newdata[, attr(model, "predictors"), drop = FALSE])
      }
    ),
    rf = list(
      fit = function(train) atlas_fit_rf(train, seed = seed, num_trees = ATLAS_RF_TUNE_TREES),
      score = atlas_rf_suitability
    ),
    stop("unknown learner '", learner, "'", call. = FALSE)
  )
}

#' Score one taxon under every arm, on one table and one set of folds.
atlas_sparse_taxon <- function(name, fingerprint, points, stack,
                               arms = atlas_sparse_arms(), grid = "draft",
                               n_background = 10000, buffer_km = 500, folds = 5,
                               block_km = "auto", correlation = 0.7,
                               min_presences = 40, guilds = atlas_guild_table()) {
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
  seed <- attr(training, "seed")
  block <- if (atlas_block_is_auto(block_km)) {
    atlas_block_size(training, seed = seed)$block_km
  } else {
    as.numeric(block_km)
  }
  fold_ids <- atlas_spatial_folds(
    training$x, training$y, k = folds, block_km = block, seed = seed,
    presence = training$presence
  )
  guild <- atlas_taxon_guild(name, guilds)
  effort_at <- atlas_effort_level(training)

  run_arm <- function(arm) {
    arm_started <- Sys.time()
    learner <- atlas_sparse_learner(arm$learner, guild, correlation, seed)
    fitted_on <- integer()
    scores <- atlas_cross_validate(
      training, fold_ids,
      fit = function(train) {
        fold <- length(fitted_on) + 1L
        thinned <- atlas_thin_detections(
          train, arm$size, seed = seed + 7919L * fold + as.integer(min(arm$size, 1e6))
        )
        fitted_on[[fold]] <<- sum(thinned$presence == 1L)
        learner$fit(thinned)
      },
      score = learner$score, effort_at = effort_at
    )
    list(
      arm = arm$arm, learner = arm$learner,
      size = if (is.finite(arm$size)) arm$size else "all",
      sites_fitted = round(mean(fitted_on), 1),
      predictors = NA,
      auc = round(mean(scores$auc, na.rm = TRUE), 4),
      boyce = round(atlas_pooled_boyce(scores), 4),
      folds_scored = sum(!is.na(scores$auc)),
      seconds = round(as.numeric(difftime(Sys.time(), arm_started, units = "secs")), 1)
    )
  }

  list(
    taxon = name, status = "scored", presences = presences,
    band = atlas_presence_band(presences),
    guild = guild, block_km = block,
    arms = lapply(arms, function(arm) {
      tryCatch(run_arm(arm), error = function(e) {
        list(arm = arm$arm, learner = arm$learner, predictors = NA, auc = NA_real_,
             boyce = NA_real_, folds_scored = 0L, error = conditionMessage(e))
      })
    }),
    seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  )
}

#' Run the study over a stratified sample of well-recorded taxa.
atlas_sparse_study <- function(grid = "draft", per_band = 40, workers = 1L, seed = 1L,
                               min_presences = 40, sizes = ATLAS_SPARSE_SIZES,
                               learners = ATLAS_SPARSE_LEARNERS,
                               n_background = 10000, buffer_km = 500, folds = 5,
                               block_km = "auto", correlation = 0.7, quiet = FALSE,
                               occurrences = NULL, points = NULL, stack = NULL,
                               taxa = NULL) {
  arms <- atlas_sparse_arms(sizes, learners)
  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  candidates <- atlas_batch_candidates(points, min_presences, taxa = taxa)
  sample <- atlas_sweep_sample(candidates, per_band = per_band, seed = seed)
  fingerprints <- atlas_fingerprints_for(occurrences, sample$scientific_name)
  baseline <- if (ATLAS_SPARSE_BASELINE %in% vapply(arms, function(a) a$arm, character(1))) {
    ATLAS_SPARSE_BASELINE
  } else {
    arms[[length(arms)]]$arm
  }

  args <- list(
    arms = arms, grid = grid, n_background = n_background, buffer_km = buffer_km,
    folds = folds, block_km = block_km, correlation = correlation,
    min_presences = min_presences
  )
  settings <- c(args[setdiff(names(args), "arms")], list(
    arms = lapply(arms, function(a) list(arm = a$arm, learner = a$learner,
                                         size = if (is.finite(a$size)) a$size else "all")),
    esm = list(predictors = ATLAS_ESM_PREDICTORS, lambda = ATLAS_ESM_LAMBDA,
               inner_folds = ATLAS_ESM_INNER_FOLDS, inner_block_km = ATLAS_ESM_INNER_BLOCK_KM),
    design = atlas_design(), per_band = per_band, seed = seed
  ))
  atlas_run_study(
    kind = "sparse-studies", file_prefix = "sparse", taxon_fn = "atlas_sparse_taxon",
    sample = sample, fingerprints = fingerprints, args = args,
    settings = settings, baseline = baseline, grid = grid, workers = workers,
    points = points, stack = stack, quiet = quiet,
    opening = paste0(
      nrow(sample), " taxa sampled from ", nrow(candidates), " with ", min_presences,
      "+ detection sites (", atlas_band_counts(sample), "), thinned to ",
      paste(sizes, collapse = ", "), " sites; learners: ", paste(learners, collapse = ", ")
    )
  )
}
