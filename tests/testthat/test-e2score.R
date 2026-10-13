# The hindcast's scorer (paper E2): places, ranks, beats-effort, and the
# pre-registered tests with intervals over taxa. Baselines are scored with
# the same functions, row for row.

# A 10 x 10 grid of 10 km cells; rank rises west to east.
score_grid <- function() {
  terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1e5, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)
}
cell_xy_of <- function(grid) function(cell) terra::xyFromCell(grid, cell)

rising_map <- function(grid, west_outside = FALSE, grade = "strong") {
  suitability <- grid
  xy <- terra::xyFromCell(grid, seq_len(terra::ncell(grid)))
  terra::values(suitability) <- xy[, 1] + xy[, 2] / 1e3
  dissimilarity <- grid
  terra::values(dissimilarity) <- if (west_outside) ifelse(xy[, 1] < 2e4, 2, 0) else 0
  list(layers = atlas_tracker_layers(suitability, dissimilarity, threshold = 1), grade = grade)
}

test_that("finds of a taxon in one cell are one place, and a place is new beyond 5 km", {
  grid <- score_grid()
  cell <- function(x, y) terra::cellFromXY(grid, cbind(x, y))
  finds <- data.frame(taxon = c("A", "A", "A", "B"),
                      cell = c(cell(5e3, 5e3), cell(5e3, 5e3), cell(85e3, 5e3), cell(45e3, 45e3)),
                      observed_after = c(FALSE, TRUE, FALSE, FALSE), stringsAsFactors = FALSE)
  training <- data.frame(taxon = c("A", "B"), x = c(5e3, 0), y = c(5e3, 0))
  places <- atlas_e2_places(finds, training, cell_xy_of(grid))
  expect_equal(nrow(places), 3L)
  first <- places[places$taxon == "A" & places$cell == cell(5e3, 5e3), ]
  expect_equal(first$finds, 2L)
  expect_true(first$observed_after)
  expect_false(first$new_place)
  expect_equal(first$band, "0-5")
  far <- places[places$taxon == "A" & places$cell == cell(85e3, 5e3), ]
  expect_true(far$new_place)
  expect_equal(far$band, "25-100")
  expect_equal(atlas_e2_band(c(0, 4.9, 5, 30, 499, 501, NA)),
               c("0-5", "0-5", "5-25", "25-100", "100-500", "500+", NA))
})

test_that("a place is ranked on each of its taxon's maps, and kept apart outside a map's applicability", {
  grid <- score_grid()
  places <- data.frame(taxon = c("A", "A", "B"), cell = c(1L, 10L, 55L), x = c(5e3, 95e3, 45e3),
                       y = c(95e3, 95e3, 45e3), stringsAsFactors = FALSE)
  maps <- list(A = list(maxnet = rising_map(grid, west_outside = TRUE), rf = rising_map(grid, grade = "weak")))
  scored <- atlas_e2_score(places, function(taxon) maps[[taxon]])
  a <- scored[scored$taxon == "A", ]
  expect_equal(nrow(a), 4L)
  expect_equal(a$place[a$map == "maxnet" & a$cell == 1L], "outside_aoa")
  expect_true(is.na(a$rank[a$map == "maxnet" & a$cell == 1L]))
  expect_equal(a$place[a$map == "rf" & a$cell == 1L], "inside")
  # The eastern place is near the top of every map.
  expect_true(all(a$rank[a$cell == 10L] > 0.9))
  expect_equal(a$grade[a$map == "rf"], c("weak", "weak"))
  # A taxon with no map is one row, counted apart.
  expect_equal(scored$place[scored$taxon == "B"], "no_map")
})

test_that("beats effort compares a place with where every other taxon's places landed, ties half", {
  grid <- score_grid()
  # A's place in the east; the other taxa's places west, at the same cell and east.
  places <- data.frame(taxon = c("A", "B", "C", "D"), cell = c(10L, 1L, 10L, 91L),
                       x = c(95e3, 5e3, 95e3, 5e3), y = c(95e3, 95e3, 95e3, 5e3),
                       stringsAsFactors = FALSE)
  map <- list(maxnet = rising_map(grid))
  scored <- atlas_e2_score(places, function(taxon) if (taxon == "A") map)
  a <- scored[scored$taxon == "A", ]
  # Others' cells: 1, 10, 91. A beats the two western ones and ties itself.
  expect_equal(a$beats_effort, (2 + 0.5) / 3)
})

