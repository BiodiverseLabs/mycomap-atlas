# A deposit's maps are drawn in whole 50 km blocks in the bundle's own tree
# (R/archiveblocks.R): the stored release and this machine's data stay as
# they are, scores change in bounds and regions only, and the prior and
# Explore tables only lose rows.

# A release on one machine whose maps of Taxon A (maxnet and rf) and Taxon B
# are drawn as their fits drew them, with full views, the Explore index and
# the prior built from them, the job that fitted them in the store, and
# unknown giving Taxon B a record set no pull holds.
deposit_published <- function(unknown = FALSE) {
  store <- fresh_store()
  boss <- machine()
  release <- on_machine(boss, {
    occurrences <- synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30))
    orchestrator_data(occurrences)
    big <- terra::rast(getOption("atlas.block_land"))
    points <- atlas_occurrence_points(occurrences, "draft")
    for (model in list(c("Taxon A", "maxnet"), c("Taxon A", "rf"), c("Taxon B", "maxnet"))) {
      name <- model[[1]]; algorithm <- model[[2]]
      area <- atlas_block_area(name, points, big, 500, ATLAS_SITE_KM)
      window <- terra::crop(big, terra::ext(area))
      xy <- terra::xyFromCell(window, seq_len(terra::ncell(window)))
      r <- window
      terra::values(r) <- (xy[, 1] - min(xy[, 1])) / diff(range(xy[, 1])) * (if (algorithm == "rf") 0.9 else 1)
      r <- terra::mask(r, area)
      names(r) <- "suitability"
      dir.create(atlas_model_dir("draft", algorithm), recursive = TRUE, showWarnings = FALSE)
      tif <- atlas_model_path(name, "draft", ".tif", algorithm)
      terra::writeRaster(r, tif, overwrite = TRUE)
      index <- r
      terra::values(index) <- ifelse(is.na(terra::values(r, mat = FALSE)), NA, 0.2)
      terra::writeRaster(index, sub("[.]tif$", ".di.tif", tif), overwrite = TRUE)
      file.copy(tif, sub("[.]tif$", ".full.tif", tif))
      file.copy(sub("[.]tif$", ".di.tif", tif), sub("[.]tif$", ".full.di.tif", tif))
      drawn <- atlas_write_map_png(r, sub("[.]tif$", ".png", tif))
      file.copy(drawn$path, sub("[.]png$", ".full.png", drawn$path))
      xy_cells <- atlas_public_cells_table(occurrences)
      mine <- xy_cells[xy_cells$taxon == name, ]
      a <- atlas_albers(mine$lat, mine$lng)
      regions <- atlas_region_counts(tif, a[, "x"], a[, "y"])
      regions$from <- "collection cells"
      fingerprint <- if (unknown && name == "Taxon B") "0000000" else unname(atlas_fingerprints_for(occurrences, name))
      atlas_write_json(list(taxon = name, algorithm = algorithm, skill = "passed", grade = "strong", presences = 25,
                            auc_mean = 0.81, null = list(p = 0.01), fingerprint = fingerprint,
                            settings = list(buffer_km = 500, thin_km = ATLAS_SITE_KM),
                            applicability = list(threshold = 0.5),
                            raster = basename(tif), map = basename(drawn$path), bounds = drawn$bounds,
                            md5 = unname(tools::md5sum(tif)), regions = regions,
                            built_at = "2026-10-06T00:00:00Z"),
                       sub("[.]tif$", ".json", tif))
    }
    atlas_build_ensembles(grid = "draft", quiet = TRUE)
    atlas_build_finish_indexes(grid = "draft", quiet = TRUE)
    pull <- atlas_file_entries(file.path("occurrences", "occurrences-20260101T000000Z.tsv.gz"))
    atlas_upload_objects(store, pull)
    atlas_store_json(store, "jobs/draft/20261005T000000Z-job/job.json", list(
      id = "20261005T000000Z-job", created_at = "2026-10-05T00:00:00Z", inputs = pull,
      tasks = list(list(taxon = "Taxon A", algorithm = "maxnet"), list(taxon = "Taxon A", algorithm = "rf"),
                   list(taxon = "Taxon B", algorithm = "maxnet"))
    ))
    atlas_publish_release(store, quiet = TRUE)
  })
  list(store = store, boss = boss, release = release)
}

