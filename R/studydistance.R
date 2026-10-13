# The distance-only baseline (paper E6b): how well does a map do that knows
# nothing but how far a place is from the taxon's known sites?
#
# A habitat map that ranks later finds well may only be saying "near where it
# was found before". Strong maps have to beat that to claim they learned
# habitat (Bahn & McGill 2007). So each taxon also gets a kernel map: the sum
# of Gaussian bumps over its detection survey sites (5 km thinned, each counted
# once), with one bandwidth chosen per taxon from ATLAS_DISTANCE_BANDWIDTHS_KM
# by blocked AUC against its non-detection sites, on the folds production
# scores the taxon on (same blocks, ties to the smaller bandwidth). Nothing
# but the training data is used to choose it.
#
# The kernel map covers the taxon's accessible area (its sites buffered by
# 500 km), the reach a production map covers, on the same grid. It is kept in
# log units, so cells far from every site still rank by their distance
# instead of tying at zero.
#
# Scoring is not done here. The hindcast's E2 scorer scores it, row for row
# with the habitat maps: for each of a taxon's models the kernel is ranked
# again over that model's own area-of-applicability cells
# (atlas_distance_paired_layers), so both are scored on the same places and
# the same cells (pre-registration: docs/experiments, E6b).
#
# Nothing here writes a model or a release. It writes kernel rasters and one
# results file under the study's output directory; coordinates never leave
# this machine except as rasters in a private study prefix.

ATLAS_DISTANCE_BANDWIDTHS_KM <- c(5, 10, 25, 50, 100, 200, 400)
# The coordinates a kernel reads, as predictor columns: the cross-validation
# loop hands a scorer predictors only, never x and y.
ATLAS_DISTANCE_COLUMNS <- c("kx", "ky")
# Matrix cells per chunk when summing kernels: bounds memory, whatever the
# number of sites.
ATLAS_DISTANCE_CHUNK_CELLS <- 2e6

#' The log of a sum of Gaussian kernels: at each query point, log of
#' sum_i exp(-d_i^2 / (2 h^2)) over the sites, d in metres and h the
#' bandwidth in km. Computed stably, so a query far from every site gets a
#' finite value that still falls with distance.
atlas_distance_log_kernel <- function(px, py, qx, qy, bandwidth_km,
                                      chunk_cells = ATLAS_DISTANCE_CHUNK_CELLS) {
  if (!length(px)) stop("a kernel needs at least one site", call. = FALSE)
  if (!is.finite(bandwidth_km) || bandwidth_km <= 0) {
    stop("a kernel bandwidth must be a positive number of km", call. = FALSE)
  }
  out <- numeric(length(qx))
  if (!length(qx)) return(out)
  two_h2 <- 2 * (bandwidth_km * 1000)^2
  chunk <- max(1L, floor(chunk_cells / length(px)))
  for (start in seq.int(1L, length(qx), by = chunk)) {
    rows <- seq.int(start, min(start + chunk - 1L, length(qx)))
    exponent <- -(outer(qx[rows], px, "-")^2 + outer(qy[rows], py, "-")^2) / two_h2
    top <- exponent[cbind(seq_along(rows), max.col(exponent, ties.method = "first"))]
    out[rows] <- top + log(rowSums(exp(exponent - top)))
  }
  out
}

#' A kernel "fitted" on a training table: its detection sites and bandwidth.
atlas_distance_fit <- function(train, bandwidth_km) {
  found <- train$presence == 1L
  list(x = train[[ATLAS_DISTANCE_COLUMNS[[1]]]][found],
       y = train[[ATLAS_DISTANCE_COLUMNS[[2]]]][found],
       bandwidth_km = bandwidth_km)
}

#' A kernel's value at new points, from their kx and ky columns.
atlas_distance_score <- function(model, newdata) {
  atlas_distance_log_kernel(model$x, model$y, newdata[[ATLAS_DISTANCE_COLUMNS[[1]]]],
                            newdata[[ATLAS_DISTANCE_COLUMNS[[2]]]], model$bandwidth_km)
}

#' A training table as the kernel sees it: presence, cell, x, y and the
#' coordinates again as its only predictors.
atlas_distance_table <- function(training) {
  out <- training[, c("presence", "cell", "x", "y"), drop = FALSE]
  out[[ATLAS_DISTANCE_COLUMNS[[1]]]] <- training$x
  out[[ATLAS_DISTANCE_COLUMNS[[2]]]] <- training$y
  out
}

