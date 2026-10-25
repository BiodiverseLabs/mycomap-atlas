# What sequence names change (paper E9): the record-name release (built by
# the private-release job with --record-names) set against the frozen one.

dna_pull <- function() {
  data.frame(
    id = as.character(1:8), source = c(rep("inat", 5), rep("mo", 3)),
    observation_id = as.character(101:108),
    scientific_name = c("Amanita muscaria", "Amanita muscaria", "Amanita muscaria",
                        "Russula sp. 'IN01'", "Russula sp. 'IN01'",
                        "Boletus edulis", "Boletus edulis", "Cortinarius alboviolaceus"),
    stringsAsFactors = FALSE
  )
}

# As the record-name job gives it: each record under its own name, spellings
# merged; the record named only "Russula" is not in it, and the rows come in
# another order.
record_pull <- function() {
  data.frame(
    id = as.character(c(8, 7, 6, 4, 3, 2, 1)), source = c("mo", "mo", "mo", rep("inat", 4)),
    observation_id = as.character(c(108, 107, 106, 104, 103, 102, 101)),
    scientific_name = c("Cortinarius alboviolaceus", "Tylopilus felleus", "Boletus edulis",
                        "Russula emetica", "Amanita persicina", "Amanita muscaria", "Amanita muscaria"),
    stringsAsFactors = FALSE
  )
}

test_that("label changes are told apart by record, whatever order the pulls are in", {
  changes <- atlas_e9_label_changes(dna_pull(), record_pull())
  expect_equal(changes$per_record,
               c("same", "same", "species", "species", "no_taxon", "same", "genus", "same"))
  by <- changes$by_source
  expect_equal(by$records[by$source == "mo" & by$change == "genus"], 1L)
  expect_equal(by$records[by$source == "inat" & by$change == "no_taxon"], 1L)
  expect_equal(sum(by$records), nrow(dna_pull()))
})

test_that("a record kept as effort under a label that is no taxon counts as no taxon", {
  record <- record_pull()
  record <- rbind(record, data.frame(id = "5", source = "inat", observation_id = "105",
                                     scientific_name = "Russula", stringsAsFactors = FALSE))
  expect_equal(atlas_e9_label_changes(dna_pull(), record)$per_record[[5]], "no_taxon")
  expect_false("Russula" %in% atlas_e9_taxon_changes(dna_pull(), record)$gained)
})

test_that("taxa split, merged, gained and lost are counted", {
  taxa <- atlas_e9_taxon_changes(dna_pull(), record_pull())
  expect_equal(taxa$split, c("Amanita muscaria", "Boletus edulis"))
  expect_equal(taxa$gained, c("Amanita persicina", "Russula emetica", "Tylopilus felleus"))
  expect_equal(taxa$lost, "Russula sp. 'IN01'")
  expect_length(taxa$merged, 0L)
  expect_equal(taxa$counts$dna_taxa, 4L)
})

test_that("only taxa under both names whose record sets differ count as changed", {
  changed <- atlas_e9_changed_taxa(dna_pull(), record_pull())
  expect_setequal(changed$taxon, c("Amanita muscaria", "Boletus edulis", "Cortinarius alboviolaceus"))
  expect_false(changed$changed[changed$taxon == "Cortinarius alboviolaceus"])
  amanita <- changed[changed$taxon == "Amanita muscaria", ]
  expect_equal(c(amanita$records_dna, amanita$records_record, amanita$lost, amanita$gained), c(3L, 2L, 1L, 0L))
})

map_grid <- function() terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 1e5, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)

test_that("identical maps compare as Spearman 1 and Schoener's D 1, opposite ones far lower", {
  skip_if_not_installed("terra")
  a <- map_grid()
  terra::values(a) <- seq(0.01, 1, length.out = 100)
  same <- atlas_e9_compare_maps(a, a)
  expect_equal(c(same$cells, same$spearman, same$schoener_d), c(100, 1, 1))
  b <- map_grid()
  terra::values(b) <- rev(seq(0.01, 1, length.out = 100))
  opposite <- atlas_e9_compare_maps(a, b)
  expect_equal(opposite$spearman, -1)
  expect_lt(opposite$schoener_d, 0.6)
  # Only cells both maps cover are compared; a map on a smaller window is
  # extended, not resampled.
  half <- terra::crop(a, terra::ext(0, 5e4, 0, 1e5))
  expect_equal(atlas_e9_compare_maps(a, half)$cells, 50L)
  shifted <- terra::rast(nrows = 10, ncols = 10, xmin = 3000, xmax = 103000, ymin = 0, ymax = 1e5, crs = ATLAS_CRS)
  terra::values(shifted) <- 1
  expect_error(atlas_e9_compare_maps(a, shifted), "one grid")
})