on_block_line <- function(v, origin) {
  m <- ATLAS_BLOCK_KM * 1000
  abs(((v - origin) / m) - round((v - origin) / m)) < 1e-9
}

# Every file under a directory, by path, with its hash.
tree_hashes <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  stats::setNames(vapply(file.path(dir, files), atlas_sha256, ""), files)
}

unpacked <- function(bundle) {
  dir <- tempfile("unpacked-")
  dir.create(dir)
  for (name in names(bundle$sources)) {
    source <- bundle$sources[[name]]
    if (grepl("[.]tar([.]gz)?$", name)) utils::untar(source, exdir = dir) else file.copy(source, file.path(dir, name))
  }
  dir
}

gz_lines <- function(path) readLines(gzfile(path), warn = FALSE)

test_that("a deposit draws its maps in whole blocks in its own tree, and leaves the store and this machine's data as they were", {
  skip_if_not_installed("terra")
  setup <- deposit_published()
  store_root <- sub("^file://", "", setup$store$uri)
  before_store <- tree_hashes(store_root)
  out <- on_machine(machine(), {
    before_data <- tree_hashes(atlas_data_dir())
    bundle <- atlas_archive_models_bundle(setup$store, "draft", quiet = TRUE)
    plain <- atlas_archive_models_bundle(setup$store, "draft", blocks = FALSE)
    list(bundle = bundle, plain = plain, before_data = before_data, after_data = tree_hashes(atlas_data_dir()))
  })
  expect_identical(tree_hashes(store_root), before_store)
  expect_identical(out$after_data, out$before_data)
  expect_equal(out$bundle$trimmed$maps, 3L)

  got <- unpacked(out$bundle)
  was <- unpacked(out$plain)
  stored <- function(path) on_machine(setup$boss, jsonlite::fromJSON(atlas_path(path), simplifyVector = FALSE))
  for (path in c("models/draft/taxon-a.json", "models/draft/rf/taxon-a.json", "models/draft/taxon-b.json")) {
    tif <- sub("[.]json$", ".tif", path)
    e <- terra::ext(terra::rast(file.path(got, tif)))
    expect_true(on_block_line(terra::xmin(e), ATLAS_GRID_EXTENT[["xmin"]]), info = path)
    expect_true(on_block_line(terra::ymax(e), ATLAS_GRID_EXTENT[["ymax"]]), info = path)
    expect_lt(sum(!is.na(terra::values(terra::rast(file.path(got, tif))))),
              sum(!is.na(terra::values(terra::rast(file.path(was, tif))))))
    # Scores: exactly bounds and regions differ from the release's, as published.
    deposited <- jsonlite::fromJSON(file.path(got, path), simplifyVector = FALSE)
    published <- jsonlite::fromJSON(file.path(was, path), simplifyVector = FALSE)
    same <- setdiff(union(names(deposited), names(published)), c("bounds", "regions"))
    expect_identical(deposited[same], published[same], info = path)
    expect_false(identical(deposited$bounds, published$bounds), info = path)
    expect_false(identical(deposited$regions$cells, published$regions$cells), info = path)
    # regions counts the trimmed map's own cells.
    cells <- utils::read.delim(gzfile(file.path(was, "collection-cells-0.1deg.tsv.gz")), stringsAsFactors = FALSE)
    mine <- cells[cells$taxon == deposited$taxon, ]
    a <- atlas_albers(mine$lat, mine$lng)
    expect_equal(lapply(deposited$regions$cells, function(x) as.integer(unlist(x))),
                 lapply(atlas_region_counts(file.path(got, tif), a[, "x"], a[, "y"])$cells, as.integer), info = path)
    # Full views are carried over as they are.
    for (full in paste0(sub("[.]json$", "", path), c(".full.tif", ".full.png"))) {
      expect_identical(atlas_sha256(file.path(got, full)), atlas_sha256(file.path(was, full)), info = full)
    }
    expect_identical(published[same], stored(path)[intersect(same, names(stored(path)))], info = path)
  }

  # The combined map is drawn in its taxon's blocks; its scores differ in bounds only.
  expect_equal(out$bundle$trimmed$ensembles, 1L)
  combined <- "models/draft/ensemble/taxon-a"
  e <- terra::ext(terra::rast(file.path(got, paste0(combined, ".tif"))))
  expect_true(on_block_line(terra::xmin(e), ATLAS_GRID_EXTENT[["xmin"]]))
  expect_true(on_block_line(terra::ymax(e), ATLAS_GRID_EXTENT[["ymax"]]))
  dep <- jsonlite::fromJSON(file.path(got, paste0(combined, ".json")), simplifyVector = FALSE)
  pub <- jsonlite::fromJSON(file.path(was, paste0(combined, ".json")), simplifyVector = FALSE)
  same <- setdiff(union(names(dep), names(pub)), "bounds")
  expect_identical(dep[same], pub[same])
  expect_false(identical(dep$bounds, pub$bounds))
  expect_false(identical(atlas_sha256(file.path(got, paste0(combined, ".png"))),
                         atlas_sha256(file.path(was, paste0(combined, ".png")))))

  # The prior and Explore tables only lose rows; every kept row is as it was.
  for (table in c("prior-ranks.tsv.gz", "prior-aoa.tsv.gz", "explore-index-20km.tsv.gz")) {
    kept <- gz_lines(file.path(got, table))
    all_rows <- gz_lines(file.path(was, table))
    expect_identical(kept[[1]], all_rows[[1]], info = table)
    expect_true(all(kept[-1] %in% all_rows[-1]), info = table)
    expect_identical(kept[-1], all_rows[-1][all_rows[-1] %in% kept[-1]], info = table)
    expect_lt(length(kept), length(all_rows))
  }
  # Every other file is carried over byte for byte.
  differ <- c("release.json", "prior-ranks.tsv.gz", "prior-aoa.tsv.gz", "prior-ranks.parquet", "prior-aoa.parquet",
              "prior-grid.json", "explore-index-20km.tsv.gz", "explore-index-20km.json")
  carried <- setdiff(intersect(names(out$bundle$sources), names(out$plain$sources)),
                     c(differ, grep("^(maps-|scores)", names(out$bundle$sources), value = TRUE)))
  expect_gt(length(carried), 0L)
  for (name in carried) {
    expect_identical(atlas_sha256(out$bundle$sources[[name]]), atlas_sha256(out$plain$sources[[name]]), info = name)
  }
  release <- jsonlite::fromJSON(out$bundle$sources[["release.json"]], simplifyVector = FALSE)
  expect_equal(release$trimmed$blocks_km, ATLAS_BLOCK_KM)
  expect_match(release$trimmed$what, "whole 50 km square lies inside the accessible area")
})

