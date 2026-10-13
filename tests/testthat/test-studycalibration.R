# Calibrating the null test on virtual species (paper E1): the
# pre-registered cells, the breadth and signal-strength knobs, the realised
# band, and a verdict per learner and null design.

# --- The cells ----------------------------------------------------------------

test_that("the layout holds the pre-registered cells, doubled before launch: 1,200 + 800 + 840 species", {
  layout <- atlas_calibration_layout()
  expect_equal(nrow(layout), 2840L)
  count <- function(family, kind) sum(layout$family == family & layout$kind == kind)
  expect_equal(count("full", "habitat"), 1200L)
  expect_equal(count("full", "geography"), 800L)
  expect_equal(count("esm", "habitat"), 480L)
  expect_equal(count("esm", "geography"), 360L)
  # 60 habitat species in every band x breadth x strength cell, 80 geography
  # species per band and centre count, 80 and 120 per ESM cell.
  cells <- table(layout$cell)
  expect_true(all(cells[grepl("^full/habitat/", names(cells))] == 60L))
  expect_true(all(cells[grepl("^full/geography/", names(cells))] == 80L))
  expect_true(all(cells[grepl("^esm/habitat/", names(cells))] == 80L))
  expect_true(all(cells[grepl("^esm/geography/", names(cells))] == 120L))
  expect_setequal(unique(layout$band[layout$family == "full"]),
                  c("20-29", "30-49", "50-99", "100-199", "200+"))
  expect_setequal(unique(layout$band[layout$family == "esm"]), c("3-4", "5-9", "10-19"))
  expect_false(anyDuplicated(layout$name) > 0)
  expect_true(all(vapply(layout$name, function(n) atlas_virtual_parse(n)$kind, "") == layout$kind))
})

test_that("full-model species are fitted with Maxent and RF, ensemble species with ESM only", {
  expect_equal(atlas_calibration_learners("full"), c("maxnet", "rf"))
  expect_equal(atlas_calibration_learners("esm"), "esm")
  expect_equal(atlas_calibration_design("esm")$folds, 3L)
  expect_equal(atlas_calibration_design("full")$folds, 5)
})

test_that("a target is drawn inside its band, the open band up to its cap", {
  targets <- vapply(1:200, function(s) atlas_calibration_target(30, 49, s), 0L)
  expect_true(all(targets >= 30 & targets <= 49))
  expect_gt(length(unique(targets)), 10L)
  top <- vapply(1:200, function(s) atlas_calibration_target(200, Inf, s), 0L)
  expect_true(all(top >= 200 & top <= ATLAS_CALIBRATION_TOP_TARGET))
})

# --- Breadth and signal -------------------------------------------------------

spec_world <- function() {
  set.seed(9)
  env <- data.frame(bio1 = stats::rnorm(500, 10, 5), soil_phh2o = stats::rnorm(500, 6, 1),
                    cover_trees = stats::runif(500))
  sites <- data.frame(x = stats::runif(500, 0, 1e6), y = stats::runif(500, 0, 1e6),
                      records = stats::rpois(500, 3) + 1L)
  list(env = env, sites = sites)
}

# The generator as it was before the E1 knobs (main f46d493), frozen here so
# the knobs can be shown to leave a spec and a collection exactly as they were.
frozen_virtual_spec <- function(kind, seed, env, sites) {
  set.seed(seed)
  target <- sample(ATLAS_VIRTUAL_TARGETS, 1L)
  spec <- list(kind = kind, target = target, seed = seed)
  if (identical(kind, "geography")) {
    n <- sample(1:2, 1L)
    picked <- sample.int(nrow(sites), n, prob = sites$records)
    spec$centres <- lapply(picked, function(i) {
      list(x = sites$x[[i]], y = sites$y[[i]], radius_km = round(stats::runif(1, 150, 400)))
    })
    return(spec)
  }
  climate <- intersect(ATLAS_VIRTUAL_CLIMATE, names(env))
  others <- setdiff(intersect(c(ATLAS_VIRTUAL_BELL, ATLAS_VIRTUAL_RISING), names(env)), climate)
  extra <- min(length(others), sample(1:2, 1L))
  drivers <- c(climate[sample.int(length(climate), 1L)], others[sample.int(length(others), extra)])
  spec$responses <- lapply(drivers, function(v) {
    values <- env[[v]][is.finite(env[[v]])]
    spread <- stats::sd(values)
    if (v %in% ATLAS_VIRTUAL_RISING) {
      list(predictor = v, shape = "rising",
           centre = unname(stats::quantile(values, stats::runif(1, 0.3, 0.8))),
           scale = spread * stats::runif(1, 0.1, 0.4))
    } else {
      list(predictor = v, shape = "bell",
           optimum = unname(stats::quantile(values, stats::runif(1, 0.1, 0.9))),
           width = spread * stats::runif(1, 0.3, 1))
    }
  })
  spec
}

