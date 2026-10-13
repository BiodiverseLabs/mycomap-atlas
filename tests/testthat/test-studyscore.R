# The baselines scored on the hindcast's later finds (E6b, E6a), with the
# hindcast's own scorer, on the same places as the models.

# A 10 x 10 grid of 10 km cells. A model's suitability rises west to east;
# its area of applicability is everything but the far-west column.
score_grid <- function() {
  terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1e5, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)
}

layers_from <- function(values, outside_west = FALSE) {
  grid <- score_grid()
  suitability <- grid
  terra::values(suitability) <- values
  xy <- terra::xyFromCell(grid, seq_len(terra::ncell(grid)))
  dissimilarity <- grid
  terra::values(dissimilarity) <- if (outside_west) ifelse(xy[, 1] < 1e4, 2, 0) else 0
  layers <- atlas_tracker_layers(suitability, dissimilarity, threshold = 1)
  layers
}

east <- function() {
  xy <- terra::xyFromCell(score_grid(), seq_len(100))
  xy[, 1] + xy[, 2] / 1e3
}

# Forty taxa, each with five places in the east half; their models are
# strong and rank the east high.
score_places <- function(n_taxa = 40) {
  set.seed(3)
  do.call(rbind, lapply(seq_len(n_taxa), function(i) {
    x <- stats::runif(5, 55e3, 99e3)
    y <- stats::runif(5, 1e3, 99e3)
    data.frame(taxon = sprintf("T%02d", i), place = atlas_e2_square(x, y), x = x, y = y,
               finds = 1L, observed_after = FALSE, known_km = 30, new_place = c(TRUE, FALSE, TRUE, FALSE, TRUE),
               band = "25-100", stringsAsFactors = FALSE)
  }))
}

model_maps <- function(taxon) {
  list(maxnet = list(layers = layers_from(east(), outside_west = TRUE), grade = "strong",
                     learner = "maxnet", kind = "model"))
}

test_that("a taxon's kernel is ranked again on each model's own cells and pairs with that model", {
  skip_if_not_installed("terra")
  kernel <- score_grid()
  # The kernel ranks the far west highest, which the model cannot apply to.
  terra::values(kernel) <- -east()
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(kernel, path)
  maps <- atlas_score_kernel_maps(model_maps("T01"), path)
  expect_setequal(names(maps), c("maxnet", "kernel"))
  expect_equal(maps$maxnet$grade, "strong")
  expect_equal(maps$maxnet$kind, "model")
  model <- model_maps("T01")$maxnet$layers
  # Ranked only where the model applies, so the far west is not ranked.
  expect_equal(is.finite(maps$maxnet$layers$rank), is.finite(model$rank))
  # Over its own reach the kernel ranks every cell.
  expect_true(all(is.finite(maps$kernel$layers$rank)))
  expect_equal(maps$kernel$kind, "baseline")
  expect_null(atlas_score_kernel_maps(model_maps("T01"), tempfile()))
})

test_that("H6b compares strong models with their kernels on the same places, by the paired lower bound", {
  skip_if_not_installed("terra")
  places <- score_places()
  # A kernel that ranks the west high: worse than the model on eastern finds.
  west <- score_grid()
  terra::values(west) <- -east()
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(west, path)
  result <- atlas_score_baselines_core(places, model_maps,
                                       kernel_maps_for = function(taxon) atlas_score_kernel_maps(model_maps(taxon), path),
                                       reps = 500)
  expect_equal(result$places$places, nrow(places))
  expect_equal(result$kernel$taxa, 40L)
  h <- result$kernel$H6b
  expect_true(h$tested)
  expect_true(h$holds)
  expect_gt(h$estimate, 0.5)
  expect_equal(h$places, atlas_e2_place_count(places))
  # The same kernel as the model: no edge.
  same <- tempfile(fileext = ".tif")
  sameraster <- score_grid()
  terra::values(sameraster) <- east()
  terra::writeRaster(sameraster, same)
  tie <- atlas_score_baselines_core(places, model_maps,
                                    kernel_maps_for = function(taxon) atlas_score_kernel_maps(model_maps(taxon), same),
                                    reps = 500)
  expect_false(tie$kernel$H6b$holds)
  expect_equal(tie$kernel$H6b$estimate, 0)
  # Splits by new and known places are reported for the models and kernel.
  expect_true(all(c("all", "new", "known", "band 25-100") %in% names(result$models$by_grade$strong)))
  expect_true(result$kernel$H6b_new$tested)
})

