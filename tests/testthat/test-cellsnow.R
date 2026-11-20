# The cells an archive version carries are made again as the sources stand
# now (R/cellsnow.R, Steve 2026-11-07): the release's own list, plus
# iNaturalist records obscured or unanswered now, MO records whose point is
# no longer shown or unanswered now, and MO records deleted at the source.

# A pull with one record for each case, each its own taxon in its own cell,
# so a record that leaves takes its cell with it.
cells_now_pull <- function() {
  rows <- list(
    c("iNaturalist", "101", "Listed inat"),
    c("iNaturalist", "102", "Obscured now"),
    c("iNaturalist", "103", "Coarse now"),
    c("iNaturalist", "104", "Unanswered inat"),
    c("iNaturalist", "105", "Public inat"),
    c("MO Observations", "201", "Listed mo"),
    c("MO Observations", "202", "Hidden now"),
    c("MO Observations", "203", "Unanswered mo"),
    c("MO Observations", "204", "Deleted mo"),
    c("MO Observations", "205", "Public mo"),
    # The same number as an iNaturalist record obscured now: another source's
    # record, which no iNaturalist answer reaches.
    c("MycoPortal", "102", "Portal record")
  )
  n <- length(rows)
  data.frame(
    id = as.character(seq_len(n)),
    observation_id = vapply(rows, `[[`, "", 2),
    source = vapply(rows, `[[`, "", 1),
    scientific_name = vapply(rows, `[[`, "", 3),
    observed_on = "2025-10-01",
    latitude = sprintf("%.4f", 40 + seq_len(n)),
    longitude = sprintf("%.4f", -100 - seq_len(n)),
    stringsAsFactors = FALSE
  )
}

cells_now_listed <- function() c("iNaturalist:101", "MO Observations:201")

cells_now_status <- function(pull = cells_now_pull()) {
  planted_status(pull, inat_hidden = c("102", "103"), inat_unanswered = "104",
                 mo_not_shown = c("201", "202"), mo_unanswered = "203", deleted = "204")
}

# The release's cells file, as a release makes it: the pull less its list.
release_cells_file <- function(pull = cells_now_pull(), listed = cells_now_listed()) {
  path <- tempfile(fileext = ".tsv.gz")
  atlas_write_tsv_gz(atlas_public_cells_table(pull, hidden = listed), path)
  path
}

# The guards stop a status answer that reads as too much left out; the
# planted pull is tiny, so for the cases below they are lifted.
without_guards <- function(code) {
  old <- c(ATLAS_CELLS_NOW_MAX_UNANSWERED, ATLAS_CELLS_NOW_MAX_BEYOND)
  ns <- asNamespace("mycomapatlas")
  unlockBinding("ATLAS_CELLS_NOW_MAX_UNANSWERED", ns)
  unlockBinding("ATLAS_CELLS_NOW_MAX_BEYOND", ns)
  assign("ATLAS_CELLS_NOW_MAX_UNANSWERED", 1, envir = ns)
  assign("ATLAS_CELLS_NOW_MAX_BEYOND", 1, envir = ns)
  on.exit({
    assign("ATLAS_CELLS_NOW_MAX_UNANSWERED", old[[1]], envir = ns)
    assign("ATLAS_CELLS_NOW_MAX_BEYOND", old[[2]], envir = ns)
    lockBinding("ATLAS_CELLS_NOW_MAX_UNANSWERED", ns)
    lockBinding("ATLAS_CELLS_NOW_MAX_BEYOND", ns)
  }, add = TRUE)
  force(code)
}

cells_now_result <- function(pull = cells_now_pull(), status = cells_now_status(pull)) {
  without_guards(atlas_cells_now(pull, cells_now_listed(), release_cells_file(pull), status, release = "r1"))
}

taxa_left <- function(result) sort(unique(result$cells$taxon))

test_that("group (a): a record on the release's own list stays out", {
  left <- taxa_left(cells_now_result())
  expect_false("Listed inat" %in% left)
  expect_false("Listed mo" %in% left)
})

