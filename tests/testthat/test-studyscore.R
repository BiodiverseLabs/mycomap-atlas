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

# --- The review's guards ----------------------------------------------------------

test_that("the combined map is scored for E15 but never enters the grades or the hypotheses", {
  skip_if_not_installed("terra")
  places <- score_places()
  with_combined <- function(taxon) {
    maps <- model_maps(taxon)
    # A combined map that ranks the east lowest: if it counted, strong maps
    # would look poor.
    maps$combined <- list(layers = layers_from(-east()), grade = "strong", learner = "combined", kind = "combined")
    maps
  }
  plain <- atlas_score_baselines_core(places, model_maps, reps = 200)
  both <- atlas_score_baselines_core(places, with_combined, reps = 200)
  expect_equal(both$models$by_grade, plain$models$by_grade)
  expect_equal(both$hypotheses$H2a$estimate, plain$hypotheses$H2a$estimate)
  expect_true(both$models$combined$all$tested)
  expect_lt(both$models$combined$all$top_half, 0.5)
})

test_that("H6b on new places counts the new places only, and both sides cover the kernel's taxa only", {
  skip_if_not_installed("terra")
  places <- score_places()
  west <- score_grid()
  terra::values(west) <- -east()
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(west, path)
  # Kernels for the first 20 taxa only.
  kernel_for <- function(taxon) {
    if (as.integer(sub("T", "", taxon)) > 20) return(NULL)
    atlas_score_kernel_maps(model_maps(taxon), path)
  }
  result <- atlas_score_baselines_core(places, model_maps, kernel_maps_for = kernel_for, reps = 200)
  half <- places[places$taxon %in% sprintf("T%02d", 1:20), ]
  expect_equal(result$kernel$H6b$places, atlas_e2_place_count(half))
  expect_equal(result$kernel$H6b_new$places, atlas_e2_place_count(half[half$new_place, ]))
  expect_equal(result$kernel$models_same_taxa$strong$all$taxa, 20L)
  expect_equal(result$kernel$paired_by_grade$strong$all$taxa, 20L)
  expect_true(is.finite(result$kernel$H6b$mean_rank_difference$estimate))
})

test_that("E2's own hypotheses are part of the results", {
  skip_if_not_installed("terra")
  result <- atlas_score_baselines_core(score_places(), model_maps, reps = 200)
  expect_true(all(c("H2a", "H2b", "H2c", "C2") %in% names(result$hypotheses)))
  expect_true(result$hypotheses$H2a$holds)
})

test_that("the visitor's map is the combined map, else the best strong map, else none", {
  skip_if_not_installed("terra")
  layers <- layers_from(east())
  model <- c(layers, list(grade = "strong", metrics = list(), aoa = TRUE))
  weak <- c(layers, list(grade = "weak", metrics = list(), aoa = TRUE))
  local_mocked_bindings(atlas_tracker_maps = function(view, taxon) {
    switch(taxon,
           ens = list(none = FALSE, models = list(maxnet = model, rf = model), grade = "strong",
                      choice = list(kind = "ensemble"), ensemble = c(layers, list(known = rep(1, 100), aoa = TRUE))),
           best = list(none = FALSE, models = list(maxnet = weak, rf = model), grade = "strong",
                       choice = list(kind = "model", algorithm = "rf"), ensemble = NULL),
           weak = list(none = FALSE, models = list(maxnet = weak), grade = "weak", choice = NULL, ensemble = NULL),
           list(none = TRUE))
  })
  ens <- atlas_score_model_maps(list(), "ens")
  expect_equal(ens$combined$kind, "combined")
  expect_equal(ens$combined$known, rep(1, 100))
  best <- atlas_score_model_maps(list(), "best")
  expect_equal(best$combined$learner, "rf")
  expect_equal(best$maxnet$grade, "weak")
  expect_null(atlas_score_model_maps(list(), "weak")$combined)
  expect_null(atlas_score_model_maps(list(), "none"))
})