test_that("every record-name model is set against the frozen one: grades, and maps where both are drawn", {
  skip_if_not_installed("terra")
  dir <- tempfile("e9-")
  dir.create(dir)
  write_map <- function(name, values) {
    r <- map_grid()
    terra::values(r) <- values
    path <- file.path(dir, paste0(name, ".tif"))
    terra::writeRaster(r, path, overwrite = TRUE)
    path
  }
  files <- list(
    frozen = list(`Amanita muscaria/maxnet` = write_map("f-am", seq(0.01, 1, length.out = 100)),
                  `Amanita muscaria/rf` = write_map("f-am-rf", seq(0.01, 1, length.out = 100))),
    record = list(`Amanita muscaria/maxnet` = write_map("r-am", seq(0.01, 1, length.out = 100)),
                  `Amanita muscaria/rf` = write_map("r-am-rf", rev(seq(0.01, 1, length.out = 100))),
                  `Amanita persicina/maxnet` = write_map("r-ap", 0.5))
  )
  view <- function(side, entries) list(side = side, grid = "draft", entries = entries)
  frozen <- view("frozen", list(list(taxon = "Amanita muscaria", algorithm = "maxnet", grade = "strong", presences = 60),
                                list(taxon = "Amanita muscaria", algorithm = "rf", grade = "strong", presences = 60)))
  record <- view("record", list(list(taxon = "Amanita muscaria", algorithm = "maxnet", grade = "strong", presences = 52),
                                list(taxon = "Amanita muscaria", algorithm = "rf", grade = "weak", presences = 52),
                                list(taxon = "Amanita persicina", algorithm = "maxnet", grade = "failed", presences = 8)))
  raster_of <- function(v, path, ext) {
    taxon <- if (grepl("persicina", path)) "Amanita persicina" else "Amanita muscaria"
    algorithm <- if (grepl("/rf/", path)) "rf" else "maxnet"
    files[[v$side]][[paste0(taxon, "/", algorithm)]]
  }
  compared <- atlas_e9_compare_releases(frozen, record, raster_of = raster_of)
  expect_equal(nrow(compared), 3L)
  am <- compared[compared$taxon == "Amanita muscaria" & compared$algorithm == "maxnet", ]
  expect_equal(c(am$spearman, am$schoener_d), c(1, 1))
  expect_equal(c(am$presences_dna, am$presences_record), c(60L, 52L))
  rf <- compared[compared$algorithm == "rf", ]
  expect_equal(rf$spearman, -1)
  expect_equal(c(rf$grade_dna, rf$grade_record), c("strong", "weak"))
  # A taxon only under record names has no frozen map to compare with.
  new <- compared[compared$taxon == "Amanita persicina", ]
  expect_true(is.na(new$grade_dna) && is.na(new$spearman))
  grades <- atlas_e9_grade_changes(compared)
  expect_equal(grades$Freq[grades$dna == "strong" & grades$record == "weak"], 1L)
  expect_equal(grades$Freq[grades$dna == "strong" & grades$record == "strong"], 1L)
})

test_that("every frozen model is accounted for: refitted, unchanged, lost, and new ones apart", {
  entry <- function(taxon, algorithm) list(taxon = taxon, algorithm = algorithm)
  frozen <- list(entry("Amanita muscaria", "maxnet"), entry("Amanita muscaria", "rf"),
                 entry("Boletus edulis", "maxnet"), entry("Russula sp. 'IN01'", "esm"),
                 entry("Cortinarius alboviolaceus", "esm"))
  record <- list(entry("Amanita muscaria", "maxnet"), entry("Amanita muscaria", "rf"),
                 entry("Amanita persicina", "esm"))
  names <- c("Amanita muscaria", "Amanita persicina", "Boletus edulis", "Cortinarius alboviolaceus")
  counts <- atlas_e9_model_counts(frozen, record, names, unchanged = 2L)
  expect_equal(counts$frozen_models, 5L)
  expect_equal(c(counts$refitted, counts$unchanged, counts$lost, counts$new), c(2L, 2L, 1L, 1L))
  expect_equal(counts$unaccounted, 0L)
  # A count the job did not report leaves the rest unaccounted, visibly.
  expect_true(is.na(atlas_e9_model_counts(frozen, record, names, NA_integer_)$unaccounted))
})

test_that("the record-name job's summary is read from the private release's prefix", {
  dir <- tempfile("store-")
  key <- paste0(ATLAS_BENCHMARK_PREFIX, "/rn1/summary.json")
  dir.create(file.path(dir, dirname(key)), recursive = TRUE)
  jsonlite::write_json(list(filter = list(models_unchanged = 812L, records_not_species_level = 40L)),
                       file.path(dir, key), auto_unbox = TRUE)
  store <- list(get = function(k, dest) file.copy(file.path(dir, k), dest, overwrite = TRUE) || stop("missing"))
  expect_equal(atlas_e9_summary(store, "rn1")$filter$models_unchanged, 812L)
  expect_null(atlas_e9_summary(store, "other"))
})

