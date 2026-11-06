# The rule (R/fingerprint.R, Steve 2026-11-05): neither a taxon's fingerprint nor a
# model's seed is public. The refits read both from the release's own files, which
# do not change.

PLANTED <- paste(rep("ab12", 16), collapse = "")
PLANTED_SEED <- atlas_seed_from_fingerprint(PLANTED)

# One taxon with a model, an ensemble and a benchmark, each carrying what must
# not get out.
with_planted_hashes <- function(code) {
  with_data_dir({
    computed_data()
    name <- "Amanita muscaria"
    atlas_write_json(data.frame(scientific_name = name, records = 3L, localities = 1L, fingerprint = PLANTED),
                     atlas_path("occurrences", "taxa-latest.json"))
    for (algorithm in c("maxnet", "rf")) {
      atlas_write_json(list(taxon = name, algorithm = algorithm, auc_mean = 0.7, grade = "strong", skill = "passed",
                            seed = PLANTED_SEED, fingerprint = PLANTED, settings_key = "keep me",
                            null = list(reps = 25L, seed = PLANTED_SEED)),
                       atlas_model_path(name, "draft", ".json", algorithm))
    }
    atlas_write_json(list(taxon = name, members = list(list(algorithm = "rf", fingerprint = PLANTED))),
                     atlas_ensemble_path(name, "draft", ".json"))
    atlas_write_json(list(taxa = list(list(taxon = name, fingerprint = PLANTED)), seed = PLANTED_SEED),
                     atlas_path("benchmarks", "draft", "models-20260101T000000Z.json", create = TRUE))
    force(code)
  })
}

planted_api <- function() test_api(c(ATLAS_DATA_DIR = atlas_data_dir(), ATLAS_PUBLIC_ORIGIN = "https://atlas.example.org"))

# An API answer's text: the hash, its seed, or a field named for either.
carries_private <- function(text) {
  grepl(PLANTED, text, fixed = TRUE) || grepl(as.character(PLANTED_SEED), text, fixed = TRUE) ||
    grepl('"seed"\\s*:', text) || grepl('"fingerprint"\\s*:', text)
}

answer_of <- function(api, path, ...) jsonlite::fromJSON(call_api(api, path, ...)$body, simplifyVector = FALSE)

# ---- what anyone can read ---------------------------------------------------

test_that("no API answer about a taxon carries its fingerprint or seed", {
  with_planted_hashes({
    api <- planted_api()
    name <- "Amanita%20muscaria"
    paths <- c("/api/taxa", paste0("/api/taxa/", name), paste0("/api/taxa/", name, "/model"),
               paste0("/api/taxa/", name, "/ensemble"), paste0("/api/taxa/", name, "/best-map"),
               "/api/models", "/api/benchmarks/latest")
    for (path in paths) {
      answer <- call_api(api, path)
      expect_equal(answer$status, 200L, info = path)
      expect_false(carries_private(answer$body), info = path)
    }
    answer <- call_api(api, paste0("/api/taxa/", name, "/model"), query = "algorithm=rf")
    expect_equal(answer$status, 200L)
    expect_false(carries_private(answer$body))
  })
})

test_that("the taxon table's other columns and the model's other fields are all still there", {
  with_planted_hashes({
    api <- planted_api()
    item <- answer_of(api, "/api/taxa")$items[[1]]
    expect_setequal(names(item), c("scientific_name", "records", "localities"))
    model <- answer_of(api, "/api/taxa/Amanita%20muscaria/model")
    expect_equal(model$settings_key, "keep me")
    expect_equal(model$null$reps, 25L)
  })
})

test_that("the pull's own fingerprint stays public, as what a result cites", {
  with_planted_hashes({
    status <- answer_of(planted_api(), "/api/status")
    expect_equal(status$fingerprint, "abc")
  })
})

test_that("the API's description promises neither field, and the web app does not ask for it", {
  spec <- jsonlite::fromJSON(system.file("api", "openapi.json", package = "mycomapatlas"), simplifyVector = FALSE)
  for (schema in c("Taxon", "Model")) {
    fields <- c(names(spec$components$schemas[[schema]]$properties),
                unlist(spec$components$schemas[[schema]]$required))
    expect_false(any(c("fingerprint", "seed") %in% fields), info = schema)
  }
  # The whole pull's stays, on /api/status.
  expect_true("fingerprint" %in% names(spec$components$schemas$Status$properties))
  page <- testthat::test_path("..", "..", "web", "src", "lib", "api.ts")
  skip_if_not(file.exists(page), "the web app's sources are not here (release image)")
  source <- paste(readLines(page, warn = FALSE), collapse = "\n")
  taxon <- sub("(?s).*export interface Taxon \\{(.*?)\\n\\}.*", "\\1", source, perl = TRUE)
  expect_true(grepl("scientific_name", taxon, fixed = TRUE))
  expect_false(grepl("export interface", taxon, fixed = TRUE))
  expect_false(grepl("fingerprint", taxon, fixed = TRUE))
})

