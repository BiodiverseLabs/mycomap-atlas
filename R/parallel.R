# Pools of R processes for work that waits on files or the store, not on one
# core: fetching a release (R/jobs.R atlas_fetch_entries) and the finish's
# exports that read every map (R/prior.R, R/continent.R).

#' Start workers R processes, each with this package loaded (attached when it
#' is installed, else its source files from the checkout this one was loaded
#' from) and ATLAS_DATA_DIR set to this process's. The caller stops it.
atlas_package_pool <- function(workers) {
  cluster <- parallel::makePSOCKcluster(workers)
  # Where this package's code is: its source when loaded from a checkout,
  # its installed copy otherwise (then a worker loads it by name).
  source_root <- normalizePath(getNamespaceInfo(asNamespace("mycomapatlas"), "path"), winslash = "/",
                               mustWork = FALSE)
  setup <- function(source_root, data_dir) {
    Sys.setenv(ATLAS_DATA_DIR = data_dir)
    if (requireNamespace("mycomapatlas", quietly = TRUE)) {
      attach(asNamespace("mycomapatlas"), name = "atlas", warn.conflicts = FALSE)
    } else {
      for (file in list.files(file.path(source_root, "R"), pattern = "[.][Rr]$", full.names = TRUE)) {
        sys.source(file, envir = globalenv())
      }
    }
    TRUE
  }
  # A function sent to a process carries its enclosing frame; cut it loose.
  environment(setup) <- globalenv()
  tryCatch(parallel::clusterCall(cluster, setup, source_root, atlas_data_dir()), error = function(e) {
    parallel::stopCluster(cluster)
    stop(e)
  })
  cluster
}

#' Run one of this package's functions over x, in x's order, across a pool of
#' workers processes, or one at a time when workers is 1.
#'
#' fun is the function's name, not the function: a function of this package
#' sent to another process makes it load the package by name, which a
#' checkout loaded from source is not installed as. Items go chunk at a time
#' to whichever process is free. ... is passed to fun with each item.
atlas_parallel_map <- function(x, fun, workers = 1L, chunk = 1L, ...) {
  stopifnot(is.character(fun), length(fun) == 1L)
  x <- unname(as.list(x))
  workers <- as.integer(workers)
  if (is.na(workers) || workers <= 1L || length(x) < 2L) {
    f <- get(fun, mode = "function")
    return(lapply(x, function(item) f(item, ...)))
  }
  cluster <- atlas_package_pool(min(workers, length(x)))
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  run <- function(items, what, args) {
    f <- get(what, mode = "function")
    lapply(items, function(item) do.call(f, c(list(item), args)))
  }
  environment(run) <- globalenv()
  chunks <- split(x, ceiling(seq_along(x) / max(1L, as.integer(chunk))))
  unlist(parallel::clusterApplyLB(cluster, chunks, run, what = fun, args = list(...)), recursive = FALSE)
}

#' How many processes the finish's exports use: ATLAS_EXPORT_WORKERS, else 16,
#' never more than the machine's cores; 1 for fewer than
#' ATLAS_EXPORT_PARALLEL_MIN maps, where starting the processes costs more.
atlas_export_workers <- function(maps) {
  if (maps < ATLAS_EXPORT_PARALLEL_MIN) return(1L)
  wanted <- suppressWarnings(as.integer(Sys.getenv("ATLAS_EXPORT_WORKERS", unset = "16")))
  if (is.na(wanted) || wanted < 1L) wanted <- 1L
  cores <- tryCatch(as.integer(parallel::detectCores()), error = function(e) NA_integer_)
  if (is.na(cores) || cores < 1L) cores <- 1L
  min(wanted, cores)
}

ATLAS_EXPORT_PARALLEL_MIN <- 20L
