# Link-preview cards beside a release, never in it (R/card.R). A release is
# never written to add them: fa1b4198 is the paper's frozen release and the
# Zenodo deposit, and must stay the one the site serves (Steve, 2026-10-20).

# A strong map of a taxon over the Pacific Northwest, on the Atlas grid.
cards_model <- function(name = "Taxon A") {
  r <- terra::rast(xmin = -2.3e6, xmax = -1.3e6, ymin = 2e5, ymax = 1.6e6, resolution = 5000, crs = ATLAS_CRS)
  terra::values(r) <- terra::xFromCell(r, seq_len(terra::ncell(r)))
  dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE, showWarnings = FALSE)
  tif <- atlas_model_path(name, "draft", ".tif", "maxnet")
  terra::writeRaster(r, tif, overwrite = TRUE)
  drawn <- atlas_write_map_png(r, sub("[.]tif$", ".png", tif))
  atlas_write_json(list(taxon = name, algorithm = "maxnet", skill = "passed", grade = "strong", presences = 25,
                        raster = basename(tif), map = basename(drawn$path), bounds = drawn$bounds,
                        built_at = "2026-10-06T00:00:00Z"),
                   sub("[.]tif$", ".json", tif))
}

# A store whose current release has one strong map.
cards_published <- function() {
  store <- fresh_store()
  release <- on_machine(machine(), {
    orchestrator_data(synthetic_occurrences(c("Taxon A" = 25)))
    cards_model()
    atlas_publish_release(store, quiet = TRUE)
  })
  list(store = store, release = release)
}

# Every key under releases/ and the bytes of each, to show none changed.
release_state <- function(store) {
  keys <- sort(store$list("releases/"))
  stats::setNames(vapply(keys, function(k) {
    f <- tempfile()
    on.exit(unlink(f), add = TRUE)
    store$get(k, f)
    unname(tools::md5sum(f))
  }, ""), keys)
}

test_that("cards are drawn beside the release, never in it: same release, same manifest, same files", {
  skip_if_not_installed("terra")
  skip_if_not_installed("png")
  setup <- cards_published()
  before <- release_state(setup$store)
  web <- machine()
  built <- on_machine(web, {
    atlas_pull_release(setup$store, rasters = FALSE, quiet = TRUE)
    atlas_build_cards(store = setup$store, quiet = TRUE)
  })
  expect_equal(built$release, setup$release$id)
  expect_equal(built$drawn, 1L)
  # The release, its manifest and the current pointer: untouched, byte for byte.
  expect_identical(release_state(setup$store), before)
  expect_equal(atlas_current_release(setup$store)$id, setup$release$id)
  # The cards are listed beside it, as hashed objects like every published file.
  index <- atlas_store_text(setup$store, atlas_card_index_key("draft", setup$release$id))
  expect_equal(index$release, setup$release$id)
  expect_length(index$files, 1L)
  expect_match(index$files[[1]]$path,
               paste0("^cards/draft/", setup$release$id, "/taxon-a-[0-9a-f]{12}[.]jpg$"))
  expect_true(setup$store$exists(atlas_object_key(index$files[[1]]$sha256)))
})

test_that("a web server's pull brings the release's cards; a worker's does not", {
  skip_if_not_installed("terra")
  skip_if_not_installed("png")
  setup <- cards_published()
  on_machine(machine(), {
    atlas_pull_release(setup$store, rasters = FALSE, quiet = TRUE)
    atlas_build_cards(store = setup$store, quiet = TRUE)
  })
  other <- machine()
  on_machine(other, {
    atlas_pull_release(setup$store, rasters = FALSE, quiet = TRUE)
    card <- atlas_card_for("Taxon A")
    expect_false(is.null(card))
    expect_match(card, paste0("cards/draft/", setup$release$id, "/"), fixed = TRUE)
  })
  worker <- machine()
  on_machine(worker, {
    atlas_pull_release(setup$store, rasters = TRUE, quiet = TRUE)
    expect_false(dir.exists(atlas_path("cards")))
  })
})

test_that("a pull with no cards listed serves none, fails nothing, and drops another release's cards", {
  skip_if_not_installed("terra")
  setup <- cards_published()
  web <- machine()
  on_machine(web, {
    # Cards left from an earlier release, and some drawn locally for this one.
    old <- atlas_card_dir("draft", "20200101T000000Z-old")
    dir.create(old, recursive = TRUE)
    writeLines("x", file.path(old, "taxon-a-000000000000.jpg"))
    pulled <- atlas_pull_release(setup$store, rasters = FALSE, quiet = TRUE)
    expect_equal(pulled$release, setup$release$id)
    expect_false(dir.exists(old))
    expect_null(atlas_card_for("Taxon A"))
  })
})

test_that("a card from another release is never served for this one", {
  skip_if_not_installed("terra")
  skip_if_not_installed("png")
  with_data_dir({
    orchestrator_data(synthetic_occurrences(c("Taxon A" = 25)))
    cards_model()
    atlas_build_cards(quiet = TRUE)
    expect_false(is.null(atlas_card_for("Taxon A")))
    # The machine now serves a different release: the local cards are not its.
    atlas_write_json(list(release = "20261101T000000Z-next", grid = "draft"),
                     atlas_path("releases", "draft", "pulled.json"))
    expect_null(atlas_card_for("Taxon A"))
  })
})

test_that("drawing cards never needs a release to be written: finishing knows nothing of them", {
  finish <- paste(readLines(testthat::test_path("..", "..", "R", "finish.R"), warn = FALSE), collapse = "\n")
  expect_false(grepl("card", finish, ignore.case = TRUE))
  expect_equal(ATLAS_FINISH_VERSION, 5L)
})
