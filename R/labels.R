# The name a record is modelled under: the DNA's, not the record's.
#
# A green record's name on .org is the .com record name, and that name is
# often never updated after the sequence is named: a record still called
# Tubaria sp. 'IN01' whose approved sequences say Tubaria hiemalis, a
# "Polyporales" record with Trametes gibbosa sequences. MycoMap Vision trained
# and benchmarked on the record name and had to rebuild its answer key from the
# sequences (2026-10-08). Of 158,581 green North American records with
# coordinates on 2026-10-08, the record name was another species or genus
# than the DNA's for 4,878 (3.1%), 2,426 had approved sequences that disagree,
# and 89 taxa reach ten records only under the DNA name, Tubaria hiemalis
# (187) the largest.
#
# So a record takes the single name of its approved, named sequences, after
# spelling differences (R/names.R atlas_name_key). Two different names, or a
# one-word sequence name, leave the record out: the DNA does not settle which
# species it is. A record with no approved named sequence that .org can link
# keeps its record name or is left out, as ATLAS_NO_SEQUENCE_NAME says; most
# such records are Mushroom Observer, MyCoPortal and GenBank records whose
# sequences .org cannot yet join to them, not records without DNA.

# What a record with no approved named sequence .org can link does: keep its
# record name ("keep") or leave the pull ("drop").
ATLAS_NO_SEQUENCE_NAME <- "keep"

# The linked_observations database that holds iNaturalist observations.
ATLAS_LINKED_INAT_DATABASE <- 43L

# How a .org source is written in a sequence's observation key ("inat:123").
ATLAS_SEQUENCE_KEY_PREFIXES <- c(
  "iNaturalist" = "inat", "MO Observations" = "mo", "MycoPortal" = "mp",
  "MyCoPortal" = "mp", "Sequences" = "seq", "GenBank Accessions" = "gb"
)

ATLAS_LABEL_SAME <- "sequence name is the record name"
ATLAS_LABEL_SPELLING <- "record name differs in writing only"
ATLAS_LABEL_RECORD_GENUS <- "record name is one word, the sequence names a species"
ATLAS_LABEL_OTHER_SPECIES <- "record name is another species of the genus"
ATLAS_LABEL_OTHER_GENUS <- "record name is in another genus"
ATLAS_LABEL_SEQUENCE_GENUS <- "sequence name is one word (left out)"
ATLAS_LABEL_DISAGREE <- "sequences disagree (left out)"
ATLAS_LABEL_NONE <- "no approved named sequence"
ATLAS_LABEL_STATUSES <- c(
  ATLAS_LABEL_SAME, ATLAS_LABEL_SPELLING, ATLAS_LABEL_RECORD_GENUS,
  ATLAS_LABEL_OTHER_SPECIES, ATLAS_LABEL_OTHER_GENUS, ATLAS_LABEL_SEQUENCE_GENUS,
  ATLAS_LABEL_DISAGREE, ATLAS_LABEL_NONE
)

#' A sequence's observation key for the record o, as SQL.
atlas_sequence_key_sql <- function() {
  arms <- paste(sprintf("WHEN '%s' THEN '%s'", names(ATLAS_SEQUENCE_KEY_PREFIXES),
                        ATLAS_SEQUENCE_KEY_PREFIXES), collapse = " ")
  sprintf("(CASE o.source %s END || ':' || o.observation_id)", arms)
}

#' The approved, named sequences of the green records with ids first_id to
#' last_id: one row per record and name. A sequence is the record's when its
#' observation key names the record, or, for an iNaturalist record, when it
#' hangs off a .com record linked to the observation (the join Vision's answer
#' key uses; the key alone misses about one iNat record in five hundred).
atlas_sequence_names_sql <- function(first_id, last_id) {
  stopifnot(length(first_id) == 1, is.numeric(first_id), length(last_id) == 1,
            is.numeric(last_id), first_id <= last_id)
  statuses <- paste(
    "coalesce(o.validation_status_1, '')",
    "coalesce(o.validation_status_2, '')",
    "coalesce(o.validation_status_3, '')",
    sep = ", "
  )
  where <- sprintf(
    "o.id >= %d AND o.id <= %d AND 'yes' IN (%s) AND s.approved = 1 AND btrim(coalesce(s.species_name, '')) <> ''",
    as.integer(first_id), as.integer(last_id), statuses
  )
  sql <- sprintf(
    "SELECT o.id, s.species_name FROM observations o
     JOIN sequences s ON s.observation = %s
     WHERE %s
     UNION
     SELECT o.id, s.species_name FROM observations o
     JOIN linked_observations l ON l.database_id = %d AND l.external_id = o.observation_id
     JOIN sequences s ON s.com_inat_record_id = l.record_id
     WHERE o.source = 'iNaturalist' AND %s",
    atlas_sequence_key_sql(), where, ATLAS_LINKED_INAT_DATABASE, where
  )
  atlas_one_line(sql)
}

#' Is a name one Atlas can model: a species-level name, provisional temp codes
#' included, not a placeholder or a bare "Genus sp."?
atlas_species_level <- function(names) {
  x <- trimws(as.character(names))
  ok <- !is.na(x) & nzchar(x) & !(x %in% c("Fungi", "Unknown"))
  ok & grepl(" ", x, fixed = TRUE) & !grepl(" sp[.]?$", tolower(x))
}

