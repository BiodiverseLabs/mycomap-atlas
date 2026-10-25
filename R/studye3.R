# Paper E3: the published release's own maps, scored on records first
# validated after it was made (docs/experiments,
# 2026-10-21-prereg-e3-prospective). One read-out, with E2's scorer
# (R/e2score.R, R/studyscore.R) and E6b's kernels; nothing is refitted.
#
# The training set is the release's own pull, read from its job. The test
# finds come from a fresh full pull (this machine's, or one staged under a
# private store prefix by stage-pull, for a study job): records first
# validated in [from, until] whose record is not in the release's pull. A
# find counts under the name it had when it was first validated: a rename or
# respelling that .org's name-change log (R/namechanges.R) dates after that
# day is undone; a merge or a split, which has no single inverse, and a
# change logged on the validation day itself, keep the find apart. Every
# find kept apart is counted by why.
#
#   ./atlas stage-pull --out=private/study/e3-pull-<date>/          (on the box)
#   ./atlas plan-study --command=study-score --shards=1 --args="--release=<frozen> \
#     --finds-pull=private/study/e3-pull-<date>/ --from=2026-10-14 --until=<read-out> \
#     [--kernels-from=JOB[,PATCH]] [--counts-only]"
#
# --counts-only is the pre-registered look before the read-out: counts of
# finds, places and ranked places by grade, and no rank or score at all.
#
# Everything written is counts and shares: no record, place or coordinate.

# Why a fresh-pull record is not a test find, in the order they are decided.
ATLAS_E3_APART <- c("in_release_pull", "undated", "green_before_pull", "before_live", "after_until",
                    "name_merge", "name_split", "name_same_day", "off_grid")

# The name-change kinds that are undone, and those that keep a find apart.
ATLAS_E3_UNDONE <- c("rename", "respelling")
ATLAS_E3_KEPT_APART <- c("merge", "split")

#' Each find's name on the day it was first validated, from the log.
#'
#' refs are the finds as the log names records (inat:N, mo:N; NA for others),
#' green their first-validation dates, changes the log's entries
#' (atlas_read_name_changes()$changes). A change counts for a find when its
#' records hold the find and it was logged after that day. Returns, per find,
#' the name to score it under (NA: keep its pulled name) and the kind of
#' change behind it: NA (none), "rename", "respelling", "merge", "split", or
#' "same_day" (a change logged that very day, which may have come before or
#' after the validation, so the find is kept apart).
atlas_e3_name_at_green <- function(refs, green, changes) {
  n <- length(refs)
  out <- data.frame(name = rep(NA_character_, n), kind = rep(NA_character_, n), stringsAsFactors = FALSE)
  if (!n || !length(changes)) return(out)
  rows <- lapply(changes, function(r) {
    if (!length(r$records)) return(NULL)
    kind <- if (isTRUE(r$respelling) && identical(r$kind, "rename")) "respelling" else as.character(r$kind)
    data.frame(ref = r$records, id = r$id, day = substr(as.character(r$logged_at), 1, 10),
               kind = kind, old_name = r$old_name, stringsAsFactors = FALSE)
  })
  log <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(log) || !nrow(log)) return(out)
  log <- log[order(log$day, log$id), , drop = FALSE]
  for (i in which(!is.na(refs) & refs %in% log$ref)) {
    mine <- log[log$ref == refs[[i]], , drop = FALSE]
    if (any(mine$day == green[[i]])) {
      out$kind[[i]] <- "same_day"
      next
    }
    later <- mine[mine$day > green[[i]], , drop = FALSE]
    if (!nrow(later)) next
    apart <- later$kind[later$kind %in% ATLAS_E3_KEPT_APART]
    if (length(apart)) {
      out$kind[[i]] <- apart[[1]]
      next
    }
    # The earliest later change names what the find was called before it:
    # undoing the changes in turn ends at its first one's old name.
    out$name[[i]] <- later$old_name[[1]]
    out$kind[[i]] <- later$kind[[1]]
  }
  out
}

