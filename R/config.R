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

# Coordinates coarser than this (metres) cannot support a 1 km model. Records
# with no accuracy recorded are kept: on iNaturalist a missing value usually
# means the app did not store one, not that the location is poor.
ATLAS_MAX_ACCURACY_M <- 1000

# Grid for counting independent localities, in degrees. 0.01 degrees is about
# 1.1 km of latitude.
ATLAS_LOCALITY_DEGREES <- 0.01

# Grid for anything shown on a map or published, in degrees. Exact coordinates
# of validated collections never leave this machine.
ATLAS_PUBLIC_DEGREES <- 0.1
