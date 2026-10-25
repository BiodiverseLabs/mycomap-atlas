# Paper E9, redesigned (plan-e9, 2026-10-25): DNA names against record names,
# as a paired hindcast. The taxa whose record set differs under the two
# labellings are fitted under each, on the E2 hindcast's own pull (cutoff
# 2026-08-17), and both are scored on E2's later finds.
#
# A job carries one pull, and the two labellings name the same records
# differently, so they are two private jobs, planned here together, from one
# Atlas commit, to be launched together on one processor family:
#
#   dna     the hindcast's pull as it is (its records under their DNA names),
#           the changed taxa only. Same records, seeds and blocks as the
#           hindcast's models: a dna model reproduces the hindcast's.
#   record  the same pull with each record under its .org name
#           (atlas_record_named), the changed taxa only. Each model draws with
#           its DNA pair's seed and fits on its DNA pair's spatial block, so
#           only the labelling differs.
#
# A taxon is changed when its record set under one labelling is not its set
# under the other, including a name only one labelling has. Taxa whose
# records do not change are the same under both and are not fitted.
#
#   ./atlas plan-job --e9-pair --from-release=<hindcast priv-ID> [--shards=N] [--dry-run]

ATLAS_E9_SIDES <- c("dna", "record")

#' The changed taxa of each algorithm: names and fingerprints on each side,
#' and which names are changed.
atlas_e9_changed <- function(dna, record, algorithms, min_presences, grid = "draft") {
  points <- list(dna = atlas_occurrence_points(dna, grid), record = atlas_occurrence_points(record, grid))
  out <- list()
  for (algorithm in algorithms) {
    algo <- atlas_algorithm(algorithm)
    minimum <- atlas_algorithm_min(algo, min_presences)
    maximum <- atlas_algorithm_max(algo) + ATLAS_RANGE_MARGIN
    candidates <- lapply(points, function(p) atlas_batch_candidates(p, minimum, max_presences = maximum)$scientific_name)
    fingerprints <- list(dna = atlas_fingerprints_for(dna, candidates$dna),
                         record = atlas_fingerprints_for(record, candidates$record))
    names <- union(candidates$dna, candidates$record)
    same <- vapply(names, function(n) {
      n %in% candidates$dna && n %in% candidates$record &&
        identical(unname(fingerprints$dna[[n]]), unname(fingerprints$record[[n]]))
    }, TRUE)
    out[[algorithm]] <- list(candidates = candidates, fingerprints = fingerprints,
                             changed = sort(names[!same]), unchanged = sum(same))
  }
  out
}

#' The block a model is to be fitted on: the hindcast model of this taxon and
#' algorithm, else another learner of the taxon there; NULL when none.
atlas_e9_block <- function(blocks, algorithm, taxon) {
  own <- blocks[[paste(algorithm, taxon, sep = "|")]]
  if (!is.null(own)) return(own)
  other <- Filter(Negate(is.null), lapply(c("maxnet", "rf", "xgboost", "esm"), function(a) blocks[[paste(a, taxon, sep = "|")]]))
  if (length(other)) other[[1]]
}

