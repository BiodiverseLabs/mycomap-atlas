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
#   place        one taxon in one 5 km square (ATLAS_E2_PLACE_KM, on the
#                model grid's coordinates, whatever the grid's resolution):
#                several finds of a taxon in a square count once, scored at
#                the first of them
#   rank         the place's rank on the map, 0..1 within the map's area of
#                applicability (chance: half the places in the top half)
#   top half, top tenth   shares of places at rank >= 0.5 and >= 0.9
#   Boyce        continuous Boyce index of the places' ranks, pooled
#   beats effort the place's rank against the ranks, on the same map, of
#                where every other taxon's test places landed (ties half);
#                0.5 is no better than knowing where people collect
# Kept apart and counted, never ranked: places outside a map's area of
# applicability or beyond its reach, places of taxa with no map, places
# under a name the release does not know, and finds off the grid. The
# hypotheses read the per-model rows only; a combined map is scored for
# E15, not for C2. Intervals are 95% percentile intervals from bootstrap
# resamples of taxa, since places cluster within taxa.
#
# Built on the tracker's lookup and Boyce code (R/tracker.R), so the
# hindcast and the prospective tracker (E3) read a map the same way.

# A place is a square of Atlas's survey-site spacing, and a place further
# than that from every training record of its taxon is new (as the tracker
# calls a new site). Both are ATLAS_SITE_KM (R/sites.R, sourced after this
# file, so the number is written here and a test holds them equal).
ATLAS_E2_PLACE_KM <- 5
ATLAS_E2_NEW_KM <- 5
# Distance bands to the nearest training record of the taxon, in km. A band
# includes its upper edge, so a place exactly 5 km away is in "0-5" and
# known, as it is not new.
ATLAS_E2_BANDS_KM <- c(5, 25, 100, 500)
# Fewest ranked places a grade needs before it is tested, and fewest taxa an
# interval over taxa needs.
ATLAS_E2_MIN_PLACES <- 30L
ATLAS_E2_MIN_TAXA <- 2L
ATLAS_E2_BOOTSTRAP <- 10000L

#' The distance band of a distance in km: "0-5", "5-25", "25-100",
#' "100-500" or "500+".
atlas_e2_band <- function(km) {
  breaks <- c(0, ATLAS_E2_BANDS_KM)
  labels <- c(paste0(utils::head(breaks, -1), "-", breaks[-1]), paste0(utils::tail(breaks, 1), "+"))
  index <- pmax(1L, findInterval(km, breaks, left.open = TRUE))
  ifelse(is.na(km), NA_character_, labels[index])
}

#' The test finds in a pull: records first validated after the cutoff (with
#' observed_after, also observed after it), each with the taxon it is
#' modelled under, its point on the model grid, and a reason when it is kept
#' apart: "undated" (no first-validation date, so on neither side of the
#' cutoff) or "off_grid" (no usable coordinate). Training records are the
#' rest that are dated: first validated on or before the cutoff. Counts of
#' every reason are kept in attr(finds, "kept_apart"); nothing is dropped
#' silently.
atlas_e2_split <- function(pull, cutoff, observed_after = FALSE, grid = "draft") {
  if (!ATLAS_FIRST_GREEN_FIELD %in% names(pull)) {
    stop("the pull has no ", ATLAS_FIRST_GREEN_FIELD, " column", call. = FALSE)
  }
  green <- as.character(pull[[ATLAS_FIRST_GREEN_FIELD]])
  dated <- !is.na(green) & nzchar(green)
  cutoff <- as.character(cutoff)
  placed <- atlas_tracker_place(pull$latitude, pull$longitude, grid)
  located <- is.finite(placed$x) & is.finite(placed$y)
  after <- dated & green > cutoff
  test <- after
  if (isTRUE(observed_after)) {
    observed <- substr(as.character(pull$observed_on), 1, 10)
    test <- after & !is.na(observed) & observed > cutoff
  }
  reason <- ifelse(!dated, "undated", ifelse(!located, "off_grid", NA_character_))
  keep <- test | !dated
  finds <- data.frame(taxon = as.character(pull$scientific_name), x = placed$x, y = placed$y,
                      first_green_on = green, kept_apart = reason,
                      stringsAsFactors = FALSE)[keep, , drop = FALSE]
  finds <- finds[order(finds$first_green_on, na.last = TRUE), , drop = FALSE]
  training <- data.frame(taxon = as.character(pull$scientific_name), x = placed$x, y = placed$y,
                         stringsAsFactors = FALSE)[dated & !after & located, , drop = FALSE]
  rownames(finds) <- NULL
  rownames(training) <- NULL
  counts <- as.list(table(factor(finds$kept_apart[!is.na(finds$kept_apart)],
                                 levels = c("undated", "off_grid"))))
  list(finds = structure(finds, kept_apart = counts), training = training)
}

