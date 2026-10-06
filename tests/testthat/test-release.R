# Releases: publish what was computed, pull it anywhere, roll back by pointer.

published_paths <- function(release) vapply(release$files, function(f) f$path, character(1))

test_that("a release carries models, maps, counts and public cells, and nothing else", {
  with_data_dir({
    computed_data()
    release <- atlas_publish_release(new_store(), quiet = TRUE)
    paths <- published_paths(release)
    expect_true(all(c("models/draft/amanita-muscaria.json", "models/draft/rf/amanita-muscaria.png",
                      "occurrences/taxa-latest.json", "public/cells.tsv.gz",
                      "public/pull.json") %in% paths))
    # The pull, the training tables and the raw pages never go in.
    expect_false(any(grepl("occurrences-.*tsv[.]gz|^training/|^raw/|occurrences/latest[.]json", paths)))
    expect_equal(release$models$maxnet, 1)
    expect_equal(release$models$rf, 1)
  })
})

test_that("no exact coordinate reaches a published file", {
  with_data_dir({
    computed_data()
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    exact <- fake_occurrences()$latitude
    for (entry in release$files) {
      file <- tempfile()
      store$get(paste0("objects/", substr(entry$sha256, 1, 2), "/", entry$sha256), file)
      text <- if (grepl("[.]gz$", entry$path)) readLines(gzfile(file)) else readLines(file, warn = FALSE)
      for (value in exact) expect_false(any(grepl(value, text, fixed = TRUE)), info = entry$path)
    }
    cells <- atlas_public_cells_table(fake_occurrences())
    expect_true(all(abs((cells$lat * 10) %% 1 - 0.5) < 1e-9))
  })
})

test_that("the published pull summary drops the SQL and the host; the pull's own manifest keeps them", {
  with_data_dir({
    computed_data()
    atlas_publish_release(new_store(), quiet = TRUE)
    published <- jsonlite::fromJSON(atlas_public_pull_path())
    expect_null(published$sql)
    expect_null(published$host)
    expect_equal(published$records, 3)
    expect_equal(atlas_read_manifest()$host, "mycomap-sql")
  })
})

test_that("a publish with nothing changed is skipped", {
  with_data_dir({
    computed_data()
    store <- new_store()
    first <- atlas_publish_release(store, quiet = TRUE)
    Sys.sleep(1.1) # a later publish would get a new id if it were not skipped
    again <- atlas_publish_release(store, quiet = TRUE)
    expect_equal(again$id, first$id)
    expect_length(atlas_list_releases(store), 1L)
  })
})

test_that("a changed model uploads only its own file, and the release remembers the last", {
  with_data_dir({
    computed_data()
    store <- new_store()
    first <- atlas_publish_release(store, quiet = TRUE)
    objects_before <- length(store$list("objects/"))
    writeLines("a better map", atlas_model_path("Amanita muscaria", "draft", ".png", "rf"))
    second <- atlas_publish_release(store, quiet = TRUE)
    expect_equal(length(store$list("objects/")) - objects_before, 1L)
    expect_equal(second$previous, first$id)
    expect_equal(atlas_current_release(store)$id, second$id)
  })
})

test_that("a pull reproduces the release exactly, and a second pull fetches nothing", {
  store <- new_store()
  release <- with_data_dir({
    computed_data()
    atlas_publish_release(store, quiet = TRUE)
  })
  with_data_dir({
    first <- atlas_pull_release(store, quiet = TRUE)
    expect_equal(first$fetched, length(release$files))
    for (entry in release$files) {
      expect_equal(atlas_sha256(file.path(atlas_data_dir(), entry$path)), entry$sha256)
    }
    expect_equal(jsonlite::fromJSON(atlas_path("releases", "draft", "pulled.json"))$release, release$id)
    expect_equal(atlas_pull_release(store, quiet = TRUE)$fetched, 0L)
  })
})

test_that("a pulled release says what to cite and which records it was built from", {
  store <- new_store()
  release <- with_data_dir({
    computed_data()
    atlas_publish_release(store, quiet = TRUE)
  })
  with_data_dir({
    atlas_pull_release(store, quiet = TRUE)
    status <- atlas_status_release()
    expect_equal(status$id, release$id)
    expect_equal(status$createdAt, release$created_at)
    expect_equal(status$grid, "draft")
    if (!is.null(release$pull$pulled_at)) expect_equal(status$dataPulledAt, release$pull$pulled_at)
    if (!is.null(release$pull$records)) expect_equal(status$records, release$pull$records)
    # Through the API: status carries the release beside the newest pull.
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      body <- jsonlite::fromJSON(call_api(api, "/api/status")$body)
      expect_equal(body$release$id, release$id)
    })
  })
  # Nothing pulled: nothing to cite.
  with_data_dir(expect_null(atlas_status_release()))
})

test_that("a pull removes local models the release does not have, unless told to keep them", {
  store <- new_store()
  with_data_dir({
    computed_data()
    atlas_publish_release(store, quiet = TRUE)
  })
  with_data_dir({
    dir.create(atlas_model_dir("draft", "xgboost"), recursive = TRUE)
    stray <- atlas_model_path("Old taxon", "draft", ".json", "xgboost")
    writeLines("{}", stray)
    atlas_pull_release(store, keep_local = TRUE, quiet = TRUE)
    expect_true(file.exists(stray))
    expect_equal(atlas_pull_release(store, quiet = TRUE)$removed, 1L)
    expect_false(file.exists(stray))
  })
})

