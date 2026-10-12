# A strong model's continent-wide projection, for Vision: every 20 km cell's
# rank on the model's own in-area scale and its area-of-applicability index,
# private, and with the in-area map exactly as it would be without it.

test_that("a continent cell is ranked on the in-area scale the map is coloured on", {
  reference <- c(3, 1, 2, 2, 5)
  # The reference itself ranks as atlas_rank_scale ranks it, ties included.
  expect_equal(atlas_percentile_in(reference, reference), atlas_rank_scale(reference))
  # Beyond the reference: the ends of the scale.
  expect_equal(atlas_percentile_in(c(-10, 99), reference), c(0, 1))
  # Between two values (3 ranks 0.75, 5 ranks 1): the midpoint.
  expect_equal(atlas_percentile_in(4, reference), 0.875)
  expect_true(is.na(atlas_percentile_in(NA_real_, reference)))
})

fit_synthetic <- function(continent) {
  with_data_dir({
    world <- synthetic_landscape()
    atlas_fit_taxon("Eastern fungus", points = world$points, stack = world$stack,
                    fingerprint = "f00dfeed", layers = "synthetic", n_background = 500,
                    buffer_km = 300, quiet = TRUE, nulls = 0, tune = FALSE,
                    guilds = stats::setNames(character(), character()), continent = continent)
    paths <- atlas_model_path("Eastern fungus", "draft", c(".tif", ".di.tif", ".png", ATLAS_CONTINENT_EXT))
    list(
      sha = vapply(paths[1:3], function(p) if (file.exists(p)) atlas_sha256(p) else NA_character_, ""),
      continent = if (file.exists(paths[[4]])) {
        r <- terra::rast(paths[[4]])
        cbind(terra::xyFromCell(r, seq_len(terra::ncell(r))), terra::values(r))
      },
      metrics = atlas_read_metrics("Eastern fungus", "draft")
    )
  })
}

test_that("the projection leaves the in-area map, its dissimilarity layer and its picture byte for byte as they were", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  without <- fit_synthetic(FALSE)
  with <- fit_synthetic(TRUE)
  expect_true(all(!is.na(without$sha)))
  expect_identical(unname(with$sha), unname(without$sha))
  expect_null(without$continent)
  expect_null(without$metrics$continent)
  expect_false(is.null(with$metrics$continent))
})

test_that("the projection reaches past the accessible area, and says where it is extrapolating", {
  skip_if_not_installed("terra")
  skip_if_not_installed("maxnet")
  fit <- fit_synthetic(TRUE)
  cells <- as.data.frame(fit$continent)
  # Every 20 km cell of the 1,000 km landscape, not only the 300 km around the finds.
  expect_equal(nrow(cells), 50L * 50L)
  expect_true(all(is.finite(cells$rank)))
  expect_true(all(cells$rank >= 0 & cells$rank <= 100))
  # The fungus is found in the east, and the first predictor rises eastward:
  # the far west ranks low and lies outside the area of applicability.
  threshold <- fit$metrics$applicability$threshold
  west <- cells[cells$x < 2e5, ]
  east <- cells[cells$x > 8e5, ]
  expect_lt(mean(west$rank), mean(east$rank))
  expect_gt(mean(west$dissimilarity > threshold), 0.9)
  expect_gt(stats::median(west$dissimilarity), 10 * stats::median(east$dissimilarity))
  expect_equal(fit$metrics$continent$cells, nrow(cells))
})

test_that("a projection is never published, even when a fit left one in the data directory", {
  skip_if_not_installed("terra")
  with_data_dir({
    write_model("Eastern agreed", "maxnet", here_raster("east"))
    writeLines("a projection", atlas_model_path("Eastern agreed", "draft", ATLAS_CONTINENT_EXT))
    expect_false(any(grepl("cont[.]tif$", atlas_release_files("draft"))))
    release <- atlas_publish_release(new_store(), quiet = TRUE)
    expect_false(any(grepl("cont[.]tif$", vapply(release$files, `[[`, "", "path"))))
  })
})

test_that("the export combines each taxon's strong models: the mean rank, and the nearest to inside its area", {
  skip_if_not_installed("terra")
  with_data_dir({
    fit <- map_fit(list("Taxon B" = "strong"))
    for (algorithm in c("maxnet", "rf")) {
      fit("Taxon B", "f", algorithm = algorithm, continent = TRUE)
      path <- atlas_model_path("Taxon B", "draft", ".json", algorithm)
      metrics <- jsonlite::fromJSON(path, simplifyVector = FALSE)
      metrics$applicability <- list(threshold = 1)
      atlas_write_json(metrics, path)
    }
    out <- atlas_build_continent("draft", quiet = TRUE)
    expect_equal(out$taxa$name, "Taxon B")
    expect_equal(out$taxa$models, 2L)
    expect_equal(sort(out$table$rank), c(10L, 40L, 70L, 100L))
    # Dissimilarity over threshold, as a percentage, capped at 255.
    expect_equal(out$table$aoa[order(out$table$rank)], c(20L, 40L, 150L, 255L))
    grid <- jsonlite::fromJSON(file.path(atlas_continent_dir("draft"), "grid.json"))
    expect_equal(grid$rows, 4L)
    expect_match(grid$reading, "Private")
  })
})

