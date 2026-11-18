# Fits that failed, and are not planned again for the same records.
#
# A fit that fails keeps its previous model (R/jobs.R, atlas_finish_job), and
# its record set still differs from the one that model was fitted on, so every
# plan used to list it again. A failure inside the fit itself (one a step
# named, R/fit.R atlas_fit_stage) fails the same way on the same records and
# settings: fits are deterministic on one processor family (E12). So such a
# failure is recorded against the record set and settings it was made for,
# like a refusal, and the planner leaves it out until either changes.
#
# A failure the fit did not name (a lost worker, a machine out of memory, a
# task never run) is not recorded: the next plan tries it again, as before.
#
# The record is kept privately in the store, one file per grid, and never in
# a release: it holds record-set fingerprints.
#
#   private/failed-refits/<grid>.json   list of {taxon, algorithm, fingerprint,
#                                       settings_key, stage, error, job,
#                                       recorded_at}
#
# To fit one again on the same records, delete its entry.

ATLAS_FAILED_REFITS_PREFIX <- "private/failed-refits"

# Failures a bigger or less busy machine might not have: never recorded.
ATLAS_FIT_RESOURCE_ERRORS <- "cannot allocate|memory exhausted|vector memory|out of memory"

atlas_failed_refits_key <- function(grid = "draft") {
  paste0(ATLAS_FAILED_REFITS_PREFIX, "/", grid, ".json")
}

#' The recorded failures for a grid, by "algorithm|taxon". Empty when none.
atlas_read_failed_refits <- function(store, grid = "draft") {
  key <- atlas_failed_refits_key(grid)
  if (!isTRUE(store$exists(key))) return(list())
  entries <- atlas_store_text(store, key)
  out <- list()
  for (e in entries %||% list()) out[[paste(e$algorithm, e$taxon, sep = "|")]] <- e
  out
}

#' Whether a recorded failure still holds for these records and settings.
atlas_failed_refit_current <- function(entry, fingerprint, settings_key) {
  !is.null(entry) &&
    identical(as.character(entry$fingerprint %||% ""), as.character(fingerprint)) &&
    identical(as.character(entry$settings_key %||% ""), as.character(settings_key))
}

#' Whether a shard result is a failure to record: inside the fit, at a named
#' step, for known records and settings, and not for want of memory.
atlas_failed_refit_recordable <- function(result) {
  identical(result$status, "failed") &&
    is.character(result$stage) && length(result$stage) == 1L && nzchar(result$stage) &&
    is.character(result$fingerprint) && length(result$fingerprint) == 1L &&
    is.character(result$settings_key) && length(result$settings_key) == 1L &&
    !grepl(ATLAS_FIT_RESOURCE_ERRORS, as.character(result$error %||% ""), ignore.case = TRUE)
}

#' Update the record from a finished job's results: a recordable failure is
#' recorded (or replaces the last one for its taxon and algorithm); a fit or a
#' refusal clears any earlier one. Returns the entries recorded by this job.
atlas_record_failed_refits <- function(store, grid, job_id, results) {
  recorded <- atlas_read_failed_refits(store, grid)
  before <- recorded
  added <- list()
  for (r in results) {
    key <- paste(r$algorithm, r$taxon, sep = "|")
    if (r$status %in% c("fitted", "refused")) {
      recorded[[key]] <- NULL
    } else if (atlas_failed_refit_recordable(r)) {
      entry <- list(
        taxon = r$taxon, algorithm = r$algorithm, fingerprint = r$fingerprint,
        settings_key = r$settings_key, stage = r$stage, error = r$error %||% NULL, job = job_id,
        recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      )
      recorded[[key]] <- entry
      added[[key]] <- entry
    }
  }
  if (!identical(names(recorded), names(before)) || length(added)) {
    atlas_store_json(store, atlas_failed_refits_key(grid), unname(recorded))
  }
  invisible(added)
}