test_that("group (b): an iNaturalist record obscured, coarse or unanswered now leaves the cells", {
  left <- taxa_left(cells_now_result())
  expect_false("Obscured now" %in% left)
  expect_false("Coarse now" %in% left)
  expect_false("Unanswered inat" %in% left)
  expect_true("Public inat" %in% left)
})

test_that("group (c): an MO record whose point is no longer shown, or unanswered now, leaves the cells", {
  left <- taxa_left(cells_now_result())
  expect_false("Hidden now" %in% left)
  expect_false("Unanswered mo" %in% left)
  expect_true("Public mo" %in% left)
})

test_that("group (d): an MO record deleted at the source leaves the cells, even with its point shown", {
  pull <- cells_now_pull()
  status <- cells_now_status(pull)
  expect_true("204" %in% status$mo$number[status$mo$shown == "t"])
  left <- taxa_left(cells_now_result(pull, status))
  expect_false("Deleted mo" %in% left)
})

test_that("another source's record is counted where recorded, whatever an iNaturalist answer says of its number", {
  left <- taxa_left(cells_now_result())
  expect_true("Portal record" %in% left)
  expect_equal(left, c("Portal record", "Public inat", "Public mo"))
})

test_that("each group is counted, and what it adds beyond the earlier ones", {
  s <- cells_now_result()$summary
  expect_equal(vapply(s$groups, function(g) g$records, numeric(1)), c(a = 2, b = 3, c = 3, d = 1))
  # 201 is on the list and also shows no point: counted in (c), not again.
  expect_equal(vapply(s$groups, function(g) g$not_in_an_earlier_group, numeric(1)), c(a = 2, b = 3, c = 2, d = 1))
  expect_equal(s$left_out, 8)
  expect_equal(s$left_out_beyond_the_list, 6)
  expect_setequal(names(s$by_source_beyond_the_list), c("iNaturalist", "MO Observations"))
  expect_equal(s$by_source_beyond_the_list[["iNaturalist"]], 3L)
  expect_equal(s$by_source_beyond_the_list[["MO Observations"]], 3L)
  expect_equal(s$cells_now, list(records = 3L, taxa = 3L, cells = 3L))
  expect_equal(s$release_cells$records, 9L)
  expect_equal(s$checked_on, "2026-11-08")
})

test_that("the pull less its own list must give the release's cells exactly, or nothing is made", {
  pull <- cells_now_pull()
  s <- cells_now_result(pull)$summary
  expect_true(s$list_alone_gives_the_release_cells)
  # A release whose cells left out one more record than its list says.
  other <- release_cells_file(pull, c(cells_now_listed(), "MycoPortal:102"))
  expect_error(
    without_guards(atlas_cells_now(pull, cells_now_listed(), other, cells_now_status(pull), release = "r1")),
    "does not give the release's cells"
  )
})

test_that("a status answer that has lost its iNaturalist or MO answers writes nothing", {
  pull <- cells_now_pull()
  status <- cells_now_status(pull)
  status$inat <- status$inat[0, ]
  expect_error(atlas_cells_now(pull, cells_now_listed(), release_cells_file(pull), status, release = "r1"),
               "looks incomplete")
  status <- cells_now_status(pull)
  status$mo <- status$mo[0, ]
  expect_error(atlas_cells_now(pull, cells_now_listed(), release_cells_file(pull), status, release = "r1"),
               "looks incomplete")
})

test_that("more than a small share of the pull leaving beyond the list writes nothing", {
  pull <- cells_now_pull()
  # Every record answered; four iNaturalist records obscured now, of eleven.
  expect_error(atlas_cells_now(pull, cells_now_listed(), release_cells_file(pull),
                               planted_status(pull, inat_hidden = c("102", "103", "104", "105")), release = "r1"),
               "would leave beyond the list")
})

