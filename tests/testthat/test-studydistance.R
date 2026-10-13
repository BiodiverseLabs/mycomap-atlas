# The distance-only baseline (paper E6b): a kernel of distance to a taxon's
# known sites, its bandwidth chosen on the folds production scores the taxon
# on, ranked on each model's own cells so the two are scored on one footing.

# --- The kernel --------------------------------------------------------------

test_that("a distance kernel falls with distance from a site and never ties far away", {
  km <- c(0, 10, 50, 1000, 3000)
  values <- atlas_distance_log_kernel(0, 0, km * 1000, rep(0, length(km)), bandwidth_km = 10)
  expect_true(all(is.finite(values)))
  # Far beyond the bandwidth a plain sum underflows to zero and every cell
  # ties; in log units the farther cell still ranks lower.
  expect_true(all(diff(values) < 0))
})

test_that("a distance kernel is the sum of one Gaussian per site", {
  px <- c(0, 30000, 90000)
  py <- c(0, 0, 40000)
  qx <- c(10000, 50000)
  qy <- c(5000, 20000)
  h <- 25
  direct <- vapply(seq_along(qx), function(i) {
    log(sum(exp(-((qx[i] - px)^2 + (qy[i] - py)^2) / (2 * (h * 1000)^2))))
  }, numeric(1))
  expect_equal(atlas_distance_log_kernel(px, py, qx, qy, h), direct, tolerance = 1e-12)
})

test_that("summing a kernel in chunks gives the answer one pass gives", {
  set.seed(3)
  px <- stats::runif(40, 0, 1e6)
  py <- stats::runif(40, 0, 1e6)
  qx <- stats::runif(500, 0, 1e6)
  qy <- stats::runif(500, 0, 1e6)
  expect_equal(atlas_distance_log_kernel(px, py, qx, qy, 50, chunk_cells = 7),
               atlas_distance_log_kernel(px, py, qx, qy, 50, chunk_cells = 1e9))
})

test_that("a distance kernel refuses a bandwidth that is not a positive distance", {
  expect_error(atlas_distance_log_kernel(0, 0, 1, 1, 0), "positive")
  expect_error(atlas_distance_log_kernel(0, 0, 1, 1, NA), "positive")
  expect_error(atlas_distance_log_kernel(numeric(), numeric(), 1, 1, 10), "at least one site")
})

# --- Choosing the bandwidth ---------------------------------------------------

# Sites in a 1,000 km square: the taxon lives in the eastern fifth only.
regional_training <- function(seed = 5) {
  set.seed(seed)
  background <- data.frame(presence = 0L, x = stats::runif(1500, 0, 1e6), y = stats::runif(1500, 0, 1e6))
  found <- data.frame(presence = 1L, x = stats::runif(80, 8e5, 1e6), y = stats::runif(80, 0, 1e6))
  out <- rbind(found, background)
  out$cell <- seq_len(nrow(out))
  out$effort <- 0
  out[, c("presence", "cell", "x", "y", "effort")]
}

test_that("a regional taxon's distance kernel beats chance on blocked folds", {
  training <- regional_training()
  folds <- atlas_spatial_folds(training$x, training$y, k = 5, block_km = 100, seed = 1,
                               presence = training$presence)
  choice <- atlas_distance_choose(training, folds, bandwidths = c(10, 50, 200))
  expect_true(choice$bandwidth_km %in% c(10, 50, 200))
  expect_gt(max(choice$tried$auc), 0.8)
  # The bandwidth chosen is the one held-out ground scored best.
  expect_equal(choice$bandwidth_km, choice$tried$bandwidth_km[which.max(choice$tried$auc)])
})

test_that("bandwidths that score alike go to the smaller one", {
  # Every detection sits far from every non-detection, so every bandwidth
  # separates them perfectly on every fold.
  set.seed(2)
  training <- data.frame(
    presence = c(rep(1L, 30), rep(0L, 300)),
    x = c(9e5 + stats::runif(30, 0, 2000), stats::runif(300, 0, 3e5)),
    y = c(stats::runif(30, 0, 9e5), stats::runif(300, 0, 9e5))
  )
  training$cell <- seq_len(nrow(training))
  folds <- rep_len(1:3, nrow(training))
  choice <- atlas_distance_choose(training, folds, bandwidths = c(400, 25, 5))
  expect_equal(choice$tried$auc, c(1, 1, 1))
  expect_equal(choice$bandwidth_km, 5)
})

