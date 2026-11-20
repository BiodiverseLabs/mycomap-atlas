# Where the records go (R/waterfall.R): every step from .org's observations to
# the pull's records, counted, adding up exactly.

waterfall_counts <- function() {
  data.frame(
    source = c("GenBank", "MO Observations", "MyCoPortal", "iNaturalist"),
    observations = c(5, 40, 12, 100),
    dna_validated = c(5, 38, 12, 96),
    with_coordinates = c(4, 37, 12, 95),
    in_north_america = c(4, 36, 11, 90),
    inat_obscured = c(0, 0, 0, 6),
    inat_coarse = c(0, 0, 0, 4),
    stringsAsFactors = FALSE
  )
}

# The pull's rows: GenBank 4, MO 30 (6 lost to its place rules), MyCoPortal 9
# (2 lost), iNaturalist 80; one of them named by a rank word, one a genus, two
# whose sequences disagree.
waterfall_labelled <- function() {
  source <- c(rep("GenBank", 4), rep("MO Observations", 30), rep("MyCoPortal", 9), rep("iNaturalist", 80))
  name <- rep("Amanita muscaria", length(source))
  status <- rep(ATLAS_LABEL_SAME, length(source))
  name[1] <- "Amanita sect. Vaginatae"
  name[2] <- "Mycena"
  name[3:4] <- NA
  status[3:4] <- ATLAS_LABEL_DISAGREE
  data.frame(source = source, scientific_name = name, name_status = status, stringsAsFactors = FALSE)
}

step_of <- function(waterfall, id) Filter(function(s) identical(s$id, id), waterfall$steps)[[1]]

test_that("the waterfall query only reads, counts by source in one id window, and uses the pull's own rules", {
  sql <- atlas_waterfall_sql(100, 200, max_m = 2000)
  expect_silent(atlas_assert_transport_safe(sql))
  expect_true(startsWith(sql, "SELECT "))
  expect_false(grepl("\\b(insert|update|delete|drop|alter|create)\\b", tolower(sql)))
  expect_match(sql, "o.id > 100", fixed = TRUE)
  expect_match(sql, "o.id <= 200", fixed = TRUE)
  expect_false(grepl("o.id <=", atlas_waterfall_sql(200), fixed = TRUE))
  expect_match(sql, "GROUP BY x.source", fixed = TRUE)
  expect_match(sql, "c.positional_accuracy > 2000 OFFSET 0", fixed = TRUE)
  expect_match(sql, "c.coordinates_obscured = true OFFSET 0", fixed = TRUE)
  expect_match(sql, atlas_status_columns(), fixed = TRUE)
  expect_match(sql, sub("^AND ", "", atlas_place_clause()), fixed = TRUE)
  expect_match(atlas_waterfall_sql(0), sprintf("c.positional_accuracy > %d", ATLAS_MAX_ACCURACY_M), fixed = TRUE)
})

test_that("the windows are the pull's pages, the last open when it read to the end", {
  expect_identical(atlas_pull_windows(c(10, 20), TRUE), list(c(0, 10), c(10, 20), c(20, NA)))
  expect_identical(atlas_pull_windows(c(10, 20), FALSE), list(c(0, 10), c(10, 20)))
  expect_identical(atlas_pull_windows(numeric(), TRUE), list(c(0, NA)))
})

test_that("the counts are summed over the windows, source by source", {
  asked <- character()
  testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
    asked <<- c(asked, sql)
    if (grepl("o.id <= 10", sql, fixed = TRUE)) {
      return(paste("source\tobservations\tdna_validated\twith_coordinates\tin_north_america\tinat_obscured\tinat_coarse",
                   "iNaturalist\t10\t9\t9\t8\t1\t1", "MO Observations\t5\t5\t4\t4\t0\t0", sep = "\n"))
    }
    paste("source\tobservations\tdna_validated\twith_coordinates\tin_north_america\tinat_obscured\tinat_coarse",
          "iNaturalist\t3\t3\t3\t3\t0\t1", sep = "\n")
  })
  counts <- atlas_waterfall_counts(atlas_pull_windows(10, TRUE), host = "test")
  expect_length(asked, 2L)
  expect_equal(counts$source, c("MO Observations", "iNaturalist"))
  expect_equal(counts$observations, c(5, 13))
  expect_equal(counts$inat_coarse, c(0, 2))
  testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) "source\tobservations\n")
  expect_error(atlas_waterfall_counts(list(c(0, NA)), host = "test"), NA)
  testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) "source\tobservations\nGenBank\t1")
  expect_error(atlas_waterfall_counts(list(c(0, NA)), host = "test"), "missing columns")
})

