# What goes into a release's archive: every file the release publishes has a
# place in the models bundle, or is left out by name and with why, and nothing
# private is ever packed (2026-10-18: the combined maps, renames, name merges
# and the Explore index were being dropped without a word).

# A tiny Explore index: three 20 km cells, the first empty.
tiny_here_index <- function() {
  list(grid = "draft", cell_km = 20, min_rank = 50L, built_at = "2026-01-01T00:00:00Z",
       models = data.frame(taxon = c("Amanita muscaria", "Boletus edulis"), algorithm = c("maxnet", "rf"),
                           stringsAsFactors = FALSE),
       start = c(1L, 1L, 3L, 4L), model = c(1L, 2L, 2L), rank = as.raw(c(90, 60, 75)))
}

# computed_data(), plus one file of every other kind a release publishes
# (atlas_release_files' allowlist).
every_kind_data <- function() {
  computed_data()
  ensemble <- atlas_path("models", "draft", "ensemble")
  dir.create(ensemble, recursive = TRUE, showWarnings = FALSE)
  writeLines("combined raster", file.path(ensemble, "amanita-muscaria.tif"))
  writeLines("combined map", file.path(ensemble, "amanita-muscaria.png"))
  atlas_write_json(list(taxon = "Amanita muscaria", models = 2), file.path(ensemble, "amanita-muscaria.json"))
  atlas_write_json(list(list(from = "Amanita muscaria var. x", to = "Amanita muscaria")), atlas_renames_path())
  atlas_write_json(list(list(name = "Amanita muscaria", spellings = list("Amanita muscaria "))), atlas_name_merges_path())
  atlas_write_tsv_gz(data.frame(cell = 1, taxa = 1), atlas_public_cells_path())
  atlas_write_tsv_gz(data.frame(region = "ON", taxon = "Amanita muscaria"), atlas_public_regions_path())
  atlas_write_tsv_gz(data.frame(taxon = "Amanita muscaria", not_yet_validated = 2), atlas_public_unvalidated_path())
  atlas_write_json(list(stamp = "20260101T000000Z"), atlas_public_pull_path())
  dir.create(atlas_layer_dir("draft"), recursive = TRUE, showWarnings = FALSE)
  atlas_write_json(list(layers = list()), file.path(atlas_layer_dir("draft"), "manifest.json"))
  atlas_write_json(list(models = 2), atlas_path("benchmarks", "draft", "models-20260101T000000Z.json", create = TRUE))
  dir.create(dirname(atlas_here_index_path("draft")), recursive = TRUE, showWarnings = FALSE)
  saveRDS(tiny_here_index(), atlas_here_index_path("draft"))
  dir.create(atlas_prior_dir("draft"), recursive = TRUE, showWarnings = FALSE)
  for (file in ATLAS_PRIOR_FILES) writeLines(paste("prior", file), file.path(atlas_prior_dir("draft"), file))
}

test_that("every file a release publishes has a place in the models bundle", {
  with_data_dir({
    every_kind_data()
    paths <- atlas_release_files("draft")
    # The kinds the 2026-10-18 archive dropped are among them.
    expect_true(all(c("models/draft/ensemble/amanita-muscaria.tif", "occurrences/renames.json",
                      "occurrences/name-merges.json", "index/draft/here.rds") %in% paths))
    plan <- atlas_archive_plan(paths, "draft")
    placed <- c(unlist(lapply(plan$tars, function(t) t$paths)), names(plan$singles), plan$here, plan$excluded)
    expect_setequal(placed, paths)
    expect_setequal(plan$tars[["maps-ensemble.tar"]]$paths,
                    c("models/draft/ensemble/amanita-muscaria.tif", "models/draft/ensemble/amanita-muscaria.png"))
    expect_true("models/draft/ensemble/amanita-muscaria.json" %in% plan$tars[["scores.tar.gz"]]$paths)
    expect_equal(plan$singles[["occurrences/renames.json"]], "renames.json")
    expect_equal(plan$singles[["occurrences/name-merges.json"]], "name-merges.json")
    expect_equal(plan$here, "index/draft/here.rds")
  })
})

test_that("a release file with no place, or a private one, stops the bundle instead of being dropped", {
  paths <- c("models/draft/amanita-muscaria.tif", "models/draft/amanita-muscaria.json")
  expect_error(atlas_archive_plan(c(paths, "models/draft/newkind/amanita-muscaria.tif")),
               "no place for 1 of the release's files .*newkind")
  expect_error(atlas_archive_plan(c(paths, "public/new-table.tsv.gz")), "no place .*new-table")
  expect_error(atlas_archive_plan(c(paths, "private/trained-ids/draft/releases/r1.tsv.gz")), "private files")
  expect_error(atlas_archive_plan(c(paths, "jobs/private/x.json")), "private files")
  # Left out by name, it is left out on purpose.
  plan <- atlas_archive_plan(c(paths, "public/new-table.tsv.gz"),
                             exclude = c("not yet described for the archive" = "^public/new-table"))
  expect_equal(plan$excluded, "public/new-table.tsv.gz")
})

