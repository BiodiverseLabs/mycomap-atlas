# The pull's sequence-names query (atlas_sequence_names_sql, R/labels.R) was
# one join on a CASE of o.source, which no index serves; on 2026-10-29 it
# reached atlas_ro's 60 s limit. It is now one join per source. These tests
# hold it to the same answer as the old query, record for record, and check
# that paging the pull by id windows neither drops nor doubles a record at a
# window's edge. Run against a real Postgres when ATLAS_TEST_PSQL names a
# command that reads SQL on stdin and prints rows (see test-source-numbers.R).
# Temporary tables shadow the real ones, so nothing in that database changes.

# The query as it was at bf236cf, kept only to compare against.
sequence_names_sql_bf236cf <- function(first_id, last_id) {
  arms <- paste(sprintf("WHEN '%s' THEN '%s'", names(ATLAS_SEQUENCE_KEY_PREFIXES),
                        ATLAS_SEQUENCE_KEY_PREFIXES), collapse = " ")
  key <- sprintf("(CASE o.source %s END || ':' || o.observation_id)", arms)
  statuses <- paste("coalesce(o.validation_status_1, '')", "coalesce(o.validation_status_2, '')",
                    "coalesce(o.validation_status_3, '')", sep = ", ")
  where <- sprintf(
    paste("o.id >= %d AND o.id <= %d AND 'yes' IN (%s) AND s.approved = 1",
          "AND coalesce(s.category_id, 0) <> %d",
          "AND coalesce(s.flags ->> 'contaminant', '') NOT IN ('true', '1')",
          "AND coalesce(s.flags ->> 'wrong', '') NOT IN ('true', '1')",
          "AND btrim(coalesce(s.species_name, '')) <> ''"),
    as.integer(first_id), as.integer(last_id), statuses, ATLAS_TRASH_SEQUENCE_CATEGORY
  )
  atlas_one_line(sprintf(
    "SELECT o.id, s.species_name FROM observations o
     JOIN sequences s ON s.observation = %s
     WHERE %s
     UNION
     SELECT o.id, s.species_name FROM observations o
     JOIN linked_observations l ON l.database_id = %d AND l.external_id = o.observation_id
     JOIN sequences s ON s.com_inat_record_id = l.record_id
     WHERE o.source = 'iNaturalist' AND %s",
    key, where, ATLAS_LINKED_INAT_DATABASE, where
  ))
}

