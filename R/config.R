# Configuration. Anything that differs between a laptop and the release
# container is an environment variable, so the same code runs in both.

#' Directory holding every pulled and derived file. Never committed.
#'
#' Anchored on ATLAS_ROOT rather than the working directory: plumber runs an
#' API file from that file's own directory, so a relative "data" would resolve
#' to inst/plumber/data and the server would report an empty dataset.
atlas_data_dir <- function() {
  explicit <- Sys.getenv("ATLAS_DATA_DIR", unset = "")
  if (nzchar(explicit)) {
    return(explicit)
  }
  root <- Sys.getenv("ATLAS_ROOT", unset = "")
  if (nzchar(root)) file.path(root, "data") else "data"
}

#' A path inside the data directory. With create = TRUE the parent is made.
atlas_path <- function(..., create = FALSE) {
  p <- file.path(atlas_data_dir(), ...)
  if (isTRUE(create)) {
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  }
  p
}

#' SSH host for mycomap.org's read-only SQL route.
atlas_sql_host <- function() {
  Sys.getenv("ATLAS_SQL_HOST", unset = "mycomap-sql")
}

# North American country codes as .org stores them. Puerto Rico records
# sometimes carry a blank country with the state spelled out, so that case is
# handled separately in the occurrence query.
ATLAS_NA_COUNTRIES <- c("US", "CA", "MX", "PR", "VI")

# An iNaturalist record placed no better than this (metres) is left out of
# the pull. Releases are fitted on the draft grid's 5 km cells, with sites at
# least 5 km apart (ATLAS_SITE_KM), so a point within 2 km mostly lies in its
# own cell (Steve, 2026-11-19: 2 km, from 1 km). Records with no accuracy
# recorded are kept: on iNaturalist a missing value usually means the app did
# not store one, not that the location is poor. Each pull records the value
# it used (max_accuracy_m in its manifest and its release's pull summary).
ATLAS_MAX_ACCURACY_M <- 2000
# The cutoff of every pull made before pulls recorded their own: 1 km. Remaking
# a release's cells reads the release's own value, never today's
# (R/cellsnow.R), so a frozen release's cells do not move with this file.
ATLAS_LEGACY_MAX_ACCURACY_M <- 1000

# Grid for counting independent localities, in degrees. 0.01 degrees is about
# 1.1 km of latitude.
ATLAS_LOCALITY_DEGREES <- 0.01

# Grid for anything shown on a map or published, in degrees. Exact coordinates
# of validated collections never leave this machine.
ATLAS_PUBLIC_DEGREES <- 0.1
