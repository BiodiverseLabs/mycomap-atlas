# The baselines scored on the hindcast's later finds (paper E6b and E6a),
# with exactly the scorer the hindcast uses (R/e2score.R).
#
# The test places are the hindcast's: the pull of the release the hindcast
# was made from, split at the cutoff on first-validation date
# (atlas_e2_split). Each taxon is then scored three ways on the same places:
#
#   models    the hindcast release's own models, each under its own grade,
#             and the map a visitor sees (kind "combined", for E15)
#   kernel    E6b's distance kernel, ranked again on each model's own cells
#             (atlas_distance_paired_layers), so every model row has a
#             kernel row on the same place and cells; and, secondary, the
#             kernel over its own 500 km reach
#   default   E6a's default-practice Maxent over its accessible area, under
#             its own null verdict
#
# H6b is atlas_e2_paired on the strong models' rows and their kernel rows.
# Everything written is counts and shares; no place, record or coordinate.

#' A taxon's maps in the hindcast release, as atlas_e2_score takes them:
#' each model under its own grade, and the map a visitor sees.
atlas_score_model_maps <- function(view, taxon) {
  maps <- atlas_tracker_maps(view, taxon)
  if (isTRUE(maps$none)) return(NULL)
  out <- lapply(stats::setNames(names(maps$models), names(maps$models)), function(algorithm) {
    m <- maps$models[[algorithm]]
    list(layers = m[c("raster", "rank", "outside")], grade = m$grade, learner = algorithm, kind = "model")
  })
  if (!is.null(maps$ensemble)) {
    out$combined <- list(layers = maps$ensemble[c("raster", "rank", "outside")], known = maps$ensemble$known,
                         grade = maps$grade, learner = "combined", kind = "combined")
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
    list(layers = atlas_distance_paired_layers(kernel, m$layers), grade = m$grade,
         learner = m$learner, kind = "model")
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

#' Score the baselines on the test places. Pure: the maps come through the
#' functions given. Returns the aggregates written to the results file.
atlas_score_baselines_core <- function(places, model_maps_for, kernel_maps_for = NULL,
                                       default_maps_for = NULL, known_names = NULL,
                                       reps = ATLAS_E2_BOOTSTRAP, seed = 1L) {
  models <- atlas_e2_score(places, model_maps_for, known_names)
  per_model <- models[models$kind %in% "model", , drop = FALSE]
  out <- list(
    places = list(places = nrow(places), off_grid = attr(places, "off_grid") %||% 0L,
                  taxa = length(unique(places$taxon))),
    models = list(by_grade = atlas_score_by_grade(per_model),
                  combined = atlas_score_splits(models[models$kind %in% "combined", , drop = FALSE]))
  )
  if (is.function(kernel_maps_for)) {
    kernel <- atlas_e2_score(places, kernel_maps_for, known_names)
    paired <- kernel[kernel$kind %in% "model", , drop = FALSE]
    have <- unique(paired$taxon[!is.na(paired$map)])
    strong <- per_model[per_model$grade %in% "strong" & per_model$taxon %in% have, , drop = FALSE]
    out$kernel <- list(
      taxa = length(have),
      paired_by_grade = atlas_score_by_grade(paired[!is.na(paired$map), , drop = FALSE]),
      own_reach = atlas_score_splits(kernel[kernel$kind %in% "baseline", , drop = FALSE]),
      H6b = if (nrow(strong)) atlas_e2_paired(strong, paired, reps = reps, seed = seed) else list(tested = FALSE),
      H6b_new = if (nrow(strong)) {
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

#' Each taxon's own null verdict from an E6a results file.
atlas_score_default_verdicts <- function(path) {
  rows <- jsonlite::fromJSON(path, simplifyVector = FALSE)$taxa
  scored <- Filter(function(r) identical(r$status, "scored"), rows)
  stats::setNames(lapply(scored, function(r) r$null$verdict %||% "untested"),
                  vapply(scored, function(r) r$taxon, ""))
}

#' Score E6b's kernels and E6a's maps on the hindcast's later finds.
#'
#' hindcast is the hindcast's private release; from_release the release it
#' was made from, whose pull holds the later finds; cutoff the hindcast's
#' first-validation cutoff. kernels is the directory of an E6b run (its
#' kernels/ folder), defaults the results file of an E6a run (its maps/
#' folder beside it). Writes one results file under data/score-studies/.
atlas_score_study <- function(store = atlas_store(), hindcast, from_release, cutoff, grid = "draft",
                              kernels = NULL, defaults = NULL, observed_after = FALSE,
                              reps = ATLAS_E2_BOOTSTRAP, out = NULL, quiet = FALSE,
                              view = NULL, full_pull = NULL) {
  started <- Sys.time()
  if (!is.null(out)) atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
  view <- view %||% atlas_tracker_view(store, hindcast, grid)
  if (is.null(full_pull)) {
    source <- atlas_tracker_manifest(store, from_release, grid)
    full_pull <- atlas_tracker_release_pull(store, source, grid)
  }
  split <- atlas_e2_split(full_pull, cutoff, observed_after = observed_after, grid = grid)
  places <- atlas_e2_places(split$finds, split$training)
  model_maps_for <- function(taxon) atlas_score_model_maps(view, taxon)
  kernel_maps_for <- if (!is.null(kernels)) {
    function(taxon) atlas_score_kernel_maps(model_maps_for(taxon), atlas_distance_raster_path(kernels, taxon))
  }
  default_maps_for <- if (!is.null(defaults)) {
    verdicts <- atlas_score_default_verdicts(defaults)
    maps_dir <- atlas_score_default_dir(defaults)
    function(taxon) {
      if (is.null(verdicts[[taxon]])) return(NULL)
      atlas_score_default_maps(atlas_default_raster_path(maps_dir, taxon), verdicts[[taxon]])
    }
  }
  result <- c(
    list(started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
         settings = list(hindcast = hindcast, from_release = from_release, cutoff = cutoff,
                         observed_after = observed_after, reps = reps, grid = grid,
                         kernels = !is.null(kernels), defaults = !is.null(defaults)),
         kept_apart = attr(split$finds, "kept_apart")),
    atlas_score_baselines_core(places, model_maps_for, kernel_maps_for, default_maps_for,
                               known_names = view$names, reps = reps),
    list(seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1))
  )
  dir <- atlas_study_out(out, "score-studies", grid, paste0(hindcast, "-", cutoff))
  path <- file.path(dirname(dir$dir), paste0(dir$prefix, "-", format(started, "%Y%m%dT%H%M%SZ", tz = "UTC"), ".json"))
  unlink(dir$dir, recursive = TRUE)
  atlas_write_json(result, path)
  if (!is.null(dir$key)) atlas_study_publish(store, path, dir$key, root = dirname(path))
  if (!isTRUE(quiet)) {
    h <- result$kernel$H6b
    message("E2 places: ", result$places$places, " (", result$places$taxa, " taxa)",
            if (!is.null(h)) paste0("; H6b strong - kernel top half ", round(h$estimate %||% NA, 3),
                                    " [", round(h$low %||% NA, 3), ", ", round(h$high %||% NA, 3), "]"),
            " -> ", path)
  }
  invisible(c(result, list(path = path)))
}

#' Where an E6a run's maps are: the run's directory beside its results
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
    stop(if (length(hit)) "more than one" else "no", " maps directory for ", basename(results_path),
         call. = FALSE)
  }
  hit[[1]]
}
