# "Default practice" Maxent (paper E6a): maxnet as shipped, random
# background and folds, and Raes & ter Steege's null test on training AUC.

test_that("feature classes follow maxnet's own default by sample size", {
  expect_equal(vapply(c(5, 12, 20, 79, 80, 300), atlas_default_classes, ""),
               c("l", "lq", "lqh", "lqh", "lqph", "lqph"))
})

test_that("maxnet is fitted with its shipped defaults: hinges from 15 detections, products from 80", {
  skip_if_not_installed("maxnet")
  set.seed(1)
  fit_terms <- function(n) {
    data <- data.frame(a = stats::runif(n + 300), b = stats::runif(n + 300))
    presence <- c(rep(1L, n), rep(0L, 300))
    names(atlas_default_fit(presence, data)$featuremins)
  }
  product <- function(terms) grepl("^[a-z]+:[a-z]+$", terms)
  small <- fit_terms(20)
  expect_true(any(grepl("^hinge", small)))
  expect_false(any(product(small)))
  big <- fit_terms(90)
  expect_true(any(product(big)))
})

test_that("a predictor with one value over the points is left out, as maxnet cannot fit it", {
  skip_if_not_installed("maxnet")
  set.seed(4)
  data <- data.frame(a = stats::runif(330), absent_host = 0, b = stats::runif(330))
  presence <- c(rep(1L, 30), rep(0L, 300))
  model <- atlas_default_fit(presence, data)
  expect_equal(attr(model, "constant"), "absent_host")
  expect_true(all(is.finite(atlas_default_predict(model, data))))
})

test_that("background cells are drawn uniformly inside the accessible area, each once, all predictors known", {
  skip_if_not_installed("terra")
  world <- synthetic_landscape()
  stack <- world$stack
  # A hole where one predictor is unknown: never drawn.
  ys <- terra::init(stack[[2]], "y")
  stack[[2]] <- terra::ifel(ys > 5e5 & ys < 5.5e5, NA, stack[[2]])
  hole <- which(is.na(terra::values(stack[[2]], mat = FALSE)))
  area <- atlas_accessible_area(5e5, 5e5, buffer_km = 300)
  cells <- atlas_default_cells(stack, area, 500, seed = 3)
  expect_equal(nrow(cells), 500L)
  expect_false(anyDuplicated(cells$cell) > 0)
  expect_true(all(stats::complete.cases(cells)))
  # Inside the 300 km area, give or take the cell a centre sits in.
  expect_true(all(sqrt((cells$x - 5e5)^2 + (cells$y - 5e5)^2) <= 300e3 + 5e3))
  expect_false(any(cells$cell %in% hole))
  # A cell number is the full grid's, the one its centre lies in.
  expect_equal(unname(terra::xyFromCell(stack, cells$cell)), unname(as.matrix(cells[, c("x", "y")])))
  # Uniform: the area's two halves get about the same share.
  expect_lt(abs(mean(cells$x < 5e5) - 0.5), 0.08)
  expect_equal(atlas_default_cells(stack, area, 500, seed = 3), cells)
})

test_that("random folds deal presences and background separately into every fold", {
  presence <- c(rep(1L, 23), rep(0L, 500))
  folds <- atlas_default_folds(presence, k = 5, seed = 2)
  expect_setequal(unique(folds), 1:5)
  per <- table(folds[presence == 1L])
  expect_true(all(per >= 4 & per <= 5))
  expect_true(all(table(folds[presence == 0L]) == 100))
})

test_that("the null test compares training AUC with uniform nulls fitted on the same background", {
  skip_if_not_installed("maxnet")
  set.seed(5)
  background <- data.frame(cell = 1:600, x = 0, y = 0, v1 = stats::runif(600, -3, 3), v2 = stats::runif(600))
  pool <- data.frame(cell = 601:1600, x = 0, y = 0, v1 = stats::runif(1000, -3, 3), v2 = stats::runif(1000))
  # A species tied to high v1: its training AUC beats every uniform null.
  found <- data.frame(v1 = stats::runif(25, 2, 3), v2 = stats::runif(25))
  data <- rbind(found, background[, c("v1", "v2")])
  presence <- c(rep(1L, 25), rep(0L, 600))
  model <- atlas_default_fit(presence, data)
  observed <- atlas_default_train_auc(model, presence, data)
  expect_equal(observed, atlas_auc(atlas_default_predict(model, found),
                                   atlas_default_predict(model, background[, c("v1", "v2")])))
  null <- atlas_default_null_test(observed, 25, background, pool, reps = 19, seed = 1)
  expect_equal(null$reps, 19L)
  expect_equal(null$p, 0.05)
  expect_equal(null$verdict, "passed")
  # A taxon no better than its nulls fails: with an observed AUC of 0.5,
  # most uniform nulls do at least as well.
  weak <- atlas_default_null_test(0.5, 25, background, pool, reps = 19, seed = 1)
  expect_gt(weak$p, 0.05)
  expect_equal(weak$verdict, "failed")
})

