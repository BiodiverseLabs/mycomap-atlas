# Paper E12's refit arms (study-repro --draw): every arm fits the same drawn
# models, each on the inputs and settings of the job that fitted it, graded
# with that job's nulls, in a recorded order; nothing but a results file under
# the study's prefix is written.

# A stand-in for the worker processes: fits nothing, but answers for each
# model as a graded fit would, and keeps what it was asked.
arm_runner <- function(calls = new.env()) {
  calls$asked <- list()
  function(models, fit_settings, nulls, grid = "draft", workers = 1L) {
    calls$asked[[length(calls$asked) + 1L]] <- list(models = models, fit = fit_settings, nulls = nulls,
                                                    workers = workers,
                                                    pull = atlas_read_manifest()$file %||% NA_character_)
    lapply(seq_len(nrow(models)), function(i) {
      list(taxon = models$taxon[[i]], status = "fitted", fingerprint = models$fingerprint[[i]],
           settings = "classes=lq regmult=1", tuning = c(0.7, 0.71), auc_mean = 0.7, boyce = 0.3,
           grade = models$grade[[i]], algorithm = models$algorithm[[i]], position = i, worker = 1L)
    })
  }
}

two_job_release <- function() {
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 22))))
  fit <- map_fit(REFRESH_GRADES)
  # The first job loses Taxon B; a second job fits it.
  losing <- function(name, ...) {
    if (identical(name, "Taxon B")) stop("worker lost")
    fit(name, ...)
  }
  first <- full_cycle(store, boss, fit = losing)
  second <- full_cycle(store, boss, fit = fit)
  list(store = store, boss = boss, first = first, second = second)
}

no_seconds <- function(...) stats::setNames(numeric(), character())

test_that("every arm draws the same models, whatever its order or shards, and the shards cover them once", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  base <- setup$main
  seeded <- atlas_e12_arm_models(setup$store, base, order = "seeded", seconds = no_seconds())
  reverse <- atlas_e12_arm_models(setup$store, base, order = "reverse", seconds = no_seconds())
  expect_true(nrow(seeded) > 0L)
  expect_identical(attr(seeded, "sample_key"), attr(reverse, "sample_key"))
  key <- function(d) paste(d$algorithm, d$taxon)
  expect_identical(key(reverse), rev(key(seeded)))
  # Seeded order is the draw's: cell by cell, by rank.
  expect_identical(key(seeded), key(seeded[order(seeded$cell, seeded$rank, method = "radix"), ]))
  # Three shards, then four: each model in exactly one shard of each split.
  for (n in c(3L, 4L)) {
    parts <- unlist(lapply(seq_len(n), function(i) key(seeded)[atlas_study_shard(seq_len(nrow(seeded)), paste0(i, "/", n))]))
    expect_setequal(parts, key(seeded))
    expect_false(anyDuplicated(parts) > 0L)
  }
})

test_that("each drawn model is fitted on the inputs, settings and nulls of the job that fitted it", {
  skip_if_not_installed("terra")
  world <- two_job_release()
  calls <- new.env()
  result <- on_machine(machine(), atlas_e12_arm_study(world$store, world$second$id, label = "a1",
                                                      fit_models = arm_runner(calls), seconds = no_seconds(),
                                                      quiet = TRUE))
  first <- atlas_read_job(world$store, world$first$job)
  second <- atlas_read_job(world$store, world$second$job)
  # One call per fitting job, holding only its own models, on its own pull,
  # with its own fit settings and nulls.
  by_job <- list()
  for (a in calls$asked) {
    jobs <- unique(vapply(seq_len(nrow(a$models)), function(i) {
      if (identical(a$models$taxon[[i]], "Taxon B")) second$id else first$id
    }, ""))
    expect_length(jobs, 1L)
    owner <- if (identical(jobs, second$id)) second else first
    expect_identical(a$pull, basename(atlas_job_pull_entry(owner)$path))
    expect_identical(a$fit, owner$fit)
    expect_equal(a$nulls, as.integer(owner$fit$nulls %||% ATLAS_NULL_REPS))
    by_job[[jobs]] <- c(by_job[[jobs]], a$models$taxon)
  }
  expect_true(all(by_job[[second$id]] == "Taxon B"))
  expect_false("Taxon B" %in% by_job[[first$id]])
  sources <- vapply(result$models, function(m) m$fit$source_job, "")
  taxa <- vapply(result$models, function(m) m$taxon, "")
  expect_true(all(sources[taxa == "Taxon B"] == second$id))
  expect_true(all(sources[taxa != "Taxon B"] == first$id))
  # The stand-in reproduces each model's records and grade: the comparison says so.
  expect_equal(result$summary$same_records, length(result$models))
  expect_equal(result$summary$same_grade, length(result$models))
})

