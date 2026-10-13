# What sequence names change (paper E9): the atlas names a record by its
# approved DNA sequence, not by the name its observer gave it. How different
# would the maps be under the record's own name?
#
# The record-name arm keeps exactly the records of the pull (a record with no
# approved sequence name is already out of it) and relabels each with its
# record name, which the pull keeps beside the DNA name (R/labels.R). The
# same rules then apply as for a pull: only a species-level name can be a
# taxon, and spellings of one taxon are merged (R/names.R). A record whose
# own name is not species level stays in the pull as survey effort, under a
# label no taxon has, so every site keeps its records and effort is
# unchanged; only which taxon a record counts for differs.
#
# Every taxon whose record set differs between the two labellings is fitted
# again under record names (full graded fits, every learner, into a private
# release). Each pair of maps is then compared over the cells both cover:
# Spearman's rank correlation and Schoener's D on suitability normalised to
# sum to one (Warren et al. 2008). Taxa with no counterpart are counted.

# The label of a record whose own name cannot be a taxon: never a candidate,
# and not species level, so no pull rule can take it for one.
ATLAS_E9_NO_TAXON <- "(no-species-level-record-name)"

#' The pull relabelled with each record's own name.
#'
#' occurrences is a pull named by DNA (it has record_name). Rows and every
#' other column are kept; scientific_name becomes the record's own name,
#' merged across spellings as a pull merges them, or ATLAS_E9_NO_TAXON when
#' that name is not species level.
atlas_e9_record_named <- function(occurrences) {
  if (!"record_name" %in% names(occurrences)) {
    stop("the pull keeps no record_name: it is not named by DNA", call. = FALSE)
  }
  out <- occurrences
  own <- trimws(as.character(out$record_name))
  usable <- atlas_species_level(own)
  out$scientific_name <- ifelse(usable, own, ATLAS_E9_NO_TAXON)
  out$original_name <- NULL
  if (any(usable)) {
    merged <- atlas_canonicalise_occurrences(out[usable, , drop = FALSE])
    out$scientific_name[usable] <- merged$scientific_name
    out$original_name <- ifelse(usable, own, NA_character_)
  }
  out
}

#' A record's key in the pull: source and observation.
atlas_e9_keys <- function(occurrences) {
  paste(occurrences$source, occurrences$observation_id, sep = ":")
}

#' How each record's label differs between the two namings: "same",
#' "spelling" (one taxon, another spelling), "species" (another species of
#' the same genus), "genus" (another genus) or "no_taxon" (the record's own
#' name is not species level), by source.
atlas_e9_label_changes <- function(dna, record) {
  stopifnot(nrow(dna) == nrow(record))
  a <- as.character(dna$scientific_name)
  b <- as.character(record$scientific_name)
  genus <- function(x) tolower(sub(" .*$", "", x))
  kind <- ifelse(b == ATLAS_E9_NO_TAXON, "no_taxon",
                 ifelse(a == b, "same",
                        ifelse(atlas_name_key(a) == atlas_name_key(b), "spelling",
                               ifelse(genus(a) == genus(b), "species", "genus"))))
  table <- as.data.frame(table(source = dna$source, change = factor(kind, levels = c(
    "same", "spelling", "species", "genus", "no_taxon"))), stringsAsFactors = FALSE)
  names(table)[names(table) == "Freq"] <- "records"
  list(per_record = kind, by_source = table)
}

#' How the taxa change: for each DNA taxon, the record-name taxa its records
#' go to, and the reverse. split: a DNA taxon whose records go to two or more
#' record-name taxa; merged: a record-name taxon fed by two or more DNA taxa;
#' gained and lost: names only under record names, and only under DNA names.
atlas_e9_taxon_changes <- function(dna, record) {
  a <- as.character(dna$scientific_name)
  b <- as.character(record$scientific_name)
  modelled <- b != ATLAS_E9_NO_TAXON
  forward <- tapply(b[modelled], a[modelled], function(x) length(unique(x)))
  backward <- tapply(a[modelled], b[modelled], function(x) length(unique(x)))
  dna_names <- unique(a)
  record_names <- unique(b[modelled])
  list(
    split = sort(names(forward)[forward > 1L]),
    merged = sort(names(backward)[backward > 1L]),
    gained = sort(setdiff(record_names, dna_names)),
    lost = sort(setdiff(dna_names, record_names)),
    counts = list(dna_taxa = length(dna_names), record_taxa = length(record_names),
                  split = sum(forward > 1L), merged = sum(backward > 1L),
                  gained = length(setdiff(record_names, dna_names)),
                  lost = length(setdiff(dna_names, record_names)))
  )
}

#' The taxa E9 refits: names under both labellings whose record sets
#' differ, with the records each gains and loses under record names.
atlas_e9_changed_taxa <- function(dna, record) {
  keys <- atlas_e9_keys(dna)
  a <- split(keys, as.character(dna$scientific_name))
  b <- split(keys, as.character(record$scientific_name))
  both <- setdiff(intersect(names(a), names(b)), ATLAS_E9_NO_TAXON)
  rows <- lapply(both, function(name) {
    gained <- length(setdiff(b[[name]], a[[name]]))
    lost <- length(setdiff(a[[name]], b[[name]]))
    data.frame(taxon = name, records_dna = length(a[[name]]), records_record = length(b[[name]]),
               gained = gained, lost = lost, changed = gained + lost > 0L, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) {
    out <- data.frame(taxon = character(), records_dna = integer(), records_record = integer(),
                      gained = integer(), lost = integer(), changed = logical(), stringsAsFactors = FALSE)
  }
  out[order(out$taxon), , drop = FALSE]
}

#' Two maps of one taxon compared over the cells both give a value: cells,
#' Spearman's rank correlation, and Schoener's D of the suitabilities each
#' normalised to sum to one. The rasters must share the grid; each is
#' extended to the other's extent, never resampled.
atlas_e9_compare_maps <- function(first, second) {
  extent <- terra::union(terra::ext(first), terra::ext(second))
  a <- terra::extend(first[[1]], extent)
  b <- terra::extend(second[[1]], extent)
  if (!isTRUE(terra::compareGeom(a, b, stopOnError = FALSE))) {
    stop("the two maps are not on one grid", call. = FALSE)
  }
  va <- terra::values(a, mat = FALSE)
  vb <- terra::values(b, mat = FALSE)
  both <- is.finite(va) & is.finite(vb)
  n <- sum(both)
  if (n < 10L) return(list(cells = n, spearman = NA_real_, schoener_d = NA_real_))
  va <- va[both]
  vb <- vb[both]
  rho <- if (stats::sd(va) > 0 && stats::sd(vb) > 0) {
    suppressWarnings(stats::cor(va, vb, method = "spearman"))
  } else {
    NA_real_
  }
  d <- if (sum(va) > 0 && sum(vb) > 0) 1 - 0.5 * sum(abs(va / sum(va) - vb / sum(vb))) else NA_real_
  list(cells = n, spearman = rho, schoener_d = d)
}