baseline_run <- function(dir, release, shards, taxa_of = function(i) sprintf("T%02d", i)) {
  vapply(seq_along(shards), function(i) {
    prefix <- sprintf("distance-%s-s%d", release, i)
    dir.create(file.path(dir, paste0(prefix, "-20261020T010101Z")), recursive = TRUE, showWarnings = FALSE)
    path <- file.path(dir, paste0(prefix, "-20261020T010101Z.json"))
    jsonlite::write_json(list(settings = list(release = release, shard = shards[[i]]),
                              taxa = lapply(taxa_of(i), function(t) list(taxon = t, status = "scored"))),
                         path, auto_unbox = TRUE)
    path
  }, "")
}

test_that("a baseline run is taken whole and only if it was run on this hindcast", {
  dir <- tempfile("runs-")
  whole <- baseline_run(dir, "h1", c("1/2", "2/2"))
  run <- atlas_score_run(whole, "h1")
  expect_length(run$dirs, 2L)
  expect_length(run$rows, 2L)
  expect_error(atlas_score_run(whole, "R_main"), "not of hindcast")
  expect_error(atlas_score_run(whole[1], "h1"), "missing shards")
  expect_error(atlas_score_run(c(whole[1], whole[1]), "h1"), "twice")
  mixed <- baseline_run(tempfile("runs-"), "h1", c("1/2", "2/3"))
  expect_error(atlas_score_run(mixed, "h1"), "different splits")
  again <- baseline_run(tempfile("runs-"), "h1", c("1/2", "2/2"), taxa_of = function(i) "T01")
  expect_error(atlas_score_run(again, "h1"), "two shards")
})

# A small hindcast as study-score reads it: its manifest, its pull's keys
# and names; and the full pull of the release it came from.
score_world <- function() {
  set.seed(5)
  n <- 120
  pull <- data.frame(
    id = as.character(1000 + seq_len(n)), source = "inat", observation_id = as.character(seq_len(n)),
    scientific_name = rep(sprintf("T%02d", 1:40), length.out = n),
    latitude = as.character(40 + stats::runif(n, 0, 0.5)), longitude = as.character(-85 + stats::runif(n, 0, 0.5)),
    first_green_on = ifelse(seq_len(n) <= 80, "2026-07-01", "2026-09-01"),
    observed_on = "2026-06-01", stringsAsFactors = FALSE
  )
  view <- list(
    manifest = list(purpose = "hindcast", validated_through = "2026-08-17", from_release = "r1"),
    pull = data.frame(key = paste("inat", pull$observation_id[1:80], sep = ":"), stringsAsFactors = FALSE),
    names = sprintf("T%02d", 1:40), renames = NULL
  )
  xy <- atlas_albers(as.numeric(pull$latitude), as.numeric(pull$longitude))
  grid <- terra::rast(nrows = 20, ncols = 20, crs = ATLAS_CRS,
                      xmin = min(xy[, "x"]) - 5e4, xmax = max(xy[, "x"]) + 5e4,
                      ymin = min(xy[, "y"]) - 5e4, ymax = max(xy[, "y"]) + 5e4)
  suitability <- grid
  terra::values(suitability) <- seq_len(400)
  list(pull = pull, view = view, layers = atlas_tracker_layers(suitability))
}

later_places <- function(world) {
  later <- world$pull[81:120, ]
  xy <- atlas_albers(as.numeric(later$latitude), as.numeric(later$longitude))
  atlas_e2_place_count(data.frame(taxon = later$scientific_name, place = atlas_e2_square(xy[, "x"], xy[, "y"])))
}

test_that("study-score reads the cutoff and source release from the hindcast and scores its later finds", {
  skip_if_not_installed("terra")
  world <- score_world()
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) {
    list(maxnet = list(layers = world$layers, grade = "strong", learner = "maxnet", kind = "model"))
  })
  with_data_dir({
    result <- atlas_score_study(store = NULL, hindcast = "h1", view = world$view, full_pull = world$pull,
                                reps = 100, quiet = TRUE)
    expect_equal(result$settings$cutoff, "2026-08-17")
    expect_equal(result$settings$from_release, "r1")
    expect_equal(result$settings$seed, 1L)
    expect_equal(result$models$by_grade$strong$all$ranked, later_places(world))
    expect_true(file.exists(result$path))
  })
})