#' Cross-validate every bandwidth on the folds and choose one: the best mean
#' blocked AUC, ties to the smaller bandwidth. Returns the chosen bandwidth
#' (NA when no bandwidth could be scored) and the table of every candidate.
atlas_distance_choose <- function(training, folds, bandwidths = ATLAS_DISTANCE_BANDWIDTHS_KM) {
  table <- atlas_distance_table(training)
  bandwidths <- sort(unique(as.numeric(bandwidths)))
  tried <- do.call(rbind, lapply(bandwidths, function(h) {
    scores <- atlas_cross_validate(table, folds,
                                   fit = function(train) atlas_distance_fit(train, h),
                                   score = atlas_distance_score, effort_at = NULL)
    auc <- mean(scores$auc, na.rm = TRUE)
    data.frame(bandwidth_km = h, auc = if (is.finite(auc)) auc else NA_real_,
               boyce = atlas_pooled_boyce(scores), folds_scored = sum(is.finite(scores$auc)))
  }))
  scored <- is.finite(tried$auc)
  chosen <- if (any(scored)) {
    best <- max(tried$auc[scored])
    min(tried$bandwidth_km[scored & tried$auc >= best - 1e-12])
  } else {
    NA_real_
  }
  list(bandwidth_km = chosen, tried = tried)
}

#' The training table and folds production scores a taxon on, rebuilt from
#' the pull, as atlas_fit_taxon builds them (R/fit.R). Copied, not shared:
#' the fit path stays frozen until the full-view refresh has run (Atlas
#' coordinator, 2026-10-13). A drift in either copy shows up as detection
#' sites that differ from the release's own count, which the study checks.
#'
#' The design is the full models' (five folds, blocks sized by the
#' variogram, at least five blocks with a detection) when the taxon has
#' enough sites and blocks for them, else the small-model ensembles' (three
#' folds of 100 km blocks, at least three). NULL design when neither fits.
atlas_distance_inputs <- function(name, points, stack, fingerprint, grid = "draft",
                                  n_background = 10000, buffer_km = 500,
                                  thin_km = ATLAS_SITE_KM) {
  training <- atlas_build_training(
    name, grid, n_background = n_background, buffer_km = buffer_km, write = FALSE,
    quiet = TRUE, points = points, stack = stack, fingerprint = fingerprint, thin_km = thin_km
  )
  presences <- sum(training$presence == 1L)
  seed <- attr(training, "seed")
  full <- atlas_algorithm_design(atlas_algorithm("maxnet"))
  small <- atlas_algorithm_design(atlas_algorithm("esm"))
  candidates <- list()
  if (presences >= atlas_algorithm_min(atlas_algorithm("maxnet"), 20)) {
    candidates$full <- full
  }
  if (presences >= atlas_algorithm_min(atlas_algorithm("esm"), 3)) {
    candidates$small <- small
  }
  for (kind in names(candidates)) {
    design <- candidates[[kind]]
    block_km <- if (atlas_block_is_auto(design$block_km)) {
      atlas_block_size(training, seed = seed)$block_km
    } else {
      as.numeric(design$block_km)
    }
    blocks <- atlas_presence_blocks(training, block_km)
    if (blocks < design$min_blocks) next
    folds <- atlas_spatial_folds(training$x, training$y, k = design$folds, block_km = block_km,
                                 seed = seed, presence = training$presence)
    return(list(training = training, folds = folds, design = kind, block_km = block_km,
                blocks = blocks, presences = presences, seed = seed))
  }
  list(training = training, folds = NULL, design = NA_character_, block_km = NA_real_,
       blocks = NA_integer_, presences = presences, seed = seed)
}

#' The kernel over a taxon's accessible area: one raster on the stack's grid,
#' with a value in every cell of the area that the grid has data for (its
#' first layer), NA elsewhere.
atlas_distance_raster <- function(model, stack, area) {
  window <- terra::mask(terra::crop(stack[[1]], terra::ext(area)), area)
  cells <- terra::cells(window)
  out <- terra::rast(window)
  names(out) <- "kernel"
  values <- rep(NA_real_, terra::ncell(out))
  if (length(cells)) {
    xy <- terra::xyFromCell(window, cells)
    values[cells] <- atlas_distance_log_kernel(model$x, model$y, xy[, 1], xy[, 2],
                                               model$bandwidth_km)
  }
  terra::values(out) <- values
  out
}

