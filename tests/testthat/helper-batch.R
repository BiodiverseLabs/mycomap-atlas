# Shared by the batch and algorithm tests.

# Points already on the grid, and the records behind them. Each taxon gets
# `cells` distinct cells; ids are unique across taxa.
batch_world <- function(cells = c("Rich one" = 40, "Middle one" = 25,
                                  "Sparse one" = 5)) {
  names <- rep(names(cells), cells)
  n <- length(names)
  points <- data.frame(
    scientific_name = names,
    cell = seq_len(n),
    x = seq_len(n) * 5000,
    y = 0,
    stringsAsFactors = FALSE
  )
  occurrences <- data.frame(
    id = as.character(seq_len(n)),
    scientific_name = names,
    latitude = as.character(45 + seq_len(n) / 100),
    longitude = "-122.5",
    observed_on = "2025-10-01",
    stringsAsFactors = FALSE
  )
  list(points = points, occurrences = occurrences)
}

# A stand-in for atlas_fit_taxon that writes metrics the way the real one
# does, and fails on command. Its environment is the global one so that it can
# be sent to a worker process.
fake_fit <- local({
  f <- function(name, fingerprint, grid = "draft", n_background = 10000,
                buffer_km = 500, folds = 5, block_km = 200, regmult = 1,
                correlation = 0.7, prune = TRUE, predict = TRUE,
                layers = NULL, min_presences = 20, algorithm = "maxnet", ...) {
    if (grepl("Broken", name)) stop("the layers are on fire")
    if (grepl("Sparse", name)) {
      stop(atlas_insufficient_evidence(name, 5, grid, min_presences))
    }
    # As many presences as the taxon has cells, like a real fit.
    points <- list(...)$points
    presences <- if (is.null(points)) 30 else length(unique(points$cell[points$scientific_name == name]))
    settings <- atlas_fit_settings(
      grid = grid, n_background = n_background, buffer_km = buffer_km,
      folds = folds, block_km = block_km, regmult = regmult,
      correlation = correlation, prune = prune, layers = layers,
      algorithm = algorithm
    )
    raster <- NULL
    if (isTRUE(predict)) {
      raster <- basename(atlas_model_path(name, grid, algorithm = algorithm))
      dir.create(atlas_model_dir(grid, algorithm), recursive = TRUE, showWarnings = FALSE)
      writeLines("not really a raster", atlas_model_path(name, grid, algorithm = algorithm))
    }
    metrics <- list(
      taxon = name, algorithm = algorithm, presences = presences, predictors = list("v1"),
      auc_mean = 0.7, boyce_mean = 0.5, fingerprint = fingerprint,
      settings_key = atlas_settings_key(settings), raster = raster
    )
    dir.create(atlas_model_dir(grid, algorithm), recursive = TRUE, showWarnings = FALSE)
    atlas_write_json(metrics, atlas_model_path(name, grid, ".json", algorithm))
    list(metrics = metrics)
  }
  environment(f) <- globalenv()
  f
})

run_batch <- function(world, ...) {
  atlas_fit_batch(
    occurrences = world$occurrences, points = world$points,
    layers = "test-layers", fit = fake_fit, quiet = TRUE, ...
  )
}

statuses <- function(result) {
  stats::setNames(
    vapply(result$taxa, function(r) r$status, character(1)),
    vapply(result$taxa, function(r) r$taxon, character(1))
  )
}