test_that("study-score refuses a cutoff, source release or hindcast that do not belong together", {
  skip_if_not_installed("terra")
  world <- score_world()
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) NULL)
  run <- function(..., reps = 10) {
    with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", full_pull = world$pull, reps = reps,
                                    quiet = TRUE, ...))
  }
  expect_error(run(view = world$view, cutoff = "2026-07-15"), "not the hindcast's")
  expect_error(run(view = world$view, from_release = "R_main"), "not the hindcast's")
  not_hindcast <- world$view
  not_hindcast$manifest$purpose <- "record-names"
  expect_error(run(view = not_hindcast), "not a hindcast")
  # A pull that is not the hindcast's source: its training records differ.
  other <- world$view
  other$pull <- other$pull[1:70, , drop = FALSE]
  expect_error(run(view = other), "not the hindcast's")
  # A cutoff earlier than the hindcast's records: the split would score the
  # hindcast's own training records as later finds.
  leaky <- world$view
  leaky$manifest$validated_through <- "2026-06-15"
  expect_error(run(view = leaky), "not the hindcast's")
  for (bad in list(0, -5, 2.5, NA)) expect_error(run(view = world$view, reps = bad), "whole number")
})

test_that("a later find under a name the release spells otherwise is scored under the release's name", {
  skip_if_not_installed("terra")
  world <- score_world()
  world$pull$scientific_name[81] <- "T01 (Author) Name"
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) {
    list(maxnet = list(layers = world$layers, grade = "strong", learner = "maxnet", kind = "model"))
  }, atlas_best_match = function(requested, names, renames = NULL) {
    if (identical(requested, "T01 (Author) Name")) return(list(name = "T01", how = "spelling"))
    if (requested %in% names) list(name = requested, how = "exact") else NULL
  })
  with_data_dir({
    result <- atlas_score_study(store = NULL, hindcast = "h1", view = world$view, full_pull = world$pull,
                                reps = 50, quiet = TRUE)
    expect_equal(result$models$by_grade$strong$all$unknown_name, 0L)
    expect_equal(result$models$by_grade$strong$all$ranked, later_places(world))
  })
})


test_that("each model map carries its tier from its stored metrics, and the results report by tier", {
  skip_if_not_installed("terra")
  layers <- layers_from(east())
  moderate <- list(grade = "weak", boyce = 0.2, auc_mean = 0.66,
                   null = list(design = "shift", auc_p = 0.125, reps = 40, observed_auc = 0.66, auc_mean = 0.6,
                               auc_sd = 0.03))
  local_mocked_bindings(atlas_tracker_maps = function(view, taxon) {
    list(none = FALSE, models = list(maxnet = c(layers, list(grade = "weak", metrics = moderate, aoa = TRUE))),
         grade = "weak", choice = NULL, ensemble = NULL)
  })
  maps <- atlas_score_model_maps(list(), "T01")
  expect_equal(maps$maxnet$tier, "moderate")
  expect_true(maps$maxnet$moderate_z)
  places <- score_places()
  result <- atlas_score_baselines_core(places, function(taxon) atlas_score_model_maps(list(), taxon), reps = 200)
  expect_true("moderate" %in% names(result$models$by_tier))
  expect_true("moderate_z" %in% names(result$models$by_tier))
  expect_true(result$tier_hypotheses$H2d$tested)
  expect_true(result$tier_hypotheses$H2d$holds)
})


# --- Excluded and held test finds -------------------------------------------------

test_that("a find that trained the hindcast stops the run unless it is excluded, and is then a counted leak", {
  skip_if_not_installed("terra")
  world <- score_world()
  # Record 81 trained the hindcast (its date was wrong then) but is now a
  # later find: the split no longer trains on it.
  world$view$pull <- rbind(world$view$pull, data.frame(key = "inat:81", stringsAsFactors = FALSE))
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) {
    list(maxnet = list(layers = world$layers, grade = "strong", learner = "maxnet", kind = "model"))
  })
  run <- function(...) {
    with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", view = world$view, full_pull = world$pull,
                                    reps = 50, quiet = TRUE, ...))
  }
  expect_error(run(), "not the hindcast's")
  result <- run(exclude = "1081")
  expect_equal(result$settings$excluded_leaks, 1L)
  expect_equal(result$kept_apart$excluded, 1L)
  # The excluded find is never scored: one fewer place than the later finds.
  expect_equal(result$models$by_grade$strong$all$ranked, later_places(world) - 1L)
})