test_that("a deposit with a map whose area cannot be built again is not built", {
  skip_if_not_installed("terra")
  setup <- deposit_published(unknown = TRUE)
  on_machine(machine(), {
    expect_error(atlas_archive_models_bundle(setup$store, "draft", quiet = TRUE),
                 "the deposit is not built: 1 maps could not be drawn in blocks \\(1 whose record set")
  })
})

test_that("a bundle kept by a build-only run is deposited later exactly as built, and a changed file stops it", {
  skip_if_not_installed("terra")
  setup <- deposit_published()
  on_machine(machine(), {
    bundle <- atlas_archive_models_bundle(setup$store, "draft", blocks = FALSE)
    kept <- tempfile("kept-")
    atlas_archive_keep_bundle(bundle, kept)
    again <- atlas_archive_read_kept_bundle(kept)
    expect_identical(vapply(again$sources, atlas_sha256, ""), vapply(bundle$sources, atlas_sha256, ""))
    expect_identical(again$version, bundle$version)
    expect_identical(again$key, bundle$key)
    expect_error(atlas_archive_keep_bundle(bundle, kept), "not empty")
    # A commit that was null comes back from JSON as an empty list; the README is still written.
    again$release$commit <- list()
    readme <- atlas_archive_readme(again, atlas_archive_file_table(again$sources))
    expect_true(any(grepl("^Code: https://github.com/BiodiverseLabs/mycomap-atlas$", readme)))
    cat("x", file = again$sources[["release.json"]], append = TRUE)
    expect_error(atlas_archive_read_kept_bundle(kept), "release.json does not match its SHA256SUMS")
  })
})

