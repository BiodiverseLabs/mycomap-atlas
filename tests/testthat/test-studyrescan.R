# The standard null test on a release's real models (paper E1c): a stratified
# sample of the release's models goes through 19 scattered nulls again, on
# inputs rebuilt exactly as production built them.

release_entries <- function() {
  grades <- c("strong", "weak", "failed")
  out <- list()
  for (i in 1:120) {
    out[[length(out) + 1L]] <- list(taxon = sprintf("Taxon %03d", i), algorithm = "maxnet",
                                    presences = c(25, 60, 150)[(i %% 3) + 1], grade = grades[(i %% 3) + 1])
  }
  c(out, list(
    list(taxon = "Untested", algorithm = "esm", presences = 4, grade = "untested"),
    list(taxon = "Refused", algorithm = "maxnet", presences = 30, grade = "strong", refused = TRUE),
    list(taxon = "Small", algorithm = "esm", presences = 4, grade = "weak")
  ))
}

test_that("only graded models are rescanned, in the plan's site bands", {
  population <- atlas_rescan_population(release_entries())
  expect_false(any(population$taxon %in% c("Untested", "Refused")))
  expect_equal(population$band[population$taxon == "Small"], "3-4")
  expect_setequal(unique(population$band), c("3-4", "20-49", "50-99", "100+"))
  expect_equal(atlas_presence_band(c(3, 5, 19, 20, 49, 50, 99, 100), ATLAS_RESCAN_BANDS),
               c("3-4", "5-19", "5-19", "20-49", "20-49", "50-99", "50-99", "100+"))
})

test_that("a stratum gives up to its cap of models, all of a smaller one, the same for the same seed", {
  population <- atlas_rescan_population(release_entries())
  sample <- atlas_rescan_sample(population, per_cell = 10, seed = 7)
  sizes <- table(sample$stratum)
  expect_true(all(sizes <= 10))
  expect_equal(sizes[["esm / 3-4 / weak"]], 1L)
  expect_equal(sum(sizes), 3 * 10 + 1)
  expect_equal(atlas_rescan_sample(population, per_cell = 10, seed = 7), sample)
  expect_false(identical(atlas_rescan_sample(population, per_cell = 10, seed = 8)$taxon, sample$taxon))
  strata <- atlas_rescan_strata(population, sample)
  expect_equal(strata$population[["maxnet / 20-49 / strong"]], 40L)
  expect_equal(strata$sampled[["maxnet / 20-49 / strong"]], 10L)
})

test_that("a model id carries a taxon name with any characters", {
  id <- atlas_rescan_id("Amanita 'sp-IN01' | odd", "maxnet")
  expect_equal(atlas_rescan_parse(id), list(algorithm = "maxnet", taxon = "Amanita 'sp-IN01' | odd"))
})

# --- Rebuilding a model exactly ----------------------------------------------

fitted_record <- function(world) {
  fit <- atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                         fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                         buffer_km = 300, predict = FALSE, write = FALSE, quiet = TRUE,
                         nulls = 3, tune = FALSE, importance = FALSE)
  fit$metrics
}

test_that("a release model rebuilt from its pull matches what production recorded", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  metrics <- fitted_record(world)
  expect_true(is.finite(metrics$null$observed_auc))
  id <- atlas_rescan_id("Eastern fungus", "maxnet")
  records <- stats::setNames(list(atlas_rescan_record(metrics)), id)
  row <- atlas_rescan_model(id, "f00dfeed", world$points, world$stack, records = records,
                            reps = 3, n_background = 500, buffer_km = 300)
  expect_equal(row$status, "scored")
  # The taxon's own untuned AUC is the one the release's shift test recorded:
  # the same sites, predictors and folds.
  expect_equal(row$scatter$observed_auc, metrics$null$observed_auc)
  expect_true(row$scatter$verdict %in% c("passed", "failed"))
  expect_equal(row$scatter$reps, 3L)
})