test_that("a held find is kept apart and counted, and an id that is no find is counted too", {
  skip_if_not_installed("terra")
  world <- score_world()
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) {
    list(maxnet = list(layers = world$layers, grade = "strong", learner = "maxnet", kind = "model"))
  })
  result <- with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", view = world$view, full_pull = world$pull,
                                            reps = 50, quiet = TRUE, hold = c("1090", "1999")))
  expect_equal(result$kept_apart$held, 1L)
  expect_equal(result$settings$held, 2L)
  expect_equal(result$settings$ids_not_found, 1L)
  expect_equal(result$models$by_grade$strong$all$ranked, later_places(world) - 1L)
  # Excluding or holding needs the pull's record ids.
  expect_error(atlas_e2_split(world$pull[, setdiff(names(world$pull), "id")], "2026-08-17", exclude = "1081"),
               "no id column")
  # A training record cannot be excluded out of the training: the split's
  # training is the hindcast's whatever the list says.
  trained <- atlas_e2_split(world$pull, "2026-08-17", exclude = "1001")
  expect_true("inat:1" %in% trained$training_keys)
  expect_length(trained$excluded_keys, 0L)
})

test_that("record ids come from a comma list or a file, and only whole numbers", {
  expect_equal(atlas_score_ids("590501, 586958,586894"), c("590501", "586958", "586894"))
  path <- tempfile(fileext = ".txt")
  writeLines(c("# leaks that trained the hindcast", "590501", "", "598980", "590501"), path)
  expect_equal(atlas_score_ids(paste0("@", path)), c("590501", "598980"))
  expect_equal(atlas_score_ids(NULL), character())
  expect_error(atlas_score_ids("590501,inat:1"), "whole numbers")
})


test_that("an exclusion never covers a real mismatch: a wrong cutoff or an extra training record still fails", {
  skip_if_not_installed("terra")
  world <- score_world()
  world$view$pull <- rbind(world$view$pull, data.frame(key = "inat:81", stringsAsFactors = FALSE))
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) NULL)
  run <- function(view, ...) {
    with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", view = view, full_pull = world$pull,
                                    reps = 10, quiet = TRUE, exclude = "1081", ...))
  }
  # A hindcast whose cutoff is not the one its records were split at.
  early <- world$view
  early$manifest$validated_through <- "2026-06-15"
  expect_error(run(early), "not the hindcast's")
  # The hindcast lacks a record the split trains on.
  short <- world$view
  short$pull <- short$pull[short$pull$key != "inat:5", , drop = FALSE]
  expect_error(run(short), "not the hindcast's")
  # The hindcast trained on a later find that is held, not excluded.
  held <- world$view
  held$pull <- rbind(held$pull, data.frame(key = "inat:90", stringsAsFactors = FALSE))
  expect_error(run(held, hold = "1090"), "not the hindcast's|not excluded")
})

test_that("a later find among the hindcast's training records stops the run unless it is excluded", {
  skip_if_not_installed("terra")
  world <- score_world()
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) NULL)
  # The split check passes (record 81 is excluded), but a held find is also
  # one of the hindcast's records: only exclusion may cover that.
  view <- world$view
  view$pull <- rbind(view$pull, data.frame(key = c("inat:81", "inat:90"), stringsAsFactors = FALSE))
  expect_error(with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", view = view, full_pull = world$pull,
                                               reps = 10, quiet = TRUE, exclude = c("1081", "1090"),
                                               hold = "1090")),
               NA)
  expect_error(with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", view = view, full_pull = world$pull,
                                               reps = 10, quiet = TRUE, exclude = "1081", hold = "1090")),
               "not the hindcast's|not excluded")
})

test_that("an --exclude id that is no later find is refused, naming it, unless allowed", {
  skip_if_not_installed("terra")
  world <- score_world()
  world$view$pull <- rbind(world$view$pull, data.frame(key = "inat:81", stringsAsFactors = FALSE))
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) NULL)
  run <- function(...) {
    with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", view = world$view, full_pull = world$pull,
                                    reps = 10, quiet = TRUE, ...))
  }
  expect_error(run(exclude = c("1081", "109999")), "109999")
  result <- run(exclude = c("1081", "109999"), allow_missing_excludes = TRUE)
  expect_equal(result$settings$ids_not_found, 1L)
  expect_equal(result$settings$excluded_leaks, 1L)
})
