# "Default practice" Maxent (paper E6a): what a common default workflow says
# about itself, against how it does on records it never saw.
#
# Most published presence-only maps are made the same way: maxnet (or
# Maxent) with its default settings, every available predictor, background
# points scattered at random over the study area, a random k-fold
# cross-validation, and, when a significance test is reported at all, the
# null test of Raes & ter Steege (2007). This study fits that workflow to
# every taxon with at least ATLAS_DEFAULT_MIN_SITES detection sites in the
# hindcast's training records, so its maps can be scored on the hindcast's
# later finds (R/e2score.R) beside Atlas's own.
#
#   presences    the taxon's detection survey sites (5 km thinned), as Atlas
#                counts them
#   background   10,000 grid cells drawn uniformly over the accessible area
#                (the sites buffered by 500 km), with every predictor known;
#                not the target-group sites Atlas uses
#   model        maxnet::maxnet as shipped: feature classes by sample size
#                (default.features), regularisation multiplier 1, its full
#                200-step path; every production predictor, no pruning, no
#                effort term
#   own score    AUC on a random 5-fold cross-validation (presences and
#                background each dealt into five folds)
#   null test    19 null species, each as many points as detections drawn
#                uniformly over the accessible area, fitted the same way;
#                the map passes when its training AUC (against the shared
#                background) beats theirs at p <= 0.05
#
# Nothing here writes a model or a release: one raster per taxon and one
# results file in the study's directory.

ATLAS_DEFAULT_MIN_SITES <- 20L
ATLAS_DEFAULT_BACKGROUND <- 10000L
ATLAS_DEFAULT_FOLDS <- 5L
ATLAS_DEFAULT_NULLS <- 19L
ATLAS_DEFAULT_ALPHA <- 0.05

#' The feature classes maxnet chooses for n presences by default
#' (maxnet.formula, classes = "default"), recorded with each fit.
atlas_default_classes <- function(n) {
  if (n < 10) "l" else if (n < 15) "lq" else if (n < 80) "lqh" else "lqph"
}

#' Fit maxnet exactly as shipped. data holds the predictors only.
atlas_default_fit <- function(presence, data) {
  maxnet::maxnet(presence, data)
}

#' maxnet's cloglog output for new data.
atlas_default_predict <- function(model, newdata) {
  as.numeric(stats::predict(model, newdata, type = "cloglog"))
}

#' n grid cells drawn uniformly over an area, each with every predictor
#' known: cell, x, y and the predictors. Cells are taken in a random order
#' fixed by seed until n are complete, so a cell is drawn at most once.
atlas_default_cells <- function(stack, area, n, seed = 1L) {
  window <- terra::mask(terra::crop(stack[[1]], terra::ext(area)), area)
  candidates <- terra::cells(window)
  if (!length(candidates)) stop("the accessible area holds no cells with data", call. = FALSE)
  set.seed(seed)
  candidates <- candidates[sample.int(length(candidates))]
  out <- NULL
  start <- 1L
  while (start <= length(candidates) && (is.null(out) || nrow(out) < n)) {
    take <- candidates[seq.int(start, min(start + 2L * n - 1L, length(candidates)))]
    start <- start + length(take)
    xy <- terra::xyFromCell(window, take)
    values <- terra::extract(stack, xy)
    values <- values[, setdiff(names(values), "ID"), drop = FALSE]
    rows <- data.frame(cell = terra::cellFromXY(stack, xy), x = xy[, 1], y = xy[, 2], values,
                       check.names = FALSE)
    rows <- rows[stats::complete.cases(rows), , drop = FALSE]
    out <- if (is.null(out)) rows else rbind(out, rows)
  }
  out <- utils::head(out, n)
  rownames(out) <- NULL
  out
}

#' Random k-fold assignment, presences and background dealt separately so
#' every fold holds both.
atlas_default_folds <- function(presence, k = ATLAS_DEFAULT_FOLDS, seed = 1L) {
  set.seed(seed)
  folds <- integer(length(presence))
  for (value in c(1L, 0L)) {
    rows <- which(presence == value)
    folds[rows] <- sample(rep_len(seq_len(k), length(rows)))
  }
  folds
}

#' The model's own score: mean held-out AUC over random folds.
atlas_default_cv <- function(presence, data, folds) {
  aucs <- vapply(sort(unique(folds)), function(f) {
    held <- folds == f
    model <- tryCatch(atlas_default_fit(presence[!held], data[!held, , drop = FALSE]),
                      error = function(e) NULL)
    if (is.null(model)) return(NA_real_)
    scores <- atlas_default_predict(model, data[held, , drop = FALSE])
    atlas_auc(scores[presence[held] == 1], scores[presence[held] == 0])
  }, numeric(1))
  list(auc = mean(aucs, na.rm = TRUE), folds_scored = sum(is.finite(aucs)))
}

#' The training AUC: presences against the background, both as fitted.
atlas_default_train_auc <- function(model, presence, data) {
  scores <- atlas_default_predict(model, data)
  atlas_auc(scores[presence == 1], scores[presence == 0])
}