# --- End to end, on a private record-names release -------------------------------

# The hindcast fixture's pull, with two of Taxon A's records under another
# name of their own, so Taxon A's record set changes and it is refitted;
# Taxon B's records are named only to genus (lost) and Taxon C's are
# "Taxon Cee" under record names (lost, and a new name).
e9_setup <- function() {
  occ <- hindcast_occurrences()
  a <- which(occ$scientific_name == "Taxon A")
  occ$record_name[a[1:2]] <- "Taxon Zed"
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(occ))
  main <- full_cycle(store, boss, fit = map_fit(list("Taxon A" = "strong", "Taxon B" = "strong", "Taxon C" = "weak")))
  list(store = store, boss = boss, main = main)
}

# The tracker's reader reads a private release only from feat/hindcast
# 1031a9d on; until that is on main, this test says so and skips.
private_releases_readable <- function() {
  any(grepl("vision-benchmark|ATLAS_BENCHMARK_PREFIX|benchmark_key",
            deparse(atlas_tracker_manifest), fixed = FALSE))
}

test_that("E9 compares a finished record-names release with the frozen release end to end", {
  skip_if_not_installed("terra")
  skip_if_not(private_releases_readable(),
              "the tracker cannot read a private release until feat/hindcast 1031a9d is merged")
  setup <- e9_setup()
  job <- on_machine(setup$boss, atlas_plan_private_release(setup$store, setup$main$id, "record-names",
                                                           shards = 1L, quiet = TRUE))
  on_machine(machine(), atlas_run_shard(setup$store, job$id, 1L, quiet = TRUE,
                                        fit = map_fit(list("Taxon A" = "weak", "Taxon Cee" = "strong"))))
  on_machine(machine(), atlas_finish_private_release_work(
    worker_store(setup$store), job$id, quiet = TRUE, count = function(...) 0L,
    ensembles = function(...) NULL, build = stub_finish_build, defer = TRUE))
  record <- atlas_store_text(setup$store, atlas_shard_key(atlas_finish_id(job$id), 1L))
  atlas_place_deferred(setup$store, record$deferred)

  with_data_dir({
    result <- atlas_e9_study(setup$store, frozen = setup$main$id, record = job$id, quiet = TRUE,
                             out = "study/study-e9/")
    expect_true(file.exists(result$path))
    expect_match(result$path, "compare-studies")
    # As a study job's results: the same file under its prefix, where a worker
    # that shuts down leaves it.
    key <- paste0("study/study-e9/", basename(result$path))
    expect_true(setup$store$exists(key))
    copy <- tempfile(fileext = ".json")
    setup$store$get(key, copy)
    expect_identical(unname(tools::md5sum(copy)), unname(tools::md5sum(result$path)))
    models <- result$models
    # Every frozen model is accounted for.
    expect_equal(models$unaccounted, 0L)
    expect_gt(models$refitted, 0L)
    expect_gt(models$lost, 0L)
    expect_gt(models$new, 0L)
    maps <- result$maps
    # Taxon A's learners in both releases are paired; a learner fitted only
    # under record names is a new model with no frozen side.
    a <- maps[maps$taxon == "Taxon A" & !is.na(maps$grade_dna), , drop = FALSE]
    expect_gt(nrow(a), 0L)
    unpaired <- maps[is.na(maps$grade_dna), , drop = FALSE]
    expect_equal(nrow(unpaired), models$new)
    expect_true(all(unpaired$cells == 0L & is.na(unpaired$spearman)))
    expect_true(all(a$grade_dna == "strong" & a$grade_record == "weak"))
    # The stand-in fits draw one map, so the pairs agree exactly.
    expect_true(all(a$spearman == 1 & a$schoener_d == 1))
    expect_true(all(is.na(maps$grade_dna[maps$taxon == "Taxon Cee"])))
    labels <- result$labels
    expect_gt(sum(labels$records[labels$change == "no_taxon"]), 0L)
    expect_gt(sum(labels$records[labels$change == "species"]), 0L)
    # Nothing is written to a release or the current pointer.
    expect_false(any(grepl(job$id, setup$store$list("releases/"))))
  })
})

test_that("E9 refuses a results prefix outside study/ before reading anything, and runs only whole", {
  untouched <- list(list = function(...) stop("read"), get = function(...) stop("read"),
                    exists = function(...) stop("read"), put = function(...) stop("written"))
  expect_error(atlas_e9_study(untouched, frozen = "a", record = "b", quiet = TRUE, out = "releases/draft/"),
               "only under")
  expect_error(atlas_main(c("study-compare", "--frozen=a", "--record=b", "--shard=2/3")), "runs whole")
})
