# Which records trained a release: written to the store's private prefix for
# Vision's benchmark, and never published anywhere.

trained_list <- function(store, release, grid = "draft") {
  file <- tempfile(fileext = ".tsv.gz")
  store$get(atlas_trained_release_key(release, grid), file)
  utils::read.delim(gzfile(file), colClasses = "character", quote = "", na.strings = "")
}

trained_summary <- function(store, release, grid = "draft") {
  atlas_store_text(store, atlas_trained_release_key(release, grid, ".json"))
}

# The source ids of the taxa a release has a model for.
modelled_ids <- function(release, occurrences) {
  taxa <- unique(vapply(Filter(function(e) !isTRUE(e$refused), release$index), function(e) e$taxon, ""))
  sort(occurrences$observation_id[occurrences$scientific_name %in% taxa])
}

test_that("a finished job lists the source ids of every record its models were trained on", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  occurrences <- synthetic_occurrences(TAXA)
  on_machine(boss, orchestrator_data(occurrences))
  release <- full_cycle(store, boss)
  listed <- trained_list(store, release$id)
  expect_equal(sort(unique(listed$source_id)), modelled_ids(release, occurrences))
  expect_true(all(listed$source == "iNaturalist"))
  # Tiny is too sparse for a model: its records trained nothing.
  expect_false("Tiny" %in% listed$taxon)
  summary <- trained_summary(store, release$id)
  expect_equal(summary$records, nrow(listed))
  expect_length(summary$not_found, 0)
})

test_that("a model kept from an earlier pull keeps the records it was fitted on", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  first_records <- synthetic_occurrences(TAXA)
  on_machine(boss, orchestrator_data(first_records))
  full_cycle(store, boss)

  # Taxon B gains a record, but its refit fails: the release keeps the model
  # fitted on its 30 old records, so the list must too, not the new 31.
  second_records <- synthetic_occurrences(c(TAXA[-2], "Taxon B" = 31))
  on_machine(boss, orchestrator_data(second_records))
  breaks_b <- local({
    f <- function(name, ...) if (name == "Taxon B") stop("worker ran out of memory") else fake_fit(name, ...)
    environment(f) <- globalenv()
    f
  })
  second <- full_cycle(store, boss, fit = breaks_b)
  listed <- trained_list(store, second$id)
  b_old <- first_records$observation_id[first_records$scientific_name == "Taxon B"]
  b_new <- setdiff(second_records$observation_id[second_records$scientific_name == "Taxon B"], b_old)
  expect_setequal(listed$source_id[listed$taxon == "Taxon B"], b_old)
  expect_false(any(b_new %in% listed$source_id[listed$taxon == "Taxon B"]))
  expect_length(trained_summary(store, second$id)$not_found, 0)
})

test_that("a model whose record set is in no saved pull is named, not guessed", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  release <- full_cycle(store, boss)
  for (key in store$list(atlas_trained_pulls_prefix("draft"))) unlink(file.path(sub("^file://", "", store$uri), key))
  summary <- on_machine(boss, atlas_write_trained_ids(store, release, quiet = TRUE))
  expect_equal(summary$records, 0L)
  expect_setequal(unlist(summary$not_found), c("Taxon A", "Taxon B", "Taxon C"))
})

test_that("finishing a release carries its list over: finishing fits nothing", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  release <- full_cycle(store, boss)
  # The worker's record: one new file, as a finished index would be.
  index <- tempfile()
  writeLines("a new index", index)
  entry <- list(path = "index/draft/here.rds", sha256 = atlas_sha256(index), bytes = file.info(index)$size)
  store$put(atlas_object_key(entry$sha256), index)
  record <- list(job = atlas_finish_id(release$id), shard = 1L, release = release$id,
                 version = ATLAS_FINISH_VERSION, finished_at = "2026-10-08T00:00:00Z", counted = 0L,
                 files = list(entry))
  atlas_store_json(store, atlas_shard_key(atlas_finish_id(release$id), 1L, "draft"), record)
  finished <- on_machine(boss, atlas_apply_finish(store, release$id, quiet = TRUE))
  expect_false(identical(finished$id, release$id))
  expect_equal(trained_list(store, finished$id), trained_list(store, release$id))
  expect_equal(trained_summary(store, finished$id)$copied_from, release$id)
})