test_that("a damaged object is refused and the file already there is left alone", {
  store <- new_store()
  release <- with_data_dir({
    computed_data()
    atlas_publish_release(store, quiet = TRUE)
  })
  entry <- Filter(function(e) e$path == "models/draft/amanita-muscaria.png", release$files)[[1]]
  damaged <- tempfile()
  writeLines("tampered", damaged)
  store$put(paste0("objects/", substr(entry$sha256, 1, 2), "/", entry$sha256), damaged)
  with_data_dir({
    dest <- file.path(atlas_data_dir(), entry$path)
    dir.create(dirname(dest), recursive = TRUE)
    writeLines("what was here", dest)
    expect_error(atlas_pull_release(store, quiet = TRUE), "does not match its hash")
    expect_equal(readLines(dest), "what was here")
  })
})

test_that("rolling back is promoting an older release, and pulls follow it", {
  store <- new_store()
  ids <- with_data_dir({
    computed_data()
    first <- atlas_publish_release(store, quiet = TRUE)$id
    writeLines("newer map", atlas_model_path("Amanita muscaria", "draft", ".png", "rf"))
    c(first, atlas_publish_release(store, quiet = TRUE)$id)
  })
  atlas_promote_release(store, ids[[1]], quiet = TRUE)
  expect_equal(atlas_current_release(store)$id, ids[[1]])
  with_data_dir({
    atlas_pull_release(store, quiet = TRUE)
    expect_equal(readLines(atlas_model_path("Amanita muscaria", "draft", ".png", "rf")), "map rf")
  })
  expect_error(atlas_promote_release(store, "no-such-release", quiet = TRUE), "no release")
})

# An S3 client that keeps objects in memory and pages its listings two at a
# time, so pagination is exercised too.
fake_s3_client <- function() {
  objects <- new.env()
  list(
    put_object = function(Bucket, Key, Body) assign(paste(Bucket, Key), Body, envir = objects),
    get_object = function(Bucket, Key) {
      k <- paste(Bucket, Key)
      if (!exists(k, envir = objects, inherits = FALSE)) stop("NoSuchKey")
      list(Body = get(k, envir = objects))
    },
    head_object = function(Bucket, Key) {
      if (!exists(paste(Bucket, Key), envir = objects, inherits = FALSE)) stop("404")
      list()
    },
    list_objects_v2 = function(Bucket, Prefix, ContinuationToken = NULL) {
      keys <- sort(sub(paste0("^", Bucket, " "), "", ls(objects)))
      keys <- keys[startsWith(keys, Prefix)]
      start <- if (is.null(ContinuationToken)) 1L else as.integer(ContinuationToken)
      page <- keys[seq_len(length(keys))[seq_len(length(keys)) >= start]][seq_len(min(2L, max(0L, length(keys) - start + 1L)))]
      more <- start + 2L <= length(keys)
      list(Contents = lapply(page, function(k) list(Key = k)), IsTruncated = more,
           NextContinuationToken = if (more) as.character(start + 2L) else NULL)
    }
  )
}

test_that("the same release works through an S3 store", {
  store <- atlas_s3_store("atlas-bucket", "atlas", client = fake_s3_client())
  release <- with_data_dir({
    computed_data()
    atlas_publish_release(store, quiet = TRUE)
  })
  # Listing pages through more than two objects.
  expect_equal(length(store$list("objects/")), length(unique(vapply(release$files, function(f) f$sha256, ""))))
  with_data_dir({
    atlas_pull_release(store, quiet = TRUE)
    expect_equal(readLines(atlas_model_path("Amanita muscaria", "draft", ".png", "rf")), "map rf")
  })
})

test_that("a store is named by URI", {
  expect_match(atlas_store(file.path(tempdir(), "s"))$uri, "^file://")
  expect_error(atlas_store(""), "no store given")
})

test_that("a machine holding only a release still answers for cells and status", {
  store <- new_store()
  from_pull <- with_data_dir({
    computed_data()
    atlas_publish_release(store, quiet = TRUE)
    atlas_taxon_cells("Amanita muscaria", occurrences = atlas_read_occurrences())
  })
  with_data_dir({
    atlas_pull_release(store, quiet = TRUE)
    expect_error(atlas_read_occurrences(), "nothing pulled")
    expect_equal(atlas_status_manifest()$records, 3)
    from_release <- atlas_taxon_cells("Amanita muscaria", public = atlas_read_public_cells())
    expect_equal(from_release[order(from_release$lat), ], from_pull[order(from_pull$lat), ],
                 ignore_attr = TRUE)
  })
})

test_that("a change to the model index alone is still a change", {
  with_data_dir({
    computed_data()
    store <- new_store()
    first <- atlas_publish_release(store, quiet = TRUE)
    # A batch refused a taxon: no file changed, but the index did.
    atlas_write_json(list(settings_key = "k", taxa = list(list(taxon = "Sparse one", status = "refused",
                                                                fingerprint = "fp", presences = 12))),
                     atlas_path("batches", "draft", "latest.json"))
    Sys.sleep(1.1)
    second <- atlas_publish_release(store, quiet = TRUE)
    expect_false(identical(second$id, first$id))
    expect_true(any(vapply(second$index, function(e) isTRUE(e$refused), logical(1))))
  })
})
