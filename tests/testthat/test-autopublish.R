# Drafts that publish themselves (R/autopublish.R): a waiting draft publishes
# once its grace period is over, and only if it reads back as it was made; a
# draft deleted on zenodo.org is marked discarded, one published there by a
# person has its DOI recorded, and text a person added to the published
# version's description stops the next one until a person looks.

DAY <- 86400

# One release, archived as a draft on the fake Zenodo.
draft_one <- function(zen, store, target = "zenodo") {
  computed_data()
  atlas_publish_release(store, quiet = TRUE)
  atlas_archive(store, "draft", "models", z = zen$client(target), cells_now = planted_cells_now(store), quiet = TRUE)
  series <- atlas_archive_series("models", "draft", target)
  ledger <- atlas_archive_ledger(store, series)
  list(series = series, entry = ledger$versions[[length(ledger$versions)]])
}

# A second release with a change, archived as the next version's draft.
draft_next <- function(zen, store) {
  atlas_write_json(list(taxon = "Amanita muscaria", algorithm = "rf", auc_mean = 0.8),
                   atlas_model_path("Amanita muscaria", "draft", ".json", "rf"))
  atlas_publish_release(store, quiet = TRUE)
  atlas_archive(store, "draft", "models", z = zen$client(), cells_now = planted_cells_now(store), quiet = TRUE)
  ledger <- atlas_archive_ledger(store, "models-draft")
  ledger$versions[[length(ledger$versions)]]
}

auto <- function(store, zen, after, target = "zenodo", ...) {
  atlas_archive_auto_publish(store, target, z = zen$client(target), now = Sys.time() + after, quiet = TRUE, ...)
}

published_calls <- function(zen) sum(grepl("actions/publish$", zen$calls))

test_that("a draft publishes itself once its grace period is over, its DOI in the ledger and on the site", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    made <- draft_one(zen, store)
    out <- auto(store, zen, 3 * DAY + 3600)
    expect_equal(out$outcome, "published")
    v <- atlas_archive_ledger(store, "models-draft")$versions[[1]]
    expect_equal(v$state, "published")
    expect_match(v$doi, "^10[.]5072/zenodo[.]")
    expect_equal(zen$records[[as.character(made$entry$deposition_id)]]$state, "published")
    expect_equal(published_calls(zen), 1L)
    # The ledger the site serves says the same.
    served <- jsonlite::fromJSON(atlas_path("archives", "models-draft.json"), simplifyVector = FALSE)
    expect_equal(served$versions[[1]]$doi, v$doi)
    expect_equal(served$concept_doi, atlas_archive_ledger(store, "models-draft")$concept_doi)
    # Run again: nothing left to do, nothing published twice.
    expect_equal(auto(store, zen, 4 * DAY)$outcome, "nothing waiting")
    expect_equal(published_calls(zen), 1L)
  })
})

test_that("a draft inside its grace period is left a draft, and says when it will publish", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    draft_one(zen, store)
    # Three days by default, when nothing sets the grace period.
    with_env(c(ATLAS_ZENODO_PUBLISH_AFTER_DAYS = NA), {
      out <- atlas_archive_auto_publish(store, "zenodo", z = zen$client(), now = Sys.time() + 3 * DAY - 3600, quiet = TRUE)
    })
    expect_equal(out$outcome, "waiting")
    expect_match(out$detail, "publishes itself after .* unless deleted on zenodo.org")
    expect_equal(published_calls(zen), 0L)
    expect_equal(atlas_archive_ledger(store, "models-draft")$versions[[1]]$state, "draft")
    # A longer setting holds it longer.
    expect_equal(auto(store, zen, 5 * DAY, after_days = 7)$outcome, "waiting")
    expect_equal(published_calls(zen), 0L)
  })
})