test_that("a rebuild that differs from the release's record is dropped and says why", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  record <- atlas_rescan_record(fitted_record(world))
  inputs <- atlas_rescan_inputs("Eastern fungus", "maxnet", record, world$points, world$stack,
                                n_background = 500, buffer_km = 300)
  expect_length(atlas_rescan_differences(inputs, record, "f00dfeed",
                                         observed_auc = record$observed_auc), 0L)
  # Within the recorded rounding is a match; beyond it is not.
  expect_length(atlas_rescan_differences(inputs, record, "f00dfeed",
                                         observed_auc = record$observed_auc + 0.0004), 0L)
  expect_equal(atlas_rescan_differences(inputs, record, "f00dfeed",
                                        observed_auc = record$observed_auc + 0.01), "observed_auc")
  expect_equal(atlas_rescan_differences(inputs, record, "beefcafe"), "fingerprint")
  expect_true("presences" %in% atlas_rescan_differences(inputs, modifyList(record, list(presences = 1L)), "f00dfeed"))
  expect_equal(atlas_rescan_differences(inputs, modifyList(record, list(predictors = c(record$predictors, "elsewhere"))), "f00dfeed"),
               "predictors")
  expect_equal(atlas_rescan_differences(inputs, modifyList(record, list(fold_presences = rev(record$fold_presences + 1L))), "f00dfeed"),
               "folds")

  id <- atlas_rescan_id("Eastern fungus", "maxnet")
  row <- atlas_rescan_model(id, "f00dfeed", world$points, world$stack,
                            records = stats::setNames(list(modifyList(record, list(block_km = record$block_km / 2))), id),
                            reps = 3, n_background = 500, buffer_km = 300)
  expect_equal(row$status, "mismatch")
  expect_null(row$scatter)
})

test_that("more than 2% of models failing to rebuild stops the reading", {
  rows <- c(rep(list(list(status = "scored")), 97), rep(list(list(status = "mismatch")), 3))
  health <- atlas_rescan_health(rows)
  expect_equal(health$dropped, 3L)
  expect_false(health$readable)
  expect_true(atlas_rescan_health(rows[-(98:99)])$readable)
})

test_that("a model whose run failed counts against the 2% as a mismatch does", {
  rows <- c(rep(list(list(status = "scored")), 97), rep(list(list(status = "failed", error = "boom")), 3))
  health <- atlas_rescan_health(rows)
  expect_equal(c(health$dropped, health$failed, health$mismatched), c(3L, 3L, 0L))
  expect_false(health$readable)
})

test_that("the summary counts maps the standard test passes that are not strong", {
  rows <- list(
    list(status = "scored", algorithm = "maxnet", grade = "strong", scatter = list(verdict = "passed")),
    list(status = "scored", algorithm = "maxnet", grade = "weak", scatter = list(verdict = "passed")),
    list(status = "scored", algorithm = "maxnet", grade = "failed", scatter = list(verdict = "passed")),
    list(status = "scored", algorithm = "maxnet", grade = "strong", scatter = list(verdict = "failed")),
    list(status = "mismatch", algorithm = "maxnet", grade = "weak")
  )
  summary <- atlas_rescan_summary(rows)
  expect_equal(summary$models, 4L)
  expect_equal(summary$scatter_passed, 3L)
  expect_equal(summary$passed_not_strong, 2L)
  expect_equal(summary$strong_failed, 1L)
})

test_that("a plan-only rescan sizes the sample and fits nothing", {
  view <- list(entries = release_entries())
  plan <- atlas_rescan_study(store = NULL, release = "frozen-test", view = view, per_cell = 10,
                             plan_only = TRUE, quiet = TRUE)
  expect_equal(plan$models, 31L)
  expect_gt(plan$cpu_hours, 0)
  expect_equal(plan$strata$sampled[["esm / 3-4 / weak"]], 1L)
  shard <- atlas_rescan_study(store = NULL, release = "frozen-test", view = view, per_cell = 10,
                              shard = "1/2", plan_only = TRUE, quiet = TRUE)
  expect_equal(shard$models, 16L)
})

test_that("a rebuilt model keeps only the predictors the release says it used", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  record <- modifyList(atlas_rescan_record(fitted_record(world)), list(predictors = "v1"))
  inputs <- atlas_rescan_inputs("Eastern fungus", "maxnet", record, world$points, world$stack,
                                n_background = 500, buffer_km = 300)
  expect_equal(setdiff(atlas_predictor_columns(inputs$training), ATLAS_EFFORT_COLUMN), "v1")
  expect_false("predictors" %in% atlas_rescan_differences(inputs, record, "f00dfeed"))
})

test_that("the standard test's verdict needs the release's own Boyce index above zero", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  record <- atlas_rescan_record(fitted_record(world))
  id <- atlas_rescan_id("Eastern fungus", "maxnet")
  verdict <- function(boyce) {
    records <- stats::setNames(list(modifyList(record, list(boyce = boyce))), id)
    atlas_rescan_model(id, "f00dfeed", world$points, world$stack, records = records,
                       reps = 19, n_background = 500, buffer_km = 300)$scatter
  }
  good <- verdict(0.5)
  # A taxon that lives only in the east beats every scattered null.
  expect_equal(good$auc_p, 0.05)
  expect_equal(good$verdict, "passed")
  expect_equal(verdict(-0.5)$verdict, "failed")
})

