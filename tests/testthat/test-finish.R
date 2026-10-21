# Finishing a release: the products that need every map at once (the
# could-grow-here index and the counts by state) are made on a worker after
# the job, and the box publishes them as the finished release.

finish_config <- function(store) {
  values <- c(
    ATLAS_STORE = store, ATLAS_EC2_REGION = "us-east-2",
    ATLAS_EC2_SUBNETS = "subnet-a", ATLAS_EC2_SECURITY_GROUP = "sg-1",
    ATLAS_EC2_INSTANCE_PROFILE = "atlas-worker", ATLAS_EC2_INSTANCE_TYPES = "c7a.8xlarge"
  )
  atlas_ec2_config(env = function(name, unset = "") if (name %in% names(values)) values[[name]] else unset,
                   commit = strrep("a", 40))
}

# A map of Taxon A over the Pacific Northwest, where synthetic_occurrences puts
# it (49N), rising eastward, on the Atlas grid; drawn and passed, as a real
# fit leaves it.
northwest_model <- function() {
  r <- terra::rast(xmin = -2.3e6, xmax = -1.3e6, ymin = 2e5, ymax = 1.6e6, resolution = 5000, crs = ATLAS_CRS)
  terra::values(r) <- terra::xFromCell(r, seq_len(terra::ncell(r)))
  dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE, showWarnings = FALSE)
  tif <- atlas_model_path("Taxon A", "draft", ".tif", "maxnet")
  terra::writeRaster(r, tif, overwrite = TRUE)
  drawn <- atlas_write_map_png(r, sub("[.]tif$", ".png", tif))
  atlas_write_json(list(taxon = "Taxon A", algorithm = "maxnet", skill = "passed", grade = "strong", presences = 25,
                        raster = basename(tif), map = basename(drawn$path), bounds = drawn$bounds,
                        built_at = "2026-10-06T00:00:00Z"),
                   sub("[.]tif$", ".json", tif))
}

# A store whose current release has one real map, never finished.
published <- function() {
  store <- fresh_store()
  boss <- machine()
  release <- on_machine(boss, {
    orchestrator_data(synthetic_occurrences(c("Taxon A" = 25)))
    northwest_model()
    atlas_publish_release(store, quiet = TRUE)
  })
  list(store = store, boss = boss, release = release)
}

test_that("a release no worker has finished is not finished", {
  expect_false(atlas_release_finished(list(id = "r")))
  expect_true(atlas_release_finished(list(finished = list(version = ATLAS_FINISH_VERSION))))
  expect_false(atlas_release_finished(list(finished = list(version = ATLAS_FINISH_VERSION - 1L))))
})

test_that("a finishing worker counts the maps, builds the index, prior and cards, and reports only what changed", {
  skip_if_not_installed("terra")
  setup <- published()
  record <- on_machine(machine(), atlas_finish_release_work(setup$store, setup$release$id, quiet = TRUE))
  paths <- vapply(record$files, `[[`, "", "path")
  prior <- paste0("prior/draft/", c("ranks.tsv.gz", "taxa.tsv", "grid.json", "models.tsv", "aoa.tsv.gz",
                                    if (requireNamespace("nanoparquet", quietly = TRUE)) c("ranks.parquet", "aoa.parquet")))
  # And the link-preview card of its one strong map, named for that map.
  cards <- grep("^models/draft/cards/", paths, value = TRUE)
  expect_length(cards, 1L)
  expect_match(cards, "^models/draft/cards/taxon-a-[0-9a-f]{12}[.]jpg$")
  expect_setequal(setdiff(paths, cards), c("index/draft/here.rds", "models/draft/taxon-a.json", prior))
  expect_equal(record$counted, 1L)
  expect_equal(record$release, setup$release$id)
  # Uploaded: the box needs only the record and the objects it names.
  for (f in record$files) expect_true(setup$store$exists(atlas_object_key(f$sha256)))
})

