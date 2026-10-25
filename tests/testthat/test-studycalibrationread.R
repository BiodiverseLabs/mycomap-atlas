# Reading the null calibration (paper E1): the pre-registered tests H1a-H1f,
# the C1 decision, and the pooling of a full run's shards, on made-up species
# rows shaped as atlas_calibration_taxon writes them.

FULL_BANDS <- c("20-29", "30-49", "50-99", "100-199", "200+")

# One species row. scatter and shift say whether each learner passes; rho is
# each learner's map-to-truth correlation.
cal_species <- function(name, kind, band, scatter = FALSE, shift = FALSE, family = "full",
                        breadth = NA_character_, signal = NA_character_, rho = 0.5,
                        realised_breadth = NA_real_, learners = if (family == "esm") "esm" else c("maxnet", "rf")) {
  pick <- function(x, l) if (is.list(x) || length(x) > 1L) x[[l]] else x
  null <- function(design, passed) {
    list(design = design, p = if (passed) 0.01 else 0.5, observed_auc = 0.7, auc_mean = 0.6, auc_sd = 0.05,
         drawn = if (passed) 99L else 10L, reps = if (passed) 99L else 10L, verdict = if (passed) "passed" else "failed")
  }
  arms <- lapply(learners, function(l) {
    list(arm = if (l == "maxnet") "maxnet:none" else l, auc = 0.7, boyce = 0.2, truth_rho = pick(rho, l),
         nulls = list(scatter = null("scatter", isTRUE(pick(scatter, l))), shift = null("shift", isTRUE(pick(shift, l)))))
  })
  list(taxon = name, family = family, kind = kind, cell = paste(family, kind, band, sep = "/"), band = band,
       breadth = breadth, signal = signal, centres = NA, presences = 30L,
       realised_breadth = if (kind == "habitat") realised_breadth else NULL, status = "scored", arms = arms)
}

# n species of one kind in each band, passing as pass(band index, i, learner) says.
cal_band_species <- function(kind, n, scatter, shift, prefix = kind, family = "full",
                             bands = if (family == "esm") c("3-4", "5-9", "10-19") else FULL_BANDS, ...) {
  learners <- if (family == "esm") "esm" else c("maxnet", "rf")
  do.call(c, lapply(seq_along(bands), function(b) lapply(seq_len(n), function(i) {
    by <- function(f) stats::setNames(lapply(learners, function(l) f(b, i, l)), learners)
    cal_species(sprintf("%s-%s-%d-%d", prefix, family, b, i), kind, bands[[b]],
                scatter = by(scatter), shift = by(shift), family = family, learners = learners, ...)
  })))
}

# A world in which C1 holds: geography species pass shift nulls almost never
# and scatter nulls often, more so with more sites; habitat maps that pass
# the shift test are closer to the truth.
cal_world <- function(rf_shift_false = function(b, i) FALSE, esm_shift_false = function(b, i) FALSE) {
  geography <- cal_band_species("geography", 160,
    scatter = function(b, i, l) i <= round(160 * (0.2 + 0.12 * b)),
    shift = function(b, i, l) if (l == "rf") rf_shift_false(b, i) else i == 1L && b == 3L)
  habitat <- do.call(c, lapply(seq_along(FULL_BANDS), function(b) lapply(seq_len(80), function(i) {
    passed <- i <= 30
    cal_species(sprintf("habitat-%d-%d", b, i), "habitat", FULL_BANDS[[b]], scatter = TRUE, shift = passed,
                breadth = if (i %% 2) "narrow" else "wide", signal = if (i %% 4 < 2) "strong" else "weak",
                rho = if (passed) 0.6 + i / 1000 else 0.3 + i / 1000, realised_breadth = (i %% 10) / 10 + 0.05)
  })))
  esm <- cal_band_species("geography", 120, family = "esm", prefix = "esm-geo",
    scatter = function(b, i, l) i <= 60, shift = function(b, i, l) esm_shift_false(b, i))
  c(geography, habitat, esm)
}

# --- The statistics ---------------------------------------------------------------

test_that("the trend test is Cochran-Armitage: its square is prop.trend.test's, and it is one-sided for a rise", {
  k <- c(10, 20, 35, 50)
  n <- c(100, 100, 100, 100)
  rising <- atlas_calibration_trend(k, n)
  expect_equal(rising$z^2, unname(stats::prop.trend.test(k, n)$statistic), tolerance = 1e-9)
  expect_lt(rising$p, 0.001)
  falling <- atlas_calibration_trend(rev(k), n)
  expect_gt(falling$p, 0.999)
  expect_true(is.na(atlas_calibration_trend(c(5, 5), c(10, 10) * 0)$p))
})