#' Plan E9's two jobs from a finished hindcast. dry_run says what it would
#' fit and cost, and writes nothing.
atlas_plan_e9_pair <- function(store = atlas_store(), hindcast, grid = "draft", shards = 4L, quiet = FALSE,
                               dry_run = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  manifest_key <- atlas_benchmark_key(hindcast, "release.json")
  if (!store$exists(manifest_key) || !store$exists(atlas_benchmark_key(hindcast, "summary.json"))) {
    stop("no finished private release ", hindcast, ": E9 is planned from the finished E2 hindcast", call. = FALSE)
  }
  manifest <- atlas_store_text(store, manifest_key)
  if (!identical(manifest$purpose, "hindcast") || !is.null(manifest$refit)) {
    stop(hindcast, " is not a hindcast", call. = FALSE)
  }
  hjob <- atlas_read_job(store, atlas_json_string(manifest$job) %||% hindcast, grid)
  if (!atlas_is_private_release(hjob) || !identical(hjob$purpose, "hindcast")) {
    stop("job ", hjob$id, " is not a hindcast", call. = FALSE)
  }
  cutoff <- atlas_json_string(hjob$validated_through)
  pull_entry <- atlas_job_pull_entry(hjob)
  if (is.null(pull_entry)) stop("hindcast job ", hjob$id, " carries no pull", call. = FALSE)
  pull_file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(pull_file), add = TRUE)
  store$get(atlas_object_key(pull_entry$sha256), pull_file)
  dna <- atlas_read_occurrences(pull_file)
  check <- atlas_filter_validated_through(dna, cutoff, undated = "exclude")
  if (check$counts$records_removed != 0L) {
    stop("hindcast ", hindcast, "'s pull holds records outside its cutoff; nothing planned", call. = FALSE)
  }
  named <- atlas_record_named(dna)
  record <- named$occurrences

  algorithms <- as.character(unlist(hjob$algorithms))
  min_presences <- hjob$fit$min_presences %||% 20
  changed <- atlas_e9_changed(dna, record, algorithms, min_presences, grid)

  # The hindcast's models' blocks and seeds: the fingerprint each was
  # fitted on is its seed, and a record-name model draws with its DNA pair's.
  hindcast_fp <- list()
  for (t in hjob$tasks) hindcast_fp[[paste(t$algorithm, t$taxon, sep = "|")]] <- t$fingerprint
  dna_names <- unique(unlist(lapply(changed, function(x) intersect(x$changed, x$candidates$dna))))
  paired_names <- unique(unlist(lapply(changed, function(x) x$changed)))
  # A taxon's DNA record set is the same whichever algorithm asks.
  fingerprints_dna <- do.call(c, unname(lapply(changed, function(x) as.list(x$fingerprints$dna))))
  fingerprints_dna <- unlist(fingerprints_dna[!duplicated(names(fingerprints_dna))])
  blocks <- atlas_release_blocks(store, manifest, fingerprints_dna[names(fingerprints_dna) %in% paired_names],
                                 hjob$fit, atlas_json_string(hjob$layers_key) %||% hjob$layers_key, grid)

  index <- Filter(function(e) !isTRUE(e$refused), manifest$index %||% list())
  areas <- vapply(index, function(e) if (is.numeric(e$area_km2) && length(e$area_km2) == 1L) e$area_km2 else NA_real_,
                  numeric(1))
  typical <- if (any(is.finite(areas))) stats::median(areas, na.rm = TRUE) else 5e6
  area_of <- list()
  for (e in index) area_of[[paste(e$algorithm, e$taxon)]] <- e$area_km2

  tasks <- list(dna = list(), record = list())
  for (algorithm in algorithms) {
    x <- changed[[algorithm]]
    for (name in intersect(x$changed, x$candidates$dna)) {
      fp <- unname(x$fingerprints$dna[[name]])
      was <- hindcast_fp[[paste(algorithm, name, sep = "|")]]
      if (!is.null(was) && !identical(as.character(was), fp)) {
        stop("hindcast ", hindcast, "'s pull no longer gives ", name, "'s record set; nothing planned", call. = FALSE)
      }
      tasks$dna[[length(tasks$dna) + 1L]] <- Filter(Negate(is.null), list(
        taxon = name, algorithm = algorithm, fingerprint = fp, seed_from = fp,
        block = atlas_e9_block(blocks, algorithm, name),
        cost = atlas_task_cost(algorithm, area_of[[paste(algorithm, name)]], typical)))
    }
    for (name in intersect(x$changed, x$candidates$record)) {
      pair <- if (name %in% dna_names) unname(fingerprints_dna[[name]])
      tasks$record[[length(tasks$record) + 1L]] <- Filter(Negate(is.null), list(
        taxon = name, algorithm = algorithm, fingerprint = unname(x$fingerprints$record[[name]]),
        seed_from = pair, block = if (!is.null(pair)) atlas_e9_block(blocks, algorithm, name),
        cost = atlas_task_cost(algorithm, area_of[[paste(algorithm, name)]], typical)))
    }
  }
  taxa_of <- function(side) unique(vapply(tasks[[side]], function(t) t$taxon, ""))
  pairs <- intersect(taxa_of("dna"), taxa_of("record"))
  counts <- list(
    records_in_pull = nrow(dna), records_record_named = nrow(record),
    records_not_species_level = named$counts$records_not_species_level,
    models_unchanged = sum(vapply(changed, function(x) x$unchanged, 0L)),
    taxa_paired = length(pairs), taxa_dna_only = length(setdiff(taxa_of("dna"), pairs)),
    taxa_record_only = length(setdiff(taxa_of("record"), pairs)),
    models = list(dna = length(tasks$dna), record = length(tasks$record)),
    models_with_dna_block = sum(vapply(tasks$record, function(t) !is.null(t$block), TRUE))
  )
  seconds <- atlas_private_seconds(store, hjob$id, grid)
  cpu_hours <- sum(vapply(c(tasks$dna, tasks$record), function(t) seconds[[t$algorithm]] %||% 600, numeric(1))) / 3600
  estimate <- list(cpu_hours = round(cpu_hours, 1),
                   basis = paste("mean seconds per model of job", hjob$id, "where timed, else ATLAS_PRIVATE_SECONDS"))
  if (isTRUE(dry_run)) {
    say("E9 pair from ", hindcast, " (dry run, nothing written): ", counts$taxa_paired, " taxa paired, ",
        counts$taxa_dna_only, " DNA only, ", counts$taxa_record_only, " record only; ",
        counts$models$dna, " + ", counts$models$record, " models; ", counts$models_unchanged,
        " unchanged models not fitted; about ", estimate$cpu_hours, " CPU-h")
    return(invisible(list(hindcast = hindcast, counts = counts, estimate = estimate, tasks = tasks)))
  }
  if (!length(tasks$dna) && !length(tasks$record)) stop("nothing to fit: no taxon's records change", call. = FALSE)

  ids <- lapply(stats::setNames(nm = ATLAS_E9_SIDES), function(side) {
    paste0("priv-", atlas_release_id(digest::digest(list(tasks[[side]], hindcast, "e9", side), algo = "sha256")))
  })
  others <- Filter(function(e) !startsWith(e$path, "occurrences/"), hjob$inputs %||% list())
  jobs <- list()
  for (side in ATLAS_E9_SIDES) {
    if (!length(tasks[[side]])) next
    side_tasks <- tasks[[side]]
    assignment <- atlas_assign_shards(vapply(side_tasks, function(t) t$cost, numeric(1)),
                                      max(1L, min(as.integer(shards), length(side_tasks))),
                                      groups = vapply(side_tasks, function(t) t$taxon, ""))
    for (i in seq_along(side_tasks)) side_tasks[[i]]$shard <- assignment[[i]]
    occurrences <- if (side == "dna") dna else record
    id <- ids[[side]]
    pull <- atlas_in_scratch_data_dir({
      file <- paste0("occurrences-", id, ".tsv.gz")
      atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
      atlas_write_json(list(
        stamp = id, pulled_at = hjob$pull$pulled_at %||% NA_character_, since = NA_character_,
        records = nrow(occurrences), fingerprint = atlas_fingerprint(occurrences), file = file,
        made_from = list(release = hjob$from_release, job = hjob$id, hindcast = hindcast, pull = pull_entry$sha256,
                         purpose = "e9", side = side, validated_through = cutoff)
      ), atlas_path("occurrences", "latest.json"))
      entries <- atlas_file_entries(c(file.path("occurrences", file), "occurrences/latest.json"))
      atlas_upload_objects(store, entries)
      entries
    })
    job <- list(
      id = id, grid = grid, kind = "private-release",
      purpose = if (side == "dna") "hindcast" else "hindcast-record-names",
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      from_release = hjob$from_release, from_job = hjob$from_job, validated_through = cutoff,
      from_pull = list(path = pull_entry$path, sha256 = pull_entry$sha256),
      algorithms = as.list(unique(vapply(side_tasks, function(t) t$algorithm, ""))), shards = max(assignment),
      fit = hjob$fit, layers_key = hjob$layers_key, pull = hjob$pull,
      inputs = c(pull, others),
      public = list(), tasks = side_tasks, retire = list(), deferred = 0L,
      trained_ids = atlas_save_trained_pull(store, grid, occurrences),
      filter = list(records_in_pull = nrow(dna), records_kept = nrow(occurrences), records_after_cutoff_kept = 0L,
                    records_not_species_level = if (side == "record") named$counts$records_not_species_level),
      estimate = estimate,
      e9 = list(hindcast = hindcast, hindcast_job = hjob$id, side = side,
                partner = if (side == "dna") ids$record else ids$dna, counts = counts),
      declared = paste0("E9 (plan-e9, 2026-10-25): the taxa whose record set differs between DNA names and record ",
                        "names, fitted under ", if (side == "dna") "DNA names" else "record names",
                        " on hindcast ", hindcast, "'s pull (cutoff ", cutoff, "), with the hindcast's settings; ",
                        if (side == "dna") "seeds and blocks are the hindcast's." else
                          "each model draws with its DNA pair's seed and fits on its block.")
    )
    atlas_store_json(store, paste0("jobs/", grid, "/", id, "/job.json"), job)
    jobs[[side]] <- job
  }
  say("E9 pair from ", hindcast, ": ", paste(vapply(names(jobs), function(s) paste(s, jobs[[s]]$id), ""),
                                              collapse = ", "), "; ", counts$taxa_paired, " taxa paired; about ",
      estimate$cpu_hours, " CPU-h")
  invisible(jobs)
}
