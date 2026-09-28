# mycomap.org is read through its forced read-only route, which takes a single
# statement as one command-line argument:
#
#   ssh mycomap-sql "select ..."
#
# That string has to survive both a Windows command line and a POSIX shell, so
# statements are kept on one line and three characters are refused outright
# rather than escaped. Queries use strpos()/right() instead of LIKE so no
# percent sign ever appears.

#' Collapse a statement onto a single line.
atlas_one_line <- function(sql) {
  trimws(gsub(" +", " ", gsub("[\r\n\t]+", " ", sql)))
}

#' Refuse any statement that cannot survive the trip to the SQL route.
atlas_assert_transport_safe <- function(sql) {
  if (grepl('"', sql, fixed = TRUE)) {
    stop("SQL must not contain a double quote", call. = FALSE)
  }
  if (grepl("%", sql, fixed = TRUE)) {
    stop("SQL must not contain a percent sign; use strpos() or right() instead of LIKE",
         call. = FALSE)
  }
  if (grepl("[\r\n]", sql)) {
    stop("SQL must be a single line", call. = FALSE)
  }
  invisible(TRUE)
}

#' Run one read-only statement and return its raw answer.
atlas_run_sql <- function(sql, host = atlas_sql_host()) {
  sql <- atlas_one_line(sql)
  atlas_assert_transport_safe(sql)
  answer <- suppressWarnings(
    system2("ssh", c(host, shQuote(sql)), stdout = TRUE, stderr = TRUE)
  )
  status <- attr(answer, "status")
  if (!is.null(status) && status != 0) {
    stop("read-only SQL route failed (exit ", status, "): ",
         paste(utils::head(answer, 5L), collapse = " | "), call. = FALSE)
  }
  paste(answer, collapse = "\n")
}