#' Raes & ter Steege's null test: the observed training AUC against those
#' of nulls species of as many uniform points, each fitted with the same
#' background. A null whose fit fails is replaced, up to as many again.
#' p = (1 + nulls at least as good) / (1 + nulls).
atlas_default_null_test <- function(observed_auc, n, background, pool, reps = ATLAS_DEFAULT_NULLS,
                                    seed = 1L) {
  predictors <- setdiff(names(background), c("cell", "x", "y"))
  aucs <- numeric()
  draw <- 0L
  while (length(aucs) < reps && draw < 2L * reps) {
    draw <- draw + 1L
    set.seed(seed + 1000L + draw)
    picked <- pool[sample.int(nrow(pool), min(n, nrow(pool))), predictors, drop = FALSE]
    data <- rbind(picked, background[, predictors, drop = FALSE])
    presence <- c(rep(1L, nrow(picked)), rep(0L, nrow(background)))
    model <- tryCatch(atlas_default_fit(presence, data), error = function(e) NULL)
    if (is.null(model)) next
    auc <- atlas_default_train_auc(model, presence, data)
    if (is.finite(auc)) aucs <- c(aucs, auc)
  }
  p <- if (length(aucs)) (1 + sum(aucs >= observed_auc)) / (1 + length(aucs)) else NA_real_
  list(reps = length(aucs), drawn = draw, auc_mean = mean(aucs), p = p,
       verdict = if (is.finite(p) && p <= ATLAS_DEFAULT_ALPHA) "passed" else "failed")
}

#' Where a taxon's map is written in a study's output directory.
atlas_default_raster_path <- function(out_dir, name) {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  file.path(out_dir, "maps", paste0(slug, ".tif"))
}