#' The 5 km square a point falls in, as a key.
atlas_e2_square <- function(x, y, km = ATLAS_E2_PLACE_KM) {
  paste(floor(x / (km * 1000)), floor(y / (km * 1000)), sep = ":")
}

#' The test places: each taxon's finds collapsed to one row per 5 km square.
#'
#' finds has taxon and x, y (the find's own point on the model grid's
#' coordinates), in the order they count (the first find of a place is where
#' it is scored), and optionally observed_after (also observed after the
#' cutoff). training has taxon, x and y of the records the hindcast was
#' fitted on. A place's distance is the smallest of its finds' own
#' distances to the taxon's nearest training record, so it is new only when
#' every one of its finds is. Finds with no point are counted apart
#' (attr(, "off_grid")), never merged into a place.
atlas_e2_places <- function(finds, training) {
  located <- is.finite(finds$x) & is.finite(finds$y)
  if ("kept_apart" %in% names(finds)) located <- located & is.na(finds$kept_apart)
  off_grid <- sum(!located)
  finds <- finds[located, , drop = FALSE]
  empty <- data.frame(taxon = character(), place = character(), x = numeric(), y = numeric(),
                      finds = integer(), observed_after = logical(), known_km = numeric(),
                      new_place = logical(), band = character(), stringsAsFactors = FALSE)
  if (!nrow(finds)) return(structure(empty, off_grid = off_grid))
  finds$known_km <- NA_real_
  for (taxon in unique(finds$taxon)) {
    mine <- finds$taxon == taxon
    known <- training$taxon == taxon
    if (any(known)) {
      finds$known_km[mine] <- atlas_nearest_km(finds$x[mine], finds$y[mine],
                                               training$x[known], training$y[known])
    }
  }
  observed <- if ("observed_after" %in% names(finds)) finds$observed_after %in% TRUE else rep(FALSE, nrow(finds))
  key <- paste(finds$taxon, atlas_e2_square(finds$x, finds$y), sep = "\x1f")
  group <- factor(key, levels = unique(key))
  first <- !duplicated(key)
  nearest <- tapply(finds$known_km, group, function(d) if (all(is.na(d))) NA_real_ else min(d, na.rm = TRUE))
  places <- data.frame(
    taxon = finds$taxon[first], place = atlas_e2_square(finds$x, finds$y)[first],
    x = finds$x[first], y = finds$y[first],
    finds = as.integer(table(group)), observed_after = as.logical(tapply(observed, group, any)),
    known_km = as.numeric(nearest), stringsAsFactors = FALSE
  )
  # A taxon with no training record has no known place: every place is new,
  # as the tracker counts it (such a taxon has no model either).
  places$new_place <- is.na(places$known_km) | places$known_km > ATLAS_E2_NEW_KM
  places$band <- atlas_e2_band(places$known_km)
  rownames(places) <- NULL
  structure(places, off_grid = off_grid)
}

