# Virtual species, the ways Maxent can account for effort, and the
# detection model.

# A world where effort and habitat are separate: the species answers to v1
# alone, while people collect far more where v2 is high. A model that does not
# account for effort learns that v2 is habitat.
confounded_world <- function(seed = 1, n = 3000) {
  set.seed(seed)
  v1 <- stats::runif(n, -2, 2)
  v2 <- stats::runif(n, -2, 2)
  records <- pmax(1L, round(exp(1.2 * v2 + stats::rnorm(n, 0, 0.5))))
  habitat <- exp(-((v1 - 0.5)^2) / 0.5)
  own <- stats::rbinom(n, records, pmin(1, 0.04 * habitat))
  data.frame(presence = as.integer(own > 0), cell = seq_len(n), x = 0, y = 0,
             v1 = v1, v2 = v2, effort = log(records - own + 1))
}

# Fresh ground on which v1 and v2 are independent: where a map that leans on
# v2 parts company with the habitat.
truth_cells <- function(n = 4000, seed = 99) {
  set.seed(seed)
  cells <- data.frame(v1 = stats::runif(n, -2, 2), v2 = stats::runif(n, -2, 2))
  attr(cells, "truth") <- exp(-((cells$v1 - 0.5)^2) / 0.5)
  cells
}

rho_with_truth <- function(score, model, world, cells) {
  scores <- atlas_score_at_effort(score, atlas_effort_level(world))(model, cells)
  stats::cor(scores, attr(cells, "truth"), method = "spearman")
}

# --- Effort modes -------------------------------------------------------------

test_that("Maxent without effort mistakes where people collect for habitat", {
  skip_if_not_installed("maxnet")
  world <- confounded_world()
  cells <- truth_cells()
  model <- atlas_fit_maxnet(world, classes = "lq", effort_mode = "none")
  # The map rises with v2, which has nothing to do with the species.
  low <- data.frame(v1 = 0.5, v2 = -1.5)
  high <- data.frame(v1 = 0.5, v2 = 1.5)
  expect_gt(atlas_suitability(model, high), 1.5 * atlas_suitability(model, low))
  expect_lt(rho_with_truth(atlas_suitability, model, world, cells), 0.97)
})

test_that("an effort offset or effort weights recover the habitat that effort confounds", {
  skip_if_not_installed("maxnet")
  for (seed in 1:3) {
    world <- confounded_world(seed)
    cells <- truth_cells()
    none <- rho_with_truth(atlas_suitability,
                           atlas_fit_maxnet(world, classes = "lq", effort_mode = "none"),
                           world, cells)
    offset <- rho_with_truth(atlas_suitability,
                             atlas_fit_maxnet(world, classes = "lq", effort_mode = "offset"),
                             world, cells)
    weights <- rho_with_truth(atlas_suitability,
                              atlas_fit_maxnet(world, classes = "lq", effort_mode = "weights"),
                              world, cells)
    expect_gt(offset, none + 0.02)
    expect_gt(weights, none + 0.02)
    expect_gt(offset, 0.97)
  }
})

test_that("the effort modes leave production Maxent exactly as it was", {
  skip_if_not_installed("maxnet")
  world <- confounded_world()
  default <- atlas_fit_maxnet(world, classes = "lq")
  none <- atlas_fit_maxnet(world, classes = "lq", effort_mode = "none")
  expect_identical(default$betas, none$betas)
  covariate <- atlas_fit_maxnet(world, classes = "lq", use_effort = TRUE)
  expect_true(any(grepl("effort", names(covariate$betas))))
  expect_false(any(grepl("effort", names(none$betas))))
})

test_that("an unknown effort mode is refused, and the offset needs the effort column", {
  skip_if_not_installed("maxnet")
  world <- confounded_world()
  expect_error(atlas_fit_maxnet(world, effort_mode = "sideways"), "unknown effort mode")
  expect_error(atlas_fit_maxnet(world[, names(world) != "effort"], effort_mode = "offset"),
               "needs the effort column")
})

# --- Detection model ----------------------------------------------------------

test_that("the detection model finds the habitat that effort confounds", {
  skip_if_not_installed("maxnet")
  skip_if_not_installed("glmnet")
  world <- confounded_world()
  cells <- truth_cells()
  model <- atlas_fit_detection(world, classes = "lq")
  expect_s3_class(model, "atlas_detection")
  expect_false(any(grepl("effort", names(model$betas))))
  none <- rho_with_truth(atlas_suitability,
                         atlas_fit_maxnet(world, classes = "lq", effort_mode = "none"),
                         world, cells)
  expect_gt(rho_with_truth(atlas_detection_suitability, model, world, cells), none + 0.02)
})

