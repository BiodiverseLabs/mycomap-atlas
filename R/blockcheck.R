# Are the spatial blocks the right size?
#
# A held-out block stands in for ground a map has to predict without
# records. The test is honest when a held-out site is about as far from the
# training sites as a mapped cell is from the nearest survey site. If held-out
# sites sit much closer, cross-validation scores ground that is easier than
# what the map is asked about, and the scores flatter the map. If they sit
# much further, it scores ground harder than the map's.
#
# blockCV sets the block size from how far detections are spatially
# autocorrelated. Its estimate is beyond the 300 km ceiling for nearly every
# taxon, so the ceiling, not a measurement, sets the size. This check asks
# the question kNNDM asks (Milà et al. 2022; Linnenbrink et al. 2024): which
# block size makes the distances cross-validation tests at match the
# distances the map predicts at?
#
# For each taxon and each candidate size, every held-out site's distance to
# the nearest training site is set beside every mapped cell's distance to the
# nearest survey site. The gap between the two distributions is the
# Wasserstein distance: the mean gap between their quantiles, in km. The size
# with the smallest gap fits best, so long as the taxon still has detections
# in enough blocks to be scored.
#
# Three versions of the map's distances are kept:
#   all     every cell of the accessible area, as maps are drawn today
#   near    only cells within ATLAS_BLOCKCHECK_NEAR_KM of a survey site, a
#           rough stand-in for a map masked to its area of applicability
#   found   distances to the nearest detection rather than any site, for
#           held-out detections and for cells alike
#
# Nothing here fits a model or writes one. It writes one results file under
# data/block-studies/.

# Block sizes compared, in km.
ATLAS_BLOCKCHECK_SIZES <- c(50, 100, 150, 200, 300, 400)
# Cells of the accessible area the map's distances are measured from.
ATLAS_BLOCKCHECK_CELLS <- 20000
# How close a cell must be to a survey site to count as "near".
ATLAS_BLOCKCHECK_NEAR_KM <- 50
# Bands of detection sites, down to the small-model ensemble's.
ATLAS_BLOCKCHECK_BANDS <- c(5, 10, 20, 30, 50, 100, 200)

#' Distance from each query point to the nearest target point, in km.
#'
#' Brute force in chunks: at Atlas's sizes (tens of thousands of cells against
#' ten thousand sites) that takes seconds and needs no extra package.
atlas_nearest_km <- function(qx, qy, tx, ty, chunk = 500L) {
  if (!length(qx)) return(numeric())
  if (!length(tx)) return(rep(NA_real_, length(qx)))
  out <- numeric(length(qx))
  for (start in seq(1L, length(qx), by = chunk)) {
    rows <- start:min(length(qx), start + chunk - 1L)
    d2 <- outer(qx[rows], tx, "-")^2 + outer(qy[rows], ty, "-")^2
    nearest <- max.col(-d2, ties.method = "first")
    out[rows] <- sqrt(d2[cbind(seq_along(rows), nearest)])
  }
  out / 1000
}

#' Each held-out site's distance to the nearest site the fold trained on.
#'
#' which limits the held-out sites measured (all of them by default); the
#' training sites are always every site in the other folds, or only their
#' detections when to_detections is TRUE.
atlas_cv_distances <- function(training, folds, which = rep(TRUE, nrow(training)),
                               to_detections = FALSE) {
  unlist(lapply(sort(unique(folds)), function(fold) {
    held <- folds == fold & which
    train <- folds != fold
    if (isTRUE(to_detections)) train <- train & training$presence == 1L
    atlas_nearest_km(training$x[held], training$y[held], training$x[train], training$y[train])
  }), use.names = FALSE)
}

#' The Wasserstein distance between two samples: the mean absolute gap
#' between their quantiles, in the samples' units.
atlas_wasserstein <- function(a, b, n = 1000L) {
  a <- a[is.finite(a)]
  b <- b[is.finite(b)]
  if (!length(a) || !length(b)) return(NA_real_)
  probs <- (seq_len(n) - 0.5) / n
  mean(abs(stats::quantile(a, probs, names = FALSE) - stats::quantile(b, probs, names = FALSE)))
}