test_that("with publishing itself off, a draft never publishes, however old", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    draft_one(zen, store)
    out <- auto(store, zen, 365 * DAY, after_days = atlas_archive_publish_after_days("off"))
    expect_equal(out$outcome, "waiting")
    expect_match(out$detail, "publishing itself is off")
    expect_equal(published_calls(zen), 0L)
  })
})

test_that("a draft deleted on zenodo.org is marked discarded, leaves the site's list and blocks nothing", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    made <- draft_one(zen, store)
    zen$records[[as.character(made$entry$deposition_id)]] <- NULL
    out <- auto(store, zen, 10 * DAY)
    expect_equal(out$outcome, "discarded")
    v <- atlas_archive_ledger(store, "models-draft")$versions[[1]]
    expect_equal(v$state, "discarded")
    expect_false(is.null(v$discarded_at))
    expect_equal(published_calls(zen), 0L)
    expect_length(atlas_archive_ledgers()[[1]]$versions, 0)
    # The next archive is not held back by it.
    atlas_archive(store, "draft", "models", z = zen$client(), cells_now = planted_cells_now(store), quiet = TRUE)
    states <- vapply(atlas_archive_ledger(store, "models-draft")$versions, function(v) v$state, character(1))
    expect_equal(states, c("discarded", "draft"))
  })
})

test_that("a deleted-looking draft is not marked discarded when the token cannot see the published record", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    draft_one(zen, store)
    expect_equal(auto(store, zen, 4 * DAY)$outcome, "published")
    second <- draft_next(zen, store)
    # Zenodo answers 404 for everything, as for a token of another account.
    zen$records <- list()
    out <- auto(store, zen, 10 * DAY)
    expect_equal(out$outcome, "failed")
    expect_equal(atlas_archive_ledger(store, "models-draft")$versions[[2]]$state, "draft")
  })
})

test_that("a draft a person published on zenodo.org has its DOI recorded and is not published again", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    made <- draft_one(zen, store)
    id <- as.character(made$entry$deposition_id)
    zen$records[[id]]$state <- "published"
    zen$records[[id]]$doi <- paste0("10.5072/zenodo.", id)
    out <- auto(store, zen, 1 * DAY)
    expect_equal(out$outcome, "published by hand")
    ledger <- atlas_archive_ledger(store, "models-draft")
    expect_equal(ledger$versions[[1]]$state, "published")
    expect_equal(ledger$versions[[1]]$doi, paste0("10.5072/zenodo.", id))
    expect_equal(ledger$versions[[1]]$published_by, "a person, on zenodo.org")
    expect_false(is.null(ledger$concept_doi))
    expect_equal(published_calls(zen), 0L)
  })
})

test_that("a draft that no longer reads back as it was made is refused, however old", {
  changes <- list(
    title = function(r) { r$metadata$title <- "Something else"; r },
    description = function(r) { r$metadata$description <- paste0(r$metadata$description, "<p>Added on Zenodo.</p>"); r },
    label = function(r) { r$metadata$version <- "another-label"; r },
    md5 = function(r) { r$files[[1]]$checksum <- strrep("0", 32); r },
    missing_file = function(r) { r$files <- r$files[-1]; r },
    extra_file = function(r) { r$files[[length(r$files) + 1L]] <- list(id = "fx", filename = "extra.txt", checksum = strrep("1", 32)); r },
    doubled_file = function(r) { r$files[[length(r$files) + 1L]] <- r$files[[1]]; r }
  )
  for (name in names(changes)) {
    with_data_dir({
      store <- new_store()
      zen <- fake_zenodo()
      made <- draft_one(zen, store)
      id <- as.character(made$entry$deposition_id)
      zen$records[[id]] <- changes[[name]](zen$records[[id]])
      out <- auto(store, zen, 30 * DAY)
      expect_equal(out$outcome, "refused", info = name)
      expect_match(out$detail, "not published", info = name)
      expect_equal(published_calls(zen), 0L, info = name)
      expect_equal(atlas_archive_ledger(store, "models-draft")$versions[[1]]$state, "draft", info = name)
      expect_equal(zen$records[[id]]$state, "draft", info = name)
    })
  }
})

