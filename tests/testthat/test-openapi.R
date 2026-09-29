# The OpenAPI file is the API's documentation: the developer page is drawn
# from it and client generators read it. These tests hold it to the routes the
# server actually has, so a new route or parameter cannot ship undocumented and
# a removed one cannot linger on the page.

repo_root <- function() testthat::test_path("..", "..")

read_spec <- function() {
  jsonlite::fromJSON(file.path(repo_root(), "inst", "api", "openapi.json"), simplifyVector = FALSE)
}

served_routes <- function() {
  atlas_plumber_routes(file.path(repo_root(), "inst", "plumber", "atlas.R"))
}

# Follow "#/components/..." references inside the spec.
resolve_ref <- function(spec, node) {
  ref <- node[["$ref"]]
  if (is.null(ref)) {
    return(node)
  }
  parts <- strsplit(sub("^#/", "", ref), "/", fixed = TRUE)[[1]]
  target <- spec
  for (part in parts) target <- target[[part]]
  target
}

spec_params <- function(spec, operation) {
  vapply(operation$parameters %||% list(), function(p) resolve_ref(spec, p)$name, character(1))
}

test_that("the spec is an OpenAPI 3.1 document with a title and version", {
  spec <- read_spec()
  expect_equal(spec$openapi, "3.1.0")
  expect_true(nzchar(spec$info$title))
  expect_true(nzchar(spec$info$version))
})

test_that("every route the server has is documented", {
  documented <- names(read_spec()$paths)
  missing <- setdiff(names(served_routes()), documented)
  expect_equal(missing, character(0), label = "routes missing from inst/api/openapi.json")
})

test_that("every documented route exists on the server", {
  stale <- setdiff(names(read_spec()$paths), names(served_routes()))
  expect_equal(stale, character(0), label = "documented routes the server does not have")
})

test_that("each route documents exactly the parameters its handler takes", {
  spec <- read_spec()
  routes <- served_routes()
  for (path in intersect(names(routes), names(spec$paths))) {
    documented <- sort(spec_params(spec, spec$paths[[path]]$get))
    expect_equal(documented, sort(routes[[path]]$params), label = paste("parameters of", path))
  }
})

test_that("every reference in the spec points at something", {
  spec <- read_spec()
  text <- readLines(file.path(repo_root(), "inst", "api", "openapi.json"), warn = FALSE)
  refs <- unique(unlist(regmatches(text, gregexpr("#/components/[A-Za-z]+/[A-Za-z-]+", text))))
  expect_true(length(refs) > 5)
  for (ref in refs) {
    expect_false(is.null(resolve_ref(spec, list(`$ref` = ref))), label = ref)
  }
})

test_that("each operation has a summary and a success response", {
  spec <- read_spec()
  for (path in names(spec$paths)) {
    operation <- spec$paths[[path]]$get
    expect_true(nzchar(operation$summary %||% ""), label = paste("summary of", path))
    expect_false(is.null(operation$responses[["200"]]), label = paste("200 response of", path))
  }
})

test_that("the route list is read from the plumber file's own text", {
  file <- tempfile(fileext = ".R")
  writeLines(c(
    "#* One thing",
    "#* @get /api/things/<id>",
    "#* @serializer unboxedJSON",
    "function(id, grid = \"draft\", res) {",
    "  list()",
    "}",
    "#* @get /api/plain",
    "function() {",
    "}"
  ), file)
  routes <- atlas_plumber_routes(file)
  expect_equal(names(routes), c("/api/things/{id}", "/api/plain"))
  expect_equal(routes[["/api/things/{id}"]]$params, c("id", "grid"))
  expect_equal(routes[["/api/plain"]]$params, character(0))
})

test_that("the server finds the spec in a source checkout", {
  path <- atlas_openapi_path(repo_root())
  expect_true(file.exists(path))
  expect_equal(jsonlite::fromJSON(path)$info$title, "MycoMap Atlas API")
})

test_that("the rate limits the spec promises are the ones the server applies", {
  documented <- read_spec()[["x-rate-limits"]]
  for (tier in names(ATLAS_RATE_DEFAULTS)) {
    expect_equal(documented[[tier]], ATLAS_RATE_DEFAULTS[[tier]], label = paste("documented", tier, "limit"))
  }
})

test_that("every route documents the token refusal and the rate limit", {
  spec <- read_spec()
  for (path in names(spec$paths)) {
    responses <- spec$paths[[path]]$get$responses
    expect_false(is.null(responses[["401"]]), label = paste("401 on", path))
    expect_false(is.null(responses[["429"]]), label = paste("429 on", path))
  }
  expect_equal(spec$components$securitySchemes$atlasToken$name, "X-API-Key")
})
