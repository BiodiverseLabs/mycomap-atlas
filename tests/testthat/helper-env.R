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
