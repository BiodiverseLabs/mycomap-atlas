test_that("a percent-encoded name from the URL path is decoded", {
  expect_equal(atlas_decode_name("Amanita%20muscaria"), "Amanita muscaria")
  expect_equal(atlas_decode_name("Russula%20%27IN01%27"), "Russula 'IN01'")
})

test_that("an already-decoded name survives decoding", {
  expect_equal(atlas_decode_name("Amanita muscaria"), "Amanita muscaria")
  expect_equal(atlas_decode_name(NULL), "")
})

test_that("the dev web app's origin is allowed", {
  expect_equal(
    atlas_allowed_origin("http://localhost:5101"),
    "http://localhost:5101"
  )
  expect_equal(
    atlas_allowed_origin("http://127.0.0.1:5101"),
    "http://127.0.0.1:5101"
  )
})

test_that("any other site is refused, so a page you visit cannot read the API", {
  expect_null(atlas_allowed_origin("https://example.com"))
  expect_null(atlas_allowed_origin("http://localhost:5100"))
})

test_that("a lookalike origin is refused, because matching is exact", {
  expect_null(atlas_allowed_origin("http://localhost:5101.example.com"))
  expect_null(atlas_allowed_origin("https://localhost:5101"))
  expect_null(atlas_allowed_origin("http://localhost:51010"))
})

test_that("a request with no origin gets no header", {
  expect_null(atlas_allowed_origin(NULL))
  expect_null(atlas_allowed_origin(""))
  expect_null(atlas_allowed_origin(character()))
})

test_that("ATLAS_ALLOWED_ORIGINS replaces the defaults", {
  with_env(c(ATLAS_ALLOWED_ORIGINS = "https://atlas.example.org , https://other.example.org"), {
    expect_equal(
      atlas_allowed_origin("https://atlas.example.org"),
      "https://atlas.example.org"
    )
    expect_null(atlas_allowed_origin("http://localhost:5101"))
  })
})

test_that("an empty setting falls back to the defaults", {
  with_env(c(ATLAS_ALLOWED_ORIGINS = ""), {
    expect_equal(atlas_allowed_origins(), ATLAS_DEFAULT_ORIGINS)
  })
})

test_that("a taxon that is not in the pull returns nothing", {
  taxa <- atlas_taxon_fingerprints(fake_occurrences())
  expect_null(atlas_taxon_row(taxa, "Boletus edulis"))
  expect_equal(atlas_taxon_row(taxa, "Amanita muscaria")$records, 3L)
})

test_that("cells are aggregated to the public grid", {
  cells <- atlas_public_cells(fake_occurrences(), "Amanita muscaria")
  expect_equal(nrow(cells), 1L)
  expect_equal(cells$records, 3L)
})

test_that("a published cell never repeats a record's own coordinates", {
  records <- fake_occurrences()
  cells <- atlas_public_cells(records, "Amanita muscaria")
  expect_false(any(cells$lat %in% as.numeric(records$latitude)))
  expect_false(any(cells$lng %in% as.numeric(records$longitude)))
})

test_that("a finer grid separates what the public grid merges", {
  records <- fake_occurrences()
  coarse <- atlas_public_cells(records, "Amanita muscaria", degrees = 0.1)
  fine <- atlas_public_cells(records, "Amanita muscaria", degrees = 0.01)
  expect_lt(nrow(coarse), nrow(fine))
})

test_that("an unknown taxon has no cells", {
  expect_equal(nrow(atlas_public_cells(fake_occurrences(), "Boletus edulis")), 0L)
})

test_that("a request names Maxent by default, and a model Atlas fits otherwise", {
  expect_equal(atlas_request_algorithm(NULL), "maxnet")
  expect_equal(atlas_request_algorithm(""), "maxnet")
  expect_equal(atlas_request_algorithm("rf"), "rf")
})

test_that("a request for a model Atlas does not fit is refused, not guessed", {
  expect_null(atlas_request_algorithm("../../etc"))
  expect_null(atlas_request_algorithm("glm"))
})

test_that("the newest study is the one served", {
  with_data_dir({
    dir.create(atlas_path("benchmarks", "draft"), recursive = TRUE)
    atlas_write_json(list(which = "old"), atlas_path("benchmarks", "draft", "models-20260101T000000Z.json"))
    atlas_write_json(list(which = "new"), atlas_path("benchmarks", "draft", "models-20260928T220000Z.json"))
    writeLines("not a study", atlas_path("benchmarks", "draft", "models-20260928T220000Z.log"))
    expect_equal(atlas_latest_study("benchmarks", prefix = "models")$which, "new")
  })
})

test_that("no study yet is NULL, not an error", {
  with_data_dir({
    expect_null(atlas_latest_study("benchmarks"))
  })
})

namespace_exports <- function(root) {
  lines <- grep("^export[(]", readLines(file.path(root, "NAMESPACE")), value = TRUE)
  gsub("^export[(]|[)]$", "", lines)
}

test_that("every Atlas function the API file calls is exported", {
  # Installed as a package, the API sees only exports: a function missing from
  # NAMESPACE works from source and breaks in the release container.
  root <- testthat::test_path("..", "..")
  api <- readLines(file.path(root, "inst", "plumber", "atlas.R"))
  called <- unique(unlist(regmatches(api, gregexpr("atlas_[a-z_]+[(]", api))))
  called <- sub("[(]$", "", called)
  exported <- namespace_exports(root)
  expect_true(length(called) > 5)
  expect_equal(setdiff(called, exported), character())
})

test_that("every Atlas constant the API file reads is exported", {
  # The same trap for a value: ATLAS_PUBLIC_DEGREES was read by the cells
  # endpoint and never exported, so every taxon page lost its collection
  # dots in the container while every test, run from source, passed.
  root <- testthat::test_path("..", "..")
  data <- utils::getParseData(parse(file.path(root, "inst", "plumber", "atlas.R"), keep.source = TRUE))
  symbols <- unique(data$text[data$token %in% c("SYMBOL", "SYMBOL_FUNCTION_CALL")])
  # Names the package defines, whatever the file calls them: request fields
  # and the file's own helpers are not the package's.
  ours <- symbols[vapply(symbols, exists, logical(1), envir = asNamespace("mycomapatlas"), inherits = FALSE)]
  expect_true("ATLAS_PUBLIC_DEGREES" %in% ours)
  expect_equal(setdiff(ours, namespace_exports(root)), character())
})

test_that("nothing is exported that does not exist", {
  exported <- namespace_exports(testthat::test_path("..", ".."))
  missing <- exported[!vapply(exported, exists, logical(1))]
  expect_equal(missing, character())
})