test_that("what is written holds counts and the cells, never a record's number", {
  dir <- tempfile("cells-now-")
  summary <- atlas_write_cells_now(cells_now_result(), dir)
  text <- paste(readLines(file.path(dir, ATLAS_CELLS_NOW_SUMMARY), warn = FALSE), collapse = "\n")
  for (number in unique(cells_now_pull()$observation_id)) {
    expect_false(grepl(paste0("\\b", number, "\\b"), text), info = number)
  }
  written <- utils::read.delim(gzfile(file.path(dir, ATLAS_CELLS_NOW_FILE)), colClasses = "character")
  expect_equal(names(written), c("taxon", "lat", "lng", "records"))
  expect_equal(summary$cells_now$sha256, atlas_sha256(file.path(dir, ATLAS_CELLS_NOW_FILE)))
})

test_that("the status queries are single read-only lines the route takes, and cover every number", {
  sql <- atlas_cells_now_sql()
  all <- c(unlist(sql$inat), sql$mo, sql$deleted)
  for (statement in all) {
    expect_silent(atlas_assert_transport_safe(statement))
    expect_true(startsWith(statement, "SELECT "))
    expect_false(grepl("\\b(insert|update|delete|drop|alter|create)\\b", tolower(statement)))
  }
  expect_length(sql$inat, 11)
  expect_true(any(grepl("NOT IN ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')", sql$inat, fixed = TRUE)))
  for (d in 0:9) expect_true(any(grepl(sprintf("= '%d' GROUP BY", d), sql$inat, fixed = TRUE)))
  expect_true(all(grepl("positional_accuracy > 1000) AS hidden", sql$inat, fixed = TRUE)))
  expect_match(sql$mo, ATLAS_MO_POINTS, fixed = TRUE)
  expect_match(sql$deleted, "o.source_deleted_at IS NOT NULL", fixed = TRUE)
  expect_match(sql$deleted, "o.source = 'MO Observations'", fixed = TRUE)
})

