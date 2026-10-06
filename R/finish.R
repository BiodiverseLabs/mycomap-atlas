# Finishing a release: what needs every map at once.
#
# A job's workers each fit a share of the models, so nothing they make can
# depend on all of them. Two products do: the "what could grow here" index
# (R/here.R), built from every map that beat its null models, and each map's
# counts by state (R/predictions.R), which maps drawn before those counts
# existed lack. Until this step the index was built only by hand, and no
# release made by a job ever carried one, so the Explore page had nothing to
# answer from.
#
# The always-on box keeps no rasters and does no processing, so one more EC2
# worker does it. It pulls the release with its rasters, counts what is
# uncounted, builds the index, uploads what changed and reports it in a shard
# record, as a fitting worker does. Workers may not write releases; the box
# reads the record and writes the finished release. The nightly run finishes
# whatever current release is not marked finished, so a night with nothing to
# fit still finishes a release that never was.

# Raised whenever finishing comes to add something new, so that every
# release is finished again under the new rule.
ATLAS_FINISH_VERSION <- 1L

#' Whether a release has been finished under the current rule.
atlas_release_finished <- function(release) {
  identical(as.integer(release$finished$version %||% 0L), ATLAS_FINISH_VERSION)
}

#' The job id a finishing run goes under: its own, so its worker and record
#' never mix with a fitting job's.
atlas_finish_id <- function(release_id) paste0("finish-", release_id)

#' On the worker: finish one release and report what changed.
#'
#' Pulls the release with its rasters, counts every map not yet counted by
#' state, builds the index, uploads the files that changed and writes the
#' record the box turns into the finished release. count and build_index are
#' replaceable for tests.
atlas_finish_release_work <- function(store = atlas_store(), release, grid = "draft", workers = 1L,
                                      quiet = FALSE, count = atlas_count_regions,
                                      build_index = atlas_build_here_index) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  started <- Sys.time()
  manifest <- atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  atlas_pull_release(store, grid, release = release, rasters = TRUE, quiet = quiet)

  counted <- count(grid = grid, workers = workers, only_missing = TRUE, quiet = quiet)
  build_index(grid = grid, quiet = quiet)

  # What differs from the release: counted metrics and the new index.
  published <- stats::setNames(vapply(manifest$files, function(f) f$sha256, ""),
                               vapply(manifest$files, function(f) f$path, ""))
  root <- atlas_data_dir()
  metrics <- unlist(lapply(names(ATLAS_ALGORITHMS), function(a) {
    list.files(atlas_model_dir(grid, a), pattern = "[.]json$", full.names = TRUE)
  }), use.names = FALSE)
  candidates <- substring(normalizePath(c(metrics, atlas_here_index_path(grid)), winslash = "/", mustWork = FALSE),
                          nchar(normalizePath(root, winslash = "/")) + 2L)
  candidates <- candidates[file.exists(file.path(root, candidates))]
  entries <- atlas_file_entries(candidates)
  changed <- Filter(function(e) !identical(unname(published[e$path]), e$sha256), entries)
  uploaded <- atlas_upload_objects(store, changed)

  id <- atlas_finish_id(release)
  record <- list(
    job = id, shard = 1L, release = release, version = ATLAS_FINISH_VERSION,
    started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    counted = as.integer(counted %||% 0L),
    files = changed
  )
  atlas_store_json(store, atlas_shard_key(id, 1L, grid), record)
  say("finished release ", release, ": counted ", record$counted, " maps by state, built the index; ",
      length(changed), " files changed, ", uploaded$count, " uploaded (",
      round(uploaded$bytes / 1048576, 1), " MB)")
  invisible(record)
}