#' A sample of the accessible area's cell centres.
atlas_area_cells <- function(stack, area, n = ATLAS_BLOCKCHECK_CELLS, seed = 1L) {
  window <- terra::mask(terra::crop(stack[[1]], terra::ext(area)), area)
  inside <- terra::cells(window)
  if (!length(inside)) {
    stop("the accessible area holds no cells with data", call. = FALSE)
  }
  set.seed(seed)
  if (length(inside) > n) inside <- sort(inside[sample.int(length(inside), n)])
  xy <- terra::xyFromCell(window, inside)
  data.frame(x = xy[, 1], y = xy[, 2])
}

#' Compare every candidate block size for one taxon.
atlas_block_check_taxon <- function(name, fingerprint, points, stack,
                                    sizes = ATLAS_BLOCKCHECK_SIZES, grid = "draft",
                                    n_background = 10000, buffer_km = 500,
                                    min_blocks = ATLAS_MIN_BLOCKS,
                                    cells = ATLAS_BLOCKCHECK_CELLS,
                                    near_km = ATLAS_BLOCKCHECK_NEAR_KM) {
  started <- Sys.time()
  training <- atlas_build_training(name, grid, n_background = n_background,
                                   buffer_km = buffer_km, write = FALSE, quiet = TRUE,
                                   points = points, stack = stack, fingerprint = fingerprint)
  presences <- sum(training$presence == 1L)
  seed <- attr(training, "seed")
  # Taxa the full models refuse are scored as the small-model ensemble is:
  # three folds, of which every one needs a detection.
  sparse <- presences < 20L
  folds_k <- if (sparse) 3L else 5L
  needed <- if (sparse) 3L else min_blocks
  production <- if (sparse) {
    list(block_km = 100, source = "ensemble design")
  } else {
    atlas_block_size(training, seed = seed)[c("block_km", "range_km", "source")]
  }

  occupied <- training[training$presence == 1L, , drop = FALSE]
  area <- atlas_accessible_area(occupied$x, occupied$y, buffer_km)
  grid_cells <- atlas_area_cells(stack, area, n = cells, seed = seed)
  to_site <- atlas_nearest_km(grid_cells$x, grid_cells$y, training$x, training$y)
  to_found <- atlas_nearest_km(grid_cells$x, grid_cells$y, occupied$x, occupied$y)
  near <- to_site <= near_km

  arms <- lapply(sizes, function(size) {
    blocks <- atlas_presence_blocks(training, size)
    folds <- atlas_spatial_folds(training$x, training$y, k = folds_k, block_km = size,
                                 seed = seed, presence = training$presence)
    cv <- atlas_cv_distances(training, folds)
    cv_found <- atlas_cv_distances(training, folds, which = training$presence == 1L,
                                   to_detections = TRUE)
    list(
      arm = paste0(size, " km"), block_km = size, blocks = blocks,
      folds = length(unique(folds)), scorable = blocks >= needed,
      w_all = round(atlas_wasserstein(cv, to_site), 1),
      w_near = round(atlas_wasserstein(cv, to_site[near]), 1),
      w_found = round(atlas_wasserstein(cv_found, to_found), 1),
      cv_median_km = round(stats::median(cv), 1),
      cv_found_median_km = round(stats::median(cv_found), 1)
    )
  })
  list(
    taxon = name, status = "scored", presences = presences,
    band = atlas_presence_band(presences, ATLAS_BLOCKCHECK_BANDS),
    sparse = sparse, production_block_km = production$block_km,
    production_source = production$source,
    production_range_km = production$range_km %||% NA_real_,
    map_median_km = round(stats::median(to_site), 1),
    map_near_share = round(mean(near), 3),
    map_found_median_km = round(stats::median(to_found), 1),
    arms = arms,
    seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  )
}

