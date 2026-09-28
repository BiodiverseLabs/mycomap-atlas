# The read-only route answers with a header row and tab-separated values, and
# prints an empty string for NULL. Only tab-safe columns are ever selected —
# no free text such as notes or place names — so nothing needs quoting.

#' Parse a tab-separated answer into a character data frame.
atlas_parse_tsv <- function(text) {
  if (!nzchar(trimws(text))) {
    return(data.frame())
  }
  con <- textConnection(text)
  on.exit(close(con), add = TRUE)
  utils::read.delim(
    con,
    sep = "\t",
    quote = "",
    comment.char = "",
    na.strings = "",
    colClasses = "character",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}
