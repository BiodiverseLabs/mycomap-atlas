# Command line entry point, reached through ./atlas (Git Bash) or
# ./atlas.ps1 (PowerShell).

atlas_usage <- function() {
  message("usage: atlas <command> [--flag=value]")
  message("")
  message("  pull-occurrences   pull the validated training universe from mycomap.org")
  message("      --since=YYYY-MM-DD   only records updated on or after this date")
  message("      --chunk-size=N       records per query (default 10000)")
  message("      --max-rows=N         stop after N records (smoke test)")
  message("      --dry-run            print the SQL and exit")
  message("  build-layers       build environmental layers onto a grid")
  message("      --grid=draft|production   which grid (default draft, 5 km)")
  message("      --only=a,b                build only these layers")
  message("      --overwrite               rebuild layers already built")
  message("  layers             which layers are registered and built")
  message("  fetch-guilds       download FungalTraits' genus table (lookup only, never published)")
  message("  training           build one taxon's presences, background and predictors")
  message("      --taxon=\"Name\"            which taxon (required)")
  message("      --grid=draft|production   which grid (default draft)")
  message("      --background=N            background records to draw (default 10000)")
  message("      --buffer-km=N             accessible area around the records (default 500)")
  message("  fit                fit Maxent for one taxon and write its map")
  message("      --taxon=\"Name\"            which taxon (required)")
  message("      --folds=N                 spatial folds (default 5)")
  message("      --block-km=N|auto         fold block size in km; auto asks blockCV (default auto)")
  message("      --min-presences=N         refuse below this many detection sites (default 20)")
  message("      --nulls=N                 null models to test the map against (default 19)")
  message("      --no-tune                 fit default settings instead of tuning in nested folds")
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
  message("       --min-presences, --correlation, --keep-all-predictors, --nulls,")
  message("       --no-tune, as for fit)")
  message("  sweep-predictors   measure how many predictors a taxon should get")
  message("      --per-band=N              taxa sampled per presence-cell band (default 40)")
  message("      --constants=2,3,4,6,none  presences per predictor to compare")
  message("      --workers=N               taxa at once (default 1)")
  message("      --seed=N                  which sample (default 1)")
  message("  sweep-layers       measure whether each new layer, and the design, improves the models")
  message("      --no-method               leave out the arms that fit the old designs")
  message("      --per-band=N              taxa sampled per presence-cell band (default 40)")
  message("      --workers=N               taxa at once (default 1)")
  message("      --seed=N                  which sample (default 1)")
  message("  study-sparse       how few sites carry a map: thin rich taxa, score on what was left out")
  message("      --per-band=N              taxa per band of detection sites (default 40)")
  message("      --min-presences=N         smallest taxon thinned (default 40)")
  message("      --sizes=5,8,12,16         sites to thin to")
  message("      --workers=N               taxa at once (default 1)")
  message("      --seed=N                  which sample (default 1)")
  message("  study-virtual      virtual species with known habitats, collected at the real sites")
  message("                     with their real effort: which model finds the habitat")
  message("      --species=N               species of each kind (default 40)")
  message("      --kinds=habitat,geography habitat follows the environment; geography only")
  message("                                distance from a centre (default habitat)")
  message("      --arms=maxnet:none,...    arms to fit (default: Maxent's four effort modes,")
  message("                                the detection model and the forest)")
  message("      --nulls=N                 run production Maxent's null test with up to N nulls")
  message("      --null-designs=scatter,shift,shift-effort  null designs to compare (default scatter)")
  message("      --stop-after=N            stop a null test once N nulls do as well (default: never)")
  message("      --workers=N               species at once (default 1)")
  message("      --seed=N                  which species (default 1)")
  message("  build-ensembles    average each taxon's passing models into one map, with where")
  message("                     they disagree (after fit-all, before a release)")
  message("      --force                   rebuild even ensembles whose members have not changed")
  message("  study-blocks       which block size makes cross-validation test at the distances")
  message("                     a map predicts at (kNNDM's question)")
  message("      --per-band=N              taxa per band of detection sites (default 25)")
  message("      --sizes=50,100,...        block sizes in km (default 50,100,150,200,300,400)")
  message("      --workers=N               taxa at once (default 1)")
  message("      --seed=N                  which sample (default 1)")
  message("  benchmark-models   boosted trees against Maxent on the richest taxa")
  message("      --per-band=N              taxa per band of presence cells (default 40)")
  message("      --min-presences=N         smallest taxon included (default 50)")
  message("      --workers=N               taxa at once (default 1)")
  message("      --seed=N                  which sample (default 1)")
  message("  redraw-maps        redraw every map's PNG from its stored raster")
  message("  count-regions      count every stored map by state, for the likely-in lists")
  message("  finish-release     on a worker: count, index and report one release (R/finish.R)")
  message("      --workers=N               maps at once (default 1)")
  message("  build-here-index   index every map by 20 km cell, for \"what could grow here\"")
  message("      --cell-km=N               cell size (default 20)")
  message("  publish-release    publish what this machine computed as a new release")
  message("      --store=URI               s3://bucket/prefix or a folder (default ATLAS_STORE)")
  message("      --note=\"text\"            why this release was made")
  message("      --no-promote              publish without making it current")
  message("  pull-release       bring this machine up to a release, fetching only what changed")
  message("      --store=URI               as above")
  message("      --release=ID              a particular release (default: the current one)")
  message("      --keep-local              keep local model files the release does not have")
  message("      --no-rasters              leave model rasters in the store (a web server)")
  message("  sitemap            write the site's sitemap: its pages, and every taxon with a")
  message("                     passing map on this machine (a web server, after pull-release)")
  message("      --out=PATH                where (default sitemap.xml in the data directory)")
  message("      --origin=URL              the public site (default ATLAS_PUBLIC_ORIGIN)")
  message("  releases           list the releases in a store, marking the current one")
  message("  promote-release    make a release current (rolling back is promoting an older one)")
  message("      --release=ID              which release (required)")
  message("  publish-layers     put this machine's built layers in the store for workers")
  message("  exclude-records    leave listed rows out of this pull and every later one, by a private drop")
  message("                     list (--ids=FILE|LIST [--by=id|source_observation] [--reason=...]);")
  message("                     --clear --confirm retires the list")
  message("  plan-job           list what needs refitting and split it into shards")
  message("      --algorithms=maxnet,xgboost,rf|all  models to consider (default all)")
  message("      --shards=N                how many workers will share it (default 4)")
  message("      --limit=N                 fit only the N richest taxa that need it (a trial)")
  message("      --sample=N                fit N taxa spread from richest to sparsest (a pilot)")
  message("      --prior-only --from-release=ID --validated-through=YYYY-MM-DD")
  message("                                refit a release's strong models on its pull without the records")
  message("                                validated after the date, for Vision's benchmark: never a release")
  message("      --hindcast --from-release=ID --validated-through=YYYY-MM-DD [--dry-run]")
  message("                                fit every taxon afresh, graded, on the records first validated by the")
  message("                                date, as a private release (Atlas E2, Vision's R_train): never public")
  message("      --record-names --from-release=ID [--dry-run]")
  message("                                the same, with records under their own .org names (Atlas E9)")
  message("      --full-refresh --from-release=ID [--dry-run]")
  message("                                refit a release's strong models for their full views alone and")
  message("                                publish them in a new release (--dry-run: say what and how much)")
  message("  run-shard          fit one shard of a job and upload the results")
  message("      --job=ID --shard=N        which (both required)")
  message("      --workers=N               fits at once on this machine (default 1)")
  message("  job-status         which shards of a job have reported")
  message("  finish-prior-only  build a prior-only job's private prior, trained ids and summary (--job=ID)")
  message("  finish-private-release  finish a hindcast or record-names job privately (--job=ID)")
  message("  plan-study         run a study command on EC2 workers, one shard each (--command=study-...,")
  message("                     --shards=N, [--from-release=ID for its inputs], [--args=\"...\"]); results under study/<id>/")
  message("  run-study          one shard of a study job (--job=ID --shard=N), as a worker runs it")
  message("  finish-full-refresh  publish a full-view refresh whose refits match its release (--job=ID)")
  message("                       --allow-mismatch: after reading the refusal, publish the rest; models whose")
  message("                       refits differ keep the release's own full views, listed in the release")
  message("  pull-privacy       make the private list of records whose place their source hides (read-only),")
  message("                     which the published collection cells leave out")
  message("  job-timing         what a job's fits cost, and a full job would (--job=ID)")
  message("      --fits-at-once=N          fits running together on EC2 (default 84)")
  message("  trained-ids        PRIVATE: which records trained a release (--out=FILE or --link [--hours=N],")
  message("                     [--release=ID]); never publish it. --write makes the list from this")
  message("                     machine's pull, for a release made before lists were kept")
  message("  track-new-finds    score records first validated since each map was made against the release")
  message("                     live when their day began; private ledger in the store, public summary")
  message("                     (lookups only: reads this machine's newest pull and the store)")
  message("      --since=YYYY-MM-DD        first day counted (default 2026-10-03)")
  message("      --dry-run                 score and summarise, write nothing")
  message("  finish-job         build and promote the release once every shard reported")
  message("      --job=ID                  which job (required)")
  message("      --no-promote              publish without making it current")
  message("      --partial                 publish what unreported shards saved (a job past its deadline)")
  message("  run-job-ec2        run a planned job's shards on EC2 spot workers, then finish it")
  message("      --job=ID                  which job (required)")
  message("      --no-finish               stop when the shards report: no release (a pilot)")
  message("  nightly            pull, plan, run the job on EC2 and finish it: the box's cron job")
  message("      --algorithms=maxnet,xgboost,rf|all  models to consider (default all)")
  message("      --tasks-per-shard=N       about this many models per worker (default 40)")
  message("      --no-pull                 plan from the last pull")
  message("      --limit=N                 fit only the N richest taxa that need it (a trial)")
  message("      (EC2 settings come from the environment; see deploy/aws/README.md)")
  message("  refresh-names      merge spellings of one taxon and rebuild the taxon counts")
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
  message("Paper studies (private; results under study/ or this machine only). On EC2, run one")
  message("through a study job (plan-study --command=study-...); --out copies results to the store.")
  message("  study-distance     paper E6b: a distance-only kernel map per taxon of a release,")
  message("                     bandwidth by the taxon's production folds; scored by the E2 scorer")
  message("      --release=ID              the (hindcast) release whose pull and taxa it uses")
  message("      --plan-only               print the work and CPU-hours, do nothing")
  message("      --shard=i/n               every n-th taxon from the i-th (default 1/1)")
  message("      --out=study/<id>/         also copy the results to this store prefix")
  message("      --workers=N               taxa at once (default 1)")
  message("  study-rescan       paper E1c: the standard test (19 scattered nulls) on a stratified")
  message("                     sample of a release's models, beside their shift grades")
  message("      --release=ID              the (frozen) release whose models and pull it uses")
  message("      --per-cell=N              models per learner x band x grade (default 50)")
  message("      --seed=N                  which sample (default 1)")
  message("      --plan-only               print the sample size and CPU-hours, do nothing")
  message("      --shard=i/n               every n-th model from the i-th (default 1/1)")
  message("      --out=study/<id>/         also copy the results to this store prefix")
  message("      --workers=N               models at once (default 1)")
  message("      --pool=a.json,b.json      read a run's shards together: the 2% rule over all")
  message("      --pool-from=study/<id>/   the same, for a study job's shards in the store")
  message("  study-calibration  paper E1: the pre-registered virtual-species cells (1,200 habitat +")
  message("                     800 geography full-model species, 840 ESM species), scattered and")
  message("                     shifted nulls per learner, on the pull and layers on this machine")
  message("      --seed=N                  which species (default 1)")
  message("      --nulls=N                 nulls per design, stopping at 5 (default 99)")
  message("      --per-cell=K              K species in every cell instead of the registered counts")
  message("                                (a smoke run: K=1 is one species per cell, 39 in all)")
  message("      --plan-only               print the species and CPU-hours, do nothing")
  message("      --shard=i/n               every n-th species from the i-th (default 1/1)")
  message("      --out=study/<id>/         also copy the results to this store prefix")
  message("      --workers=N               species at once (default 1)")
  message("  study-e12-draw     paper E12 step 0: the seeded stratified draw on a release and its cost from")
  message("                     recorded fit times, to a local CSV (--release=ID [--out=e12-draw.csv]); read-only")
  message("  study-repro        paper E12 gate: refit models in fresh processes on one machine, twice or more,")
  message("                     against the release (--release=ID --source-job=ID --taxa=A%20b|C%20d [--runs=2] [--label])")
  message("  study-default      paper E6a: \"default practice\" Maxent (maxnet defaults, random")
  message("                     background and folds, 19 uniform nulls) on a release's 20+ site taxa")
  message("      --release=ID              the (hindcast) release whose pull and taxa it uses")
  message("      --plan-only               print the taxa and CPU-hours, do nothing")
  message("      --shard=i/n               every n-th taxon from the i-th (default 1/1)")
  message("      --out=study/<id>/         also copy the results to this store prefix")
  message("      --workers=N               taxa at once (default 1)")
  message("  study-score        paper E2, E6b and E6a: score the hindcast's models and the baselines on")
  message("                     its later finds, all on the same places")
  message("      --hindcast=ID             the hindcast's private release (its cutoff and source release")
  message("                                are read from it)")
  message("      --from-release=ID         optional: refused unless it is the hindcast's source release")
  message("      --cutoff=YYYY-MM-DD       optional: refused unless it is the hindcast's cutoff")
  message("      --kernels=a.json,...      every shard's results file of one E6b run on this hindcast")
  message("      --defaults=a.json,...     every shard's results file of one E6a run on this hindcast")
  message("      --observed-after          only finds also observed after the cutoff")
  message("      --reps=N                  bootstrap resamples of taxa (default 10000)")
  message("      --exclude=ID,ID|@file     .org record ids of test finds never to score (counted)")
  message("      --hold=ID,ID|@file        .org record ids of test finds held for now (counted)")
  message("      --allow-missing-excludes  go on when an --exclude id is no later find (else refused)")
  message("      --out=study/<id>/         also copy the results to this store prefix")
  message("  study-compare      paper E9: the record-name release against the frozen one, per taxon")
  message("                     and learner: grades, map Spearman and Schoener's D, label changes")
  message("      --frozen=ID               the frozen (DNA-named) release")
  message("      --record=ID               the private release built with --record-names")
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

#' The store named by --store, or ATLAS_STORE.
atlas_flag_store <- function(flags) {
  atlas_store(flags$store %||% Sys.getenv("ATLAS_STORE", unset = ""))
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

#' --block-km: a number of km, or auto (the default) to let blockCV decide.
atlas_flag_block <- function(flags) {
  value <- flags$block_km
  if (is.null(value) || isTRUE(value) || identical(tolower(as.character(value)), "auto")) {
    return("auto")
  }
  atlas_flag_number(flags, "block_km", "auto")
}

atlas_flag_number <- function(flags, name, default) {
  if (is.null(flags[[name]])) return(default)
  value <- suppressWarnings(as.numeric(flags[[name]]))
  if (is.na(value)) stop("--", gsub("_", "-", name), " must be a number", call. = FALSE)
  value
}

#' Serve the API used by the web app, on loopback only. In production the
#' container shares the server's network (deploy/lightsail), so nginx reaches
#' it from 127.0.0.1, the one peer whose X-Forwarded-For the API believes.
atlas_serve <- function(port = 5100) {
  if (!requireNamespace("plumber", quietly = TRUE)) {
    stop("plumber is not installed: install.packages('plumber')", call. = FALSE)
  }
  file <- system.file("plumber", "atlas.R", package = "mycomapatlas")
  if (!nzchar(file)) {
    file <- file.path(Sys.getenv("ATLAS_ROOT", unset = "."), "inst", "plumber", "atlas.R")
  }
  plumber::pr_run(plumber::pr(file), port = port, host = "127.0.0.1")
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
    "plan-study" = {
      if (is.null(flags$command)) stop("plan-study needs --command=study-...", call. = FALSE)
      args <- if (is.null(flags$args)) character() else strsplit(trimws(as.character(flags$args)), "[[:space:]]+")[[1]]
      atlas_plan_study_job(atlas_flag_store(flags), command = as.character(flags$command), args = args,
                           shards = as.integer(atlas_flag_number(flags, "shards", 4)),
                           from_release = if (!is.null(flags$from_release)) as.character(flags$from_release),
                           grid = atlas_flag_grid(flags))
      invisible(0L)
    },
    "run-study" = {
      if (is.null(flags$job) || is.null(flags$shard)) stop("run-study needs --job=ID and --shard=N", call. = FALSE)
      record <- atlas_run_study_shard(atlas_flag_store(flags), as.character(flags$job),
                                      as.integer(atlas_flag_number(flags, "shard", NA)), atlas_flag_grid(flags))
      invisible(if (identical(record$status, "succeeded")) 0L else 1L)
    },
    "pull-privacy" = {
      # Read-only: the private list of records whose place their source
      # hides, for the published collection cells (R/privacy.R).
      atlas_pull_privacy()
      invisible(0L)
    },
    "exclude-records" = {
      # Private: the box's drop list, applied to every pull (R/exclude.R).
      if (isTRUE(flags$clear)) {
        atlas_clear_exclusions(confirm = isTRUE(flags$confirm))
      } else {
        if (is.null(flags$ids)) stop("exclude-records needs --ids=FILE or a comma list, or --clear --confirm", call. = FALSE)
        atlas_exclude_records(as.character(flags$ids), by = as.character(flags$by %||% "id"),
                              reason = as.character(flags$reason %||% ""))
      }
      invisible(0L)
    },
    "pull-occurrences" = {
      atlas_pull_occurrences(
        since = flags$since,
        chunk_size = atlas_flag_number(flags, "chunk_size", 10000),
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
    "fetch-guilds" = {
      atlas_fetch_guild_table()
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
        block_km = atlas_flag_block(flags),
        min_presences = atlas_flag_number(flags, "min_presences", 20),
        correlation = atlas_flag_number(flags, "correlation", 0.7),
        prune = atlas_flag_prune(flags),
        nulls = atlas_flag_number(flags, "nulls", ATLAS_NULL_REPS),
        tune = !isTRUE(flags$no_tune),
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
          block_km = atlas_flag_block(flags),
          min_presences = atlas_flag_number(flags, "min_presences", 20),
          correlation = atlas_flag_number(flags, "correlation", 0.7),
          prune = atlas_flag_prune(flags),
          nulls = atlas_flag_number(flags, "nulls", ATLAS_NULL_REPS),
          tune = !isTRUE(flags$no_tune),
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
    "sweep-layers" = {
      atlas_layer_sweep(
        grid = atlas_flag_grid(flags),
        per_band = atlas_flag_number(flags, "per_band", 40),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        seed = as.integer(atlas_flag_number(flags, "seed", 1)),
        method = !isTRUE(flags$no_method)
      )
      invisible(0L)
    },
    "study-sparse" = {
      sizes <- if (is.null(flags$sizes)) {
        ATLAS_SPARSE_SIZES
      } else {
        as.integer(strsplit(as.character(flags$sizes), ",", fixed = TRUE)[[1]])
      }
      atlas_sparse_study(
        grid = atlas_flag_grid(flags),
        per_band = atlas_flag_number(flags, "per_band", 40),
        min_presences = atlas_flag_number(flags, "min_presences", 40),
        sizes = sizes,
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        seed = as.integer(atlas_flag_number(flags, "seed", 1))
      )
      invisible(0L)
    },
    "study-virtual" = {
      split_flag <- function(value, default) {
        if (is.null(value)) default else trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1]])
      }
      atlas_virtual_study(
        grid = atlas_flag_grid(flags),
        species = as.integer(atlas_flag_number(flags, "species", 40)),
        kinds = split_flag(flags$kinds, "habitat"),
        arms = split_flag(flags$arms, ATLAS_VIRTUAL_ARMS),
        nulls = as.integer(atlas_flag_number(flags, "nulls", 0)),
        null_designs = split_flag(flags$null_designs, "scatter"),
        stop_after = if (is.null(flags$stop_after)) NULL else as.integer(atlas_flag_number(flags, "stop_after", 5)),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        seed = as.integer(atlas_flag_number(flags, "seed", 1))
      )
      invisible(0L)
    },
    "build-ensembles" = {
      atlas_build_ensembles(grid = atlas_flag_grid(flags), force = isTRUE(flags$force))
      invisible(0L)
    },
    "study-blocks" = {
      sizes <- if (is.null(flags$sizes)) {
        ATLAS_BLOCKCHECK_SIZES
      } else {
        as.numeric(strsplit(as.character(flags$sizes), ",", fixed = TRUE)[[1]])
      }
      atlas_block_study(
        grid = atlas_flag_grid(flags),
        per_band = atlas_flag_number(flags, "per_band", 25),
        sizes = sizes,
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
    "build-here-index" = {
      atlas_build_here_index(
        grid = atlas_flag_grid(flags),
        cell_km = atlas_flag_number(flags, "cell_km", ATLAS_HERE_CELL_KM)
      )
      invisible(0L)
    },
    "count-regions" = {
      atlas_count_regions(
        grid = atlas_flag_grid(flags),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        only_missing = isTRUE(flags$only_missing)
      )
      invisible(0L)
    },
    "finish-release" = {
      if (is.null(flags$release)) stop("finish-release needs --release=ID", call. = FALSE)
      atlas_finish_release_work(
        atlas_flag_store(flags), release = as.character(flags$release),
        grid = atlas_flag_grid(flags),
        workers = as.integer(atlas_flag_number(flags, "workers", 1))
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
        keep_local = isTRUE(flags$keep_local),
        rasters = !isTRUE(flags$no_rasters)
      )
      invisible(0L)
    },
    "sitemap" = {
      atlas_write_sitemap(
        path = as.character(flags$out %||% file.path(atlas_data_dir(), "sitemap.xml")),
        origin = as.character(flags$origin %||% Sys.getenv("ATLAS_PUBLIC_ORIGIN", unset = "")),
        grid = atlas_flag_grid(flags)
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
    "publish-layers" = {
      atlas_publish_layers(atlas_flag_store(flags), grid = atlas_flag_grid(flags))
      invisible(0L)
    },
    "plan-job" = {
      if (isTRUE(flags$full_refresh)) {
        if (is.null(flags$from_release)) stop("plan-job --full-refresh needs --from-release=ID", call. = FALSE)
        atlas_plan_full_refresh(
          atlas_flag_store(flags), from_release = as.character(flags$from_release), grid = atlas_flag_grid(flags),
          shards = as.integer(atlas_flag_number(flags, "shards", 4)), dry_run = isTRUE(flags$dry_run)
        )
      } else if (isTRUE(flags$hindcast) || isTRUE(flags$record_names)) {
        if (is.null(flags$from_release)) stop("a private release needs --from-release=ID", call. = FALSE)
        atlas_plan_private_release(
          atlas_flag_store(flags), from_release = as.character(flags$from_release),
          purpose = if (isTRUE(flags$hindcast)) "hindcast" else "record-names",
          validated_through = if (!is.null(flags$validated_through)) as.character(flags$validated_through),
          grid = atlas_flag_grid(flags), algorithms = flags$algorithms %||% "all",
          shards = as.integer(atlas_flag_number(flags, "shards", 4)), dry_run = isTRUE(flags$dry_run)
        )
      } else if (isTRUE(flags$prior_only)) {
        if (is.null(flags$from_release) || is.null(flags$validated_through)) {
          stop("plan-job --prior-only needs --from-release=ID and --validated-through=YYYY-MM-DD", call. = FALSE)
        }
        atlas_plan_prior_only(
          atlas_flag_store(flags), from_release = as.character(flags$from_release),
          validated_through = as.character(flags$validated_through), grid = atlas_flag_grid(flags),
          shards = as.integer(atlas_flag_number(flags, "shards", 4))
        )
      } else atlas_plan_job(
        atlas_flag_store(flags), grid = atlas_flag_grid(flags),
        algorithms = flags$algorithms %||% "all",
        shards = as.integer(atlas_flag_number(flags, "shards", 4)),
        min_presences = atlas_flag_number(flags, "min_presences", 20),
        limit = atlas_flag_number(flags, "limit", Inf),
        sample = atlas_flag_number(flags, "sample", Inf)
      )
      invisible(0L)
    },
    "run-shard" = {
      if (is.null(flags$job) || is.null(flags$shard)) {
        stop("run-shard needs --job=ID and --shard=N", call. = FALSE)
      }
      record <- atlas_run_shard(
        atlas_flag_store(flags), id = as.character(flags$job),
        shard = as.integer(atlas_flag_number(flags, "shard", NA)),
        grid = atlas_flag_grid(flags),
        workers = as.integer(atlas_flag_number(flags, "workers", 1))
      )
      invisible(if ((record$counts$failed %||% 0) > 0) 1L else 0L)
    },
    "job-status" = {
      if (is.null(flags$job)) stop("job-status needs --job=ID", call. = FALSE)
      status <- atlas_job_status(atlas_flag_store(flags), as.character(flags$job), atlas_flag_grid(flags))
      message("job ", status$job, ": ", length(status$done), " of ", status$shards, " shards reported",
              if (length(status$missing)) paste0("; waiting on ", paste(status$missing, collapse = ", ")) else "",
              if (isTRUE(status$finished)) "; finished" else "")
      invisible(0L)
    },
    "finish-job" = {
      if (is.null(flags$job)) stop("finish-job needs --job=ID", call. = FALSE)
      atlas_finish_job(atlas_flag_store(flags), as.character(flags$job), atlas_flag_grid(flags),
                       promote = !isTRUE(flags$no_promote), partial = isTRUE(flags$partial))
      invisible(0L)
    },
    "run-job-ec2" = {
      if (is.null(flags$job)) stop("run-job-ec2 needs --job=ID", call. = FALSE)
      config <- atlas_ec2_config()
      store <- atlas_store(flags$store %||% config$store)
      grid <- atlas_flag_grid(flags)
      atlas_run_job_on_ec2(store, atlas_read_job(store, as.character(flags$job), grid), grid,
                           config = config, finish = !isTRUE(flags$no_finish))
      invisible(0L)
    },
    "trained-ids" = {
      # Private: which records trained a release, for Vision's benchmark.
      # --out copies it here; --link prints a presigned link instead.
      store_uri <- flags$store %||% Sys.getenv("ATLAS_STORE", unset = "")
      store <- atlas_store(store_uri)
      grid <- atlas_flag_grid(flags)
      release <- if (is.null(flags$release)) NULL else as.character(flags$release)
      if (isTRUE(flags$write)) {
        atlas_backfill_trained_ids(store, release, grid)
      } else if (isTRUE(flags$link)) {
        release <- release %||% atlas_current_release(store, grid)$id
        cat(atlas_trained_ids_link(store_uri, release, grid, hours = atlas_flag_number(flags, "hours", 1)), "\n")
      } else {
        if (is.null(flags$out)) stop("trained-ids needs --out=FILE, or --link", call. = FALSE)
        atlas_fetch_trained_ids(store, release, grid, as.character(flags$out))
        message("wrote ", flags$out, ": private, do not publish it")
      }
      invisible(0L)
    },
    "track-new-finds" = {
      # Bookkeeping: a failure warns and the command still succeeds, so a
      # unit running it never fails anything after it.
      atlas_track_new_finds_quietly(
        store = atlas_flag_store(flags), grid = atlas_flag_grid(flags),
        since = as.character(flags$since %||% ATLAS_TRACKER_SINCE), dry_run = isTRUE(flags$dry_run)
      )
      invisible(0L)
    },
    "finish-full-refresh" = {
      if (is.null(flags$job)) stop("finish-full-refresh needs --job=ID", call. = FALSE)
      atlas_finish_full_refresh(atlas_flag_store(flags), as.character(flags$job), atlas_flag_grid(flags),
                                promote = !isTRUE(flags$no_promote), allow_mismatch = isTRUE(flags$allow_mismatch))
      invisible(0L)
    },
    "finish-private-release" = {
      if (is.null(flags$job)) stop("finish-private-release needs --job=ID", call. = FALSE)
      atlas_finish_private_release_work(atlas_flag_store(flags), as.character(flags$job), atlas_flag_grid(flags),
                                        usd_per_vcpu_hour = atlas_flag_number(flags, "usd_per_vcpu_hour", 0.025),
                                        defer = isTRUE(flags$defer))
      invisible(0L)
    },
    "finish-prior-only" = {
      if (is.null(flags$job)) stop("finish-prior-only needs --job=ID", call. = FALSE)
      atlas_finish_prior_only_work(atlas_flag_store(flags), as.character(flags$job), atlas_flag_grid(flags),
                                   usd_per_vcpu_hour = atlas_flag_number(flags, "usd_per_vcpu_hour", 0.025),
                                   defer = isTRUE(flags$defer))
      invisible(0L)
    },
    "job-timing" = {
      if (is.null(flags$job)) stop("job-timing needs --job=ID", call. = FALSE)
      timing <- atlas_job_timing(atlas_flag_store(flags), as.character(flags$job), atlas_flag_grid(flags),
                                 fits_at_once = atlas_flag_number(flags, "fits_at_once", 84))
      print(timing$per_algorithm, row.names = FALSE)
      message(sprintf(paste("job %s: %d models, %d timed, %.2f CPU-h. A full job of %d models:",
                            "about %.0f CPU-h, %.1f h wall at %d fits at once."),
                      timing$job, timing$models, timing$timed, timing$pilot_cpu_hours,
                      timing$full_models, timing$full_cpu_hours, timing$full_wall_hours,
                      as.integer(timing$fits_at_once)))
      x <- timing$extent
      if (x$models) {
        message(sprintf(paste("full-extent views: %d models (%.0f%% of those timed), %.1f s and %.1f MB each;",
                              "in a full job about %.1f CPU-h (already in the total) and %.1f GB."),
                        x$models, 100 * x$share, x$mean_seconds, x$mean_mb, x$full_cpu_hours, x$full_gb))
      }
      invisible(0L)
    },
    "nightly" = {
      config <- atlas_ec2_config()
      atlas_nightly(
        grid = atlas_flag_grid(flags), algorithms = flags$algorithms %||% "all",
        pull = !isTRUE(flags$no_pull), config = config,
        store = atlas_store(flags$store %||% config$store),
        tasks_per_shard = atlas_flag_number(flags, "tasks_per_shard", 40),
        limit = atlas_flag_number(flags, "limit", Inf)
      )
      invisible(0L)
    },
    "refresh-names" = {
      atlas_refresh_names()
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
    # Paper studies.
    "study-distance" = {
      if (is.null(flags$release)) stop("study-distance needs --release=ID", call. = FALSE)
      atlas_distance_study(
        atlas_flag_store(flags), release = as.character(flags$release),
        grid = atlas_flag_grid(flags),
        out = if (is.null(flags$out)) NULL else as.character(flags$out),
        shard = as.character(flags$shard %||% "1/1"),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        plan_only = isTRUE(flags$plan_only)
      )
      invisible(0L)
    },
    "study-rescan" = {
      if (!is.null(flags$pool) || !is.null(flags$pool_from)) {
        pooled <- if (!is.null(flags$pool_from)) {
          atlas_rescan_pool_from(atlas_flag_store(flags), as.character(flags$pool_from))
        } else {
          atlas_rescan_pool(trimws(strsplit(as.character(flags$pool), ",", fixed = TRUE)[[1]]))
        }
        message(pooled$models, " of ", pooled$sampled, " sampled models over ", length(pooled$shards),
                " shards; ", pooled$health$dropped, " without a verdict; readable: ", pooled$readable)
        print(pooled$summary, row.names = FALSE)
        return(invisible(if (isTRUE(pooled$readable)) 0L else 1L))
      }
      if (is.null(flags$release)) stop("study-rescan needs --release=ID", call. = FALSE)
      atlas_rescan_study(
        atlas_flag_store(flags), release = as.character(flags$release),
        grid = atlas_flag_grid(flags),
        per_cell = as.integer(atlas_flag_number(flags, "per_cell", ATLAS_RESCAN_PER_CELL)),
        seed = as.integer(atlas_flag_number(flags, "seed", 1)),
        out = if (is.null(flags$out)) NULL else as.character(flags$out),
        shard = as.character(flags$shard %||% "1/1"),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        plan_only = isTRUE(flags$plan_only)
      )
      invisible(0L)
    },
    "study-calibration" = {
      out <- if (is.null(flags$out)) NULL else as.character(flags$out)
      per_cell <- if (is.null(flags$per_cell)) NULL else as.integer(atlas_flag_number(flags, "per_cell", 1))
      if (!is.null(per_cell) && (is.na(per_cell) || per_cell < 1L)) {
        stop("--per-cell must be a whole number, 1 or more", call. = FALSE)
      }
      atlas_calibration_study(
        grid = atlas_flag_grid(flags),
        layout = if (is.null(per_cell)) atlas_calibration_layout() else
          atlas_calibration_layout(per_cell, per_cell, per_cell, per_cell),
        seed = as.integer(atlas_flag_number(flags, "seed", 1)),
        nulls = as.integer(atlas_flag_number(flags, "nulls", ATLAS_CALIBRATION_NULLS)),
        shard = as.character(flags$shard %||% "1/1"),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        out = out, store = if (!is.null(out)) atlas_flag_store(flags),
        plan_only = isTRUE(flags$plan_only)
      )
      invisible(0L)
    },
    "study-score" = {
      if (is.null(flags$hindcast)) stop("study-score needs --hindcast=ID", call. = FALSE)
      files <- function(value) if (is.null(value)) NULL else trimws(strsplit(as.character(value), ",", fixed = TRUE)[[1]])
      atlas_score_study(
        atlas_flag_store(flags), hindcast = as.character(flags$hindcast),
        from_release = if (is.null(flags$from_release)) NULL else as.character(flags$from_release),
        cutoff = if (is.null(flags$cutoff)) NULL else as.character(flags$cutoff),
        grid = atlas_flag_grid(flags), kernels = files(flags$kernels), defaults = files(flags$defaults),
        observed_after = isTRUE(flags$observed_after),
        reps = atlas_flag_number(flags, "reps", ATLAS_E2_BOOTSTRAP),
        out = if (is.null(flags$out)) NULL else as.character(flags$out),
        exclude = atlas_score_ids(flags$exclude), hold = atlas_score_ids(flags$hold),
        allow_missing_excludes = isTRUE(flags$allow_missing_excludes)
      )
      invisible(0L)
    },
    "study-e12-draw" = {
      if (is.null(flags$release)) stop("study-e12-draw needs --release=ID", call. = FALSE)
      atlas_e12_draw_study(atlas_flag_store(flags), release = as.character(flags$release),
                           grid = atlas_flag_grid(flags), out = as.character(flags$out %||% "e12-draw.csv"))
      invisible(0L)
    },
    "study-repro" = {
      if (is.null(flags$release) || is.null(flags$source_job) || is.null(flags$taxa)) {
        stop("study-repro needs --release=ID --source-job=ID --taxa='Name one|Name two'", call. = FALSE)
      }
      atlas_repro_study(
        atlas_flag_store(flags), release = as.character(flags$release),
        source_job = as.character(flags$source_job), taxa = as.character(flags$taxa),
        algorithm = as.character(flags$algorithm %||% "maxnet"),
        runs = as.integer(atlas_flag_number(flags, "runs", ATLAS_REPRO_RUNS)),
        grid = atlas_flag_grid(flags),
        out = if (is.null(flags$out)) NULL else as.character(flags$out),
        shard = as.character(flags$shard %||% "1/1"),
        label = if (is.null(flags$label)) NULL else as.character(flags$label)
      )
      invisible(0L)
    },
    "study-default" = {
      if (is.null(flags$release)) stop("study-default needs --release=ID", call. = FALSE)
      atlas_default_study(
        atlas_flag_store(flags), release = as.character(flags$release),
        grid = atlas_flag_grid(flags),
        out = if (is.null(flags$out)) NULL else as.character(flags$out),
        shard = as.character(flags$shard %||% "1/1"),
        workers = as.integer(atlas_flag_number(flags, "workers", 1)),
        plan_only = isTRUE(flags$plan_only)
      )
      invisible(0L)
    },
    "study-compare" = {
      if (is.null(flags$frozen) || is.null(flags$record)) {
        stop("study-compare needs --frozen=ID and --record=ID", call. = FALSE)
      }
      atlas_e9_study(atlas_flag_store(flags), frozen = as.character(flags$frozen),
                     record = as.character(flags$record), grid = atlas_flag_grid(flags))
      invisible(0L)
    },
    {
      message("unknown command: ", command)
      atlas_usage()
      invisible(1L)
    }
  )
}
