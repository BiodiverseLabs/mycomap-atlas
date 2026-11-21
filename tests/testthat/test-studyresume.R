# A study job's shard resumes: what its study runs score is uploaded as they
# go (atlas_run_study), and a worker that replaces a lost one scores only the
# taxa that upload does not hold. The calibration run of 2026-11-20 lost
# every shard's work when one shard's slow taxa outlived three workers.

RESUME_TAXA <- paste("Taxon", LETTERS[1:5])

# A taxon function the runner finds by name, as a study's own is. It scores
# each taxon the same way every time (as a seeded study does), counts its
# calls, and is lost (a spot worker taken back) after `lose_after` calls, or
# fails the taxa named in `fail`.
resume_taxon_fn <- function(lose_after = Inf, fail = character()) {
  seen <- new.env()
  seen$taxa <- character()
  assign(".resume_test_taxon", function(name, fingerprint, points, stack, ...) {
    if (length(seen$taxa) >= lose_after) {
      stop(structure(class = c("atlas_test_lost", "condition"),
                     list(message = "the worker was taken back", call = NULL)))
    }
    seen$taxa <- c(seen$taxa, name)
    if (name %in% fail) stop("a bad taxon")
    list(taxon = name, status = "scored", presences = 10L + nchar(name), seconds = 1,
         arms = list(list(arm = "a", auc = round(0.5 + match(name, RESUME_TAXA) / 100, 3), boyce = 0.2)))
  }, envir = globalenv())
  seen
}

resume_run <- function(progress, taxa = RESUME_TAXA, settings = list(seed = 1L), upload_seconds = 0) {
  tryCatch(
    atlas_run_study(
      kind = "resume-studies", file_prefix = "resume-shard-1of2", taxon_fn = ".resume_test_taxon",
      sample = data.frame(scientific_name = taxa, stringsAsFactors = FALSE),
      fingerprints = stats::setNames(as.list(seq_along(taxa)), taxa), args = list(), settings = settings,
      baseline = "a", points = NULL, stack = list(stub = TRUE), quiet = TRUE,
      summarise = function(rows, baseline) data.frame(),
      progress = progress, upload_seconds = upload_seconds),
    atlas_test_lost = function(e) NULL)
}

by_taxon <- function(rows) rows[order(vapply(rows, function(r) r$taxon, ""))]

resume_progress <- function(store, shard = 1L) list(store = store, job = "study-resume", shard = shard, grid = "draft")

test_that("a study shard's next worker scores only the taxa its lost worker did not upload, and ends with an unbroken run's rows", {
  on.exit(rm(".resume_test_taxon", envir = globalenv()), add = TRUE)
  with_data_dir({
    store <- fresh_store()
    # Lost after two taxa.
    first <- resume_taxon_fn(lose_after = 2L)
    expect_null(resume_run(resume_progress(store)))
    expect_equal(first$taxa, RESUME_TAXA[1:2])
    expect_equal(atlas_study_saved_count(store, "study-resume", 1L), 2L)
    # The orchestrator counts them, so this worker did not use up an attempt.
    expect_equal(atlas_shard_saved_count(store, "study-resume", 1L), 2L)
    # The results as they stood are there to read too.
    keys <- store$list("jobs/draft/study-resume/shards/")
    expect_true(any(grepl("^1[.]study-.*[.]progress[.]json$", basename(keys))))
    # Not a shard record: the shard has not reported.
    expect_false(any(grepl("^[0-9]+[.]json$", basename(keys))))

    second <- resume_taxon_fn()
    resumed <- resume_run(resume_progress(store))
    expect_equal(second$taxa, RESUME_TAXA[3:5])
    expect_length(resumed$taxa, 5L)
    written <- jsonlite::fromJSON(resumed$path, simplifyVector = FALSE)
    expect_setequal(vapply(written$taxa, function(r) r$taxon, ""), RESUME_TAXA)

    unbroken_seen <- resume_taxon_fn()
    unbroken <- resume_run(NULL)
    expect_equal(unbroken_seen$taxa, RESUME_TAXA)
    expect_identical(by_taxon(resumed$taxa), by_taxon(unbroken$taxa))
    expect_equal(atlas_study_saved_count(store, "study-resume", 1L), 5L)
  })
})

