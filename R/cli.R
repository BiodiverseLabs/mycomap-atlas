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
  message("  build-layers       build environmental layers onto a grid")
  message("      --grid=draft|production   which grid (default draft, 5 km)")
  message("      --only=a,b                build only these layers")
  message("      --overwrite               rebuild layers already built")
  message("  layers             which layers are registered and built")
  message("  training           build one taxon's presences, background and predictors")
  message("      --taxon=\"Name\"            which taxon (required)")
  message("      --grid=draft|production   which grid (default draft)")
  message("      --background=N            background records to draw (default 10000)")
  message("      --buffer-km=N             accessible area around the records (default 500)")
  message("  fit                fit Maxent for one taxon and write its map")
  message("      --taxon=\"Name\"            which taxon (required)")
  message("      --folds=N                 spatial folds (default 5)")
  message("      --block-km=N              fold block size (default 200)")
  message("      --min-presences=N         refuse below this many cells (default 20)")
  message("      --correlation=N           prune predictors above this correlation (default 0.7)")
  message("      --keep-all-predictors     skip pruning")
  message("      --algorithm=maxnet|xgboost|rf  which model (default maxnet)")
  message("  fit-all            fit every taxon with enough presence cells")
  message("      --limit=N                 only the N richest candidates (trial runs)")
  message("      --no-predict              score only; draw no maps")
  message("      --force                   refit even taxa whose records have not changed")
  message("      --workers=N               fit N taxa at once (default 1)")
  message("      --algorithms=maxnet,xgboost,rf|all  models to fit (default maxnet)")
  message("      (also --grid, --background, --buffer-km, --folds, --block-km,")
  message("       --min-presences, --correlation, --keep-all-predictors, as for fit)")
  message("  sweep-predictors   measure how many predictors a taxon should get")
  message("      --per-band=N              taxa sampled per presence-cell band (default 40)")
  message("      --constants=2,3,4,6,none  presences per predictor to compare")
  message("      --workers=N               taxa at once (default 1)")
  message("      --seed=N                  which sample (default 1)")
  message("  benchmark-models   boosted trees against Maxent on the richest taxa")
  message("      --per-band=N              taxa per band of presence cells (default 40)")
  message("      --min-presences=N         smallest taxon included (default 50)")
  message("      --workers=N               taxa at once (default 1)")
  message("      --seed=N                  which sample (default 1)")
  message("  redraw-maps        redraw every map's PNG from its stored raster")
  message("      --workers=N               maps at once (default 1)")
  message("  publish-release    publish what this machine computed as a new release")
  message("      --store=URI               s3://bucket/prefix or a folder (default ATLAS_STORE)")
  message("      --note=\"text\"            why this release was made")
  message("      --no-promote              publish without making it current")
  message("  pull-release       bring this machine up to a release, fetching only what changed")
  message("      --store=URI               as above")
  message("      --release=ID              a particular release (default: the current one)")
  message("      --keep-local              keep local model files the release does not have")
  message("  releases           list the releases in a store, marking the current one")
  message("  promote-release    make a release current (rolling back is promoting an older one)")
  message("      --release=ID              which release (required)")
  message("  archive-release    deposit a release and its layers on Zenodo as new versions")
  message("      --store=URI               as above")
  message("      --release=ID              a particular release (default: the current one)")
  message("      --only=models|layers      one series (default both; layers only when rebuilt)")
  message("      --sandbox                 sandbox.zenodo.org, with test DOIs (do this first)")
  message("      --dry-run                 build the bundles and show what would be uploaded")
  message("      --publish                 mint the DOIs now; otherwise a draft is left to check")
  message("      --resume-draft=ID         carry on in an existing unpublished Zenodo draft")
  message("  archive-publish    publish the waiting draft of a series (--series=models-production)")
  message("  archive-discard    throw away the waiting draft of a series")
  message("  archives           list archived versions and their DOIs")
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

