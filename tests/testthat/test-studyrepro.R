# Refit reproducibility (paper E12's gate): fits of the same models in fresh
# processes, compared with each other and with the release, written only
# under the study's prefix.

repro_runner <- function(store, release, change = NULL) {
  fits <- NULL
  calls <- 0L
  function(taxa, algorithm, fit_settings, grid = "draft") {
    calls <<- calls + 1L
    if (is.null(fits)) fits <<- atlas_repro_release_fits(store, release, taxa, algorithm, grid)
    out <- fits
    if (is.function(change)) out <- change(out, calls)
    out
  }
}

test_that("runs that reproduce the release are reported as agreeing, and the results go under the study prefix only", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  main <- setup$main
  before <- sort(unlist(setup$store$list("")))
  result <- on_machine(machine(), atlas_repro_study(
    setup$store, release = main$id, source_job = atlas_json_string(main$job),
    taxa = "Taxon A|Taxon B", runs = 3L, out = "study/repro-test/", label = "r7i",
    run = repro_runner(setup$store, main), quiet = TRUE))
  expect_equal(result$summary$models, 2L)
  expect_equal(result$summary$runs_agree, 2L)
  expect_equal(result$summary$match_release, 2L)
  expect_length(result$models[[1]]$runs, 3L)
  expect_equal(result$models[[1]]$release$status, "fitted")
  # Written: the results file under the study prefix, nothing else.
  added <- sub("^/", "", setdiff(sort(unlist(setup$store$list(""))), before))
  expect_length(added, 1L)
  expect_match(added, "^study/repro-test/.*[.]json$")
  expect_match(added, "shard-1of1[.]json$")
  expect_equal(atlas_current_release(setup$store)$id, main$id)
})

test_that("two shards of one repro job publish two results files, not one over the other", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  main <- setup$main
  before <- sort(unlist(setup$store$list("")))
  for (shard in c("1/2", "2/2")) {
    on_machine(machine(), atlas_repro_study(
      setup$store, release = main$id, source_job = atlas_json_string(main$job),
      taxa = "Taxon A|Taxon B", runs = 2L, out = "study/repro-test/", label = "r7i", shard = shard,
      run = repro_runner(setup$store, main), quiet = TRUE))
  }
  added <- sub("^/", "", setdiff(sort(unlist(setup$store$list(""))), before))
  expect_length(added, 2L)
  expect_match(added, "shard-[12]of2[.]json$")
})

test_that("a run whose tuning scores move is reported, with which parts differ and by how much", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  main <- setup$main
  moved <- function(fits, call) {
    for (name in names(fits)) fits[[name]]$tuning <- c(0.71, 0.73)
    if (call == 2L) {
      fits[["Taxon A"]]$tuning <- c(0.70, 0.72)
      fits[["Taxon A"]]$settings <- "classes=lq regmult=4"
    }
    fits
  }
  result <- on_machine(machine(), atlas_repro_study(
    setup$store, release = main$id, source_job = atlas_json_string(main$job),
    taxa = "Taxon A|Taxon B", runs = 2L, run = repro_runner(setup$store, main, moved), quiet = TRUE))
  by_taxon <- stats::setNames(result$models, vapply(result$models, function(m) m$taxon, ""))
  a <- by_taxon[["Taxon A"]]
  expect_false(a$runs_agree)
  expect_setequal(unlist(a$between_runs[[1]]$differs), c("settings", "tuning"))
  expect_equal(a$between_runs[[1]]$tuning_max_difference, 0.01, tolerance = 1e-9)
  expect_true(by_taxon[["Taxon B"]]$runs_agree)
  expect_equal(result$summary$runs_agree, 1L)
})

test_that("study-repro refuses fewer than two runs, an unknown release, and a study prefix it may not write", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  main <- setup$main
  run <- repro_runner(setup$store, main)
  job <- atlas_json_string(main$job)
  expect_error(on_machine(machine(), atlas_repro_study(setup$store, main$id, job, "Taxon A", runs = 1L,
                                                       run = run, quiet = TRUE)), "2 or more")
  expect_error(on_machine(machine(), atlas_repro_study(setup$store, "no-such-release", job, "Taxon A",
                                                       run = run, quiet = TRUE)), "no release")
  expect_error(on_machine(machine(), atlas_repro_study(setup$store, main$id, job, "Taxon A", out = "releases/x/",
                                                       run = run, quiet = TRUE)), "a study writes only under")
  expect_error(atlas_repro_taxa(" | "), "needs --taxa")
  expect_equal(atlas_repro_taxa("Russula sp. 'compacta-PA01'| Gliophorus fumosus"),
               c("Russula sp. 'compacta-PA01'", "Gliophorus fumosus"))
  # As plan-study passes them: no spaces, percent-encoded.
  expect_equal(atlas_repro_taxa("Russula%20sp.%20%27compacta-PA01%27|Stropharia%20hardii"),
               c("Russula sp. 'compacta-PA01'", "Stropharia hardii"))
})

test_that("two fits compare as identical only when every part a rerun must reproduce is the same", {
  a <- list(status = "fitted", presences = 21, background = 3995, predictors = c("x", "y"),
            settings = "classes=lqh regmult=0.25", tuning = c(0.7071, 0.786), auc_mean = 0.75,
            boyce = 0.4, fold_auc = c(0.7, 0.8), tif_sha256 = "abc")
  expect_true(atlas_repro_compare(a, a)$identical)
  b <- a; b$tif_sha256 <- "abd"
  expect_equal(unlist(atlas_repro_compare(a, b)$differs), "tif_sha256")
  b <- a; b$fold_auc <- c(0.7, 0.81)
  expect_equal(unlist(atlas_repro_compare(a, b)$differs), "fold_auc")
  b <- a; b$predictors <- c("x", "z")
  expect_equal(unlist(atlas_repro_compare(a, b)$differs), "predictors")
  expect_false(atlas_repro_compare(a, list(status = "not fitted"))$identical)
})

test_that("study-repro is a command a study job can plan", {
  expect_true("study-repro" %in% atlas_cli_commands())
})
