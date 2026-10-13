# Refit reproducibility (paper E12, its first gate): the same models fitted
# again from a job's own inputs, several times in fresh R processes on one
# machine, against what the release holds.
#
# The full-view refresh of 2026-10-13 refitted the frozen release's 576 strong
# models on other machines: three tuned Maxent models chose other settings,
# and for two of them (Stropharia hardii, Gliophorus fumosus) the
# cross-validated AUC of every tuning candidate moved, on the same pull,
# presences and background. On one PC the same two fits came out bit for bit
# the same in fresh processes and in any order, but that PC has neither the
# frozen pull nor the image's BLAS. This study asks it on a worker of the
# image itself: two or more fresh-process fits of each model, compared with
# each other (does one machine give one answer?) and with the release (does
# this machine give the release's?). Run once on each processor family
# (ATLAS_EC2_INSTANCE_TYPES at run time), it separates a machine effect from
# run-to-run non-determinism.
#
#   ./atlas plan-study --command=study-repro --shards=1 \
#     --args="--release=<frozen> --source-job=<job that fitted them> --taxa=Name%20one|Name%20two --runs=2 --label=r7i"
#   ATLAS_EC2_INSTANCE_TYPES=r7i.2xlarge ./atlas run-job-ec2 --job=<ID>
#
# Each run fits exactly as a shard does (atlas_fit_batch, the job's own fit
# settings) but with no null test and no full view: tuning, scores and the
# default map are what the refresh compared. Nothing here writes a model to
# the store or a release: one results file under the study's prefix.

ATLAS_REPRO_RUNS <- 2L

#' The taxa a --taxa flag names: separated by "|", since names hold spaces
#' and commas never. plan-study splits a study's arguments at spaces, so a
#' name may be percent-encoded there (Stropharia%20hardii, %27 for a quote).
atlas_repro_taxa <- function(text) {
  taxa <- trimws(strsplit(as.character(text %||% ""), "|", fixed = TRUE)[[1]])
  taxa <- vapply(taxa, utils::URLdecode, "", USE.NAMES = FALSE)
  taxa <- unique(taxa[nzchar(taxa)])
  if (!length(taxa)) stop("study-repro needs --taxa='Name one|Name two'", call. = FALSE)
  taxa
}

#' One run: fit the taxa as a shard of `job` would (no nulls, no full view)
#' and return what each fit chose and scored, read back from its metrics and
#' default raster. Runs in the calling process; atlas_repro_fresh_run runs it
#' in a new one.
atlas_repro_fit <- function(taxa, algorithm, fit_settings, grid = "draft") {
  s <- fit_settings
  atlas_fit_batch(
    grid = grid, force = TRUE, workers = 1L, taxa = taxa, algorithm = algorithm,
    min_presences = s$min_presences %||% 20, n_background = s$n_background %||% 10000,
    buffer_km = s$buffer_km %||% 500, folds = s$folds %||% 5, block_km = s$block_km %||% "auto",
    regmult = s$regmult %||% 1, correlation = s$correlation %||% 0.7,
    nulls = 0, tune = s$tune %||% TRUE, full = FALSE, quiet = TRUE
  )
  lapply(stats::setNames(taxa, taxa), function(name) {
    m <- atlas_read_metrics(name, grid, algorithm)
    if (is.null(m)) return(list(taxon = name, status = "not fitted"))
    tif <- atlas_model_path(name, grid, ".tif", algorithm)
    atlas_repro_summary(m, if (file.exists(tif)) atlas_sha256(tif))
  })
}

#' What a fit chose and scored, from its metrics: the parts a rerun must
#' reproduce.
atlas_repro_summary <- function(m, tif_sha256 = NULL) {
  num <- function(x) if (is.null(x)) NA_real_ else suppressWarnings(as.numeric(unlist(x)))
  Filter(Negate(is.null), list(
    taxon = m$taxon, status = "fitted",
    presences = num(m$presences), background = num(m$background),
    predictors = as.character(unlist(m$predictors)),
    settings = atlas_params_label(m$params),
    tuning = num(m$tuning),
    auc_mean = num(m$auc_mean), boyce = num(m$boyce),
    fold_auc = vapply(m$folds %||% list(), function(f) num(f$auc)[1], numeric(1)),
    tif_sha256 = tif_sha256
  ))
}

#' A run in a fresh R process (Rscript, the installed package), so nothing a
#' fit leaves in a process can reach the next run.
atlas_repro_fresh_run <- function(taxa, algorithm, fit_settings, grid = "draft") {
  dir <- tempfile("repro-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  # Forward slashes: the paths are written into R code, where a Windows
  # backslash would be an escape.
  input <- normalizePath(file.path(dir, "in.json"), winslash = "/", mustWork = FALSE)
  output <- normalizePath(file.path(dir, "out.json"), winslash = "/", mustWork = FALSE)
  atlas_write_json(list(taxa = as.list(taxa), algorithm = algorithm, fit = fit_settings, grid = grid), input)
  code <- sprintf(paste0("x <- jsonlite::fromJSON('%s', simplifyVector = FALSE); ",
                         "r <- mycomapatlas:::atlas_repro_fit(unlist(x$taxa), x$algorithm, x$fit, x$grid); ",
                         "mycomapatlas:::atlas_write_json(r, '%s')"), input, output)
  status <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)))
  if (!identical(as.integer(status), 0L) || !file.exists(output)) {
    stop("a fresh-process run failed (exit ", status, ")", call. = FALSE)
  }
  jsonlite::fromJSON(output, simplifyVector = FALSE)
}