test_that("E6a's maps are scored under their own verdict, beside Atlas's models on the same taxa", {
  skip_if_not_installed("terra")
  places <- score_places()
  maps_dir <- tempfile("default-")
  dir.create(file.path(maps_dir, "maps"), recursive = TRUE)
  flat <- score_grid()
  terra::values(flat) <- stats::runif(100)
  for (t in sprintf("T%02d", 1:20)) {
    terra::writeRaster(flat, atlas_default_raster_path(maps_dir, t), overwrite = TRUE)
  }
  verdicts <- stats::setNames(as.list(rep(c("passed", "failed"), 10)), sprintf("T%02d", 1:20))
  default_for <- function(taxon) {
    if (is.null(verdicts[[taxon]])) return(NULL)
    atlas_score_default_maps(atlas_default_raster_path(maps_dir, taxon), verdicts[[taxon]])
  }
  result <- atlas_score_baselines_core(places, model_maps, default_maps_for = default_for, reps = 200)
  expect_equal(result$default$taxa, 20L)
  expect_setequal(names(result$default$by_verdict), c("passed", "failed"))
  expect_equal(result$default$by_verdict$passed$all$taxa, 10L)
  # Atlas's models on the taxa E6a has maps for.
  expect_equal(result$default$atlas_same_taxa$strong$all$taxa, 20L)
  # Taxa without a default map are counted as having none.
  expect_equal(result$default$all$all$no_map, 20L * 5L)
})

test_that("the results hold counts and shares, never a place or a coordinate", {
  skip_if_not_installed("terra")
  places <- score_places()
  result <- atlas_score_baselines_core(places, model_maps, reps = 100)
  names_in <- function(x) if (is.list(x)) c(names(x), unlist(lapply(x, names_in))) else character()
  expect_length(intersect(names_in(result), c("x", "y", "place", "lat", "lng", "latitude", "longitude", "cell")), 0L)
  text <- jsonlite::toJSON(result, auto_unbox = TRUE)
  expect_false(any(vapply(places$place, function(p) grepl(p, text, fixed = TRUE), TRUE)))
})

test_that("an E6a run's maps are found beside its results file, and never guessed between two", {
  dir <- tempfile("default-studies-")
  dir.create(file.path(dir, "default-h1-20261020T010101Z"), recursive = TRUE)
  results <- file.path(dir, "default-h1-20261020T010102Z.json")
  writeLines("{}", results)
  expect_equal(basename(atlas_score_default_dir(results)), "default-h1-20261020T010101Z")
  dir.create(file.path(dir, "default-h1-20261021T010101Z"))
  expect_error(atlas_score_default_dir(results), "more than one")
  exact <- file.path(dir, "default-h1-20261021T010101Z.json")
  writeLines("{}", exact)
  expect_equal(basename(atlas_score_default_dir(exact)), "default-h1-20261021T010101Z")
})

test_that("score-on-E2 refuses a bad --out before it reads anything", {
  touched <- FALSE
  store <- list(get = function(...) {
    touched <<- TRUE
    stop("touched")
  })
  expect_error(atlas_score_study(store, hindcast = "h1", from_release = "r1", cutoff = "2026-08-17",
                                 out = "private/tracker/", quiet = TRUE), "only under")
  expect_false(touched)
})

test_that("H6b reads the strong models only", {
  skip_if_not_installed("terra")
  places <- score_places()
  graded <- function(taxon) {
    maps <- model_maps(taxon)
    if (as.integer(sub("T", "", taxon)) > 20) maps$maxnet$grade <- "weak"
    maps
  }
  kernel <- score_grid()
  terra::values(kernel) <- -east()
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(kernel, path)
  result <- atlas_score_baselines_core(places, graded,
                                       kernel_maps_for = function(taxon) atlas_score_kernel_maps(graded(taxon), path),
                                       reps = 200)
  strong_places <- atlas_e2_place_count(places[places$taxon %in% sprintf("T%02d", 1:20), ])
  expect_equal(result$kernel$H6b$places, strong_places)
  expect_equal(result$kernel$H6b$n_taxa, 20L)
})