test_that("a build-only run reads no Zenodo token", {
  withr::local_envvar(ZENODO_TOKEN = "")
  z <- atlas_flag_zenodo(list(keep_bundle = "somewhere"))
  expect_null(z$call)
  expect_error(atlas_flag_zenodo(list()), "ZENODO_TOKEN")
})

test_that("a bundle built on a worker is kept privately by the box and deposited from there as built", {
  skip_if_not_installed("terra")
  setup <- deposit_published()
  config <- list(max_hours = 3, store = setup$store$uri)
  asked <- NULL
  local_mocked_bindings(atlas_one_worker_on_ec2 = function(store, id, grid, command, label, config, hours, ...) {
    asked <<- list(id = id, command = command, hours = hours)
    on_machine(machine(), atlas_archive_build_work(store, setup$release$id, grid, quiet = TRUE))
  })
  keys <- on_machine(setup$boss, atlas_archive_build_on_ec2(setup$store, setup$release$id, "draft", config = config,
                                                            quiet = TRUE))
  expect_equal(asked$hours, 3)
  expect_equal(asked$id, paste0("archive-", setup$release$id))
  expect_match(asked$command, paste0("^archive-build --grid=draft --release=", setup$release$id))
  expect_true(all(startsWith(keys, paste0("private/archive-build/draft/", setup$release$id, "/"))))
  expect_true(all(c("SHA256SUMS", "bundle.json", "release.json") %in% basename(keys)))
  on_machine(machine(), {
    kept <- atlas_archive_read_kept_bundle(atlas_archive_fetch_build(setup$store, setup$release$id, "draft"))
    direct <- atlas_archive_models_bundle(setup$store, "draft", quiet = TRUE)
    expect_identical(vapply(kept$sources, atlas_sha256, ""), vapply(direct$sources, atlas_sha256, ""))
    expect_equal(kept$version, direct$version)
  })
})

test_that("a bundle build's worker is given no Zenodo token", {
  withr::local_envvar(ZENODO_TOKEN = "zenodo-secret-for-the-test")
  config <- list(store = "s3://bucket/atlas", region = "us-east-2", image = "atlas:test", max_hours = 3,
                 gb_per_fit = 3)
  script <- atlas_worker_user_data("archive-r1", 1L, "draft", config, command = atlas_archive_build_command("r1"))
  expect_false(grepl("ZENODO", script, ignore.case = TRUE))
  expect_false(grepl("zenodo-secret-for-the-test", script, fixed = TRUE))
  expect_match(script, "archive-build --grid=draft --release=r1")
})

test_that("a deposit fetches the release's layers into a directory of its own, never into this machine's data", {
  withr::local_options(atlas.block_land = NULL)
  local_mocked_bindings(atlas_block_land_file = function(store, grid, layers_key) {
    path <- atlas_path("blocks", grid, "complete-cases.tif", create = TRUE)
    writeLines("land", path)
    path
  })
  on_machine(machine(), {
    dir.create(atlas_data_dir(), recursive = TRUE, showWarnings = FALSE)
    before <- tree_hashes(atlas_data_dir())
    own <- tempfile("deposit-")
    path <- atlas_archive_block_land(fresh_store(), "draft", "key", own)
    expect_true(startsWith(normalizePath(path, winslash = "/"), normalizePath(own, winslash = "/")))
    expect_identical(tree_hashes(atlas_data_dir()), before)
  })
})

