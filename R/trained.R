# Which records trained a release: kept private, never published.
#
# MycoMap Vision benchmarks photo identification on records it holds out,
# and weighs photos by Atlas's location prior (R/prior.R). A held-out record
# that also trained the maps would flatter that benchmark, so Vision needs to
# know which records a release's models were fitted on. A record's id (an
# iNaturalist observation id, say) leads straight to its exact collection
# point, so the list falls under the rule that no training point is ever
# published: it is written only under the store's private/ prefix, and never
# to a release's files, the API, the site, Zenodo or this repository (Steve,
# 8 Oct 2026). Vision's box reads it from there with access of its own.
#
# A release's models were fitted on different pulls (a model stays while its
# record set is unchanged), so a release's list is put together model by
# model from each record set's fingerprint. Every plan saves, once per pull,
# each record's taxon, its taxon's fingerprint in that pull, and its source
# and source id; finishing a job finds each model's record set in those
# tables, the job's own pull first.
#
#   private/trained-ids/<grid>/pulls/<sha256>.tsv.gz        taxon, fingerprint, source, source_id
#   private/trained-ids/<grid>/releases/<id>.tsv.gz         source, source_id, taxon
#   private/trained-ids/<grid>/releases/<id>.json           counts, and any model not found
#
# Only presences are listed. Background sites are every survey site with no
# taxon attached: a held-out record among them teaches no map its name.

ATLAS_TRAINED_PREFIX <- "private/trained-ids"

atlas_trained_pulls_prefix <- function(grid = "draft") {
  paste0(ATLAS_TRAINED_PREFIX, "/", grid, "/pulls/")
}

atlas_trained_release_key <- function(release, grid = "draft", ext = ".tsv.gz") {
  paste0(ATLAS_TRAINED_PREFIX, "/", grid, "/releases/", release, ext)
}

#' Every record of a pull with what identifies it outside Atlas: taxon, the
#' taxon's record-set fingerprint (as a model's index entry carries it),
#' source and source id.
atlas_trained_pull_table <- function(occurrences) {
  names <- unique(occurrences$scientific_name)
  fingerprints <- atlas_fingerprints_for(occurrences, names)
  data.frame(
    taxon = occurrences$scientific_name,
    fingerprint = unname(fingerprints[occurrences$scientific_name]),
    source = occurrences$source,
    source_id = as.character(occurrences$observation_id),
    stringsAsFactors = FALSE
  )
}

#' Save a pull's table to the store's private prefix, once: the key is the
#' table's own hash, so the same pull is stored once and two pulls never
#' share a key. Returns the key.
atlas_save_trained_pull <- function(store, grid, occurrences) {
  file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(file), add = TRUE)
  table <- atlas_trained_pull_table(occurrences)
  table <- table[order(table$taxon, table$source, table$source_id), , drop = FALSE]
  atlas_write_tsv_gz(table, file)
  key <- paste0(atlas_trained_pulls_prefix(grid), atlas_sha256(file), ".tsv.gz")
  if (!store$exists(key)) store$put(key, file)
  key
}

atlas_read_trained_table <- function(store, key) {
  file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(file), add = TRUE)
  store$get(key, file)
  utils::read.delim(gzfile(file), colClasses = "character", quote = "", na.strings = "")
}

#' Write a release's list: the records of every model in its index, found by
#' record-set fingerprint in the saved pull tables (prefer first). A model
#' whose record set is in none of them is named in the summary, not guessed.
atlas_write_trained_ids <- function(store, release, grid = "draft", prefer = NULL, quiet = FALSE) {
  say <- function(...) if (!isTRUE(quiet)) message(...)
  entries <- Filter(function(e) !isTRUE(e$refused) && is.character(e$fingerprint) && length(e$fingerprint) == 1L,
                    release$index %||% list())
  need <- unique(data.frame(
    taxon = vapply(entries, function(e) e$taxon, ""),
    fingerprint = vapply(entries, function(e) e$fingerprint, ""),
    stringsAsFactors = FALSE
  ))
  pair <- function(d) paste(d$taxon, d$fingerprint, sep = "\x1f")
  keys <- store$list(atlas_trained_pulls_prefix(grid))
  keys <- unique(c(intersect(prefer, keys), rev(sort(keys))))
  found <- list()
  remaining <- need
  for (key in keys) {
    if (!nrow(remaining)) break
    table <- atlas_read_trained_table(store, key)
    hit <- pair(table) %in% pair(remaining)
    if (any(hit)) {
      found[[length(found) + 1L]] <- table[hit, c("source", "source_id", "taxon"), drop = FALSE]
      remaining <- remaining[!pair(remaining) %in% pair(table), , drop = FALSE]
    }
  }
  out <- do.call(rbind, found)
  if (is.null(out)) out <- data.frame(source = character(), source_id = character(), taxon = character())
  out <- unique(out)
  out <- out[order(out$source, out$source_id, out$taxon), , drop = FALSE]
  rownames(out) <- NULL

  file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(file), add = TRUE)
  atlas_write_tsv_gz(out, file)
  store$put(atlas_trained_release_key(release$id, grid), file)
  summary <- list(
    release = release$id, grid = grid,
    written_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    records = nrow(out),
    by_source = as.list(table(out$source)),
    models = length(entries),
    record_sets = nrow(need),
    not_found = as.list(sort(unique(remaining$taxon)))
  )
  atlas_store_json(store, atlas_trained_release_key(release$id, grid, ".json"), summary)
  say("trained ids for release ", release$id, ": ", nrow(out), " records",
      if (nrow(remaining)) paste0("; record sets of ", length(unique(remaining$taxon)), " taxa not found") else "")
  invisible(summary)
}

