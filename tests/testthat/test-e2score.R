# The hindcast's scorer (paper E2): places, ranks, beats-effort, and the
# pre-registered tests with intervals over taxa. Baselines are scored with
# the same functions, row for row.

# A 10 x 10 grid of 10 km cells; rank rises west to east.
score_grid <- function() {
  terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1e5, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)
}

rising_map <- function(grid, west_outside = FALSE, grade = "strong", kind = "model") {
  suitability <- grid
  xy <- terra::xyFromCell(grid, seq_len(terra::ncell(grid)))
  terra::values(suitability) <- xy[, 1] + xy[, 2] / 1e3
  dissimilarity <- grid
  terra::values(dissimilarity) <- if (west_outside) ifelse(xy[, 1] < 2e4, 2, 0) else 0
  list(layers = atlas_tracker_layers(suitability, dissimilarity, threshold = 1), grade = grade, kind = kind)
}

place_rows <- function(taxon, x, y) {
  data.frame(taxon = taxon, place = atlas_e2_square(x, y), x = x, y = y, stringsAsFactors = FALSE)
}

# --- Places -------------------------------------------------------------------

test_that("finds of a taxon in one 5 km square are one place, scored at the first find", {
  finds <- data.frame(taxon = c("A", "A", "A", "B"), x = c(1200, 3900, 85e3, 45e3),
                      y = c(1200, 2100, 1e3, 45e3), observed_after = c(FALSE, TRUE, FALSE, FALSE),
                      stringsAsFactors = FALSE)
  training <- data.frame(taxon = c("A", "B"), x = c(1000, 0), y = c(1000, 0))
  places <- atlas_e2_places(finds, training)
  expect_equal(nrow(places), 3L)
  first <- places[places$taxon == "A" & places$x == 1200, ]
  expect_equal(first$finds, 2L)
  expect_true(first$observed_after)
  expect_false(first$new_place)
  expect_equal(first$band, "0-5")
  far <- places[places$taxon == "A" & places$x == 85e3, ]
  expect_true(far$new_place)
  expect_equal(far$band, "25-100")
  expect_equal(atlas_e2_band(c(0, 4.9, 5, 30, 499, 501, NA)),
               c("0-5", "0-5", "0-5", "25-100", "100-500", "500+", NA))
  # The band's edge and the new/known line agree: 5 km is known, just over
  # it is new.
  edge <- atlas_e2_places(data.frame(taxon = "A", x = c(5000, 10001), y = 0),
                          data.frame(taxon = "A", x = 0, y = 0))
  expect_equal(edge$new_place, c(FALSE, TRUE))
  expect_equal(edge$band, c("0-5", "5-25"))
  expect_equal(ATLAS_E2_PLACE_KM, ATLAS_SITE_KM)
  expect_equal(ATLAS_E2_NEW_KM, ATLAS_SITE_KM)
})

test_that("a place is new only when every one of its finds is over 5 km from the taxon's training records", {
  # Two finds in one 5 km square: one 4 km from a training record, one 6 km.
  finds <- data.frame(taxon = "A", x = c(4000, 2000), y = c(500, 500), stringsAsFactors = FALSE)
  training <- data.frame(taxon = "A", x = -2000, y = 500)
  places <- atlas_e2_places(finds, training)
  expect_equal(nrow(places), 1L)
  expect_equal(places$known_km, 4)
  expect_false(places$new_place)
})

test_that("a place is a 5 km square whatever the model grid's cell size", {
  # Finds 3 km apart in one 5 km square are one place; 3 km apart across a
  # square's edge are two.
  finds <- data.frame(taxon = "A", x = c(500, 3500, 4500, 7500), y = 500, stringsAsFactors = FALSE)
  places <- atlas_e2_places(finds, data.frame(taxon = character(), x = numeric(), y = numeric()))
  expect_equal(nrow(places), 2L)
  expect_equal(places$finds, c(3L, 1L))
})

test_that("finds with no point are counted apart, never merged into one place", {
  finds <- data.frame(taxon = "A", x = c(NA, NA, 500), y = c(NA, NA, 500), stringsAsFactors = FALSE)
  places <- atlas_e2_places(finds, data.frame(taxon = "A", x = 0, y = 0))
  expect_equal(nrow(places), 1L)
  expect_equal(attr(places, "off_grid"), 2L)
})

