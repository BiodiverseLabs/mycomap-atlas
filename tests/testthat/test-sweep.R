# The predictor-count sweep: how many predictors per presence cell.

test_that("presence counts fall into the bands the sweep is stratified by", {
  expect_equal(
    atlas_presence_band(c(12, 20, 29, 30, 49, 50, 199, 200, 900)),
    c("<20", "20-29", "20-29", "30-49", "30-49", "50-99", "100-199", "200+", "200+")
  )
})

test_that("the sample takes at most so many taxa per band, the same ones every time", {
  candidates <- data.frame(
    scientific_name = paste("Taxon", 1:100),
    cells = c(rep(22, 60), rep(35, 30), rep(250, 10)),
    stringsAsFactors = FALSE
  )
  first <- atlas_sweep_sample(candidates, per_band = 20, seed = 5L)
  again <- atlas_sweep_sample(candidates, per_band = 20, seed = 5L)
  expect_equal(first, again)
  expect_equal(as.vector(table(first$band)[c("20-29", "30-49", "200+")]), c(20L, 20L, 10L))
})

test_that("--constants reads none as no cap, and refuses nonsense", {
  expect_equal(atlas_parse_constants("2,4,none"), c(2, 4, Inf))
  expect_error(atlas_parse_constants("2,four"), "positive numbers")
  expect_error(atlas_parse_constants("0,4"), "positive numbers")
})

# Two taxa, two arms. Taxon A gains 0.05 from the tighter cap; taxon B loses
# 0.01. A failure and a refusal must not enter the averages.
sweep_rows <- function() {
  arm <- function(k, auc, n) list(per_presence = k, predictors = n, auc = auc,
                                  boyce = auc - 0.2, folds_scored = 5)
  list(
    list(taxon = "A", status = "scored", presences = 24, band = "20-29",
         arms = list(arm(2, 0.65, 12), arm(4, 0.60, 6))),
    list(taxon = "B", status = "scored", presences = 150, band = "100-199",
         arms = list(arm(2, 0.70, 18), arm(4, 0.71, 18))),
    list(taxon = "C", status = "failed", error = "boom"),
    list(taxon = "D", status = "refused", presences = 12)
  )
}

test_that("the summary compares each taxon with itself under the baseline", {
  summary <- atlas_sweep_summary(sweep_rows())
  row <- function(band, arm) summary[summary$band == band & summary$arm == arm, ]
  expect_equal(row("20-29", "2")$delta_auc, 0.05)
  expect_equal(row("100-199", "2")$delta_auc, -0.01)
  expect_equal(row("all", "2")$delta_auc, 0.02)
  expect_equal(row("all", "4")$delta_auc, 0)
})

test_that("failed and refused taxa are left out of the averages", {
  summary <- atlas_sweep_summary(sweep_rows())
  expect_equal(summary$taxa[summary$band == "all" & summary$arm == "4"], 2L)
})

test_that("the summary says which arm won for how many taxa", {
  summary <- atlas_sweep_summary(sweep_rows())
  expect_equal(summary$best_share[summary$band == "all" & summary$arm == "2"], 0.5)
  expect_equal(summary$best_share[summary$band == "20-29" & summary$arm == "2"], 1)
})

test_that("bands are listed smallest first, with the overall row last", {
  summary <- atlas_sweep_summary(sweep_rows())
  expect_equal(unique(summary$band), c("20-29", "100-199", "all"))
})

test_that("every arm is scored on the same folds, so only the cap differs", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  # The landscape has two predictors, fewer than any cap allows, so every arm
  # keeps the same ones. On shared folds they must then score identically; if
  # each arm drew its own folds, they would not.
  row <- atlas_sweep_taxon(
    "Eastern fungus", fingerprint = "f00dfeed", points = world$points,
    stack = world$stack, constants = c(2, 4, Inf), n_background = 500,
    buffer_km = 300
  )
  expect_equal(row$status, "scored")
  aucs <- vapply(row$arms, function(a) a$auc, numeric(1))
  expect_equal(length(unique(aucs)), 1L)
  expect_gt(aucs[[1]], 0.6)
  expect_equal(vapply(row$arms, function(a) as.character(a$per_presence), character(1)),
               c("2", "4", "none"))
})

test_that("a sweep writes its results and never touches the fitted models", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  with_data_dir({
    world <- synthetic_landscape()
    occurrences <- data.frame(
      id = as.character(seq_len(nrow(world$points))),
      scientific_name = world$points$scientific_name,
      latitude = "45", longitude = "-100", observed_on = "2025-01-01",
      stringsAsFactors = FALSE
    )
    result <- atlas_predictor_sweep(
      occurrences = occurrences, points = world$points, stack = world$stack,
      constants = c(4, Inf), n_background = 500, buffer_km = 300, quiet = TRUE
    )
    expect_true(file.exists(result$path))
    expect_false(dir.exists(atlas_path("models")))
    saved <- jsonlite::fromJSON(result$path, simplifyVector = FALSE)
    expect_equal(length(saved$taxa), 2L)
    expect_true(length(saved$summary) > 0)
  })
})
