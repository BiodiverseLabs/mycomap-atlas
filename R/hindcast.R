# A private release: Atlas fitted in full on a variant of a release's pull,
# graded by its own null tests, finished as any release is, and kept where
# nothing public can reach it (Steve, 2026-10-13).
#
# Two purposes, one machinery:
#
#   hindcast      Atlas as it would have been at a cutoff (Atlas E2, and
#                 MycoMap Vision's R_train): the release's pull with only the
#                 records first validated (first_green_on, R/firstgreen.R) on
#                 or before the cutoff; records with no first green date are
#                 left out and counted, since nothing says they were known
#                 by then. Never the observation date.
#   record-names  Atlas with each record under .org's own name for it instead
#                 of its approved sequence's (Atlas E9): the same records,
#                 named as their observers named them. Only the models whose
#                 record set changes are fitted: a taxon with the same records
#                 under the same name would refit to the release's own model.
#
# Unlike a prior-only job (R/prioronly.R), which refits R_main's strong
# models and inherits their grades, this plans every taxon afresh, with the
# release's settings, null tests and tuning, so its grades are its own: a
# release that saw the test records cannot be the one that grades them.
#
# Everything record-derived comes from the variant pull: survey sites,
# effort, background and each taxon's accessible area are built on the
# worker from the pull the job carries (R/background.R), never the box's.
#
# Its finishing runs the same builders a release's finishing does (R/finish.R:
# counts by state, combined maps, the here index, the prior with its trust
# signals, the weak maps' ranks, the continent export from full views on the
# sliver-free scope) on one worker, and files everything privately:
#
#   private/vision-benchmark/<id>/release.json     its files and model index (never under releases/)
#   private/vision-benchmark/<id>/prior/<grid>/     the prior export
#   private/vision-benchmark/<id>/continent/<grid>/ the continent export
#   private/vision-benchmark/<id>/here/<grid>/      the here index
#   private/vision-benchmark/<id>/weak/<grid>/      the weak maps' ranks
#   private/vision-benchmark/<id>/models.tsv.gz     every model's grade, strength and scores
#   private/vision-benchmark/<id>/summary.json      what was filtered, fitted, graded and cost
#   private/trained-ids/<grid>/releases/<id>.tsv.gz the records it trained on
#
# It is never a release: nothing is written under releases/ or current/,
# so it cannot be promoted, pulled, served, archived or put in a sitemap.
#
#   ./atlas plan-job --hindcast --from-release=<R_main> --validated-through=YYYY-MM-DD [--dry-run]
#   ./atlas plan-job --record-names --from-release=<R_main> [--dry-run]
#   ./atlas plan-job --hindcast --from-release=<hindcast priv-ID> --taxa=NAME[,NAME] --leave-out=ID[,ID]
#                    [--validated-through=YYYY-MM-DD] [--dry-run]
#   ./atlas run-job-ec2 --job=<ID>      (fits the shards, then finishes it on one worker)
#
# The third refits some of a finished hindcast's taxa without listed .org
# records (atlas_plan_hindcast_refit): a private release of its own, the
# hindcast's in everything but those records, the hindcast left untouched.

atlas_is_private_release <- function(job) identical(job$kind, "private-release")

ATLAS_PRIVATE_PURPOSES <- c("hindcast", "record-names")

# Seconds per model for the plan's estimate when the release's job has no
# timed results: a full fit with tuning and null tests (the 2026-10-12/13
# timings, after the short-path pass budget).
ATLAS_PRIVATE_SECONDS <- c(maxnet = 1500, rf = 600, xgboost = 300, esm = 120)

#' The pull named by records' own names (R/labels.R keeps .org's name in
#' record_name beside the sequence's): a record keeps its place under its
#' record name when that is species level, and is left out otherwise.
atlas_record_named <- function(occurrences) {
  if (!"record_name" %in% names(occurrences)) {
    stop("this pull carries no record names: it was made before they were kept", call. = FALSE)
  }
  name <- trimws(as.character(occurrences$record_name))
  species <- !is.na(name) & grepl(" ", name) &
    !grepl(" sp[.]?$", tolower(name)) & !tolower(name) %in% c("fungi", "unknown")
  out <- occurrences[species, , drop = FALSE]
  # Reading a pull names each record from original_name (R/names.R), so the
  # record name goes there too, with the same spelling merges.
  out$scientific_name <- name[species]
  out$original_name <- name[species]
  out <- atlas_canonicalise_occurrences(out)
  rownames(out) <- NULL
  list(occurrences = out, counts = list(records_in_pull = nrow(occurrences), records_kept = nrow(out),
                                        records_not_species_level = sum(!species)))
}

#' Seconds per model by algorithm: the mean of the release job's own timed
#' fits where it has them, else ATLAS_PRIVATE_SECONDS.
atlas_private_seconds <- function(store, job_id, grid = "draft") {
  measured <- tryCatch(atlas_job_timing(store, job_id, grid)$per_algorithm, error = function(e) NULL)
  out <- ATLAS_PRIVATE_SECONDS
  if (!is.null(measured) && nrow(measured)) {
    for (i in seq_len(nrow(measured))) out[[measured$algorithm[[i]]]] <- measured$mean_seconds[[i]]
  }
  out
}

