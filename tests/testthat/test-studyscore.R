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

# A distance study's shards as a study job publishes them: under
# study/<job>/, every shard's results file and kernels directory named
# distance-<release>-<stamp>, the same prefix with different stamps.
published_kernels <- function(store, job, release, shards, taxa_of = function(i) sprintf("T%02d", i)) {
  for (i in seq_along(shards)) {
    stamp <- sprintf("20261020T0101%02dZ", i)
    key <- sprintf("study/%s/distance-%s-%s", job, release, stamp)
    file <- tempfile(fileext = ".json")
    jsonlite::write_json(list(settings = list(release = release, shard = shards[[i]]),
                              taxa = lapply(taxa_of(i), function(t) list(taxon = t, status = "scored"))),
                         file, auto_unbox = TRUE)
    store$put(paste0(key, ".json"), file)
    for (taxon in taxa_of(i)) {
      tif <- tempfile(fileext = ".tif")
      writeLines(paste("kernel of", taxon), tif)
      store$put(sprintf("%s/kernels/%s.tif", key, tolower(taxon)), tif)
    }
  }
}

test_that("--kernels-from fetches every shard of a distance study job and finds each taxon's kernel", {
  store <- fresh_store()
  published_kernels(store, "e6b", "h1", c("1/2", "2/2"))
  fetched <- atlas_score_fetch_kernels(store, "e6b")
  expect_length(fetched$paths, 2L)
  expect_equal(fetched$kernels, 2L)
  run <- atlas_score_run(fetched$paths, "h1", dirs = fetched$dir)
  expect_length(run$rows, 2L)
  for (taxon in c("T01", "T02")) {
    expect_true(file.exists(atlas_score_find(run$dirs, atlas_distance_raster_path, taxon)), info = taxon)
  }
  # By name alone the shards' directories cannot be told apart: that is why
  # the fetch merges them.
  expect_error(atlas_score_run(fetched$paths, "h1"), "no directory|more than one")
  expect_error(atlas_score_fetch_kernels(store, "nothing"), "no results file under study/nothing/")
})

test_that("--kernels-from reads shard-numbered names and the older names without a shard alike", {
  store <- fresh_store()
  published_kernels(store, "e6b", "h1", c("1/3", "2/3"))
  # Shard 3 as a study job now names it: shard-3of3, the same start second.
  out <- atlas_study_out("study/e6b/", "distance-studies", "draft", "h1", shard = "3/3",
                         stamp = "20261020T010101Z")
  expect_equal(out$prefix, "distance-h1-shard-3of3")
  results <- file.path(dirname(out$dir), paste0(out$prefix, "-20261020T010101Z.json"))
  jsonlite::write_json(list(settings = list(release = "h1", shard = "3/3"),
                            taxa = list(list(taxon = "T03", status = "scored"))), results, auto_unbox = TRUE)
  dir.create(file.path(out$dir, "kernels"))
  writeLines("kernel of T03", file.path(out$dir, "kernels", "t03.tif"))
  atlas_study_publish(store, c(results, file.path(out$dir, "kernels", "t03.tif")), out$key, root = dirname(out$dir))
  fetched <- atlas_score_fetch_kernels(store, "e6b")
  expect_length(fetched$paths, 3L)
  expect_equal(fetched$kernels, 3L)
  run <- atlas_score_run(fetched$paths, "h1", dirs = fetched$dir)
  expect_length(run$rows, 3L)
  expect_true(file.exists(atlas_score_find(run$dirs, atlas_distance_raster_path, "T03")))
})

test_that("--kernels-from refuses a kernel that two shards both hold, and both kernel sources at once", {
  store <- fresh_store()
  published_kernels(store, "e6b", "h1", c("1/2", "2/2"), taxa_of = function(i) "T01")
  expect_error(atlas_score_fetch_kernels(store, "e6b"), "a kernel appears in two shards")
  expect_error(atlas_score_study(store = NULL, hindcast = "h1", kernels = "a.json", kernels_from = "e6b",
                                 view = list(), full_pull = data.frame(), quiet = TRUE),
               "--kernels or --kernels-from, not both")
})

