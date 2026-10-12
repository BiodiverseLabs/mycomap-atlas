# The continent export, for Vision: every strong map's rank across the whole
# grid by 20 km cell, on its own map's scale, with how far it is
# extrapolating there. Built from the full-extent files, private.

test_that("a value is ranked on the in-area scale the map is coloured on", {
  reference <- c(3, 1, 2, 2, 5)
  # The reference itself ranks as atlas_rank_scale ranks it, ties included.
  expect_equal(atlas_percentile_in(reference, reference), atlas_rank_scale(reference))
  # Beyond the reference: the ends of the scale.
  expect_equal(atlas_percentile_in(c(-10, 99), reference), c(0, 1))
  # Between two values (3 ranks 0.75, 5 ranks 1): the midpoint.
  expect_equal(atlas_percentile_in(4, reference), 0.875)
  expect_true(is.na(atlas_percentile_in(NA_real_, reference)))
})

test_that("every cell is ranked: the map's rank where the map ranks, the same scale elsewhere", {
  skip_if_not_installed("terra")
  f <- full_fixture(threshold = 0.4)
  rank <- atlas_full_ranks(f$full, f$suitability, f$dissimilarity, f$threshold)
  default <- terra::extend(atlas_map_layers(f$suitability, f$dissimilarity, f$threshold)[["rank"]], f$full)
  mapped <- !is.na(terra::values(default, mat = FALSE))
  expect_identical(rank[mapped], terra::values(default, mat = FALSE)[mapped])
  # Hatched in-area ground and everything beyond get a rank too.
  expect_true(all(is.finite(rank)))
  expect_true(all(rank >= 0 & rank <= 1))
})

test_that("the export combines each taxon's strong maps: the mean rank, and the nearest to inside its area", {
  skip_if_not_installed("terra")
  with_data_dir({
    fit <- map_fit(list("Taxon B" = "strong", "Taxon W" = "weak"))
    for (algorithm in c("maxnet", "rf")) fit("Taxon B", "f", algorithm = algorithm, full = TRUE)
    fit("Taxon W", "f", algorithm = "rf", full = TRUE)
    out <- atlas_build_continent("draft", quiet = TRUE)
    # Only strong maps.
    expect_equal(out$taxa$name, "Taxon B")
    expect_equal(out$taxa$models, 2L)
    table <- out$table
    # The map's own ground (index 0) is inside; far east (index up to 1, over
    # a threshold of 0.5) is outside, and rank 100 there, beyond every in-area value.
    expect_true(all(table$rank >= 0 & table$rank <= 100))
    expect_true(any(table$aoa <= 100) && any(table$aoa > 100))
    expect_true(all(table$rank[table$aoa > 100] == 100L))
    grid <- jsonlite::fromJSON(file.path(atlas_continent_dir("draft"), "grid.json"))
    expect_equal(grid$rows, nrow(table))
    expect_match(grid$reading, "Private")
  })
})

test_that("a release's continent export is filed privately when it is finished, never in the release", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  release <- on_machine(boss, {
    orchestrator_data(synthetic_occurrences(c("Taxon B" = 30)))
    fit <- map_fit(list("Taxon B" = "strong"))
    fit("Taxon B", "f", algorithm = "maxnet", full = TRUE)
    atlas_publish_release(store, quiet = TRUE)
  })
  record <- on_machine(machine(), atlas_finish_release_work(store, release$id, quiet = TRUE))
  private <- vapply(record$private, function(e) paste(e$prefix, e$name, sep = "/"), "")
  expect_true(paste(ATLAS_CONTINENT_PREFIX, "taxa.tsv", sep = "/") %in% private)
  expect_false(any(grepl("continent|unpublished", vapply(record$files, `[[`, "", "path"))))
  finished <- on_machine(boss, atlas_apply_finish(store, release$id, quiet = TRUE))
  expect_true(store$exists(paste(ATLAS_CONTINENT_PREFIX, finished$id, "draft", "taxa.tsv", sep = "/")))
  expect_false(any(grepl("continent|unpublished", vapply(finished$files, `[[`, "", "path"))))
  # The full-extent files themselves are the map's, and do go out.
  expect_true("models/draft/taxon-b.full.png" %in% vapply(finished$files, `[[`, "", "path"))
})

test_that("Vision's benchmark job refits with full views and carries its continent export, privately", {
  skip_if_not_installed("terra")
  setup <- prior_only_setup()
  job <- on_machine(setup$boss, atlas_plan_prior_only(setup$store, setup$main$id, PRIOR_ONLY_CUTOFF,
                                                      shards = 1L, quiet = TRUE))
  expect_true(job$fit$full)
  on_machine(machine(), atlas_run_shard(setup$store, job$id, 1L, quiet = TRUE, fit = map_fit()))
  summary <- on_machine(machine(), atlas_finish_prior_only_work(setup$store, job$id, quiet = TRUE,
                                                                build = stub_prior_build))
  expect_equal(summary$continent$taxa, 1L)
  expect_true(setup$store$exists(atlas_benchmark_key(job$id, "continent", "draft", "taxa.tsv")))
  expect_equal(summary$filter$records_after_cutoff_kept, 0L)
  expect_true(setup$store$exists(atlas_trained_release_key(job$id)))
})