test_that("a draft made before the ledger recorded what to check it against is refused", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    draft_one(zen, store)
    ledger <- atlas_archive_ledger(store, "models-draft")
    ledger$versions[[1]]$files <- lapply(ledger$versions[[1]]$files, function(f) f[c("name", "bytes", "sha256")])
    atlas_archive_save_ledger(store, ledger)
    out <- auto(store, zen, 30 * DAY)
    expect_equal(out$outcome, "refused")
    expect_match(out$detail, "archive-publish")
    expect_equal(published_calls(zen), 0L)
  })
})

test_that("text a person added to the published version's description stops the next draft until a person looks", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    first <- draft_one(zen, store)
    expect_equal(auto(store, zen, 4 * DAY)$outcome, "published")
    # As the 76-records paragraph was added to version 23463939 on zenodo.org.
    id <- as.character(first$entry$deposition_id)
    zen$records[[id]]$metadata$description <- sub(
      "</pre>", "\n\nThese counts are after 76 erroneous records were removed.</pre>",
      zen$records[[id]]$metadata$description, fixed = TRUE)
    draft_next(zen, store)
    out <- auto(store, zen, 30 * DAY)
    expect_equal(out$outcome, "refused")
    expect_match(out$detail, "carries into this version")
    expect_equal(published_calls(zen), 1L)
  })
})

test_that("a published version whose generated description the ledger lacks stops the next draft", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    draft_one(zen, store)
    expect_equal(auto(store, zen, 4 * DAY)$outcome, "published")
    # As for 23463939 and 24214060, archived before the ledger recorded it.
    ledger <- atlas_archive_ledger(store, "models-draft")
    ledger$versions[[1]]$description <- NULL
    atlas_archive_save_ledger(store, ledger)
    draft_next(zen, store)
    out <- auto(store, zen, 30 * DAY)
    expect_equal(out$outcome, "refused")
    expect_match(out$detail, "76-records paragraph")
    expect_equal(published_calls(zen), 1L)
  })
})

test_that("the next version publishes itself when the published one's description is as the code wrote it", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    draft_one(zen, store)
    expect_equal(auto(store, zen, 4 * DAY)$outcome, "published")
    draft_next(zen, store)
    out <- auto(store, zen, 30 * DAY)
    expect_equal(out$outcome, "published")
    ledger <- atlas_archive_ledger(store, "models-draft")
    expect_equal(vapply(ledger$versions, function(v) v$state, character(1)), c("published", "published"))
    first <- zen$records[[as.character(ledger$versions[[1]]$deposition_id)]]
    second <- zen$records[[as.character(ledger$versions[[2]]$deposition_id)]]
    expect_equal(first$concept, second$concept)
  })
})

test_that("sandbox ledgers are handled only against the sandbox, the same way", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    made <- draft_one(zen, store, target = "sandbox")
    calls <- length(zen$calls)
    # A real-Zenodo run leaves the sandbox draft alone and calls nobody.
    expect_equal(nrow(auto(store, zen, 30 * DAY)), 0L)
    expect_equal(length(zen$calls), calls)
    # A real-Zenodo client is never used on sandbox ledgers.
    wrong <- atlas_archive_auto_publish(store, "sandbox", z = zen$client("zenodo"), now = Sys.time() + 30 * DAY, quiet = TRUE)
    expect_equal(wrong$outcome, "failed")
    expect_equal(published_calls(zen), 0L)
    expect_equal(auto(store, zen, 1 * DAY, target = "sandbox")$outcome, "waiting")
    out <- auto(store, zen, 4 * DAY, target = "sandbox")
    expect_equal(out$series, "models-draft-sandbox")
    expect_equal(out$outcome, "published")
    expect_equal(atlas_archive_ledger(store, "models-draft-sandbox")$versions[[1]]$state, "published")
    expect_length(atlas_archive_ledger(store, "models-draft")$versions, 0)
  })
})