#' The test finds and the training records: E2's split, for a published
#' release and a fresh pull.
#'
#' release_pull is the release's own pull (its training set), fresh the
#' fresh pull, pulled_on the release pull's date (YYYY-MM-DD), from and until
#' the window of first validation. Returns finds (key, taxon, x, y,
#' first_green_on, kept_apart, name_change) in the order they count, the
#' training records (taxon, x, y), and the counts kept apart.
atlas_e3_split <- function(release_pull, fresh, pulled_on, from, until, changes = list(), grid = "draft") {
  for (d in c(pulled_on, from, until)) {
    if (!is.character(d) || length(d) != 1L || !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", d)) {
      stop("dates must be YYYY-MM-DD", call. = FALSE)
    }
  }
  if (from <= pulled_on) {
    stop("--from ", from, " must be after the release's pull (", pulled_on, "): earlier finds could be its training",
         call. = FALSE)
  }
  if (until < from) stop("--until is before --from", call. = FALSE)
  if (!ATLAS_FIRST_GREEN_FIELD %in% names(fresh)) {
    stop("the fresh pull has no ", ATLAS_FIRST_GREEN_FIELD, " column", call. = FALSE)
  }
  key_of <- function(p) atlas_record_key(p$source, p$observation_id)
  release_keys <- key_of(release_pull)
  release_ids <- as.character(release_pull$id %||% character())
  key <- key_of(fresh)
  id <- as.character(fresh$id %||% rep(NA_character_, nrow(fresh)))
  green <- as.character(fresh[[ATLAS_FIRST_GREEN_FIELD]])
  dated <- !is.na(green) & nzchar(green)
  placed <- atlas_tracker_place(fresh$latitude, fresh$longitude, grid)
  located <- is.finite(placed$x) & is.finite(placed$y)
  reason <- rep(NA_character_, nrow(fresh))
  # A record in the release's pull, by its key or its .org id, trained the
  # maps: never a find, whatever its date now says.
  reason[key %in% release_keys | (!is.na(id) & id %in% release_ids)] <- "in_release_pull"
  todo <- is.na(reason)
  reason[todo & !dated] <- "undated"
  todo <- is.na(reason)
  reason[todo & green < pulled_on] <- "green_before_pull"
  reason[todo & green >= pulled_on & green < from] <- "before_live"
  reason[todo & green > until] <- "after_until"
  names_now <- as.character(fresh$scientific_name)
  taxon <- names_now
  change <- rep(NA_character_, nrow(fresh))
  todo <- is.na(reason)
  if (any(todo) && length(changes)) {
    at_green <- atlas_e3_name_at_green(atlas_occurrence_refs(fresh[todo, , drop = FALSE]), green[todo], changes)
    change[todo] <- at_green$kind
    undo <- !is.na(at_green$name)
    taxon[which(todo)[undo]] <- at_green$name[undo]
    reason[which(todo)[at_green$kind %in% "merge"]] <- "name_merge"
    reason[which(todo)[at_green$kind %in% "split"]] <- "name_split"
    reason[which(todo)[at_green$kind %in% "same_day"]] <- "name_same_day"
  }
  reason[is.na(reason) & !located] <- "off_grid"
  candidate <- reason != "in_release_pull" | is.na(reason)
  finds <- data.frame(key = key, taxon = taxon, x = placed$x, y = placed$y, first_green_on = green,
                      kept_apart = reason, name_change = change,
                      stringsAsFactors = FALSE)[candidate, , drop = FALSE]
  finds <- finds[order(finds$first_green_on, na.last = TRUE), , drop = FALSE]
  rownames(finds) <- NULL
  trained <- atlas_tracker_place(release_pull$latitude, release_pull$longitude, grid)
  keep <- is.finite(trained$x) & is.finite(trained$y)
  training <- data.frame(taxon = as.character(release_pull$scientific_name), x = trained$x, y = trained$y,
                         stringsAsFactors = FALSE)[keep, , drop = FALSE]
  rownames(training) <- NULL
  counts <- as.list(table(factor(reason[!is.na(reason)], levels = ATLAS_E3_APART)))
  scored <- is.na(finds$kept_apart)
  undone <- as.list(table(factor(finds$name_change[scored & !is.na(finds$name_change)], levels = ATLAS_E3_UNDONE)))
  list(finds = finds, training = training, kept_apart = counts, names_undone = undone,
       test_finds = sum(scored), release_keys = release_keys)
}