#' Score the places on every map of their taxa.
#'
#' maps_for(taxon) gives a named list of maps, each a list with layers (as
#' atlas_tracker_layers makes them: raster, rank, outside), grade, and
#' optionally learner, kind ("model", the default, or "combined" for the
#' map a visitor sees) and known (a combined map's reach, per cell). It gives
#' NULL or an empty list when the taxon has no map. known_names, when given,
#' are the names the release knows: a place under any other name is
#' "unknown_name", not "no_map". One row per place and map: rank (NA unless
#' inside), place class ("inside", "outside_aoa", "beyond_reach", "no_map",
#' "unknown_name"), and beats_effort for ranked places.
atlas_e2_score <- function(places, maps_for, known_names = NULL) {
  if (!nrow(places)) {
    return(structure(data.frame(places, map = character(), learner = character(), kind = character(),
                                grade = character(), rank = numeric(), class = character(),
                                beats_effort = numeric(), stringsAsFactors = FALSE),
                     off_grid = attr(places, "off_grid") %||% 0L))
  }
  rows <- list()
  apart <- function(mine, class) {
    data.frame(mine, map = NA_character_, learner = NA_character_, kind = NA_character_,
               grade = NA_character_, rank = NA_real_, class = class, beats_effort = NA_real_,
               stringsAsFactors = FALSE)
  }
  for (taxon in unique(places$taxon)) {
    mine <- places[places$taxon == taxon, , drop = FALSE]
    if (!is.null(known_names) && !taxon %in% known_names) {
      rows[[length(rows) + 1L]] <- apart(mine, "unknown_name")
      next
    }
    maps <- maps_for(taxon)
    if (!length(maps)) {
      rows[[length(rows) + 1L]] <- apart(mine, "no_map")
      next
    }
    others <- places[places$taxon != taxon, , drop = FALSE]
    for (id in names(maps)) {
      map <- maps[[id]]
      hit <- atlas_tracker_lookup(map$layers, mine$x, mine$y, known = map$known)
      effort <- rep(NA_real_, nrow(mine))
      if (nrow(others)) {
        tg <- atlas_tracker_lookup(map$layers, others$x, others$y, known = map$known)$rank
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
        kind = as.character(map$kind %||% "model"), grade = as.character(map$grade %||% NA),
        rank = hit$rank, class = hit$place, beats_effort = effort, stringsAsFactors = FALSE
      )
    }
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  structure(out, off_grid = attr(places, "off_grid") %||% 0L)
}

#' Ranked rows: inside a map's area of applicability, with a rank.
atlas_e2_ranked <- function(rows) rows$class %in% "inside" & is.finite(rows$rank)

#' Distinct places among rows: one per taxon and 5 km square, however many
#' maps scored it.
atlas_e2_place_count <- function(rows) length(unique(paste(rows$taxon, rows$place, sep = "\x1f")))

#' The pre-registered numbers for a set of scored rows: counts each way, and
#' for ranked places the shares in the top half and top tenth, mean rank,
#' beats effort and Boyce. The unit of a share is a place on a map: a place
#' ranked by two maps counts on each. Shares are reported from
#' ATLAS_E2_MIN_PLACES distinct ranked places, Boyce from the tracker's
#' ATLAS_TRACKER_MIN_BOYCE; below, only counts.
atlas_e2_metrics <- function(scored, min_places = ATLAS_E2_MIN_PLACES) {
  inside <- scored[atlas_e2_ranked(scored), , drop = FALSE]
  ranked <- inside$rank
  effort <- inside$beats_effort[is.finite(inside$beats_effort)]
  places <- atlas_e2_place_count(inside)
  show <- places >= min_places
  count <- function(class) sum(scored$class %in% class)
  list(
    rows = nrow(scored), taxa = length(unique(scored$taxon)), ranked = length(ranked),
    ranked_places = places, outside_aoa = count("outside_aoa"), beyond_reach = count("beyond_reach"),
    no_map = count("no_map"), unknown_name = count("unknown_name"),
    off_grid = attr(scored, "off_grid") %||% 0L,
    top_half = if (show) mean(ranked >= 0.5), top_tenth = if (show) mean(ranked >= 0.9),
    mean_rank = if (show) mean(ranked),
    beats_effort = if (show && length(effort)) mean(effort),
    boyce = if (places >= ATLAS_TRACKER_MIN_BOYCE) atlas_tracker_boyce(ranked),
    tested = show
  )
}

#' A statistic of scored rows, resampled over taxa: the point estimate and
#' its 95% percentile interval. stat(rows) gives one number; rows is every
#' row of the resampled taxa (a taxon drawn twice counts twice). With
#' strata (a named list of row filters), taxa are resampled within each
#' stratum separately, so a difference between two groups keeps each group's
#' own taxa. Fewer than ATLAS_E2_MIN_TAXA taxa in any stratum give no
#' interval. The caller's random number stream is left as it was, and
#' resamples whose statistic cannot be computed are counted (dropped).
atlas_e2_bootstrap <- function(scored, stat, reps = ATLAS_E2_BOOTSTRAP, seed = 1L, strata = NULL) {
  stream <- atlas_rng_state()
  on.exit(atlas_rng_restore(stream), add = TRUE)
  strata <- strata %||% list(all = function(rows) rep(TRUE, nrow(rows)))
  groups <- lapply(strata, function(keep) scored[keep(scored), , drop = FALSE])
  taxa <- lapply(groups, function(rows) unique(rows$taxon))
  estimate <- stat(scored)
  n_taxa <- length(unique(scored$taxon))
  if (any(lengths(taxa) < ATLAS_E2_MIN_TAXA)) {
    return(list(estimate = estimate, low = NA_real_, high = NA_real_, reps = 0L, dropped = 0L,
                n_taxa = n_taxa))
  }
  by_taxon <- lapply(seq_along(groups), function(g) {
    split(seq_len(nrow(groups[[g]])), factor(groups[[g]]$taxon, levels = taxa[[g]]))
  })
  set.seed(seed)
  draws <- vapply(seq_len(reps), function(i) {
    resampled <- do.call(rbind, lapply(seq_along(groups), function(g) {
      picked <- taxa[[g]][sample.int(length(taxa[[g]]), length(taxa[[g]]), replace = TRUE)]
      groups[[g]][unlist(by_taxon[[g]][picked], use.names = FALSE), , drop = FALSE]
    }))
    stat(resampled)
  }, numeric(1))
  finite <- draws[is.finite(draws)]
  interval <- if (length(finite)) unname(stats::quantile(finite, c(0.025, 0.975))) else c(NA_real_, NA_real_)
  list(estimate = estimate, low = interval[[1]], high = interval[[2]], reps = length(finite),
       dropped = length(draws) - length(finite), n_taxa = n_taxa)
}

#' The share of rows' ranked places at or above a rank.
atlas_e2_share <- function(rows, at = 0.5) {
  ranked <- rows$rank[atlas_e2_ranked(rows)]
  if (!length(ranked)) NA_real_ else mean(ranked >= at)
}

#' One group's top-half share minus another's, both from the same rows: a
#' function for atlas_e2_bootstrap.
atlas_e2_difference <- function(first, second, at = 0.5) {
  force(first)
  force(second)
  function(rows) atlas_e2_share(rows[first(rows), , drop = FALSE], at) -
    atlas_e2_share(rows[second(rows), , drop = FALSE], at)
}

#' The pre-registered test of claim C2, on the per-model rows only: H2a
#' strong models' top-half share above 0.5, H2b strong above failed, H2c
#' strong beats effort above 0.5, each by its bootstrap lower bound. A grade
#' with fewer than ATLAS_E2_MIN_PLACES distinct ranked places is reported,
#' not tested.
atlas_e2_hypotheses <- function(scored, reps = ATLAS_E2_BOOTSTRAP, seed = 1L) {
  models <- scored[scored$kind %in% "model", , drop = FALSE]
  strong <- models[models$grade %in% "strong", , drop = FALSE]
  failed <- models[models$grade %in% "failed", , drop = FALSE]
  enough <- function(rows) atlas_e2_place_count(rows[atlas_e2_ranked(rows), , drop = FALSE]) >= ATLAS_E2_MIN_PLACES
  untested <- function(rows) list(tested = FALSE, n_taxa = length(unique(rows$taxon)))
  test <- function(rows, stat, above, strata = NULL) {
    if (!enough(rows)) return(untested(rows))
    b <- atlas_e2_bootstrap(rows, stat, reps = reps, seed = seed, strata = strata)
    c(b, list(tested = is.finite(b$low), holds = isTRUE(b$low > above)))
  }
  h2a <- test(strong, atlas_e2_share, 0.5)
  # Strong and failed maps are resampled each over their own taxa.
  is_strong <- function(r) r$grade == "strong"
  is_failed <- function(r) r$grade == "failed"
  h2b <- if (enough(strong) && enough(failed)) {
    test(models[models$grade %in% c("strong", "failed"), , drop = FALSE],
         atlas_e2_difference(is_strong, is_failed), 0,
         strata = list(strong = is_strong, failed = is_failed))
  } else {
    untested(failed)
  }
  h2c <- test(strong, function(rows) {
    effort <- rows$beats_effort[atlas_e2_ranked(rows) & is.finite(rows$beats_effort)]
    if (length(effort)) mean(effort) else NA_real_
  }, 0.5)
  supported <- isTRUE(h2a$holds) && isTRUE(h2b$holds) && isTRUE(h2c$holds)
  list(H2a = h2a, H2b = h2b, H2c = h2c, C2 = supported)
}

#' The pre-registered E6b test: strong models' top-half share minus the
#' distance kernel's, on identical places. model_rows and kernel_rows are
#' atlas_e2_score rows whose maps pair by taxon, map and place (the kernel
#' ranked again on each model's own cells, atlas_distance_paired_layers);
#' only places ranked on both enter, and the bound is the bootstrap's lower.
atlas_e2_paired <- function(model_rows, kernel_rows, grade = "strong",
                            reps = ATLAS_E2_BOOTSTRAP, seed = 1L) {
  key <- function(r) paste(r$taxon, r$map, r$place, sep = "\x1f")
  models <- model_rows[model_rows$kind %in% "model" & model_rows$grade %in% grade, , drop = FALSE]
  kernel <- kernel_rows[match(key(models), key(kernel_rows)), , drop = FALSE]
  if (anyNA(kernel$taxon)) stop("every model row needs its kernel row on the same place and map", call. = FALSE)
  both <- atlas_e2_ranked(models) & atlas_e2_ranked(kernel)
  models <- models[both, , drop = FALSE]
  kernel <- kernel[both, , drop = FALSE]
  if (atlas_e2_place_count(models) < ATLAS_E2_MIN_PLACES) {
    return(list(tested = FALSE, n_taxa = length(unique(models$taxon))))
  }
  columns <- c("taxon", "map", "place", "rank", "class")
  paired <- rbind(data.frame(models[, columns], arm = "model", stringsAsFactors = FALSE),
                  data.frame(kernel[, columns], arm = "kernel", stringsAsFactors = FALSE))
  stat <- atlas_e2_difference(function(r) r$arm == "model", function(r) r$arm == "kernel")
  b <- atlas_e2_bootstrap(paired, stat, reps = reps, seed = seed)
  c(b, list(tested = is.finite(b$low), holds = isTRUE(b$low > 0), places = atlas_e2_place_count(models)))
}