test_that("a bandwidth is chosen from the training sites alone", {
  # Every kernel atlas_distance_choose fits sees only its training folds'
  # rows: a held-out site is never one of its sites.
  training <- regional_training()
  folds <- atlas_spatial_folds(training$x, training$y, k = 5, block_km = 100, seed = 1,
                               presence = training$presence)
  fitted_on <- list()
  real_fit <- atlas_distance_fit
  local_mocked_bindings(atlas_distance_fit = function(train, bandwidth_km) {
    fitted_on[[length(fitted_on) + 1L]] <<- train$cell
    real_fit(train, bandwidth_km)
  })
  atlas_distance_choose(training, folds, bandwidths = c(10, 50))
  expect_length(fitted_on, 2L * length(unique(folds)))
  for (cells in fitted_on) {
    fold <- setdiff(unique(folds), unique(folds[training$cell %in% cells]))
    expect_length(fold, 1L)
    expect_false(any(training$cell[folds == fold] %in% cells))
  }
})

# --- Inputs as production builds them ------------------------------------------

test_that("the kernel's folds are the folds production scores the taxon on", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  inputs <- atlas_distance_inputs("Eastern fungus", world$points, world$stack,
                                  fingerprint = "f00dfeed", n_background = 500, buffer_km = 300)
  fit <- atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                         fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                         buffer_km = 300, predict = FALSE, write = FALSE, quiet = TRUE,
                         nulls = 0, tune = FALSE, importance = FALSE)
  expect_equal(inputs$design, "full")
  expect_equal(inputs$presences, fit$metrics$presences)
  expect_equal(inputs$block_km, fit$metrics$block_km)
  # The same sites in the same folds: production's held-out rows, fold by
  # fold, are the kernel's.
  held <- attr(fit$scores, "held")
  expect_false(is.null(held))
  ours <- do.call(rbind, lapply(sort(unique(inputs$folds)), function(f) {
    data.frame(fold = f, presence = inputs$training$presence[inputs$folds == f])
  }))
  expect_equal(table(held$fold, held$presence), table(ours$fold, ours$presence))
})

test_that("a taxon with too few sites for the full models takes the small models' folds", {
  skip_if_not_installed("terra")
  world <- synthetic_landscape()
  east <- which(world$points$scientific_name == "Eastern fungus")
  # Keep 8 of its records, spread north to south so three 100 km blocks hold one.
  keep <- east[order(world$points$y[east])][round(seq(1, length(east), length.out = 8))]
  points <- world$points[c(which(world$points$scientific_name != "Eastern fungus"), keep), ]
  inputs <- atlas_distance_inputs("Eastern fungus", points, world$stack,
                                  fingerprint = "f00dfeed", n_background = 500, buffer_km = 300)
  expect_equal(inputs$design, "small")
  expect_equal(inputs$block_km, 100)
  expect_equal(length(unique(inputs$folds)), 3L)
})

test_that("a taxon with fewer than three sites gets no folds and no kernel", {
  skip_if_not_installed("terra")
  world <- synthetic_landscape()
  east <- which(world$points$scientific_name == "Eastern fungus")
  points <- world$points[c(which(world$points$scientific_name != "Eastern fungus"), east[1:2]), ]
  inputs <- atlas_distance_inputs("Eastern fungus", points, world$stack,
                                  fingerprint = "f00dfeed", n_background = 500, buffer_km = 300)
  expect_null(inputs$folds)
  expect_true(is.na(inputs$design))
})

# --- Pairing with a model's cells ---------------------------------------------

# A model on a 10 x 10 grid whose area of applicability is the western half.
model_layers_west <- function() {
  grid <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1e5, ymin = 0, ymax = 1e5,
                      crs = ATLAS_CRS)
  suitability <- grid
  terra::values(suitability) <- seq_len(100)
  dissimilarity <- grid
  xy <- terra::xyFromCell(grid, seq_len(100))
  terra::values(dissimilarity) <- ifelse(xy[, 1] < 5e4, 0, 2)
  atlas_tracker_layers(suitability, dissimilarity, threshold = 1)
}

test_that("the kernel is ranked again on the model's own cells, and only there", {
  skip_if_not_installed("terra")
  model <- model_layers_west()
  kernel <- terra::rast(model$raster[[1]])
  xy <- terra::xyFromCell(kernel, seq_len(100))
  # Highest in the east, where the model does not apply.
  terra::values(kernel) <- xy[, 1] / 1e3 + xy[, 2] / 1e7
  paired <- atlas_distance_paired_layers(kernel, model)
  inside <- is.finite(model$rank)
  expect_equal(is.finite(paired$rank), inside)
  expect_equal(range(paired$rank[inside]), c(0, 1))
  expect_equal(paired$outside, model$outside)
  # Within the model's cells the order is the kernel's.
  expect_equal(rank(paired$rank[inside]), rank(terra::values(kernel, mat = FALSE)[inside]))
  # And a find lands in the same place class on both.
  hit_model <- atlas_tracker_lookup(model, c(2e4, 8e4), c(5e4, 5e4))
  hit_kernel <- atlas_tracker_lookup(paired, c(2e4, 8e4), c(5e4, 5e4))
  expect_equal(hit_kernel$place, hit_model$place)
})