test_that("the 2% rule is read over every shard together, and a missing shard keeps the run unreadable", {
  dir <- tempfile("rescan-")
  dir.create(dir)
  shard <- function(i, statuses, of = 2, ids = NULL) {
    ids <- ids %||% sprintf("maxnet|Taxon %d-%03d", i, seq_along(statuses))
    path <- file.path(dir, paste0("shard", i, "of", of, "-", length(statuses), ".json"))
    jsonlite::write_json(list(settings = list(release = "r1", seed = 1, per_cell = 50, nulls = 19,
                                              shard = paste0(i, "/", of)),
                              strata = list(sampled = list(a = 100L)),
                              taxa = lapply(seq_along(statuses), function(k) list(
                                taxon = ids[[k]], status = statuses[[k]], algorithm = "maxnet",
                                grade = "strong", scatter = list(verdict = "passed")))),
                         path, auto_unbox = TRUE)
    path
  }
  # Each shard on its own is at 2%; together 4 of 100 have no verdict.
  a <- shard(1, c(rep("scored", 49), "failed"))
  b <- shard(2, c(rep("scored", 48), "mismatch", "mismatch"))
  expect_true(atlas_rescan_health(jsonlite::fromJSON(a, simplifyVector = FALSE)$taxa)$readable)
  pooled <- atlas_rescan_pool(c(a, b))
  expect_equal(c(pooled$models, pooled$health$dropped), c(100L, 3L))
  expect_false(pooled$readable)
  # One shard alone is not the run.
  expect_false(atlas_rescan_pool(a)$readable)
  expect_error(atlas_rescan_pool(c(a, a)), "twice")
  other <- file.path(dir, "other.json")
  jsonlite::write_json(list(settings = list(release = "r2", seed = 1, per_cell = 50, nulls = 19, shard = "2/2"),
                            taxa = list()), other, auto_unbox = TRUE)
  expect_error(atlas_rescan_pool(c(a, other)), "not shards of one rescan")
  # Shards of different splits never add up to a run, even when the
  # counts would happen to.
  expect_error(atlas_rescan_pool(c(a, shard(2, rep("scored", 50), of = 3))), "different splits")
  # A model in two shards is refused.
  twice <- shard(2, rep("scored", 50), ids = c("maxnet|Taxon 1-001", sprintf("maxnet|Taxon 2-%03d", 2:50)))
  expect_error(atlas_rescan_pool(c(a, twice)), "two shards")
  # With a shard missing, the run is not complete, however many rows it has.
  big <- shard(1, rep("scored", 100), of = 3)
  expect_false(atlas_rescan_pool(big)$complete)
})

test_that("a rescan model whose record keeps no folds is not trusted", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  world <- synthetic_landscape()
  record <- atlas_rescan_record(fitted_record(world))
  inputs <- atlas_rescan_inputs("Eastern fungus", "maxnet", record, world$points, world$stack,
                                n_background = 500, buffer_km = 300)
  expect_equal(atlas_rescan_differences(inputs, modifyList(record, list(fold_presences = integer())), "f00dfeed"),
               "no folds recorded")
})

test_that("a study job's rescan shards are pooled from the store, and only from a study prefix", {
  dir <- tempfile("store-")
  prefix <- "study/study-abc/"
  write_shard <- function(i) {
    key <- sprintf("%srescan-r1-20261020T01010%dZ.json", prefix, i)
    dir.create(file.path(dir, dirname(key)), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(list(settings = list(release = "r1", seed = 1, per_cell = 50, nulls = 19, shard = paste0(i, "/2")),
                              strata = list(sampled = list(a = 2L)),
                              taxa = list(list(taxon = paste0("maxnet|T", i), status = "scored", algorithm = "maxnet",
                                               grade = "strong", scatter = list(verdict = "passed")))),
                         file.path(dir, key), auto_unbox = TRUE)
    key
  }
  keys <- c(write_shard(1), write_shard(2), paste0(prefix, "rescan-r1-x.log"))
  store <- list(list = function(p) keys[startsWith(keys, p)],
                get = function(k, dest) file.copy(file.path(dir, k), dest, overwrite = TRUE))
  pooled <- atlas_rescan_pool_from(store, prefix)
  expect_equal(pooled$models, 2L)
  expect_true(pooled$complete)
  expect_true(pooled$readable)
  expect_error(atlas_rescan_pool_from(store, "releases/draft/"), "only under")
  expect_error(atlas_rescan_pool_from(store, "study/none/"), "no rescan results")
})
