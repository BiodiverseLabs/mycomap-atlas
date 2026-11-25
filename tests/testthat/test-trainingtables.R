# The training-record and lineage tables made on the box and deposited with
# a models version (R/trainingtables.R).

frozen_fixture <- function(...) {
  fx <- tables_fixture(...)
  fx$manifest$id <- ATLAS_TRAINING_TABLE_RELEASES[[1]]
  fx
}

# How the sources stand now for the fixture's records: answered and shown,
# unless told otherwise, with one record deleted at the source that no
# model trained on.
fixture_status <- function(fx, ...) {
  args <- list(...)
  if (is.null(args$deleted)) args$deleted <- "not-in-the-table"
  do.call(planted_status, c(list(fx$occurrences), args))
}

# A removed-records answer, as atlas_removed_records gives it.
fake_removed <- function() {
  list(table = data.frame(source = "iNaturalist", source_id = "removed-1", name = "Plantae one"),
       summary = list(records = 1L, source = "iNaturalist", names = 1L, ids_differing_from_the_drop_list = 0L))
}

make_tables <- function(fx, status, dir, ...) {
  atlas_training_tables_make(fx$store, fx$manifest, fx$tree, fx$land, status, dir, removed = fake_removed(), ...)
}

# A bundle as the deposit holds it once its cells made now are in.
fake_bundle <- function(fx, sources = character()) {
  list(kind = "models", release = list(id = fx$manifest$id), key = "key", sources = sources,
       cells_now = list(checked_at = "2026-11-08T09:00:00Z", checked_on = "2026-11-08"))
}

read_table <- function(path) {
  con <- if (grepl("[.]gz$", path)) gzfile(path) else path
  utils::read.delim(con, sep = "\t", quote = "", na.strings = character(), colClasses = "character",
                    check.names = FALSE, stringsAsFactors = FALSE)
}

test_that("the tables are made only for the release whose models version carries them", {
  fx <- tables_fixture()
  expect_error(make_tables(fx, fixture_status(fx), tempfile()),
               "made only for release 20261013T191324Z-fa1b4198, not r1")
  expect_error(atlas_training_tables_run(tempfile(), "20990101T000000Z-other", store = fx$store,
                                         run = function(...) stop("no query may be sent")),
               "made only for release")
  expect_error(suppressMessages(atlas_main(c("training-tables", "--release=20990101T000000Z-other",
                                             paste0("--out=", tempfile()), paste0("--store=", fx$store$uri),
                                             "--privacy-list=list.tsv.gz", "--cells-now=cells"))),
               "made only for release")
  expect_identical(ATLAS_TRAINING_TABLE_RELEASES, ATLAS_FROZEN_RELEASES)
})

test_that("a record hidden at its source now has no site, and one deleted there is left out, as the cells made now judge them", {
  fx <- frozen_fixture(mo = 4L)
  before <- store_hashes(fx$store)
  inat_a <- fx$occurrences$observation_id[fx$occurrences$scientific_name == "Taxon A"]
  mo_b <- fx$occurrences$observation_id[fx$occurrences$source == ATLAS_MO_SOURCE]
  status <- fixture_status(fx, inat_hidden = inat_a[[2]], inat_unanswered = inat_a[[3]], mo_not_shown = mo_b[[1]],
                           deleted = mo_b[[2]])
  dir <- tempfile("tables-")
  summary <- make_tables(fx, status, dir)
  expect_setequal(list.files(dir), c(unname(ATLAS_TRAINING_TABLE_FILES), ATLAS_TRAINING_TABLE_SUMMARY))
  expect_identical(read_table(file.path(dir, ATLAS_TRAINING_TABLE_FILES[["removed"]])), fake_removed()$table)
  out <- read_table(file.path(dir, ATLAS_TRAINING_TABLE_FILES[["records"]]))
  expect_identical(names(out), ATLAS_TRAINING_COLUMNS)
  site <- stats::setNames(out$site_id, out$source_id)
  expect_identical(unname(site[c(inat_a[[2]], inat_a[[3]], mo_b[[1]])]), c("", "", ""))
  expect_true(all(nzchar(site[setdiff(names(site), c(inat_a[[2]], inat_a[[3]], mo_b[[1]]))])))
  expect_false(mo_b[[2]] %in% out$source_id)
  expect_equal(nrow(out), 55L)
  expect_equal(summary$rows_without_site, 3L)
  expect_equal(summary$deleted_at_source$left_out, 1L)
  expect_identical(summary$deleted_at_source$list_read_on, "2026-11-08")
  expect_identical(summary$checked_on, "2026-11-08")
  expect_equal(summary$privacy_list_records, 0L)
  expect_equal(summary$checks$models_checked, 3L)
  expect_equal(summary$checks$models_whose_records_differ_from_the_listed_rows, 0L)
  expect_equal(summary$checks$models_found_only_through_another_pull, 0L)
  # A record on this machine's privacy list has no site either.
  listed <- atlas_record_key(fx$occurrences$source[1], fx$occurrences$observation_id[1])
  again <- make_tables(fx, fixture_status(fx), tempfile(),
                                      listed = listed)
  expect_equal(again$rows_without_site, 1L)
  expect_equal(again$privacy_list_records, 1L)
  # Each file's sum is in the summary, and the store is as it was.
  written <- jsonlite::fromJSON(file.path(dir, ATLAS_TRAINING_TABLE_SUMMARY), simplifyVector = FALSE)
  for (name in ATLAS_TRAINING_TABLE_FILES) expect_identical(written$files[[name]]$sha256, atlas_sha256(file.path(dir, name)))
  expect_identical(store_hashes(fx$store), before)
})

