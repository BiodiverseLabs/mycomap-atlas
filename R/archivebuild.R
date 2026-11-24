# A models bundle built on one EC2 worker, kept privately, and deposited from
# the box later (R/archive.R, R/archiveblocks.R).
#
# Drawing every map of a release in blocks is more than the box's two cores
# should do, so the bundle is built on one worker, as finishing is: the box
# launches it (archive-build-ec2), the worker builds the bundle with nothing
# but the store and uploads its files as objects with a record of them
# (archive-build), and the box files them under the store's private prefix,
# which a worker may not write. The worker reads no Zenodo token and is given
# none: its container gets the store, the region and its instance type only
# (atlas_worker_user_data). The deposit runs on the box afterwards from the
# kept files (archive-release --from-build), checked against their sums.

ATLAS_ARCHIVE_BUILD_PREFIX <- "private/archive-build"

#' The job id a bundle build goes under.
atlas_archive_build_id <- function(release) paste0("archive-", release)

#' Where a release's kept bundle is filed in the store.
atlas_archive_build_prefix <- function(release, grid = "draft") {
  paste(ATLAS_ARCHIVE_BUILD_PREFIX, grid, release, "", sep = "/")
}

#' The worker's command for a bundle build: the archive's own build, kept.
atlas_archive_build_command <- function(release, grid = "draft") {
  sprintf("archive-build --grid=%s --release=%s --workers=$WORKERS", grid, release)
}

#' On the worker: build a release's models bundle, keep it, upload its files
#' as objects and write the record the box files them from.
atlas_archive_build_work <- function(store, release, grid = "draft", workers = 1L, quiet = FALSE) {
  started <- Sys.time()
  bundle <- atlas_archive_models_bundle(store, grid, release, workers = workers, quiet = quiet)
  on.exit(unlink(dirname(bundle$dir), recursive = TRUE), add = TRUE)
  kept <- atlas_path("archive-build", grid, release)
  unlink(kept, recursive = TRUE)
  atlas_archive_keep_bundle(bundle, kept)
  root <- normalizePath(atlas_data_dir(), winslash = "/")
  paths <- substring(normalizePath(list.files(kept, full.names = TRUE), winslash = "/"), nchar(root) + 2L)
  entries <- atlas_file_entries(paths)
  uploaded <- atlas_upload_objects(store, entries)
  id <- atlas_archive_build_id(release)
  record <- list(
    job = id, shard = 1L, release = release, version = bundle$version,
    started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    files = lapply(entries, function(e) list(name = basename(e$path), sha256 = e$sha256, bytes = e$bytes))
  )
  atlas_store_json(store, atlas_shard_key(id, 1L, grid), record)
  if (!isTRUE(quiet)) {
    message("models bundle of ", release, ": ", length(entries), " files kept, ", uploaded$count, " uploaded (",
            round(uploaded$bytes / 1048576, 1), " MB)")
  }
  invisible(record)
}

#' On the box: file a worker's kept bundle under the store's private prefix.
atlas_archive_place_build <- function(store, release, grid = "draft") {
  record <- atlas_store_text(store, atlas_shard_key(atlas_archive_build_id(release), 1L, grid))
  if (is.null(record)) stop("no bundle build of ", release, " has reported", call. = FALSE)
  prefix <- atlas_archive_build_prefix(release, grid)
  for (f in record$files) {
    file <- tempfile()
    store$get(atlas_object_key(f$sha256), file)
    if (!identical(atlas_sha256(file), f$sha256)) stop("the store's copy of ", f$name, " does not match its hash",
                                                       call. = FALSE)
    store$put(paste0(prefix, f$name), file)
    unlink(file)
  }
  invisible(paste0(prefix, vapply(record$files, `[[`, "", "name")))
}

#' On the box: build a release's models bundle on one EC2 worker, by hours
#' (config$max_hours, ATLAS_EC2_MAX_HOURS, unless given), and file it
#' privately. The worker runs on ATLAS_EC2_FINISH_MARKET and
#' ATLAS_EC2_INSTANCE_TYPES, as a finishing worker does. Returns the keys.
atlas_archive_build_on_ec2 <- function(store, release, grid = "draft", config = atlas_ec2_config(),
                                       hours = config$max_hours, quiet = FALSE, ...) {
  if (is.null(atlas_store_text(store, paste0("releases/", grid, "/", release, ".json")))) {
    stop("no release ", release, " on the ", grid, " grid", call. = FALSE)
  }
  atlas_one_worker_on_ec2(store, atlas_archive_build_id(release), grid,
                          command = atlas_archive_build_command(release, grid),
                          label = paste("the models bundle of", release), config = config,
                          hours = hours, quiet = quiet, ...)
  keys <- atlas_archive_place_build(store, release, grid)
  if (!isTRUE(quiet)) message("models bundle of ", release, " kept under ", atlas_archive_build_prefix(release, grid))
  invisible(keys)
}

#' On the box: bring a kept bundle from the store into dir, for
#' archive-release --from-build.
atlas_archive_fetch_build <- function(store, release, grid = "draft", dir = tempfile("atlas-kept-")) {
  prefix <- atlas_archive_build_prefix(release, grid)
  keys <- store$list(prefix)
  if (!length(keys)) stop("no kept bundle of ", release, " in the store", call. = FALSE)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (key in keys) store$get(key, file.path(dir, sub(prefix, "", key, fixed = TRUE)))
  dir
}