frozen_virtual_collect <- function(habitat, records, target, seed = 1L) {
  habitat[!is.finite(habitat)] <- 0
  expected <- function(rate) sum(1 - (1 - pmin(1, rate * habitat))^records)
  ceiling_rate <- 1 / max(habitat)
  rate <- if (expected(ceiling_rate) <= target) {
    ceiling_rate
  } else {
    exp(stats::uniroot(function(r) expected(exp(r)) - target,
                       c(log(1e-12), log(ceiling_rate)), tol = 1e-6)$root)
  }
  set.seed(seed)
  own <- stats::rbinom(length(records), records, pmin(1, rate * habitat))
  attr(own, "rate") <- rate
  own
}

test_that("with nothing fixed, the generator draws exactly what it drew before the knobs", {
  world <- spec_world()
  for (seed in 1:8) {
    for (kind in c("habitat", "geography")) {
      expect_identical(atlas_virtual_spec(kind, seed, world$env, world$sites),
                       frozen_virtual_spec(kind, seed, world$env, world$sites))
    }
  }
  set.seed(6)
  habitat <- c(stats::runif(400), NA, NA)
  records <- stats::rpois(402, 3) + 1L
  for (seed in 1:5) {
    expect_identical(atlas_virtual_collect(habitat, records, 40, seed = seed),
                     frozen_virtual_collect(habitat, records, 40, seed = seed))
  }
})

test_that("a site with no data yields nothing under a weak signal either", {
  set.seed(8)
  habitat <- c(stats::runif(300), rep(NA, 50))
  # The sites with no data are the busiest, so the flat half would find
  # them first if it reached them.
  records <- c(rep(2L, 300), rep(200L, 50))
  for (seed in 1:10) {
    own <- atlas_virtual_collect(habitat, records, 40, seed = seed, signal = "weak")
    expect_equal(sum(own[301:350]), 0L)
  }
})

test_that("breadth halves or doubles bell widths only, with the habitat otherwise unchanged", {
  world <- spec_world()
  for (seed in 1:10) {
    base <- atlas_virtual_spec("habitat", seed, world$env, world$sites)
    for (factor in c(0.5, 2)) {
      changed <- atlas_virtual_spec("habitat", seed, world$env, world$sites, breadth = factor)
      for (i in seq_along(base$responses)) {
        a <- base$responses[[i]]
        b <- changed$responses[[i]]
        expect_equal(b$predictor, a$predictor)
        if (identical(a$shape, "bell")) {
          expect_equal(b$width, a$width * factor)
          expect_equal(b$optimum, a$optimum)
        } else {
          expect_identical(b, a)
        }
      }
    }
  }
})

test_that("a fixed target and centre count are kept", {
  world <- spec_world()
  expect_equal(atlas_virtual_spec("habitat", 3, world$env, world$sites, target = 37L)$target, 37L)
  for (n in 1:2) {
    expect_length(atlas_virtual_spec("geography", 3, world$env, world$sites, centres = n)$centres, n)
  }
})

test_that("a weak signal is half habitat, scaled by its mean where present, and half flat", {
  habitat <- c(0, 0.2, 0.4, 0.6, NA)
  mean_h <- mean(c(0.2, 0.4, 0.6))
  weak <- atlas_virtual_signal(habitat, "weak")
  expect_equal(weak[1:4], 0.5 * c(0, 0.2, 0.4, 0.6) / mean_h + 0.5)
  # A site the layers cannot describe yields nothing either way.
  expect_equal(weak[[5]], 0)
  expect_equal(atlas_virtual_signal(habitat, "strong"), c(0, 0.2, 0.4, 0.6, 0))
  expect_error(atlas_virtual_signal(habitat, "medium"), "strong or weak")
})