# --- Scoring --------------------------------------------------------------------

test_that("a place is ranked on each of its taxon's maps, and kept apart outside a map's applicability", {
  grid <- score_grid()
  places <- rbind(place_rows("A", c(5e3, 95e3), c(95e3, 95e3)), place_rows("B", 45e3, 45e3))
  maps <- list(A = list(maxnet = rising_map(grid, west_outside = TRUE), rf = rising_map(grid, grade = "weak")))
  scored <- atlas_e2_score(places, function(taxon) maps[[taxon]])
  a <- scored[scored$taxon == "A", ]
  expect_equal(nrow(a), 4L)
  expect_equal(a$class[a$map == "maxnet" & a$x == 5e3], "outside_aoa")
  expect_true(is.na(a$rank[a$map == "maxnet" & a$x == 5e3]))
  expect_equal(a$class[a$map == "rf" & a$x == 5e3], "inside")
  expect_true(all(a$rank[a$x == 95e3] > 0.9))
  expect_equal(a$grade[a$map == "rf"], c("weak", "weak"))
  expect_equal(scored$class[scored$taxon == "B"], "no_map")
})

test_that("a name the release does not know is counted apart from a taxon with no map", {
  grid <- score_grid()
  places <- rbind(place_rows("A", 5e3, 5e3), place_rows("B", 45e3, 45e3), place_rows("Z", 5e3, 5e3))
  scored <- atlas_e2_score(places, function(taxon) if (taxon == "A") list(maxnet = rising_map(grid)),
                           known_names = c("A", "B"))
  expect_equal(scored$class[scored$taxon == "B"], "no_map")
  expect_equal(scored$class[scored$taxon == "Z"], "unknown_name")
  metrics <- atlas_e2_metrics(scored)
  expect_equal(c(metrics$no_map, metrics$unknown_name), c(1L, 1L))
})

test_that("a combined map's reach decides between outside its applicability and beyond its reach", {
  grid <- score_grid()
  map <- rising_map(grid, west_outside = TRUE, kind = "combined")
  # Nothing reaches the far west column; the rest of the west is reached.
  xy <- terra::xyFromCell(grid, seq_len(terra::ncell(grid)))
  map$known <- ifelse(xy[, 1] < 1e4, NA, 1)
  places <- place_rows("A", c(5e3, 15e3), c(50e3, 50e3))
  scored <- atlas_e2_score(places, function(taxon) list(combined = map))
  expect_equal(scored$class, c("beyond_reach", "outside_aoa"))
  expect_equal(scored$kind, c("combined", "combined"))
})

test_that("beats effort compares a place with where every other taxon's places landed, ties half", {
  grid <- score_grid()
  places <- rbind(place_rows("A", 95e3, 95e3), place_rows("B", 5e3, 95e3),
                  place_rows("C", 95e3, 95e3), place_rows("D", 5e3, 5e3))
  scored <- atlas_e2_score(places, function(taxon) if (taxon == "A") list(maxnet = rising_map(grid)))
  expect_equal(scored$beats_effort[scored$taxon == "A"], (2 + 0.5) / 3)
})

test_that("beats effort never counts the taxon's own places among where people collected", {
  grid <- score_grid()
  places <- rbind(place_rows("A", 95e3, 95e3), place_rows("B", 5e3, 95e3), place_rows("D", 5e3, 5e3))
  scored <- atlas_e2_score(places, function(taxon) if (taxon == "A") list(maxnet = rising_map(grid)))
  expect_equal(scored$beats_effort[scored$taxon == "A"], 1)
})

# --- Metrics and tests ------------------------------------------------------------

# Rows for taxa whose places rank as rank_of(taxon index) says.
taxon_rows <- function(n_taxa, per_taxon, rank_of, grade = "strong", seed = 1, prefix = "T",
                       map = "maxnet", kind = "model") {
  set.seed(seed)
  do.call(rbind, lapply(seq_len(n_taxa), function(i) {
    rank <- pmin(1, pmax(0, rank_of(i, per_taxon)))
    data.frame(taxon = sprintf("%s%03d", prefix, i), map = map, kind = kind,
               place = paste0("p", seq_len(per_taxon)), grade = grade, rank = rank,
               class = "inside", beats_effort = rank, stringsAsFactors = FALSE)
  }))
}

