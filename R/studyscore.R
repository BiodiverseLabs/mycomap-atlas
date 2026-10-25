# The hindcast's later finds, scored (paper E2, and the baselines E6b and
# E6a), with the hindcast's scorer (R/e2score.R).
#
# The test places are the hindcast's: the pull of the release the hindcast
# was made from, split at its first-validation cutoff (atlas_e2_split). Both
# are read from the hindcast's own manifest, never typed in, and the split is
# checked against the hindcast: the records it trains on must be exactly the
# hindcast's pull, and no test find may be one of them. Each taxon is then
# scored three ways on the same places:
#
#   models    the hindcast release's own models, each under its own grade
#             (E2: H2a, H2b, H2c and C2), and the map a visitor sees: the
#             combined map, else the best strong map (kind "combined", E15)
#   kernel    E6b's distance kernel, ranked again on each model's own cells
#             (atlas_distance_paired_layers), so every model row has a
#             kernel row on the same place and cells; and, secondary, the
#             kernel over its own 500 km reach
#   default   E6a's default-practice Maxent over its accessible area, under
#             its own null verdict
#
# A baseline run is taken whole or not at all: its results files must be of
# this hindcast and cover every shard of one split. Everything written is
# counts and shares; no place, record or coordinate.

#' A taxon's maps in the hindcast release, as atlas_e2_score takes them:
#' each model under its own grade, and the map a visitor sees (kind
#' "combined"): the combined map where there is one, else the best strong
#' single map; none for a taxon with no strong map.
atlas_score_model_maps <- function(view, taxon) {
  maps <- atlas_tracker_maps(view, taxon)
  if (isTRUE(maps$none)) return(NULL)
  layers_of <- function(m) m[c("raster", "rank", "outside")]
  out <- lapply(stats::setNames(names(maps$models), names(maps$models)), function(algorithm) {
    m <- maps$models[[algorithm]]
    tier <- atlas_metrics_tier(m$metrics %||% list(grade = m$grade))
    list(layers = layers_of(m), grade = m$grade, tier = tier$tier, moderate_z = tier$moderate_z,
         learner = algorithm, kind = "model")
  })
  if (!is.null(maps$ensemble)) {
    out$combined <- list(layers = layers_of(maps$ensemble), known = maps$ensemble$known,
                         grade = maps$grade, learner = "combined", kind = "combined")
  } else if (!is.null(maps$choice$algorithm) && !is.null(maps$models[[maps$choice$algorithm]])) {
    best <- maps$models[[maps$choice$algorithm]]
    out$combined <- list(layers = layers_of(best), grade = maps$grade, learner = maps$choice$algorithm,
                         kind = "combined")
  }
  out
}

#' A taxon's kernel maps: for each model, the kernel ranked again on that
#' model's cells, under the model's grade and name (so a kernel row pairs
#' with its model row); and the kernel over its own reach. NULL when the
#' taxon has no kernel.
atlas_score_kernel_maps <- function(model_maps, kernel_path) {
  if (is.null(kernel_path) || !file.exists(kernel_path)) return(NULL)
  kernel <- terra::rast(kernel_path)
  models <- Filter(function(m) identical(m$kind, "model"), model_maps %||% list())
  paired <- lapply(models, function(m) {
    list(layers = atlas_distance_paired_layers(kernel, m$layers), grade = m$grade, tier = m$tier,
         moderate_z = m$moderate_z, learner = m$learner, kind = "model")
  })
  c(paired, list(kernel = list(layers = atlas_tracker_layers(kernel), grade = "kernel",
                               learner = "kernel", kind = "baseline")))
}

#' A taxon's default-practice map over its accessible area, under its own
#' null verdict. NULL when it has none.
atlas_score_default_maps <- function(path, verdict) {
  if (is.null(path) || !file.exists(path)) return(NULL)
  list(default = list(layers = atlas_tracker_layers(terra::rast(path)), grade = verdict %||% "untested",
                      learner = "default-maxent", kind = "baseline"))
}