continent_setup <- function() {
  setup <- prior_only_setup()
  job <- on_machine(setup$boss, atlas_plan_continent_only(setup$store, setup$main$id, shards = 2L, quiet = TRUE))
  c(setup, list(job = job))
}

finish_continent <- function(setup, fit) {
  for (n in seq_len(setup$job$shards)) {
    on_machine(machine(), atlas_run_shard(setup$store, setup$job$id, n, quiet = TRUE, fit = fit))
  }
  on_machine(machine(), atlas_finish_prior_only_work(setup$store, setup$job$id, quiet = TRUE))
}

test_that("the main release's continent job refits its strong models unchanged, and checks each refit matches", {
  skip_if_not_installed("terra")
  setup <- continent_setup()
  job <- setup$job
  expect_identical(job$purpose, "continent")
  expect_true(startsWith(job$id, "cont-"))
  expect_equal(job$filter$records_removed, 0L)
  expect_true(job$fit$continent)
  expect_equal(job$fit$nulls, 0)
  # Nothing left out: Taxon A keeps all 25 records and is refitted too.
  expect_setequal(vapply(job$tasks, function(t) paste(t$algorithm, t$taxon), ""),
                  c("maxnet Taxon A", "rf Taxon A", "maxnet Taxon B", "rf Taxon B"))
  summary <- finish_continent(setup, map_fit())
  expect_equal(summary$identity$compared, 4L)
  expect_equal(summary$identity$identical, 4L)
  expect_length(summary$identity$differ, 0L)
  expect_equal(summary$continent$taxa, 2L)
  key <- paste0("private/atlas-continent/", setup$main$id, "/draft/taxa.tsv")
  expect_true(setup$store$exists(key))
  expect_true(setup$store$exists(paste0("private/atlas-continent/", setup$main$id, "/summary.json")))
  # It makes no prior and no trained ids: the main release has its own.
  expect_false(setup$store$exists(atlas_trained_release_key(job$id)))
  expect_false(any(grepl("/prior/", unlist(summary$files))))
})

test_that("a refit whose in-area map differs from the release's is reported, by path", {
  skip_if_not_installed("terra")
  setup <- continent_setup()
  plain <- map_fit()
  drifted <- function(name, fingerprint, grid = "draft", algorithm = "maxnet", ...) {
    out <- plain(name, fingerprint, grid = grid, algorithm = algorithm, ...)
    if (identical(name, "Taxon B") && identical(algorithm, "rf")) {
      r <- terra::rast(atlas_model_path(name, grid, ".tif", algorithm))
      terra::values(r) <- terra::values(r) + 1
      terra::writeRaster(r, atlas_model_path(name, grid, ".tif", algorithm), overwrite = TRUE)
    }
    out
  }
  summary <- finish_continent(setup, drifted)
  expect_equal(summary$identity$identical, 3L)
  expect_equal(unlist(summary$identity$differ), "models/draft/rf/taxon-b.tif")
})

test_that("the continent job is never public: only its job's and private keys, and the release unchanged", {
  skip_if_not_installed("terra")
  setup <- continent_setup()
  before <- sort(unlist(lapply(c("releases/", "current/", "archives/", "layers/", "jobs/", "private/"), setup$store$list)))
  current <- atlas_current_release(setup$store)
  finish_continent(setup, map_fit())
  after <- sort(unlist(lapply(c("releases/", "current/", "archives/", "layers/", "jobs/", "private/"), setup$store$list)))
  added <- setdiff(after, before)
  expect_true(all(startsWith(added, paste0("jobs/draft/", setup$job$id, "/")) |
                    startsWith(added, paste0("jobs/draft/finish-", setup$job$id, "/")) |
                    startsWith(added, "private/atlas-continent/")), info = paste(added, collapse = ", "))
  expect_identical(atlas_current_release(setup$store), current)
  expect_error(atlas_finish_job(setup$store, setup$job$id, quiet = TRUE), "never becomes a release")
  on_machine(machine(), {
    atlas_pull_release(setup$store, quiet = TRUE)
    expect_length(list.files(atlas_data_dir(), pattern = "cont[.]tif$", recursive = TRUE), 0L)
    expect_false(dir.exists(atlas_continent_dir("draft")))
  })
})

test_that("Vision's benchmark job carries its continent projection too, privately", {
  skip_if_not_installed("terra")
  setup <- prior_only_setup()
  job <- on_machine(setup$boss, atlas_plan_prior_only(setup$store, setup$main$id, PRIOR_ONLY_CUTOFF,
                                                      shards = 1L, quiet = TRUE))
  expect_true(job$fit$continent)
  on_machine(machine(), atlas_run_shard(setup$store, job$id, 1L, quiet = TRUE, fit = map_fit()))
  summary <- on_machine(machine(), atlas_finish_prior_only_work(setup$store, job$id, quiet = TRUE,
                                                                build = stub_prior_build))
  expect_equal(summary$continent$taxa, 1L)
  expect_true(setup$store$exists(atlas_benchmark_key(job$id, "continent", "draft", "taxa.tsv")))
  # And its benchmark checks are as before.
  expect_equal(summary$filter$records_after_cutoff_kept, 0L)
  expect_true(setup$store$exists(atlas_trained_release_key(job$id)))
})