# ---- the helpers -------------------------------------------------------------

test_that("the private fields come out at any depth, and nothing else does", {
  x <- list(a = 1, fingerprint = "f", b = list(seed = 2L, c = list(fingerprint = "g", d = "keep")),
            rows = list(list(seed = 3L, e = 4)), plain = list(1, 2))
  expect_equal(atlas_public_fields(x), list(a = 1, b = list(c = list(d = "keep")), rows = list(list(e = 4)), plain = list(1, 2)))
  table <- data.frame(scientific_name = "x", fingerprint = "f", records = 1L)
  expect_equal(names(atlas_public_fields(table)), c("scientific_name", "records"))
})

test_that("taking the fields out of a file's text leaves every other byte as it was", {
  pretty <- '{\n  "taxon": "x",\n  "seed": 12,\n  "fingerprint": "abc",\n  "auc": 0.123456789012,\n  "fold": {\n    "seed": 3,\n    "n": 1\n  }\n}'
  expect_equal(atlas_public_json_text(pretty),
               '{\n  "taxon": "x",\n  "auc": 0.123456789012,\n  "fold": {\n    "n": 1\n  }\n}')
  # Last in its object, and alone in it.
  expect_equal(atlas_public_json_text('{"a": 1, "seed": 2}'), '{"a": 1}')
  expect_equal(atlas_public_json_text('{"a": {"seed": 2}}'), '{"a": {}}')
  # A value stored as empty, as JSON writes a missing one.
  expect_equal(atlas_public_json_text('{"a": 1, "fingerprint": {}, "b": 2}'), '{"a": 1, "b": 2}')
  expect_equal(atlas_public_json_text('{"a": 1, "seed": []}'), '{"a": 1}')
  rows <- '[{"name": "x", "fingerprint": "abc", "sites": 2}, {"name": "y", "fingerprint": "def"}]'
  expect_equal(atlas_public_json_text(rows), '[{"name": "x", "sites": 2}, {"name": "y"}]')
})

test_that("a value it cannot take out stops, rather than publish it", {
  expect_error(atlas_public_json_text('{"a": 1, "seed": {"value": 2}}'), "could not be taken out")
  expect_error(atlas_public_json_text('{"a": 1, "fingerprint": ["abc", "def"]}'), "could not be taken out")
})

# ---- the archive --------------------------------------------------------------

bundle_texts <- function(bundle) {
  tree <- tempfile("unpacked-")
  dir.create(tree)
  utils::untar(bundle$sources[["scores.tar.gz"]], exdir = tree)
  files <- c(list.files(tree, recursive = TRUE, full.names = TRUE),
             bundle$sources[grepl("[.]json$", names(bundle$sources))])
  stats::setNames(lapply(files, function(f) paste(readLines(f, warn = FALSE), collapse = "\n")), basename(files))
}

test_that("a release's archive holds no per-taxon fingerprint or seed, in any file", {
  with_planted_hashes({
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    bundle <- atlas_archive_models_bundle(store, "draft")
    texts <- bundle_texts(bundle)
    expect_true(all(c("amanita-muscaria.json", "taxa.json", "release.json", "benchmark.json") %in% names(texts)))
    for (name in names(texts)) {
      expect_false(grepl(PLANTED, texts[[name]], fixed = TRUE), info = name)
      expect_false(grepl('"seed"\\s*:', texts[[name]]), info = name)
    }
    archived <- jsonlite::fromJSON(texts[["release.json"]], simplifyVector = FALSE)
    expect_true(length(archived$index) > 0L)
    expect_false(any(vapply(archived$index, function(e) "fingerprint" %in% names(e), TRUE)))
    expect_equal(unlist(archived$withheld$fields), c("fingerprint", "seed"))
    # The pull's own stays, in both places that give it.
    expect_equal(archived$pull$fingerprint, "abc")
    expect_equal(jsonlite::fromJSON(bundle$sources[["pull.json"]])$fingerprint, "abc")
    # The rest of a model's record is as the release holds it.
    model <- jsonlite::fromJSON(texts[["amanita-muscaria.json"]], simplifyVector = FALSE)
    expect_equal(model$settings_key, "keep me")
    # The README says so.
    readme <- atlas_archive_readme(bundle, atlas_archive_file_table(bundle$sources))
    expect_true(any(grepl("fingerprint and each model's seed are withheld for privacy", readme, fixed = TRUE)))
  })
})

