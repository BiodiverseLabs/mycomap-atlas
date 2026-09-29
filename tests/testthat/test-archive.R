# Archives on Zenodo: each release and each layer build becomes a new version
# of its series, with its own DOI under one concept DOI, never twice, and
# never published without being asked.

# A stand-in for Zenodo's deposit API that keeps records in memory. Like the
# real one, a new version may carry the previous version's files (copy_files),
# which the client has to clear.
fake_zenodo <- function(copy_files = TRUE) {
  z <- new.env()
  # Upload failures to stage: name -> how many times to fail. A "stored"
  # failure keeps the file but still answers 502, as a gateway timing out
  # after the server has the bytes does.
  z$fail <- list()
  z$fail_stored <- list()
  z$uploads <- character()
  z$records <- list()
  z$calls <- character()
  z$tokens <- character()
  z$next_id <- 100L
  base <- "https://fake.zenodo/api"
  ok <- function(status, body = NULL) list(status = status, body = body)
  view <- function(r) {
    list(id = r$id, conceptrecid = r$concept, state = r$state, doi = r$doi,
         conceptdoi = if (!is.null(r$doi)) paste0("10.5072/zenodo.", r$concept),
         record_id = r$id, metadata = r$metadata,
         links = list(bucket = paste0(base, "/files/bucket-", r$id),
                      html = paste0("https://fake.zenodo/records/", r$id)))
  }
  new_record <- function(concept = NULL, files = list()) {
    id <- z$next_id
    z$next_id <- z$next_id + 1L
    z$records[[as.character(id)]] <- list(id = id, concept = if (is.null(concept)) id + 5000L else concept, state = "draft",
                                          files = files, metadata = NULL, doi = NULL)
    z$records[[as.character(id)]]
  }
  z$transport <- function(method, url, token, json = NULL, file = NULL) {
    z$tokens <- c(z$tokens, token)
    path <- sub("^https://[^/]+/api", "", url)
    z$calls <- c(z$calls, paste(method, path))
    parts <- strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1]]
    if (method == "POST" && path == "/deposit/depositions") return(ok(201L, view(new_record())))
    if (parts[[1]] == "files") {
      id <- sub("^bucket-", "", parts[[2]])
      r <- z$records[[id]]
      if (r$state != "draft") return(ok(403L, list(message = "published")))
      name <- utils::URLdecode(parts[[3]])
      if ((z$fail[[name]] %||% 0) > 0) {
        z$fail[[name]] <- z$fail[[name]] - 1
        return(ok(502L, list(message = "<html><body>502 Bad Gateway</body></html>")))
      }
      z$uploads <- c(z$uploads, name)
      r$files[[length(r$files) + 1L]] <- list(id = paste0("f", length(r$files) + 1L, "-", id), filename = name,
                                              sha256 = digest::digest(file = file, algo = "sha256"),
                                              checksum = digest::digest(file = file, algo = "md5"))
      z$records[[id]] <- r
      if ((z$fail_stored[[name]] %||% 0) > 0) {
        z$fail_stored[[name]] <- z$fail_stored[[name]] - 1
        return(ok(502L, list(message = "<html><body>502 Bad Gateway</body></html>")))
      }
      return(ok(201L, list(key = name)))
    }
    id <- parts[[3]]
    r <- z$records[[id]]
    if (is.null(r)) return(ok(404L, list(message = "no such deposition")))
    if (length(parts) == 3 && method == "GET") return(ok(200L, c(view(r), list(submitted = r$state == "published"))))
    if (length(parts) == 3 && method == "PUT") {
      r$metadata <- json$metadata
      z$records[[id]] <- r
      return(ok(200L, view(r)))
    }
    if (length(parts) == 3 && method == "DELETE") {
      if (r$state != "draft") return(ok(403L, list(message = "published records cannot be deleted")))
      z$records[[id]] <- NULL
      return(ok(204L))
    }
    if (parts[[4]] == "files" && method == "GET") return(ok(200L, lapply(r$files, function(f) f[c("id", "filename", "checksum")])))
    if (parts[[4]] == "files" && method == "DELETE") {
      r$files <- Filter(function(f) f$id != parts[[5]], r$files)
      z$records[[id]] <- r
      return(ok(204L))
    }
    if (parts[[5]] == "publish") {
      if (is.null(r$metadata$version)) return(ok(400L, list(message = "missing metadata")))
      r$state <- "published"
      r$doi <- paste0("10.5072/zenodo.", r$id)
      z$records[[id]] <- r
      return(ok(202L, view(r)))
    }
    if (parts[[5]] == "newversion") {
      if (r$state != "published") return(ok(400L, list(message = "only a published record gets a new version")))
      draft <- new_record(r$concept, if (copy_files) r$files else list())
      return(ok(201L, list(id = r$id, links = list(latest_draft = paste0(base, "/deposit/depositions/", draft$id)))))
    }
    ok(400L, list(message = paste("unexpected", method, path)))
  }
  z$client <- function(target = "zenodo", waits = c(0, 0, 0)) {
    # No real waiting between retries in tests.
    zen <- atlas_zenodo(target, token = "zenodo-secret-token", transport = z$transport,
                        waits = waits, sleep = function(s) NULL)
    zen
  }
  z
}