# A distance study job as it publishes: each shard's rows (taxon = status)
# in its results file, and a kernel for each scored taxon only.
distance_job <- function(store, job, release, shards) {
  for (i in seq_along(shards)) {
    key <- sprintf("study/%s/distance-%s-shard-%s-20261020T0101%02dZ", job, release,
                   sub("/", "of", names(shards)[[i]]), i)
    status <- shards[[i]]
    file <- tempfile(fileext = ".json")
    jsonlite::write_json(list(settings = list(release = release, shard = names(shards)[[i]]),
                              taxa = lapply(names(status), function(t) list(taxon = t, status = status[[t]]))),
                         file, auto_unbox = TRUE)
    store$put(paste0(key, ".json"), file)
    for (taxon in names(status)[unlist(status) == "scored"]) {
      tif <- tempfile(fileext = ".tif")
      writeLines(paste("kernel of", taxon, "from", job), tif)
      store$put(sprintf("%s/kernels/%s.tif", key, tolower(taxon)), tif)
    }
  }
}

test_that("a patch job's kernels replace the main run's mismatches, and nothing else", {
  store <- fresh_store()
  distance_job(store, "e6b", "h1", list("1/2" = list(T01 = "scored", T02 = "mismatch"),
                                        "2/2" = list(T03 = "scored", T04 = "mismatch")))
  distance_job(store, "patch", "h1", list("1/1" = list(T02 = "scored", T04 = "mismatch")))
  run <- atlas_score_kernel_runs(store, c("e6b", "patch"), "h1")
  status <- stats::setNames(vapply(run$rows, `[[`, "", "status"), vapply(run$rows, `[[`, "", "taxon"))
  expect_equal(status[c("T01", "T02", "T03", "T04")], c(T01 = "scored", T02 = "scored", T03 = "scored", T04 = "mismatch"))
  expect_equal(run$files, 3L)
  expect_equal(run$patched, list(patch = list("T02")))
  # T02's kernel is the patch's; T04, still a mismatch, has none.
  found <- atlas_score_find(run$dirs, atlas_distance_raster_path, "T02")
  expect_equal(readLines(found), "kernel of T02 from patch")
  expect_null(atlas_score_find(run$dirs, atlas_distance_raster_path, "T04"))
  # One job alone reads as before.
  alone <- atlas_score_kernel_runs(store, "e6b", "h1")
  expect_null(atlas_score_find(alone$dirs, atlas_distance_raster_path, "T02"))
  expect_length(alone$patched, 0L)
})