test_that("what the public notes say of the removal is that it was for privacy, and no more", {
  # Steve, 2026-11-06: the changelog's entry and the archive's notes, word for word.
  path <- testthat::test_path("..", "..", "CHANGELOG.md")
  skip_if_not(file.exists(path), "CHANGELOG.md is not here (release image)")
  changelog <- readLines(path, encoding = "UTF-8", warn = FALSE)
  at <- grep("Removed: each taxon's `fingerprint`", changelog, fixed = TRUE)
  expect_length(at, 1L)
  expect_equal(changelog[at:(at + 1L)], c(
    "- **Removed: each taxon's `fingerprint` and each model's `seed`**, for privacy,",
    "  without the usual 30 days' notice."
  ))
  expect_true(changelog[at + 2L] == "" || startsWith(changelog[at + 2L], "- "))

  with_planted_hashes({
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    bundle <- atlas_archive_models_bundle(store, "draft")
    archived <- jsonlite::fromJSON(bundle_texts(bundle)[["release.json"]], simplifyVector = FALSE)
    expect_equal(archived$withheld$why, "Withheld for privacy.")
    readme <- atlas_archive_readme(bundle, atlas_archive_file_table(bundle$sources))
    at <- grep("are withheld for privacy", readme, fixed = TRUE)
    expect_length(at, 1L)
    expect_equal(readme[at:(at + 1L)], c(
      "Each taxon's record-set fingerprint and each model's seed are withheld for privacy, from these files and",
      "`taxa.json`. `release.json` says so under `withheld`."
    ))
  })
})

test_that("a per-taxon hash under any other name, or a seed, stops the bundle", {
  with_planted_hashes({
    # A new kind of field, in a file the withholding does not look at for it.
    atlas_write_json(list(list(from = "x", to = "y", record_hash = PLANTED)), atlas_renames_path())
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    expect_error(atlas_archive_models_bundle(store, "draft"), "would have been archived, in renames.json")
  })
  with_planted_hashes({
    private <- tempfile(fileext = ".json")
    writeLines('{"seed": 12}', private)
    expect_error(atlas_archive_refuse_withheld(private, character()), "would have been archived")
    writeLines(sprintf('{"note": "%s"}', PLANTED), private)
    expect_error(atlas_archive_refuse_withheld(private, PLANTED), "would have been archived")
    writeLines('{"note": "fine"}', private)
    expect_true(atlas_archive_refuse_withheld(private, PLANTED))
  })
})

test_that("a release's archive still packs to the same bytes every time", {
  with_planted_hashes({
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    first <- atlas_archive_models_bundle(store, "draft")
    Sys.sleep(1.1)
    second <- atlas_archive_models_bundle(store, "draft")
    hashes <- function(b) vapply(b$sources, atlas_sha256, character(1))
    expect_equal(hashes(first), hashes(second))
  })
})

# ---- no model goes stale -------------------------------------------------------

test_that("the calculation does not move: every stored model's fingerprint and seed still hold", {
  # Pinned: a change here would mark every model stale and refit it, and salting
  # would too. Both values are from before this rule.
  records <- data.frame(id = c("2", "1"), scientific_name = "Amanita muscaria", latitude = c("45.5", "44.25"),
                        longitude = c("-120.5", "-119.75"), observed_on = c("2020-01-02", "2019-06-30"),
                        stringsAsFactors = FALSE)
  expect_equal(atlas_fingerprint(records), "d2b981b121948945eec956b19f4140554970d1d2e05c7133dcee1a20c0947e8a")
  expect_equal(atlas_seed_from_fingerprint("8a6c4a97ec6c1b00"), 145147049L)
  expect_equal(atlas_taxon_fingerprints(cbind(records, stringsAsFactors = FALSE))$fingerprint, "d2b981b121948945eec956b19f4140554970d1d2e05c7133dcee1a20c0947e8a")
})

test_that("the release's own files keep what refits read, byte for byte, after every public read", {
  with_planted_hashes({
    before <- vapply(atlas_release_files("draft"), function(p) atlas_sha256(file.path(atlas_data_dir(), p)), "")
    api <- planted_api()
    for (path in c("/api/taxa", "/api/taxa/Amanita%20muscaria", "/api/taxa/Amanita%20muscaria/model",
                   "/api/taxa/Amanita%20muscaria/ensemble")) {
      call_api(api, path)
    }
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    atlas_archive_models_bundle(store, "draft")
    after <- vapply(atlas_release_files("draft"), function(p) atlas_sha256(file.path(atlas_data_dir(), p)), "")
    expect_equal(after[names(before)], before)
    # The private release keeps both, and its index the fingerprint planning reads.
    stored <- jsonlite::fromJSON(atlas_path("models", "draft", "amanita-muscaria.json"), simplifyVector = FALSE)
    expect_equal(stored$fingerprint, PLANTED)
    expect_equal(stored$seed, PLANTED_SEED)
    expect_true(all(vapply(release$index, function(e) identical(e$fingerprint, PLANTED), TRUE)))
    expect_equal(jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))$fingerprint, PLANTED)
  })
})

test_that("with this rule in place, a finished job leaves nothing to refit", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)
  # Every public read, then plan again: nothing is stale.
  on_machine(boss, {
    api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir(), ATLAS_PUBLIC_ORIGIN = "https://atlas.example.org"))
    expect_false(carries_private(call_api(api, "/api/taxa")$body))
    atlas_archive_models_bundle(store, "draft")
    expect_null(atlas_plan_job(store, algorithms = c("maxnet", "rf"), quiet = TRUE))
  })
})