test_that("an arm records its sample, order and shard, compares each fit with the release, and writes only under the study prefix", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  before <- sort(unlist(setup$store$list("")))
  result <- on_machine(machine(), atlas_e12_arm_study(setup$store, setup$main$id, label = "a2", order = "reverse",
                                                      shard = "1/2", workers = 3L, out = "study/e12-test/",
                                                      fit_models = arm_runner(), seconds = no_seconds(),
                                                      quiet = TRUE))
  all <- atlas_e12_arm_models(setup$store, setup$main, order = "reverse", seconds = no_seconds())
  expect_equal(result$sample_key, attr(all, "sample_key"))
  expect_equal(result$drawn, nrow(all))
  expect_equal(result$order, "reverse")
  expect_equal(result$shard, "1/2")
  expect_equal(length(result$models), length(atlas_study_shard(seq_len(nrow(all)), "1/2")))
  m <- result$models[[1]]
  expect_false(is.null(m$release$grade))
  expect_false(is.null(m$against_release$identical))
  added <- sub("^/", "", setdiff(sort(unlist(setup$store$list(""))), before))
  expect_length(added, 1L)
  expect_match(added, "^study/e12-test/.*[.]json$")
  expect_equal(atlas_current_release(setup$store)$id, setup$main$id)
  # A nulls override reaches the fits.
  calls <- new.env()
  on_machine(machine(), atlas_e12_arm_study(setup$store, setup$main$id, nulls = 19L, fit_models = arm_runner(calls),
                                            seconds = no_seconds(), quiet = TRUE))
  expect_true(all(vapply(calls$asked, function(a) a$nulls, 0) == 19))
})

test_that("--limit fits only the shard's first models, for a smoke run, and keeps the whole sample's key", {
  skip_if_not_installed("terra")
  setup <- refresh_setup()
  calls <- new.env()
  result <- on_machine(machine(), atlas_e12_arm_study(setup$store, setup$main$id, limit = 2, fit_models = arm_runner(calls),
                                                      seconds = no_seconds(), quiet = TRUE))
  all <- atlas_e12_arm_models(setup$store, setup$main, seconds = no_seconds())
  expect_length(result$models, 2L)
  expect_equal(vapply(result$models, function(m) paste(m$algorithm, m$taxon), ""),
               paste(all$algorithm, all$taxon)[1:2])
  expect_equal(result$sample_key, attr(all, "sample_key"))
  expect_equal(result$limit, 2L)
  expect_equal(sum(vapply(calls$asked, function(a) nrow(a$models), 0)), 2)
})

test_that("models are dealt to worker processes in order, so order and split set each model's place", {
  expect_equal(atlas_e12_worker_parts(7, 3), c(1L, 2L, 3L, 1L, 2L, 3L, 1L))
  expect_equal(atlas_e12_worker_parts(2, 8), c(1L, 2L))
  expect_equal(atlas_e12_worker_parts(4, 1), rep(1L, 4))
})

test_that("a worker fits its models in order, graded with the nulls it is given, and records where and how", {
  skip_if_not_installed("terra")
  with_data_dir({
    asked <- list()
    local_mocked_bindings(atlas_fit_batch = function(taxa, algorithm, nulls, ...) {
      asked[[length(asked) + 1L]] <<- list(taxon = taxa, algorithm = algorithm, nulls = nulls)
      dir.create(atlas_model_dir("draft", algorithm), recursive = TRUE, showWarnings = FALSE)
      atlas_write_json(list(taxon = taxa, algorithm = algorithm, fingerprint = paste0("fp-", taxa), presences = 22,
                            background = 900, predictors = list("v1"), params = list(classes = "lq", regmult = 2),
                            tuning = list(0.7, 0.72), auc_mean = 0.71, boyce = 0.4, boyce_mean = 0.3,
                            folds = list(list(auc = 0.7)), skill = "passed", grade = "strong", map_strength = 0.6,
                            null = list(design = "shift", reps = 40, drawn = 41, auc_p = 0.02)),
                       atlas_model_path(taxa, "draft", ".json", algorithm))
      writeLines("raster", atlas_model_path(taxa, "draft", ".tif", algorithm))
      invisible(NULL)
    })
    models <- data.frame(taxon = c("Taxon B", "Taxon A"), algorithm = c("rf", "maxnet"),
                         fingerprint = c("fp-Taxon B", "fp-Taxon A"), stringsAsFactors = FALSE)
    fits <- atlas_e12_worker_fit(models, list(n_background = 500), nulls = 99L, occurrences = data.frame(),
                                 points = data.frame(), stack = list())
    expect_equal(vapply(asked, function(a) a$taxon, ""), c("Taxon B", "Taxon A"))
    expect_true(all(vapply(asked, function(a) a$nulls, 0) == 99))
    expect_equal(vapply(fits, function(f) f$position, 0), c(1, 2))
    expect_equal(fits[[1]]$grade, "strong")
    expect_equal(fits[[1]]$null_p, 0.02)
    expect_equal(fits[[1]]$null_drawn, 41)
    expect_equal(fits[[1]]$boyce, 0.4)
    expect_equal(fits[[1]]$settings, "classes=lq regmult=2")
    expect_true(is.character(fits[[1]]$tif_sha256))
    expect_equal(fits[[1]]$process, Sys.getpid())
  })
})

test_that("study-repro --draw is a command, and the plain study-repro still needs its taxa", {
  expect_true("study-repro" %in% atlas_cli_commands())
  expect_error(atlas_main(c("study-repro", "--draw")), "needs --release")
  expect_error(atlas_main(c("study-repro", "--release=x")), "needs --release=ID --source-job=ID --taxa")
})