test_that("an incomplete status answer writes nothing", {
  fx <- frozen_fixture()
  inat <- fx$occurrences$observation_id
  dir <- tempfile("tables-")
  expect_error(make_tables(fx,
                                          fixture_status(fx, inat_unanswered = inat[1:5]), dir),
               "the status answer looks incomplete")
  expect_false(dir.exists(dir) && length(list.files(dir)) > 0L)
  status <- fixture_status(fx)
  status$deleted <- character()
  expect_error(make_tables(fx, status, dir),
               "lists no record deleted at the source")
  expect_false(dir.exists(dir) && length(list.files(dir)) > 0L)
})

test_that("the lineage names a pull by the hash the printed values begin, and its column says which", {
  fx <- tables_fixture()
  built <- atlas_deposit_training_table(fx$store, fx$manifest, fx$tree, fx$land)
  jobs <- atlas_deposit_jobs(fx$store)
  by_print <- atlas_deposit_lineage(built$fitting, jobs, printed = substr(strrep("ab", 32), 1, 8))
  expect_identical(by_print$pull_column, "pull_fingerprint")
  expect_true(all(by_print$models$pull_fingerprint == strrep("ab", 32)))
  file_sha <- unique(built$fitting$pull)
  by_file <- atlas_deposit_lineage(built$fitting, jobs, printed = toupper(substr(file_sha, 1, 8)))
  expect_identical(by_file$pull_column, "pull_file_sha256")
  expect_false("pull_fingerprint" %in% c(names(by_file$models), names(by_file$pulls)))
  expect_true(all(by_file$models$pull_file_sha256 == file_sha))
  expect_true(all(by_file$pulls$pull_file_sha256 == file_sha))
  expect_error(atlas_deposit_lineage(built$fitting, jobs, printed = c(substr(file_sha, 1, 8), "abababab")),
               "begin neither")
  expect_error(atlas_deposit_lineage(built$fitting, jobs, printed = "0123456789"), "begin neither")
  expect_error(atlas_deposit_lineage(built$fitting, jobs, printed = "4b1f56"), "not the start of a hash")
})

