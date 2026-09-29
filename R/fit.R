# Fitting, and judging the fit honestly.
#
# Maxent is fitted through maxnet, the reference implementation written by
# Maxent's own author: the same model as the Java program, expressed as a
# penalised regression. Evaluation is deliberately not a random split. Fungal
# records are clustered — a foray produces thirty collections from one wood —
# so a random hold-out puts near-neighbours on both sides and reports a score
# that says only "this model can interpolate between two points 200 m apart".
# Folds are therefore whole spatial blocks.
#
# Two statistics are reported. AUC is familiar but, with background rather than
# absences, it measures separation from the sampled landscape, not from where
# the species is truly absent — it cannot reach 1 and its ceiling depends on
# how widespread the species is. The Boyce index asks the question that suits
# presence-background data: do higher predictions really hold proportionally
# more records?

#' Columns of a training table that are predictors, rather than bookkeeping.
atlas_predictor_columns <- function(training) {
  setdiff(names(training), c("presence", "cell", "x", "y"))
}

#' Feature classes for a fit. Hinge features need records to support them.
atlas_feature_classes <- function(n_presence) {
  if (n_presence < 30) "lq" else "lqh"
}

#' Assign each row to a fold by spatial block, so a fold holds out a region.
atlas_spatial_folds <- function(x, y, k = 5, block_km = 200, seed = 1L) {
  block <- paste(
    floor(x / (block_km * 1000)),
    floor(y / (block_km * 1000)),
    sep = ":"
  )
  blocks <- unique(block)
  k <- max(2L, min(as.integer(k), length(blocks)))
  set.seed(seed)
  assignment <- sample(rep_len(seq_len(k), length(blocks)))
  assignment[match(block, blocks)]
}

#' Fit Maxent to a training table.
atlas_fit_maxnet <- function(training, classes = NULL, regmult = 1) {
  if (!requireNamespace("maxnet", quietly = TRUE)) {
    stop("maxnet is needed to fit: install.packages('maxnet')", call. = FALSE)
  }
  predictors <- training[, atlas_predictor_columns(training), drop = FALSE]
  presence <- as.integer(training$presence)
  if (sum(presence == 1L) < 2L) {
    stop("a fit needs at least two presences", call. = FALSE)
  }
  classes <- classes %||% atlas_feature_classes(sum(presence == 1L))
  maxnet::maxnet(
    p = presence,
    data = predictors,
    f = maxnet::maxnet.formula(presence, predictors, classes = classes),
    regmult = regmult
  )
}

#' Suitability on the cloglog scale, clamped outside the training range.
atlas_suitability <- function(model, newdata) {
  as.numeric(stats::predict(model, newdata, type = "cloglog", clamp = TRUE))
}

#' Area under the ROC curve, from ranks.
#'
#' With background rather than true absences this is a measure of separation
#' from the sampled landscape. Read it as a comparison between models of the
#' same species, not as a probability of being right.
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
#' fit and score default to Maxent; the model benchmark passes boosted trees
#' through the same loop, so both are scored on exactly the same folds.
atlas_cross_validate <- function(training, folds, classes = NULL, regmult = 1,
                                 fit = function(train) {
                                   atlas_fit_maxnet(train, classes = classes, regmult = regmult)
                                 },
                                 score = atlas_suitability) {
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
    scores <- score(model, test[, atlas_predictor_columns(test), drop = FALSE])
    data.frame(
      fold = fold,
      presences = presences_held,
      auc = atlas_auc(scores[test$presence == 1L], scores[test$presence == 0L]),
      boyce = atlas_boyce(scores[test$presence == 1L], scores[test$presence == 0L])
    )
  })
  out <- do.call(rbind, results)
  rownames(out) <- NULL
  out
}

#' Where a taxon's fitted map and its scores are written.
atlas_model_path <- function(name, grid = "draft", extension = ".tif", algorithm = "maxnet") {
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(name)))
  file.path(atlas_model_dir(grid, algorithm), paste0(slug, extension))
}

#' A refusal to model, as opposed to a failure: the taxon is fine, there is
#' just not enough of it. Classed so a batch run can count the two apart.
atlas_insufficient_evidence <- function(name, presences, grid, min_presences) {
  structure(
    class = c("atlas_insufficient_evidence", "error", "condition"),
    list(
      message = paste0(
        "insufficient evidence for ", name, ": ", presences,
        " presence cells on the ", grid, " grid, and a map needs ",
        min_presences, ". This taxon is a survey target, not a model."
      ),
      call = NULL,
      presences = presences
    )
  )
}

