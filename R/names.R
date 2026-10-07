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
# hyphen inside a code, letter case — or in an author citation, and modelled
# under the spelling most of the records use. Letters and digits are never touched: 'IN1' and 'IN01'
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

# Words that introduce an infraspecific epithet, each with the one spelling
# it is compared under: "Amanita muscaria ssp. flavivolvata" and "Amanita
# muscaria subsp. flavivolvata" are one taxon. Only spellings of the same rank
# are joined; a variety and a subspecies of one epithet stay apart.
ATLAS_RANK_SPELLINGS <- c(
  "subsp." = "subsp.", "subsp" = "subsp.", "ssp." = "subsp.", "ssp" = "subsp.",
  "var." = "var.", "var" = "var.",
  "f." = "f.", "fo." = "f.", "fo" = "f.", "forma" = "f."
)
ATLAS_NAME_RANKS <- names(ATLAS_RANK_SPELLINGS)

#' A name with each rank word spelled one way. Only a word between epithets
#' counts: the third word on, followed by another word, and never inside a
#' quoted provisional code. Rank words are lower case; a capital "F." is an
#' author's initial.
atlas_regular_ranks <- function(names) {
  vapply(names, function(name) {
    words <- strsplit(name, " ", fixed = TRUE)[[1]]
    if (length(words) < 4L) return(name)
    for (i in 3:(length(words) - 1L)) {
      if (grepl("'", words[[i]], fixed = TRUE)) break
      spelling <- ATLAS_RANK_SPELLINGS[words[[i]]]
      if (!is.na(spelling)) words[[i]] <- unname(spelling)
    }
    paste(words, collapse = " ")
  }, character(1), USE.NAMES = FALSE)
}

#' A name without its author citation: the genus, the species epithet, and
#' any rank and infraspecific epithet, stopping at the first word that is not
#' part of the name — a bracket, a capital, an ampersand or "ex".
#' "Pluteus chrysophaeus (Schaeff. ex Lasch) Quel." is Pluteus chrysophaeus.
#' A provisional name keeps its quoted code whole, brackets and all.
#'
#' Only a plain binomial is trimmed. A name with a digit anywhere is left
#' alone: "Cuphophyllus pratensis PNW06" is a lineage code, not an author, and
#' merging it into Cuphophyllus pratensis would join two taxa. So is a name
#' whose second word is not a species epithet, such as "Entoloma subg.
#' Pouzarella".
atlas_strip_authors <- function(names) {
  vapply(names, function(name) {
    if (grepl(" sp[.] '", name) || grepl("[0-9]", name)) return(name)
    words <- strsplit(name, " ", fixed = TRUE)[[1]]
    if (length(words) < 3L || !grepl("^[[:lower:]][[:lower:]-]*$", words[[2]])) return(name)
    keep <- 2L
    i <- 3L
    while (i <= length(words)) {
      word <- words[[i]]
      if (word %in% ATLAS_NAME_RANKS && i < length(words)) {
        keep <- i + 1L
        i <- i + 2L
      } else if (grepl("^[[:lower:]][[:lower:]-]*$", word) && !word %in% c("ex", "et", "al.", "in")) {
        keep <- i
        i <- i + 1L
      } else if (identical(word, intToUtf8(0xd7))) {
        # A hybrid sign joins two epithets.
        keep <- i
        i <- i + 1L
      } else {
        break
      }
    }
    paste(words[seq_len(keep)], collapse = " ")
  }, character(1), USE.NAMES = FALSE)
}

