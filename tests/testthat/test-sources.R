# inst/api/sources.json is the public list of everything Atlas is built on.
# These tests keep it whole: a package the code starts calling, or one the web
# app starts depending on, has to be credited there with a link and a licence,
# and a dataset the layers download from has to be listed with its source.

sources_root <- function() testthat::test_path("..", "..")

read_sources <- function() {
  jsonlite::fromJSON(file.path(sources_root(), "inst", "api", "sources.json"), simplifyVector = FALSE)
}

software_names <- function(sources, group) {
  rows <- Filter(function(s) identical(s$group, group), sources$software)
  vapply(rows, `[[`, character(1), "name")
}

# Packages that ship with R itself need no credit line of their own.
BASE_PACKAGES <- c("base", "stats", "utils", "tools", "parallel", "grDevices", "graphics", "methods")

called_packages <- function(root) {
  files <- c(
    list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE),
    list.files(file.path(root, "inst"), pattern = "[.][Rr]$", full.names = TRUE, recursive = TRUE)
  )
  text <- unlist(lapply(files, readLines, warn = FALSE))
  text <- sub("#.*$", "", text)
  found <- unlist(regmatches(text, gregexpr("[A-Za-z][A-Za-z0-9.]+::", text)))
  setdiff(unique(sub("::$", "", found)), BASE_PACKAGES)
}

test_that("every R package the code calls is credited", {
  called <- called_packages(sources_root())
  expect_true(all(c("terra", "maxnet", "ranger") %in% called))
  missing <- setdiff(called, software_names(read_sources(), "r"))
  expect_equal(missing, character(0), label = "packages missing from inst/api/sources.json")
})

test_that("every package the web app depends on is credited", {
  # The release image carries the R package, not the web app's sources; CI's
  # R tests, which have the whole checkout, check this on every change.
  package <- file.path(sources_root(), "web", "package.json")
  skip_if_not(file.exists(package), "the web app's sources are not here (release image)")
  web <- jsonlite::fromJSON(package)
  deps <- c(names(web$dependencies), names(web$devDependencies))
  # Type definitions are build-time scaffolding, not software the site runs on.
  deps <- deps[!startsWith(deps, "@types/")]
  missing <- setdiff(deps, software_names(read_sources(), "web"))
  expect_equal(missing, character(0), label = "web packages missing from inst/api/sources.json")
})

test_that("no credited web package is one the app has stopped depending on", {
  package <- file.path(sources_root(), "web", "package.json")
  skip_if_not(file.exists(package), "the web app's sources are not here (release image)")
  web <- jsonlite::fromJSON(package)
  deps <- c(names(web$dependencies), names(web$devDependencies))
  stale <- setdiff(software_names(read_sources(), "web"), deps)
  expect_equal(stale, character(0), label = "credited web packages the app does not use")
})

test_that("no credited R package is one the code has stopped using", {
  stale <- setdiff(software_names(read_sources(), "r"), c(called_packages(sources_root()), "testthat"))
  expect_equal(stale, character(0), label = "credited packages nothing calls")
})

test_that("every entry links somewhere and says under what licence", {
  sources <- read_sources()
  for (entry in c(sources$datasets, sources$software)) {
    expect_true(grepl("^https://", entry$url %||% ""), label = paste("link for", entry$name))
    expect_true(nzchar(entry$license %||% ""), label = paste("licence for", entry$name))
    expect_true(nzchar(entry$role %||% ""), label = paste("role of", entry$name))
  }
})

test_that("every layer that downloads from a provider names a listed dataset", {
  listed <- vapply(read_sources()$datasets, `[[`, character(1), "url")
  for (layer in atlas_layer_registry()) {
    if (is.null(layer$url) || is.na(layer$url)) next
    expect_true(layer$url %in% listed, label = paste("dataset for layer", layer$id))
  }
})

test_that("every data product says whether it is published, and where or why not", {
  allowed <- c("published", "in releases", "planned", "at source", "withheld")
  for (product in read_sources()$products) {
    expect_true(product$availability %in% allowed, label = product$name)
    explained <- if (identical(product$availability, "published")) product$where else product$why
    expect_true(nzchar(explained %||% ""), label = paste("where or why for", product$name))
  }
})

test_that("a withheld product is never also given an address", {
  for (product in read_sources()$products) {
    if (identical(product$availability, "withheld")) expect_null(product$where, label = product$name)
  }
})

test_that("references carry a DOI link target", {
  for (ref in read_sources()$references) {
    expect_true(grepl("^10[.][0-9]+/", ref$doi %||% ""), label = ref$citation)
  }
})

test_that("the layer overview hands out each provider's link", {
  with_data_dir({
    layers <- atlas_layer_overview("draft")
    by_id <- stats::setNames(layers, vapply(layers, `[[`, character(1), "id"))
    expect_equal(by_id$bioclim$url, "https://worldclim.org/data/worldclim21.html")
    # Terrain is derived on the grid, so it has nothing to link to.
    expect_null(by_id$terrain$url)
  })
})

test_that("the server finds the sources in a source checkout", {
  expect_true(file.exists(atlas_sources_path(sources_root())))
})

test_that("every dataset production fits on is explained beside its bar on the taxon page", {
  # The ? beside each dataset in "What drives this map" says what it is, which
  # variables it offers and why. A dataset without one would show a bare bar.
  path <- file.path(sources_root(), "web", "src", "lib", "layerNotes.tsx")
  # As for the credits above: the release image has no web sources, and CI's
  # R tests on the full checkout are where this is checked.
  skip_if_not(file.exists(path), "the web app's sources are not here (release image)")
  notes <- readLines(path, warn = FALSE)
  keys <- sub(":.*$", "", trimws(grep("^  [a-z0-9_]+: ", notes, value = TRUE)))
  expect_equal(setdiff(ATLAS_PRODUCTION_LAYERS, keys), character())
})