test_that("shares are reported from 30 distinct ranked places, however many maps scored them", {
  rows <- taxon_rows(3, 10, function(i, n) rep(0.8, n))
  expect_true(atlas_e2_metrics(rows)$tested)
  expect_equal(atlas_e2_metrics(rows)$top_half, 1)
  # 15 places, each scored by two maps: 30 rows, but only 15 places.
  doubled <- rbind(taxon_rows(3, 5, function(i, n) rep(0.8, n)),
                   taxon_rows(3, 5, function(i, n) rep(0.8, n), map = "rf"))
  metrics <- atlas_e2_metrics(doubled)
  expect_equal(metrics$ranked, 30L)
  expect_equal(metrics$ranked_places, 15L)
  expect_false(metrics$tested)
  expect_null(metrics$top_half)
})

test_that("intervals come from resampling taxa, so one big taxon cannot carry the result", {
  rows <- rbind(taxon_rows(1, 200, function(i, n) rep(0.9, n)),
                taxon_rows(20, 2, function(i, n) rep(0.1, n), prefix = "S"))
  b <- atlas_e2_bootstrap(rows, atlas_e2_share, reps = 2000, seed = 3)
  expect_equal(b$estimate, 200 / 240)
  expect_lt(b$low, 0.5)
  expect_equal(atlas_e2_bootstrap(rows, atlas_e2_share, reps = 2000, seed = 3), b)
})

test_that("a single taxon gives no interval rather than a zero-width one", {
  rows <- taxon_rows(1, 50, function(i, n) rep(0.9, n))
  b <- atlas_e2_bootstrap(rows, atlas_e2_share, reps = 200)
  expect_equal(b$estimate, 1)
  expect_true(is.na(b$low) && is.na(b$high))
  h <- atlas_e2_hypotheses(rows, reps = 200)
  expect_false(h$H2a$tested)
  expect_false(h$C2)
})

test_that("C2 holds only when strong maps beat chance, failed maps and effort", {
  good <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1))
  failed <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), grade = "failed", seed = 2, prefix = "F")
  h <- atlas_e2_hypotheses(rbind(good, failed), reps = 1000)
  expect_true(h$H2a$holds && h$H2b$holds && h$H2c$holds)
  expect_true(h$C2)
  chance <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), seed = 4)
  h <- atlas_e2_hypotheses(rbind(chance, failed), reps = 1000)
  expect_false(h$H2a$holds)
  expect_false(h$C2)
  h <- atlas_e2_hypotheses(rbind(good[1:20, ], failed), reps = 200)
  expect_false(h$H2a$tested)
  expect_false(h$C2)
})

test_that("the hypotheses read the per-model rows only, never the combined map's", {
  chance <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), seed = 4)
  failed <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), grade = "failed", seed = 2, prefix = "F")
  # A combined map that would carry H2a if it were counted.
  combined <- taxon_rows(40, 5, function(i, n) rep(1, n), map = "combined", kind = "combined")
  h <- atlas_e2_hypotheses(rbind(chance, combined, failed), reps = 1000)
  expect_false(h$H2a$holds)
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

test_that("an edge over the kernel carried by one taxon does not pass the paired test", {
  models <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.5, 1))
  kernel <- models
  kernel$rank[kernel$taxon == "T001"] <- 0
  result <- atlas_e2_paired(models, kernel, reps = 1000)
  expect_gt(result$estimate, 0)
  expect_false(result$holds)
})

test_that("the paired test compares the model and the kernel on identical places", {
  models <- taxon_rows(40, 5, function(i, n) rep(0.6, n))
  kernel <- models
  kernel$rank <- 0.6
  # Where the kernel cannot rank a place, the model's rank there is left out
  # too: here those places are the model's worst, and keeping them on one
  # side only would flatter the kernel.
  models$rank[models$place == "p1"] <- 0
  kernel$rank[kernel$place == "p1"] <- NA
  kernel$class[kernel$place == "p1"] <- "outside_aoa"
  result <- atlas_e2_paired(models, kernel, reps = 200)
  expect_equal(result$estimate, 0)
  expect_equal(result$places, 160L)
})