test_that("a deposit adds the tables to their own release's bundle only, each file checked against its sum", {
  fx <- frozen_fixture()
  dir <- tempfile("tables-")
  make_tables(fx, fixture_status(fx), dir)
  cells <- tempfile(fileext = ".tsv.gz")
  writeLines("x", cells)
  bundle <- fake_bundle(fx, c("collection-cells-0.1deg.tsv.gz" = cells))
  given <- atlas_archive_bundle_tables(bundle, dir)
  expect_setequal(names(given$sources), c("collection-cells-0.1deg.tsv.gz", unname(ATLAS_TRAINING_TABLE_FILES),
                                         ATLAS_TRAINING_TABLE_SUMMARY))
  expect_true(any(grepl("`removed-records.tsv` lists the 1 records removed", atlas_archive_tables_lines(given), fixed = TRUE)))
  # Without the cells made now, or with cells made more than a day apart, the tables are refused.
  plain <- bundle
  plain$cells_now <- NULL
  expect_error(atlas_archive_bundle_tables(plain, dir), "give --cells-now as well")
  late <- bundle
  late$cells_now$checked_at <- "2026-11-10T10:00:00Z"
  expect_error(atlas_archive_bundle_tables(late, dir), "not made within a day of each other")
  expect_false(identical(given$key, bundle$key))
  lines <- atlas_archive_tables_lines(given)
  expect_true(any(grepl("Site numbers are the table's own, given in the table's order, and say nothing of where a site is",
                        lines, fixed = TRUE)))
  expect_true(any(grepl("as the sources said on 2026-11-08", lines, fixed = TRUE)))
  expect_true(any(grepl("`sequence_id` is left blank in this version.", lines, fixed = TRUE)))
  expect_length(atlas_archive_tables_lines(bundle), 0L)
  expect_error(atlas_archive_bundle_tables(given, dir), "already holds the training-record table")
  other <- bundle
  other$release$id <- "20990101T000000Z-other"
  expect_error(atlas_archive_bundle_tables(other, dir), "made only for release")
  cat("x", file = file.path(dir, ATLAS_TRAINING_TABLE_FILES[["pulls"]]), append = TRUE)
  expect_error(atlas_archive_bundle_tables(bundle, dir), "lineage-pulls.tsv does not match its summary")
})

test_that("a deposited table with a coordinate in it is refused at deposit, even with its sums made again", {
  fx <- frozen_fixture()
  dir <- tempfile("tables-")
  make_tables(fx, fixture_status(fx), dir)
  path <- file.path(dir, ATLAS_TRAINING_TABLE_FILES[["records"]])
  out <- read_table(path)
  out$sequence_id[[1]] <- "45.12345"
  atlas_write_tsv_gz(out, path)
  summary <- jsonlite::fromJSON(file.path(dir, ATLAS_TRAINING_TABLE_SUMMARY), simplifyVector = FALSE)
  summary$files[[basename(path)]]$sha256 <- atlas_sha256(path)
  atlas_write_json(summary, file.path(dir, ATLAS_TRAINING_TABLE_SUMMARY))
  bundle <- fake_bundle(fx)
  expect_error(atlas_archive_bundle_tables(bundle, dir), "coordinate")
})

test_that("the box fetches only the release's model metrics and taxa table, each checked against its hash", {
  store <- fresh_store()
  files <- list()
  put <- function(path, text) {
    f <- tempfile()
    writeLines(text, f)
    sha <- atlas_sha256(f)
    store$put(atlas_object_key(sha), f)
    files[[length(files) + 1L]] <<- list(path = path, sha256 = sha, bytes = file.size(f))
  }
  put("models/draft/taxon-a.json", '{"taxon": "Taxon A"}')
  put("models/draft/rf/taxon-a.json", '{"taxon": "Taxon A"}')
  put("occurrences/taxa-latest.json", '[{"scientific_name": "Taxon A", "records": 3}]')
  put("models/draft/taxon-a.tif", "not a map")
  put("public/cells.tsv.gz", "not cells")
  atlas_store_json(store, "releases/draft/r1.json", list(id = "r1", files = files))
  tree <- tempfile("tree-")
  manifest <- atlas_training_tables_release(store, "r1", "draft", tree)
  expect_identical(manifest$id, "r1")
  expect_setequal(list.files(tree, recursive = TRUE),
                  c("models/draft/taxon-a.json", "models/draft/rf/taxon-a.json", "occurrences/taxa-latest.json"))
  files[[1]]$sha256 <- strrep("0", 64)
  store$put(atlas_object_key(strrep("0", 64)), file.path(tree, "models/draft/rf/taxon-a.json"))
  atlas_store_json(store, "releases/draft/r2.json", list(id = "r2", files = files))
  expect_error(atlas_training_tables_release(store, "r2", "draft", tempfile("tree-")), "does not match its hash")
  expect_error(atlas_training_tables_release(store, "r3", "draft", tempfile("tree-")), "no release r3")
})

# ---- removed records ---------------------------------------------------------