test_that("the Explore index is archived as a table that gives back exactly the index", {
  index <- tiny_here_index()
  table <- atlas_archive_here_table(index)
  expect_equal(table$cell, c(2L, 2L, 3L))
  expect_equal(table$taxon, c("Amanita muscaria", "Boletus edulis", "Boletus edulis"))
  expect_equal(table$algorithm, c("maxnet", "rf", "rf"))
  expect_equal(table$rank, c(90L, 60L, 75L))
  # Back again: the same starts, models and ranks.
  key <- paste(index$models$taxon, index$models$algorithm)
  model <- match(paste(table$taxon, table$algorithm), key)
  start <- c(1L, cumsum(tabulate(table$cell, nbins = length(index$start) - 1L)) + 1L)
  expect_identical(start, index$start)
  expect_identical(as.integer(model), index$model)
  expect_identical(as.raw(table$rank), index$rank)
  grid <- atlas_archive_here_grid(index)
  expect_equal(grid$cell_km, 20)
  expect_equal(grid$entries, 3L)
  # The cell formula is the index's own.
  x <- ATLAS_GRID_EXTENT[["xmin"]] + 25000
  y <- ATLAS_GRID_EXTENT[["ymax"]] - 45000
  expect_equal(atlas_here_cell(x, y, 20), 2 * grid$ncol + 1 + 1)
})

test_that("the bundle carries the combined maps, renames, name merges and the Explore index, and nothing private", {
  with_data_dir({
    every_kind_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    bundle <- atlas_archive_models_bundle(store, "draft")
    expect_true(all(c("maps-ensemble.tar", "renames.json", "name-merges.json", "explore-index-20km.tsv.gz",
                      "explore-index-20km.json") %in% names(bundle$sources)))
    expect_setequal(utils::untar(bundle$sources[["maps-ensemble.tar"]], list = TRUE),
                    c("models/draft/ensemble/amanita-muscaria.tif", "models/draft/ensemble/amanita-muscaria.png"))
    here <- utils::read.delim(gzfile(bundle$sources[["explore-index-20km.tsv.gz"]]), stringsAsFactors = FALSE)
    expect_equal(here, atlas_archive_here_table(tiny_here_index()), ignore_attr = TRUE)
    # No archive file is the R-only .rds.
    expect_false(any(grepl("[.]rds$", names(bundle$sources))))
    expect_false(any(grepl("private", names(bundle$sources))))
    # The README describes the new files.
    readme <- atlas_archive_readme(bundle, atlas_archive_file_table(bundle$sources))
    for (name in c("maps-ensemble.tar", "explore-index-20km.tsv.gz", "renames.json", "name-merges.json")) {
      expect_true(any(grepl(name, readme, fixed = TRUE)), info = name)
    }
  })
})

test_that("a release with every kind of file still packs to the same bytes every time", {
  with_data_dir({
    every_kind_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    first <- atlas_archive_models_bundle(store, "draft")
    Sys.sleep(1.1)
    second <- atlas_archive_models_bundle(store, "draft")
    hashes <- function(b) vapply(b$sources, atlas_sha256, character(1))
    expect_equal(hashes(first), hashes(second))
  })
})

test_that("the models record's summary names every model the release fits, the grades and the cells", {
  template <- jsonlite::fromJSON(file.path(testthat::test_path("..", ".."), "inst", "archive", "zenodo.json"),
                                 simplifyVector = FALSE)
  summary <- tolower(template$models$summary)
  # One phrase per algorithm, so a new algorithm cannot ship undescribed.
  described <- c(maxnet = "maxent", xgboost = "boosted trees", rf = "random forest", esm = "ensemble of small models")
  expect_setequal(names(described), names(ATLAS_ALGORITHMS))
  for (a in names(described)) expect_true(grepl(described[[a]], summary, fixed = TRUE), info = a)
  for (grade in c("strong", "weak", "failed", "untested")) expect_true(grepl(grade, summary, fixed = TRUE), info = grade)
  expect_true(grepl("combined maps", summary, fixed = TRUE))
  expect_true(grepl("0.1 degree cells", summary, fixed = TRUE))
  expect_false(grepl("three ways", summary, fixed = TRUE))
  expect_true("ensembles of small models" %in% unlist(template$common$keywords))
})