test_that("total less every step's removals is used, and each step's parts are what it removed", {
  mo <- list(unknown = "keep", deleted_at_source_uncached = 1L, uncached = 0L, uncached_kept = 3L,
             too_coarse = 5L, complete = TRUE)
  w <- atlas_waterfall(waterfall_counts(), waterfall_labelled(), mo, excluded = 2L, kingdom = 1L, used = 116L,
                       max_m = 2000)
  expect_true(w$adds_up)
  expect_equal(w$total, 157L)
  expect_equal(w$used, 116L)
  expect_equal(w$pulled, nrow(waterfall_labelled()))
  expect_equal(w$max_accuracy_m, 2000)
  ids <- vapply(w$steps, function(s) s$id, "")
  expect_equal(ids, c("dna", "coordinates", "north_america", "obscured", "inat_coarse", "other_coarse", "name",
                      "excluded", "other_kingdom"))
  removed <- vapply(w$steps, function(s) s$removed, 0L)
  expect_equal(unname(removed), c(6L, 3L, 7L, 6L, 4L, 8L, 4L, 2L, 1L))
  expect_equal(w$total - sum(removed), w$used)
  part <- function(step, id) {
    found <- Filter(function(p) identical(p$id, id), step_of(w, step)$parts)
    if (length(found)) found[[1]]$count else NULL
  }
  expect_equal(part("other_coarse", "mo_place_centre"), 5L)
  expect_equal(part("other_coarse", "mo_deleted"), 1L)
  expect_null(part("other_coarse", "mo_unexplained"))
  expect_equal(part("other_coarse", "mycoportal"), 2L)
  expect_equal(part("other_coarse", "sequences"), 0L)
  expect_equal(part("other_coarse", "genbank"), 0L)
  expect_equal(part("name", "disagree"), 2L)
  expect_equal(part("name", "genus_only"), 1L)
  expect_equal(part("name", "rank_above_species"), 1L)
  expect_equal(part("name", "no_named_sequence"), 0L)
  for (s in Filter(function(s) !is.null(s$parts), w$steps)) {
    expect_equal(sum(vapply(s$parts, function(p) p$count, 0L)), s$removed, info = s$id)
  }
  # Counts only: no record's number, name or place anywhere in it.
  text <- as.character(jsonlite::toJSON(w, auto_unbox = TRUE))
  expect_false(grepl("Amanita|Mycena", text))
})

test_that("a record lost with no rule to explain it shows as its own part, and a pull that does not add up says so", {
  counts <- waterfall_counts()
  counts$in_north_america[counts$source == "GenBank"] <- 5
  w <- atlas_waterfall(counts, waterfall_labelled(), list(too_coarse = 6L, deleted_at_source_uncached = 0L),
                       excluded = 0L, kingdom = 0L, used = 119L)
  coarse <- step_of(w, "other_coarse")
  expect_equal(Filter(function(p) identical(p$id, "genbank"), coarse$parts)[[1]]$count, 1L)
  expect_true(w$adds_up)
  counts$in_north_america[counts$source == "GenBank"] <- 4
  counts$in_north_america[counts$source == "iNaturalist"] <- 91
  odd <- atlas_waterfall(counts, waterfall_labelled(), list(too_coarse = 6L), 0L, 0L, used = 119L)
  expect_equal(Filter(function(p) identical(p$id, "inaturalist"), step_of(odd, "other_coarse")$parts)[[1]]$count, 1L)
  expect_true(odd$adds_up)
  expect_false(atlas_waterfall(waterfall_counts(), waterfall_labelled(), list(), 0L, 0L, used = 100L)$adds_up)
  failed <- atlas_waterfall(waterfall_counts(), waterfall_labelled(), list(error = "permission denied"), 0L, 0L, 119L)
  expect_equal(Filter(function(p) identical(p$id, "mo_unexplained"), step_of(failed, "other_coarse")$parts)[[1]]$count, 6L)
  expect_true(failed$adds_up)
  broken <- w
  broken$steps[[6]]$parts[[1]]$count <- 99L
  expect_false(atlas_waterfall_adds_up(broken))
})

test_that("cleaning a pull again moves its waterfall with it", {
  w <- atlas_waterfall(waterfall_counts(), waterfall_labelled(), list(too_coarse = 6L), excluded = 2L, kingdom = 1L,
                       used = 116L)
  again <- atlas_waterfall_recut(w, removed = 3L, used = 113L)
  expect_true(again$adds_up)
  expect_equal(step_of(again, "excluded")$removed, 5L)
  expect_equal(again$used, 113L)
  expect_false(atlas_waterfall_recut(w, removed = 3L, used = 112L)$adds_up)
  expect_null(atlas_waterfall_recut(NULL, 3L, 113L))
})