test_that("the box publishes the finished release: the worker's files in, everything else kept", {
  skip_if_not_installed("terra")
  setup <- published()
  on_machine(machine(), atlas_finish_release_work(setup$store, setup$release$id, quiet = TRUE))
  finished <- on_machine(setup$boss, atlas_apply_finish(setup$store, setup$release$id, quiet = TRUE))

  expect_true(atlas_release_finished(finished))
  expect_equal(finished$previous, setup$release$id)
  expect_equal(atlas_current_release(setup$store)$id, finished$id)
  expect_equal(finished$index, setup$release$index)
  expect_equal(finished$pull, setup$release$pull)
  before <- vapply(setup$release$files, `[[`, "", "path")
  after <- vapply(finished$files, `[[`, "", "path")
  expect_true(all(before %in% after))
  expect_true("index/draft/here.rds" %in% after)

  # A web server pulling it, without rasters, gets the index and the counts.
  on_machine(machine(), {
    atlas_pull_release(setup$store, rasters = FALSE, quiet = TRUE)
    index <- atlas_read_here_index("draft")
    expect_equal(index$models$taxon, "Taxon A")
    metrics <- jsonlite::fromJSON(atlas_model_path("Taxon A", "draft", ".json", "maxnet"), simplifyVector = FALSE)
    expect_true(any(c("US-WA", "CA-BC") %in% atlas_region_rows(metrics$regions)$code))
  })
})

# Taxon A's map, also fitted by the forest: two strong maps, so a combined one.
second_northwest_model <- function() {
  r <- terra::rast(xmin = -2.3e6, xmax = -1.3e6, ymin = 2e5, ymax = 1.6e6, resolution = 5000, crs = ATLAS_CRS)
  terra::values(r) <- -terra::yFromCell(r, seq_len(terra::ncell(r)))
  dir.create(atlas_model_dir("draft", "rf"), recursive = TRUE, showWarnings = FALSE)
  tif <- atlas_model_path("Taxon A", "draft", ".tif", "rf")
  terra::writeRaster(r, tif, overwrite = TRUE)
  drawn <- atlas_write_map_png(r, sub("[.]tif$", ".png", tif))
  atlas_write_json(list(taxon = "Taxon A", algorithm = "rf", skill = "passed", grade = "strong", presences = 25,
                        auc_mean = 0.75, raster = basename(tif), map = basename(drawn$path), bounds = drawn$bounds,
                        built_at = "2026-10-06T00:00:00Z"),
                   sub("[.]tif$", ".json", tif))
}

test_that("finishing builds the combined map of a taxon's strong maps, which no job's release had", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  release <- on_machine(boss, {
    orchestrator_data(synthetic_occurrences(c("Taxon A" = 25)))
    northwest_model()
    metrics <- jsonlite::fromJSON(atlas_model_path("Taxon A", "draft", ".json"), simplifyVector = FALSE)
    metrics$auc_mean <- 0.7
    atlas_write_json(metrics, atlas_model_path("Taxon A", "draft", ".json"))
    second_northwest_model()
    atlas_publish_release(store, quiet = TRUE)
  })
  expect_false(any(grepl("/ensemble/", vapply(release$files, `[[`, "", "path"))))
  record <- on_machine(machine(), atlas_finish_release_work(store, release$id, quiet = TRUE))
  expect_true("models/draft/ensemble/taxon-a.json" %in% vapply(record$files, `[[`, "", "path"))
  finished <- on_machine(boss, atlas_apply_finish(store, release$id, quiet = TRUE))
  expect_true(all(paste0("models/draft/ensemble/taxon-a", c(".json", ".tif", ".png")) %in%
                    vapply(finished$files, `[[`, "", "path")))
})