test_that("shares are reported from 30 ranked places, counts always", {
  rows <- data.frame(taxon = rep(c("A", "B"), 15), rank = c(rep(0.8, 20), rep(0.2, 10)),
                     place = "inside", beats_effort = 0.7, stringsAsFactors = FALSE)
  metrics <- atlas_e2_metrics(rows)
  expect_equal(metrics$ranked, 30L)
  expect_equal(metrics$top_half, 20 / 30)
  expect_equal(metrics$beats_effort, 0.7)
  few <- atlas_e2_metrics(rows[1:29, ])
  expect_null(few$top_half)
  expect_false(few$tested)
  with_apart <- rbind(rows, data.frame(taxon = "C", rank = NA, place = c("outside_aoa", "beyond_reach"),
                                       beats_effort = NA))
  expect_equal(atlas_e2_metrics(with_apart)$outside_aoa, 1L)
  expect_equal(atlas_e2_metrics(with_apart)$beyond_reach, 1L)
  expect_equal(atlas_e2_metrics(with_apart)$ranked, 30L)
})

# Rows for taxa whose places rank as rank_of(taxon index) says.
taxon_rows <- function(n_taxa, per_taxon, rank_of, grade = "strong", seed = 1) {
  set.seed(seed)
  do.call(rbind, lapply(seq_len(n_taxa), function(i) data.frame(
    taxon = sprintf("T%03d", i), map = "maxnet", cell = seq_len(per_taxon), grade = grade,
    rank = pmin(1, pmax(0, rank_of(i, per_taxon))), place = "inside",
    beats_effort = pmin(1, pmax(0, rank_of(i, per_taxon))), stringsAsFactors = FALSE
  )))
}

test_that("intervals come from resampling taxa, so one big taxon cannot carry the result", {
  # One taxon with 200 places all high; twenty with 2 places each all low.
  rows <- rbind(taxon_rows(1, 200, function(i, n) rep(0.9, n)),
                transform(taxon_rows(20, 2, function(i, n) rep(0.1, n)), taxon = paste0("S", taxon)))
  b <- atlas_e2_bootstrap(rows, atlas_e2_share, reps = 2000, seed = 3)
  expect_equal(b$estimate, 200 / 240)
  # Resampling places would give a tight interval around 0.83; resampling
  # taxa lets the one big taxon drop out.
  expect_lt(b$low, 0.5)
  expect_equal(atlas_e2_bootstrap(rows, atlas_e2_share, reps = 2000, seed = 3), b)
})

test_that("C2 holds only when strong maps beat chance, failed maps and effort", {
  good <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1))
  failed <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), grade = "failed", seed = 2)
  failed$taxon <- paste0("F", failed$taxon)
  h <- atlas_e2_hypotheses(rbind(good, failed), reps = 1000)
  expect_true(h$H2a$holds)
  expect_true(h$H2b$holds)
  expect_true(h$H2c$holds)
  expect_true(h$C2)
  chance <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), seed = 4)
  h <- atlas_e2_hypotheses(rbind(chance, failed), reps = 1000)
  expect_false(h$H2a$holds)
  expect_false(h$C2)
  # A grade with too few ranked places is reported, not tested.
  h <- atlas_e2_hypotheses(rbind(good[1:20, ], failed), reps = 200)
  expect_false(h$H2a$tested)
  expect_false(h$C2)
})

test_that("strong maps beat the distance kernel only when their paired lower bound is above zero", {
  models <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.5, 1))
  better_kernel <- models
  better_kernel$rank <- pmin(1, models$rank + 0.05)
  worse_kernel <- models
  worse_kernel$rank <- stats::runif(nrow(models), 0, 1)
  expect_true(atlas_e2_paired(models, worse_kernel, reps = 1000)$holds)
  expect_false(atlas_e2_paired(models, better_kernel, reps = 1000)$holds)
  expect_false(atlas_e2_paired(models, models, reps = 500)$holds)
  expect_error(atlas_e2_paired(models, worse_kernel[-1, ], reps = 10), "kernel row")
})

test_that("beats effort never counts the taxon's own places among where people collected", {
  grid <- score_grid()
  places <- data.frame(taxon = c("A", "B", "D"), cell = c(10L, 1L, 91L),
                       x = c(95e3, 5e3, 5e3), y = c(95e3, 95e3, 5e3), stringsAsFactors = FALSE)
  map <- list(maxnet = rising_map(grid))
  scored <- atlas_e2_score(places, function(taxon) if (taxon == "A") map)
  expect_equal(scored$beats_effort[scored$taxon == "A"], 1)
})

test_that("an edge over the kernel carried by one taxon does not pass the paired test", {
  models <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.5, 1))
  kernel <- models
  # The kernel matches the model everywhere but one taxon, where it is worse.
  kernel$rank[kernel$taxon == "T001"] <- 0
  result <- atlas_e2_paired(models, kernel, reps = 1000)
  expect_gt(result$estimate, 0)
  expect_false(result$holds)
})