test_that("the status answer is put together from every page", {
  sql <- atlas_cells_now_sql()
  run <- function(statement, host) {
    if (identical(statement, sql$mo)) return("number\tshown\n201\tf\n205\tt")
    if (identical(statement, sql$deleted)) return("number\n204")
    last <- sub(".*right\\(c.source_observation_id, 1\\) = '([0-9])'.*", "\\1", statement)
    if (identical(last, "1")) return("number\thidden\n101\tf\n301\tt")
    if (identical(last, "5")) return("number\thidden\n105\tf")
    ""
  }
  status <- atlas_cells_now_status(run, host = "test")
  expect_setequal(status$inat$number, c("101", "301", "105"))
  expect_equal(status$mo$number, c("201", "205"))
  expect_equal(status$deleted, "204")
  expect_match(status$checked_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T")
  expect_error(atlas_cells_now_status(function(statement, host) "wrong\n1", host = "test"), "missing columns")
})

test_that("cells made now are only read for the release they were made for, as made", {
  with_data_dir({
    computed_data()
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    dir <- planted_cells_now(store)
    expect_silent(atlas_read_cells_now(dir, release))
    other <- release
    other$id <- "20990101T000000Z-other"
    expect_error(atlas_read_cells_now(dir, other), "made for release")
    s <- jsonlite::fromJSON(file.path(dir, ATLAS_CELLS_NOW_SUMMARY), simplifyVector = FALSE)
    s$list_alone_gives_the_release_cells <- FALSE
    atlas_write_json(s, file.path(dir, ATLAS_CELLS_NOW_SUMMARY))
    expect_error(atlas_read_cells_now(dir, release), "own check")
    dir <- planted_cells_now(store)
    cat("x\n", file = file.path(dir, ATLAS_CELLS_NOW_FILE), append = TRUE)
    expect_error(atlas_read_cells_now(dir, release), "does not match its summary")
    dir <- planted_cells_now(store)
    s <- jsonlite::fromJSON(file.path(dir, ATLAS_CELLS_NOW_SUMMARY), simplifyVector = FALSE)
    s$release_cells$sha256 <- strrep("0", 64)
    atlas_write_json(s, file.path(dir, ATLAS_CELLS_NOW_SUMMARY))
    expect_error(atlas_read_cells_now(dir, release), "another cells file")
  })
})

test_that("cells-now reads the release's own pull and list, not a pull made since", {
  with_data_dir({
    computed_data()
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    atlas_write_tsv_gz(data.frame(source = character(), observation_id = character(), privacy = character()),
                       atlas_privacy_path())
    # A later pull, with one more record, is now the machine's latest.
    later <- rbind(fake_occurrences(), transform(fake_occurrences()[1, ], id = "4", observation_id = "d"))
    atlas_write_tsv_gz(later, atlas_path("occurrences", "occurrences-20260201T000000Z.tsv.gz"))
    manifest <- jsonlite::fromJSON(atlas_path("occurrences", "latest.json"), simplifyVector = FALSE)
    manifest$file <- "occurrences-20260201T000000Z.tsv.gz"
    atlas_write_json(manifest, atlas_path("occurrences", "latest.json"))
    expect_equal(nrow(atlas_read_occurrences()), 4L)
    sql <- atlas_cells_now_sql()
    run <- function(statement, host) {
      if (identical(statement, sql$mo)) return("number	shown")
      if (identical(statement, sql$deleted)) return("number")
      if (grepl("NOT IN", statement, fixed = TRUE)) return("number	hidden
a	f
b	f
c	f
d	f")
      ""
    }
    dir <- tempfile("cells-now-")
    summary <- atlas_cells_now_run(dir, store, run = run, host = "test")
    expect_equal(summary$release, release$id)
    expect_equal(summary$pull$records, 3L)
    expect_true(summary$list_alone_gives_the_release_cells)
    expect_silent(atlas_read_cells_now(dir, release))
    # Without the release's own pull on the machine, nothing is made.
    unlink(atlas_path("occurrences", release$pull$file))
    expect_error(atlas_cells_now_run(tempfile("cells-now-"), store, run = run, host = "test"),
                 "does not hold release")
  })
})

# ---- the archive version ---------------------------------------------------

# A release whose pull holds a record obscured since, and cells made now that
# leave it out; check(store, release, dir) runs in its data directory.
archive_with_later_obscured <- function(check) {
  without_guards(with_data_dir({
    computed_data()
    store <- new_store()
    release <- atlas_publish_release(store, quiet = TRUE)
    pull <- atlas_read_occurrences()
    dir <- planted_cells_now(store, status = planted_status(pull, inat_hidden = pull$observation_id[[3]]))
    check(store, release, dir)
  }))
}

bundle_cells <- function(bundle) {
  utils::read.delim(gzfile(bundle$sources[["collection-cells-0.1deg.tsv.gz"]]), colClasses = "character")
}

test_that("a record obscured since the release leaves the archive's cells, and the release's own file stays", {
  archive_with_later_obscured(function(store, release, dir) {
    before <- atlas_sha256(atlas_public_cells_path())
    bundle <- atlas_archive_models_bundle(store, "draft", cells_now = dir)
    cells <- bundle_cells(bundle)
    expect_equal(sum(as.integer(cells$records)), 2L)
    plain <- atlas_archive_models_bundle(store, "draft")
    expect_equal(sum(as.integer(bundle_cells(plain)$records)), 3L)
    expect_equal(atlas_sha256(atlas_public_cells_path()), before)
  })
})

test_that("the archive's models are the release's, byte for byte", {
  archive_with_later_obscured(function(store, release, dir) {
    bundle <- atlas_archive_models_bundle(store, "draft", cells_now = dir)
    plain <- atlas_archive_models_bundle(store, "draft")
    models <- setdiff(names(bundle$sources), c("collection-cells-0.1deg.tsv.gz", "release.json"))
    models <- models[grepl("^maps-|^scores", models)]
    expect_gt(length(models), 0)
    for (name in models) {
      expect_equal(atlas_sha256(bundle$sources[[name]]), atlas_sha256(plain$sources[[name]]), info = name)
    }
  })
})

test_that("no JSON in a version with cells made now holds a per-taxon hash or a seed", {
  archive_with_later_obscured(function(store, release, dir) {
    bundle <- atlas_archive_models_bundle(store, "draft", cells_now = dir)
    jsons <- bundle$sources[grepl("[.]json$", names(bundle$sources))]
    expect_gt(length(jsons), 0)
    for (name in names(jsons)) {
      keys <- names(rapply(jsonlite::fromJSON(jsons[[name]], simplifyVector = FALSE), function(v) v, how = "unlist"))
      keys <- keys %||% character()
      expect_false(any(grepl("(^|[.])seed$", keys)), info = name)
      # The whole pull's fingerprint is the only one kept: what a result cites.
      found <- keys[grepl("(^|[.])fingerprint$", keys)]
      expect_true(all(found %in% c("pull.fingerprint", "fingerprint")), info = name)
      if (length(found)) expect_true(name %in% c("release.json", "pull.json"), info = name)
    }
  })
})

test_that("a version with cells made now has its own name and key, so the first version's key does not stop it", {
  archive_with_later_obscured(function(store, release, dir) {
    bundle <- atlas_archive_models_bundle(store, "draft", cells_now = dir)
    expect_equal(bundle$version, paste0(release$id, ".20261108"))
    expect_false(identical(bundle$key, release$files_key))
    zen <- fake_zenodo()
    atlas_archive(store, "draft", "models", z = zen$client(), publish = TRUE, quiet = TRUE, cells_now = dir)
    later <- planted_cells_now(store, status = planted_status(atlas_read_occurrences(), inat_hidden = c("b", "c"),
                                                              checked_at = "2026-11-09T10:00:00Z"))
    atlas_archive(store, "draft", "models", z = zen$client(), publish = TRUE, quiet = TRUE, cells_now = later)
    ledger <- atlas_archive_ledger(store, "models-draft")
    expect_equal(vapply(ledger$versions, function(v) v$version, ""),
                 paste0(release$id, c(".20261108", ".20261109")))
  })
})

test_that("a models version is not deposited without cells made now; a dry run still shows it", {
  with_data_dir({
    computed_data()
    store <- new_store()
    atlas_publish_release(store, quiet = TRUE)
    expect_error(atlas_archive(store, "draft", "models", z = fake_zenodo()$client(), quiet = TRUE),
                 "needs its collection cells made as the sources stand now")
    expect_silent(atlas_archive(store, "draft", "models", z = fake_zenodo()$client(), dry_run = TRUE, quiet = TRUE))
  })
})

test_that("the README says of the cells what Steve approved, word for word", {
  archive_with_later_obscured(function(store, release, dir) {
    bundle <- atlas_archive_models_bundle(store, "draft", cells_now = dir)
    readme <- atlas_archive_readme(bundle, atlas_archive_file_table(bundle$sources))
    short <- sub("^.*-", "", release$id)
    expect_true(paste0("This version holds the models of release ", short, " unchanged. Two things differ from that release's own files: each taxon's record-set fingerprint and each model's seed are withheld for privacy, and the collection cells (`collection-cells-0.1deg.tsv.gz`) also leave out records whose source has hidden or obscured their location since the release was made, and Mushroom Observer records the source no longer holds, as the sources said on 2026-11-08. `release.json` keeps the release's original checksums, so the cells file here differs from its entry there.") %in% readme)
    expect_true("Collection locations are given as record counts per 0.1 degree cell; the maps are on a 5 km grid. Records from iNaturalist and Mushroom Observer whose location the source hides, obscures or may hide, and Mushroom Observer records the source no longer holds, are left out of the cells; records from the other sources (MyCoPortal, DNA sequence records, GenBank) are counted where recorded." %in% readme)
    expect_false(any(grepl("exact coordinates are never published|appear only as", readme)))
  })
})

test_that("the Zenodo description says of the cells what Steve approved, word for word", {
  summary <- atlas_archive_template()$models$summary
  expect_true(endsWith(summary, "Collection locations are given as record counts per 0.1 degree cell. Records from iNaturalist and Mushroom Observer whose location the source hides, obscures or may hide, and Mushroom Observer records the source no longer holds, as checked when the version was made, are left out of the cells; records from other sources are counted where recorded."))
  expect_false(grepl("exact coordinates are never published|appear only as", summary))
})