#' Everything that decides a fit apart from the records themselves.
#'
#' A stored model is current only when both its record set and these match.
#' The layers are in here because a model fitted before soil was built has the
#' same records as one fitted after, and is still out of date.
atlas_fit_settings <- function(grid = "draft", n_background = 10000,
                               buffer_km = 500, folds = 5, block_km = 200,
                               regmult = 1, correlation = 0.7, prune = TRUE,
                               layers = atlas_layers_key(grid),
                               algorithm = "maxnet") {
  settings <- list(
    grid = grid,
    n_background = as.numeric(n_background),
    buffer_km = as.numeric(buffer_km),
    folds = as.numeric(folds),
    block_km = as.numeric(block_km),
    regmult = as.numeric(regmult),
    correlation = if (isTRUE(prune)) as.numeric(correlation) else "none",
    layers = layers
  )
  # Maxent's key is left exactly as it was before there was a choice, so the
  # maps fitted then stay current. Every other algorithm names itself, with
  # the settings of its learner, so changing those makes its models stale.
  if (!identical(algorithm, "maxnet")) {
    settings$algorithm <- algorithm
    settings$learner <- switch(
      algorithm,
      xgboost = ATLAS_XGBOOST_PARAMS,
      rf = list(num_trees = ATLAS_RF_TREES, down_sampled = TRUE),
      list()
    )
  }
  settings
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

#' Fit one taxon end to end: training data, blocked scores, map, metrics.
#'
#' With predict = FALSE the scores are still computed and written, but no map
#' is drawn: that is the cheap way to score hundreds of taxa.
atlas_fit_taxon <- function(name, grid = "draft", n_background = 10000,
                            buffer_km = 500, folds = 5, block_km = 200,
                            regmult = 1, min_presences = 20, correlation = 0.7,
                            prune = NULL, write = TRUE, predict = TRUE,
                            quiet = FALSE, points = NULL, stack = NULL,
                            occurrences = NULL, fingerprint = NULL,
                            layers = NULL, algorithm = "maxnet") {
  algo <- atlas_algorithm(algorithm)
  # Each algorithm has its own habit about correlated predictors; an explicit
  # prune overrides it.
  prune <- prune %||% algo$prune
  stack <- stack %||% atlas_predictor_stack(grid)
  settings <- atlas_fit_settings(
    grid = grid, n_background = n_background, buffer_km = buffer_km,
    folds = folds, block_km = block_km, regmult = regmult,
    correlation = correlation, prune = prune,
    layers = layers %||% atlas_layers_key(grid), algorithm = algo$id
  )
  training <- atlas_build_training(
    name, grid,
    n_background = n_background, buffer_km = buffer_km,
    write = FALSE, quiet = TRUE, points = points, stack = stack,
    occurrences = occurrences, fingerprint = fingerprint
  )
  presences <- sum(training$presence == 1L)
  if (presences < min_presences) {
    stop(atlas_insufficient_evidence(name, presences, grid, min_presences))
  }

  considered <- atlas_predictor_columns(training)
  if (isTRUE(prune)) {
    keep <- atlas_choose_predictors(training, threshold = correlation)
    kept_attributes <- attributes(training)[c("area_km2", "seed", "fingerprint", "dropped")]
    training <- training[, c("presence", "cell", "x", "y", keep), drop = FALSE]
    attributes(training)[names(kept_attributes)] <- kept_attributes
  }

  seed <- attr(training, "seed")
  fold_ids <- atlas_spatial_folds(
    training$x, training$y, k = folds, block_km = block_km, seed = seed
  )
  learn <- function(train) {
    algo$fit(train, regmult = regmult, seed = seed, block_km = block_km)
  }
  scores <- atlas_cross_validate(training, fold_ids, fit = learn, score = algo$score)
  model <- learn(training)

  suitability <- NULL
  if (isTRUE(predict)) {
    occupied <- training[training$presence == 1L, , drop = FALSE]
    area <- atlas_accessible_area(occupied$x, occupied$y, buffer_km)
    suitability <- atlas_predict_raster(model, stack, area, score = algo$score)
  } else if (isTRUE(write)) {
    # A map left over from an older fit would be drawn beside scores it does
    # not belong to, so it goes.
    atlas_remove_map(name, grid, algo$id)
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
    predictors = as.list(atlas_predictor_columns(training)),
    predictors_considered = length(considered),
    correlation = if (isTRUE(prune)) correlation else NA,
    classes = if (algo$id == "maxnet") atlas_feature_classes(presences) else NULL,
    nrounds = attr(model, "nrounds"),
    regmult = regmult,
    block_km = block_km,
    seed = seed,
    fingerprint = attr(training, "fingerprint"),
    settings = settings,
    settings_key = atlas_settings_key(settings),
    folds = lapply(seq_len(nrow(scores)), function(i) as.list(scores[i, ])),
    auc_mean = round(mean(scores$auc, na.rm = TRUE), 3),
    auc_sd = round(stats::sd(scores$auc, na.rm = TRUE), 3),
    boyce_mean = round(mean(scores$boyce, na.rm = TRUE), 3),
    boyce_sd = round(stats::sd(scores$boyce, na.rm = TRUE), 3),
    raster = if (is.null(raster_path)) NULL else basename(raster_path),
    md5 = if (is.null(raster_path)) NULL else unname(tools::md5sum(raster_path)),
    map = if (is.null(drawn)) NULL else basename(drawn$path),
    bounds = if (is.null(drawn)) NULL else drawn$bounds,
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
    message("  presences (cells):  ", metrics$presences)
    message("  background:         ", metrics$background)
    message("  predictors:         ", length(metrics$predictors), " of ",
            metrics$predictors_considered)
    message("  blocked AUC:        ", metrics$auc_mean, " (sd ", metrics$auc_sd, ")")
    message("  blocked Boyce:      ", metrics$boyce_mean, " (sd ", metrics$boyce_sd, ")")
    message("  folds scored:       ", sum(!is.na(scores$auc)), " of ", nrow(scores))
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
  window <- terra::crop(stack, terra::ext(area))
  predicted <- terra::predict(
    window, model,
    fun = function(model, data, ...) score(model, data),
    na.rm = TRUE
  )
  names(predicted) <- "suitability"
  terra::mask(predicted, area)
}