test_that("the list is never published: not in a release, its files, the API, or the Zenodo bundle", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  release <- full_cycle(store, boss)
  key <- atlas_trained_release_key(release$id)
  expect_true(store$exists(key))
  expect_true(startsWith(key, "private/"))

  file <- tempfile(fileext = ".tsv.gz")
  store$get(key, file)
  private_sha <- atlas_sha256(file)
  paths <- vapply(release$files, function(f) f$path, "")
  shas <- vapply(release$files, function(f) f$sha256, "")
  expect_false(any(grepl("trained|^private/", paths)))
  expect_false(private_sha %in% shas)

  on_machine(boss, {
    # Even a copy left under data/ is not on the release allowlist.
    dir.create(atlas_path("private", "trained-ids"), recursive = TRUE, showWarnings = FALSE)
    file.copy(file, atlas_path("private", "trained-ids", "copy.tsv.gz"))
    expect_false(any(grepl("trained|^private/", atlas_release_files("draft"))))
    bundle <- atlas_archive_models_bundle(store, "draft")
    expect_false(any(grepl("trained|private", names(bundle$sources))))
    bundle_shas <- vapply(bundle$sources, atlas_sha256, "")
    expect_false(private_sha %in% bundle_shas)
  })
  # No API route reads it.
  routes <- readLines(api_file(), warn = FALSE)
  expect_false(any(grepl("trained", routes, ignore.case = TRUE)))
  expect_false(any(grepl("trained", names(jsonlite::fromJSON(
    testthat::test_path("..", "..", "inst", "api", "openapi.json"), simplifyVector = FALSE)$paths))))
})

test_that("a release does not fail when its list cannot be written; it says so", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"), shards = 1L, quiet = TRUE))
  on_machine(machine(), atlas_run_shard(store, job$id, 1L, quiet = TRUE, fit = fake_fit))
  broken <- store
  broken$put <- function(key, file) {
    if (startsWith(key, "private/trained-ids/draft/releases/")) stop("access denied")
    store$put(key, file)
  }
  expect_warning(release <- on_machine(boss, atlas_finish_job(broken, job$id, quiet = TRUE)),
                 "could not write the trained ids")
  expect_true(is.character(release$id))
})

test_that("a link to the list is presigned for an S3 store only, and for at most 12 hours", {
  seen <- NULL
  presign <- function(bucket, key, filename, expires, content_type) {
    seen <<- list(bucket = bucket, key = key, filename = filename, expires = expires, type = content_type)
    "https://example.com/signed"
  }
  url <- atlas_trained_ids_link("s3://atlas-bucket/store", "r1", hours = 2, presign = presign)
  expect_equal(url, "https://example.com/signed")
  expect_equal(seen$bucket, "atlas-bucket")
  expect_equal(seen$key, "store/private/trained-ids/draft/releases/r1.tsv.gz")
  expect_equal(seen$expires, 7200L)
  expect_equal(seen$type, "application/gzip")
  expect_error(atlas_trained_ids_link("C:/atlas/store", "r1", presign = presign), "S3")
  expect_error(atlas_trained_ids_link("s3://b/p", "r1", hours = 24, presign = presign), "12")
})

test_that("a release made before lists were kept gets one from its job's pull, with nothing refitted", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  release <- full_cycle(store, boss)
  expected <- trained_list(store, release$id)
  root <- sub("^file://", "", store$uri)
  for (key in store$list(paste0(ATLAS_TRAINED_PREFIX, "/"))) unlink(file.path(root, key))
  expect_false(store$exists(atlas_trained_release_key(release$id)))
  # The box has pulled again since: its own pull no longer matches the
  # models, so the list must come from the job's pull in the store.
  on_machine(boss, orchestrator_data(synthetic_occurrences(c("Taxon A" = 40, "Taxon B" = 41, "Taxon C" = 42))))
  summary <- on_machine(boss, atlas_backfill_trained_ids(store, quiet = TRUE))
  expect_equal(trained_list(store, release$id), expected)
  expect_length(summary$not_found, 0)
})