#' The pre-registered splits of a set of scored rows: all places, new and
#' known places, and each distance band; each with the E2 metrics.
atlas_score_splits <- function(rows) {
  out <- list(all = atlas_e2_metrics(rows),
              new = atlas_e2_metrics(rows[rows$new_place %in% TRUE, , drop = FALSE]),
              known = atlas_e2_metrics(rows[rows$new_place %in% FALSE, , drop = FALSE]))
  for (band in sort(unique(stats::na.omit(rows$band)))) {
    out[[paste0("band ", band)]] <- atlas_e2_metrics(rows[rows$band %in% band, , drop = FALSE])
  }
  out
}

#' The E2 metrics of rows by grade, each with its splits.
atlas_score_by_grade <- function(rows) {
  grades <- intersect(c("strong", "weak", "failed", "untested", "passed"), unique(rows$grade))
  lapply(stats::setNames(grades, grades), function(g) atlas_score_splits(rows[rows$grade %in% g, , drop = FALSE]))
}

#' The E2 metrics of rows by map tier (and moderate-z), each with its splits.
atlas_score_by_tier <- function(rows) {
  tiers <- intersect(c(ATLAS_TIERS, "untested"), unique(rows$tier))
  out <- lapply(stats::setNames(tiers, tiers), function(t) atlas_score_splits(rows[rows$tier %in% t, , drop = FALSE]))
  if (any(rows$moderate_z %in% TRUE)) out$moderate_z <- atlas_score_splits(rows[rows$moderate_z %in% TRUE, , drop = FALSE])
  out
}

#' Score the models and baselines on the test places. Pure: the maps come
#' through the functions given. Returns the aggregates written to the
#' results file.
atlas_score_baselines_core <- function(places, model_maps_for, kernel_maps_for = NULL,
                                       default_maps_for = NULL, known_names = NULL,
                                       reps = ATLAS_E2_BOOTSTRAP, seed = 1L) {
  models <- atlas_e2_score(places, model_maps_for, known_names)
  per_model <- models[models$kind %in% "model", , drop = FALSE]
  out <- list(
    places = list(places = nrow(places), off_grid = attr(places, "off_grid") %||% 0L,
                  taxa = length(unique(places$taxon))),
    # E2 itself: the pre-registered hypotheses on the per-model rows, and
    # the numbers by grade.
    hypotheses = atlas_e2_hypotheses(models, reps = reps, seed = seed),
    # Secondary: the looser map tiers (E24), H2d-H2f.
    tier_hypotheses = atlas_e2_tier_hypotheses(models, reps = reps, seed = seed),
    models = list(by_grade = atlas_score_by_grade(per_model), by_tier = atlas_score_by_tier(per_model),
                  combined = atlas_score_splits(models[models$kind %in% "combined", , drop = FALSE]))
  )
  if (is.function(kernel_maps_for)) {
    kernel <- atlas_e2_score(places, kernel_maps_for, known_names)
    paired <- kernel[kernel$kind %in% "model", , drop = FALSE]
    have <- unique(paired$taxon[!is.na(paired$map)])
    same <- per_model[per_model$taxon %in% have, , drop = FALSE]
    strong <- same[same$grade %in% "strong", , drop = FALSE]
    out$kernel <- list(
      taxa = length(have),
      # Both sides on the taxa that have a kernel: the same places and cells.
      paired_by_grade = atlas_score_by_grade(paired[!is.na(paired$map), , drop = FALSE]),
      models_same_taxa = atlas_score_by_grade(same),
      paired_by_tier = atlas_score_by_tier(paired[!is.na(paired$map), , drop = FALSE]),
      models_same_taxa_by_tier = atlas_score_by_tier(same),
      # Each tier against the kernel on the same places (reported).
      tiers_vs_kernel = lapply(stats::setNames(nm = c("moderate", "indicative")), function(t) {
        rows <- same[same$tier %in% t, , drop = FALSE]
        if (nrow(rows)) atlas_e2_paired(rows, paired, grade = t, by = "tier", reps = reps, seed = seed) else
          list(tested = FALSE)
      }),
      own_reach = atlas_score_splits(kernel[kernel$kind %in% "baseline", , drop = FALSE]),
      H6b = if (nrow(strong)) atlas_e2_paired(strong, paired, reps = reps, seed = seed) else list(tested = FALSE),
      H6b_new = if (any(strong$new_place %in% TRUE)) {
        atlas_e2_paired(strong[strong$new_place %in% TRUE, , drop = FALSE], paired, reps = reps, seed = seed)
      } else {
        list(tested = FALSE)
      }
    )
  }
  if (is.function(default_maps_for)) {
    default <- atlas_e2_score(places, default_maps_for, known_names)
    # Rows with no map stay, so the places of taxa without one are counted.
    default <- default[default$kind %in% "baseline" | is.na(default$map), , drop = FALSE]
    taxa <- unique(default$taxon[!is.na(default$map)])
    out$default <- list(
      taxa = length(taxa),
      all = atlas_score_splits(default),
      by_verdict = atlas_score_by_grade(default),
      # Atlas's own models on the same taxa, for the comparison E6a reports.
      atlas_same_taxa = atlas_score_by_grade(per_model[per_model$taxon %in% taxa, , drop = FALSE])
    )
  }
  out
}