#' The kernel as one model's scorer sees that model: ranked again over the
#' model's own area-of-applicability cells (where its rank is finite), with
#' the model's own outside flags, so a find lands in the same place class on
#' both and only the ranking differs. Same shape as atlas_tracker_layers.
#'
#' The kernel raster must share the model's grid; it is extended or cropped
#' to the model's extent, never resampled.
atlas_distance_paired_layers <- function(kernel, model_layers) {
  target <- model_layers$raster
  aligned <- terra::crop(terra::extend(kernel, target), target)
  if (!isTRUE(terra::compareGeom(aligned, target[[1]], stopOnError = FALSE))) {
    stop("the kernel and the model are not on one grid", call. = FALSE)
  }
  values <- terra::values(aligned, mat = FALSE)
  inside <- is.finite(model_layers$rank)
  rank <- rep(NA_real_, length(values))
  rank[inside] <- atlas_rank_scale(values[inside])
  layers <- terra::rast(target, nlyrs = 2)
  terra::values(layers) <- cbind(rank, model_layers$outside)
  names(layers) <- c("rank", "outside")
  list(raster = layers, rank = rank, outside = model_layers$outside)
}

#' The kernel ranked over its own reach: the secondary score's map.
atlas_distance_own_layers <- function(kernel) {
  atlas_tracker_layers(kernel)
}

#' Where a taxon's kernel raster is written in a study's output directory.
atlas_distance_raster_path <- function(out_dir, name) {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  file.path(out_dir, "kernels", paste0(slug, ".tif"))
}

#' One taxon of the study: rebuild its training table and folds, choose the
#' bandwidth, and write its kernel map. The row carries counts and scores,
#' never a coordinate.
#'
#' records holds, by taxon, what the release recorded about the folds the
#' taxon was scored on (atlas_distance_record). A rebuild that differs from
#' it in any way (atlas_distance_differences) is refused as "mismatch", since
#' the kernel would then be chosen on other data or other folds than the
#' models it is compared with.
atlas_distance_taxon <- function(name, fingerprint, points, stack, grid = "draft",
                                 out_dir, bandwidths = ATLAS_DISTANCE_BANDWIDTHS_KM,
                                 n_background = 10000, buffer_km = 500, records = NULL) {
  started <- Sys.time()
  seconds <- function() round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  inputs <- atlas_distance_inputs(name, points, stack, fingerprint, grid = grid,
                                  n_background = n_background, buffer_km = buffer_km)
  row <- list(taxon = name, presences = inputs$presences,
              band = atlas_presence_band(inputs$presences, ATLAS_DISTANCE_BANDS),
              design = inputs$design, block_km = inputs$block_km, blocks = inputs$blocks)
  record <- records[[name]]
  if (!is.null(record)) {
    differs <- atlas_distance_differences(inputs, record, fingerprint)
    if (length(differs)) {
      return(c(row, list(status = "mismatch", differs = as.list(differs), seconds = seconds())))
    }
  }
  if (is.null(inputs$folds)) {
    return(c(row, list(status = "refused", seconds = seconds())))
  }
  choice <- atlas_distance_choose(inputs$training, inputs$folds, bandwidths)
  row$bandwidth_km <- choice$bandwidth_km
  row$tried <- lapply(seq_len(nrow(choice$tried)), function(i) {
    lapply(as.list(choice$tried[i, ]), function(v) if (is.numeric(v)) round(v, 4) else v)
  })
  if (!is.finite(choice$bandwidth_km)) {
    return(c(row, list(status = "refused", seconds = seconds())))
  }
  found <- inputs$training[inputs$training$presence == 1L, , drop = FALSE]
  model <- list(x = found$x, y = found$y, bandwidth_km = choice$bandwidth_km)
  area <- atlas_accessible_area(found$x, found$y, buffer_km)
  kernel <- atlas_distance_raster(model, stack, area)
  path <- atlas_distance_raster_path(out_dir, name)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(kernel, path, overwrite = TRUE, datatype = "FLT8S",
                     gdal = c("COMPRESS=DEFLATE"))
  chosen <- choice$tried[choice$tried$bandwidth_km == choice$bandwidth_km, , drop = FALSE]
  c(row, list(status = "scored", file = basename(path),
              arms = list(list(arm = "kernel", bandwidth_km = choice$bandwidth_km,
                               auc = round(chosen$auc, 4),
                               boyce = round(chosen$boyce, 4))),
              seconds = seconds()))
}