test_that("the Zenodo token is read from the file ZENODO_TOKEN_FILE names, and a missing, empty or odd file refuses", {
  token <- paste(rep("t0Ken", 12), collapse = "")
  file <- tempfile()
  writeBin(charToRaw(token), file)
  expect_identical(atlas_zenodo_token(file = file, env = "from-env"), token)
  expect_identical(atlas_zenodo_token(file = "", env = "from-env"), "from-env")
  expect_error(atlas_zenodo_token(file = tempfile(), env = ""), "names a file that is not there")
  empty <- tempfile(); file.create(empty)
  expect_error(atlas_zenodo_token(file = empty, env = ""), "is empty")
  crlf <- tempfile(); writeBin(charToRaw(paste0(token, "\r\n")), crlf)
  err <- tryCatch(atlas_zenodo_token(file = crlf, env = ""), error = conditionMessage)
  expect_match(err, "line ends")
  expect_false(grepl(token, err, fixed = TRUE))
  withr::local_envvar(ZENODO_TOKEN_FILE = file, ZENODO_TOKEN = "")
  expect_false(is.null(atlas_zenodo("sandbox", transport = function(...) list(status = 200L, body = list()))$call))
})

test_that("the token never appears in a message or an error, whatever Zenodo or the network answers", {
  token <- paste(rep("s3cr", 15), collapse = "")
  echo <- function(method, url, token, json, file) list(status = 400L, body = list(message = paste("bad token", token),
                                                                                    errors = list(list(field = token, messages = list(token)))))
  boom <- function(method, url, token, json, file) stop("could not connect with Authorization: Bearer ", token)
  for (transport in list(echo, boom)) {
    z <- atlas_zenodo("sandbox", token = token, transport = transport, waits = c(0, 0), sleep = function(s) NULL)
    said <- character()
    err <- withCallingHandlers(
      tryCatch(z$call("GET", "/deposit/depositions"), error = conditionMessage),
      message = function(m) { said <<- c(said, conditionMessage(m)); invokeRestart("muffleMessage") }
    )
    expect_false(grepl(token, err, fixed = TRUE))
    expect_false(any(grepl(token, said, fixed = TRUE)))
    expect_match(err, "Zenodo answered")
  }
})

test_that("a kept bundle is staged only where the disk has room for it, and the archive build holds the orchestrator lock", {
  skip_if_not_installed("terra")
  setup <- deposit_published()
  local_mocked_bindings(atlas_one_worker_on_ec2 = function(store, id, grid, ...) {
    on_machine(machine(), atlas_archive_build_work(store, setup$release$id, grid, quiet = TRUE))
  })
  on_machine(setup$boss, {
    # A second orchestrator is refused while one holds the lock.
    held <- tryCatch(atlas_with_orchestrator_lock("nightly", 6, {
      atlas_archive_build_on_ec2(setup$store, setup$release$id, "draft", config = list(max_hours = 3), quiet = TRUE)
    }), error = conditionMessage)
    expect_match(held, "nightly has held the box's orchestrator lock")
    atlas_archive_build_on_ec2(setup$store, setup$release$id, "draft", config = list(max_hours = 3), quiet = TRUE)
    dir <- tempfile("staged-")
    expect_error(atlas_archive_fetch_build(setup$store, setup$release$id, "draft", dir = dir, free = function(d) 1e6),
                 "needs .* GB with its margin and the disk has 0.0 GB free; nothing done")
    expect_false(dir.exists(dir))
    staged <- atlas_archive_fetch_build(setup$store, setup$release$id, "draft", dir = dir, free = function(d) 1e12)
    expect_true(file.exists(file.path(staged, "SHA256SUMS")))
  })
})

test_that("a deposit from a kept build removes its staged copy when it ends", {
  skip_if_not_installed("terra")
  setup <- deposit_published()
  local_mocked_bindings(atlas_one_worker_on_ec2 = function(store, id, grid, ...) {
    on_machine(machine(), atlas_archive_build_work(store, setup$release$id, grid, quiet = TRUE))
  })
  on_machine(setup$boss, {
    atlas_archive_build_on_ec2(setup$store, setup$release$id, "draft", config = list(max_hours = 3), quiet = TRUE)
    with_env(c(ATLAS_STORE = setup$store$uri), {
      suppressMessages(atlas_main(c("archive-release", "--only=models", paste0("--from-build=", setup$release$id),
                                    "--dry-run")))
    })
    expect_false(dir.exists(atlas_archive_staging_dir(setup$release$id)))
  })
})