with_layers <- function(md5 = "aaa") {
  dir.create(atlas_layer_dir("draft"), recursive = TRUE, showWarnings = FALSE)
  writeLines(paste("stack", md5), file.path(atlas_layer_dir("draft"), "bioclim.tif"))
  atlas_write_json(list(list(id = "bioclim", md5 = md5, built_at = "2026-09-28T10:00:00Z",
                             bands = list("bio1", "bio12"))),
                   file.path(atlas_layer_dir("draft"), "manifest.json"))
}

archive_quietly <- function(...) atlas_archive(..., quiet = TRUE)

test_that("a first archive leaves a draft on Zenodo and publishes nothing", {
  with_data_dir({
    computed_data()
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "models", z = zen$client())
    ledger <- atlas_archive_ledger(store, "models-draft")
    expect_length(ledger$versions, 1)
    expect_equal(ledger$versions[[1]]$state, "draft")
    expect_equal(ledger$versions[[1]]$release, release$id)
    expect_null(ledger$concept_doi)
    expect_false(any(grepl("actions/publish", zen$calls)))
    record <- zen$records[[as.character(ledger$versions[[1]]$deposition_id)]]
    expect_equal(record$state, "draft")
    expect_equal(record$metadata$version, release$id)
  })
})

test_that("publishing mints a version DOI and the concept DOI for every version", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "models", z = zen$client(), publish = TRUE)
    ledger <- atlas_archive_ledger(store, "models-draft")
    v <- ledger$versions[[1]]
    expect_equal(v$state, "published")
    expect_match(v$doi, "^10[.]5072/zenodo[.]")
    expect_match(ledger$concept_doi, "^10[.]5072/zenodo[.]")
    expect_false(identical(v$doi, ledger$concept_doi))
  })
})

test_that("a new release becomes a new version of the same record, with only its own files", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo(copy_files = TRUE)
    archive_quietly(store, "draft", "models", z = zen$client(), publish = TRUE)
    # Something changes, and a new release is made.
    atlas_write_json(list(taxon = "Amanita muscaria", algorithm = "rf", auc_mean = 0.8),
                     atlas_model_path("Amanita muscaria", "draft", ".json", "rf"))
    second <- atlas_publish_release(store, quiet = TRUE)
    archive_quietly(store, "draft", "models", z = zen$client(), publish = TRUE)

    ledger <- atlas_archive_ledger(store, "models-draft")
    expect_length(ledger$versions, 2)
    expect_equal(ledger$versions[[2]]$release, second$id)
    expect_false(identical(ledger$versions[[1]]$doi, ledger$versions[[2]]$doi))
    first_record <- zen$records[[as.character(ledger$versions[[1]]$deposition_id)]]
    second_record <- zen$records[[as.character(ledger$versions[[2]]$deposition_id)]]
    expect_equal(first_record$concept, second_record$concept)
    # The files carried over from version one were cleared, not doubled.
    names <- vapply(second_record$files, function(f) f$filename, character(1))
    expect_false(any(duplicated(names)))
    expect_setequal(names, vapply(ledger$versions[[2]]$files, function(f) f$name, character(1)))
  })
})

test_that("an unchanged release is not archived twice", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "models", z = zen$client(), publish = TRUE)
    calls <- length(zen$calls)
    archive_quietly(store, "draft", "models", z = zen$client(), publish = TRUE)
    expect_equal(length(zen$calls), calls)
    expect_length(atlas_archive_ledger(store, "models-draft")$versions, 1)
  })
})

