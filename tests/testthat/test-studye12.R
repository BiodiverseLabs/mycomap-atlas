# Paper E12's draw: seeded, stratified, the same every time, and its cost
# from the recorded fit times with the plan's one cap.

e12_index <- function() {
  entry <- function(algorithm, taxon, presences, grade, refused = FALSE) {
    Filter(Negate(is.null), list(algorithm = algorithm, taxon = taxon, fingerprint = paste0("fp-", taxon),
                                 presences = presences, grade = grade, refused = if (refused) TRUE))
  }
  c(
    lapply(sprintf("Strong %02d", 1:40), function(t) entry("maxnet", t, 60, "strong")),
    lapply(sprintf("Weak %02d", 1:8), function(t) entry("maxnet", t, 25, "weak")),
    lapply(sprintf("Forest %02d", 1:30), function(t) entry("rf", t, 12, "failed")),
    list(entry("esm", "Few one", 3, "strong"), entry("esm", "Untested", 4, "untested"),
         entry("maxnet", "Refused", 10, NULL, refused = TRUE), entry("maxnet", "Too few", 2, "weak"))
  )
}

test_that("the draw takes the first 25 of each cell in a seeded order, the same every time and whatever came before", {
  index <- e12_index()
  d <- atlas_e12_draw(index)
  expect_setequal(unique(d$cell), c("maxnet | 50+ | strong", "maxnet | 20-49 | weak", "rf | 5-19 | failed",
                                    "esm | 3-4 | strong"))
  counts <- tapply(d$drawn, d$cell, sum)
  expect_equal(as.vector(counts[c("maxnet | 50+ | strong", "maxnet | 20-49 | weak", "rf | 5-19 | failed",
                               "esm | 3-4 | strong")]), c(25L, 8L, 25L, 1L))
  # Left out: the refused, the untested and the one below every band.
  left <- attr(d, "left_out")
  expect_equal(left$refused, 1L)
  expect_equal(left[["grade untested"]], 1L)
  expect_equal(left[["no band"]], 1L)
  # The same draw again, from another random state, and with the index in
  # another order; the caller's stream is left as it was.
  set.seed(99)
  before <- stats::runif(1)
  set.seed(99)
  again <- atlas_e12_draw(rev(index))
  expect_equal(stats::runif(1), before)
  expect_identical(again[, c("cell", "taxon", "rank")], d[, c("cell", "taxon", "rank")])
  # A cell's order is its own: dropping another cell does not change it.
  alone <- atlas_e12_draw(Filter(function(e) identical(e$algorithm, "rf"), index))
  expect_identical(alone$taxon, d$taxon[d$cell == "rf | 5-19 | failed"])
  # And it is not just taxon order.
  rf <- d[d$cell == "rf | 5-19 | failed", ]
  expect_false(identical(rf$taxon, sort(rf$taxon)))
})

test_that("the cost is three fits of the recorded times, and rich Maxent is capped at 10 a cell only past half of it", {
  d <- atlas_e12_draw(e12_index())
  key <- function(rows) paste(rows$algorithm, rows$taxon, rows$fingerprint, sep = "|")
  # Rich Maxent dominates: 600 s each against 10 s for the rest.
  seconds <- stats::setNames(ifelse(d$algorithm == "maxnet" & d$band == "50+", 600, 10), key(d))
  cost <- atlas_e12_cost(d, seconds)
  expect_true(cost$summary$cap_applied)
  m <- cost$models
  rich <- m$algorithm == "maxnet" & m$band == "50+"
  expect_equal(sum(m$sample & rich), 10L)
  expect_true(all(m$rank[m$sample & rich] <= 10L))
  expect_equal(sum(m$sample & !rich), sum(m$drawn & !rich))
  expect_equal(cost$summary$cpu_hours, (10 * 600 + sum(m$drawn & !rich) * 10) * 3 / 3600, tolerance = 0.05)
  # Cheap rich Maxent: no cap.
  cheap <- atlas_e12_cost(d, stats::setNames(rep(10, nrow(d)), key(d)))
  expect_false(cheap$summary$cap_applied)
  expect_equal(cheap$summary$sample, sum(d$drawn))
  # A missing time takes its cell's median, flagged.
  partial <- seconds
  partial[key(d[d$cell == "rf | 5-19 | failed", ])[1]] <- NA
  filled <- atlas_e12_cost(d, partial[!is.na(partial)])
  expect_equal(filled$summary$imputed, 1L)
  expect_equal(filled$models$seconds[filled$models$imputed], 10)
})

test_that("recorded fit times come from the job that fitted the release's model", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  main <- setup$main
  seconds <- atlas_e12_seconds(setup$store, main)
  fitted <- Filter(function(e) !isTRUE(e$refused), main$index)
  keys <- vapply(fitted, function(e) paste(e$algorithm, e$taxon, e$fingerprint %||% "", sep = "|"), "")
  expect_true(length(seconds) > 0L)
  expect_true(all(names(seconds) %in% keys))
  expect_true(all(seconds >= 0))
})

test_that("study-e12-draw is a command", {
  expect_true("study-e12-draw" %in% atlas_cli_commands())
})
