# The collection cells as the sources stand now (Steve, 2026-11-07).
#
# A release's cells leave out the records on the privacy list made with its
# pull (R/privacy.R). Sources change after that: an observer obscures or hides
# a point, or Mushroom Observer no longer holds a record. Before a release goes
# into an archive version, its cells are made again from the same pull,
# leaving out four groups:
#   (a) the records on the release's own privacy list;
#   (b) iNaturalist records whose cached answer now says obscured, or placed no
#       better than ATLAS_MAX_ACCURACY_M, or that have no cached answer now;
#   (c) Mushroom Observer records whose observer shows no point now, or that
#       have no cached answer now;
#   (d) Mushroom Observer records .org marks as deleted at the source.
# Records from the other sources are counted where recorded.
#
# Made from the same pull with group (a) alone, the cells must equal the
# release's own file, or nothing is written. What is written holds counts and
# the cells file only, never a record's number.

ATLAS_CELLS_NOW_GROUPS <- c(
  a = "on the release's privacy list",
  b = "iNaturalist: obscured, coarser than 1 km, or no cached answer now",
  c = "Mushroom Observer: no point the observer shows, or no cached answer now",
  d = "Mushroom Observer: deleted at the source"
)

# A status answer that has gone wrong (a page lost, a view emptied) would read
# as thousands of records with no answer and strip the cells. Above these
# shares nothing is written: the share of a source's records with no cached
# answer now (36 of 126,506 iNaturalist and 24 of 5,035 MO in the frozen pull
# on 2026-11-07), and the share of the pull left out beyond the list.
ATLAS_CELLS_NOW_MAX_UNANSWERED <- 0.02
ATLAS_CELLS_NOW_MAX_BEYOND <- 0.01

ATLAS_CELLS_NOW_FILE <- "cells.tsv.gz"
ATLAS_CELLS_NOW_SUMMARY <- "cells-now.json"

#' The read-only statements that say how the sources stand now. The cached
#' iNaturalist answers come a page at a time, by the last character of the
#' observation number, so each page stays well inside the route's 60 s cap.
atlas_cells_now_sql <- function(max_m = ATLAS_MAX_ACCURACY_M) {
  digits <- as.character(0:9)
  inat_page <- function(last) {
    where <- if (is.na(last)) {
      sprintf("right(c.source_observation_id, 1) NOT IN (%s)", paste(sprintf("'%s'", digits), collapse = ", "))
    } else {
      sprintf("right(c.source_observation_id, 1) = '%s'", last)
    }
    atlas_one_line(sprintf(paste(
      "SELECT c.source_observation_id AS number,",
      "bool_or(c.coordinates_obscured = true OR c.positional_accuracy > %d) AS hidden",
      "FROM observation_cache c WHERE c.source = 'inat' AND %s GROUP BY 1"
    ), as.integer(max_m), where))
  }
  list(
    inat = c(lapply(digits, inat_page), list(inat_page(NA))),
    mo = atlas_one_line(sprintf(paste(
      "SELECT m.source_observation_id AS number,",
      "bool_or(m.latitude IS NOT NULL AND m.longitude IS NOT NULL) AS shown",
      "FROM %s m GROUP BY 1"
    ), ATLAS_MO_POINTS)),
    deleted = atlas_one_line(sprintf(paste(
      "SELECT o.observation_id AS number FROM observations o",
      "WHERE o.source = '%s' AND %s IS NOT NULL"
    ), ATLAS_MO_SOURCE, ATLAS_SOURCE_DELETED))
  )
}