#' On the box: turn a finishing worker's record into the finished release.
#'
#' The release is the one the worker started from, with the files it changed
#' put in and everything else, its model index and its pull, kept. Refuses if
#' another release became current in between: finishing that one is the next
#' night's work.
atlas_apply_finish <- function(store = atlas_store(), release, grid = "draft", quiet = FALSE) {
  id <- atlas_finish_id(release)
  record <- atlas_store_text(store, atlas_shard_key(id, 1L, grid))
  base <- atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  current <- atlas_current_release(store, grid)
  if (!identical(current$id, release)) {
    stop("release ", current$id %||% "(none)", " became current while ", release,
         " was being finished; it is finished next time", call. = FALSE)
  }
  files <- list()
  for (f in base$files) files[[f$path]] <- f
  for (f in record$files) files[[f$path]] <- f

  kept <- base[intersect(names(base), c("job", "job_results", "retired", "partial", "unreported_shards"))]
  atlas_write_release(
    store, grid, unname(files), base$index,
    previous = base$id, note = paste("finished", base$id),
    pull = base$pull, layers_key = base$layers_key, promote = TRUE, quiet = quiet,
    extra = c(kept, list(finished = list(
      version = ATLAS_FINISH_VERSION, from = base$id, counted = record$counted,
      changed = length(record$files), at = record$finished_at
    )))
  )
}

#' On the box: finish the current release on an EC2 worker, if it needs it.
#'
#' Returns the finished release, or NULL when there was nothing to finish.
#' Launches one worker, launches it again if it is lost without reporting (up
#' to config$max_attempts), and stops it at the deadline.
atlas_finish_on_ec2 <- function(store, grid = "draft", ec2 = NULL, config = atlas_ec2_config(),
                                poll_seconds = 60, wait = Sys.sleep, quiet = FALSE,
                                clock = Sys.time, hours = config$finish_hours %||% 3,
                                image_exists = atlas_image_exists, ...) {
  say <- function(...) if (!isTRUE(quiet)) message(format(clock(), "%H:%M:%S"), "  ", ...)
  current <- atlas_current_release(store, grid)
  if (is.null(current) || atlas_release_finished(current)) return(invisible(NULL))
  if (identical(image_exists(config$image), FALSE)) {
    stop("the image ", config$image, " is not in its registry, so release ", current$id,
         " could not be finished", call. = FALSE)
  }

  ec2 <- ec2 %||% paws.compute::ec2(config = list(region = config$region))
  id <- atlas_finish_id(current$id)
  deadline <- clock() + hours * 3600
  minutes_left <- function() as.numeric(difftime(deadline, clock(), units = "mins"))
  command <- sprintf("finish-release --grid=%s --release=%s --workers=$WORKERS", grid, current$id)
  reported <- function() store$exists(atlas_shard_key(id, 1L, grid))

  terminate_all <- function() {
    running <- atlas_job_instances(ec2, id)
    running <- running$instance[!running$state %in% ATLAS_EC2_GONE]
    if (length(running)) ec2$terminate_instances(InstanceIds = as.list(running))
  }
  done <- FALSE
  on.exit(if (!done) tryCatch(terminate_all(), error = function(e) NULL), add = TRUE)

  attempts <- 0L
  instance <- NA_character_
  seen <- character()
  repeat {
    if (reported()) break
    if (clock() > deadline) {
      stop("finishing release ", current$id, " ran past its ", hours, " h deadline; its worker was stopped",
           call. = FALSE)
    }
    if (!is.na(instance)) {
      instances <- atlas_job_instances(ec2, id)
      seen <- union(seen, instances$instance)
      state <- instances$state[instances$instance == instance]
      gone <- if (length(state)) state[[1]] %in% ATLAS_EC2_GONE else instance %in% seen
      if (gone && !reported()) {
        if (attempts >= config$max_attempts) {
          stop("finishing release ", current$id, " failed ", attempts, " times without reporting",
               call. = FALSE)
        }
        say("finishing worker ", instance, " is gone without reporting; launching another")
        instance <- NA_character_
      }
    }
    if (is.na(instance)) {
      launched <- atlas_launch_worker(ec2, config, id, 1L, grid, attempts + 1L,
                                      minutes = minutes_left(), say = say, command = command)
      if (!is.null(launched)) {
        attempts <- attempts + 1L
        instance <- launched
        say("finishing release ", current$id, ": launched ", instance)
      }
    }
    wait(poll_seconds)
  }
  release <- atlas_apply_finish(store, current$id, grid, quiet = quiet)
  done <- TRUE
  terminate_all()
  invisible(release)
}