#' Which block size fits each band best, and how far each size is off.
#'
#' For each band and size: taxa, the share still scorable, the mean gap from
#' the map's distances (all cells, near cells, detections) and the share of
#' taxa for which the size had the smallest gap among their scorable sizes.
atlas_block_check_summary <- function(rows, baseline = NULL) {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  if (!length(scored)) return(data.frame())
  long <- do.call(rbind, lapply(scored, function(r) do.call(rbind, lapply(r$arms, function(a) {
    data.frame(taxon = r$taxon, band = r$band, size = a$block_km, scorable = isTRUE(a$scorable),
               w_all = as.numeric(a$w_all %||% NA), w_near = as.numeric(a$w_near %||% NA),
               w_found = as.numeric(a$w_found %||% NA), stringsAsFactors = FALSE)
  }))))
  best_for <- function(column) {
    ok <- long[long$scorable & is.finite(long[[column]]), , drop = FALSE]
    best <- stats::ave(ok[[column]], ok$taxon, FUN = min)
    paste(ok$taxon, ok$size)[ok[[column]] == best]
  }
  best <- lapply(c(all = "w_all", near = "w_near", found = "w_found"), best_for)
  bands <- c(unique(long$band[order(as.numeric(sub("[^0-9].*$", "", long$band)))]), "all")
  out <- do.call(rbind, lapply(bands, function(b) {
    in_band <- if (b == "all") long else long[long$band == b, , drop = FALSE]
    do.call(rbind, lapply(sort(unique(long$size)), function(s) {
      x <- in_band[in_band$size == s, , drop = FALSE]
      keys <- paste(x$taxon, x$size)
      data.frame(
        band = b, size_km = s, taxa = nrow(x), scorable = round(mean(x$scorable), 2),
        w_all = round(mean(x$w_all, na.rm = TRUE), 1),
        w_near = round(mean(x$w_near, na.rm = TRUE), 1),
        w_found = round(mean(x$w_found, na.rm = TRUE), 1),
        best_all = round(mean(keys %in% best$all), 2),
        best_near = round(mean(keys %in% best$near), 2),
        best_found = round(mean(keys %in% best$found), 2),
        stringsAsFactors = FALSE
      )
    }))
  }))
  rownames(out) <- NULL
  out
}

#' Run the block-size check over a stratified sample of real taxa, from the
#' small-model ensemble's (5 sites) up.
atlas_block_study <- function(grid = "draft", per_band = 25, workers = 1L, seed = 1L,
                              sizes = ATLAS_BLOCKCHECK_SIZES, min_presences = 5,
                              n_background = 10000, buffer_km = 500, quiet = FALSE,
                              occurrences = NULL, points = NULL, stack = NULL, taxa = NULL) {
  occurrences <- occurrences %||% atlas_read_occurrences()
  points <- points %||% atlas_occurrence_points(occurrences, grid)
  candidates <- atlas_batch_candidates(points, min_presences, taxa = taxa)
  sample <- atlas_sweep_sample(candidates, per_band = per_band, seed = seed,
                               breaks = ATLAS_BLOCKCHECK_BANDS)
  fingerprints <- atlas_fingerprints_for(occurrences, sample$scientific_name)
  args <- list(sizes = sizes, grid = grid, n_background = n_background, buffer_km = buffer_km)
  settings <- c(args, list(per_band = per_band, seed = seed, cells = ATLAS_BLOCKCHECK_CELLS,
                           near_km = ATLAS_BLOCKCHECK_NEAR_KM, min_blocks = ATLAS_MIN_BLOCKS,
                           design = atlas_design()))
  atlas_run_study(
    kind = "block-studies", file_prefix = "blocks", taxon_fn = "atlas_block_check_taxon",
    sample = sample, fingerprints = fingerprints, args = args, settings = settings,
    baseline = NULL, grid = grid, workers = workers, points = points, stack = stack,
    quiet = quiet, summarise = atlas_block_check_summary,
    detail = function(arm) paste0(arm$block_km, ":", arm$w_all),
    opening = paste0(nrow(sample), " taxa sampled from ", nrow(candidates), " with ",
                     min_presences, "+ detection sites (", atlas_band_counts(sample),
                     "); block sizes ", paste(sizes, collapse = ", "), " km")
  )
}