#' One taxon: fit the default workflow, score it its own way, test it, and
#' write its map over the accessible area. The row holds no coordinate.
atlas_default_taxon <- function(name, fingerprint, points, stack, grid = "draft", out_dir,
                                n_background = ATLAS_DEFAULT_BACKGROUND, buffer_km = 500,
                                folds = ATLAS_DEFAULT_FOLDS, nulls = ATLAS_DEFAULT_NULLS,
                                min_sites = ATLAS_DEFAULT_MIN_SITES) {
  started <- Sys.time()
  seconds <- function(since = started) round(as.numeric(difftime(Sys.time(), since, units = "secs")), 1)
  seed <- atlas_seed_from_fingerprint(fingerprint)
  sites <- atlas_training_table(name, points, n_background = 0L, buffer_km = buffer_km,
                                fingerprint = fingerprint)
  sites <- sites[sites$presence == 1L, , drop = FALSE]
  sites <- atlas_add_predictors(sites, grid, stack = stack)
  predictors <- setdiff(names(stack), ATLAS_EFFORT_COLUMN)
  presences <- nrow(sites)
  row <- list(taxon = name, presences = presences,
              band = atlas_presence_band(presences, ATLAS_DISTANCE_BANDS),
              classes = atlas_default_classes(presences))
  if (presences < min_sites) return(c(row, list(status = "refused", seconds = seconds())))
  area <- atlas_accessible_area(sites$x, sites$y, buffer_km)
  background <- atlas_default_cells(stack, area, n_background, seed = seed)
  data <- rbind(sites[, predictors, drop = FALSE], background[, predictors, drop = FALSE])
  presence <- c(rep(1L, presences), rep(0L, nrow(background)))
  row$background <- nrow(background)

  fit_started <- Sys.time()
  cv <- atlas_default_cv(presence, data, atlas_default_folds(presence, folds, seed))
  model <- atlas_default_fit(presence, data)
  train_auc <- atlas_default_train_auc(model, presence, data)
  row$seconds_fit <- seconds(fit_started)

  null_started <- Sys.time()
  pool <- atlas_default_cells(stack, area, max(n_background, 4L * presences), seed = seed + 7L)
  null <- atlas_default_null_test(train_auc, presences, background, pool, reps = nulls, seed = seed)
  row$seconds_nulls <- seconds(null_started)

  suitability <- atlas_predict_raster(model, stack[[predictors]], area, score = atlas_default_predict)
  path <- atlas_default_raster_path(out_dir, name)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(suitability, path, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
  c(row, list(status = "scored", file = basename(path),
              arms = list(list(arm = "default-maxent", auc = round(cv$auc, 4),
                               train_auc = round(train_auc, 4), p = round(null$p, 4),
                               verdict = null$verdict)),
              cv = list(auc = round(cv$auc, 4), folds_scored = cv$folds_scored),
              null = list(reps = null$reps, drawn = null$drawn, auc_mean = round(null$auc_mean, 4),
                          p = round(null$p, 4), verdict = null$verdict, train_auc = round(train_auc, 4)),
              seconds = seconds()))
}

#' Pass rate and own-CV AUC by site band.
atlas_default_summary <- function(rows, baseline = NULL) {
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  if (!length(scored)) return(data.frame())
  long <- data.frame(
    band = vapply(scored, function(r) as.character(r$band), ""),
    auc = vapply(scored, function(r) as.numeric(r$cv$auc %||% NA), 0),
    passed = vapply(scored, function(r) identical(r$null$verdict, "passed"), TRUE),
    stringsAsFactors = FALSE
  )
  out <- do.call(rbind, lapply(split(long, long$band), function(x) data.frame(
    band = x$band[[1]], taxa = nrow(x), cv_auc = round(mean(x$auc, na.rm = TRUE), 3),
    passed = sum(x$passed), pass_rate = round(mean(x$passed), 3), stringsAsFactors = FALSE
  )))
  rownames(out) <- NULL
  out
}

# Planning figures, seconds per maxnet fit on one core at 10,000 background
# points, by the feature classes it uses (a first guess; the pilot sets them).
ATLAS_DEFAULT_PLAN_FIT_SECONDS <- c(l = 1, lq = 2, lqh = 15, lqph = 60)

#' Rough CPU-hours: per taxon, the folds, the final fit and the nulls.
atlas_default_plan <- function(presences, folds = ATLAS_DEFAULT_FOLDS, nulls = ATLAS_DEFAULT_NULLS,
                               min_sites = ATLAS_DEFAULT_MIN_SITES,
                               seconds = ATLAS_DEFAULT_PLAN_FIT_SECONDS) {
  presences <- as.integer(presences[presences >= min_sites])
  per <- vapply(presences, function(n) (folds + 1 + nulls) * seconds[[atlas_default_classes(n)]], 0)
  list(taxa = length(presences),
       by_classes = as.list(table(vapply(presences, atlas_default_classes, ""))),
       cpu_hours = round(sum(per) / 3600, 1))
}

#' Run the default-practice arm over a release's taxa with at least
#' min_sites detection sites. release is the hindcast release; its job's
#' pull is the training data.
atlas_default_study <- function(store = atlas_store(), release, grid = "draft",
                                min_sites = ATLAS_DEFAULT_MIN_SITES, out = NULL, shard = "1/1",
                                workers = 1L, plan_only = FALSE, quiet = FALSE, view = NULL) {
  view <- view %||% atlas_tracker_view(store, release, grid)
  expected <- atlas_distance_expected(view)
  eligible <- sort(names(expected)[unlist(expected) >= min_sites])
  taxa <- atlas_study_shard(eligible, shard)
  plan <- atlas_default_plan(unlist(expected[taxa]) %||% integer(), min_sites = min_sites)
  if (isTRUE(plan_only)) {
    if (!isTRUE(quiet)) {
      message("default-practice Maxent on release ", release, " (shard ", shard, "): ",
              plan$taxa, " taxa with ", min_sites, "+ sites, about ", plan$cpu_hours, " CPU-hours")
      print(unlist(plan$by_classes))
    }
    return(invisible(plan))
  }
  out <- atlas_study_out(out, "default-studies", grid, release)
  pull <- atlas_tracker_release_pull(store, view$manifest, grid, view$cache)
  points <- atlas_occurrence_points(pull, grid)
  fingerprints <- as.list(atlas_fingerprints_for(pull, taxa))
  settings <- list(release = release, shard = shard, min_sites = min_sites,
                   background = ATLAS_DEFAULT_BACKGROUND, folds = ATLAS_DEFAULT_FOLDS,
                   nulls = ATLAS_DEFAULT_NULLS, model = "maxnet::maxnet defaults",
                   maxnet = as.character(utils::packageVersion("maxnet")),
                   null_test = "Raes & ter Steege 2007: training AUC, uniform null points")
  result <- atlas_run_study(
    kind = "default-studies", file_prefix = out$prefix, taxon_fn = "atlas_default_taxon",
    sample = data.frame(scientific_name = taxa, stringsAsFactors = FALSE),
    fingerprints = fingerprints, args = list(grid = grid, out_dir = out$dir, min_sites = min_sites),
    settings = settings, baseline = "default-maxent", grid = grid, workers = workers,
    points = points, quiet = quiet, summarise = atlas_default_summary,
    extra = function(rows) list(counts = atlas_study_counts(rows)),
    detail = function(arm) sprintf("cv=%s train=%s p=%s %s", arm$auc, arm$train_auc, arm$p, arm$verdict),
    opening = paste0(length(taxa), " taxa of release ", release, " with ", min_sites,
                     "+ sites, shard ", shard, ": maxnet defaults, random background and folds, ",
                     ATLAS_DEFAULT_NULLS, " uniform nulls")
  )
  if (!is.null(out$key)) {
    files <- c(list.files(out$dir, recursive = TRUE, full.names = TRUE), result$path,
               sub("[.]json$", ".log", result$path))
    atlas_study_publish(store, files[file.exists(files)], out$key, root = dirname(out$dir))
  }
  invisible(c(result, list(out = out$dir)))
}
