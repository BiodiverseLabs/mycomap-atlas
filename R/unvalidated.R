# Sequenced but not yet validated: per taxon, how many of mycomap.org's
# sequenced records no validation project has given a verdict yet (Steve,
# 2026-10-07). Shown on the taxon page beside the validated count, so a taxon
# whose records are waiting for review is not mistaken for a rare one.
#
# Counted at pull time, beside the pull and outside it: these records are never
# modelled, and the counts are not part of the record set, its fingerprint or
# any fit setting, so a count that moves every night never makes a model stale.

#' Where the pull keeps the raw counts, one row per spelling .org uses.
atlas_unvalidated_raw_path <- function() {
  atlas_path("occurrences", "unvalidated-latest.tsv.gz")
}

#' The count file a release carries: one row per taxon with any.
atlas_public_unvalidated_path <- function() {
  atlas_path("public", "unvalidated.tsv.gz")
}

#' Run the count query and keep its raw rows for the release to fold.
atlas_pull_unvalidated <- function(host = atlas_sql_host(), quiet = FALSE) {
  raw <- atlas_parse_tsv(atlas_run_sql(atlas_unvalidated_sql(), host = host))
  if (!nrow(raw)) {
    raw <- data.frame(taxon = character(), not_yet_validated = character(),
                      with_coordinates = character(), stringsAsFactors = FALSE)
  }
  missing <- setdiff(c("taxon", "not_yet_validated", "with_coordinates"), names(raw))
  if (length(missing)) stop("count query is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  atlas_write_tsv_gz(raw, atlas_unvalidated_raw_path())
  if (!isTRUE(quiet)) {
    message(sprintf("not yet validated: %d records under %d spellings",
                    sum(as.integer(raw$not_yet_validated)), nrow(raw)))
  }
  invisible(raw)
}

#' Fold the raw rows into the taxa the pull models, matching spellings by
#' atlas_name_key rather than exact name, since records waiting for review can
#' be spelled differently from the validated ones. taxa is the pull's
#' canonical names. Spellings of no taxon in the pull are dropped: they have no
#' page to show a count on.
atlas_unvalidated_table <- function(raw, taxa) {
  empty <- data.frame(taxon = character(), not_yet_validated = integer(),
                      with_coordinates = integer(), stringsAsFactors = FALSE)
  if (is.null(raw) || !nrow(raw) || !length(taxa)) return(empty)
  keys <- atlas_name_key(raw$taxon)
  sums <- stats::aggregate(
    list(not_yet_validated = as.integer(raw$not_yet_validated),
         with_coordinates = as.integer(raw$with_coordinates)),
    by = list(key = keys), FUN = sum
  )
  taxa <- unique(as.character(taxa))
  canonical <- stats::setNames(taxa, atlas_name_key(taxa))
  sums <- sums[sums$key %in% names(canonical) & sums$not_yet_validated > 0, , drop = FALSE]
  if (!nrow(sums)) return(empty)
  out <- data.frame(taxon = unname(canonical[sums$key]),
                    not_yet_validated = as.integer(sums$not_yet_validated),
                    with_coordinates = as.integer(sums$with_coordinates),
                    stringsAsFactors = FALSE)
  out <- out[order(out$taxon), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The published count table, or NULL when this machine has none.
atlas_read_public_unvalidated <- function() {
  path <- atlas_public_unvalidated_path()
  if (!file.exists(path)) return(NULL)
  utils::read.delim(gzfile(path, encoding = "UTF-8"), sep = "\t", quote = "", comment.char = "",
                    colClasses = c("character", "integer", "integer"),
                    na.strings = character(0), check.names = FALSE, stringsAsFactors = FALSE,
                    encoding = "UTF-8")
}

#' One taxon's count: 0 when the table has no row for it, NULL when there is
#' no table at all (counts not taken yet), so the page can tell the two apart.
atlas_unvalidated_for <- function(table, name) {
  if (is.null(table)) return(NULL)
  hit <- table$not_yet_validated[table$taxon == name]
  if (length(hit)) as.integer(hit[[1]]) else 0L
}
