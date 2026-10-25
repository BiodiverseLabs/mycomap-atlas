# A record's key: its source and its number, together (the independent
# review, 2026-10-25; Steve). Every .org source numbers its records on its
# own, so an MO, MyCoPortal or Sequences record can carry an iNaturalist
# observation's number. Three lookups keyed on the bare number took one
# source's fact for another's record: the "iNat<n>" labels, the first green
# date (46556a9) and the obscured check (85343fc). So no join, lookup, match
# or set operation on records uses the number alone: R code keys records
# with atlas_record_key, and SQL compares a number only beside a source
# condition. tests/testthat/test-record-keys.R holds every builder and every
# R file to it.

#' A record's key, "<source>:<number>", as the privacy list, the exclusion
#' list and the tracker's ledger store it.
atlas_record_key <- function(source, number) {
  paste(source, number, sep = ":")
}