test_that("a kernel on another grid is refused rather than resampled", {
  skip_if_not_installed("terra")
  model <- model_layers_west()
  shifted <- terra::rast(nrows = 10, ncols = 10, xmin = 3000, xmax = 103000, ymin = 0, ymax = 1e5,
                         crs = ATLAS_CRS)
  terra::values(shifted) <- seq_len(100)
  expect_error(atlas_distance_paired_layers(shifted, model), "one grid")
})

# --- Running it ---------------------------------------------------------------

# The record a release keeps for the synthetic taxon, as production fits it.
distance_record <- function(world) {
  fit <- atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                         fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                         buffer_km = 300, predict = FALSE, write = FALSE, quiet = TRUE,
                         nulls = 0, tune = FALSE, importance = FALSE)
  view <- list(grid = "draft", entries = list(list(taxon = "Eastern fungus", algorithm = "esm"),
                                              list(taxon = "Eastern fungus", algorithm = "maxnet")))
  atlas_distance_record(view, "Eastern fungus", read_metrics = function(view, taxon, algorithm) {
    if (identical(algorithm, "esm")) {
      return(list(fingerprint = "f00dfeed", presences = fit$metrics$presences, seed = fit$metrics$seed,
                  block_km = 100, folds = list()))
    }
    jsonlite::fromJSON(jsonlite::toJSON(fit$metrics, auto_unbox = TRUE, null = "null", na = "null"),
                       simplifyVector = FALSE)
  })
}

test_that("a distance study row carries no coordinate and writes only into its own directory", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  out <- tempfile("distance-")
  dir.create(out)
  row <- atlas_distance_taxon("Eastern fungus", "f00dfeed", world$points, world$stack,
                              out_dir = out, bandwidths = c(25, 100), n_background = 500,
                              buffer_km = 300, records = list("Eastern fungus" = distance_record(world)))
  expect_equal(row$status, "scored")
  expect_true(row$bandwidth_km %in% c(25, 100))
  written <- list.files(out, recursive = TRUE)
  expect_equal(written, "kernels/eastern-fungus.tif")
  coordinate_names <- c("x", "y", "lat", "lng", "latitude", "longitude")
  names_in <- function(x) if (is.list(x)) c(names(x), unlist(lapply(x, names_in))) else character()
  expect_length(intersect(names_in(row), coordinate_names), 0L)
  kernel <- terra::rast(file.path(out, written))
  expect_gt(sum(is.finite(terra::values(kernel))), 0)
})

test_that("the kernel's rebuild is checked against the model whose folds it shares", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  record <- distance_record(world)
  # Maxent's folds are the full design's, so Maxent is read before the ensemble.
  expect_equal(record$algorithm, "maxnet")
  expect_equal(record$design, "full")
  inputs <- atlas_distance_inputs("Eastern fungus", world$points, world$stack,
                                  fingerprint = "f00dfeed", n_background = 500, buffer_km = 300)
  expect_length(atlas_distance_differences(inputs, record, "f00dfeed"), 0L)
  expect_equal(atlas_distance_differences(inputs, record, "beefcafe"), "fingerprint")
  expect_true("presences" %in% atlas_distance_differences(inputs, modifyList(record, list(presences = 999L)), "f00dfeed"))
  expect_equal(atlas_distance_differences(inputs, modifyList(record, list(seed = 1L)), "f00dfeed"), "seed")
  expect_equal(atlas_distance_differences(inputs, modifyList(record, list(block_km = 77)), "f00dfeed"), "block")
  expect_equal(atlas_distance_differences(inputs, modifyList(record, list(design = "small")), "f00dfeed"), "design")
  expect_equal(atlas_distance_differences(inputs, modifyList(record, list(fold_presences = rev(record$fold_presences + 1L))),
                                          "f00dfeed"), "folds")
  # A record that keeps no folds cannot vouch for them.
  expect_equal(atlas_distance_differences(inputs, modifyList(record, list(fold_presences = integer())), "f00dfeed"),
               "no folds recorded")
})