# Site bands the E2 pre-registration reports by.
ATLAS_DISTANCE_BANDS <- c(3, 5, 20, 50)

#' Chosen bandwidths by site band: how far a taxon's finds "reach".
atlas_distance_summary <- function(rows, baseline = NULL) {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  if (!length(scored)) return(data.frame())
  long <- data.frame(
    band = vapply(scored, function(r) as.character(r$band), ""),
    bandwidth_km = vapply(scored, function(r) as.numeric(r$bandwidth_km), 0),
    auc = vapply(scored, function(r) as.numeric(r$arms[[1]]$auc %||% NA), 0),
    stringsAsFactors = FALSE
  )
  out <- do.call(rbind, lapply(split(long, long$band), function(x) data.frame(
    band = x$band[[1]], taxa = nrow(x),
    median_bandwidth_km = stats::median(x$bandwidth_km),
    auc = round(mean(x$auc, na.rm = TRUE), 3), stringsAsFactors = FALSE
  )))
  rownames(out) <- NULL
  out
}

#' What a run would do, without doing it: taxa by band and design, and a
#' rough CPU-hour figure (kernel cells x sites, plus the folds).
atlas_distance_plan <- function(presences, bandwidths = ATLAS_DISTANCE_BANDWIDTHS_KM,
                                cells_per_taxon = ATLAS_DISTANCE_PLAN_CELLS,
                                seconds_per_million = ATLAS_DISTANCE_PLAN_SECONDS) {
  presences <- as.integer(presences)
  band <- atlas_presence_band(presences, ATLAS_DISTANCE_BANDS)
  # Raster: every cell of the reach against every site; cross-validation:
  # every candidate bandwidth against every held-out site.
  work <- presences * cells_per_taxon + length(bandwidths) * presences * 10000
  seconds <- sum(work) / 1e6 * seconds_per_million + 30 * length(presences)
  list(taxa = length(presences), by_band = as.list(table(band)),
       cpu_hours = round(seconds / 3600, 2))
}

# Planning figures: about 31,000 5 km cells in a 500 km reach, and the time
# one core takes per million kernel terms (measured on this code).
ATLAS_DISTANCE_PLAN_CELLS <- 31000
ATLAS_DISTANCE_PLAN_SECONDS <- 0.08

#' Run the baseline over a release's modelled taxa.
#'
#' release is the hindcast release; its job's pull is the training data, so
#' the kernels see exactly the records its models did. shard "i/n" takes
#' every n-th taxon from the i-th, so n machines split a run without
#' overlap. plan_only prints the work and stops.
atlas_distance_study <- function(store = atlas_store(), release, grid = "draft",
                                 out = NULL, shard = "1/1", workers = 1L,
                                 bandwidths = ATLAS_DISTANCE_BANDWIDTHS_KM,
                                 plan_only = FALSE, quiet = FALSE, view = NULL) {
  view <- view %||% atlas_tracker_view(store, release, grid)
  expected <- atlas_distance_expected(view)
  taxa <- atlas_study_shard(sort(view$modelled), shard)
  plan <- atlas_distance_plan(unlist(expected[taxa]) %||% integer(), bandwidths)
  if (isTRUE(plan_only)) {
    if (!isTRUE(quiet)) {
      message("distance baseline on release ", release, " (shard ", shard, "): ",
              plan$taxa, " taxa, about ", plan$cpu_hours, " CPU-hours")
      print(unlist(plan$by_band))
    }
    return(invisible(plan))
  }
  out <- atlas_study_out(out, "distance-studies", grid, release)
  pull <- atlas_tracker_release_pull(store, view$manifest, grid, view$cache)
  points <- atlas_occurrence_points(pull, grid)
  fingerprints <- as.list(atlas_fingerprints_for(pull, taxa))
  records <- lapply(stats::setNames(taxa, taxa), function(taxon) atlas_distance_record(view, taxon))
  args <- list(grid = grid, out_dir = out$dir, bandwidths = bandwidths, records = records)
  settings <- list(release = release, shard = shard, bandwidths_km = bandwidths,
                   kernel = "sum of Gaussians over detection survey sites, log units",
                   folds = "production design: full models, else small-model ensembles")
  result <- atlas_run_study(
    kind = "distance-studies", file_prefix = out$prefix, taxon_fn = "atlas_distance_taxon",
    sample = data.frame(scientific_name = taxa, stringsAsFactors = FALSE),
    fingerprints = fingerprints, args = args, settings = settings, baseline = "kernel",
    grid = grid, workers = workers, points = points, quiet = quiet,
    summarise = atlas_distance_summary,
    extra = function(rows) list(counts = atlas_study_counts(rows)),
    detail = function(arm) sprintf("h=%s auc=%s", arm$bandwidth_km %||% "", arm$auc),
    opening = paste0(length(taxa), " taxa of release ", release, ", shard ", shard,
                     "; kernel bandwidths ", paste(bandwidths, collapse = ", "), " km")
  )
  if (!is.null(out$key)) {
    files <- c(list.files(out$dir, recursive = TRUE, full.names = TRUE), result$path,
               sub("[.]json$", ".log", result$path))
    atlas_study_publish(store, files[file.exists(files)], out$key, root = dirname(out$dir))
  }
  invisible(c(result, list(out = out$dir)))
}