#' A fresh pull, its manifest and the name-change log read with it: this
#' machine's own (prefix NULL), or one stage-pull put under a private store
#' prefix. A pull made with --since holds only part of the records, so it is
#' refused: a missing record would look like no find.
atlas_e3_fresh <- function(store, prefix = NULL) {
  if (is.null(prefix)) {
    manifest <- atlas_read_manifest()
    if (is.null(manifest)) stop("no pull on this machine: run ./atlas pull-occurrences", call. = FALSE)
    pull <- atlas_read_occurrences()
    changes <- atlas_read_name_changes()
  } else {
    prefix <- atlas_study_check_key(paste0(sub("/*$", "/", as.character(prefix))))
    dir <- tempfile("e3-pull-")
    dir.create(dir)
    get <- function(name) {
      path <- file.path(dir, name)
      store$get(paste0(prefix, name), path)
      path
    }
    manifest <- jsonlite::fromJSON(get("latest.json"), simplifyVector = TRUE)
    pull <- atlas_read_occurrences(get(as.character(manifest$file)))
    changes <- if (store$exists(paste0(prefix, "name-changes.json"))) {
      atlas_read_name_changes(get("name-changes.json"))
    } else {
      list(cursor = NA, changes = list())
    }
  }
  since <- manifest$since %||% NA
  if (!(length(since) == 1L && (is.na(since) || !nzchar(as.character(since))))) {
    stop("the fresh pull was made with --since ", since, ": a read-out needs a full pull", call. = FALSE)
  }
  list(pull = pull, manifest = manifest, changes = changes)
}

#' Copy this machine's pull, its manifest and its name-change log to a
#' private store prefix, for a study job to score (study-score --finds-pull).
#' The pull names records and places, so only under private/study/.
atlas_stage_pull <- function(store, out) {
  out <- atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
  if (!startsWith(out, "private/")) stop("a pull is private: stage it under private/study/, not ", out, call. = FALSE)
  manifest <- atlas_read_manifest()
  if (is.null(manifest)) stop("no pull on this machine: run ./atlas pull-occurrences", call. = FALSE)
  files <- c(atlas_path("occurrences", as.character(manifest$file)), atlas_path("occurrences", "latest.json"))
  changes <- atlas_name_changes_path()
  if (file.exists(changes)) files <- c(files, changes)
  for (f in files) store$put(paste0(out, basename(f)), f)
  invisible(paste0(out, basename(files)))
}

#' The counts a look before the read-out may see: finds and places, and how
#' many places each grade and tier ranks. No rank, share or score.
atlas_e3_counts <- function(places, model_maps_for, known_names) {
  scored <- atlas_e2_score(places, model_maps_for, known_names)
  models <- scored[scored$kind %in% "model", , drop = FALSE]
  ranked <- models[atlas_e2_ranked(models), , drop = FALSE]
  count_by <- function(field, levels) {
    lapply(stats::setNames(levels, levels), function(g) {
      rows <- ranked[ranked[[field]] %in% g, , drop = FALSE]
      list(rows = nrow(rows), taxa = length(unique(rows$taxon)), ranked_places = atlas_e2_place_count(rows))
    })
  }
  list(places = nrow(places), taxa = length(unique(places$taxon)),
       by_grade = count_by("grade", c("strong", "weak", "failed", "untested")),
       by_tier = count_by("tier", ATLAS_TIERS),
       classes = as.list(table(models$class)))
}