#' A baseline run, taken whole: its results files must all be of release
#' hindcast and cover every shard 1..n of one split, each once. Returns the
#' run's directories (where its maps are) and its rows.
atlas_score_run <- function(paths, hindcast, dirs = NULL) {
  results <- lapply(paths, function(p) jsonlite::fromJSON(p, simplifyVector = FALSE))
  releases <- vapply(results, function(r) as.character(r$settings$release %||% NA), "")
  if (!all(releases %in% hindcast)) {
    stop("a baseline run is not of hindcast ", hindcast, " (it was run on ",
         paste(unique(releases[!releases %in% hindcast]), collapse = ", "), ")", call. = FALSE)
  }
  shards <- vapply(results, function(r) as.character(r$settings$shard %||% "1/1"), "")
  if (anyDuplicated(shards)) stop("a shard appears twice: ", shards[duplicated(shards)][[1]], call. = FALSE)
  of <- unique(sub("^.*/", "", shards))
  if (length(of) != 1L) stop("the baseline's shards come from different splits", call. = FALSE)
  if (!setequal(as.integer(sub("/.*$", "", shards)), seq_len(as.integer(of)))) {
    stop("the baseline run is missing shards: has ", paste(sort(shards), collapse = ", "), call. = FALSE)
  }
  rows <- do.call(c, lapply(results, function(r) r$taxa))
  taxa <- vapply(rows, function(r) as.character(r$taxon), "")
  if (anyDuplicated(taxa)) stop("a taxon appears in two shards: ", taxa[duplicated(taxa)][[1]], call. = FALSE)
  list(dirs = dirs %||% vapply(paths, atlas_score_default_dir, ""), rows = rows)
}

#' The kernels of one or more distance study jobs, read as one run. The
#' first job is the whole run (every shard of it); each later job is a patch
#' (study-distance --taxa) of taxa no earlier job scored: its scored taxa
#' replace the earlier unscored rows (a mismatch, refusal or failure), and
#' the rest stay as they were. Refused: a patch taxon an earlier job already
#' scored, or one the first job never tried. fetch is replaceable for tests.
atlas_score_kernel_runs <- function(store, jobs, hindcast, fetch = atlas_score_fetch_kernels) {
  jobs <- as.character(jobs)
  if (!length(jobs) || anyDuplicated(jobs)) stop("--kernels-from needs distinct job ids", call. = FALSE)
  runs <- lapply(jobs, function(job) {
    fetched <- fetch(store, job)
    c(atlas_score_run(fetched$paths, hindcast, dirs = fetched$dir), list(job = job, files = length(fetched$paths)))
  })
  taxon_of <- function(rows) vapply(rows, function(r) as.character(r$taxon), "")
  rows <- runs[[1]]$rows
  from <- rep(jobs[[1]], length(rows))
  patched <- list()
  for (run in runs[-1]) {
    for (r in run$rows) {
      at <- match(as.character(r$taxon), taxon_of(rows))
      if (is.na(at)) {
        stop("patch job ", run$job, " holds ", r$taxon, ", which ", jobs[[1]], " never tried", call. = FALSE)
      }
      if (identical(rows[[at]]$status, "scored")) {
        stop("patch job ", run$job, " holds ", r$taxon, ", which ", from[[at]], " already scored", call. = FALSE)
      }
      if (!identical(r$status, "scored")) next
      rows[[at]] <- r
      from[[at]] <- run$job
      patched[[run$job]] <- c(patched[[run$job]], as.character(r$taxon))
    }
  }
  # Each taxon has a kernel in at most one job (refused above otherwise), so
  # the order of the directories does not decide which kernel is found.
  list(dirs = unlist(lapply(runs, `[[`, "dirs")), rows = rows,
       files = sum(vapply(runs, `[[`, 0L, "files")),
       patched = lapply(patched, function(t) as.list(sort(t))))
}