test_that("weak and strong species are found at the same number of sites, the weak further from habitat", {
  set.seed(4)
  habitat <- stats::rbeta(5000, 0.4, 2)
  records <- pmax(1L, stats::rpois(5000, 3))
  sites_found <- function(signal) vapply(1:150, function(s) {
    sum(atlas_virtual_collect(habitat, records, target = 60, seed = s, signal = signal) > 0)
  }, numeric(1))
  for (signal in c("strong", "weak")) {
    found <- sites_found(signal)
    expect_lt(abs(mean(found) - 60), 4 * stats::sd(found) / sqrt(length(found)))
  }
  low_share <- function(signal) mean(vapply(1:50, function(s) {
    own <- atlas_virtual_collect(habitat, records, target = 60, seed = s, signal = signal)
    mean(habitat[own > 0] < 0.05)
  }, numeric(1)))
  expect_gt(low_share("weak"), 2 * low_share("strong"))
})

test_that("realised breadth is the share of the accessible area's sites at habitat 0.5 or more", {
  skip_if_not_installed("terra")
  sites <- data.frame(x = c(0, 10e3, 20e3, 30e3, 900e3), y = 0)
  habitat <- c(0.9, 0.5, 0.49, 0.1, 1)
  area <- atlas_accessible_area(0, 0, buffer_km = 100)
  # The far site is outside the area, so its habitat does not count.
  expect_equal(atlas_calibration_breadth(habitat, sites, area), 0.5)
})

# --- Drawing into a band ------------------------------------------------------

calibration_world <- function() {
  set.seed(11)
  stack <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 1e6, ymin = 0, ymax = 1e6,
                       crs = ATLAS_CRS, nlyrs = 2)
  names(stack) <- c("bio1", "cover_trees")
  xy <- terra::xyFromCell(stack, seq_len(terra::ncell(stack)))
  terra::values(stack) <- cbind(xy[, 1] / 1e5, stats::runif(nrow(xy)))
  x <- c(stats::runif(1500, 0, 5e5), stats::runif(900, 0, 1e6))
  y <- stats::runif(2400, 0, 1e6)
  points <- fake_points(x, y, names = "Everything else")
  points$cell <- terra::cellFromXY(stack, cbind(points$x, points$y))
  centres <- terra::xyFromCell(stack, points$cell)
  points$x <- centres[, 1]
  points$y <- centres[, 2]
  list(stack = stack, points = atlas_attach_sites(points))
}

one_cell <- function(family, kind, band, breadth = NA, signal = NA, centres = NA) {
  layout <- data.frame(family = family, kind = kind, band_lo = band[[1]], band_hi = band[[2]],
                       band = atlas_calibration_band_label(band), breadth = breadth,
                       signal = signal, centres = centres, cell = "test", stringsAsFactors = FALSE)
  as.list(layout[1, ])
}

test_that("a species counts in the band of its realised detection sites, drawn again until it lands", {
  skip_if_not_installed("terra")
  world <- calibration_world()
  base <- atlas_virtual_base(world$points, world$stack)
  cell <- one_cell("full", "habitat", c(20, 29), breadth = "wide", signal = "strong")
  drawn <- atlas_calibration_draw(cell, "virtual-habitat-0001", 77L, base, world$stack,
                                  n_background = 2000, buffer_km = 600)
  expect_true(drawn$ok)
  presences <- sum(drawn$training$presence == 1L)
  expect_true(presences >= 20 && presences <= 29)
  expect_equal(length(drawn$realised), drawn$draws)
  expect_equal(utils::tail(drawn$realised, 1), presences)
  expect_equal(length(unique(drawn$folds)), 5L)
})

test_that("a band no species can reach is reported unfilled after the last redraw", {
  skip_if_not_installed("terra")
  world <- calibration_world()
  base <- atlas_virtual_base(world$points, world$stack)
  cell <- one_cell("full", "habitat", c(5000, 6000), breadth = "narrow", signal = "strong")
  drawn <- atlas_calibration_draw(cell, "virtual-habitat-0002", 5L, base, world$stack,
                                  n_background = 2000, buffer_km = 600, redraws = 3L)
  expect_false(drawn$ok)
  expect_equal(drawn$draws, 4L)
  expect_length(drawn$realised, 4L)
})