#' A finished release was fitted on exactly what its base was: its list is
#' the base's, under the new id.
atlas_copy_trained_ids <- function(store, grid, from, to) {
  for (ext in c(".tsv.gz", ".json")) {
    key <- atlas_trained_release_key(from, grid, ext)
    if (!store$exists(key)) return(invisible(FALSE))
    file <- tempfile(fileext = ext)
    store$get(key, file)
    if (identical(ext, ".json")) {
      summary <- jsonlite::fromJSON(file, simplifyVector = FALSE)
      summary$release <- to
      summary$copied_from <- from
      atlas_write_json(summary, file)
    }
    store$put(atlas_trained_release_key(to, grid, ext), file)
    unlink(file)
  }
  invisible(TRUE)
}

#' Write the list for a step that publishes or finishes a release without
#' letting it stop the release: the list is bookkeeping for a benchmark, and
#' a release must not fail on it. A failure is said aloud, as a warning.
atlas_trained_ids_quietly <- function(expr, release) {
  tryCatch(expr, error = function(e) {
    warning("could not write the trained ids for release ", release, ": ", conditionMessage(e),
            call. = FALSE)
    NULL
  })
}

#' The pull a release's job was planned from, read back from the store's
#' objects (a job carries its pull to the workers that way), or NULL.
atlas_release_job_occurrences <- function(store, release, grid = "draft") {
  id <- atlas_json_string(release$job)
  if (is.null(id)) return(NULL)
  job <- tryCatch(atlas_read_job(store, id, grid), error = function(e) NULL)
  pulls <- Filter(function(e) grepl("^occurrences/occurrences-.*[.]tsv[.]gz$", e$path %||% ""), job$inputs %||% list())
  if (!length(pulls)) return(NULL)
  file <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(file), add = TRUE)
  store$get(atlas_object_key(pulls[[1]]$sha256), file)
  atlas_read_occurrences(file)
}

#' Write the list for a release made before lists were kept (or whose list
#' failed to write): from the pull its job was planned from, kept in the
#' store, and this machine's own pull besides. A model whose record set is in
#' neither is named in the summary. The current release when none is named.
atlas_backfill_trained_ids <- function(store, release = NULL, grid = "draft", quiet = FALSE) {
  manifest <- if (is.null(release)) {
    atlas_current_release(store, grid)
  } else {
    atlas_store_text(store, paste0("releases/", grid, "/", release, ".json"))
  }
  if (is.null(manifest)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)
  job_pull <- atlas_release_job_occurrences(store, manifest, grid)
  prefer <- if (!is.null(job_pull)) atlas_save_trained_pull(store, grid, job_pull)
  local <- tryCatch(atlas_read_occurrences(), error = function(e) NULL)
  if (!is.null(local)) atlas_save_trained_pull(store, grid, local)
  atlas_write_trained_ids(store, manifest, grid, prefer = prefer, quiet = quiet)
}

#' Fetch a release's list from the store to a local file (the current
#' release when none is named), for handing to Vision's box.
atlas_fetch_trained_ids <- function(store, release = NULL, grid = "draft", out) {
  release <- release %||% atlas_current_release(store, grid)$id
  if (is.null(release)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)
  key <- atlas_trained_release_key(release, grid)
  if (!store$exists(key)) stop("no trained ids for release ", release, call. = FALSE)
  store$get(key, out)
  invisible(out)
}

#' A presigned link to a release's list, for Vision's box to fetch over HTTPS
#' without credentials of its own. S3 stores only. The link lasts `hours`
#' (at most 12), and no longer than the signing credentials do: an instance
#' role's last about 6 hours.
atlas_trained_ids_link <- function(store_uri, release, grid = "draft", hours = 1,
                                   presign = atlas_presign_s3) {
  s3 <- atlas_s3_location(store_uri)
  if (is.null(s3)) stop("a link needs an S3 store; copy the file with --out instead", call. = FALSE)
  if (!is.numeric(hours) || length(hours) != 1L || !is.finite(hours) || hours <= 0 || hours > 12) {
    stop("hours must be more than 0 and at most 12", call. = FALSE)
  }
  presign(s3$bucket, paste0(s3$prefix, atlas_trained_release_key(release, grid)),
          paste0("atlas-trained-ids-", grid, "-", release, ".tsv.gz"),
          expires = as.integer(round(hours * 3600)), content_type = "application/gzip")
}