test_that("the Wilson interval is not rounded before the 5% bound is compared", {
  i <- atlas_calibration_wilson(0, 160)
  expect_equal(i[[1]], 0)
  expect_lt(i[[2]], 0.025)
  expect_false(i[[2]] == round(i[[2]], 3))
})

# --- H1a and H1b ----------------------------------------------------------------

test_that("H1a holds when shift nulls pass at most 5% of geography species, pooled bound and every band", {
  read <- atlas_calibration_read(cal_world(), reps = 200)
  h1a <- read$learners$maxnet$h1a
  expect_equal(h1a$species, 800L)
  expect_equal(h1a$passed, 1L)
  expect_lte(h1a$high, 0.05)
  expect_true(h1a$holds)
})

test_that("H1a fails when one band passes more than 5%, though the pooled bound is under 5%", {
  # 9 of 160 (5.6%) in the 200+ band only: 9 of 800 pooled, upper bound 2.1%.
  read <- atlas_calibration_read(cal_world(rf_shift_false = function(b, i) b == 5L && i <= 9), reps = 200)
  h1a <- read$learners$rf$h1a
  expect_lt(h1a$high, 0.05)
  expect_gt(h1a$by_band[[5]]$rate, 0.05)
  expect_false(h1a$holds)
  expect_true(read$learners$maxnet$h1a$holds)
})

test_that("H1a fails when the pooled upper bound passes 5%, though no band's rate does", {
  # 8 of 160 (5%) in every band: 40 of 800, upper bound about 6.7%.
  read <- atlas_calibration_read(cal_world(rf_shift_false = function(b, i) i <= 8), reps = 200)
  h1a <- read$learners$rf$h1a
  expect_true(all(vapply(h1a$by_band, function(b) b$rate, 0) <= 0.05))
  expect_gt(h1a$high, 0.05)
  expect_false(h1a$holds)
})

test_that("H1b holds when scatter nulls pass far more than 20% of geography species, rising with band", {
  h1b <- atlas_calibration_read(cal_world(), reps = 200)$learners$maxnet$h1b
  expect_gt(h1b$low, 0.20)
  expect_lt(h1b$trend_p, 0.05)
  expect_true(h1b$holds)
})

test_that("H1b fails without a rise over bands, and when the pooled lower bound is 20% or less", {
  flat <- c(cal_band_species("geography", 160, scatter = function(b, i, l) i <= 80, shift = function(b, i, l) FALSE))
  h1b <- atlas_calibration_read(flat, reps = 200)$learners$maxnet$h1b
  expect_gt(h1b$low, 0.20)
  expect_false(h1b$holds)
  low <- c(cal_band_species("geography", 160, scatter = function(b, i, l) i <= 10 * b, shift = function(b, i, l) FALSE))
  h1b <- atlas_calibration_read(low, reps = 200)$learners$maxnet$h1b
  expect_lt(h1b$trend_p, 0.05)
  expect_lte(h1b$low, 0.20)
  expect_false(h1b$holds)
})

# --- H1c, H1d and H1f ---------------------------------------------------------------

# Habitat species whose shift pass follows breadth and strength as given.
cal_power_world <- function(breadth_effect, strength_effect, band_effect = 0, seed = 7) {
  set.seed(seed)
  do.call(c, lapply(seq_along(FULL_BANDS), function(b) {
    do.call(c, lapply(c("narrow", "wide"), function(breadth) {
      do.call(c, lapply(c("strong", "weak"), function(signal) lapply(seq_len(60), function(i) {
        realised <- if (breadth == "narrow") stats::runif(1, 0.05, 0.3) else stats::runif(1, 0.4, 0.9)
        p <- stats::plogis(-0.5 + breadth_effect * realised + strength_effect * (signal == "strong") +
                             band_effect * (b - 3) * (breadth == "narrow"))
        passed <- stats::runif(1) < p
        cal_species(sprintf("h-%d-%s-%s-%d", b, breadth, signal, i), "habitat", FULL_BANDS[[b]],
                    scatter = TRUE, shift = passed, breadth = breadth, signal = signal,
                    rho = 0.4, realised_breadth = realised)
      })))
    }))
  }))
}

