# One taxon, one name.
#
# .org holds the same provisional taxon under several spellings: Mycena sp.
# 'IN10' and Mycena "sp-IN10"; Clitocybe sp. 'fuscidisca PNW10' and
# 'fuscidisca-PNW10'; curly quotes and straight; a trailing non-breaking
# space. Modelled as written, each spelling is its own taxon: the records are
# split between them, and where two spellings clear the threshold they share
# a file name and one map overwrites the other.
#
# So names are merged when they differ only in punctuation — quote marks,
# spaces, "sp-X" against sp. 'X', a doubled or missing quote, a space or a
# hyphen inside a code, letter case — and modelled under the spelling most of
# the records use. Letters and digits are never touched: 'IN1' and 'IN01'
# stay apart, and so do accented names. Every record keeps its original
# spelling, and the merges are reported so the names can be fixed on .org.
# (Steve, 2026-09-29.)

# Characters that stand for a quote mark: straight and curly, single and
# double, primes and backticks.
ATLAS_QUOTE_CHARS <- paste0("[", intToUtf8(c(0x2018, 0x2019, 0x201a, 0x201b, 0x2032, 0x00b4, 0x60,
                                                0x201c, 0x201d, 0x201e, 0x2033, 0x22)), "]")

# Spaces that are not plain spaces.
ATLAS_ODD_SPACES <- paste0("[", intToUtf8(c(0xa0, 0x2000:0x200b, 0x202f, 0x205f, 0x3000)), "]")

#' A name with its punctuation made regular, still readable.
atlas_regular_name <- function(names) {
  x <- enc2utf8(as.character(names))
  x <- gsub(ATLAS_ODD_SPACES, " ", x)
  x <- gsub(ATLAS_QUOTE_CHARS, "'", x)
  x <- gsub("'{2,}", "'", x)
  x <- gsub("[[:space:]]+", " ", trimws(x))
  # Genus 'sp-CODE' or Genus sp-CODE as Genus sp. 'CODE'
  x <- gsub(" '?sp[-. ]+([^' ]+)'?$", " sp. '\\1'", x)
  # A code with an opening quote but no closing one.
  x <- sub("( sp[.] '[^']*)$", "\\1'", x)
  x
}

#' The key two spellings of one taxon share: punctuation made regular, the
#' separators inside a provisional code made the same, case ignored.
atlas_name_key <- function(names) {
  x <- atlas_regular_name(names)
  quoted <- grepl(" sp[.] '[^']*'$", x)
  code <- sub("^.* sp[.] '([^']*)'$", "\\1", x[quoted])
  x[quoted] <- paste0(sub(" sp[.] '[^']*'$", "", x[quoted]), " sp. '",
                      gsub("[ _-]+", "-", code), "'")
  tolower(x)
}

#' For each distinct spelling, the name its taxon is modelled under: the
#' spelling most records use, and alphabetically first on a tie.
atlas_canonical_names <- function(names) {
  counts <- table(as.character(names))
  spellings <- names(counts)
  keys <- atlas_name_key(spellings)
  chosen <- vapply(split(seq_along(spellings), keys), function(i) {
    i <- i[order(-as.integer(counts[i]), spellings[i])]
    spellings[[i[[1]]]]
  }, character(1))
  stats::setNames(unname(chosen[keys]), spellings)
}

#' Records with each name replaced by its taxon's name, the original kept.
#' Applying it twice changes nothing.
atlas_canonicalise_occurrences <- function(occurrences) {
  if (!nrow(occurrences)) return(occurrences)
  original <- if ("original_name" %in% names(occurrences)) {
    occurrences$original_name
  } else {
    occurrences$scientific_name
  }
  canonical <- atlas_canonical_names(original)
  occurrences$original_name <- original
  occurrences$scientific_name <- unname(canonical[original])
  occurrences
}

#' Every merge made: one row per spelling that was folded into another name.
atlas_name_merges <- function(occurrences) {
  empty <- data.frame(taxon = character(), spelling = character(), records = integer(),
                      stringsAsFactors = FALSE)
  if (!nrow(occurrences) || !"original_name" %in% names(occurrences)) return(empty)
  pairs <- occurrences[occurrences$original_name != occurrences$scientific_name,
                       c("scientific_name", "original_name"), drop = FALSE]
  if (!nrow(pairs)) return(empty)
  counts <- stats::aggregate(list(records = rep(1L, nrow(pairs))),
                             by = list(taxon = pairs$scientific_name, spelling = pairs$original_name),
                             FUN = sum)
  counts <- counts[order(counts$taxon, -counts$records), , drop = FALSE]
  rownames(counts) <- NULL
  counts
}

#' Where the merge report is written; releases carry it.
atlas_name_merges_path <- function() {
  atlas_path("occurrences", "name-merges.json")
}

#' Rebuild the per-taxon counts and the merge report from this machine's pull.
atlas_refresh_names <- function(quiet = FALSE) {
  occurrences <- atlas_read_occurrences()
  merges <- atlas_name_merges(occurrences)
  atlas_write_json(atlas_taxon_fingerprints(occurrences),
                   atlas_path("occurrences", "taxa-latest.json", create = TRUE))
  atlas_write_json(merges, atlas_name_merges_path())
  if (!isTRUE(quiet)) {
    message(length(unique(merges$taxon)), " taxa gathered ", nrow(merges), " other spellings (",
            sum(merges$records), " records); report: ", atlas_name_merges_path())
  }
  invisible(merges)
}