test_that("a combined map a taxon no longer qualifies for leaves the finished release", {
  skip_if_not_installed("terra")
  setup <- published()
  # The release carries a combined map left from when the taxon had two strong maps.
  stale <- tempfile()
  writeLines("an old combined map", stale)
  entry <- list(path = "models/draft/ensemble/taxon-a.json", sha256 = atlas_sha256(stale), bytes = 20)
  setup$store$put(atlas_object_key(entry$sha256), stale)
  base <- setup$release
  base$files <- c(base$files, list(entry))
  with_stale <- atlas_write_release(setup$store, "draft", base$files, base$index, previous = base$id,
                                    pull = base$pull, quiet = TRUE)
  record <- on_machine(machine(), atlas_finish_release_work(setup$store, with_stale$id, quiet = TRUE))
  expect_true("models/draft/ensemble/taxon-a.json" %in% unlist(record$removed))
  finished <- on_machine(setup$boss, atlas_apply_finish(setup$store, with_stale$id, quiet = TRUE))
  expect_false("models/draft/ensemble/taxon-a.json" %in% vapply(finished$files, `[[`, "", "path"))
})

test_that("a finished release is left alone, and a release that moved on is not overwritten", {
  skip_if_not_installed("terra")
  setup <- published()
  on_machine(machine(), atlas_finish_release_work(setup$store, setup$release$id, quiet = TRUE))
  # Another release became current while the worker ran.
  on_machine(setup$boss, {
    writeLines("newer", atlas_path("occurrences", "name-merges.json"))
    atlas_publish_release(setup$store, quiet = TRUE)
  })
  expect_error(on_machine(setup$boss, atlas_apply_finish(setup$store, setup$release$id, quiet = TRUE)),
               "became current")
  ec2 <- list(run_instances = function(...) stop("should not launch"))
  finished <- list(finished = list(version = ATLAS_FINISH_VERSION))
  store <- setup$store
  current <- atlas_current_release(store)
  current$finished <- finished$finished
  atlas_store_json(store, paste0("releases/draft/", current$id, ".json"), current)
  expect_null(on_machine(setup$boss, atlas_finish_on_ec2(store, ec2 = ec2, config = finish_config(store$uri),
                                                         quiet = TRUE, image_exists = function(i) TRUE)))
})

# ---- on EC2 -------------------------------------------------------------------

# A fake EC2 whose workers finish for real, on a fresh machine, between polls
# (with the counting and the index stubbed: those are tested above), or are
# lost without reporting when `lose` says so.
finish_ec2 <- function(store, lose = function(attempt) FALSE) {
  state <- new.env()
  state$instances <- list()
  state$requests <- list()
  tag <- function(tags, key) Filter(function(t) t$Key == key, tags)[[1]]$Value
  client <- list(
    run_instances = function(...) {
      request <- list(...)
      state$requests[[length(state$requests) + 1L]] <- request
      tags <- request$TagSpecifications[[1]]$Tags
      id <- sprintf("i-%017d", length(state$instances) + 1L)
      state$instances[[id]] <- list(id = id, job = tag(tags, "atlas-job"), state = "pending",
                                    attempt = as.integer(tag(tags, "atlas-attempt")), tags = tags)
      list(Instances = list(list(InstanceId = id)))
    },
    describe_instances = function(Filters, NextToken = NULL) {
      for (id in names(state$instances)) {
        w <- state$instances[[id]]
        if (w$state != "pending") next
        if (!lose(w$attempt)) {
          on_machine(machine(), atlas_finish_release_work(
            store, sub("^finish-", "", w$job), quiet = TRUE,
            count = function(...) 0L,
            build_index = function(grid, quiet) {
              dir.create(dirname(atlas_here_index_path(grid)), recursive = TRUE, showWarnings = FALSE)
              saveRDS(list(stub = TRUE), atlas_here_index_path(grid))
            }
          ))
        }
        state$instances[[id]]$state <- "terminated"
      }
      job <- Filters[[1]]$Values[[1]]
      mine <- Filter(function(i) identical(i$job, job), state$instances)
      list(Reservations = list(list(Instances = unname(lapply(mine, function(i) {
        list(InstanceId = i$id, State = list(Name = i$state), Tags = i$tags)
      })))))
    },
    terminate_instances = function(InstanceIds) list()
  )
  list(client = client, state = state)
}

