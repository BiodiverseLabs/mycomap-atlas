# A synthetic pool on the grid: cell centres in the projected CRS, so no test
# here needs a layer, a network or the real pull.
fake_points <- function(x, y, names = "Target group", cells = NULL) {
  data.frame(
    scientific_name = rep_len(names, length(x)),
    cell = if (is.null(cells)) seq_along(x) else cells,
    x = x, y = y,
    stringsAsFactors = FALSE
  )
}

test_that("repeat visits to one cell become one presence", {
  skip_if_not_installed("terra")
  # Three records 200 m apart, well inside one 5 km cell, plus one 40 km away.
  points <- atlas_occurrence_points(
    data.frame(
      scientific_name = "Amanita muscaria",
      latitude = c("45.1030", "45.1032", "45.1048", "45.4500"),
      longitude = c("-122.5050", "-122.5052", "-122.5060", "-122.5050"),
      stringsAsFactors = FALSE
    ),
    grid = "draft"
  )
  expect_equal(nrow(points), 4L)
  expect_equal(nrow(atlas_thin_to_cells(points)), 2L)
})

test_that("records off the grid are dropped rather than snapped to its edge", {
  skip_if_not_installed("terra")
  points <- atlas_occurrence_points(
    data.frame(
      scientific_name = c("Here", "London"),
      latitude = c("45.10", "51.5"),
      longitude = c("-122.50", "-0.1"),
      stringsAsFactors = FALSE
    ),
    grid = "draft"
  )
  expect_equal(nrow(points), 1L)
  expect_equal(points$scientific_name, "Here")
})

test_that("the accessible area reaches the buffer distance and no further", {
  skip_if_not_installed("terra")
  area <- atlas_accessible_area(x = 0, y = 0, buffer_km = 500)
  inside <- atlas_points_in_area(c(300000, 700000), c(0, 0), area)
  expect_true(inside[[1]])
  expect_false(inside[[2]])
})

test_that("background points come only from inside the accessible area", {
  skip_if_not_installed("terra")
  pool <- fake_points(x = c(0, 100000, 2000000), y = c(0, 0, 0))
  area <- atlas_accessible_area(0, 0, buffer_km = 500)
  drawn <- atlas_background_sample(pool, area, n = 10)
  expect_equal(nrow(drawn), 2L)
  expect_true(all(drawn$x < 500000))
})

test_that("a pool smaller than the request returns everything it has", {
  skip_if_not_installed("terra")
  pool <- fake_points(x = c(0, 1000, 2000), y = c(0, 0, 0))
  area <- atlas_accessible_area(0, 0, buffer_km = 500)
  expect_equal(nrow(atlas_background_sample(pool, area, n = 10000)), 3L)
})

test_that("background keeps sampling effort, so a much-visited cell dominates", {
  skip_if_not_installed("terra")
  # 900 records at one site, 100 at another: the draw should follow that.
  pool <- fake_points(
    x = c(rep(0, 900), rep(100000, 100)),
    y = rep(0, 1000),
    cells = c(rep(1L, 900), rep(2L, 100))
  )
  area <- atlas_accessible_area(0, 0, buffer_km = 500)
  drawn <- atlas_background_sample(pool, area, n = 500, seed = 42L)
  share <- mean(drawn$cell == 1L)
  expect_gt(share, 0.8)
  expect_lt(share, 0.98)
})

test_that("the same data always draws the same background", {
  skip_if_not_installed("terra")
  pool <- fake_points(x = seq(0, 400000, length.out = 200), y = rep(0, 200))
  area <- atlas_accessible_area(0, 0, buffer_km = 500)
  first <- atlas_background_sample(pool, area, n = 50, seed = 7L)
  again <- atlas_background_sample(pool, area, n = 50, seed = 7L)
  other <- atlas_background_sample(pool, area, n = 50, seed = 8L)
  expect_equal(first$x, again$x)
  expect_false(identical(first$x, other$x))
})

test_that("a provisional name still makes a usable file name", {
  with_data_dir({
    expect_match(atlas_training_path("Trametes versicolor"), "trametes-versicolor.tsv.gz$")
    expect_match(atlas_training_path("Russula sp. 'IN01'"), "russula-sp-in01.tsv.gz$")
    expect_match(atlas_training_path("Pleurotus sp. 'pulmonarius-PNW02'"),
                 "pleurotus-sp-pulmonarius-pnw02.tsv.gz$")
  })
})

test_that("training tables are kept per grid", {
  with_data_dir({
    expect_match(atlas_training_path("Amanita muscaria", "draft"), "training/draft/")
    expect_match(atlas_training_path("Amanita muscaria", "production"), "training/production/")
  })
})

test_that("the seed follows the record set, not the clock", {
  expect_equal(
    atlas_seed_from_fingerprint("0b4fd25712c22e129ee72e765ad6610035a3f547"),
    strtoi("0b4fd25", base = 16L)
  )
  expect_false(
    identical(atlas_seed_from_fingerprint("aaaaaaa"), atlas_seed_from_fingerprint("bbbbbbb"))
  )
  expect_equal(atlas_seed_from_fingerprint(NULL), 1L)
  expect_equal(atlas_seed_from_fingerprint(""), 1L)
})

test_that("a training table is presences plus background, and says which", {
  skip_if_not_installed("terra")
  points <- rbind(
    fake_points(x = c(0, 20000), y = c(0, 0), names = "Focal species"),
    fake_points(x = c(5000, 30000, 60000), y = c(0, 0, 0), names = "Other species",
                cells = c(10L, 11L, 12L))
  )
  table <- atlas_training_table("Focal species", points, n_background = 100)

  expect_equal(sum(table$presence == 1L), 2L)
  expect_true(sum(table$presence == 0L) > 0)
  expect_true(all(table$presence %in% c(0L, 1L)))
  expect_gt(attr(table, "area_km2"), 0)
})

test_that("a training table carries the fingerprint of the records it came from", {
  skip_if_not_installed("terra")
  points <- rbind(
    fake_points(x = c(0, 20000), y = c(0, 0), names = "Focal species"),
    fake_points(x = c(5000, 30000), y = c(0, 0), names = "Other species",
                cells = c(10L, 11L))
  )
  table <- atlas_training_table("Focal species", points, n_background = 100,
                                fingerprint = "0b4fd25712c2")
  expect_equal(attr(table, "fingerprint"), "0b4fd25712c2")
  expect_equal(attr(table, "seed"), atlas_seed_from_fingerprint("0b4fd25712c2"))
})

test_that("a taxon with no records on the grid is refused, not modelled", {
  skip_if_not_installed("terra")
  points <- fake_points(x = 0, y = 0, names = "Other species")
  expect_error(atlas_training_table("Missing species", points), "no records on the grid")
})

test_that("the background describes where people sampled, not the landscape", {
  skip_if_not_installed("terra")
  # Everyone collected in the east; the focal species sits in the middle. A
  # uniform background would call the whole area available. The target group
  # should pull the background east, towards the sampling.
  effort_x <- seq(300000, 500000, length.out = 400)
  points <- rbind(
    fake_points(x = 0, y = 0, names = "Focal species"),
    fake_points(x = effort_x, y = rep(0, length(effort_x)), names = "Other species",
                cells = seq_along(effort_x) + 100L)
  )
  table <- atlas_training_table("Focal species", points, n_background = 200)
  background_x <- table$x[table$presence == 0L]

  # Closer to where the collecting happened than to the middle of the area.
  expect_gt(mean(background_x), 250000)
  expect_lt(abs(mean(background_x) - mean(effort_x)), 60000)
})