removed_fixture <- function() {
  after <- data.frame(id = c("1", "2"), source = "iNaturalist", observation_id = c("a", "b"),
                      scientific_name = c("Fungus one", "Fungus two"), stringsAsFactors = FALSE)
  extra <- data.frame(id = c("3", "4", "5"), source = "iNaturalist", observation_id = c("c", "d", "e"),
                      scientific_name = c("Plant one", "Plant one", "Moss one"), stringsAsFactors = FALSE)
  exclude <- data.frame(by = "id", id = c("9", "3", "4", "5"),
                        reason = c("bogus links", rep("non-fungal names", 3)),
                        added_at = c("2026-10-13T06:15:00Z", rep("2026-10-13T13:34:10Z", 3)), stringsAsFactors = FALSE)
  expect <- list(before = "xb", after = "xa", records = 3L, source = "iNaturalist", names = 2L,
                 added_at = "2026-10-13T13:34", reason = "non-fungal names")
  list(before = rbind(after, extra), after = after, exclude = exclude, expect = expect)
}

test_that("the removed records are the rows the cleaning took from the pull, as the drop list's entries of that cleaning name them", {
  r <- removed_fixture()
  got <- atlas_removed_records(r$before, r$after, r$exclude, r$expect)
  expect_identical(names(got$table), ATLAS_REMOVED_COLUMNS)
  expect_identical(got$table$source_id, c("c", "d", "e"))
  expect_identical(got$table$name, c("Plant one", "Plant one", "Moss one"))
  expect_equal(c(got$summary$records, got$summary$names, got$summary$ids_differing_from_the_drop_list), c(3L, 2L, 0L))
  # Another count, another source or another number of names: refused, with the three numbers.
  fewer <- r$expect
  fewer$records <- 4L
  expect_error(atlas_removed_records(r$before, r$after, r$exclude, fewer),
               "3 rows from iNaturalist under 2 names, not 4 from iNaturalist under 2")
  mixed <- r
  mixed$before$source[5] <- ATLAS_MO_SOURCE
  expect_error(atlas_removed_records(mixed$before, mixed$after, mixed$exclude, mixed$expect), "from iNaturalist and MO")
  # Ids that differ from the drop list's entries of that cleaning: refused, with the count only.
  off <- r$exclude
  off$id[4] <- "6"
  expect_error(atlas_removed_records(r$before, r$after, off, r$expect), "2 ids differ")
  expect_error(atlas_removed_records(r$before, r$after, NULL, r$expect), "no drop list")
})

# ---- which status blanks a site ---------------------------------------------

test_that("a site stays blank once hidden: on the release's own list though open now, or open on the list but obscured now", {
  fx <- frozen_fixture()
  inat <- fx$occurrences$observation_id[fx$occurrences$scientific_name == "Taxon A"]
  listed <- atlas_record_key(ATLAS_INAT_SOURCE, inat[[1]])
  status <- fixture_status(fx, inat_hidden = inat[[2]])
  dir <- tempfile("tables-")
  make_tables(fx, status, dir, listed = listed)
  out <- read_table(file.path(dir, ATLAS_TRAINING_TABLE_FILES[["records"]]))
  site <- stats::setNames(out$site_id, out$source_id)
  expect_identical(unname(site[inat[1:3]]), c("", "", site[[inat[[3]]]]))
  expect_true(nzchar(site[[inat[[3]]]]))
})

test_that("the tables are not made more than a day from the cells made beside them", {
  fx <- frozen_fixture()
  expect_error(make_tables(fx, fixture_status(fx), tempfile(), cells_now = list(checked_at = "2026-11-06T09:00:00Z")),
               "not made within a day of each other")
  expect_error(atlas_training_tables_check_cells_now(list(release = "other"), fx$manifest$id, tempfile(), "x"),
               "release other's")
  list_file <- tempfile()
  writeLines("a", list_file)
  expect_error(atlas_training_tables_check_cells_now(list(release = fx$manifest$id, privacy_list = list(sha256 = "0")),
                                                     fx$manifest$id, list_file, "2026-11-08T10:00:00Z"),
               "another privacy list")
})