test_that("a taxon whose rebuild differs from the release's record is refused, not fitted", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  record <- distance_record(world)
  out <- tempfile("distance-")
  dir.create(out)
  row <- atlas_distance_taxon("Eastern fungus", "f00dfeed", world$points, world$stack,
                              out_dir = out, bandwidths = 25, n_background = 500, buffer_km = 300,
                              records = list("Eastern fungus" = modifyList(record, list(block_km = 77))))
  expect_equal(row$status, "mismatch")
  expect_equal(unlist(row$differs), "block")
  expect_length(list.files(out, recursive = TRUE), 0L)
  ok <- atlas_distance_taxon("Eastern fungus", "f00dfeed", world$points, world$stack,
                             out_dir = out, bandwidths = 25, n_background = 500, buffer_km = 300,
                             records = list("Eastern fungus" = record))
  expect_equal(ok$status, "scored")
  # A taxon the release holds no record for is not fitted either.
  none <- atlas_distance_taxon("Eastern fungus", "f00dfeed", world$points, world$stack,
                               out_dir = tempfile(), bandwidths = 25, n_background = 500, buffer_km = 300,
                               records = list())
  expect_equal(none$status, "mismatch")
  expect_equal(unlist(none$differs), "no record")
})

test_that("shards split a study's taxa without overlap or gap", {
  names <- sprintf("taxon %02d", 1:23)
  parts <- lapply(1:4, function(i) atlas_study_shard(names, paste0(i, "/4")))
  expect_setequal(unlist(parts), names)
  expect_equal(sum(lengths(parts)), length(names))
  expect_equal(atlas_study_shard(names, "1/1"), names)
  expect_error(atlas_study_shard(names, "5/4"), "shard")
  expect_error(atlas_study_shard(names, "0/4"), "shard")
  expect_error(atlas_study_shard(names, "two"), "shard")
})

test_that("a study writes only under study/ or private/study/, never a release, the pointer or production's private files", {
  for (key in c("releases/draft/x.json", "current", "public/x", "study/../releases/x",
                "study/..\\releases\\x", "study\\x", "study/e6b\\x.tif", "objects/ab/cd", "",
                "private/tracker/draft/ledger.tsv.gz", "private/vision-benchmark/r1/release.json",
                "private/trained-ids/x", "private/e6b/a.json")) {
    expect_error(atlas_study_check_key(key), "only under")
  }
  expect_equal(atlas_study_check_key("study/e6b/kernels/a.tif"), "study/e6b/kernels/a.tif")
  expect_equal(atlas_study_check_key("private/study/e6b/a.json"), "private/study/e6b/a.json")
})

test_that("a bad --out is refused before anything is read or computed", {
  touched <- FALSE
  store <- list(get = function(...) {
    touched <<- TRUE
    stop("touched")
  })
  view <- list(grid = "draft", modelled = "A", entries = list(list(taxon = "A", algorithm = "esm", presences = 4)),
               manifest = list(job = "j"), cache = tempfile())
  with_data_dir({
    expect_error(atlas_distance_study(store, "hindcast-test", view = view, out = "private/tracker/", quiet = TRUE),
                 "only under")
  })
  expect_false(touched)
})

test_that("a study published to a bad prefix writes nothing at all", {
  root <- tempfile("study-")
  dir.create(file.path(root, "run"), recursive = TRUE)
  files <- file.path(root, "run", c("a.tif", "b.json"))
  for (f in files) writeLines("x", f)
  puts <- character()
  store <- list(put = function(key, file) puts <<- c(puts, key))
  expect_error(atlas_study_publish(store, files, "releases/draft", root), "only under")
  expect_length(puts, 0L)
  keys <- atlas_study_publish(store, files, "study/e6b", root)
  expect_equal(keys, c("study/e6b/run/a.tif", "study/e6b/run/b.json"))
  expect_equal(puts, keys)
})

test_that("a plan-only run counts the work and fits nothing", {
  view <- list(
    modelled = c("A", "B", "C", "D"),
    entries = list(list(taxon = "A", algorithm = "esm", presences = 4),
                   list(taxon = "B", algorithm = "maxnet", presences = 60),
                   list(taxon = "B", algorithm = "rf", presences = 60),
                   list(taxon = "C", algorithm = "esm", presences = 12),
                   list(taxon = "D", algorithm = "maxnet", presences = 25))
  )
  plan <- atlas_distance_study(store = NULL, release = "hindcast-test", view = view,
                               plan_only = TRUE, quiet = TRUE)
  expect_equal(plan$taxa, 4L)
  expect_equal(unlist(plan$by_band)[["3-4"]], 1L)
  expect_equal(unlist(plan$by_band)[["50+"]], 1L)
  expect_gt(plan$cpu_hours, 0)
  half <- atlas_distance_study(store = NULL, release = "hindcast-test", view = view,
                               shard = "2/2", plan_only = TRUE, quiet = TRUE)
  expect_equal(half$taxa, 2L)
})