#' "2,4,none" as c(2, 4, Inf). "none" means no cap.
atlas_parse_constants <- function(value) {
  parts <- trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1]])
  numbers <- suppressWarnings(as.numeric(ifelse(parts == "none", "Inf", parts)))
  if (!length(parts) || anyNA(numbers) || any(numbers <= 0)) {
    stop("--constants must be positive numbers or none, such as 2,4,none", call. = FALSE)
  }
  numbers
}

#' --keep-all-predictors forces pruning off; otherwise each algorithm decides.
atlas_flag_prune <- function(flags) {
  if (isTRUE(flags$keep_all_predictors)) FALSE else NULL
}

atlas_flag_grid <- function(flags) {
  if (is.null(flags$grid)) "draft" else as.character(flags$grid)
}

#' Zenodo, or its sandbox with --sandbox, using ZENODO_TOKEN.
atlas_flag_zenodo <- function(flags) {
  if (isTRUE(flags$dry_run)) {
    # A dry run talks to nobody, so it needs no token.
    return(list(target = if (isTRUE(flags$sandbox)) "sandbox" else "zenodo", base = "", call = NULL))
  }
  atlas_zenodo(if (isTRUE(flags$sandbox)) "sandbox" else "zenodo")
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
    "build-layers" = {
      only <- if (is.null(flags$only)) {
        NULL
      } else {
        trimws(strsplit(as.character(flags$only), ",", fixed = TRUE)[[1]])
      }
      atlas_build_layers(
        ids = only,
        grid = atlas_flag_grid(flags),
        overwrite = isTRUE(flags$overwrite)
      )
      invisible(0L)
    },
    "layers" = {
      print(atlas_layer_status(atlas_flag_grid(flags)), row.names = FALSE)
      invisible(0L)
    },
    "training" = {
      if (is.null(flags$taxon)) {
        stop("training needs --taxon=\"Scientific name\"", call. = FALSE)
      }
      atlas_build_training(
        name = as.character(flags$taxon),
        grid = atlas_flag_grid(flags),
        n_background = atlas_flag_number(flags, "background", 10000),
        buffer_km = atlas_flag_number(flags, "buffer_km", 500)
      )
      invisible(0L)
    },
    "fit" = {
      if (is.null(flags$taxon)) {
        stop("fit needs --taxon=\"Scientific name\"", call. = FALSE)
      }
      atlas_fit_taxon(
        name = as.character(flags$taxon),
        grid = atlas_flag_grid(flags),
        n_background = atlas_flag_number(flags, "background", 10000),
        buffer_km = atlas_flag_number(flags, "buffer_km", 500),
        folds = atlas_flag_number(flags, "folds", 5),
        block_km = atlas_flag_number(flags, "block_km", 200),
        min_presences = atlas_flag_number(flags, "min_presences", 20),
        correlation = atlas_flag_number(flags, "correlation", 0.7),
        prune = atlas_flag_prune(flags),
        algorithm = atlas_parse_algorithms(flags$algorithm %||% "maxnet")[[1]]
      )
      invisible(0L)
    },
    "fit-all" = {
      # One pass per algorithm, each with its own currency check and summary.
      failed <- 0L
      for (algorithm in atlas_parse_algorithms(flags$algorithms %||% flags$algorithm)) {
        summary <- atlas_fit_batch(
          grid = atlas_flag_grid(flags),
          limit = atlas_flag_number(flags, "limit", Inf),
          predict = !isTRUE(flags$no_predict),
          force = isTRUE(flags$force),
          workers = as.integer(atlas_flag_number(flags, "workers", 1)),
          n_background = atlas_flag_number(flags, "background", 10000),
          buffer_km = atlas_flag_number(flags, "buffer_km", 500),
          folds = atlas_flag_number(flags, "folds", 5),
          block_km = atlas_flag_number(flags, "block_km", 200),
          min_presences = atlas_flag_number(flags, "min_presences", 20),
          correlation = atlas_flag_number(flags, "correlation", 0.7),
          prune = atlas_flag_prune(flags),
          algorithm = algorithm
        )
        failed <- failed + summary$counts$failed
      }
      # A run with failures exits non-zero, so a scheduler notices.
      invisible(if (failed > 0L) 1L else 0L)
    },
    "sweep-predictors" = {
      constants <- if (is.null(flags$constants)) {
        c(2, 3, 4, 6, Inf)
      } else {
        atlas_parse_constants(flags$constants)
      }
      atlas_predictor_sweep(
        grid = atlas_flag_grid(flags),
        per_band = atlas_flag_number(flags, "per_band", 40),
        constants = constants,
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        seed = as.integer(atlas_flag_number(flags, "seed", 1))
      )
      invisible(0L)
    },
    "benchmark-models" = {
      atlas_model_benchmark(
        grid = atlas_flag_grid(flags),
        per_band = atlas_flag_number(flags, "per_band", 40),
        min_presences = atlas_flag_number(flags, "min_presences", 50),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        seed = as.integer(atlas_flag_number(flags, "seed", 1))
      )
      invisible(0L)
    },
    "redraw-maps" = {
      atlas_rebuild_maps(
        grid = atlas_flag_grid(flags),
        workers = as.integer(atlas_flag_number(flags, "workers", 1))
      )
      invisible(0L)
    },
    "publish-release" = {
      atlas_publish_release(
        store = atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = "")),
        grid = atlas_flag_grid(flags),
        note = if (is.null(flags$note)) NULL else as.character(flags$note),
        promote = !isTRUE(flags$no_promote)
      )
      invisible(0L)
    },
    "pull-release" = {
      atlas_pull_release(
        store = atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = "")),
        grid = atlas_flag_grid(flags),
        release = if (is.null(flags$release)) NULL else as.character(flags$release),
        keep_local = isTRUE(flags$keep_local)
      )
      invisible(0L)
    },
    "releases" = {
      store <- atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = ""))
      grid <- atlas_flag_grid(flags)
      current <- atlas_current_release(store, grid)$id
      ids <- atlas_list_releases(store, grid)
      if (!length(ids)) message("no releases for the ", grid, " grid")
      for (id in ids) message(if (identical(id, current)) "* " else "  ", id)
      invisible(0L)
    },
    "promote-release" = {
      if (is.null(flags$release)) stop("promote-release needs --release=ID", call. = FALSE)
      atlas_promote_release(
        store = atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = "")),
        id = as.character(flags$release),
        grid = atlas_flag_grid(flags)
      )
      invisible(0L)
    },
    "archive-release" = {
      kinds <- if (is.null(flags$only)) ATLAS_ARCHIVE_KINDS else as.character(flags$only)
      atlas_archive(
        store = atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = "")),
        grid = atlas_flag_grid(flags),
        kinds = kinds,
        release = if (is.null(flags$release)) NULL else as.character(flags$release),
        z = atlas_flag_zenodo(flags),
        publish = isTRUE(flags$publish),
        dry_run = isTRUE(flags$dry_run),
        resume_draft = if (is.null(flags$resume_draft)) NULL else as.character(flags$resume_draft)
      )
      invisible(0L)
    },
    "archive-publish" = ,
    "archive-discard" = {
      if (is.null(flags$series)) stop(command, " needs --series=models-<grid> or layers-<grid>", call. = FALSE)
      store <- atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = ""))
      series <- as.character(flags$series)
      z <- atlas_flag_zenodo(list(sandbox = endsWith(series, "-sandbox")))
      if (command == "archive-publish") atlas_archive_publish(store, series, z) else atlas_archive_discard(store, series, z)
      invisible(0L)
    },
    "archives" = {
      store <- atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = ""))
      keys <- store$list("archives/")
      if (!length(keys)) message("nothing archived yet")
      for (key in keys[grepl("[.]json$", keys)]) {
        ledger <- atlas_store_text(store, key)
        message(ledger$series, if (!is.null(ledger$concept_doi)) paste0("  all versions: doi:", ledger$concept_doi) else "")
        for (v in ledger$versions) {
          message("  ", v$version, "  ", v$state, "  ", v$doi %||% v$url)
        }
      }
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