#' Plan a private release from a release's pull: a hindcast at a cutoff, or
#' the records under their own names. dry_run = TRUE reads the store and
#' says what it would fit and cost, and writes nothing.
atlas_plan_private_release <- function(store = atlas_store(), from_release, purpose = ATLAS_PRIVATE_PURPOSES,
                                       validated_through = NULL, grid = "draft", algorithms = "all",
                                       shards = 4L, tasks_per_shard = NULL, quiet = FALSE, dry_run = FALSE,
                                       fits_at_once = 128) {
  purpose <- match.arg(purpose)
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (identical(purpose, "hindcast")) {
    if (!is.character(validated_through) || length(validated_through) != 1L ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", validated_through) ||
        is.na(as.Date(validated_through, format = "%Y-%m-%d"))) {
      stop("a hindcast needs --validated-through=YYYY-MM-DD", call. = FALSE)
    }
  } else if (!is.null(validated_through)) {
    stop("only a hindcast takes a cutoff", call. = FALSE)
  }
  key <- paste0("releases/", grid, "/", from_release, ".json")
  if (!store$exists(key)) stop("no release ", from_release, " for the ", grid, " grid", call. = FALSE)
  base <- atlas_store_text(store, key)
  main_job_id <- atlas_json_string(base$job)
  if (is.null(main_job_id)) {
    stop("release ", from_release, " was not made by a job, so its pull is not in the store", call. = FALSE)
  }
  main_job <- atlas_read_job(store, main_job_id, grid)
  pull_entry <- atlas_job_pull_entry(main_job)
  if (is.null(pull_entry)) stop("job ", main_job_id, " carries no pull", call. = FALSE)
  pull_file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(pull_file), add = TRUE)
  store$get(atlas_object_key(pull_entry$sha256), pull_file)
  pulled <- atlas_read_occurrences(pull_file)

  variant <- if (identical(purpose, "hindcast")) {
    filtered <- atlas_filter_validated_through(pulled, validated_through, undated = "exclude")
    if (filtered$counts$records_after_cutoff_kept != 0L) {
      stop("records validated after the cutoff survived the filter; nothing planned", call. = FALSE)
    }
    filtered
  } else {
    atlas_record_named(pulled)
  }
  occurrences <- variant$occurrences

  algorithms <- if (length(algorithms) == 1L) atlas_parse_algorithms(algorithms) else algorithms
  min_presences <- main_job$fit$min_presences %||% 20
  points <- atlas_occurrence_points(occurrences, grid)
  areas <- vapply(base$index %||% list(), function(e) {
    if (is.numeric(e$area_km2) && length(e$area_km2) == 1L) e$area_km2 else NA_real_
  }, numeric(1))
  typical <- if (any(is.finite(areas))) stats::median(areas, na.rm = TRUE) else 5e6
  area_of <- list()
  fitted_on <- list()
  for (e in base$index %||% list()) {
    area_of[[paste(e$algorithm, e$taxon)]] <- e$area_km2
    if (!isTRUE(e$refused)) fitted_on[[paste(e$algorithm, e$taxon)]] <- e$fingerprint
  }
  unchanged <- 0L
  tasks <- list()
  for (algorithm in algorithms) {
    algo <- atlas_algorithm(algorithm)
    minimum <- atlas_algorithm_min(algo, min_presences)
    candidates <- atlas_batch_candidates(points, minimum,
                                         max_presences = atlas_algorithm_max(algo) + ATLAS_RANGE_MARGIN)$scientific_name
    fingerprints <- atlas_fingerprints_for(occurrences, candidates)
    for (name in candidates) {
      if (identical(purpose, "record-names") &&
          identical(as.character(fitted_on[[paste(algorithm, name)]] %||% ""), as.character(fingerprints[[name]]))) {
        unchanged <- unchanged + 1L
        next
      }
      tasks[[length(tasks) + 1L]] <- list(
        taxon = name, algorithm = algorithm, fingerprint = fingerprints[[name]],
        cost = atlas_task_cost(algorithm, area_of[[paste(algorithm, name)]], typical)
      )
    }
  }
  if (identical(purpose, "record-names")) variant$counts$models_unchanged <- unchanged
  if (!length(tasks)) stop("nothing to fit: no taxon has enough records in the ", purpose, " pull",
                           if (unchanged) paste0(", or each is unchanged (", unchanged, ")"), call. = FALSE)
  seconds <- atlas_private_seconds(store, main_job_id, grid)
  models <- table(vapply(tasks, function(t) t$algorithm, ""))
  cpu_hours <- sum(vapply(tasks, function(t) seconds[[t$algorithm]] %||% 600, numeric(1))) / 3600
  estimate <- list(
    models = length(tasks), taxa = length(unique(vapply(tasks, function(t) t$taxon, ""))),
    per_algorithm = as.list(models), cpu_hours = round(cpu_hours, 1),
    wall_hours = round(cpu_hours / fits_at_once, 1),
    basis = paste("mean seconds per model of job", main_job_id, "where timed, else ATLAS_PRIVATE_SECONDS;",
                  "wall at", fits_at_once, "fits at once; an estimate")
  )
  if (isTRUE(dry_run)) {
    say(purpose, " from ", from_release, if (!is.null(validated_through)) paste0(" validated through ", validated_through),
        " (dry run, nothing written): ", variant$counts$records_kept, " of ", variant$counts$records_in_pull,
        " records kept", if (!is.null(variant$counts$records_undated_left_out))
          paste0(" (", variant$counts$records_undated_left_out, " with no first green date left out)"),
        "; ", estimate$models, " models of ", estimate$taxa, " taxa (",
        paste(names(models), models, collapse = ", "), "); about ", estimate$cpu_hours, " CPU-h, ",
        estimate$wall_hours, " h on EC2")
    return(invisible(list(from_release = from_release, purpose = purpose, filter = variant$counts,
                          estimate = estimate, tasks = tasks)))
  }

  costs <- vapply(tasks, function(t) t$cost, numeric(1))
  if (!is.null(tasks_per_shard)) shards <- atlas_shard_count(length(tasks), shards, tasks_per_shard)
  assignment <- atlas_assign_shards(costs, shards, groups = vapply(tasks, function(t) t$taxon, ""))
  for (i in seq_along(tasks)) tasks[[i]]$shard <- assignment[[i]]
  id <- paste0("priv-", atlas_release_id(digest::digest(list(tasks, from_release, purpose, validated_through),
                                                        algo = "sha256")))
  # The variant pull goes to the workers as the job's pull, written in a
  # scratch directory, never over this machine's own.
  pull_entries <- atlas_in_scratch_data_dir({
    file <- paste0("occurrences-", id, ".tsv.gz")
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(
      stamp = id, pulled_at = base$pull$pulled_at %||% NA_character_, since = NA_character_,
      records = nrow(occurrences), fingerprint = atlas_fingerprint(occurrences), file = file,
      made_from = list(release = from_release, job = main_job_id, pull = pull_entry$sha256,
                       purpose = purpose, validated_through = validated_through)
    ), atlas_path("occurrences", "latest.json"))
    entries <- atlas_file_entries(c(file.path("occurrences", file), "occurrences/latest.json"))
    atlas_upload_objects(store, entries)
    entries
  })
  others <- Filter(function(e) !startsWith(e$path, "occurrences/"), main_job$inputs %||% list())
  trained_ids <- atlas_save_trained_pull(store, grid, occurrences)
  job <- list(
    id = id, grid = grid, kind = "private-release", purpose = purpose,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    from_release = from_release, from_job = main_job_id, validated_through = validated_through,
    # The pull the release was fitted on, which this job's is made from: the
    # paper shows the two read the same records.
    from_pull = list(path = pull_entry$path, sha256 = pull_entry$sha256),
    algorithms = as.list(algorithms), shards = max(assignment),
    # The release's own settings, null tests and tuning included: the
    # grades are this job's.
    fit = main_job$fit,
    layers_key = main_job$layers_key,
    pull = base$pull,
    inputs = c(pull_entries, others),
    public = list(), tasks = tasks, retire = list(), deferred = 0L,
    trained_ids = trained_ids,
    filter = variant$counts,
    estimate = estimate,
    declared = if (identical(purpose, "hindcast")) {
      paste("Fitted and graded afresh on the records of", from_release, "'s pull first validated on or before",
            validated_through, "; records with no first green date left out.")
    } else {
      paste("Fitted and graded afresh on the records of", from_release, "'s pull under their own .org names.")
    }
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
  say(purpose, " job ", id, " from ", from_release, ": ", variant$counts$records_kept, " of ",
      variant$counts$records_in_pull, " records; ", length(tasks), " models in ", job$shards, " shard",
      if (job$shards == 1L) "" else "s", "; about ", estimate$cpu_hours, " CPU-h")
  invisible(job)
}