# --- End to end ---------------------------------------------------------------

test_that("each learner gets its own scores, map-to-truth and verdict under each null design", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  skip_if_not_installed("ranger")
  skip_if_not_installed("glmnet")
  with_data_dir({
    world <- calibration_world()
    layout <- atlas_calibration_layout()
    pick <- c(which(layout$cell == "full/habitat/20-29/narrow/weak/-")[1],
              which(layout$cell == "esm/geography/10-19/-/-/-")[1])
    result <- atlas_calibration_study(layout = layout[pick, ], nulls = 3L, n_background = 2000,
                                      buffer_km = 600, quiet = TRUE, points = world$points,
                                      stack = world$stack)
    expect_match(result$path, "virtual-studies")
    expect_false(dir.exists(atlas_path("models")))
    saved <- jsonlite::fromJSON(result$path, simplifyVector = FALSE)
    rows <- saved$taxa
    expect_length(rows, 2L)
    habitat <- Filter(function(r) identical(r$kind, "habitat"), rows)[[1]]
    expect_equal(habitat$status, "scored")
    arms <- vapply(habitat$arms, function(a) a$arm, "")
    expect_equal(arms, c("maxnet:none", "rf", ATLAS_CALIBRATION_EFFORT_ARMS))
    for (a in habitat$arms[1:2]) {
      expect_true(is.finite(as.numeric(a$truth_rho)))
      expect_setequal(names(a$nulls), c("scatter", "shift"))
      for (n in a$nulls) expect_true(n$verdict %in% c("passed", "failed"))
    }
    # The effort arms run without nulls.
    for (a in habitat$arms[3:5]) expect_null(a$nulls)
    expect_true(is.finite(as.numeric(habitat$realised_breadth)))
    expect_true(is.finite(as.numeric(habitat$outside_share)))
    expect_true(habitat$presences >= 20 && habitat$presences <= 29)

    esm <- Filter(function(r) identical(r$kind, "geography"), rows)[[1]]
    if (identical(esm$status, "scored")) {
      expect_equal(vapply(esm$arms, function(a) a$arm, ""), "esm")
      expect_null(esm$realised_breadth)
    }
    long <- atlas_calibration_long(rows)
    expect_setequal(unique(long$learner[long$kind == "habitat"]), c("maxnet", "rf"))
    expect_equal(sum(long$taxon == habitat$taxon), 4L)
    expect_true(length(saved$fill) > 0)
  })
})

test_that("pass rates are reported with Wilson intervals by learner, design, kind and band", {
  row <- function(taxon, kind, verdict) list(
    status = "scored", taxon = taxon, family = "full", kind = kind, band = "20-29",
    breadth = if (kind == "habitat") "narrow", signal = if (kind == "habitat") "strong",
    presences = 25L,
    arms = list(list(arm = "maxnet:none", truth_rho = 0.5,
                     nulls = list(shift = list(design = "shift", p = 0.01, verdict = verdict))))
  )
  rows <- c(lapply(1:4, function(i) row(paste("g", i), "geography", if (i == 1) "passed" else "failed")),
            lapply(1:5, function(i) row(paste("h", i), "habitat", "passed")))
  summary <- atlas_calibration_summary(rows)
  geography <- summary[summary$kind == "geography", ]
  expect_equal(geography$rate, 0.25)
  interval <- atlas_tracker_wilson(1, 4)
  expect_equal(geography$low, round(interval[[1]], 3))
  expect_equal(summary$rate[summary$kind == "habitat"], 1)
})

test_that("a plan-only run sizes the layout and shards it", {
  plan <- atlas_calibration_study(plan_only = TRUE, quiet = TRUE)
  expect_equal(plan$species, 2840L)
  expect_gt(plan$cpu_hours, 100)
  half <- atlas_calibration_study(plan_only = TRUE, quiet = TRUE, shard = "2/2")
  expect_equal(half$species, 1420L)
})