test_that("a waiting draft blocks the next archive until it is published or discarded", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "models", z = zen$client())
    expect_error(archive_quietly(store, "draft", "models", z = zen$client()), "still a draft")
    atlas_archive_discard(store, "models-draft", zen$client(), quiet = TRUE)
    expect_length(atlas_archive_ledger(store, "models-draft")$versions, 0)
    expect_length(zen$records, 0)
    archive_quietly(store, "draft", "models", z = zen$client())
    atlas_archive_publish(store, "models-draft", zen$client(), quiet = TRUE)
    expect_equal(atlas_archive_ledger(store, "models-draft")$versions[[1]]$state, "published")
  })
})

test_that("the bundle holds maps per model, scores, counts and cells, and nothing private", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    bundle <- atlas_archive_models_bundle(store, "draft")
    expect_setequal(names(bundle$sources), c(
      "maps-maxnet.tar", "maps-rf.tar", "scores.tar.gz", "taxa.json",
      "collection-cells-0.1deg.tsv.gz", "pull.json", "release.json"
    ))
    inside <- utils::untar(bundle$sources[["maps-rf.tar"]], list = TRUE)
    expect_setequal(inside, c("models/draft/rf/amanita-muscaria.tif", "models/draft/rf/amanita-muscaria.png"))
    scores <- utils::untar(bundle$sources[["scores.tar.gz"]], list = TRUE)
    expect_setequal(scores, c("models/draft/amanita-muscaria.json", "models/draft/rf/amanita-muscaria.json"))

    # Unpack everything and look for an exact coordinate or a private file.
    unpacked <- tempfile()
    dir.create(unpacked)
    for (name in names(bundle$sources)) {
      if (grepl("[.]tar", name)) {
        utils::untar(bundle$sources[[name]], exdir = unpacked)
      } else {
        file.copy(bundle$sources[[name]], file.path(unpacked, name))
      }
    }
    all <- list.files(unpacked, recursive = TRUE, full.names = TRUE)
    expect_false(any(grepl("training|raw|occurrences-", all)))
    for (file in all) {
      text <- if (grepl("[.]gz$", file)) readLines(gzfile(file), warn = FALSE) else readLines(file, warn = FALSE)
      for (value in fake_occurrences()$latitude) expect_false(any(grepl(value, text, fixed = TRUE)), info = file)
    }
  })
})

test_that("what is uploaded carries a README and checksums that verify", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "models", z = zen$client())
    version <- atlas_archive_ledger(store, "models-draft")$versions[[1]]
    names <- vapply(version$files, function(f) f$name, character(1))
    expect_true(all(c("README.md", "CHECKSUMS.sha256") %in% names))
    record <- zen$records[[as.character(version$deposition_id)]]
    uploaded <- stats::setNames(vapply(record$files, function(f) f$sha256, character(1)),
                                vapply(record$files, function(f) f$filename, character(1)))
    listed <- stats::setNames(vapply(version$files, function(f) f$sha256, character(1)), names)
    expect_equal(uploaded[names], listed[names])
  })
})

test_that("a models version names the layers version it was fitted on", {
  with_data_dir({
    with_layers("aaa")
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", c("models", "layers"), z = zen$client(), publish = TRUE)
    layers <- atlas_archive_ledger(store, "layers-draft")
    models <- atlas_archive_ledger(store, "models-draft")
    expect_equal(models$versions[[1]]$layers_version, layers$versions[[1]]$version)
    metadata <- zen$records[[as.character(models$versions[[1]]$deposition_id)]]$metadata
    derived <- Filter(function(r) identical(r$relation, "isDerivedFrom"), metadata$related_identifiers)
    expect_true(layers$versions[[1]]$doi %in% vapply(derived, function(r) r$identifier, character(1)))
  })
})

test_that("layers get a new version only when a layer is rebuilt", {
  with_data_dir({
    with_layers("aaa")
    computed_data()
    store <- new_store()
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "layers", z = zen$client(), publish = TRUE)
    archive_quietly(store, "draft", "layers", z = zen$client(), publish = TRUE)
    expect_length(atlas_archive_ledger(store, "layers-draft")$versions, 1)
    with_layers("bbb")
    archive_quietly(store, "draft", "layers", z = zen$client(), publish = TRUE)
    ledger <- atlas_archive_ledger(store, "layers-draft")
    expect_length(ledger$versions, 2)
    expect_false(identical(ledger$versions[[1]]$version, ledger$versions[[2]]$version))
  })
})

