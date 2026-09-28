# Run code with environment variables set, restoring them afterwards.
with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA)
  names(old) <- names(vars)
  set <- vars[!vapply(vars, is.na, logical(1))]
  if (length(set)) do.call(Sys.setenv, as.list(set))
  unset <- names(vars)[vapply(vars, is.na, logical(1))]
  if (length(unset)) Sys.unsetenv(unset)
  on.exit(
    {
      keep <- old[!is.na(old)]
      if (length(keep)) do.call(Sys.setenv, as.list(keep))
      drop <- names(old)[is.na(old)]
      if (length(drop)) Sys.unsetenv(drop)
    },
    add = TRUE
  )
  force(code)
}

# Run code with ATLAS_DATA_DIR pointing at a fresh temporary directory, so a
# test never reads or writes the real pull.
with_data_dir <- function(code) {
  dir <- file.path(tempdir(), paste0("atlas-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  old <- Sys.getenv("ATLAS_DATA_DIR", unset = NA)
  Sys.setenv(ATLAS_DATA_DIR = dir)
  on.exit(
    {
      if (is.na(old)) Sys.unsetenv("ATLAS_DATA_DIR") else Sys.setenv(ATLAS_DATA_DIR = old)
      unlink(dir, recursive = TRUE)
    },
    add = TRUE
  )
  force(code)
}