test_that("a detection model's chance of detection rises with effort, never past 1", {
  skip_if_not_installed("maxnet")
  skip_if_not_installed("glmnet")
  world <- confounded_world()
  model <- atlas_fit_detection(world, classes = "lq")
  site <- data.frame(v1 = 0.5, v2 = 0)
  quiet <- atlas_detection_suitability(model, cbind(site, effort = log(1)))
  busy <- atlas_detection_suitability(model, cbind(site, effort = log(50)))
  expect_gt(busy, quiet)
  expect_true(all(c(quiet, busy) > 0 & c(quiet, busy) <= 1))
})

test_that("the detection model refuses a table without effort", {
  skip_if_not_installed("maxnet")
  world <- confounded_world()
  expect_error(atlas_fit_detection(world[, names(world) != "effort"]), "effort column")
})

# --- Making and collecting a virtual species ---------------------------------

test_that("a habitat peaks at its optimum and fades away from it", {
  expect_equal(atlas_virtual_bell(3, optimum = 3, width = 1), 1)
  expect_lt(atlas_virtual_bell(5, 3, 1), atlas_virtual_bell(4, 3, 1))
  expect_equal(atlas_virtual_rising(2, centre = 2, scale = 1), 0.5)
  expect_gt(atlas_virtual_rising(3, 2, 1), atlas_virtual_rising(1, 2, 1))
  spec <- list(kind = "habitat", responses = list(
    list(predictor = "bio1", shape = "bell", optimum = 10, width = 2),
    list(predictor = "cover_trees", shape = "rising", centre = 0.5, scale = 0.1)
  ))
  data <- data.frame(bio1 = c(10, 10, 20), cover_trees = c(0.9, 0.1, 0.9))
  habitat <- atlas_virtual_habitat(spec, data)
  expect_equal(order(habitat, decreasing = TRUE), c(1L, 2L, 3L))
  expect_true(all(habitat >= 0 & habitat <= 1))
})

test_that("a geography species ignores the environment and fades with distance", {
  spec <- list(kind = "geography",
               centres = list(list(x = 0, y = 0, radius_km = 100)))
  data <- data.frame(x = c(0, 50e3, 300e3), y = 0, bio1 = c(-20, 10, 30))
  habitat <- atlas_virtual_habitat(spec, data)
  expect_equal(habitat[[1]], 1)
  expect_true(habitat[[2]] > habitat[[3]])
  expect_lt(habitat[[3]], 0.001)
})

test_that("collection brings in the target number of detection sites on average", {
  set.seed(4)
  habitat <- stats::runif(5000)
  records <- pmax(1L, stats::rpois(5000, 3))
  found <- vapply(1:200, function(s) {
    sum(atlas_virtual_collect(habitat, records, target = 70, seed = s) > 0)
  }, numeric(1))
  # Within four standard errors of the target.
  expect_lt(abs(mean(found) - 70), 4 * stats::sd(found) / sqrt(length(found)))
  own <- atlas_virtual_collect(habitat, records, target = 70, seed = 1)
  expect_true(all(own <= records))
  expect_true(attr(own, "rate") > 0)
})

test_that("a busier site is more likely to yield the species in the same habitat", {
  habitat <- rep(0.5, 4000)
  records <- rep(c(1L, 20L), each = 2000)
  own <- atlas_virtual_collect(habitat, records, target = 300, seed = 2)
  expect_gt(mean(own[records == 20L] > 0), 3 * mean(own[records == 1L] > 0))
})

test_that("relabelling changes only names: every site keeps its records and effort", {
  points <- fake_points(x = rep(c(0, 20e3, 40e3), times = c(5, 3, 1)), y = 0,
                        names = "Something", cells = rep(1:3, times = c(5, 3, 1)))
  points <- atlas_attach_sites(points)
  sites <- attr(points, "sites")
  rows_by_site <- split(seq_len(nrow(points)), factor(points$site, levels = sites$site))
  own <- c(2L, 0L, 1L)
  relabelled <- atlas_virtual_points(points, own, "virtual-habitat-001", rows_by_site)
  expect_equal(sum(relabelled$scientific_name == "virtual-habitat-001"), 3L)
  expect_identical(attr(relabelled, "sites"), sites)
  expect_identical(relabelled$site, points$site)
  per_site <- tapply(relabelled$scientific_name == "virtual-habitat-001", relabelled$site, sum)
  expect_equal(as.integer(per_site), own)
})

