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
#
# The candidate layers (R/layersweep.R) slot in beside the variable each one
# refines, ahead of it where it is the more direct measure: the moisture a
# fungus actually lacks (climatic moisture deficit) before the rain that falls
# (bio12), autumn rain and warmth — when most fungi fruit — before the driest
# and warmest quarters, forest type before bare tree cover, lime before the
# rest of the soil. Secondary climate (humidity, vapour pressure deficit,
# evapotranspiration, snow) waits until after the soil, so a sparse taxon's few
# predictors are not all spent on moisture. A layer that is not built simply
# has no columns, and the order is unchanged for the rest.
#
# Where the host trees go depends on the fungus (atlas_predictor_priority),
# and how many of them a model may take depends on its records
# (atlas_limit_hosts).

# The order before the host-tree bands are placed in it.
ATLAS_PREDICTOR_PRIORITY <- c(
  # Soil pH: which fungi a soil holds follows its acidity more than its climate.
  "soil_phh2o",
  # Moisture: the first thing that decides whether a fungus fruits at all.
  "clim_cmd", "bio12", "clim_ppt_autumn", "bio17", "bio15", "bio14",
  # Temperature: means, then the fruiting season, then the extremes that set
  # a range's edges.
  "bio1", "clim_tave_autumn", "clim_ffp", "bio6", "bio5", "bio4",
  # What it grows on or with.
  "forest_needleleaf", "forest_broadleaf", "forest_mixed",
  "cover_trees", "cover_wetland", "cover_shrubs", "cover_grassland",
  # The rest of the soil, and the rock beneath.
  "bedrock_carbonate", "soil_soc", "soil_clay", "soil_sand", "soil_cec",
  # Secondary climate.
  "clim_rh", "clim_vpd", "clim_aet", "clim_pas",
  # The shape of the ground: where water gathers, which way it faces.
  "elevation", "twi", "northness", "heat_load", "slope", "roughness"
)

# Whether the inventories spoke for a cell (R/layers.R, atlas_fill_outside).
ATLAS_HOST_KNOWN_BANDS <- c("host_known", "hostw_known")

# The share of a model's predictors the host trees may take. There are twenty
# host bands and they are barely correlated, so placed straight after soil pH
# they used up a sparse taxon's whole allowance: forty sites give ten
# predictors, which were soil pH and nine trees, several of them trees that do
# not grow in the region, and no climate at all. An ectomycorrhizal fungus gets
# a third of its predictors for trees, anything else a fifth.
ATLAS_HOST_SHARE <- list(ectomycorrhizal = 1 / 3, other = 1 / 5)

# Guilds whose host trees come straight after soil pH. An ectomycorrhizal
# fungus cannot fruit where its partner tree is absent, whatever the climate,
# so which trees grow there is the next thing a mycologist would ask. Every
# other guild — and a genus FungalTraits does not know — gets the host bands
# after climate: a wood-rotter cares which wood, but rainfall and temperature
# decide first.
ATLAS_HOST_FIRST_GUILDS <- "ectomycorrhizal"

#' The predictor order for a guild (R/guilds.R): the fixed ecological order,
#' with the host-tree bands placed after soil pH for ectomycorrhizal fungi
#' and after the temperature block, before land cover, for everything else.
#'
#' Only Maxent's pruning reads it; the boosted trees and the forest take every
#' predictor.
atlas_predictor_priority <- function(guild = ATLAS_GUILD_UNKNOWN) {
  after <- if (isTRUE(guild %in% ATLAS_HOST_FIRST_GUILDS)) "soil_phh2o" else "bio4"
  at <- match(after, ATLAS_PREDICTOR_PRIORITY)
  c(
    ATLAS_PREDICTOR_PRIORITY[seq_len(at)],
    atlas_host_columns(),
    ATLAS_PREDICTOR_PRIORITY[-seq_len(at)]
  )
}

#' Every host-tree column either host layer can bring, flags first.
atlas_host_columns <- function() {
  c(ATLAS_HOST_KNOWN_BANDS, ATLAS_HOST_BANDS,
    atlas_wilson_band(names(ATLAS_WILSON_GENERA)))
}

#' Whether a column is a host tree's share (not the flag beside them).
atlas_is_host_share <- function(columns) {
  grepl("^hostw?_", columns) & !columns %in% ATLAS_HOST_KNOWN_BANDS
}

#' The share of its predictors a guild's model may spend on host trees.
atlas_host_allowance <- function(guild = ATLAS_GUILD_UNKNOWN) {
  if (isTRUE(guild %in% ATLAS_HOST_FIRST_GUILDS)) {
    ATLAS_HOST_SHARE$ectomycorrhizal
  } else {
    ATLAS_HOST_SHARE$other
  }
}

#' Keep the host trees that matter where the taxon lives, and only as many as
#' its allowance.
#'
#' kept is the pruned predictor list in priority order; cap is how many
#' predictors the model may have. The host shares among them are ranked by how
#' much of the region's trees each is, measured on the non-detection sites —
#' never on the detections, so the choice cannot leak into a score — with the
#' conifer share first, and only the first round(cap x share) stay, at least
#' one. They keep the place in the order the first host had.
atlas_limit_hosts <- function(kept, background, cap, share) {
  is_host <- atlas_is_host_share(kept)
  hosts <- kept[is_host]
  if (!length(hosts) || !is.finite(cap)) {
    return(kept)
  }
  allowed <- max(1L, as.integer(round(cap * share)))
  abundance <- vapply(hosts, function(h) mean(background[[h]], na.rm = TRUE), numeric(1))
  abundance[!is.finite(abundance)] <- 0
  not_conifer <- !grepl("_conifer$", hosts)
  ranked <- hosts[order(not_conifer, -abundance, seq_along(hosts))]
  chosen <- ranked[seq_len(min(allowed, length(ranked)))]
  before <- sum(!is_host[seq_len(match(hosts[1], kept))])
  others <- kept[!is_host]
  c(others[seq_len(before)], chosen, others[seq_along(others) > before])
}

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
                                   priority = atlas_predictor_priority()) {
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
                                    priority = atlas_predictor_priority(),
                                    per_presence = 4, minimum = 5,
                                    host_share = atlas_host_allowance()) {
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
  if (nrow(background)) {
    kept <- atlas_limit_hosts(kept, background, cap, host_share)
  }
  if (length(kept) > cap) {
    # kept is already in priority order, so this keeps the ecologically
    # primary variables and drops the tail.
    kept <- kept[seq_len(cap)]
  }
  c(kept, effort)
}