test_that("a resumed shard tries its failed taxa again, and never takes rows saved under other settings or by another shard", {
  on.exit(rm(".resume_test_taxon", envir = globalenv()), add = TRUE)
  with_data_dir({
    store <- fresh_store()
    resume_taxon_fn(lose_after = 3L, fail = "Taxon B")
    resume_run(resume_progress(store))
    # A failed taxon is not saved progress.
    expect_equal(atlas_study_saved_count(store, "study-resume", 1L), 2L)
    again <- resume_taxon_fn()
    result <- resume_run(resume_progress(store))
    expect_equal(again$taxa, RESUME_TAXA[c(2, 4, 5)])
    expect_true(all(vapply(result$taxa, function(r) r$status, "") == "scored"))

    # Another shard, or the same shard under other settings, starts afresh.
    other <- resume_taxon_fn()
    resume_run(resume_progress(store, shard = 2L))
    expect_equal(other$taxa, RESUME_TAXA)
    changed <- resume_taxon_fn()
    resume_run(resume_progress(store), settings = list(seed = 2L))
    expect_equal(changed$taxa, RESUME_TAXA)
  })
})

test_that("a study run uploads its progress at most every few minutes, and once more when it ends", {
  on.exit(rm(".resume_test_taxon", envir = globalenv()), add = TRUE)
  with_data_dir({
    store <- fresh_store()
    puts <- character()
    counted <- store
    counted$put <- function(key, file) {
      puts <<- c(puts, key)
      store$put(key, file)
    }
    resume_taxon_fn()
    resume_run(resume_progress(counted), upload_seconds = ATLAS_WORKER_LOG_SECONDS)
    rds <- puts[grepl("[.]progress[.]rds$", puts)]
    # The first taxon, at once (a worker lost after it has still saved
    # something), then not again within five minutes until the run ends.
    expect_length(rds, 2L)
    expect_equal(atlas_study_saved_count(store, "study-resume", 1L), 5L)
  })
})

test_that("a progress upload that fails costs the run nothing", {
  on.exit(rm(".resume_test_taxon", envir = globalenv()), add = TRUE)
  with_data_dir({
    store <- fresh_store()
    broken <- store
    broken$put <- function(key, file) stop("SlowDown: the store is busy", call. = FALSE)
    resume_taxon_fn()
    result <- resume_run(resume_progress(broken))
    expect_length(result$taxa, 5L)
  })
})

test_that("a worker may write a study shard's progress, and only a study job's shard runs are told where", {
  on.exit(rm(".resume_test_taxon", envir = globalenv()), add = TRUE)
  with_data_dir({
    store <- fresh_store()
    job <- atlas_plan_study_job(store, "study-rescan", shards = 2L, commands = "study-rescan", quiet = TRUE)
    told <- NULL
    main <- function(argv) {
      told <<- getOption("atlas.study_progress")
      resume_taxon_fn()
      atlas_run_study(
        kind = "resume-studies", file_prefix = "resume", taxon_fn = ".resume_test_taxon",
        sample = data.frame(scientific_name = RESUME_TAXA, stringsAsFactors = FALSE),
        fingerprints = list(), args = list(), settings = list(), baseline = "a", points = NULL,
        stack = list(stub = TRUE), quiet = TRUE, summarise = function(rows, baseline) data.frame())
      invisible(0L)
    }
    record <- on_machine(machine(), atlas_run_study_shard(worker_store(store), job$id, 2L, quiet = TRUE, main = main))
    expect_equal(record$status, "succeeded")
    expect_identical(told$job, job$id)
    expect_identical(told$shard, 2L)
    expect_equal(atlas_shard_saved_count(store, job$id, 2L), 5L)
    expect_null(getOption("atlas.study_progress"))
  })
})