test_that("a virtual name says its kind and index, and anything else is refused", {
  name <- atlas_virtual_name("geography", 7)
  expect_equal(name, "virtual-geography-007")
  expect_equal(atlas_virtual_parse(name), list(kind = "geography", index = 7L))
  expect_error(atlas_virtual_parse("Amanita muscaria"), "not a virtual species")
  expect_false(identical(atlas_virtual_fingerprint(name, 1), atlas_virtual_fingerprint(name, 2)))
  expect_identical(atlas_virtual_fingerprint(name, 1), atlas_virtual_fingerprint(name, 1))
})

test_that("truth scores reward a map that ranks ground as the habitat does", {
  truth <- seq(0, 1, length.out = 100)
  perfect <- atlas_virtual_truth_scores(truth * 3, truth)
  expect_equal(perfect$truth_rho, 1)
  expect_equal(perfect$truth_top, 1)
  backwards <- atlas_virtual_truth_scores(-truth, truth)
  expect_equal(backwards$truth_rho, -1)
  expect_equal(backwards$truth_top, 0)
  expect_true(is.na(atlas_virtual_truth_scores(rep(1, 100), truth)$truth_rho))
})

# --- End to end ---------------------------------------------------------------

# A 1,000 km square where bio1 rises west to east and cover_trees is noise,
# collected at 900 records spread over the whole square, busier in the west.
virtual_landscape <- function() {
  set.seed(11)
  stack <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 1e6, ymin = 0, ymax = 1e6,
                       crs = ATLAS_CRS, nlyrs = 2)
  names(stack) <- c("bio1", "cover_trees")
  xy <- terra::xyFromCell(stack, seq_len(terra::ncell(stack)))
  terra::values(stack) <- cbind(xy[, 1] / 1e5, stats::runif(nrow(xy)))
  x <- c(stats::runif(600, 0, 5e5), stats::runif(300, 0, 1e6))
  y <- stats::runif(900, 0, 1e6)
  points <- fake_points(x, y, names = "Everything else")
  points$cell <- terra::cellFromXY(stack, cbind(points$x, points$y))
  centres <- terra::xyFromCell(stack, points$cell)
  points$x <- centres[, 1]
  points$y <- centres[, 2]
  list(stack = stack, points = atlas_attach_sites(points))
}

test_that("the study collects virtual species at real sites and scores every arm against the truth", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("glmnet")
  with_data_dir({
    world <- virtual_landscape()
    result <- atlas_virtual_study(
      species = 2, kinds = c("habitat", "geography"),
      arms = c("maxnet:none", "maxnet:offset", "detection"), nulls = 3L,
      n_background = 2000, buffer_km = 600, block_km = 200, folds = 3,
      quiet = TRUE, points = world$points, stack = world$stack
    )
    expect_true(file.exists(result$path))
    expect_match(result$path, "virtual-studies")
    expect_false(dir.exists(atlas_path("models")))
    saved <- jsonlite::fromJSON(result$path, simplifyVector = FALSE)
    expect_equal(saved$baseline, "maxnet:none")
    expect_equal(length(saved$taxa), 4L)
    scored <- Filter(function(r) identical(r$status, "scored"), saved$taxa)
    expect_gt(length(scored), 0L)
    for (row in scored) {
      expect_setequal(vapply(row$arms, function(a) a$arm, character(1)),
                      c("maxnet:none", "maxnet:offset", "detection"))
      rhos <- vapply(row$arms, function(a) as.numeric(a$truth_rho %||% NA), numeric(1))
      expect_true(all(is.finite(rhos)))
      expect_true(is.character(row$null$skill))
    }
    # A habitat species here answers to bio1, which every arm can see.
    habitat <- Filter(function(r) identical(r$kind, "habitat"), scored)
    if (length(habitat)) {
      best <- max(vapply(habitat[[1]]$arms, function(a) a$truth_rho, numeric(1)))
      expect_gt(best, 0.5)
    }
    summary_arms <- unique(vapply(saved$summary, function(r) r$arm, character(1)))
    expect_setequal(summary_arms, c("maxnet:none", "maxnet:offset", "detection"))
    expect_true(length(saved$nulls) > 0)
  })
})