#' The detection-site count the release recorded for each modelled taxon:
#' the largest over its models (all of a taxon's models see the same sites).
atlas_distance_expected <- function(view) {
  counts <- list()
  for (entry in view$entries) {
    n <- suppressWarnings(as.integer(entry$presences %||% NA))
    if (length(n) != 1L || is.na(n)) next
    counts[[entry$taxon]] <- max(n, counts[[entry$taxon]] %||% 0L)
  }
  counts
}

#' A model's metrics as a release recorded them, or NULL.
atlas_distance_read_metrics <- function(view, taxon, algorithm) {
  json <- atlas_tracker_file(view, atlas_model_relpaths(taxon, view$grid, algorithm, ".json")[[1]], ".json")
  if (is.null(json)) NULL else jsonlite::fromJSON(json, simplifyVector = FALSE)
}

#' What the release recorded about the folds a taxon was scored on, from
#' the model whose design set them: a full model (Maxent, the forest or
#' boosted trees, which share one design) when the taxon has one, else the
#' small-model ensemble. The fingerprint, detection sites, seed, block size
#' and detection sites in each fold; NULL when the release holds none.
atlas_distance_record <- function(view, taxon, read_metrics = atlas_distance_read_metrics) {
  algorithms <- vapply(Filter(function(e) identical(e$taxon, taxon), view$entries),
                       function(e) as.character(e$algorithm), "")
  for (algorithm in intersect(c("maxnet", "rf", "xgboost", "esm"), algorithms)) {
    metrics <- read_metrics(view, taxon, algorithm)
    if (is.null(metrics)) next
    return(list(
      algorithm = algorithm, design = if (identical(algorithm, "esm")) "small" else "full",
      fingerprint = as.character(metrics$fingerprint %||% NA),
      presences = suppressWarnings(as.integer(metrics$presences %||% NA)),
      seed = suppressWarnings(as.integer(metrics$seed %||% NA)),
      block_km = suppressWarnings(as.numeric(metrics$block_km %||% NA)),
      fold_presences = vapply(metrics$folds %||% list(), function(f) as.integer(f$presences %||% NA), 0L)
    ))
  }
  NULL
}

#' Where a rebuilt taxon differs from the release's record, as short
#' reasons; empty when it matches: the fingerprint, the detection sites, the
#' design, the seed, the block size and the detection sites in each fold.
atlas_distance_differences <- function(inputs, record, fingerprint) {
  why <- character()
  if (!identical(as.character(fingerprint), record$fingerprint)) why <- c(why, "fingerprint")
  if (!identical(as.integer(inputs$presences), record$presences)) why <- c(why, "presences")
  if (!identical(inputs$design, record$design)) return(c(why, "design"))
  if (!identical(as.integer(inputs$seed), record$seed)) why <- c(why, "seed")
  if (!isTRUE(all.equal(as.numeric(inputs$block_km), record$block_km))) why <- c(why, "block")
  folds <- vapply(sort(unique(inputs$folds)), function(f) {
    sum(inputs$training$presence[inputs$folds == f] == 1L)
  }, 0L)
  if (length(record$fold_presences) && !identical(as.integer(folds), as.integer(record$fold_presences))) {
    why <- c(why, "folds")
  }
  why
}