#' A distance study's results from the store (study/<job>/), for scoring on
#' a machine that did not run it (an EC2 study job): every shard's results
#' file, and every kernel raster merged into one directory. The shards'
#' own directories share one name prefix with different stamps, so they are
#' not told apart by name; merged, each taxon's kernel is found once (a
#' taxon is in one shard only). Returns the results files and that directory.
atlas_score_fetch_kernels <- function(store, job_id, dest = tempfile("kernels-")) {
  prefix <- paste0("study/", job_id, "/")
  keys <- sub("^/", "", store$list(prefix))
  rest <- substring(keys, nchar(prefix) + 1L)
  results <- keys[grepl("^[^/]+[.]json$", rest)]
  rasters <- keys[grepl("/kernels/[^/]+[.]tif$", rest)]
  if (!length(results)) stop("no results file under ", prefix, call. = FALSE)
  if (anyDuplicated(basename(rasters))) {
    stop("a kernel appears in two shards under ", prefix, ": ", basename(rasters)[duplicated(basename(rasters))][[1]],
         call. = FALSE)
  }
  paths <- file.path(dest, "results", basename(results))
  for (i in seq_along(results)) store$get(results[[i]], paths[[i]])
  for (key in rasters) store$get(key, file.path(dest, "kernels", basename(key)))
  list(paths = paths, dir = dest, kernels = length(rasters))
}

#' A default-practice study's results from the store (study/<job>/), for
#' scoring on a machine that did not run it, as atlas_score_fetch_kernels does
#' for kernels: every shard's results file, and every map (maps/<taxon>.tif)
#' merged into one directory, a taxon being in one shard only.
atlas_score_fetch_defaults <- function(store, job_id, dest = tempfile("defaults-")) {
  prefix <- paste0("study/", job_id, "/")
  keys <- sub("^/", "", store$list(prefix))
  rest <- substring(keys, nchar(prefix) + 1L)
  results <- keys[grepl("^[^/]+[.]json$", rest)]
  maps <- keys[grepl("/maps/[^/]+[.]tif$", rest)]
  if (!length(results)) stop("no results file under ", prefix, call. = FALSE)
  if (anyDuplicated(basename(maps))) {
    stop("a map appears in two shards under ", prefix, ": ", basename(maps)[duplicated(basename(maps))][[1]],
         call. = FALSE)
  }
  paths <- file.path(dest, "results", basename(results))
  for (i in seq_along(results)) store$get(results[[i]], paths[[i]])
  for (key in maps) store$get(key, file.path(dest, "maps", basename(key)))
  list(paths = paths, dir = dest, maps = length(maps))
}

#' The first of a run's directories that holds the taxon's file, or NULL.
atlas_score_find <- function(dirs, path_of, taxon) {
  for (dir in dirs) {
    path <- path_of(dir, taxon)
    if (file.exists(path)) return(path)
  }
  NULL
}