test_that("a grade is tested only from 30 distinct places, not 30 rows", {
  # 15 strong places, each ranked by two models: 30 rows.
  strong <- rbind(taxon_rows(15, 1, function(i, n) rep(0.9, n)),
                  taxon_rows(15, 1, function(i, n) rep(0.9, n), map = "rf"))
  h <- atlas_e2_hypotheses(strong, reps = 200)
  expect_false(h$H2a$tested)
})

test_that("a taxon with no training records has only new places, as the tracker counts them", {
  places <- atlas_e2_places(data.frame(taxon = "A", x = 500, y = 500),
                            data.frame(taxon = "B", x = 0, y = 0))
  expect_true(places$new_place)
  expect_true(is.na(places$band))
})

test_that("no finds give an empty set of places and of scored rows, which the metrics take", {
  places <- atlas_e2_places(data.frame(taxon = character(), x = numeric(), y = numeric()),
                            data.frame(taxon = character(), x = numeric(), y = numeric()))
  expect_equal(nrow(places), 0L)
  scored <- atlas_e2_score(places, function(taxon) NULL)
  expect_equal(nrow(scored), 0L)
  expect_true(all(c("rank", "class", "beats_effort") %in% names(scored)))
  metrics <- atlas_e2_metrics(scored)
  expect_equal(c(metrics$rows, metrics$ranked), c(0L, 0L))
  expect_false(metrics$tested)
})

test_that("finds off the grid are counted through to the metrics", {
  grid <- score_grid()
  finds <- data.frame(taxon = "A", x = c(NA, 95e3), y = c(NA, 95e3))
  places <- atlas_e2_places(finds, data.frame(taxon = "A", x = 0, y = 0))
  scored <- atlas_e2_score(places, function(taxon) list(maxnet = rising_map(grid)))
  expect_equal(atlas_e2_metrics(scored)$off_grid, 1L)
})

test_that("a place beyond a map's reach is counted, not ranked", {
  grid <- score_grid()
  places <- place_rows("A", 500e3, 500e3)
  scored <- atlas_e2_score(places, function(taxon) list(maxnet = rising_map(grid)))
  expect_equal(scored$class, "beyond_reach")
  expect_equal(atlas_e2_metrics(scored)$beyond_reach, 1L)
})

test_that("a place counts once on each map that scores it", {
  grid <- score_grid()
  places <- place_rows("A", c(25e3, 75e3), c(50e3, 50e3))
  scored <- atlas_e2_score(places, function(taxon) list(maxnet = rising_map(grid), rf = rising_map(grid)))
  expect_equal(nrow(scored), 4L)
  expect_equal(as.integer(table(scored$map)), c(2L, 2L))
  expect_equal(atlas_e2_place_count(scored), 2L)
})

test_that("Boyce is reported from 50 ranked places, as the tracker reports it", {
  rows <- taxon_rows(10, 4, function(i, n) stats::runif(n))
  expect_null(atlas_e2_metrics(rows)$boyce)
  rows <- taxon_rows(10, 6, function(i, n) stats::runif(n)^0.3)
  expect_true(is.finite(atlas_e2_metrics(rows)$boyce))
  expect_gt(atlas_e2_metrics(rows)$boyce, 0)
})

test_that("C2 fails when failed maps do as well as strong ones (H2b)", {
  good <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1))
  as_good <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1), grade = "failed", seed = 9, prefix = "F")
  h <- atlas_e2_hypotheses(rbind(good, as_good), reps = 1000)
  expect_true(h$H2a$holds)
  expect_false(h$H2b$holds)
  expect_false(h$C2)
})

test_that("C2 fails when strong maps rank high but do not beat collecting effort (H2c)", {
  rows <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1))
  rows$beats_effort <- stats::runif(nrow(rows), 0.3, 0.5)
  failed <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), grade = "failed", seed = 2, prefix = "F")
  h <- atlas_e2_hypotheses(rbind(rows, failed), reps = 1000)
  expect_true(h$H2a$holds && h$H2b$holds)
  expect_false(h$H2c$holds)
  expect_false(h$C2)
})