#' The DNA name of each record and how it relates to the record name.
#'
#' record_names: one per record. sequence_names: a list, one character vector
#' per record, of its approved sequences' names (empty when none). Returns a
#' data frame with name (NA when the record is left out) and status (one of
#' ATLAS_LABEL_STATUSES).
atlas_dna_names <- function(record_names, sequence_names,
                            no_sequence = ATLAS_NO_SEQUENCE_NAME) {
  no_sequence <- match.arg(no_sequence, c("keep", "drop"))
  stopifnot(length(record_names) == length(sequence_names))
  one <- function(record, seqs) {
    seqs <- trimws(as.character(seqs))
    seqs <- sort(unique(seqs[!is.na(seqs) & nzchar(seqs)]))
    if (!length(seqs)) {
      return(c(if (identical(no_sequence, "keep")) record else NA_character_, ATLAS_LABEL_NONE))
    }
    if (length(unique(atlas_name_key(seqs))) > 1L) return(c(NA_character_, ATLAS_LABEL_DISAGREE))
    record <- trimws(as.character(record))
    # The record's spelling when a sequence uses it; R/names.R later models
    # every spelling of a taxon under the one most records use.
    name <- if (!is.na(record) && record %in% seqs) record else seqs[[1]]
    if (!grepl(" ", name, fixed = TRUE)) return(c(NA_character_, ATLAS_LABEL_SEQUENCE_GENUS))
    status <- if (is.na(record) || !nzchar(record) || !grepl(" ", record, fixed = TRUE)) {
      ATLAS_LABEL_RECORD_GENUS
    } else if (identical(record, name)) {
      ATLAS_LABEL_SAME
    } else if (identical(atlas_name_key(record), atlas_name_key(name))) {
      ATLAS_LABEL_SPELLING
    } else if (!identical(tolower(sub(" .*$", "", record)), tolower(sub(" .*$", "", name)))) {
      ATLAS_LABEL_OTHER_GENUS
    } else {
      ATLAS_LABEL_OTHER_SPECIES
    }
    c(name, status)
  }
  out <- mapply(one, as.character(record_names), sequence_names, USE.NAMES = FALSE)
  if (!length(record_names)) return(data.frame(name = character(), status = character()))
  data.frame(name = out[1, ], status = out[2, ], stringsAsFactors = FALSE)
}

#' A page of the pull named by its DNA: scientific_name becomes the DNA name,
#' record_name keeps .org's, and name_status says how they relate. A record
#' the DNA does not name gets no scientific_name, and the pull leaves it out
#' (atlas_species_level). names: the answer of
#' atlas_sequence_names_sql (columns id, species_name).
atlas_label_occurrences <- function(page, names, no_sequence = ATLAS_NO_SEQUENCE_NAME) {
  if (!nrow(page)) {
    page$record_name <- character()
    page$name_status <- character()
    return(page)
  }
  by_id <- if (nrow(names)) split(names$species_name, names$id) else list()
  seqs <- lapply(as.character(page$id), function(id) by_id[[id]] %||% character())
  labels <- atlas_dna_names(page$scientific_name, seqs, no_sequence = no_sequence)
  page$record_name <- page$scientific_name
  page$scientific_name <- labels$name
  page$name_status <- labels$status
  page
}

#' How the pull's names came out: records per status and source, and the
#' commonest record-name to DNA-name changes. Names only, no coordinates.
atlas_label_audit <- function(labelled, top = 50L) {
  status <- factor(labelled$name_status, levels = ATLAS_LABEL_STATUSES)
  by_status <- as.data.frame(table(status = status), stringsAsFactors = FALSE)
  names(by_status)[2] <- "records"
  by_source <- as.data.frame(table(status = status, source = labelled$source),
                             stringsAsFactors = FALSE)
  names(by_source)[3] <- "records"
  by_source <- by_source[by_source$records > 0, , drop = FALSE]
  moved <- labelled[labelled$name_status %in% c(ATLAS_LABEL_OTHER_SPECIES, ATLAS_LABEL_OTHER_GENUS),
                    c("record_name", "scientific_name"), drop = FALSE]
  changes <- if (nrow(moved)) {
    counts <- stats::aggregate(list(records = rep(1L, nrow(moved))),
                               by = list(record_name = moved$record_name,
                                         dna_name = moved$scientific_name), FUN = sum)
    utils::head(counts[order(-counts$records, counts$record_name), , drop = FALSE], top)
  } else {
    data.frame(record_name = character(), dna_name = character(), records = integer())
  }
  rownames(changes) <- NULL
  list(
    rule = paste("a record is named by the single name of its approved .com sequences;",
                 "disagreeing or one-word sequence names leave it out; with none it",
                 sprintf("is %s", if (identical(ATLAS_NO_SEQUENCE_NAME, "keep")) "kept under its record name" else "left out")),
    pulled = nrow(labelled),
    modelled = sum(atlas_species_level(labelled$scientific_name)),
    by_status = by_status,
    by_source = by_source,
    changes = changes
  )
}

#' Where the audit of the last pull's names is written.
atlas_label_audit_path <- function() {
  atlas_path("occurrences", "labels-latest.json")
}