#' The release's own fit of each taxon, summarised the same way.
atlas_repro_release_fits <- function(store, release, taxa, algorithm, grid = "draft") {
  files <- stats::setNames(release$files, vapply(release$files, function(f) f$path, ""))
  lapply(stats::setNames(taxa, taxa), function(name) {
    json <- files[[atlas_model_relpaths(name, grid, algorithm, ".json")]]
    if (is.null(json)) return(list(taxon = name, status = "not in the release"))
    file <- tempfile(fileext = ".json")
    on.exit(unlink(file), add = TRUE)
    store$get(atlas_object_key(json$sha256), file)
    tif <- files[[atlas_model_relpaths(name, grid, algorithm, ".tif")]]
    atlas_repro_summary(jsonlite::fromJSON(file, simplifyVector = FALSE), tif$sha256)
  })
}

#' How two fits of one model compare: the same in every part, or which parts
#' differ, with the largest change in a tuning candidate's score.
atlas_repro_compare <- function(a, b) {
  if (!identical(a$status, "fitted") || !identical(b$status, "fitted")) {
    return(list(identical = FALSE, differs = list("not both fitted")))
  }
  parts <- c("presences", "background", "predictors", "settings", "tuning", "auc_mean", "boyce",
             "fold_auc", "tif_sha256")
  num_same <- function(x, y) length(x) == length(y) && isTRUE(all(x == y | (is.na(x) & is.na(y))))
  differs <- Filter(function(p) {
    x <- unlist(a[[p]]); y <- unlist(b[[p]])
    if (is.null(x) || is.null(y)) return(!identical(is.null(x), is.null(y)))
    if (is.numeric(x) && is.numeric(y)) !num_same(x, y) else !identical(as.character(x), as.character(y))
  }, parts)
  ta <- as.numeric(unlist(a$tuning)); tb <- as.numeric(unlist(b$tuning))
  comparable <- length(ta) > 0L && length(ta) == length(tb) && any(!is.na(ta - tb))
  Filter(Negate(is.null), list(
    identical = !length(differs), differs = as.list(differs),
    tuning_max_difference = if (comparable) max(abs(ta - tb), na.rm = TRUE),
    tuning_correlation = if (length(ta) > 2L && length(ta) == length(tb) && stats::sd(ta) > 0 && stats::sd(tb) > 0)
      round(stats::cor(ta, tb), 4)
  ))
}

#' The study: fetch the source job's inputs, fit the taxa `runs` times in
#' fresh processes, and compare the runs with each other and with the
#' release. run is replaceable for tests (in-process).
atlas_repro_study <- function(store = atlas_store(), release, source_job, taxa, algorithm = "maxnet",
                              runs = ATLAS_REPRO_RUNS, grid = "draft", out = NULL, shard = "1/1",
                              label = NULL, run = atlas_repro_fresh_run, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  runs <- as.integer(runs)
  if (is.na(runs) || runs < 2L) stop("study-repro needs --runs of 2 or more", call. = FALSE)
  taxa <- atlas_study_shard(atlas_repro_taxa(paste(taxa, collapse = "|")), shard)
  key <- paste0("releases/", grid, "/", release, ".json")
  if (!store$exists(key)) stop("no release ", release, " for the ", grid, " grid", call. = FALSE)
  base <- atlas_store_text(store, key)
  job <- atlas_read_job(store, source_job, grid)
  if (is.null(atlas_job_pull_entry(job))) stop("job ", source_job, " names no pull", call. = FALSE)
  fetched <- atlas_fetch_entries(store, job$inputs)
  say("study-repro: ", length(taxa), " ", algorithm, " model(s) x ", runs, " fresh runs on the inputs of job ",
      source_job, " (", fetched$fetched, " files fetched)")
  machine <- atlas_machine_info()
  fits <- lapply(seq_len(runs), function(i) {
    started <- Sys.time()
    r <- run(taxa, algorithm, job$fit %||% list(), grid)
    say("  run ", i, " done in ", round(as.numeric(difftime(Sys.time(), started, units = "secs"))), " s")
    r
  })
  released <- atlas_repro_release_fits(store, base, taxa, algorithm, grid)
  models <- lapply(taxa, function(name) {
    mine <- lapply(fits, function(f) f[[name]])
    list(
      taxon = name, algorithm = algorithm, runs = mine, release = released[[name]],
      runs_agree = all(vapply(mine[-1], function(x) isTRUE(atlas_repro_compare(mine[[1]], x)$identical), logical(1))),
      between_runs = lapply(mine[-1], function(x) atlas_repro_compare(mine[[1]], x)),
      against_release = atlas_repro_compare(released[[name]], mine[[1]])
    )
  })
  result <- list(
    study = "repro", label = label, release = release, source_job = source_job, algorithm = algorithm,
    runs = runs, machine = machine, image_commit = Sys.getenv("ATLAS_COMMIT", unset = NA),
    at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    summary = list(models = length(models),
                   runs_agree = sum(vapply(models, function(m) isTRUE(m$runs_agree), logical(1))),
                   match_release = sum(vapply(models, function(m) isTRUE(m$against_release$identical), logical(1)))),
    models = models
  )
  where <- atlas_study_out(out, "repro-studies", grid, paste(label %||% "repro", release))
  path <- file.path(where$dir, paste0(where$prefix, ".json"))
  atlas_write_json(result, path)
  if (!is.null(where$key)) atlas_study_publish(store, path, where$key, where$dir)
  for (m in models) {
    say(sprintf("  %s: runs agree %s; vs release: %s", m$taxon, m$runs_agree,
                if (isTRUE(m$against_release$identical)) "identical" else
                  paste("differs in", paste(unlist(m$against_release$differs), collapse = ", "))))
  }
  invisible(result)
}