test_that("H1c holds, with its direction, when shift power falls with realised breadth; H1f when strong signal helps", {
  read <- atlas_calibration_read(cal_power_world(breadth_effect = -3, strength_effect = 1), reps = 200)
  t <- read$learners$maxnet
  expect_equal(t$power_model$species, 1200L)
  expect_lt(t$h1c$estimate, 0)
  expect_equal(t$h1c$direction, "lower for wider habitats")
  expect_true(t$h1c$holds)
  expect_gt(t$h1f$estimate, 0)
  expect_true(t$h1f$holds)
  # The power curve: every band and strength at three breadths.
  expect_equal(nrow(t$power_curve), 5L * 2L * 3L)
  expect_true(all(t$power_curve$power > 0 & t$power_curve$power < 1))
})

test_that("H1c and H1f do not hold when shift power follows neither breadth nor strength", {
  t <- atlas_calibration_read(cal_power_world(breadth_effect = 0, strength_effect = 0), reps = 200)$learners$rf
  expect_false(t$h1c$holds)
  expect_false(t$h1f$holds)
})

test_that("H1f is one-sided: weak signal passing more often than strong does not hold", {
  t <- atlas_calibration_read(cal_power_world(breadth_effect = 0, strength_effect = -1.5), reps = 200)$learners$maxnet
  expect_lt(t$h1f$estimate, 0)
  expect_lt(t$h1f$p_two_sided, 0.05)
  expect_false(t$h1f$holds)
})

test_that("H1d holds when narrow habitats' shift power rises with band, and not when it falls", {
  up <- atlas_calibration_read(cal_power_world(0, 0, band_effect = 0.6), reps = 200)$learners$maxnet$h1d
  expect_equal(up$species, 600L)
  expect_lt(up$trend_p, 0.05)
  expect_true(up$holds)
  down <- atlas_calibration_read(cal_power_world(0, 0, band_effect = -0.6), reps = 200)$learners$maxnet$h1d
  expect_false(down$holds)
})

# --- H1e ------------------------------------------------------------------------

test_that("H1e holds when shift-passed habitat maps are closer to the truth, with an interval above 0", {
  h1e <- atlas_calibration_read(cal_world(), reps = 500)$learners$rf$h1e
  expect_equal(h1e$passed + h1e$rest, 400L)
  expect_gt(h1e$difference, 0.2)
  expect_gt(h1e$low, 0)
  expect_lt(h1e$p, 0.05)
  expect_true(h1e$holds)
})

test_that("H1e is one-sided and needs both groups", {
  reversed <- lapply(seq_len(60), function(i) {
    cal_species(paste0("h", i), "habitat", "50-99", shift = i <= 20, rho = if (i <= 20) 0.2 else 0.6,
                breadth = "wide", signal = "strong", realised_breadth = 0.5)
  })
  h1e <- atlas_calibration_read(reversed, reps = 200)$learners$maxnet$h1e
  expect_lt(h1e$difference, 0)
  expect_false(h1e$holds)
  none <- lapply(seq_len(10), function(i) cal_species(paste0("h", i), "habitat", "50-99", shift = FALSE,
                                                      breadth = "wide", signal = "strong", realised_breadth = 0.5))
  h1e <- atlas_calibration_read(none, reps = 200)$learners$maxnet$h1e
  expect_equal(h1e$passed, 0L)
  expect_false(h1e$holds)
})

# --- C1 -------------------------------------------------------------------------

test_that("C1 is supported when H1a, H1b and H1e hold for Maxent and for RF", {
  read <- atlas_calibration_read(cal_world(), reps = 200)
  expect_true(read$c1$supported)
  expect_equal(read$c1$by_learner, list(maxnet = TRUE, rf = TRUE))
  expect_true(any(grepl("^C1 is supported", atlas_calibration_report(read))))
})

test_that("C1 is not supported when one learner fails H1a, and the ensembles do not decide it", {
  read <- atlas_calibration_read(cal_world(rf_shift_false = function(b, i) i <= 12), reps = 200)
  expect_false(read$c1$supported)
  expect_equal(read$c1$by_learner, list(maxnet = TRUE, rf = FALSE))
  # Ensembles failing H1a are reported, secondary, and leave C1 alone.
  read <- atlas_calibration_read(cal_world(esm_shift_false = function(b, i) i <= 30), reps = 200)
  expect_false(read$secondary$esm$h1a$holds)
  expect_equal(vapply(read$secondary$esm$h1a$by_band, function(b) b$band, ""), c("3-4", "5-9", "10-19"))
  expect_true(read$c1$supported)
})