sequence_names_fixture <- paste(
  "CREATE TEMP TABLE observations (id integer, observation_id text, source text,",
  "  validation_status_1 text, validation_status_2 text, validation_status_3 text);",
  "CREATE TEMP TABLE sequences (observation varchar, com_inat_record_id integer, approved integer,",
  "  category_id integer, flags jsonb, species_name text);",
  "CREATE TEMP TABLE linked_observations (database_id integer, external_id text, record_id bigint);",
  "INSERT INTO observations VALUES",
  # One green record per source, each named by its own key.
  "(1, '100', 'iNaturalist', 'yes', NULL, NULL), (2, '100', 'MO Observations', 'yes', NULL, NULL),",
  "(3, '200', 'MycoPortal', 'yes', NULL, NULL), (4, '201', 'MyCoPortal', 'yes', NULL, NULL),",
  "(5, '300', 'Sequences', 'yes', NULL, NULL), (6, '400', 'GenBank Accessions', 'yes', NULL, NULL),",
  # A blank, a missing and an unknown source: no key, so no name.
  "(7, '500', '', 'yes', NULL, NULL), (8, '501', NULL, 'yes', NULL, NULL),",
  "(9, '502', 'Unknown Source', 'yes', NULL, NULL),",
  # Several sequences, two names, one of them twice.
  "(10, '600', 'iNaturalist', 'yes', NULL, NULL),",
  # Trash, contaminant (true and 1), wrong, unapproved, blank and missing names.
  "(11, '700', 'iNaturalist', 'yes', NULL, NULL), (12, '701', 'iNaturalist', 'yes', NULL, NULL),",
  "(13, '702', 'iNaturalist', 'yes', NULL, NULL), (14, '703', 'iNaturalist', 'yes', NULL, NULL),",
  "(15, '704', 'iNaturalist', 'yes', NULL, NULL), (16, '705', 'iNaturalist', 'yes', NULL, NULL),",
  "(17, '706', 'iNaturalist', 'yes', NULL, NULL),",
  # Named by its key and by a linked .com record; an MO record shares its number.
  "(18, '800', 'iNaturalist', 'yes', NULL, NULL), (19, '800', 'MO Observations', 'yes', NULL, NULL),",
  # Linked, but through another database than iNaturalist's.
  "(20, '801', 'iNaturalist', 'yes', NULL, NULL),",
  # Not green; green on the third status only.
  "(21, '900', 'iNaturalist', 'no', 'no', 'no'), (22, '901', 'iNaturalist', '', NULL, 'yes'),",
  # Flags present but not set; no category and no flags at all.
  "(23, '902', 'iNaturalist', 'yes', NULL, NULL), (24, '903', 'MO Observations', 'yes', NULL, NULL),",
  # MycoPortal and MyCoPortal share the mp prefix, so this one shares record 4's key.
  "(25, '201', 'MycoPortal', 'yes', NULL, NULL),",
  # A number that starts like another record's: its key is inat:1000, not inat:100.
  "(26, '1000', 'iNaturalist', 'yes', NULL, NULL),",
  # Named only through a linked .com record, with no sequence on its key.
  "(27, '802', 'iNaturalist', 'yes', NULL, NULL);",
  "INSERT INTO sequences VALUES",
  "('inat:100', NULL, 1, NULL, NULL, 'Amanita one'), ('mo:100', NULL, 1, NULL, NULL, 'Russula one'),",
  "('mp:200', NULL, 1, NULL, NULL, 'Portal one'), ('mp:201', NULL, 1, NULL, NULL, 'Portal two'),",
  "('seq:300', NULL, 1, NULL, NULL, 'Sequence one'), ('gb:400', NULL, 1, NULL, NULL, 'GenBank one'),",
  "(':500', NULL, 1, NULL, NULL, 'Blank'), (':501', NULL, 1, NULL, NULL, 'Missing'),",
  "('unknown:502', NULL, 1, NULL, NULL, 'Unknown'),",
  "('inat:600', NULL, 1, NULL, NULL, 'Boletus one'), ('inat:600', NULL, 1, NULL, NULL, 'Boletus two'),",
  "('inat:600', NULL, 1, NULL, NULL, 'Boletus one'),",
  "('inat:700', NULL, 1, 169, NULL, 'Trash'),",
  "('inat:701', NULL, 1, NULL, '{\"contaminant\": true}', 'Contaminant'),",
  "('inat:702', NULL, 1, NULL, '{\"contaminant\": \"1\"}', 'Contaminant'),",
  "('inat:703', NULL, 1, NULL, '{\"wrong\": true}', 'Wrong'),",
  "('inat:704', NULL, 0, NULL, NULL, 'Unapproved'), ('inat:705', NULL, 1, NULL, NULL, '  '),",
  "('inat:706', NULL, 1, NULL, NULL, NULL),",
  "('inat:800', NULL, 1, NULL, NULL, 'Linked one'), (NULL, 9001, 1, NULL, NULL, 'Linked one'),",
  "(NULL, 9001, 1, 169, NULL, 'Linked trash'), (NULL, 9002, 1, NULL, NULL, 'Other database'),",
  "(NULL, 9003, 1, NULL, NULL, 'Linked only'),",
  "('inat:900', NULL, 1, NULL, NULL, 'Not green'), ('inat:901', NULL, 1, NULL, NULL, 'Third status'),",
  "('inat:902', NULL, 1, NULL, '{\"contaminant\": false, \"wrong\": \"0\"}', 'Flags unset'),",
  "('mo:903', NULL, 1, NULL, NULL, 'Russula two');",
  "INSERT INTO linked_observations VALUES (43, '800', 9001), (44, '801', 9002), (43, '802', 9003);"
)