test_that("a full pull writes its waterfall into its manifest and its release summary, adding up", {
  records <- fake_occurrences()
  text <- function(df) paste(c(paste(names(df), collapse = "\t"), do.call(paste, c(df, sep = "\t"))), collapse = "\n")
  by <- table(records$source)
  waterfall_rows <- paste(
    "source\tobservations\tdna_validated\twith_coordinates\tin_north_america\tinat_obscured\tinat_coarse",
    paste(sprintf("%s\t%d\t%d\t%d\t%d\t0\t0", names(by), as.integer(by) + 2L, as.integer(by) + 1L,
                  as.integer(by), as.integer(by)), collapse = "\n"), sep = "\n")
  pull <- function(...) {
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
      if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
      if (startsWith(sql, "SELECT o.id, s.species_name")) {
        return(text(data.frame(id = records$id, species_name = records$scientific_name)))
      }
      # The pull reads one page, so there are two windows: the page, and the open
      # one above it, which holds nothing.
      if (startsWith(sql, "SELECT x.source,")) {
        return(if (grepl("o.id <=", sql, fixed = TRUE)) waterfall_rows else sub("
.*$", "", waterfall_rows))
      }
      if (grepl("not_yet_validated", sql, fixed = TRUE)) return("name\tnot_yet_validated\n")
      if (grepl("max(id)", sql, fixed = TRUE)) return("top\n1\n")
      if (grepl("AS privacy", sql, fixed = TRUE)) return("source\tobservation_id\tprivacy\n")
      if (grepl("AS too_coarse", sql, fixed = TRUE)) return("deleted_at_source_uncached\tuncached\ttoo_coarse\n0\t0\t0")
      text(records)
    })
    atlas_pull_occurrences(host = "test", quiet = TRUE, ...)
  }
  with_data_dir({
    atlas_name_kingdoms(unique(records$scientific_name), lookup = function(name) "Fungi")
    manifest <- pull()
    w <- manifest$waterfall
    expect_null(w$error)
    expect_true(w$adds_up)
    expect_equal(w$total, nrow(records) + 2L * length(by))
    expect_equal(w$used, manifest$records)
    expect_equal(w$pulled, nrow(records))
    expect_equal(w$pulled_at, manifest$pulled_at)
    expect_equal(w$max_accuracy_m, ATLAS_MAX_ACCURACY_M)
    summary <- atlas_release_pull_summary(manifest)
    expect_identical(summary$waterfall, w)
    expect_null(summary$sql)
    # A pull of changes only says why it has none.
    expect_equal(pull(since = "2026-01-01")$waterfall$skipped, "not a full pull")
  })
})

# Against a real Postgres (ATLAS_TEST_PSQL, as test-privacy.R): the counts the
# query gives, source by source, either psql field separator.
test_that("on Postgres the waterfall query counts each step by source", {
  testthat::skip_if(!nzchar(Sys.getenv("ATLAS_TEST_PSQL")), "set ATLAS_TEST_PSQL to run SQL against Postgres")
  row <- function(id, source, green = TRUE, xy = TRUE, country = "US", state = "NULL") {
    sprintf("(%d, '%d', '%s', %s, %s, %s, NULL, NULL, %s, %s)", id, id, source,
            if (xy) "45" else "NULL", if (xy) "-122" else "NULL", if (green) "'yes'" else "'no'",
            if (is.na(country)) "NULL" else sprintf("'%s'", country), state)
  }
  sql <- paste(
    "BEGIN;",
    "CREATE TEMP TABLE observations (id integer, observation_id text, source text, latitude numeric,",
    "  longitude numeric, validation_status_1 text, validation_status_2 text, validation_status_3 text,",
    "  country text, state text);",
    "CREATE TEMP TABLE observation_cache (source text, source_observation_id text, coordinates_obscured boolean,",
    "  positional_accuracy integer);",
    "INSERT INTO observations VALUES",
    paste(c(
      row(1, "iNaturalist"),                       # kept
      row(2, "iNaturalist"),                       # obscured
      row(3, "iNaturalist"),                       # 3,000 m: over the cutoff
      row(4, "iNaturalist"),                       # 1,500 m: kept at 2 km
      row(5, "iNaturalist", green = FALSE),        # not validated
      row(6, "MO Observations", xy = FALSE),       # no coordinates
      row(7, "MO Observations", country = "FR"),   # outside North America
      row(8, "GenBank"),                           # kept
      row(9, "MO Observations", country = NA, state = "'Puerto Rico'"),  # in, by its state
      row(10, "iNaturalist")                       # out of the window
    ), collapse = ", "), ";",
    "INSERT INTO observation_cache VALUES ('inat', '1', false, 500), ('inat', '2', true, 10),",
    "  ('inat', '3', false, 3000), ('inat', '4', false, 1500), ('inat', '10', true, 10);",
    paste0(atlas_waterfall_sql(0, 9, max_m = 2000), ";"),
    "ROLLBACK;"
  )
  out <- system(Sys.getenv("ATLAS_TEST_PSQL"), input = sql, intern = TRUE)
  rows <- grep("^[A-Za-z ]+[|,][0-9]", out, value = TRUE)
  got <- lapply(strsplit(rows, "[|,]"), function(x) x)
  table <- stats::setNames(lapply(got, function(x) as.integer(x[-1])), vapply(got, `[[`, "", 1))
  expect_setequal(names(table), c("GenBank", "MO Observations", "iNaturalist"))
  expect_equal(table[["iNaturalist"]], c(5L, 4L, 4L, 4L, 1L, 1L))
  expect_equal(table[["MO Observations"]], c(3L, 3L, 2L, 1L, 0L, 0L))
  expect_equal(table[["GenBank"]], c(1L, 1L, 1L, 1L, 0L, 0L))
})