#' A finished private release's models table (models.tsv.gz), or NULL.
atlas_private_models <- function(store, id) {
  key <- atlas_benchmark_key(id, "models.tsv.gz")
  if (!store$exists(key)) return(NULL)
  file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(file), add = TRUE)
  store$get(key, file)
  utils::read.delim(gzfile(file), stringsAsFactors = FALSE)
}

#' A models table's rows as lists, leaving out what is missing.
atlas_model_rows <- function(models) {
  if (is.null(models) || !nrow(models)) return(list())
  lapply(seq_len(nrow(models)), function(i) {
    row <- lapply(as.list(models[i, , drop = FALSE]), function(v) if (length(v) == 1L && is.na(v)) NULL else v)
    Filter(Negate(is.null), row)
  })
}

#' Plan a hindcast refit: some of a finished hindcast's models fitted again
#' without listed records, as the paper's pre-registered rule asks when a
#' training record turns out to have been validated after the cutoff.
#'
#' The refit is the hindcast in everything but those records. Its pull is
#' the hindcast's own (already cut at its date), read from the store, with
#' the listed rows dropped in memory: each named by .org's id, or by its
#' source and the source's own number ("Mushroom Observer:123456"), never
#' by that number alone (the sources' numbers overlap). It fits exactly the
#' hindcast's models of the named taxa (or of those algorithms, when given),
#' with the hindcast job's settings, null tests, tuning and layers, and each
#' model draws with its hindcast model's seed (seed_from), so its folds,
#' background and null draws differ only where the records do. Survey sites,
#' effort and background are built on the worker from the whole refit pull,
#' as the hindcast's were from its own: the same sites, except that a
#' left-out record no longer counts at its site, and a site it held alone is
#' gone. Neither the pull it is made from, nor the box's pull, nor the drop
#' list (R/exclude.R) is written: the refit's pull reaches its workers as
#' the job's own private input, as any hindcast's does.
#'
#' Finished (atlas_finish_hindcast_refit_work), it is a private release of
#' its own under private/vision-benchmark/<id>/, never promotable: the
#' hindcast's, file for file, with only the refitted models' files and index
#' entries replaced. The hindcast itself is untouched.
#'
#' leave_out may be empty: the refit then reproduces the hindcast's models,
#' which is how the tests show nothing else changes. Refuses, writing
#' nothing: a hindcast not finished; a left-out record not in its pull, or
#' not a named taxon's; a taxon or algorithm with no model there; a taxon
#' with a combined map (a swap would leave it stale); a model whose taxon
#' falls outside the algorithm's range of sites without the records; and a
#' cutoff other than the hindcast's.
atlas_plan_hindcast_refit <- function(store = atlas_store(), hindcast, taxa, leave_out = character(),
                                      algorithms = NULL, reason = NULL, rule = NULL, validated_through = NULL,
                                      grid = "draft", shards = 1L, quiet = FALSE, dry_run = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  taxa <- unique(trimws(as.character(taxa)))
  taxa <- taxa[nzchar(taxa)]
  if (!length(taxa)) stop("a hindcast refit needs --taxa=NAME[,NAME...]", call. = FALSE)
  leave_out <- unique(trimws(as.character(leave_out)))
  leave_out <- leave_out[nzchar(leave_out)]

  # Planned only from a finished hindcast: its summary is written last.
  manifest_key <- atlas_benchmark_key(hindcast, "release.json")
  if (!store$exists(manifest_key) || !store$exists(atlas_benchmark_key(hindcast, "summary.json"))) {
    stop("no finished private release ", hindcast, ": a refit is planned from a finished hindcast, ",
         "named by --from-release=priv-...", call. = FALSE)
  }
  manifest <- atlas_store_text(store, manifest_key)
  if (!identical(manifest$purpose, "hindcast") || !is.null(manifest$refit)) {
    stop(hindcast, " is not a hindcast: only a hindcast's models are refitted this way", call. = FALSE)
  }
  hjob <- atlas_read_job(store, atlas_json_string(manifest$job) %||% hindcast, grid)
  if (!atlas_is_private_release(hjob) || !identical(hjob$purpose, "hindcast")) {
    stop("job ", hjob$id, " is not a hindcast", call. = FALSE)
  }
  cutoff <- atlas_json_string(hjob$validated_through)
  if (!is.null(validated_through) && !identical(as.character(validated_through), cutoff)) {
    stop("--validated-through=", validated_through, " is not the hindcast's cutoff (", cutoff, ")", call. = FALSE)
  }

  # The models refitted: the hindcast's own, of the named taxa.
  index <- Filter(function(e) !isTRUE(e$refused), manifest$index %||% list())
  modelled <- function(name) unique(vapply(Filter(function(e) identical(e$taxon, name), index),
                                           function(e) as.character(e$algorithm), ""))
  missing_taxa <- Filter(function(name) !length(modelled(name)), taxa)
  if (length(missing_taxa)) {
    stop("no model of ", paste(missing_taxa, collapse = ", "), " in hindcast ", hindcast, call. = FALSE)
  }
  models <- list()
  for (name in taxa) {
    have <- modelled(name)
    wanted <- if (is.null(algorithms)) have else as.character(algorithms)
    absent <- setdiff(wanted, have)
    if (length(absent)) {
      stop("no ", paste(absent, collapse = ", "), " model of ", name, " in hindcast ", hindcast, call. = FALSE)
    }
    for (algorithm in wanted) models[[length(models) + 1L]] <- list(taxon = name, algorithm = algorithm)
  }
  combined <- Filter(function(name) {
    any(startsWith(vapply(manifest$files %||% list(), function(f) f$path, ""), atlas_refit_ensemble_prefix(name, grid)))
  }, taxa)
  if (length(combined)) {
    stop(paste(combined, collapse = ", "), " has a combined map in hindcast ", hindcast,
         ", which swapping one model would leave stale; not refitted", call. = FALSE)
  }

  pull_entry <- atlas_job_pull_entry(hjob)
  if (is.null(pull_entry)) stop("hindcast job ", hjob$id, " carries no pull", call. = FALSE)
  pull_file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(pull_file), add = TRUE)
  store$get(atlas_object_key(pull_entry$sha256), pull_file)
  pulled <- atlas_read_occurrences(pull_file)
  if (!all(c("id", "source", "observation_id") %in% names(pulled))) {
    stop("the hindcast's pull has no id, source or observation_id column", call. = FALSE)
  }
  ids <- as.character(pulled$id)
  keys <- atlas_record_key(pulled$source, pulled$observation_id)
  dropped <- rep(FALSE, nrow(pulled))
  for (k in leave_out) {
    hit <- if (grepl(":", k, fixed = TRUE)) keys == k else ids == k
    if (!any(hit)) {
      stop("not in hindcast ", hindcast, "'s pull: ", k,
           " (--leave-out takes .org record ids, or source:observation_id)", call. = FALSE)
    }
    if (sum(hit) > 1L) stop(k, " names ", sum(hit), " records in the pull; name each by its .org id", call. = FALSE)
    dropped <- dropped | hit
  }
  others <- unique(pulled$scientific_name[dropped & !pulled$scientific_name %in% taxa])
  if (length(others)) {
    stop("a left-out record is ", paste(others, collapse = ", "), "'s, not a named taxon's: ",
         "leaving it out would change that taxon's sites without refitting it", call. = FALSE)
  }
  # The hindcast's pull is already cut at its date: nothing outside it.
  check <- atlas_filter_validated_through(pulled, cutoff, undated = "exclude")
  if (check$counts$records_removed != 0L) {
    stop("hindcast ", hindcast, "'s pull holds records outside its cutoff; nothing planned", call. = FALSE)
  }
  # Each model draws with its hindcast model's seed, the fingerprint of the
  # record set it was fitted on, which the pull read back must still give.
  seed_of <- list()
  for (t in hjob$tasks) if (t$taxon %in% taxa) seed_of[[t$taxon]] <- t$fingerprint
  again <- atlas_fingerprints_for(pulled, taxa)
  for (name in taxa) {
    if (!identical(as.character(seed_of[[name]] %||% ""), unname(again[[name]]))) {
      stop("hindcast ", hindcast, "'s pull no longer gives ", name, "'s record set; nothing planned", call. = FALSE)
    }
  }

  occurrences <- pulled[!dropped, , drop = FALSE]
  rownames(occurrences) <- NULL
  records <- lapply(which(dropped), function(i) {
    list(id = ids[[i]], source = as.character(pulled$source[[i]]),
         observation_id = as.character(pulled$observation_id[[i]]), taxon = pulled$scientific_name[[i]])
  })
  left_out_by_taxon <- lapply(stats::setNames(nm = taxa), function(name) {
    as.list(sort(ids[dropped & pulled$scientific_name == name]))
  })

  # Each model is refitted only if its taxon is still in the algorithm's
  # range of sites without the records, as the hindcast's planning asked.
  min_presences <- hjob$fit$min_presences %||% 20
  sites <- atlas_presence_cell_counts(atlas_occurrence_points(occurrences, grid))
  areas <- vapply(index, function(e) {
    if (is.numeric(e$area_km2) && length(e$area_km2) == 1L) e$area_km2 else NA_real_
  }, numeric(1))
  typical <- if (any(is.finite(areas))) stats::median(areas, na.rm = TRUE) else 5e6
  area_of <- list()
  for (e in index) area_of[[paste(e$algorithm, e$taxon)]] <- e$area_km2
  fingerprints <- atlas_fingerprints_for(occurrences, taxa)
  tasks <- lapply(models, function(m) {
    algo <- atlas_algorithm(m$algorithm)
    low <- atlas_algorithm_min(algo, min_presences)
    high <- atlas_algorithm_max(algo) + ATLAS_RANGE_MARGIN
    n <- sites$cells[match(m$taxon, sites$scientific_name)]
    n <- if (is.na(n)) 0L else n
    if (n < low || n > high) {
      stop("without the left-out records ", m$taxon, " has ", n, " sites, outside ", m$algorithm, "'s ", low, " to ",
           high, "; not refitted", call. = FALSE)
    }
    list(taxon = m$taxon, algorithm = m$algorithm, fingerprint = fingerprints[[m$taxon]],
         seed_from = seed_of[[m$taxon]], cost = atlas_task_cost(m$algorithm, area_of[[paste(m$algorithm, m$taxon)]],
                                                               typical))
  })

  # The hindcast's models of these taxa, as its models table lists them
  # (as its index does, where it has no table).
  refitted <- vapply(tasks, function(t) paste(t$algorithm, t$taxon), "")
  original <- atlas_private_models(store, hindcast)
  original <- if (!is.null(original)) {
    atlas_model_rows(original[paste(original$algorithm, original$taxon) %in% refitted, , drop = FALSE])
  } else {
    lapply(Filter(function(e) paste(e$algorithm, e$taxon) %in% refitted, index),
           function(e) e[intersect(names(e), c("taxon", "algorithm", "grade", "presences"))])
  }
  filter <- list(records_in_pull = nrow(pulled), records_left_out = sum(dropped), records_kept = nrow(occurrences),
                 records_after_cutoff_kept = 0L)
  seconds <- atlas_private_seconds(store, hjob$id, grid)
  per_algorithm <- table(vapply(tasks, function(t) t$algorithm, ""))
  cpu_hours <- sum(vapply(tasks, function(t) seconds[[t$algorithm]] %||% 600, numeric(1))) / 3600
  estimate <- list(
    models = length(tasks), taxa = length(taxa), per_algorithm = as.list(per_algorithm),
    cpu_hours = round(cpu_hours, 2),
    basis = paste("mean seconds per model of job", hjob$id, "where timed, else ATLAS_PRIVATE_SECONDS; an estimate")
  )
  plural <- function(n, word) paste0(n, " ", word, if (n == 1L) "" else "s")
  if (isTRUE(dry_run)) {
    say("hindcast refit of ", paste(refitted, collapse = ", "), " from ", hindcast, " (dry run, nothing written): ",
        plural(sum(dropped), "record"), " left out of ", nrow(pulled), "; about ", estimate$cpu_hours, " CPU-h")
    return(invisible(list(hindcast = hindcast, filter = filter, estimate = estimate, tasks = tasks,
                          left_out = records)))
  }
  if (!is.character(reason) || length(reason) != 1L || !nzchar(trimws(reason))) {
    stop("a hindcast refit needs --reason=\"why these records are left out\"", call. = FALSE)
  }

  costs <- vapply(tasks, function(t) t$cost, numeric(1))
  assignment <- atlas_assign_shards(costs, max(1L, min(as.integer(shards), length(tasks))),
                                    groups = vapply(tasks, function(t) t$taxon, ""))
  for (i in seq_along(tasks)) tasks[[i]]$shard <- assignment[[i]]
  id <- paste0("priv-", atlas_release_id(digest::digest(list(tasks, hindcast, "refit", sort(ids[dropped])),
                                                        algo = "sha256")))
  # The refit's pull, written in a scratch directory, never this machine's.
  refit_pull <- atlas_in_scratch_data_dir({
    file <- paste0("occurrences-", id, ".tsv.gz")
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    # Read back as the workers will: the hindcast's records but the left-out ones.
    back <- atlas_read_occurrences(atlas_path("occurrences", file))
    if (nrow(back) != nrow(occurrences) || !identical(atlas_fingerprint(back), atlas_fingerprint(occurrences))) {
      stop("the refit's pull does not read back as it was written; nothing planned", call. = FALSE)
    }
    atlas_write_json(list(
      stamp = id, pulled_at = hjob$pull$pulled_at %||% NA_character_, since = NA_character_,
      records = nrow(occurrences), fingerprint = atlas_fingerprint(occurrences), file = file,
      made_from = list(release = hjob$from_release, job = hjob$id, hindcast = hindcast, pull = pull_entry$sha256,
                       purpose = "hindcast", validated_through = cutoff, records_left_out = sum(dropped))
    ), atlas_path("occurrences", "latest.json"))
    entries <- atlas_file_entries(c(file.path("occurrences", file), "occurrences/latest.json"))
    atlas_upload_objects(store, entries)
    entries
  })
  inputs <- Filter(function(e) !startsWith(e$path, "occurrences/"), hjob$inputs %||% list())
  trained_ids <- atlas_save_trained_pull(store, grid, occurrences)
  job <- list(
    id = id, grid = grid, kind = "private-release", purpose = "hindcast",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    from_release = hjob$from_release, from_job = hjob$from_job, validated_through = cutoff,
    # The pull this one is made from: the hindcast's.
    from_pull = list(path = pull_entry$path, sha256 = pull_entry$sha256),
    algorithms = as.list(unique(vapply(tasks, function(t) t$algorithm, ""))), shards = max(assignment),
    # The hindcast's settings, null tests and tuning: only the records differ.
    fit = hjob$fit,
    layers_key = hjob$layers_key,
    pull = hjob$pull,
    inputs = c(refit_pull, inputs),
    public = list(), tasks = tasks, retire = list(), deferred = 0L,
    trained_ids = trained_ids,
    filter = filter,
    estimate = estimate,
    refit = Filter(Negate(is.null), list(
      hindcast = hindcast, hindcast_job = hjob$id, reason = trimws(reason),
      rule = if (is.character(rule) && nzchar(trimws(rule))) trimws(rule),
      taxa = as.list(taxa), left_out = records, left_out_by_taxon = left_out_by_taxon,
      seeds = "each model draws with its hindcast model's seed (seed_from)",
      original = original
    )),
    declared = paste0("The models ", paste(refitted, collapse = ", "), " of hindcast ", hindcast, " fitted again without ",
                      plural(sum(dropped), "training record"), " (", trimws(reason), "), left out in memory; ",
                      "otherwise the hindcast's pull, cutoff (", cutoff, "), settings, null tests, tuning and seeds. ",
                      "Every other file is the hindcast's.")
  )
  atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
  say("hindcast refit ", id, " of ", paste(refitted, collapse = ", "), " from ", hindcast, ": ",
      plural(sum(dropped), "record"), " left out; ", plural(length(tasks), "model"), " in ",
      plural(job$shards, "shard"))
  invisible(job)
}