# Each window's rows, as "window,id,name", from one psql session.
sequence_names_rows <- function(sqls) {
  queries <- vapply(seq_along(sqls), function(i) {
    sprintf("SELECT %d, q.id, q.species_name FROM (%s) q ORDER BY 2, 3;", i, sqls[[i]])
  }, "")
  sql <- paste("BEGIN;", sequence_names_fixture, paste(queries, collapse = " "), "ROLLBACK;")
  out <- system(Sys.getenv("ATLAS_TEST_PSQL"), input = sql, intern = TRUE)
  out <- out[grepl("^[0-9]+[,\t|][0-9]+[,\t|]", out)]
  parts <- strsplit(out, "[,\t|]")
  data.frame(window = vapply(parts, `[[`, "", 1), id = as.integer(vapply(parts, `[[`, "", 2)),
             species_name = vapply(parts, `[[`, "", 3), stringsAsFactors = FALSE)
}

sequence_names_expected <- data.frame(
  id = c(1L, 2L, 3L, 4L, 5L, 6L, 10L, 10L, 18L, 22L, 23L, 24L, 25L, 27L),
  species_name = c("Amanita one", "Russula one", "Portal one", "Portal two", "Sequence one", "GenBank one",
                   "Boletus one", "Boletus two", "Linked one", "Third status", "Flags unset", "Russula two",
                   "Portal two", "Linked only"),
  stringsAsFactors = FALSE
)

test_that("the per-source query names exactly the records the CASE join named", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  rows <- sequence_names_rows(list(atlas_sequence_names_sql(1, 27), sequence_names_sql_bf236cf(1, 27)))
  new <- rows[rows$window == "1", c("id", "species_name")]
  old <- rows[rows$window == "2", c("id", "species_name")]
  rownames(new) <- NULL
  rownames(old) <- NULL
  expect_identical(new, old)
  # And that answer is the one the rules give, so the comparison is not of two
  # empty answers: every source by its own key, two names for record 10 and
  # one for 18 (key and link agree), 27 by its link alone, none for a blank or unknown source, none
  # from trash, contaminant, wrong, unapproved or unnamed sequences, none
  # linked through another database, and none for the MO record sharing 18's
  # number.
  expect_identical(new, sequence_names_expected)
})

test_that("paging the pull by id windows neither drops nor doubles a record at a window's edge", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  ids <- 1:27
  # Every page size, as the pull pages: each window runs from its first id to
  # its last, inclusive, and the next starts after it.
  windows <- unlist(lapply(1:6, function(size) {
    lapply(split(ids, ceiling(seq_along(ids) / size)), function(w) c(min(w), max(w)))
  }), recursive = FALSE)
  sizes <- unlist(lapply(1:6, function(size) rep(size, ceiling(length(ids) / size))))
  rows <- sequence_names_rows(lapply(windows, function(w) atlas_sequence_names_sql(w[[1]], w[[2]])))
  for (size in 1:6) {
    mine <- rows[rows$window %in% as.character(which(sizes == size)), c("id", "species_name")]
    mine <- mine[order(mine$id, mine$species_name), ]
    rownames(mine) <- NULL
    expect_identical(mine, sequence_names_expected, info = sprintf("pages of %d", size))
  }
  # A window's ends are its own: one id names only that record.
  edge <- sequence_names_rows(list(atlas_sequence_names_sql(10, 10), atlas_sequence_names_sql(11, 17)))
  expect_identical(edge$id[edge$window == "1"], c(10L, 10L))
  expect_length(edge$id[edge$window == "2"], 0L)
})