test_that("a patch is refused for a taxon already scored or never tried, and for a repeated job", {
  store <- fresh_store()
  distance_job(store, "e6b", "h1", list("1/1" = list(T01 = "scored", T02 = "mismatch")))
  distance_job(store, "twice", "h1", list("1/1" = list(T01 = "scored")))
  distance_job(store, "retried", "h1", list("1/1" = list(T01 = "mismatch")))
  distance_job(store, "stranger", "h1", list("1/1" = list(T09 = "scored")))
  distance_job(store, "other", "h2", list("1/1" = list(T02 = "scored")))
  expect_error(atlas_score_kernel_runs(store, c("e6b", "twice"), "h1"), "patch job twice holds T01, which e6b already scored")
  # Even when the patch did not score it: a patch is only of unscored taxa.
  expect_error(atlas_score_kernel_runs(store, c("e6b", "retried"), "h1"), "patch job retried holds T01, which e6b already scored")
  # A second patch may not redo what the first patch scored.
  distance_job(store, "patch", "h1", list("1/1" = list(T02 = "scored")))
  distance_job(store, "again", "h1", list("1/1" = list(T02 = "scored")))
  expect_error(atlas_score_kernel_runs(store, c("e6b", "patch", "again"), "h1"), "holds T02, which patch already scored")
  expect_error(atlas_score_kernel_runs(store, c("e6b", "stranger"), "h1"), "holds T09, which e6b never tried")
  expect_error(atlas_score_kernel_runs(store, c("e6b", "other"), "h1"), "not of hindcast h1")
  expect_error(atlas_score_kernel_runs(store, c("e6b", "e6b"), "h1"), "distinct job ids")
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


# --- The split checks, each on its own --------------------------------------------

test_that("a later find among the hindcast's records stops the run even when the training records match", {
  split <- list(training_keys = c("inat:1", "inat:2"), excluded_keys = character(),
                finds = data.frame(key = c("inat:2", "inat:9"), kept_apart = c("held", NA), stringsAsFactors = FALSE))
  # The training records are the hindcast's, yet a held later find is one
  # of them: only an excluded find may be.
  expect_error(atlas_score_check_split(split, c("inat:1", "inat:2")), "not excluded")
  split$finds$kept_apart[1] <- "excluded"
  expect_length(atlas_score_check_split(split, c("inat:1", "inat:2")), 0L)
  # A training gap that an exclusion explains is returned as a known leak.
  leak <- list(training_keys = "inat:1", excluded_keys = "inat:2",
               finds = data.frame(key = "inat:2", kept_apart = "excluded", stringsAsFactors = FALSE))
  expect_equal(atlas_score_check_split(leak, c("inat:1", "inat:2")), "inat:2")
  expect_error(atlas_score_check_split(leak, c("inat:1", "inat:2", "inat:3")), "not the hindcast's")
})

# --- Refits of the hindcast -------------------------------------------------------

test_that("a refit is used only if it refits this hindcast, and no taxon twice", {
  views <- list(
    r1 = list(manifest = list(refit = list(hindcast = "h1", taxa = list("T01")))),
    r2 = list(manifest = list(refit = list(hindcast = "h1", taxa = list("T01", "T02")))),
    other = list(manifest = list(refit = list(hindcast = "h9", taxa = list("T03")))),
    plain = list(manifest = list(purpose = "hindcast"))
  )
  view_of <- function(store, id, grid) views[[id]]
  got <- atlas_score_refits(NULL, "r1", "h1", view_of = view_of)
  expect_equal(got[[1]]$taxa, "T01")
  expect_error(atlas_score_refits(NULL, "other", "h1", view_of = view_of), "not a refit of hindcast h1")
  expect_error(atlas_score_refits(NULL, "plain", "h1", view_of = view_of), "not a refit")
  expect_error(atlas_score_refits(NULL, c("r1", "r2"), "h1", view_of = view_of), "two refits both refit T01")
  expect_length(atlas_score_refits(NULL, character(), "h1", view_of = view_of), 0L)
})

test_that("a refitted taxon is scored on the refit's maps, every other taxon on the hindcast's", {
  skip_if_not_installed("terra")
  world <- score_world()
  seen <- list()
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) {
    seen[[taxon]] <<- view$which %||% "hindcast"
    list(maxnet = list(layers = world$layers, grade = "strong", learner = "maxnet", kind = "model"))
  })
  refit <- list(list(id = "r1", taxa = "T01", view = list(which = "refit")))
  result <- with_data_dir(atlas_score_study(store = NULL, hindcast = "h1", view = world$view, full_pull = world$pull,
                                            reps = 20, quiet = TRUE, refit_views = refit))
  expect_equal(seen[["T01"]], "refit")
  expect_equal(seen[["T02"]], "hindcast")
  expect_equal(result$settings$refits, list(list(release = "r1", taxa = list("T01"))))
})

# --- Exploratory splits (the independent review, 2026-10-25; not registered) ---

# Strong and failed models in two site bands: strong ranks the east (where the
# places are) high and failed ranks it low, so the ordering holds in each band.
banded_maps <- function(taxon) {
  i <- as.integer(sub("^T", "", taxon))
  strong <- i %% 2 == 1
  sites <- if (i <= 20) 8L else 60L
  list(maxnet = list(layers = layers_from(if (strong) east() else -east(), outside_west = TRUE),
                     grade = if (strong) "strong" else "failed", learner = "maxnet", kind = "model",
                     sites = sites, z = if (strong) 2.5 else -0.5))
}

test_that("H2a-c are read again within each model's site band, labelled exploratory", {
  skip_if_not_installed("terra")
  result <- atlas_score_baselines_core(score_places(), banded_maps, reps = 200)
  bands <- result$exploratory$by_site_band
  expect_equal(bands$label, "exploratory")
  expect_equal(bands$without_sites, 0L)
  expect_setequal(setdiff(names(bands), c("label", "without_sites")), c("3-4", "5-19", "20-49", "50-99", "100+"))
  for (b in c("5-19", "50-99")) {
    expect_equal(bands[[b]]$taxa, 20L, info = b)
    expect_true(bands[[b]]$H2b$tested, info = b)
    expect_gt(bands[[b]]$H2b$estimate, 0.5)
  }
  expect_equal(bands[["3-4"]]$taxa, 0L)
  expect_false(isTRUE(bands[["3-4"]]$H2a$tested))
  # The registered hypotheses are unchanged by the split.
  expect_true(result$hypotheses$H2b$holds)
})

