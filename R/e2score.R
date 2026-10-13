# Scoring maps on records they never saw: the hindcast's scorer (paper E2,
# pre-registered 2026-10-13), and every baseline scored beside it (E6a, E6b).
#
# A hindcast fits the full pipeline on the records first validated on or
# before a cutoff, then asks how its maps rank the records first validated
# after it. The scoring is pure: it takes the test places and, for each
# taxon, the maps to score them on, and returns one row per map and place.
# Any surface that can say where a place ranks can be scored this way: a
# release's models, the map a visitor sees, a distance kernel, a
# default-practice Maxent. So a baseline is scored with exactly the metrics
# and units of the maps it is compared with, row for row.
#
# Units and metrics, as pre-registered:
#   place        one taxon in one 5 km cell: several finds of a taxon in a
#                cell count once
#   rank         the place's cell rank on the map, 0..1 within the map's area
#                of applicability (chance: half the places in the top half)
#   top half, top tenth   shares of places at rank >= 0.5 and >= 0.9
#   Boyce        continuous Boyce index of the places' ranks, pooled
#   beats effort the place's rank against the ranks, on the same map, of the
#                cells where every other taxon's test places landed (ties
#                half); 0.5 is no better than knowing where people collect
# Places outside a map's area of applicability or beyond its reach are kept
# apart and counted, never ranked. Intervals are 95% percentile intervals
# from bootstrap resamples of taxa, since places cluster within taxa.
#
# Built on the tracker's lookup, Boyce and Wilson code (R/tracker.R), so the
# hindcast and the prospective tracker (E3) read a map the same way.

# Distance bands to the nearest training record of the taxon, in km.
ATLAS_E2_BANDS_KM <- c(5, 25, 100, 500)
# A place further than this from every training record of its taxon is new.
ATLAS_E2_NEW_KM <- 5
# Fewest ranked places a grade needs before it is tested.
ATLAS_E2_MIN_PLACES <- 30L
ATLAS_E2_BOOTSTRAP <- 10000L

#' The distance band of a distance in km: "0-5", "5-25", "25-100",
#' "100-500" or "500+".
atlas_e2_band <- function(km) {
  breaks <- c(0, ATLAS_E2_BANDS_KM)
  labels <- c(paste0(utils::head(breaks, -1), "-", breaks[-1]), paste0(utils::tail(breaks, 1), "+"))
  ifelse(is.na(km), NA_character_, labels[findInterval(km, breaks, rightmost.closed = FALSE)])
}

#' The test places: each taxon's finds collapsed to one row per 5 km cell.
#'
#' finds has taxon, cell (the model grid's cell) and x, y on the model grid,
#' and optionally observed_after (TRUE when the find was also observed after
#' the cutoff); training has taxon, x and y of the records the hindcast was
#' fitted on. A place sits at its cell's centre (cell_xy gives it), and its
#' distance is from that centre to the taxon's nearest training record. A
#' taxon with no training record has an NA distance and is not "new".
atlas_e2_places <- function(finds, training, cell_xy) {
  if (!nrow(finds)) {
    return(data.frame(taxon = character(), cell = integer(), x = numeric(), y = numeric(),
                      finds = integer(), observed_after = logical(), known_km = numeric(),
                      new_place = logical(), band = character(), stringsAsFactors = FALSE))
  }
  key <- paste(finds$taxon, finds$cell, sep = "\x1f")
  first <- !duplicated(key)
  observed <- if ("observed_after" %in% names(finds)) finds$observed_after %in% TRUE else rep(FALSE, nrow(finds))
  places <- data.frame(taxon = finds$taxon[first], cell = finds$cell[first],
                       finds = as.integer(table(factor(key, levels = key[first]))),
                       observed_after = as.logical(tapply(observed, factor(key, levels = key[first]), any)),
                       stringsAsFactors = FALSE)
  xy <- cell_xy(places$cell)
  places$x <- xy[, 1]
  places$y <- xy[, 2]
  places$known_km <- NA_real_
  for (taxon in unique(places$taxon)) {
    mine <- places$taxon == taxon
    known <- training$taxon == taxon
    if (!any(known)) next
    places$known_km[mine] <- atlas_nearest_km(places$x[mine], places$y[mine],
                                              training$x[known], training$y[known])
  }
  places$new_place <- !is.na(places$known_km) & places$known_km > ATLAS_E2_NEW_KM
  places$band <- atlas_e2_band(places$known_km)
  rownames(places) <- NULL
  places
}