#' Where a taxon's combined map's files begin.
atlas_refit_ensemble_prefix <- function(name, grid = "draft") {
  paste0("models/", grid, "/ensemble/", basename(atlas_model_path(name, grid, extension = "")), ".")
}

#' Whether a release file is one of a refitted model's: its taxon's files
#' in its algorithm's model folder.
atlas_refit_owns <- function(path, tasks, grid = "draft") {
  prefixes <- vapply(tasks, function(t) {
    json <- atlas_model_relpaths(t$taxon, grid, t$algorithm, ".json")
    sub("json$", "", json)
  }, "")
  any(startsWith(path, prefixes))
}

#' A refit's models beside the hindcast's they stand for: taxon, algorithm,
#' both fingerprints, the records left out, and both fits' grades and
#' scores (either left out where that fit has no model).
atlas_refit_record <- function(refit, models, tasks = list()) {
  key <- function(r) paste(r$algorithm, r$taxon)
  before <- refit$original %||% list()
  before <- stats::setNames(before, vapply(before, key, ""))
  after <- atlas_model_rows(models)
  after <- stats::setNames(after, vapply(after, key, ""))
  task_of <- stats::setNames(tasks, vapply(tasks, key, ""))
  entries <- lapply(sort(unique(c(names(before), names(after)))), function(k) {
    first <- before[[k]] %||% after[[k]]
    Filter(Negate(is.null), list(
      taxon = first$taxon, algorithm = first$algorithm,
      hindcast_fingerprint = task_of[[k]]$seed_from, refit_fingerprint = task_of[[k]]$fingerprint,
      left_out = refit$left_out_by_taxon[[first$taxon]] %||% list(),
      hindcast = before[[k]], refit = after[[k]]
    ))
  })
  c(refit[intersect(names(refit), c("hindcast", "hindcast_job", "reason", "rule", "taxa", "left_out", "seeds"))],
    list(models = entries))
}