#' Score the hindcast's later finds: its models (E2), and E6b's kernels and
#' E6a's maps when their runs are given.
#'
#' hindcast is the hindcast's private release. The release it was made from
#' and its cutoff are read from its manifest; from_release and cutoff, when
#' given, must agree with it. kernels and defaults are the results files of
#' a whole E6b or E6a run on this hindcast (every shard), with each run's
#' directory beside its file. Writes one results file under
#' data/score-studies/ (and its store prefix with out).
atlas_score_study <- function(store = atlas_store(), hindcast, from_release = NULL, cutoff = NULL,
                              grid = "draft", kernels = NULL, defaults = NULL, observed_after = FALSE,
                              reps = ATLAS_E2_BOOTSTRAP, seed = 1L, out = NULL, quiet = FALSE,
                              view = NULL, full_pull = NULL, exclude = character(), hold = character(),
                              allow_missing_excludes = FALSE, refits = character(), refit_views = NULL,
                              kernels_from = NULL, defaults_from = NULL,
                              fetch_defaults = atlas_score_fetch_defaults) {
  started <- Sys.time()
  if (!is.null(out)) atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
  if (!is.null(kernels) && !is.null(kernels_from)) {
    stop("give --kernels or --kernels-from, not both", call. = FALSE)
  }
  if (!is.null(defaults) && !is.null(defaults_from)) {
    stop("give --defaults or --defaults-from, not both", call. = FALSE)
  }
  if (!is.null(defaults_from) && length(defaults_from) != 1L) {
    stop("--defaults-from takes one default-practice study job", call. = FALSE)
  }
  if (length(reps) != 1L || !is.finite(reps) || reps < 1 || reps != round(reps)) {
    stop("reps must be a whole number of resamples, 1 or more", call. = FALSE)
  }
  view <- view %||% atlas_tracker_view(store, hindcast, grid)
  made <- view$manifest
  if (!identical(made$purpose, "hindcast") || is.null(made$validated_through) || is.null(made$from_release)) {
    stop(hindcast, " is not a hindcast: its manifest names no cutoff and source release", call. = FALSE)
  }
  if (!is.null(cutoff) && !identical(as.character(cutoff), made$validated_through)) {
    stop("--cutoff ", cutoff, " is not the hindcast's (", made$validated_through, ")", call. = FALSE)
  }
  if (!is.null(from_release) && !identical(as.character(from_release), made$from_release)) {
    stop("--from-release ", from_release, " is not the hindcast's (", made$from_release, ")", call. = FALSE)
  }
  cutoff <- made$validated_through
  from_release <- made$from_release
  kernel_run <- if (!is.null(kernels)) {
    atlas_score_run(kernels, hindcast)
  } else if (!is.null(kernels_from)) {
    atlas_score_kernel_runs(store, kernels_from, hindcast)
  }
  default_run <- if (!is.null(defaults)) {
    atlas_score_run(defaults, hindcast)
  } else if (!is.null(defaults_from)) {
    # E6a's maps, from the study job that made them (a scoring job's machine
    # has none of its own).
    fetched <- fetch_defaults(store, as.character(defaults_from))
    atlas_score_run(fetched$paths, hindcast, dirs = fetched$dir)
  }
  if (is.null(full_pull)) {
    full_pull <- atlas_tracker_release_pull(store, atlas_tracker_manifest(store, from_release, grid), grid)
  }
  split <- atlas_e2_split(full_pull, cutoff, observed_after = observed_after, grid = grid,
                          exclude = exclude, hold = hold)
  # An excluded id that is no find is most likely a typo, and a typo would
  # leave the record it meant scored: refuse, naming them, unless told.
  if (length(split$exclude_missing) && !isTRUE(allow_missing_excludes)) {
    stop("--exclude names no later find for ", paste(split$exclude_missing, collapse = ", "),
         " (pass --allow-missing-excludes to go on without them)", call. = FALSE)
  }
  missing <- atlas_score_check_split(split, sort(unique(view$pull$key)))
  # Names as the release knows them (renames and spellings, as the tracker
  # matches them); a name it does not know stays as it is, and is counted.
  rename <- function(names) {
    vapply(names, function(n) {
      match <- if (!is.na(n)) atlas_best_match(n, view$names, view$renames)
      if (is.null(match)) n else match$name
    }, "", USE.NAMES = FALSE)
  }
  split$finds$taxon <- rename(split$finds$taxon)
  split$training$taxon <- rename(split$training$taxon)
  places <- atlas_e2_places(split$finds, split$training)

  # A taxon a refit of this hindcast refitted is scored on the refit's maps;
  # every other taxon on the hindcast's.
  refit_views <- refit_views %||% atlas_score_refits(store, refits, hindcast, grid)
  refit_of <- list()
  for (r in refit_views) for (taxon in r$taxa) refit_of[[taxon]] <- r$view
  model_maps_for <- function(taxon) atlas_score_model_maps(refit_of[[taxon]] %||% view, taxon)
  kernel_maps_for <- if (!is.null(kernel_run)) {
    function(taxon) atlas_score_kernel_maps(model_maps_for(taxon),
                                            atlas_score_find(kernel_run$dirs, atlas_distance_raster_path, taxon))
  }
  default_maps_for <- if (!is.null(default_run)) {
    scored <- Filter(function(r) identical(r$status, "scored"), default_run$rows)
    verdicts <- stats::setNames(lapply(scored, function(r) r$null$verdict %||% "untested"),
                                vapply(scored, function(r) r$taxon, ""))
    function(taxon) {
      if (is.null(verdicts[[taxon]])) return(NULL)
      atlas_score_default_maps(atlas_score_find(default_run$dirs, atlas_default_raster_path, taxon),
                               verdicts[[taxon]])
    }
  }
  result <- c(
    list(started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
         settings = list(hindcast = hindcast, from_release = from_release, cutoff = cutoff,
                         observed_after = observed_after, reps = as.integer(reps), seed = as.integer(seed),
                         grid = grid, kernel_shards = if (!is.null(kernels)) length(kernels) else
                           if (!is.null(kernels_from)) kernel_run$files else 0L,
                         kernels_from = if (!is.null(kernels_from)) as.list(kernels_from),
                         kernels_patched = if (!is.null(kernels_from)) kernel_run$patched,
                         default_shards = if (!is.null(defaults_from)) length(fetched$paths) else length(defaults),
                         defaults_from = if (!is.null(defaults_from)) as.character(defaults_from),
                         excluded = length(unique(exclude)), held = length(unique(hold)),
                         excluded_leaks = length(intersect(missing, split$excluded_keys)),
                         ids_not_found = attr(split$finds, "not_found") %||% 0L,
                         excludes_not_found = length(split$exclude_missing),
                         refits = lapply(refit_views, function(r) list(release = r$id, taxa = as.list(r$taxa)))),
         kept_apart = attr(split$finds, "kept_apart")),
    atlas_score_baselines_core(places, model_maps_for, kernel_maps_for, default_maps_for,
                               known_names = view$names, reps = as.integer(reps), seed = as.integer(seed)),
    list(seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1))
  )
  stamp <- format(started, "%Y%m%dT%H%M%SZ", tz = "UTC")
  path <- atlas_path("score-studies", grid, paste0("score-", gsub("[^A-Za-z0-9]+", "-", hindcast), "-", stamp, ".json"),
                     create = TRUE)
  atlas_write_json(result, path)
  if (!is.null(out)) atlas_study_publish(store, path, out, root = dirname(path))
  if (!isTRUE(quiet)) {
    h <- result$kernel$H6b
    message("E2 places: ", result$places$places, " (", result$places$taxa, " taxa); C2 ",
            if (isTRUE(result$hypotheses$C2)) "supported" else "not supported",
            if (!is.null(h)) paste0("; H6b strong - kernel top half ", round(h$estimate %||% NA, 3),
                                    " [", round(h$low %||% NA, 3), ", ", round(h$high %||% NA, 3), "]"),
            " -> ", path)
  }
  invisible(c(result, list(path = path)))
}

