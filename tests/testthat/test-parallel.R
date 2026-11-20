# Work spread over a pool of processes (R/parallel.R): the same results, in
# the same order, as one process gives; and the finish's pull leaving out what
# it never reads.

test_that("a function of the package runs over a list in other processes, by name, in the list's order", {
  files <- vapply(1:6, function(i) {
    f <- tempfile(fileext = ".txt")
    writeLines(sprintf("item %d", i), f)
    f
  }, "")
  serial <- atlas_parallel_map(files, "atlas_sha256", workers = 1L)
  pooled <- atlas_parallel_map(files, "atlas_sha256", workers = 2L, chunk = 2L)
  expect_identical(pooled, serial)
  expect_identical(unlist(serial), unname(vapply(files, atlas_sha256, "")))
  expect_error(atlas_parallel_map(files, atlas_sha256, workers = 2L))
})

test_that("the exports use one process for a few maps, else ATLAS_EXPORT_WORKERS, never more than the cores", {
  cores <- parallel::detectCores()
  expect_equal(atlas_export_workers(ATLAS_EXPORT_PARALLEL_MIN - 1L), 1L)
  with_env(c(ATLAS_EXPORT_WORKERS = "3"), expect_equal(atlas_export_workers(500), min(3L, cores)))
  with_env(c(ATLAS_EXPORT_WORKERS = "none"), expect_equal(atlas_export_workers(500), 1L))
})

test_that("the weak maps' ranks are the same file built across processes as in one", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    sides <- c("east", "west", "east", "west", "east")
    for (i in seq_along(sides)) {
      name <- sprintf("Faint %d", i)
      write_model(name, "rf", here_raster(sides[[i]]))
      metrics <- jsonlite::fromJSON(atlas_model_path(name, "draft", ".json", "rf"), simplifyVector = FALSE)
      metrics$grade <- "weak"
      atlas_write_json(metrics, atlas_model_path(name, "draft", ".json", "rf"))
    }
    path <- atlas_weak_ranks_path("draft")
    one <- atlas_build_weak_ranks("draft", quiet = TRUE, workers = 1L)
    serial <- atlas_sha256(path)
    pooled <- atlas_build_weak_ranks("draft", quiet = TRUE, workers = 2L)
    expect_identical(atlas_sha256(path), serial)
    expect_identical(pooled, one)
    expect_equal(length(unique(one$taxon)), length(sides))
  })
})

test_that("the continent export is the same files built across processes as in one", {
  testthat::skip_if_not_installed("terra")
  with_data_dir({
    fit <- map_fit(list("Taxon B" = "strong", "Taxon C" = "strong", "Taxon D" = "strong", "Taxon W" = "weak"))
    for (algorithm in c("maxnet", "rf")) fit("Taxon B", "f", algorithm = algorithm, full = TRUE)
    fit("Taxon C", "f", algorithm = "rf", full = TRUE)
    fit("Taxon D", "f", algorithm = "maxnet", full = TRUE)
    fit("Taxon W", "f", algorithm = "rf", full = TRUE)
    files <- file.path(atlas_continent_dir("draft"), ATLAS_CONTINENT_FILES)
    hashes <- function() vapply(files, function(f) if (file.exists(f)) atlas_sha256(f) else NA_character_, "")
    one <- atlas_build_continent("draft", quiet = TRUE, workers = 1L)
    serial <- hashes()
    pooled <- atlas_build_continent("draft", quiet = TRUE, workers = 2L)
    expect_identical(hashes(), serial)
    expect_true(any(!is.na(serial)))
    expect_identical(pooled$table, one$table)
    expect_identical(pooled$taxa, one$taxa)
    expect_equal(one$taxa$name, c("Taxon B", "Taxon C", "Taxon D"))
  })
})

test_that("the finish's pull leaves out the full-view rasters of maps that are not strong, and nothing else", {
  with_data_dir({
    store <- new_store()
    files <- list()
    add <- function(taxon, algorithm, extensions) {
      for (path in atlas_model_relpaths(taxon, "draft", algorithm, extensions)) {
        src <- tempfile()
        writeLines(path, src)
        sha <- atlas_sha256(src)
        store$put(atlas_object_key(sha), src)
        files[[length(files) + 1L]] <<- list(path = path, sha256 = sha, bytes = file.info(src)$size)
      }
    }
    every <- c(".json", ".tif", ".di.tif", ".png", ATLAS_FULL_EXTS)
    add("Strong one", "maxnet", every)
    add("Weak one", "rf", every)
    manifest <- list(id = "r1", files = files, index = list(
      list(taxon = "Strong one", algorithm = "maxnet", grade = "strong"),
      list(taxon = "Weak one", algorithm = "rf", grade = "weak")
    ))
    store$put("releases/draft/r1.json", {
      f <- tempfile(fileext = ".json")
      atlas_write_json(manifest, f)
      f
    })
    here <- function(taxon, algorithm, extensions) {
      file.exists(file.path(atlas_data_dir(), atlas_model_relpaths(taxon, "draft", algorithm, extensions)))
    }
    atlas_pull_release(store, "draft", release = "r1", keep_local = TRUE, quiet = TRUE, full_rasters = "strong")
    expect_true(all(here("Strong one", "maxnet", every)))
    expect_true(all(here("Weak one", "rf", c(".json", ".tif", ".di.tif", ".png", ".full.png"))))
    expect_false(any(here("Weak one", "rf", c(".full.tif", ".full.di.tif"))))
    # Any other pull takes everything, as before.
    atlas_pull_release(store, "draft", release = "r1", keep_local = TRUE, quiet = TRUE)
    expect_true(all(here("Weak one", "rf", every)))
    expect_setequal(atlas_release_strong_full_rasters(manifest),
                    atlas_model_relpaths("Strong one", "draft", "maxnet", c(".full.tif", ".full.di.tif")))
  })
})

test_that("finishing a release pulls it without the full-view rasters of maps that are not strong", {
  with_data_dir({
    store <- new_store()
    store$put("releases/draft/r1.json", {
      f <- tempfile(fileext = ".json")
      atlas_write_json(list(id = "r1", files = list(), index = list()), f)
      f
    })
    asked <- NULL
    testthat::local_mocked_bindings(atlas_pull_release = function(...) {
      asked <<- list(...)
      stop("stop here")
    })
    expect_error(atlas_finish_release_work(store, "r1", quiet = TRUE), "stop here")
    expect_equal(asked$full_rasters, "strong")
    expect_true(isTRUE(asked$rasters))
  })
})