#' Score the places on every map of their taxa.
#'
#' maps_for(taxon) gives a named list of maps, each a list with layers (as
#' atlas_tracker_layers makes them: raster, rank, outside) and grade, and
#' optionally learner; NULL or an empty list when the taxon has none. The
#' result has one row per place and map: rank (NA unless inside), place
#' ("inside", "outside_aoa", "beyond_reach"), and beats_effort for ranked
#' places. A taxon with no map gives one row with map NA and place "no_map".
atlas_e2_score <- function(places, maps_for) {
  rows <- list()
  for (taxon in unique(places$taxon)) {
    mine <- places[places$taxon == taxon, , drop = FALSE]
    others <- unique(places$cell[places$taxon != taxon])
    others_xy <- if (length(others)) places[match(others, places$cell), c("x", "y"), drop = FALSE]
    maps <- maps_for(taxon)
    if (!length(maps)) {
      rows[[length(rows) + 1L]] <- data.frame(mine, map = NA_character_, learner = NA_character_,
                                              grade = NA_character_, rank = NA_real_,
                                              place = "no_map", beats_effort = NA_real_,
                                              stringsAsFactors = FALSE)
      next
    }
    for (id in names(maps)) {
      map <- maps[[id]]
      hit <- atlas_tracker_lookup(map$layers, mine$x, mine$y)
      effort <- rep(NA_real_, nrow(mine))
      if (!is.null(others_xy)) {
        tg <- atlas_tracker_lookup(map$layers, others_xy$x, others_xy$y)$rank
        tg <- tg[is.finite(tg)]
        if (length(tg)) {
          ranked <- is.finite(hit$rank)
          effort[ranked] <- vapply(hit$rank[ranked], function(r) {
            (sum(tg < r) + 0.5 * sum(tg == r)) / length(tg)
          }, numeric(1))
        }
      }
      rows[[length(rows) + 1L]] <- data.frame(
        mine, map = id, learner = as.character(map$learner %||% id),
        grade = as.character(map$grade %||% NA), rank = hit$rank, place = hit$place,
        beats_effort = effort, stringsAsFactors = FALSE
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' The pre-registered numbers for a set of scored rows: counts each way, and
#' for ranked places the shares in the top half and top tenth, mean rank,
#' beats effort and Boyce. Shares are reported from ATLAS_E2_MIN_PLACES
#' ranked places; below, only counts.
atlas_e2_metrics <- function(scored, min_places = ATLAS_E2_MIN_PLACES) {
  ranked <- scored$rank[scored$place == "inside" & is.finite(scored$rank)]
  effort <- scored$beats_effort[scored$place == "inside" & is.finite(scored$beats_effort)]
  k <- length(ranked)
  show <- k >= min_places
  list(
    rows = nrow(scored), taxa = length(unique(scored$taxon)), ranked = k,
    outside_aoa = sum(scored$place == "outside_aoa"),
    beyond_reach = sum(scored$place == "beyond_reach"),
    no_map = sum(scored$place == "no_map"),
    top_half = if (show) mean(ranked >= 0.5), top_tenth = if (show) mean(ranked >= 0.9),
    mean_rank = if (show) mean(ranked),
    beats_effort = if (length(effort) >= min_places) mean(effort),
    boyce = if (show) atlas_tracker_boyce(ranked),
    tested = show
  )
}

#' A statistic of ranked rows, resampled over taxa: the point estimate and
#' its 95% percentile interval. stat(rows) gives one number; rows is every
#' scored row of the resampled taxa (a taxon drawn twice counts twice).
atlas_e2_bootstrap <- function(scored, stat, reps = ATLAS_E2_BOOTSTRAP, seed = 1L) {
  taxa <- unique(scored$taxon)
  by_taxon <- split(seq_len(nrow(scored)), factor(scored$taxon, levels = taxa))
  estimate <- stat(scored)
  set.seed(seed)
  draws <- vapply(seq_len(reps), function(i) {
    picked <- taxa[sample.int(length(taxa), length(taxa), replace = TRUE)]
    stat(scored[unlist(by_taxon[picked], use.names = FALSE), , drop = FALSE])
  }, numeric(1))
  draws <- draws[is.finite(draws)]
  interval <- if (length(draws)) unname(stats::quantile(draws, c(0.025, 0.975))) else c(NA_real_, NA_real_)
  list(estimate = estimate, low = interval[[1]], high = interval[[2]], reps = length(draws))
}

#' The share of a subset's ranked places at or above a rank.
atlas_e2_share <- function(rows, at = 0.5) {
  ranked <- rows$rank[rows$place == "inside" & is.finite(rows$rank)]
  if (!length(ranked)) NA_real_ else mean(ranked >= at)
}

#' The share of one group's ranked places in the top half minus another's,
#' both from the same rows: a function for atlas_e2_bootstrap.
atlas_e2_difference <- function(first, second, at = 0.5) {
  force(first)
  force(second)
  function(rows) atlas_e2_share(rows[first(rows), , drop = FALSE], at) -
    atlas_e2_share(rows[second(rows), , drop = FALSE], at)
}

#' The pre-registered test of claim C2 on hindcast rows: H2a strong models'
#' top-half share above 0.5, H2b strong above failed, H2c strong beats
#' effort above 0.5, each by its bootstrap lower bound. A grade with fewer
#' than ATLAS_E2_MIN_PLACES ranked places is reported, not tested.
atlas_e2_hypotheses <- function(scored, reps = ATLAS_E2_BOOTSTRAP, seed = 1L) {
  strong <- scored[scored$grade %in% "strong", , drop = FALSE]
  failed <- scored[scored$grade %in% "failed", , drop = FALSE]
  enough <- function(rows) sum(rows$place == "inside" & is.finite(rows$rank)) >= ATLAS_E2_MIN_PLACES
  test <- function(rows, stat, above) {
    if (!enough(rows)) return(list(tested = FALSE))
    b <- atlas_e2_bootstrap(rows, stat, reps = reps, seed = seed)
    c(b, list(tested = TRUE, holds = isTRUE(b$low > above)))
  }
  h2a <- test(strong, atlas_e2_share, 0.5)
  h2b <- if (enough(strong) && enough(failed)) {
    test(scored[scored$grade %in% c("strong", "failed"), , drop = FALSE],
         atlas_e2_difference(function(r) r$grade == "strong", function(r) r$grade == "failed"), 0)
  } else {
    list(tested = FALSE)
  }
  h2c <- test(strong, function(rows) {
    effort <- rows$beats_effort[rows$place == "inside" & is.finite(rows$beats_effort)]
    if (length(effort)) mean(effort) else NA_real_
  }, 0.5)
  supported <- isTRUE(h2a$holds) && isTRUE(h2b$holds) && isTRUE(h2c$holds)
  list(H2a = h2a, H2b = h2b, H2c = h2c, C2 = supported)
}

#' The pre-registered E6b test: strong models' top-half share minus the
#' distance kernel's on the same places and cells, by its bootstrap lower
#' bound. model_rows and kernel_rows are atlas_e2_score rows whose maps are
#' paired by taxon, map and cell (the kernel re-ranked on each model's own
#' cells, atlas_distance_paired_layers).
atlas_e2_paired <- function(model_rows, kernel_rows, grade = "strong",
                            reps = ATLAS_E2_BOOTSTRAP, seed = 1L) {
  key <- function(r) paste(r$taxon, r$map, r$cell, sep = "\x1f")
  models <- model_rows[model_rows$grade %in% grade, , drop = FALSE]
  kernel <- kernel_rows[match(key(models), key(kernel_rows)), , drop = FALSE]
  if (anyNA(kernel$taxon)) stop("every model row needs its kernel row on the same place and map", call. = FALSE)
  paired <- rbind(data.frame(models[, c("taxon", "map", "cell", "rank", "place")], arm = "model"),
                  data.frame(models[, c("taxon", "map", "cell")], rank = kernel$rank,
                             place = kernel$place, arm = "kernel"))
  stat <- atlas_e2_difference(function(r) r$arm == "model", function(r) r$arm == "kernel")
  if (sum(models$place == "inside" & is.finite(models$rank)) < ATLAS_E2_MIN_PLACES) {
    return(list(tested = FALSE))
  }
  b <- atlas_e2_bootstrap(paired, stat, reps = reps, seed = seed)
  c(b, list(tested = TRUE, holds = isTRUE(b$low > 0)))
}
