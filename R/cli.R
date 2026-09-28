# Command line entry point, reached through ./atlas (Git Bash) or
# ./atlas.ps1 (PowerShell).

atlas_usage <- function() {
  message("usage: atlas <command> [--flag=value]")
  message("")
  message("  pull-occurrences   pull the validated training universe from mycomap.org")
  message("      --since=YYYY-MM-DD   only records updated on or after this date")
  message("      --chunk-size=N       records per query (default 20000)")
  message("      --max-rows=N         stop after N records (smoke test)")
  message("      --dry-run            print the SQL and exit")
  message("  status             what the last pull holds")
  message("  api                serve the development API on port 5100")
  message("      --port=N             another port")
  invisible(NULL)
}

#' Parse --flag and --flag=value arguments into a list.
atlas_parse_flags <- function(args) {
  flags <- list()
  for (arg in args) {
    if (!grepl("^--", arg)) {
      stop("unexpected argument: ", arg, call. = FALSE)
    }
    body <- sub("^--", "", arg)
    if (grepl("=", body, fixed = TRUE)) {
      key <- sub("=.*$", "", body)
      value <- sub("^[^=]*=", "", body)
    } else {
      key <- body
      value <- TRUE
    }
    if (!nzchar(key)) stop("empty flag name in: ", arg, call. = FALSE)
    flags[[gsub("-", "_", key)]] <- value
  }
  flags
}

atlas_flag_number <- function(flags, name, default) {
  if (is.null(flags[[name]])) return(default)
  value <- suppressWarnings(as.numeric(flags[[name]]))
  if (is.na(value)) stop("--", gsub("_", "-", name), " must be a number", call. = FALSE)
  value
}

#' Serve the development API used by the web app.
atlas_serve <- function(port = 5100) {
  if (!requireNamespace("plumber", quietly = TRUE)) {
    stop("plumber is not installed: install.packages('plumber')", call. = FALSE)
  }
  file <- system.file("plumber", "atlas.R", package = "mycomapatlas")
  if (!nzchar(file)) {
    file <- file.path(Sys.getenv("ATLAS_ROOT", unset = "."), "inst", "plumber", "atlas.R")
  }
  plumber::pr_run(plumber::pr(file), port = port)
}

atlas_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (!length(args)) {
    atlas_usage()
    return(invisible(1L))
  }
  command <- args[[1]]
  flags <- atlas_parse_flags(args[-1])

  switch(
    command,
    "pull-occurrences" = {
      atlas_pull_occurrences(
        since = flags$since,
        chunk_size = atlas_flag_number(flags, "chunk_size", 20000),
        max_rows = atlas_flag_number(flags, "max_rows", Inf),
        dry_run = isTRUE(flags$dry_run)
      )
      invisible(0L)
    },
    "status" = {
      atlas_status()
      invisible(0L)
    },
    "api" = {
      atlas_serve(port = atlas_flag_number(flags, "port", 5100))
      invisible(0L)
    },
    "help" = {
      atlas_usage()
      invisible(0L)
    },
    {
      message("unknown command: ", command)
      atlas_usage()
      invisible(1L)
    }
  )
}