test_that("a learner failing H1a is decided band by band, its failing band reported and never dropped", {
  # RF passes 9 of 160 geography species in 200+ only.
  read <- atlas_calibration_read(cal_world(rf_shift_false = function(b, i) b == 5L && i <= 9), reps = 200)
  rf <- read$c1$by_band$rf
  expect_equal(rf$mode, "by band")
  expect_equal(rf$supported, c("20-29", "30-49", "50-99", "100-199"))
  expect_equal(rf$failing, "200+")
  expect_true(rf$h1e$holds)
  expect_equal(rf$h1e$passed + rf$h1e$rest, 320L)
  maxnet <- read$c1$by_band$maxnet
  expect_equal(maxnet$mode, "registered")
  expect_equal(maxnet$supported, FULL_BANDS)
  expect_false(read$c1$supported)
  report <- atlas_calibration_report(read)
  expect_true(any(grepl("^rf C1 \\(by band\\): supported in 20-29, 30-49, 50-99, 100-199; failing in 200\\+", report)))
  expect_true(any(grepl("uncorrected for testing 5 bands", report, fixed = TRUE)))
  expect_false(any(grepl("uncorrected", atlas_calibration_report(atlas_calibration_read(cal_world(), reps = 200)))))
})

test_that("a band's H1a bound is from its own count: a short band allows fewer passes", {
  # 2 of 160 clears 5%; 2 of 100 (upper bound 7%) does not.
  rows <- cal_world(rf_shift_false = function(b, i) (b == 1L && i <= 2) || (b == 2L && i <= 2) || (b == 5L && i <= 9))
  short <- vapply(rows, function(r) !(identical(r$kind, "geography") && identical(r$family, "full") &&
                                       identical(r$band, "30-49") && as.integer(sub(".*-", "", r$taxon)) > 100), TRUE)
  rf <- atlas_calibration_read(rows[short], reps = 200)$c1$by_band$rf
  expect_true("20-29" %in% rf$supported)
  expect_true("30-49" %in% rf$failing)
})

test_that("in a band, H1a holds only with its own upper bound at most 5%: 2 of 160 passes, not 3", {
  read <- atlas_calibration_read(cal_world(rf_shift_false = function(b, i) (b == 1L && i <= 2) || (b == 2L && i <= 3) ||
                                             (b == 5L && i <= 9)), reps = 200)
  rf <- read$c1$by_band$rf
  expect_true("20-29" %in% rf$supported)
  expect_true("30-49" %in% rf$failing)
  expect_true("200+" %in% rf$failing)
})

test_that("a band decision still needs H1e over those bands, and scatter's lower bound above 20% in the band", {
  rows <- cal_world(rf_shift_false = function(b, i) b == 5L && i <= 9)
  # RF's habitat maps that pass are no closer to the truth: H1e fails, so no band is supported.
  for (k in seq_along(rows)) {
    if (identical(rows[[k]]$kind, "habitat")) rows[[k]]$arms[[2]]$truth_rho <- 0.3
  }
  rf <- atlas_calibration_read(rows, reps = 200)$c1$by_band$rf
  expect_length(rf$supported, 0L)
  expect_equal(rf$failing, FULL_BANDS)
})

test_that("best-effort shifted nulls are reported by learner and band, as shares of nulls and of species", {
  rows <- list(cal_species("g1", "geography", "200+"), cal_species("g2", "geography", "200+"),
               cal_species("g3", "geography", "20-29"))
  rows[[1]]$arms[[1]]$nulls$shift$best_effort <- 4L
  be <- atlas_calibration_read(rows, reps = 200)$best_effort
  top <- be[be$learner == "maxnet" & be$band == "200+", ]
  expect_equal(top$species, 2L)
  expect_equal(top$best_effort, 4L)
  expect_equal(top$share_of_nulls, 4 / 20)
  expect_equal(top$share_of_species, 0.5)
  expect_equal(be$best_effort[be$learner == "rf" & be$band == "200+"], 0L)
})

test_that("species that were not scored, and nulls that errored, are counted and left out of every test", {
  rows <- cal_world()
  rows[[1]] <- list(taxon = rows[[1]]$taxon, family = "full", kind = "geography", cell = "c", band = "20-29",
                    status = "unfilled", draws = 21L)
  rows[[2]]$arms[[1]]$nulls$shift <- list(design = "shift", error = "the stack is on fire")
  read <- atlas_calibration_read(rows, reps = 200)
  expect_equal(read$health$by_status$unfilled, 1L)
  expect_equal(read$health$null_errors, 1L)
  expect_equal(read$learners$maxnet$h1a$species, 798L)
  expect_equal(read$learners$rf$h1a$species, 799L)
})

# --- The map tiers (secondary) ---------------------------------------------------