test_that("the box step works in a folder of its own under the data directory, removed however it ends, and holds the lock", {
  with_data_dir({
    root <- atlas_path("work")
    store <- fresh_store()
    local_mocked_bindings(atlas_training_tables_release = function(store, release, grid, tree) {
      dir.create(tree, recursive = TRUE)
      stop("stopped on purpose")
    })
    expect_error(atlas_training_tables_run(tempfile(), ATLAS_TRAINING_TABLE_RELEASES[[1]], tempfile(), tempfile(),
                                           store = store, work_root = root), "stopped on purpose")
    expect_length(list.files(root), 0L)
    expect_false(dir.exists(atlas_path("locks", "orchestrator")))
    # While another run holds the lock, the step does not start.
    dir.create(atlas_path("locks", "orchestrator"), recursive = TRUE)
    atlas_write_json(list(name = "atlas-nightly", since = "2026-11-25T00:00:00Z", until = "2099-01-01T00:00:00Z"),
                     atlas_path("locks", "orchestrator", "held.json"))
    expect_error(atlas_training_tables_run(tempfile(), ATLAS_TRAINING_TABLE_RELEASES[[1]], tempfile(), tempfile(),
                                           store = store, work_root = root), "does not start until it ends")
  })
})

# ---- how the sources stand now, a window of ids at a time -------------------

test_that("the status is asked a keyed window of ids at a time, and read as the cells' status is", {
  sent <- character()
  run <- function(sql, host) {
    sent <<- c(sent, sql)
    if (grepl("max(id)", sql, fixed = TRUE)) return("top\n150000")
    if (!grepl("o.id > 0 AND", sql, fixed = TRUE)) return("")
    paste("source\tobservation_id\tinat_answered\tinat_hidden\tmo_answered\tmo_shown\tdeleted",
          "iNaturalist\t1\tt\tt\tf\t\tf", "iNaturalist\t2\tt\tf\tt\tf\tf", "iNaturalist\t3\tf\t\tf\t\tf",
          "MO Observations\t1\tf\t\tt\tf\tt", "MO Observations\t5\tt\t\tt\tt\tf", sep = "\n")
  }
  status <- atlas_status_paged(run, "sql", max_m = 1000, window = 100000, sleep = function(seconds) NULL)
  pages <- sent[-1]
  expect_length(pages, 2L)
  for (sql in pages) {
    expect_match(sql, "WHERE o.id > [0-9]+ AND o.id <= [0-9]+ AND o.source IN")
    expect_match(sql, "positional_accuracy > 1000")
    expect_false(grepl("\n|\"|%", sql))
  }
  expect_identical(status$inat$number, c("1", "2"))
  expect_identical(status$inat$hidden, c("t", "f"))
  # An answer is read only for its own source: the MO cache's row for number 2
  # is not the iNaturalist 2's, and the iNaturalist cache's 5 is not the MO 5's.
  expect_identical(status$mo$number, c("1", "5"))
  expect_identical(status$mo$shown, c("f", "t"))
  expect_identical(status$deleted, "1")
  pull <- data.frame(source = c(rep("iNaturalist", 3), "MO Observations", "MO Observations"),
                     observation_id = c("1", "2", "3", "1", "5"), stringsAsFactors = FALSE)
  groups <- atlas_cells_now_groups(pull, character(), status)
  expect_identical(unname(groups[, "b"]), c(TRUE, FALSE, TRUE, FALSE, FALSE))
  expect_identical(unname(groups[, "c"]), c(FALSE, FALSE, FALSE, TRUE, FALSE))
  expect_identical(unname(groups[, "d"]), c(FALSE, FALSE, FALSE, TRUE, FALSE))
})

# ---- the contributors table -------------------------------------------------

test_that("the contributors table counts each named contributor's rows by source, and the rest as one anonymous row", {
  training <- data.frame(source = c(rep("iNaturalist", 5), rep("MO Observations", 3)),
                         source_id = c(as.character(1:5), as.character(1:3)), stringsAsFactors = FALSE)
  names <- data.frame(source = c(rep("iNaturalist", 4), rep("MO Observations", 3)),
                      source_id = c(as.character(1:4), as.character(1:3)),
                      contributor = c("ann", "ann", "bo", "someone@example.org", "ann", "Cy Dee", ""),
                      stringsAsFactors = FALSE)
  opt_outs <- data.frame(source = "iNaturalist", contributor = "bo")
  got <- atlas_contributors_table(training, names, opt_outs)
  expect_identical(names(got$table), ATLAS_CONTRIBUTOR_COLUMNS)
  row <- function(source, who) got$table$training_records[got$table$source == source & got$table$contributor == who]
  expect_equal(row("iNaturalist", "ann"), 2L)
  # bo asked not to be named, one is an email address, record 5 has no name: one anonymous row of 3.
  expect_equal(row("iNaturalist", "anonymous"), 3L)
  expect_false(any(got$table$contributor %in% c("bo", "someone@example.org")))
  # The same login under another source is another contributor; a name with a space is kept whole.
  expect_equal(row("MO Observations", "ann"), 1L)
  expect_equal(row("MO Observations", "Cy Dee"), 1L)
  expect_equal(row("MO Observations", "anonymous"), 1L)
  expect_equal(sum(got$table$training_records), nrow(training))
  expect_equal(got$summary$anonymous_records, list(no_name = 2L, email_like = 1L, asked_not_to_be_named = 1L))
  twice <- rbind(names, names[1, ])
  expect_error(atlas_contributors_table(training, twice), "more than once")
})