#' Ask .org how the sources stand now.
atlas_cells_now_status <- function(run = atlas_run_sql, host = atlas_sql_host()) {
  sql <- atlas_cells_now_sql()
  ask <- function(statement, columns) {
    page <- atlas_parse_tsv(run(statement, host = host))
    if (!nrow(page)) {
      return(stats::setNames(as.data.frame(rep(list(character()), length(columns)), stringsAsFactors = FALSE),
                             columns))
    }
    missing <- setdiff(columns, names(page))
    if (length(missing)) stop("the status query is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
    page[, columns, drop = FALSE]
  }
  inat <- do.call(rbind, lapply(sql$inat, ask, columns = c("number", "hidden")))
  list(
    inat = inat,
    mo = ask(sql$mo, c("number", "shown")),
    deleted = ask(sql$deleted, "number")$number,
    checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}

atlas_cells_now_true <- function(x) tolower(as.character(x)) %in% c("t", "true")

#' Which of a pull's records each group leaves out. Returns a logical matrix,
#' one column per group, one row per record.
atlas_cells_now_groups <- function(pull, listed, status) {
  keys <- atlas_record_key(pull$source, pull$observation_id)
  inat <- pull$source == ATLAS_INAT_SOURCE
  mo <- pull$source == ATLAS_MO_SOURCE
  # Each answer is keyed by its own source (R/keys.R): an answer for an
  # iNaturalist number never reaches another source's record of that number.
  at_inat <- match(keys, atlas_record_key(ATLAS_INAT_SOURCE, status$inat$number))
  at_mo <- match(keys, atlas_record_key(ATLAS_MO_SOURCE, status$mo$number))
  hidden <- atlas_cells_now_true(status$inat$hidden)[at_inat]
  shown <- atlas_cells_now_true(status$mo$shown)[at_mo]
  cbind(
    a = keys %in% listed,
    b = inat & (is.na(at_inat) | hidden %in% TRUE),
    c = mo & (is.na(at_mo) | !(shown %in% TRUE)),
    d = mo & keys %in% atlas_record_key(ATLAS_MO_SOURCE, as.character(status$deleted))
  )
}

#' Whether each of a pull's iNaturalist and MO records has a cached answer now.
atlas_cells_now_answered <- function(pull, status) {
  keys <- atlas_record_key(pull$source, pull$observation_id)
  keys %in% c(atlas_record_key(ATLAS_INAT_SOURCE, status$inat$number),
              atlas_record_key(ATLAS_MO_SOURCE, status$mo$number))
}

#' The text of a gzipped file, as bytes.
atlas_gz_bytes <- function(path) {
  con <- gzfile(path, open = "rb")
  on.exit(close(con), add = TRUE)
  out <- raw()
  repeat {
    chunk <- readBin(con, "raw", n = 1048576L)
    if (!length(chunk)) break
    out <- c(out, chunk)
  }
  out
}

#' Make the cells again as the sources stand now.
#'
#' pull is the release's pull, listed its privacy list (record keys),
#' release_cells the path of the release's own cells file, status what
#' atlas_cells_now_status returned. Stops, writing nothing, unless the pull
#' with group (a) alone gives exactly the release's cells.
atlas_cells_now <- function(pull, listed, release_cells, status, release = NULL) {
  if (!file.exists(release_cells)) stop("the release's cells file is not here: ", release_cells, call. = FALSE)
  groups <- atlas_cells_now_groups(pull, listed, status)
  keys <- atlas_record_key(pull$source, pull$observation_id)

  check <- tempfile(fileext = ".tsv.gz")
  on.exit(unlink(check), add = TRUE)
  atlas_write_tsv_gz(atlas_public_cells_table(pull, hidden = keys[groups[, "a"]]), check)
  same <- identical(atlas_gz_bytes(check), atlas_gz_bytes(release_cells))
  if (!same) {
    stop("the pull less its own list does not give the release's cells; nothing written", call. = FALSE)
  }

  out <- rowSums(groups) > 0
  answered <- atlas_cells_now_answered(pull, status)
  unanswered <- c(
    iNaturalist = mean(!answered[pull$source == ATLAS_INAT_SOURCE]),
    `Mushroom Observer` = mean(!answered[pull$source == ATLAS_MO_SOURCE])
  )
  unanswered[is.nan(unanswered)] <- 0
  if (any(unanswered > ATLAS_CELLS_NOW_MAX_UNANSWERED)) {
    stop(sprintf("the status answer looks incomplete: no cached answer now for %s of the pull's records; nothing written",
                 paste(sprintf("%.1f per cent of %s", 100 * unanswered, names(unanswered)), collapse = " and ")),
         call. = FALSE)
  }
  beyond <- sum(out & !groups[, "a"])
  if (beyond > ATLAS_CELLS_NOW_MAX_BEYOND * nrow(pull)) {
    stop(sprintf("%d records would leave beyond the list, more than %.0f per cent of the pull; nothing written",
                 beyond, 100 * ATLAS_CELLS_NOW_MAX_BEYOND), call. = FALSE)
  }
  cells <- atlas_public_cells_table(pull, hidden = keys[out])
  earlier <- rep(FALSE, nrow(pull))
  by_group <- list()
  for (g in colnames(groups)) {
    by_group[[g]] <- list(
      group = unname(ATLAS_CELLS_NOW_GROUPS[[g]]),
      records = sum(groups[, g]),
      not_in_an_earlier_group = sum(groups[, g] & !earlier)
    )
    earlier <- earlier | groups[, g]
  }
  list(
    cells = cells,
    summary = list(
      release = release,
      checked_at = status$checked_at,
      checked_on = substr(status$checked_at, 1L, 10L),
      pull = list(records = nrow(pull)),
      release_cells = list(sha256 = atlas_sha256(release_cells), records = sum(!groups[, "a"])),
      list_alone_gives_the_release_cells = same,
      list_alone_gives_the_same_gzip = identical(atlas_sha256(check), atlas_sha256(release_cells)),
      groups = by_group,
      left_out = sum(out),
      left_out_beyond_the_list = sum(out & !groups[, "a"]),
      by_source_beyond_the_list = as.list(table(pull$source[out & !groups[, "a"]])),
      cells_now = list(records = sum(!out), taxa = length(unique(cells$taxon)), cells = nrow(cells))
    )
  )
}

#' Write the cells and their summary into dir.
atlas_write_cells_now <- function(result, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(dir, ATLAS_CELLS_NOW_FILE)
  atlas_write_tsv_gz(result$cells, path)
  summary <- result$summary
  summary$cells_now$file <- ATLAS_CELLS_NOW_FILE
  summary$cells_now$sha256 <- atlas_sha256(path)
  atlas_write_json(summary, file.path(dir, ATLAS_CELLS_NOW_SUMMARY))
  invisible(summary)
}

#' Make the current release's cells as the sources stand now, on the machine
#' that holds its pull, and write them into dir.
atlas_cells_now_run <- function(dir, store = atlas_store(), grid = "draft", run = atlas_run_sql,
                                host = atlas_sql_host()) {
  manifest <- atlas_current_release(store, grid)
  if (is.null(manifest)) stop("nothing has been published for the ", grid, " grid", call. = FALSE)
  entry <- Filter(function(f) identical(f$path, "public/cells.tsv.gz"), manifest$files)
  if (!length(entry)) stop("release ", manifest$id, " has no cells file", call. = FALSE)
  release_cells <- atlas_public_cells_path()
  if (!file.exists(release_cells) || !identical(atlas_sha256(release_cells), entry[[1]]$sha256)) {
    stop("this machine's cells file is not release ", manifest$id, "'s", call. = FALSE)
  }
  listed <- atlas_read_privacy()
  if (is.null(listed)) stop("no privacy list on this machine", call. = FALSE)
  # The release's own pull, not whatever was pulled since: a later pull or a
  # rewrite of this one would fail the check below and write nothing.
  pull_file <- manifest$pull$file
  if (is.null(pull_file) || !file.exists(atlas_path("occurrences", pull_file))) {
    stop("this machine does not hold release ", manifest$id, "'s pull", call. = FALSE)
  }
  result <- atlas_cells_now(atlas_read_occurrences(atlas_path("occurrences", pull_file)), listed, release_cells,
                            atlas_cells_now_status(run, host), release = manifest$id)
  atlas_write_cells_now(result, dir)
}

#' Read cells made by atlas_cells_now_run, checked against their summary and
#' the release they were made for.
atlas_read_cells_now <- function(dir, manifest) {
  summary_path <- file.path(dir, ATLAS_CELLS_NOW_SUMMARY)
  if (!file.exists(summary_path)) stop("no ", ATLAS_CELLS_NOW_SUMMARY, " in ", dir, call. = FALSE)
  summary <- jsonlite::fromJSON(summary_path, simplifyVector = FALSE)
  path <- file.path(dir, summary$cells_now$file %||% ATLAS_CELLS_NOW_FILE)
  if (!identical(summary$release, manifest$id)) {
    stop("the cells were made for release ", summary$release %||% "?", ", not ", manifest$id, call. = FALSE)
  }
  if (!isTRUE(summary$list_alone_gives_the_release_cells)) {
    stop("the cells' own check did not pass", call. = FALSE)
  }
  entry <- Filter(function(f) identical(f$path, "public/cells.tsv.gz"), manifest$files)
  if (!length(entry) || !identical(summary$release_cells$sha256, entry[[1]]$sha256)) {
    stop("the cells were checked against another cells file than the release's", call. = FALSE)
  }
  if (!file.exists(path) || !identical(atlas_sha256(path), summary$cells_now$sha256)) {
    stop("the cells file does not match its summary", call. = FALSE)
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", summary$checked_on %||% "")) {
    stop("the cells' summary has no date", call. = FALSE)
  }
  list(path = path, summary = summary)
}
