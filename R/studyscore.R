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
atlas_score_run <- function(paths, hindcast) {
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
  list(dirs = vapply(paths, atlas_score_default_dir, ""), rows = rows)
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
                              view = NULL, full_pull = NULL, exclude = character(), hold = character()) {
  started <- Sys.time()
  if (!is.null(out)) atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
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
  kernel_run <- if (!is.null(kernels)) atlas_score_run(kernels, hindcast)
  default_run <- if (!is.null(defaults)) atlas_score_run(defaults, hindcast)
  if (is.null(full_pull)) {
    full_pull <- atlas_tracker_release_pull(store, atlas_tracker_manifest(store, from_release, grid), grid)
  }
  split <- atlas_e2_split(full_pull, cutoff, observed_after = observed_after, grid = grid,
                          exclude = exclude, hold = hold)
  # The split must be the hindcast's own: it trains on exactly the records
  # the hindcast was fitted on, and no later find it scores is one of them.
  # The one difference allowed is an excluded find the hindcast trained on
  # (a record whose first-validation date was wrong when the hindcast was
  # planned): it is kept apart, never scored, and counted as a known leak.
  hindcast_keys <- sort(unique(view$pull$key))
  extra <- setdiff(split$training_keys, hindcast_keys)
  missing <- setdiff(hindcast_keys, split$training_keys)
  unexplained <- setdiff(missing, split$excluded_keys)
  if (length(extra) || length(unexplained)) {
    stop("the split's training records are not the hindcast's (", length(extra), " more, ", length(unexplained),
         " fewer, not excluded): wrong source release or cutoff", call. = FALSE)
  }
  scored <- is.na(split$finds$kept_apart)
  if (any(split$finds$key[scored] %in% hindcast_keys)) {
    stop("a later find is one of the hindcast's training records", call. = FALSE)
  }
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

  model_maps_for <- function(taxon) atlas_score_model_maps(view, taxon)
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
                         grid = grid, kernel_shards = length(kernels), default_shards = length(defaults),
                         excluded = length(unique(exclude)), held = length(unique(hold)),
                         excluded_leaks = length(intersect(missing, split$excluded_keys)),
                         ids_not_found = attr(split$finds, "not_found") %||% 0L),
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