#' Where a study run's files are: the run's directory beside its results
#' file, named <prefix>-<stamp>. The results file carries a stamp of its own
#' (atlas_run_study), usually the same second; a directory with exactly its
#' name is taken first, else the one directory of that prefix, and more than
#' one is refused rather than guessed.
atlas_score_default_dir <- function(results_path) {
  exact <- sub("[.]json$", "", results_path)
  if (dir.exists(exact)) return(exact)
  base <- sub("-[0-9]{8}T[0-9]{6}Z[.]json$", "", basename(results_path))
  candidates <- list.dirs(dirname(results_path), recursive = FALSE)
  names <- basename(candidates)
  prefix <- paste0(base, "-")
  stamps <- substring(names, nchar(prefix) + 1L)
  hit <- candidates[startsWith(names, prefix) & grepl("^[0-9]{8}T[0-9]{6}Z$", stamps)]
  if (length(hit) != 1L) {
    stop(if (length(hit)) "more than one" else "no", " directory for ", basename(results_path),
         call. = FALSE)
  }
  hit[[1]]
}

#' Record ids from a flag: "590501,586958", or "@path" for a file of ids, one
#' per line (blank lines and lines starting with # ignored). Only digits.
atlas_score_ids <- function(value) {
  if (is.null(value) || isTRUE(value)) return(character())
  value <- as.character(value)
  ids <- if (startsWith(value, "@")) readLines(substring(value, 2L), warn = FALSE) else strsplit(value, ",", fixed = TRUE)[[1]]
  ids <- trimws(ids)
  ids <- ids[nzchar(ids) & !startsWith(ids, "#")]
  if (any(!grepl("^[0-9]+$", ids))) stop("record ids are whole numbers, not '", ids[!grepl("^[0-9]+$", ids)][[1]], "'", call. = FALSE)
  unique(ids)
}