test_that("sandbox archives keep their own ledger and never touch real DOIs", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "models", z = zen$client("sandbox"), publish = TRUE)
    expect_length(atlas_archive_ledger(store, "models-draft-sandbox")$versions, 1)
    expect_length(atlas_archive_ledger(store, "models-draft")$versions, 0)
  })
})

test_that("a dry run builds the bundle but calls nobody and records nothing", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    offline <- list(target = "zenodo", base = "", call = function(...) stop("no calls in a dry run"))
    expect_silent(atlas_archive(store, "draft", "models", z = offline, dry_run = TRUE, quiet = TRUE))
    expect_length(atlas_archive_ledger(store, "models-draft")$versions, 0)
  })
})

test_that("the Zenodo token is sent in the header and never written down", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    archive_quietly(store, "draft", "models", z = zen$client(), publish = TRUE)
    expect_true(all(zen$tokens == "zenodo-secret-token"))
    ledger_text <- readLines(atlas_path("archives", "models-draft.json"))
    expect_false(any(grepl("zenodo-secret-token", ledger_text, fixed = TRUE)))
  })
  with_env(c(ZENODO_TOKEN = NA), expect_error(atlas_zenodo(), "ZENODO_TOKEN"))
})

test_that("a pull brings the ledgers, so the API can list the downloads", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    archive_quietly(store, "draft", "models", z = fake_zenodo()$client(), publish = TRUE)
    doi <- atlas_archive_ledger(store, "models-draft")$versions[[1]]$doi
    with_data_dir({
      atlas_pull_release(store, quiet = TRUE)
      ledgers <- atlas_archive_ledgers()
      expect_length(ledgers, 1)
      expect_equal(ledgers[[1]]$versions[[1]]$doi, doi)
    })
  })
})

test_that("a bundle Zenodo would refuse is refused before anything is uploaded", {
  expect_error(atlas_archive_check_size(data.frame(name = paste0("f", 1:101), bytes = 1)), "100 per record")
  expect_error(atlas_archive_check_size(data.frame(name = "big", bytes = 51 * 1024^3)), "50 GB")
  expect_silent(atlas_archive_check_size(data.frame(name = "ok", bytes = 1024)))
})

test_that("Zenodo's refusals are reported with its reasons", {
  refuse <- function(method, url, token, json, file) {
    list(status = 400L, body = list(message = "Validation error.",
                                    errors = list(list(field = "metadata.creators", messages = list("Required.")))))
  }
  zen <- atlas_zenodo("sandbox", token = "t", transport = refuse)
  expect_error(atlas_zenodo_create(zen), "400.*metadata.creators: Required")
})

test_that("the metadata template has everything Zenodo requires", {
  template <- atlas_archive_template(testthat::test_path("..", ".."))
  for (kind in ATLAS_ARCHIVE_KINDS) {
    bundle <- list(kind = kind, grid = "production", version = "v1")
    metadata <- atlas_archive_metadata(bundle, c("# t", "body"), template, today = as.Date("2026-09-29"))
    for (field in c("upload_type", "title", "creators", "description", "access_right", "license", "version")) {
      expect_false(is.null(metadata[[field]]), label = paste(kind, field))
    }
    expect_match(metadata$title, "production")
    expect_equal(metadata$publication_date, "2026-09-29")
  }
})

test_that("a person is credited as Family, Given, as Zenodo cites them", {
  template <- atlas_archive_template(testthat::test_path("..", ".."))
  names <- vapply(template$common$creators, function(c) c$name, character(1))
  expect_equal(names[[1]], "Russell, Stephen D.")
  # Anything that is not an organisation must carry the comma Zenodo splits on.
  people <- names[!grepl("[.](org|com)$", names)]
  expect_true(all(grepl("^[^,]+, [^,]+$", people)))
})

# ORCID's own check digit (ISO 7064 11,2), so a mistyped iD fails here, not on Zenodo.
orcid_valid <- function(id) {
  digits <- gsub("-", "", id)
  if (!grepl("^[0-9]{15}[0-9X]$", digits)) return(FALSE)
  total <- 0
  for (d in as.integer(strsplit(substr(digits, 1, 15), "")[[1]])) total <- (total + d) * 2
  check <- (12 - total %% 11) %% 11
  identical(substr(digits, 16, 16), if (check == 10) "X" else as.character(check))
}