#' On a worker: finish a hindcast refit from its shards, never in part. Its
#' release is the hindcast's (private/vision-benchmark/<hindcast>/
#' release.json) with each refitted model's files, counted by state as the
#' hindcast's were, and index entry (marked refit_of) in place of the
#' hindcast's; every other file entry is the hindcast's, byte for byte, the
#' here index, prior and weak ranks among them, which were built with the
#' hindcast's models. Its models table is the hindcast's with the refitted
#' rows swapped (refit = TRUE), and the refit's record, in its summary and
#' manifest, sets each refitted model beside the hindcast's.
atlas_finish_hindcast_refit_work <- function(store, job, records, results, files, index, grid = "draft",
                                             count = atlas_count_regions, quiet = FALSE) {
  id <- job$id
  hindcast <- job$refit$hindcast
  key <- function(x) paste(x$algorithm, x$taxon)
  refitted <- vapply(job$tasks, key, "")
  fitted <- Filter(function(r) identical(r$status, "fitted"), results)
  missing <- setdiff(refitted, vapply(fitted, key, ""))
  if (length(missing)) {
    stop("hindcast refit ", id, " is not finished: ", paste(missing, collapse = ", "),
         " not fitted; the hindcast's models stand and nothing is built", call. = FALSE)
  }
  source <- atlas_store_text(store, atlas_benchmark_key(hindcast, "release.json"))
  built <- atlas_in_scratch_data_dir({
    atlas_fetch_entries(store, Filter(function(e) startsWith(e$path, "occurrences/"), job$inputs))
    atlas_fetch_entries(store, files)
    atlas_refresh_public_files()
    counted <- count(grid = grid, only_missing = TRUE, quiet = quiet)
    models <- atlas_private_models_table(grid)
    paths <- atlas_release_files(grid)
    entries <- atlas_file_entries(paths[vapply(paths, atlas_refit_owns, logical(1), tasks = job$tasks, grid = grid)])
    atlas_upload_objects(store, entries)
    list(counted = counted, models = models, entries = entries)
  })
  kept <- Filter(function(f) !atlas_refit_owns(f$path, job$tasks, grid), source$files %||% list())
  release_files <- c(kept, built$entries)
  release_files <- release_files[order(vapply(release_files, function(f) f$path, ""))]
  new_entry <- stats::setNames(index, vapply(index, key, ""))
  swapped <- lapply(source$index %||% list(), function(e) {
    if (!key(e) %in% refitted) return(e)
    c(new_entry[[key(e)]], list(refit_of = hindcast))
  })

  hindcast_models <- atlas_private_models(store, hindcast)
  models <- if (is.null(hindcast_models)) built$models else {
    hindcast_models$refit <- rep(FALSE, nrow(hindcast_models))
    refit_models <- built$models
    refit_models$refit <- rep(TRUE, nrow(refit_models))
    for (column in setdiff(names(hindcast_models), names(refit_models))) refit_models[[column]] <- NA
    for (column in setdiff(names(refit_models), names(hindcast_models))) hindcast_models[[column]] <- NA
    out <- rbind(hindcast_models[!paste(hindcast_models$algorithm, hindcast_models$taxon) %in% refitted, , drop = FALSE],
                 refit_models[, names(hindcast_models), drop = FALSE])
    out[order(out$taxon, out$algorithm), , drop = FALSE]
  }
  record <- atlas_refit_record(job$refit, built$models, job$tasks)
  uploaded <- character()
  upload <- function(path, ...) {
    k <- atlas_benchmark_key(id, ...)
    store$put(k, path)
    uploaded <<- c(uploaded, k)
  }
  models_file <- tempfile(fileext = ".tsv.gz")
  atlas_write_tsv_gz(models, models_file)
  upload(models_file, "models.tsv.gz")
  manifest_file <- tempfile(fileext = ".json")
  atlas_write_json(list(
    id = id, grid = grid, kind = "private-release", purpose = job$purpose, job = id,
    from_release = job$from_release, validated_through = job$validated_through,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    pull = job$pull, layers_key = job$layers_key, refit = record,
    carried = paste0("Every file but the refitted models' is hindcast ", hindcast, "'s, byte for byte: its here ",
                     "index, prior and weak ranks were built with its own models, the refitted ones' hindcast fits ",
                     "among them."),
    index = swapped, files = release_files
  ), manifest_file)
  upload(manifest_file, "release.json")
  trained <- atlas_write_trained_ids(store, list(id = id, index = Filter(function(e) !isTRUE(e$refused), swapped)),
                                     grid, prefer = atlas_json_string(job$trained_ids), quiet = TRUE)
  summary <- Filter(Negate(is.null), list(
    job = id, grid = grid, kind = "private-release", purpose = job$purpose,
    from_release = job$from_release, validated_through = job$validated_through,
    from_pull = job$from_pull,
    pull = list(sha256 = (atlas_job_pull_entry(job) %||% list())$sha256),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    filter = job$filter,
    models_planned = length(job$tasks), models_fitted = length(fitted),
    counted = as.integer(built$counted %||% 0L),
    files = as.list(uploaded),
    trained_ids = list(key = atlas_trained_release_key(id, grid), records = trained$records),
    cpu_hours = round(sum(vapply(results, function(r) as.numeric(r$seconds %||% 0), 0), na.rm = TRUE) / 3600, 2),
    billing = atlas_job_billing(records, c(id, atlas_finish_id(id))),
    refit = record,
    declared = job$declared
  ))
  atlas_store_json(store, atlas_benchmark_key(id, "summary.json"), summary)
  summary
}