#' Score a published release on the finds first validated after it (E3).
#'
#' release is a published release (not a hindcast). finds_pull is a store
#' prefix stage-pull wrote, or NULL for this machine's pull. from and until
#' bound the first-validation dates (from must be after the release's
#' pull). kernels_from are E6b-style distance study jobs on this release.
#' counts_only writes the counts a look before the read-out may see, and no
#' score. view, release_pull and fresh are replaceable for tests.
atlas_e3_study <- function(store = atlas_store(), release, from, until, finds_pull = NULL, grid = "draft",
                           kernels_from = NULL, counts_only = FALSE, reps = ATLAS_E2_BOOTSTRAP, seed = 1L,
                           out = NULL, quiet = FALSE, view = NULL, release_pull = NULL, fresh = NULL) {
  started <- Sys.time()
  say <- function(...) if (!isTRUE(quiet)) message(...)
  if (!is.null(out)) atlas_study_check_key(paste0(sub("/*$", "/", as.character(out))))
  view <- view %||% atlas_tracker_view(store, release, grid)
  if (identical(view$manifest$purpose, "hindcast")) {
    stop(release, " is a hindcast: score it with study-score --hindcast", call. = FALSE)
  }
  pulled_on <- substr(as.character(view$pulled_at), 1, 10)
  if (is.na(pulled_on) || !nzchar(pulled_on)) stop("release ", release, " records no pull date", call. = FALSE)
  release_pull <- release_pull %||% atlas_tracker_release_pull(store, view$manifest, grid)
  fresh <- fresh %||% atlas_e3_fresh(store, finds_pull)
  split <- atlas_e3_split(release_pull, fresh$pull, pulled_on, as.character(from), as.character(until),
                          fresh$changes$changes %||% list(), grid)
  # The guard the prereg names: no test find is a training record.
  test <- split$finds[is.na(split$finds$kept_apart), , drop = FALSE]
  if (any(test$key %in% split$release_keys) || any(test$key %in% view$pull$key)) {
    stop("a test find is one of the release's training records", call. = FALSE)
  }
  # Names as the release knows them, as E2 matches them; an unknown name is
  # counted by the scorer.
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
  manifest <- fresh$manifest %||% list()
  settings <- list(
    release = release, release_pulled_at = as.character(view$pulled_at), from = as.character(from),
    until = as.character(until), grid = grid, reps = as.integer(reps), seed = as.integer(seed),
    counts_only = isTRUE(counts_only), kernels_from = if (!is.null(kernels_from)) as.list(kernels_from),
    image_commit = Sys.getenv("ATLAS_COMMIT", unset = NA),
    # Each pull rule's own count, as the pull recorded it (the pre-registration
    # asks for them): the drop list's hash and removed rows, the Mushroom
    # Observer records left out and why, and how the pull named its records
    # (by DNA, by record name, and the sequences its flags set aside).
    fresh_pull = list(file = manifest$file %||% NA, pulled_at = manifest$pulled_at %||% NA,
                      records = manifest$records %||% NA, exclusions = manifest$exclusions,
                      mo_left_out = manifest$mo_left_out, names = manifest$names,
                      name_change_cursor = fresh$changes$cursor %||% NA, staged_at = finds_pull)
  )
  finds <- list(test_finds = split$test_finds, kept_apart = split$kept_apart, names_undone = split$names_undone,
                places = nrow(places), off_grid_places = attr(places, "off_grid") %||% 0L)
  if (isTRUE(counts_only)) {
    result <- list(started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), study = "e3-counts",
                   settings = settings, finds = finds, counts = atlas_e3_counts(places, model_maps_for, view$names))
    name <- "e3-counts"
  } else {
    kernel_run <- if (!is.null(kernels_from)) atlas_score_kernel_runs(store, kernels_from, release)
    kernel_maps_for <- if (!is.null(kernel_run)) {
      function(taxon) atlas_score_kernel_maps(model_maps_for(taxon),
                                              atlas_score_find(kernel_run$dirs, atlas_distance_raster_path, taxon))
    }
    core <- atlas_score_baselines_core(places, model_maps_for, kernel_maps_for, NULL,
                                       known_names = view$names, reps = as.integer(reps), seed = as.integer(seed))
    h <- core$hypotheses
    e3 <- list(H3a = h$H2a, H3b = h$H2b,
               H3c = if (!is.null(core$kernel)) core$kernel$H6b else list(tested = FALSE, why = "no kernels given"))
    settings$kernels_patched <- if (!is.null(kernel_run)) kernel_run$patched
    result <- c(list(started_at = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), study = "e3",
                     settings = settings, finds = finds, e3 = e3), core)
    name <- "e3"
  }
  result$seconds <- round(as.numeric(difftime(Sys.time(), started, units = "secs")), 1)
  stamp <- format(started, "%Y%m%dT%H%M%SZ", tz = "UTC")
  path <- atlas_path("score-studies", grid, paste0(name, "-", gsub("[^A-Za-z0-9]+", "-", release), "-", stamp, ".json"),
                     create = TRUE)
  atlas_write_json(result, path)
  if (!is.null(out)) atlas_study_publish(store, path, out, root = dirname(path))
  say(sprintf("E3 %s on %s: %d test finds, %d places -> %s", if (isTRUE(counts_only)) "counts" else "read-out",
              release, split$test_finds, nrow(places), path))
  invisible(c(result, list(path = path)))
}
