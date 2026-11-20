# Fetching a job's or a release's files from the store (R/jobs.R
# atlas_fetch_entries): the same checks one at a time and in parallel.

# A local store holding n small files, and the entries naming them.
fetch_fixture <- function(n, root = tempfile("fetch-store-")) {
  store <- atlas_local_store(root)
  src <- tempfile("fetch-src-")
  dir.create(src)
  entries <- lapply(seq_len(n), function(i) {
    file <- file.path(src, sprintf("f%04d.txt", i))
    writeLines(sprintf("file %d of %d", i, n), file)
    sha <- atlas_sha256(file)
    store$put(atlas_object_key(sha), file)
    list(path = sprintf("models/draft/maxnet/t%04d.json", i), sha256 = sha, bytes = file.info(file)$size)
  })
  list(store = store, entries = entries)
}

fetched_paths <- function(entries) {
  file.path(atlas_data_dir(), vapply(entries, function(e) e$path, ""))
}

test_that("a short list is fetched one at a time, checked, and a file already here is kept", {
  with_data_dir({
    fx <- fetch_fixture(5)
    got <- atlas_fetch_entries(fx$store, fx$entries, workers = 4L)
    expect_equal(got$fetched, 5L)
    expect_true(all(file.exists(fetched_paths(fx$entries))))
    expect_equal(atlas_fetch_entries(fx$store, fx$entries, workers = 4L)$fetched, 0L)
    # A stale copy is replaced.
    writeLines("stale", fetched_paths(fx$entries)[[2]])
    expect_equal(atlas_fetch_entries(fx$store, fx$entries)$fetched, 1L)
    expect_identical(atlas_sha256(fetched_paths(fx$entries)[[2]]), fx$entries[[2]]$sha256)
  })
})

test_that("a store copy that does not match its hash replaces nothing and stops the fetch, naming the file", {
  with_data_dir({
    fx <- fetch_fixture(3)
    atlas_fetch_entries(fx$store, fx$entries)
    bad <- fx$entries[[3]]
    dest <- fetched_paths(list(bad))
    writeLines("what was here", dest)
    # The store's object for that hash now holds other bytes.
    writeLines("corrupted", file.path(sub("^file://", "", fx$store$uri), atlas_object_key(bad$sha256)))
    expect_error(atlas_fetch_entries(fx$store, fx$entries), "t0003.json does not match its hash; nothing replaced")
    expect_equal(readLines(dest), "what was here")
    expect_false(file.exists(paste0(dest, ".part")))
  })
})

test_that("a long list is fetched by several processes, with the same files and the same checks", {
  with_data_dir({
    n <- ATLAS_FETCH_PARALLEL_MIN + 50L
    fx <- fetch_fixture(n)
    got <- atlas_fetch_entries(fx$store, fx$entries, workers = 2L)
    expect_equal(got$fetched, n)
    expect_equal(got$bytes, sum(vapply(fx$entries, function(e) e$bytes, 0)))
    paths <- fetched_paths(fx$entries)
    expect_true(all(file.exists(paths)))
    expect_identical(unname(vapply(paths, atlas_sha256, "")), vapply(fx$entries, function(e) e$sha256, ""))
    expect_false(any(file.exists(paste0(paths, ".part"))))
    # Run again: everything is already here.
    expect_equal(atlas_fetch_entries(fx$store, fx$entries, workers = 2L)$fetched, 0L)
    # One bad copy among many: it alone is refused, the rest are fetched.
    unlink(paths)
    bad <- fx$entries[[100]]
    writeLines("corrupted", file.path(sub("^file://", "", fx$store$uri), atlas_object_key(bad$sha256)))
    expect_error(atlas_fetch_entries(fx$store, fx$entries, workers = 2L), "t0100.json does not match its hash")
    expect_false(file.exists(paths[[100]]))
    expect_equal(sum(file.exists(paths)), n - 1L)
  })
})

test_that("a file the store cannot give stops the fetch with its name", {
  with_data_dir({
    fx <- fetch_fixture(2)
    missing <- list(path = "models/draft/maxnet/gone.json", sha256 = strrep("0", 64), bytes = 1)
    expect_error(atlas_fetch_entries(fx$store, c(fx$entries, list(missing))), "could not fetch models/draft/maxnet/gone.json")
  })
})

test_that("how many processes fetch: ATLAS_FETCH_WORKERS, else 16, never more than the cores", {
  cores <- parallel::detectCores()
  with_env(c(ATLAS_FETCH_WORKERS = "3"), expect_equal(atlas_fetch_workers(), min(3L, cores)))
  with_env(c(ATLAS_FETCH_WORKERS = "zero"), expect_equal(atlas_fetch_workers(), 1L))
  old <- Sys.getenv("ATLAS_FETCH_WORKERS", unset = NA)
  Sys.unsetenv("ATLAS_FETCH_WORKERS")
  on.exit(if (!is.na(old)) Sys.setenv(ATLAS_FETCH_WORKERS = old), add = TRUE)
  expect_equal(atlas_fetch_workers(), min(16L, cores))
})