#' The key two spellings of one taxon share: punctuation made regular, author
#' citations dropped, rank words spelled one way, the separators inside a
#' provisional code made the same, case ignored.
atlas_name_key <- function(names) {
  x <- atlas_regular_ranks(atlas_strip_authors(atlas_regular_name(names)))
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

# ---- renames across pulls -------------------------------------------------------
#
# A provisional name is renamed on .org when its lineage gets a formal name or
# a new code. A taxon page, a citation or a link made under the old name would
# then find nothing. So each full pull compares its records with the previous
# pull's, by record id: a name that is gone, and more than half of whose
# records now sit under one other name, was renamed to it. The renames
# accumulate in occurrences/renames.json, which releases carry, and an old
# name is followed through them to the name its records have now.

#' Where the renames found so far are kept; releases carry it.
atlas_renames_path <- function() {
  atlas_path("occurrences", "renames.json")
}

#' Names in `previous` that are gone from `current` and whose records mostly
#' moved to one other name: one row each, from, to, records (the old name's
#' records) and moved (how many of them the new name has now). A name whose
#' records were dropped, or split with no majority, is not a rename.
atlas_detect_renames <- function(previous, current) {
  empty <- data.frame(from = character(), to = character(), records = integer(),
                      moved = integer(), stringsAsFactors = FALSE)
  if (is.null(previous) || !nrow(previous) || is.null(current) || !nrow(current)) return(empty)
  gone <- setdiff(unique(previous$scientific_name), unique(current$scientific_name))
  if (!length(gone)) return(empty)
  now <- stats::setNames(current$scientific_name, as.character(current$id))
  rows <- lapply(sort(gone), function(name) {
    ids <- as.character(previous$id[previous$scientific_name == name])
    where <- unname(now[ids])
    where <- where[!is.na(where)]
    if (!length(where)) return(NULL)
    counts <- sort(table(where), decreasing = TRUE)
    if (counts[[1]] * 2 <= length(ids)) return(NULL)
    data.frame(from = name, to = names(counts)[[1]], records = length(ids),
               moved = as.integer(counts[[1]]), stringsAsFactors = FALSE)
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) empty else do.call(rbind, rows)
}

#' The renames known after a pull: the ones known before, the ones just found
#' (a name renamed again keeps only its latest), and none for a name that is
#' current again.
atlas_update_renames <- function(existing, found, current_names, seen = format(Sys.Date())) {
  columns <- c("from", "to", "records", "moved", "seen")
  keep <- function(x) {
    if (is.null(x) || !NROW(x)) return(NULL)
    x <- as.data.frame(x, stringsAsFactors = FALSE)
    if (is.null(x$seen)) x$seen <- seen
    x[, columns, drop = FALSE]
  }
  existing <- keep(existing)
  found <- keep(found)
  if (!is.null(existing) && !is.null(found)) existing <- existing[!existing$from %in% found$from, , drop = FALSE]
  out <- rbind(existing, found)
  if (is.null(out)) {
    return(data.frame(from = character(), to = character(), records = integer(),
                      moved = integer(), seen = character(), stringsAsFactors = FALSE))
  }
  out <- out[!out$from %in% current_names, , drop = FALSE]
  out <- out[order(out$from), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' The renames this machine knows, or none.
atlas_read_renames <- function(path = atlas_renames_path()) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE), error = function(e) NULL)
}

#' Compare a full pull with the one before it and keep what was renamed.
#' Never fails a pull: renames are a convenience for old links.
atlas_record_renames <- function(current, previous = NULL, path = atlas_renames_path(),
                                 quiet = FALSE) {
  tryCatch({
    if (is.null(previous)) previous <- tryCatch(atlas_read_occurrences(), error = function(e) NULL)
    found <- atlas_detect_renames(previous, current)
    updated <- atlas_update_renames(atlas_read_renames(path), found,
                                    unique(current$scientific_name))
    atlas_write_json(updated, path)
    if (!isTRUE(quiet) && nrow(found)) {
      message(nrow(found), " name(s) renamed since the last pull; ", nrow(updated), " known")
    }
    invisible(updated)
  }, error = function(e) {
    if (!isTRUE(quiet)) message("renames not recorded: ", conditionMessage(e))
    invisible(NULL)
  })
}

#' The current name for a name someone asked for: itself when current; the
#' one current name it is a spelling of (punctuation and case only, as
#' merges are made); or where its renames lead. NULL when none applies.
#' Returns name, how ("current", "spelling" or "renamed") and via, the names
#' passed through.
atlas_resolve_name <- function(name, names, renames = NULL, hops = 10L) {
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) return(NULL)
  if (name %in% names) return(list(name = name, how = "current", via = list()))
  spelling <- function(x) {
    key <- tolower(atlas_regular_name(x))
    hit <- names[tolower(atlas_regular_name(names)) == key]
    if (length(hit) == 1L) hit else NULL
  }
  direct <- spelling(name)
  if (!is.null(direct)) return(list(name = direct, how = "spelling", via = list()))
  if (is.null(renames) || !NROW(renames)) return(NULL)
  at <- name
  via <- character()
  for (i in seq_len(hops)) {
    row <- which(renames$from == at)
    if (!length(row)) row <- which(tolower(atlas_regular_name(renames$from)) == tolower(atlas_regular_name(at)))
    if (length(row) != 1L) return(NULL)
    via <- c(via, at)
    at <- renames$to[[row]]
    if (at %in% names) return(list(name = at, how = "renamed", via = as.list(via)))
    current <- spelling(at)
    if (!is.null(current)) return(list(name = current, how = "renamed", via = as.list(c(via, at))))
  }
  NULL
}