test_that("H2b is untested with fewer than 30 failed places, and C2 then cannot hold", {
  good <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1))
  failed <- taxon_rows(5, 5, function(i, n) stats::runif(n, 0, 1), grade = "failed", seed = 2, prefix = "F")
  h <- atlas_e2_hypotheses(rbind(good, failed), reps = 500)
  expect_true(h$H2a$holds)
  expect_false(h$H2b$tested)
  expect_equal(h$H2b$n_taxa, 5L)
  expect_false(h$C2)
})

test_that("H2b resamples strong and failed taxa each within their own group", {
  good <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1))
  failed <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0, 1), grade = "failed", seed = 2, prefix = "F")
  rows <- rbind(good, failed)
  sizes <- numeric()
  stat <- function(r) {
    sizes <<- c(sizes, length(unique(r$taxon[r$grade == "strong"])))
    atlas_e2_difference(function(x) x$grade == "strong", function(x) x$grade == "failed")(r)
  }
  atlas_e2_bootstrap(rows, stat, reps = 50, strata = list(strong = function(r) r$grade == "strong",
                                                         failed = function(r) r$grade == "failed"))
  # Each resample draws 40 strong taxa (with repeats), never a mix that
  # takes strong taxa's places from the failed group.
  drawn <- sizes[-1]
  expect_true(all(drawn <= 40))
  expect_gt(min(drawn), 15)
})

test_that("the bootstrap leaves the caller's random numbers as they were, and reports taxa and drops", {
  rows <- taxon_rows(10, 5, function(i, n) stats::runif(n))
  set.seed(42)
  expected <- stats::runif(1)
  set.seed(42)
  b <- atlas_e2_bootstrap(rows, function(r) if (stats::runif(1) < 0.1) NA_real_ else atlas_e2_share(r), reps = 200)
  expect_equal(stats::runif(1), expected)
  expect_equal(b$n_taxa, 10L)
  expect_gt(b$dropped, 0L)
  expect_equal(b$reps + b$dropped, 200L)
})

test_that("the pull splits into dated training records and later finds, with every kept-apart reason counted", {
  pull <- data.frame(
    scientific_name = c("A", "A", "A", "B", "B"),
    latitude = c("40", "40.1", "40.2", NA, "41"), longitude = c("-85", "-85.1", "-85", "-86", "-86"),
    first_green_on = c("2026-08-01", "2026-09-01", NA, "2026-09-10", "2026-08-17"),
    observed_on = c("2025-08-01", "2026-08-20", "2026-09-01", "2025-01-01", "2026-08-10"),
    stringsAsFactors = FALSE
  )
  split <- atlas_e2_split(pull, "2026-08-17")
  # The cutoff day itself trains.
  expect_equal(nrow(split$training), 2L)
  expect_equal(nrow(split$finds), 3L)
  expect_equal(attr(split$finds, "kept_apart"), list(undated = 1L, off_grid = 1L))
  places <- atlas_e2_places(split$finds, split$training)
  # Only the dated, located find becomes a place; the others stay counted.
  expect_equal(nrow(places), 1L)
  expect_equal(attr(places, "off_grid"), 2L)
  observed <- atlas_e2_split(pull, "2026-08-17", observed_after = TRUE)
  expect_equal(sum(is.na(observed$finds$kept_apart)), 1L)
  expect_error(atlas_e2_split(pull[, setdiff(names(pull), "first_green_on")], "2026-08-17"), "first_green_on")
})

test_that("H2b never loses a resample for want of failed taxa, since each group is resampled on its own", {
  good <- taxon_rows(40, 5, function(i, n) stats::runif(n, 0.45, 1))
  # Two failed taxa with 15 places each: a resample over all 42 taxa would
  # often draw neither.
  failed <- taxon_rows(2, 15, function(i, n) stats::runif(n, 0, 1), grade = "failed", seed = 2, prefix = "F")
  h <- atlas_e2_hypotheses(rbind(good, failed), reps = 500)
  expect_true(h$H2b$tested)
  expect_equal(h$H2b$dropped, 0L)
})
