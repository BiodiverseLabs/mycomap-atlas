# The models Atlas fits, side by side.
#
# Every taxon can carry one fitted model per algorithm, each with its own map
# and scores, so people can compare what Maxent, boosted trees and a
# down-sampled random forest make of the same records. They share the training
# table, the background and the spatial folds; only the learner differs.
#
# Maxent keeps the paths it always had (models/<grid>/<taxon>.*); the others
# live in models/<grid>/<algorithm>/, so the maps fitted before there was a
# choice stay valid.

ATLAS_ALGORITHMS <- list(
  maxnet = list(
    label = "Maxent",
    # Maxent is a regression: correlated predictors blur its response curves,
    # so they are pruned and capped by the number of records.
    prune = TRUE,
    fit = function(train, regmult = 1, seed = 1L, block_km = 200) {
      atlas_fit_maxnet(train, regmult = regmult)
    },
    score = function(model, newdata) atlas_suitability(model, newdata),
    package = "maxnet"
  ),
  xgboost = list(
    label = "Boosted trees",
    prune = FALSE,
    # Benchmarked from 20 cells (2026-09-29): below 50 presence cells boosted
    # trees overfit, and at 20-29 cells their maps ranked ground backwards
    # (mean Boyce -0.15, 0.35 below Maxent). From 50 they match Maxent.
    min_presences = 50,
    fit = function(train, regmult = 1, seed = 1L, block_km = 200) {
      atlas_fit_xgboost(train, block_km = block_km, seed = seed)
    },
    score = function(model, newdata) atlas_xgboost_suitability(model, newdata),
    package = "xgboost"
  ),
  rf = list(
    label = "Random forest",
    prune = FALSE,
    fit = function(train, regmult = 1, seed = 1L, block_km = 200) {
      atlas_fit_rf(train, seed = seed)
    },
    score = function(model, newdata) atlas_rf_suitability(model, newdata),
    package = "ranger"
  )
)

#' One algorithm's definition, refusing names Atlas does not fit.
atlas_algorithm <- function(name = "maxnet") {
  name <- as.character(name %||% "maxnet")[[1]]
  if (!name %in% names(ATLAS_ALGORITHMS)) {
    stop("unknown algorithm '", name, "': use one of ",
         paste(names(ATLAS_ALGORITHMS), collapse = ", "), call. = FALSE)
  }
  c(list(id = name), ATLAS_ALGORITHMS[[name]])
}

#' The fewest presence cells an algorithm will map: the run's own minimum, or
#' the algorithm's, whichever is higher.
atlas_algorithm_min <- function(algo, min_presences = 20) {
  max(min_presences, algo$min_presences %||% 0)
}

#' Delete a taxon's model for one algorithm: its scores and its map.
atlas_remove_model <- function(name, grid = "draft", algorithm = "maxnet") {
  paths <- atlas_model_path(name, grid, c(".json", ".tif", ".png", ".png.aux.xml"), algorithm)
  existed <- file.exists(paths)
  unlink(paths[existed])
  invisible(any(existed))
}

#' "maxnet,xgboost" or "all" as a vector of algorithm names.
atlas_parse_algorithms <- function(value) {
  if (is.null(value) || identical(value, TRUE)) {
    return("maxnet")
  }
  parts <- trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1]])
  if (identical(parts, "all")) {
    return(names(ATLAS_ALGORITHMS))
  }
  for (part in parts) atlas_algorithm(part)
  unique(parts)
}

#' The folder an algorithm's models live in.
atlas_model_dir <- function(grid = "draft", algorithm = "maxnet") {
  if (identical(algorithm, "maxnet")) {
    atlas_path("models", grid)
  } else {
    atlas_path("models", grid, algorithm)
  }
}