test_that("the tiers count a species at its tier or better, and strong is the shift pass", {
  rows <- list(
    cal_species("g1", "geography", "50-99", shift = TRUE),
    cal_species("g2", "geography", "50-99", shift = FALSE)
  )
  # g2's Maxent shift test: p 0.15 of 40 nulls, so moderate.
  rows[[2]]$arms[[1]]$nulls$shift$p <- 0.15
  rows[[2]]$arms[[1]]$nulls$shift$reps <- 40L
  rates <- atlas_calibration_read(rows, reps = 200)$tiers$rates
  share <- function(tier, learner) rates$rate[rates$tier == tier & rates$learner == learner]
  expect_equal(share("strong", "maxnet"), 0.5)
  expect_equal(share("moderate", "maxnet"), 1)
  expect_equal(share("indicative", "maxnet"), 1)
  expect_equal(share("moderate", "rf"), 0.5)
})

# --- Pooling the shards -------------------------------------------------------

cal_results <- function(shard, taxa, seed = 1, nulls = 99) {
  list(settings = list(seed = seed, shard = shard, nulls = nulls, stop_after = 5, designs = list("scatter", "shift"),
                       redraws = 20), taxa = taxa)
}

cal_write <- function(results) {
  path <- tempfile(fileext = ".json")
  jsonlite::write_json(results, path, auto_unbox = TRUE, null = "null", na = "null")
  path
}

test_that("a run's shards pool only when they are one split of one run, each once, with no species twice", {
  a <- cal_write(cal_results("1/2", list(cal_species("s1", "geography", "20-29"))))
  b <- cal_write(cal_results("2/2", list(cal_species("s2", "geography", "20-29"))))
  pooled <- atlas_calibration_pool(c(a, b), expected = 2L)
  expect_true(pooled$complete)
  expect_equal(pooled$species, 2L)
  expect_false(atlas_calibration_pool(a, expected = 2L)$complete)
  expect_false(atlas_calibration_pool(c(a, b), expected = 2840L)$complete)
  expect_error(atlas_calibration_pool(c(a, a), expected = 2L), "appears twice")
  expect_error(atlas_calibration_pool(c(a, cal_write(cal_results("2/2", list(cal_species("s2", "geography", "20-29")),
                                                                 seed = 2))), expected = 2L), "not shards of one")
  expect_error(atlas_calibration_pool(c(a, cal_write(cal_results("2/3", list(cal_species("s2", "geography", "20-29"))))),
                                      expected = 2L), "different splits")
  expect_error(atlas_calibration_pool(c(a, cal_write(cal_results("2/2", list(cal_species("s1", "geography", "20-29"))))),
                                      expected = 2L), "two shards")
})

test_that("a pooled run read back from JSON gives the same tests as the rows it was written from", {
  rows <- cal_world()
  half <- seq_along(rows) %% 2 == 0
  paths <- c(cal_write(cal_results("1/2", rows[half])), cal_write(cal_results("2/2", rows[!half])))
  pooled <- atlas_calibration_pool(paths, expected = length(rows))
  expect_true(pooled$complete)
  from_json <- atlas_calibration_read(pooled$rows, reps = 200)
  direct <- atlas_calibration_read(rows, reps = 200)
  expect_equal(from_json$c1, direct$c1)
  expect_equal(from_json$learners$maxnet$h1a$passed, direct$learners$maxnet$h1a$passed)
  expect_equal(from_json$learners$rf$h1e$difference, direct$learners$rf$h1e$difference)
})

test_that("a run's shards are pooled from a study prefix in the store, and complete only when every shard is there", {
  dir <- tempfile("store-")
  prefix <- "study/study-e1/"
  put <- function(shard, taxa) {
    key <- sprintf("%svirtual-e1-seed1-shard-%sof2-20261101T000000Z.json", prefix, sub("/.*$", "", shard))
    dir.create(file.path(dir, dirname(key)), recursive = TRUE, showWarnings = FALSE)
    file.copy(cal_write(cal_results(shard, taxa)), file.path(dir, key))
    key
  }
  keys <- put("1/2", list(cal_species("s1", "geography", "20-29")))
  store <- list(list = function(p) keys[startsWith(keys, p)],
                get = function(k, dest) file.copy(file.path(dir, k), dest, overwrite = TRUE))
  expect_false(atlas_calibration_pool_from(store, prefix, expected = 2L)$complete)
  keys <- c(keys, put("2/2", list(cal_species("s2", "geography", "20-29"))), paste0(prefix, "virtual-e1-x.log"))
  pooled <- atlas_calibration_pool_from(store, prefix, expected = 2L)
  expect_true(pooled$complete)
  expect_error(atlas_calibration_pool_from(store, "releases/draft/"), "only under")
  expect_error(atlas_calibration_pool_from(store, "study/none/"), "no calibration results")
})