test_that("with no draft waiting, nothing is asked of Zenodo and no token is needed", {
  with_data_dir({
    store <- new_store()
    zen <- fake_zenodo()
    draft_one(zen, store)
    expect_equal(auto(store, zen, 4 * DAY)$outcome, "published")
    out <- atlas_archive_auto_publish(store, "zenodo", z = function() stop("no token here"), quiet = TRUE)
    expect_equal(out$outcome, "nothing waiting")
  })
})

test_that("the Zenodo token is never written to the output or the ledger", {
  with_data_dir({
    root <- tempfile("store-")
    store <- atlas_local_store(root)
    zen <- fake_zenodo()
    seen <- character()
    keep <- function(m) {
      seen <<- c(seen, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
    run <- function(after) {
      withCallingHandlers(
        atlas_archive_auto_publish(store, "zenodo", z = zen$client(), now = Sys.time() + after, quiet = FALSE),
        message = keep
      )
    }
    made <- draft_one(zen, store)
    out <- rbind(run(1 * DAY), run(4 * DAY))
    # A refusal, and a failure Zenodo answers with an error.
    draft_next(zen, store)
    id <- as.character(atlas_archive_ledger(store, "models-draft")$versions[[2]]$deposition_id)
    zen$records[[id]]$metadata$title <- "changed"
    out <- rbind(out, run(30 * DAY))
    broken <- zen$transport
    zen$transport <- function(...) list(status = 401L, body = list(message = "The server could not verify that you are authorized"))
    out <- rbind(out, run(30 * DAY))
    zen$transport <- broken
    expect_setequal(out$outcome, c("waiting", "published", "refused", "failed"))
    expect_true(all(zen$tokens == "zenodo-secret-token"))
    text <- c(seen, unlist(out), readLines(atlas_path("archives", "models-draft.json"), warn = FALSE),
              unlist(lapply(list.files(root, recursive = TRUE, full.names = TRUE, pattern = "[.]json$"),
                            readLines, warn = FALSE)))
    expect_true(length(seen) >= 4L)
    expect_false(any(grepl("zenodo-secret-token", text, fixed = TRUE)))
  })
})

test_that("the grace period is a number of days, 1 or more, or off", {
  expect_equal(atlas_archive_publish_after_days(""), 3)
  expect_equal(atlas_archive_publish_after_days("5"), 5)
  expect_equal(atlas_archive_publish_after_days("OFF"), Inf)
  expect_error(atlas_archive_publish_after_days("0"), "1 or more")
  expect_error(atlas_archive_publish_after_days("0.5"), "1 or more")
  expect_error(atlas_archive_publish_after_days("soon"), "1 or more")
  with_env(c(ATLAS_ZENODO_PUBLISH_AFTER_DAYS = "4"), expect_equal(atlas_archive_publish_after_days(), 4))
})

test_that("archive-auto-publish fails the run when a draft is refused, so a person looks", {
  with_data_dir({
    store <- tempfile("store-")
    got <- NULL
    local_mocked_bindings(atlas_archive_auto_publish = function(...) {
      got <<- list(...)
      data.frame(series = "models-draft", version = "v", outcome = "refused", detail = "")
    })
    expect_equal(atlas_main(c("archive-auto-publish", paste0("--store=", store), "--after-days=5")), 1L)
    expect_equal(got$after_days, 5)
    expect_equal(got$target, "zenodo")
    atlas_main(c("archive-auto-publish", paste0("--store=", store), "--sandbox"))
    expect_equal(got$target, "sandbox")
  })
})

test_that("archive-auto-publish with nothing archived is a clean run, with no token and no call", {
  with_data_dir({
    empty <- tempfile("store-")
    dir.create(empty)
    with_env(c(ZENODO_TOKEN = NA), {
      expect_equal(atlas_main(c("archive-auto-publish", paste0("--store=", empty))), 0L)
    })
  })
})