test_that("every creator's ORCID is well formed and passes its check digit", {
  template <- atlas_archive_template(testthat::test_path("..", ".."))
  orcids <- unlist(lapply(template$common$creators, function(c) c$orcid))
  expect_true(length(orcids) >= 1)
  for (id in orcids) expect_true(orcid_valid(id), label = id)
  expect_false(orcid_valid("0000-0001-7191-2452"))
})

test_that("a gateway error during an upload is retried, and the archive completes", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    zen$fail[["maps-rf.tar"]] <- 2
    expect_message(archive_quietly(store, "draft", "models", z = zen$client()), "trying again")
    version <- atlas_archive_ledger(store, "models-draft")$versions[[1]]
    expect_equal(version$state, "draft")
    record <- zen$records[[as.character(version$deposition_id)]]
    expect_true("maps-rf.tar" %in% vapply(record$files, function(f) f$filename, character(1)))
  })
})

test_that("a run that dies part way leaves its draft in the ledger, and the next run carries on in it", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    zen$fail[["maps-rf.tar"]] <- 10
    expect_error(suppressMessages(archive_quietly(store, "draft", "models", z = zen$client())), "gateway failed")
    ledger <- atlas_archive_ledger(store, "models-draft")
    expect_equal(ledger$versions[[1]]$state, "uploading")
    first_draft <- ledger$versions[[1]]$deposition_id
    uploaded_before <- zen$uploads

    zen$fail[["maps-rf.tar"]] <- 0
    archive_quietly(store, "draft", "models", z = zen$client())
    ledger <- atlas_archive_ledger(store, "models-draft")
    expect_length(ledger$versions, 1)
    expect_equal(ledger$versions[[1]]$deposition_id, first_draft)
    expect_equal(ledger$versions[[1]]$state, "draft")
    expect_length(zen$records, 1)
    # Files that made it the first time were not uploaded again.
    again <- zen$uploads[-seq_along(uploaded_before)]
    expect_false(any(uploaded_before %in% again))
  })
})

test_that("a file the server kept despite answering 502 is not uploaded twice", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    zen$fail_stored[["maps-rf.tar"]] <- 10
    expect_error(suppressMessages(archive_quietly(store, "draft", "models", z = zen$client(waits = numeric()))))
    zen$fail_stored[["maps-rf.tar"]] <- 0
    archive_quietly(store, "draft", "models", z = zen$client())
    expect_equal(sum(zen$uploads == "maps-rf.tar"), 1)
    record <- zen$records[[as.character(atlas_archive_ledger(store, "models-draft")$versions[[1]]$deposition_id)]]
    names <- vapply(record$files, function(f) f$filename, character(1))
    expect_false(any(duplicated(names)))
  })
})

test_that("creating or publishing a record is never retried blindly", {
  calls <- 0
  flaky <- function(method, url, token, json, file) {
    calls <<- calls + 1
    list(status = 502L, body = list(message = "<html>502</html>"))
  }
  zen <- atlas_zenodo("sandbox", token = "t", transport = flaky, waits = c(0, 0, 0), sleep = function(s) NULL)
  expect_error(atlas_zenodo_create(zen), "gateway failed")
  expect_equal(calls, 1)
  expect_error(zen$call("GET", "/deposit/depositions"), "gateway failed")
  expect_equal(calls, 1 + 4)
})

test_that("a draft Zenodo holds but the ledger lost can be adopted with --resume-draft", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    zen <- fake_zenodo()
    orphan <- atlas_zenodo_create(zen$client())
    archive_quietly(store, "draft", "models", z = zen$client(), resume_draft = orphan$id)
    expect_length(zen$records, 1)
    expect_equal(atlas_archive_ledger(store, "models-draft")$versions[[1]]$deposition_id, orphan$id)
  })
})

test_that("the same release always packs to the same bytes", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    first <- atlas_archive_models_bundle(store, "draft")
    Sys.sleep(1.1)
    second <- atlas_archive_models_bundle(store, "draft")
    hashes <- function(b) vapply(b$sources, atlas_sha256, character(1))
    expect_equal(hashes(first), hashes(second))
  })
})