test_that("each model's later-find ranks sit beside its null-test z, with taxon names and numbers only", {
  skip_if_not_installed("terra")
  result <- atlas_score_baselines_core(score_places(), banded_maps, reps = 100)
  per <- result$exploratory$per_model
  expect_equal(nrow(per), 40L)
  expect_setequal(names(per), c("taxon", "learner", "grade", "tier", "sites", "z", "places", "mean_rank", "top_half"))
  t01 <- per[per$taxon == "T01", ]
  expect_equal(t01$z, 2.5)
  expect_equal(t01$sites, 8L)
  expect_gt(t01$mean_rank, per$mean_rank[per$taxon == "T02"])
  # No place, record or coordinate.
  expect_length(intersect(names(per), c("x", "y", "place", "lat", "lng", "latitude", "longitude", "cell", "id")), 0L)
})

test_that("a model's z is read from its shift null test, and is missing for a scattered one", {
  shift <- list(null = list(design = "shift", observed_auc = 0.8, auc_mean = 0.6, auc_sd = 0.05), presences = 33)
  expect_equal(atlas_score_z(shift), 4)
  expect_true(is.na(atlas_score_z(list(null = list(design = "scatter", observed_auc = 0.8, auc_mean = 0.6, auc_sd = 0.05)))))
  expect_true(is.na(atlas_score_z(list(null = list(design = "shift", observed_auc = 0.8, auc_mean = 0.6, auc_sd = 0)))))
  expect_equal(atlas_score_sites(shift), 33L)
  expect_true(is.na(atlas_score_sites(list())))
# A default-practice study job as it publishes (R/studydefault.R): each
# shard's results file, and its maps in the directory beside it.
published_defaults <- function(store, job, release, shards, taxa_of = function(i) sprintf("T%02d", i)) {
  for (i in seq_along(shards)) {
    out <- atlas_study_out(paste0("study/", job, "/"), "default-studies", "draft", release, shard = shards[[i]],
                           stamp = "20261025T164500Z")
    results <- file.path(dirname(out$dir), paste0(out$prefix, "-20261025T164500Z.json"))
    taxa <- taxa_of(i)
    jsonlite::write_json(list(settings = list(release = release, shard = shards[[i]]),
                              taxa = lapply(taxa, function(t) list(taxon = t, status = "scored"))),
                         results, auto_unbox = TRUE)
    dir.create(file.path(out$dir, "maps"), recursive = TRUE, showWarnings = FALSE)
    maps <- vapply(taxa, function(t) {
      path <- atlas_default_raster_path(out$dir, t)
      writeLines(paste("map of", t), path)
      path
    }, "")
    atlas_study_publish(store, c(results, maps), out$key, root = dirname(out$dir))
  }
}

test_that("--defaults-from fetches every shard of a default-practice study job and finds each taxon's map", {
  store <- fresh_store()
  published_defaults(store, "e6a", "h1", c("1/2", "2/2"))
  fetched <- atlas_score_fetch_defaults(store, "e6a")
  expect_length(fetched$paths, 2L)
  expect_equal(fetched$maps, 2L)
  run <- atlas_score_run(fetched$paths, "h1", dirs = fetched$dir)
  expect_length(run$rows, 2L)
  for (taxon in c("T01", "T02")) {
    expect_true(file.exists(atlas_score_find(run$dirs, atlas_default_raster_path, taxon)), info = taxon)
  }
  expect_error(atlas_score_fetch_defaults(store, "nothing"), "no results file under study/nothing/")
})

test_that("--defaults-from refuses a map two shards both hold, both default sources at once, and two jobs", {
  store <- fresh_store()
  published_defaults(store, "e6a", "h1", c("1/2", "2/2"), taxa_of = function(i) "T01")
  expect_error(atlas_score_fetch_defaults(store, "e6a"), "a map appears in two shards")
  expect_error(atlas_score_study(store = NULL, hindcast = "h1", defaults = "a.json", defaults_from = "e6a",
                                 view = list(), full_pull = data.frame(), quiet = TRUE),
               "--defaults or --defaults-from, not both")
  expect_error(atlas_score_study(store = NULL, hindcast = "h1", defaults_from = c("a", "b"),
                                 view = list(), full_pull = data.frame(), quiet = TRUE),
               "one default-practice study job")
})

test_that("score-on-E2 fetches E6a's run from its study job when given --defaults-from", {
  view <- list(manifest = list(purpose = "hindcast", validated_through = "2026-08-17", from_release = "r1"))
  expect_error(atlas_score_study(store = NULL, hindcast = "h1", defaults_from = "e6a", view = view,
                                 full_pull = data.frame(), quiet = TRUE,
                                 fetch_defaults = function(store, job) stop("fetched ", job, call. = FALSE)),
               "fetched e6a")
})
