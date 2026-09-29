# Survey sites: the one unit detections, non-detections and effort share.

test_that("records within the thinning distance become one site, busiest first", {
  # Three cells 2 km apart and one 20 km away. The middle cell has the most
  # records, so it is the centre the other two join.
  x <- c(0, 2000, 4000, 20000)
  points <- fake_points(x = rep(x, c(1, 5, 1, 2)), y = rep(0, 9),
                        cells = rep(1:4, c(1, 5, 1, 2)))
  sited <- atlas_attach_sites(points, thin_km = 5)
  sites <- attr(sited, "sites")
  expect_equal(nrow(sites), 2L)
  expect_equal(sort(sites$records), c(2L, 7L))
  expect_equal(sites$x[sites$records == 7L], 2000)
  expect_equal(length(unique(sited$site[sited$x < 10000])), 1L)
})

test_that("no two sites are closer than the thinning distance", {
  set.seed(4)
  x <- stats::runif(400, 0, 60000)
  y <- stats::runif(400, 0, 60000)
  points <- fake_points(x = x, y = y, cells = seq_along(x))
  sites <- attr(atlas_attach_sites(points, thin_km = 5), "sites")
  gaps <- as.matrix(stats::dist(sites[, c("x", "y")]))
  diag(gaps) <- Inf
  expect_gte(min(gaps), 5000)
  # Every record lands in exactly one site.
  expect_equal(sum(sites$records), 400L)
})

test_that("on a grid as coarse as the spacing, a site is a cell", {
  # Neighbouring 5 km cells are exactly 5 km apart, which is not closer.
  x <- c(0, 5000, 10000, 0, 5000)
  y <- c(0, 0, 0, 5000, 5000)
  points <- fake_points(x = x, y = y, cells = 1:5)
  expect_equal(nrow(attr(atlas_attach_sites(points, thin_km = 5), "sites")), 5L)
})

test_that("the same foray is one site on a fine grid and on a coarse one", {
  # One foray: records spread over 3 km. On a 1 km grid they fall in several
  # cells, but still make one site.
  x <- c(0, 1000, 2000, 3000)
  fine <- fake_points(x = x, y = rep(0, 4), cells = 1:4)
  coarse <- fake_points(x = rep(0, 4), y = rep(0, 4), cells = rep(1L, 4))
  expect_equal(nrow(attr(atlas_attach_sites(fine, 5), "sites")), 1L)
  expect_equal(nrow(attr(atlas_attach_sites(coarse, 5), "sites")), 1L)
})

test_that("sites are gathered again when the points are not the ones they were made from", {
  points <- atlas_attach_sites(fake_points(x = c(0, 20000, 40000), y = c(0, 0, 0)), 5)
  subset <- points[1:2, ]
  attr(subset, "sites") <- attr(points, "sites")
  attr(subset, "thin_km") <- 5
  expect_equal(nrow(attr(atlas_ensure_sites(subset, 5), "sites")), 2L)
  # And a different spacing gathers them afresh.
  expect_equal(attr(atlas_ensure_sites(points, 50), "thin_km"), 50)
})

test_that("a taxon's count is its detection sites, not its records or cells", {
  points <- rbind(
    fake_points(x = c(0, 1000, 2000, 50000), y = rep(0, 4), names = "Focal", cells = 1:4),
    fake_points(x = 90000, y = 0, names = "Other", cells = 5L)
  )
  counts <- atlas_presence_site_counts(points, thin_km = 5)
  expect_equal(counts$cells[counts$scientific_name == "Focal"], 2L)
})

test_that("detection blocks count blocks, not sites", {
  training <- data.frame(presence = c(1L, 1L, 1L, 0L), x = c(0, 10000, 300000, 600000),
                         y = c(0, 0, 0, 0))
  expect_equal(atlas_presence_blocks(training, block_km = 100), 2L)
  expect_equal(atlas_presence_blocks(training, block_km = 1000), 1L)
})

test_that("blockCV sets the block from how far detections are autocorrelated", {
  skip_if_not_installed("blockCV")
  skip_if_not_installed("sf")
  skip_if_not_installed("terra")
  # Detections in 60 km patches: a variogram of them has a range, and the
  # block follows it, held inside the floor and ceiling.
  set.seed(11)
  x <- stats::runif(1500, 0, 1e6)
  y <- stats::runif(1500, 0, 1e6)
  patch <- (floor(x / 60000) + floor(y / 60000)) %% 2 == 0
  presence <- as.integer(patch & stats::runif(1500) < 0.5)
  block <- atlas_block_size(data.frame(presence = presence, x = x, y = y), seed = 2L)
  expect_equal(block$source, "blockCV")
  expect_true(is.finite(block$range_km))
  expect_gte(block$block_km, ATLAS_BLOCK_FLOOR_KM)
  expect_lte(block$block_km, ATLAS_BLOCK_CEILING_KM)
  expect_equal(block$block_km %% 5, 0)
})

test_that("without both kinds of site the block size falls back rather than failing", {
  block <- atlas_block_size(data.frame(presence = c(1L, 1L), x = c(0, 1), y = c(0, 1)))
  expect_equal(block$source, "fallback")
  expect_equal(block$block_km, ATLAS_BLOCK_FALLBACK_KM)
})
