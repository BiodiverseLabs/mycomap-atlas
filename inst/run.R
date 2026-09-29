# Entry point for ./atlas and ./atlas.ps1. Uses the installed package when
# there is one, and otherwise loads the sources in place, so the command line
# works before anything is installed.

root <- Sys.getenv("ATLAS_ROOT", unset = ".")

if (requireNamespace("mycomapatlas", quietly = TRUE)) {
  library(mycomapatlas)
} else {
  for (file in list.files(file.path(root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) {
    source(file)
  }
}

status <- atlas_main(commandArgs(trailingOnly = TRUE))
# Pass the command's result on as the exit code, so a scheduler can tell a
# run with failures from a clean one.
if (is.numeric(status) && length(status) == 1L && status != 0) {
  quit(save = "no", status = as.integer(status))
}