#' The split must be the hindcast's own: it trains on exactly the records
#' the hindcast was fitted on, and no later find it scores is one of them.
#' The one difference allowed is an excluded find the hindcast trained on (a
#' record whose first-validation date was wrong when the hindcast was
#' planned): it is kept apart, never scored, and counted as a known leak.
#' Then, on its own, only an excluded find may be one of the hindcast's
#' training records: any other later find among them (scored, held or kept
#' apart for another reason) stops the run. Returns the hindcast's training
#' keys the split lacks (the known leaks).
atlas_score_check_split <- function(split, hindcast_keys) {
  extra <- setdiff(split$training_keys, hindcast_keys)
  missing <- setdiff(hindcast_keys, split$training_keys)
  unexplained <- setdiff(missing, split$excluded_keys)
  if (length(extra) || length(unexplained)) {
    stop("the split's training records are not the hindcast's (", length(extra), " more, ", length(unexplained),
         " fewer, not excluded): wrong source release or cutoff", call. = FALSE)
  }
  not_excluded <- !(split$finds$kept_apart %in% "excluded")
  if (any(split$finds$key[not_excluded] %in% hindcast_keys)) {
    stop("a later find is one of the hindcast's training records and is not excluded", call. = FALSE)
  }
  missing
}

#' Refits of this hindcast (plan-job --hindcast --leave-out: some taxa's
#' models fitted again without listed records), each with the taxa it
#' refitted. A release that is not a refit of this very hindcast is refused,
#' and so is a taxon refitted by two of them.
atlas_score_refits <- function(store, refits, hindcast, grid = "draft", view_of = atlas_tracker_view) {
  out <- lapply(unique(as.character(refits)), function(id) {
    view <- view_of(store, id, grid)
    made <- view$manifest$refit
    if (is.null(made) || !identical(as.character(made$hindcast %||% ""), hindcast)) {
      stop(id, " is not a refit of hindcast ", hindcast, call. = FALSE)
    }
    taxa <- as.character(unlist(made$taxa %||% list()))
    if (!length(taxa)) stop("refit ", id, " names no taxa", call. = FALSE)
    list(id = id, view = view, taxa = taxa)
  })
  taxa <- unlist(lapply(out, `[[`, "taxa"))
  if (anyDuplicated(taxa)) stop("two refits both refit ", taxa[duplicated(taxa)][[1]], call. = FALSE)
  out
}
