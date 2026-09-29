# Choosing predictors.
#
# Thirty-three predictors against forty-seven presences is a lot of rope, and
# the nineteen bioclim variables are near-copies of each other: mean annual
# temperature and mean temperature of the warmest quarter say almost the same
# thing twice. Measured on identical records, a hand-pruned set of twelve beat
# all thirty-three (0.561 against 0.511) with less variance between folds.
#
# So predictors are pruned by correlation before fitting, keeping whichever of
# a correlated pair comes first in a fixed order. The order is ecological
# rather than statistical: for fungi, soil pH first — among the strongest known
# drivers of where fungi occur (Tedersoo et al. 2014), and before this order
# put it first it reached only 29% of Maxent models with 30-49 sites — then
# moisture, then temperature, then what they grow on, then the rest of the
# soil, then the shape of the ground. When two
# variables are interchangeable to the model, the one a mycologist would name
# is the one that survives, which also makes a response curve readable.
#
# Correlations are measured on the background — the environment available to
# the species — not on the presences, which are too few to estimate them.

ATLAS_PREDICTOR_PRIORITY <- c(
  # Soil pH: which fungi a soil holds follows its acidity more than its climate.
  "soil_phh2o",
  # Moisture: the first thing that decides whether a fungus fruits at all.
  "bio12", "bio17", "bio15", "bio14",
  # Temperature: means, then the extremes that set a range's edges.
  "bio1", "bio6", "bio5", "bio4",
  # What it grows on or with.
  "cover_trees", "cover_wetland", "cover_shrubs", "cover_grassland",
  # The rest of the soil.
  "soil_soc", "soil_clay", "soil_sand", "soil_cec",
  # The shape of the ground.
  "elevation", "slope", "roughness"
)

#' Drop predictors that say nothing, because they never vary here.
atlas_drop_constant <- function(data) {
  varies <- vapply(data, function(column) {
    values <- column[is.finite(column)]
    length(values) > 0 && stats::var(values) > 0
  }, logical(1))
  names(data)[varies]
}

#' Keep one predictor from each correlated group, preferring the earlier one.
atlas_prune_correlated <- function(data, threshold = 0.7,
                                   priority = ATLAS_PREDICTOR_PRIORITY) {
  usable <- atlas_drop_constant(data)
  if (length(usable) < 2L) {
    return(usable)
  }
  ordered <- c(intersect(priority, usable), setdiff(usable, priority))
  correlations <- abs(stats::cor(
    data[, ordered, drop = FALSE], use = "pairwise.complete.obs"
  ))

  kept <- ordered[1]
  for (name in ordered[-1]) {
    against <- correlations[name, kept]
    if (all(is.na(against)) || max(against, na.rm = TRUE) < threshold) {
      kept <- c(kept, name)
    }
  }
  kept
}

#' The predictors a training table should be fitted on.
#'
#' Pruning correlated variables is only half of it. Measured across three taxa,
#' how much pruning helps depends entirely on how many records there are:
#'
#'   presences   all 33   pruned to ~10-13
#'          47    0.512               0.610
#'         150    0.706               0.689
#'         294    0.580               0.552
#'
#' A sparse taxon gains a tenth of an AUC from a short list; a well-recorded
#' one loses a little. So the number of predictors is capped in proportion to
#' the presences — roughly one predictor per four records — and the cap simply
#' does not bind once a taxon is well recorded. The ratio is the mechanism;
#' the correlation threshold only decides which of two twins is dropped.
#'
#' Re-measured on 153 taxa (atlas_predictor_sweep, 2026-09-28): the gain is
#' smaller than those three suggested — about 0.02 AUC for 20-29 cells — and
#' shows mostly in the Boyce index, which drops by 0.07-0.09 without a cap.
#' One per four was within noise of the best ratio on both, so it stays.
atlas_choose_predictors <- function(training, threshold = 0.7,
                                    priority = ATLAS_PREDICTOR_PRIORITY,
                                    per_presence = 4, minimum = 5) {
  # Effort is not habitat: it is never pruned against a habitat variable,
  # never counts against the cap, and always goes in.
  available <- setdiff(atlas_predictor_columns(training), ATLAS_EFFORT_COLUMN)
  effort <- intersect(ATLAS_EFFORT_COLUMN, atlas_predictor_columns(training))
  background <- training[training$presence == 0L, available, drop = FALSE]
  kept <- if (nrow(background)) {
    atlas_prune_correlated(background, threshold = threshold, priority = priority)
  } else {
    available
  }
  # per_presence = Inf means no cap at all, not "no predictors per record".
  cap <- if (is.finite(per_presence)) {
    max(minimum, floor(sum(training$presence == 1L) / per_presence))
  } else {
    Inf
  }
  if (length(kept) > cap) {
    # kept is already in priority order, so this keeps the ecologically
    # primary variables and drops the tail.
    kept <- kept[seq_len(cap)]
  }
  c(kept, effort)
}