test_that("the contributors table is made with the tables when a names file is given, and goes into the deposit with them", {
  fx <- frozen_fixture()
  names <- data.frame(source = fx$occurrences$source, source_id = fx$occurrences$observation_id,
                      contributor = "ann", stringsAsFactors = FALSE)
  dir <- tempfile("tables-")
  summary <- make_tables(fx, fixture_status(fx), dir, names = names)
  expect_true(file.exists(file.path(dir, ATLAS_CONTRIBUTORS_FILE)))
  expect_equal(summary$contributors$records, 56L)
  given <- atlas_archive_bundle_tables(fake_bundle(fx), dir)
  expect_true(ATLAS_CONTRIBUTORS_FILE %in% names(given$sources))
  expect_true(any(grepl("`contributors.tsv` gives", atlas_archive_tables_lines(given), fixed = TRUE)))
  # Without a names file, there is no contributors table and the README says nothing of one.
  plain <- tempfile("tables-")
  make_tables(fx, fixture_status(fx), plain)
  expect_false(file.exists(file.path(plain, ATLAS_CONTRIBUTORS_FILE)))
  expect_false(any(grepl("contributors", atlas_archive_tables_lines(atlas_archive_bundle_tables(fake_bundle(fx), plain)))))
})

test_that("the box step holds terra to its own memory while it builds the predictor cover, and puts the setting back", {
  with_data_dir({
    before <- terra::terraOptions(print = FALSE)$memmax
    seen <- NULL
    list_file <- tempfile(fileext = ".tsv.gz")
    atlas_write_tsv_gz(data.frame(source = character(), observation_id = character(), privacy = character()), list_file)
    local_mocked_bindings(
      atlas_training_tables_release = function(store, release, grid, tree) list(id = release, pull = list(file = "p.tsv.gz")),
      atlas_read_cells_now = function(dir, manifest) list(summary = list()),
      atlas_pull_by_stamp = function(suffix) "p.tsv.gz",
      atlas_read_occurrences = function(...) data.frame(),
      atlas_removed_records = function(...) fake_removed(),
      atlas_archive_block_land = function(...) {
        seen <<- terra::terraOptions(print = FALSE)$memmax
        stop("cover built")
      }
    )
    expect_error(atlas_training_tables_run(tempfile(), ATLAS_TRAINING_TABLE_RELEASES[[1]], list_file, tempfile(),
                                           store = fresh_store()), "cover built")
    expect_equal(seen, ATLAS_TABLES_TERRA_GB)
    expect_identical(terra::terraOptions(print = FALSE)$memmax, before)
  })
})

test_that("the status pages are paced: a pause between pages, a longer one after a slow page, and a stop near the limit", {
  now <- as.POSIXct("2026-11-25 00:00:00", tz = "UTC")
  slept <- numeric()
  takes <- c(2, 12, 3, 4)
  page <- 0L
  run <- function(sql, host) {
    if (grepl("max(id)", sql, fixed = TRUE)) return("top\n350000")
    page <<- page + 1L
    now <<- now + takes[[page]]
    "source\tobservation_id\tinat_answered\tinat_hidden\tmo_answered\tmo_shown\tdeleted"
  }
  atlas_status_paged(run, "sql", window = 100000, clock = function() now, sleep = function(s) slept <<- c(slept, s))
  # No wait before the first page; 5 s after a 2 s page, 30 s after the 12 s one.
  expect_identical(slept, c(5, 30, 5))
  takes <- c(2, 31)
  page <- 0L
  expect_error(atlas_status_paged(run, "sql", window = 100000, clock = function() now, sleep = function(s) NULL),
               "ids 100001 to 200000 took 31 s, near the read-only route's limit; stopped, nothing written")
})