run_finish <- function(setup, ec2, now = as.POSIXct("2026-01-01", tz = "UTC")) {
  on_machine(setup$boss, atlas_finish_on_ec2(
    setup$store, ec2 = ec2$client, config = finish_config(setup$store$uri), poll_seconds = 60,
    wait = function(s) now <<- now + s, clock = function() now, quiet = TRUE,
    image_exists = function(image) TRUE
  ))
}

test_that("the box finishes an unfinished release on one EC2 worker that runs finish-release", {
  skip_if_not_installed("terra")
  setup <- published()
  ec2 <- finish_ec2(setup$store)
  finished <- run_finish(setup, ec2)
  expect_true(atlas_release_finished(finished))
  expect_length(ec2$state$requests, 1L)
  script <- rawToChar(jsonlite::base64_dec(ec2$state$requests[[1]]$UserData))
  expect_match(script, paste0("finish-release --grid=draft --release=", setup$release$id), fixed = TRUE)
  expect_false(grepl("run-shard", script, fixed = TRUE))
})

test_that("a finishing worker lost without reporting is launched again", {
  skip_if_not_installed("terra")
  setup <- published()
  ec2 <- finish_ec2(setup$store, lose = function(attempt) attempt == 1L)
  finished <- run_finish(setup, ec2)
  expect_true(atlas_release_finished(finished))
  expect_length(ec2$state$requests, 2L)
})

test_that("finishing gives up after its attempts, and the release stays as it was", {
  skip_if_not_installed("terra")
  setup <- published()
  ec2 <- finish_ec2(setup$store, lose = function(attempt) TRUE)
  expect_error(run_finish(setup, ec2), "without reporting")
  expect_equal(atlas_current_release(setup$store)$id, setup$release$id)
})

test_that("a night with nothing to fit still finishes a release that never was", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(TAXA)))
  full_cycle(store, boss)
  ec2 <- finish_ec2(store)
  now <- as.POSIXct("2026-01-01", tz = "UTC")
  result <- on_machine(boss, atlas_nightly(
    pull = FALSE, algorithms = c("maxnet", "rf"), config = finish_config(store$uri), store = store,
    ec2 = ec2$client, quiet = TRUE, poll_seconds = 60, wait = function(s) now <<- now + s,
    clock = function() now, image_exists = function(image) TRUE
  ))
  expect_true(atlas_release_finished(atlas_current_release(store)))
  expect_length(ec2$state$requests, 1L)
})

test_that("finishing files the weak maps' ranks privately, through the box, never in the release", {
  skip_if_not_installed("terra")
  setup <- published()
  # A weak map beside the strong one.
  weak_release <- on_machine(setup$boss, {
    northwest_model()
    tif <- atlas_model_path("Taxon A", "draft", ".tif", "rf")
    dir.create(dirname(tif), recursive = TRUE, showWarnings = FALSE)
    file.copy(atlas_model_path("Taxon A", "draft", ".tif"), tif, overwrite = TRUE)
    atlas_write_json(list(taxon = "Taxon A", algorithm = "rf", grade = "weak", presences = 25,
                          raster = basename(tif), map = "x.png", built_at = "2026-10-06T00:00:00Z"),
                     atlas_model_path("Taxon A", "draft", ".json", "rf"))
    atlas_publish_release(setup$store, quiet = TRUE)
  })
  record <- on_machine(machine(), atlas_finish_release_work(setup$store, weak_release$id, quiet = TRUE))
  expect_equal(vapply(record$private, `[[`, "", "name"), "weak-ranks.tsv.gz")
  expect_false(any(grepl("weak|unpublished", vapply(record$files, `[[`, "", "path"))))
  finished <- on_machine(setup$boss, atlas_apply_finish(setup$store, weak_release$id, quiet = TRUE))
  key <- paste("private/atlas-weak", finished$id, "draft/weak-ranks.tsv.gz", sep = "/")
  expect_true(setup$store$exists(key))
  expect_false(any(grepl("weak|unpublished", vapply(finished$files, `[[`, "", "path"))))
})