test_that("a default-practice row scores itself, writes its map in its own directory, and holds no coordinate", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  out <- tempfile("default-")
  dir.create(out)
  row <- atlas_default_taxon("Eastern fungus", "f00dfeed", world$points, world$stack, out_dir = out,
                             n_background = 600, buffer_km = 300, nulls = 5)
  expect_equal(row$status, "scored")
  expect_equal(row$classes, atlas_default_classes(row$presences))
  expect_true(is.finite(row$cv$auc))
  expect_equal(row$cv$folds_scored, 5L)
  expect_equal(row$null$reps, 5L)
  expect_true(is.numeric(row$seconds_fit) && is.numeric(row$seconds_nulls))
  expect_equal(list.files(out, recursive = TRUE), "maps/eastern-fungus.tif")
  names_in <- function(x) if (is.list(x)) c(names(x), unlist(lapply(x, names_in))) else character()
  expect_length(intersect(names_in(row), c("x", "y", "lat", "lng", "latitude", "longitude")), 0L)
  map <- terra::rast(file.path(out, "maps/eastern-fungus.tif"))
  values <- terra::values(map, mat = FALSE)
  expect_true(all(values[is.finite(values)] >= 0 & values[is.finite(values)] <= 1))
  # The taxon lives in the east, and so does its map's high ground.
  xy <- terra::xyFromCell(map, which(is.finite(values)))
  v <- values[is.finite(values)]
  expect_gt(mean(v[xy[, 1] > 8e5]), mean(v[xy[, 1] < 6e5]))
})

test_that("a taxon under the minimum is refused", {
  skip_if_not_installed("terra")
  world <- synthetic_landscape()
  row <- atlas_default_taxon("Eastern fungus", "f00dfeed", world$points, world$stack,
                             out_dir = tempfile(), min_sites = 1000)
  expect_equal(row$status, "refused")
})

test_that("a plan-only run takes taxa with 20+ sites and sizes the work", {
  view <- list(entries = list(list(taxon = "A", presences = 4), list(taxon = "B", presences = 25),
                              list(taxon = "C", presences = 90), list(taxon = "C", presences = 90),
                              list(taxon = "D", presences = 19)))
  plan <- atlas_default_study(store = NULL, release = "hindcast-test", view = view,
                              plan_only = TRUE, quiet = TRUE)
  expect_equal(plan$taxa, 2L)
  expect_equal(plan$by_classes, list(lqh = 1L, lqph = 1L))
  expect_gt(plan$cpu_hours, 0)
})

test_that("the results say how many predictors each taxon's fit left out, median and most", {
  rows <- list(list(status = "scored", constant_predictors = 0L),
               list(status = "scored", constant_predictors = 3L),
               list(status = "scored", constant_predictors = 7L),
               list(status = "refused"))
  summary <- atlas_default_constant_summary(rows)
  expect_equal(summary$taxa, 3L)
  expect_equal(c(summary$median, summary$max, summary$taxa_with_any), c(3, 7, 2))
})

test_that("a taxon whose records differ from the release's, or that it holds no record of, is not fitted", {
  skip_if_not_installed("terra")
  world <- synthetic_landscape()
  sites <- atlas_training_table("Eastern fungus", world$points, n_background = 0L, buffer_km = 300,
                                fingerprint = "f00dfeed")
  n <- nrow(atlas_add_predictors(sites[sites$presence == 1L, , drop = FALSE], stack = world$stack))
  record <- list(fingerprint = "f00dfeed", presences = as.integer(n))
  run <- function(records, fingerprint = "f00dfeed") {
    atlas_default_taxon("Eastern fungus", fingerprint, world$points, world$stack, out_dir = tempfile(),
                        n_background = 300, buffer_km = 300, nulls = 1, min_sites = 1000, records = records)
  }
  # A matching record passes the check (and is then refused only for the
  # test's high minimum).
  expect_equal(run(list("Eastern fungus" = record))$status, "refused")
  expect_equal(unlist(run(list("Eastern fungus" = record), "beefcafe")$differs), "fingerprint")
  expect_equal(unlist(run(list("Eastern fungus" = modifyList(record, list(presences = 1L))))$differs), "presences")
  expect_equal(unlist(run(list())$differs), "no record")
})