#' What a job's workers were billed for, from its shard records: hours per
#' instance type (each shard from its start to its record, so a worker's boot
#' and image pull, and any worker lost before reporting, are not counted),
#' and US dollars where a price per instance-hour is known
#' (ATLAS_EC2_SPOT_PRICES, e.g. "r7a.8xlarge=0.80,r7i.8xlarge=0.85"). The
#' workers are tagged atlas-job, so Cost Explorer can confirm the bill.
atlas_job_billing <- function(records, job_ids, prices = Sys.getenv("ATLAS_EC2_SPOT_PRICES", unset = "")) {
  price_of <- list()
  for (pair in strsplit(prices, ",", fixed = TRUE)[[1]]) {
    parts <- strsplit(trimws(pair), "=", fixed = TRUE)[[1]]
    if (length(parts) == 2L && is.finite(suppressWarnings(as.numeric(parts[[2]])))) {
      price_of[[parts[[1]]]] <- as.numeric(parts[[2]])
    }
  }
  hours <- list()
  for (r in records) {
    if (is.null(r$started_at) || is.null(r$finished_at)) next
    type <- r$machine$instance_type %||% "unknown"
    h <- as.numeric(difftime(as.POSIXct(r$finished_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                             as.POSIXct(r$started_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours"))
    if (is.finite(h)) hours[[type]] <- (hours[[type]] %||% 0) + h
  }
  priced <- length(hours) && all(names(hours) %in% names(price_of))
  usd <- if (priced) sum(vapply(names(hours), function(t) hours[[t]] * price_of[[t]], numeric(1))) else NA_real_
  list(
    instance_hours = lapply(hours, round, 2),
    usd = if (priced) round(usd, 2) else NULL,
    priced = priced,
    note = paste0(if (priced) "priced from ATLAS_EC2_SPOT_PRICES" else
                    "no price per instance-hour for every type (ATLAS_EC2_SPOT_PRICES)",
                  "; boot, image pull and lost workers not counted; Cost Explorer by tag atlas-job = ",
                  paste(job_ids, collapse = ", "))
  )
}

#' Every model's grade, strength and scores, from this data directory's
#' metrics: what Atlas E2 scores by grade. A fit's metrics keep the pooled
#' Boyce index, the one its grade is judged by, as "boyce" ("boyce_mean" is
#' the mean over folds; R/fit.R): the table's boyce_pooled is that.
atlas_private_models_table <- function(grid = "draft") {
  rows <- lapply(names(ATLAS_ALGORITHMS), function(algorithm) {
    files <- list.files(atlas_model_dir(grid, algorithm), pattern = "[.]json$", full.names = TRUE)
    lapply(files, function(path) {
      m <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(m$taxon)) return(NULL)
      number <- function(x) if (is.numeric(x) && length(x) == 1L) x else NA_real_
      data.frame(taxon = m$taxon, algorithm = algorithm, grade = atlas_metrics_grade(m),
                 presences = number(m$presences), map_strength = number(m$map_strength),
                 auc_mean = number(m$auc_mean), boyce_pooled = number(m$boyce),
                 null_reps = number(m$null$reps), null_auc_p = number(m$null$auc_p),
                 threshold = number(m$applicability$threshold),
                 full_view = !is.null(m$full_map), stringsAsFactors = FALSE)
    })
  })
  out <- do.call(rbind, unlist(rows, recursive = FALSE))
  if (is.null(out)) out <- data.frame(taxon = character(), algorithm = character(), grade = character())
  out[order(out$taxon, out$algorithm), , drop = FALSE]
}

#' On a worker (or any machine): finish a private release from its shards,
#' as a release's finishing does, in a scratch data directory, filing every
#' product privately. Never in part: every shard must have reported.
atlas_finish_private_release_work <- function(store = atlas_store(), id, grid = "draft", quiet = FALSE,
                                              count = atlas_count_regions, ensembles = atlas_build_ensembles,
                                              build = atlas_build_finish_indexes, defer = FALSE,
                                              usd_per_vcpu_hour = 0.025, vcpus_per_worker = 32) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (isTRUE(defer)) store <- atlas_deferring_store(store)
  job <- atlas_read_job(store, id, grid)
  if (!atlas_is_private_release(job)) stop("job ", id, " is not a private release", call. = FALSE)
  status <- atlas_job_status(store, id, grid)
  if (length(status$missing)) {
    stop("job ", id, " is not finished: shard", if (length(status$missing) > 1L) "s " else " ",
         paste(status$missing, collapse = ", "), " not reported; a private release is never finished in part",
         call. = FALSE)
  }
  if (identical(job$purpose, "hindcast") && !identical(as.integer(job$filter$records_after_cutoff_kept), 0L)) {
    stop("job ", id, " kept records validated after its cutoff; nothing built", call. = FALSE)
  }
  records <- lapply(seq_len(job$shards), function(n) atlas_store_text(store, atlas_shard_key(id, n, grid)))
  results <- unlist(lapply(records, function(r) r$results), recursive = FALSE)
  files <- unlist(lapply(records, function(r) r$files), recursive = FALSE)
  index <- unlist(lapply(records, function(r) r$index), recursive = FALSE)
  for (r in Filter(function(r) identical(r$status, "refused"), results)) {
    index[[length(index) + 1L]] <- atlas_refusal_entry(r$taxon, r$algorithm, r$fingerprint, r$settings_key, r$presences)
  }
  # A hindcast refit is the hindcast with its refitted models swapped in.
  if (!is.null(job$refit)) {
    summary <- atlas_finish_hindcast_refit_work(store, job, records, results, files, index, grid,
                                                count = count, quiet = quiet)
    atlas_finish_private_record(store, id, grid, summary, defer)
    say("hindcast refit ", id, ": ", summary$models_fitted, " of ", length(job$tasks), " models swapped into ",
        job$refit$hindcast, "'s files; summary at ", atlas_benchmark_key(id, "summary.json"))
    return(invisible(summary))
  }

  key <- function(...) atlas_benchmark_key(id, ...)
  uploaded <- character()
  upload <- function(path, ...) {
    if (!file.exists(path)) return(invisible(NULL))
    k <- key(...)
    store$put(k, path)
    uploaded <<- c(uploaded, k)
  }
  built <- atlas_in_scratch_data_dir({
    # The job's own pull, for the collection cells counting reads; the
    # layers are not needed, only the maps.
    atlas_fetch_entries(store, Filter(function(e) startsWith(e$path, "occurrences/"), job$inputs))
    atlas_fetch_entries(store, files)
    atlas_refresh_public_files()
    counted <- count(grid = grid, only_missing = TRUE, quiet = quiet)
    ensembles(grid = grid, quiet = quiet)
    build(grid = grid, quiet = quiet)
    models <- atlas_private_models_table(grid)
    models_file <- tempfile(fileext = ".tsv.gz")
    atlas_write_tsv_gz(models, models_file)
    upload(models_file, "models.tsv.gz")
    for (f in ATLAS_PRIOR_FILES) upload(file.path(atlas_prior_dir(grid), f), "prior", grid, f)
    for (f in ATLAS_CONTINENT_FILES) upload(file.path(atlas_continent_dir(grid), f), "continent", grid, f)
    upload(atlas_here_index_path(grid), "here", grid, basename(atlas_here_index_path(grid)))
    upload(atlas_weak_ranks_path(grid), "weak", grid, basename(atlas_weak_ranks_path(grid)))
    # Its files as a release would list them, kept privately: the fitted
    # maps (metrics counted by state now) and the combined maps.
    paths <- atlas_release_files(grid)
    paths <- paths[!startsWith(paths, "public/") & !startsWith(paths, "occurrences/")]
    entries <- atlas_file_entries(paths)
    atlas_upload_objects(store, entries)
    # The renames the release it was made from carries (how names moved
    # between pulls), so a reader matches a later find under an old name to
    # its model as the tracker does for a release. Already in the store.
    base <- tryCatch(atlas_store_text(store, paste0("releases/", grid, "/", job$from_release, ".json")),
                     error = function(e) NULL)
    renames <- Filter(function(f) identical(f$path, "occurrences/renames.json"), base$files %||% list())
    entries <- c(entries, renames)
    list(counted = counted, models = models, entries = entries)
  })
  manifest_file <- tempfile(fileext = ".json")
  # job is this job: its inputs hold the variant pull, so the new-find
  # tracker's reader (atlas_tracker_view) finds the records it was trained
  # on, as it does a release's.
  atlas_write_json(list(id = id, grid = grid, kind = "private-release", purpose = job$purpose, job = id,
                        from_release = job$from_release, validated_through = job$validated_through,
                        created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                        pull = job$pull, layers_key = job$layers_key,
                        index = index, files = built$entries), manifest_file)
  upload(manifest_file, "release.json")

  fitted <- Filter(function(r) identical(r$status, "fitted"), results)
  trained <- atlas_write_trained_ids(store, list(id = id, index = Filter(function(e) !isTRUE(e$refused), index)),
                                     grid, prefer = atlas_json_string(job$trained_ids), quiet = TRUE)
  grades <- table(factor(built$models$grade, levels = c("strong", "weak", "failed", "untested")),
                  built$models$algorithm)
  seconds <- sum(vapply(results, function(r) as.numeric(r$seconds %||% 0), 0), na.rm = TRUE)
  worker_hours <- sum(vapply(records, function(r) {
    if (is.null(r$started_at) || is.null(r$finished_at)) return(0)
    as.numeric(difftime(as.POSIXct(r$finished_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                        as.POSIXct(r$started_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "hours"))
  }, 0), na.rm = TRUE)
  summary <- Filter(Negate(is.null), list(
    job = id, grid = grid, kind = "private-release", purpose = job$purpose,
    from_release = job$from_release, validated_through = job$validated_through,
    from_pull = job$from_pull,
    pull = list(sha256 = (atlas_job_pull_entry(job) %||% list())$sha256),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    filter = job$filter,
    models_planned = length(job$tasks),
    models_fitted = length(fitted),
    models_refused = sum(vapply(results, function(r) identical(r$status, "refused"), logical(1))),
    models_failed = sum(vapply(results, function(r) identical(r$status, "failed"), logical(1))),
    grades = lapply(stats::setNames(nm = colnames(grades)), function(a) as.list(grades[, a])),
    counted = as.integer(built$counted %||% 0L),
    files = as.list(uploaded),
    trained_ids = list(key = atlas_trained_release_key(id, grid), records = trained$records),
    cpu_hours = round(seconds / 3600, 2),
    worker_hours = round(worker_hours, 2),
    cost_estimate_usd = round(worker_hours * vcpus_per_worker * usd_per_vcpu_hour, 2),
    billing = atlas_job_billing(records, c(id, atlas_finish_id(id))),
    declared = job$declared
  ))
  atlas_store_json(store, key("summary.json"), summary)
  atlas_finish_private_record(store, id, grid, summary, defer)
  say(job$purpose, " ", id, ": ", length(fitted), " of ", length(job$tasks), " models fitted; ",
      sum(built$models$grade == "strong"), " strong; summary at ", key("summary.json"))
  invisible(summary)
}

#' The finishing worker's record, last: the box places what it deferred.
atlas_finish_private_record <- function(store, id, grid, summary, defer) {
  atlas_store_json(store, atlas_shard_key(atlas_finish_id(id), 1L, grid),
                   list(job = atlas_finish_id(id), shard = 1L, private_release = id,
                        finished_at = summary$finished_at,
                        deferred = if (isTRUE(defer)) store$deferred() else list()))
}

#' On the box: once a private release's shards have reported, finish it on
#' one EC2 worker and put its private files in place.
atlas_finish_private_release_on_ec2 <- function(store, job, grid = "draft", ec2 = NULL, config = atlas_ec2_config(),
                                                poll_seconds = 60, wait = Sys.sleep, quiet = FALSE,
                                                clock = Sys.time, hours = config$finish_hours %||% 3,
                                                image_exists = atlas_image_exists) {
  if (!atlas_is_private_release(job)) stop("job ", job$id, " is not a private release", call. = FALSE)
  atlas_one_worker_on_ec2(
    store, atlas_finish_id(job$id), grid,
    command = sprintf("finish-private-release --grid=%s --job=%s --defer", grid, job$id),
    label = paste("the private release of job", job$id),
    ec2 = ec2, config = config, poll_seconds = poll_seconds, wait = wait, quiet = quiet,
    clock = clock, hours = hours, image_exists = image_exists
  )
  record <- atlas_store_text(store, atlas_shard_key(atlas_finish_id(job$id), 1L, grid))
  atlas_place_deferred(store, record$deferred)
  invisible(atlas_store_text(store, atlas_benchmark_key(job$id, "summary.json")))
}
