# A pull's QA report and its hard stops (R/qa.R).

qa_pull <- function(n_inat = 100, n_mo = 50) {
  data.frame(
    id = as.character(seq_len(n_inat + n_mo)),
    source = c(rep("iNaturalist", n_inat), rep("MO Observations", n_mo)),
    observation_id = as.character(c(seq_len(n_inat), seq_len(n_mo) + 5000)),
    scientific_name = rep(c("Amanita muscaria", "Russula emetica"), length.out = n_inat + n_mo),
    stringsAsFactors = FALSE
  )
}

qa_privacy <- function(pull, centres = 2, unknown = 1) {
  mo <- pull[pull$source == "MO Observations", , drop = FALSE]
  data.frame(source = c(mo$source[seq_len(centres)], pull$source[seq_len(unknown)]),
             observation_id = c(mo$observation_id[seq_len(centres)], pull$observation_id[seq_len(unknown)]),
             privacy = c(rep("place", centres), rep("unknown", unknown)), stringsAsFactors = FALSE)
}

qa_audit <- function(disagree = 10, pulled = 1000) {
  list(pulled = pulled, by_status = data.frame(status = c("dna_name", "sequences_disagree"),
                                               records = c(pulled - disagree, disagree)))
}

report_of <- function(pull = qa_pull(), ..., previous = NULL) {
  atlas_qa_report(pull, list(stamp = "20261101T070000Z"), audit = qa_audit(), privacy = qa_privacy(pull),
                  previous = previous, ...)
}

test_that("a clean pull stops nothing, and the report holds counts and shares, never a record", {
  report <- report_of(kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = "Fungi"))
  expect_length(report$stops, 0L)
  expect_equal(report$records, 150L)
  expect_setequal(names(report$checks), c("kingdom", "keys", "place_centres", "uncached", "privacy_list", "naming", "sources"))
  text <- jsonlite::toJSON(report, auto_unbox = TRUE)
  expect_false(grepl("5001", text, fixed = TRUE))
  expect_false(grepl("latitude|longitude", text))
})

test_that("a modelled name of another kingdom stops the pull, unless it is allowed", {
  kingdoms <- c("Amanita muscaria" = "Fungi", "Russula emetica" = "Animalia")
  report <- report_of(kingdoms = kingdoms)
  expect_equal(unlist(report$stops), "kingdom")
  expect_match(report$checks$kingdom$why, "Russula emetica")
  expect_length(report_of(kingdoms = kingdoms, allow = "Russula emetica")$stops, 0L)
  # A name GBIF could not place is counted, not a stop.
  unknown <- report_of(kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = NA))
  expect_length(unknown$stops, 0L)
  expect_equal(unknown$checks$kingdom$detail$unknown, 1L)
})

test_that("two records under one source:number key stop the pull; one number in two sources does not", {
  pull <- qa_pull()
  pull$observation_id[pull$source == "MO Observations"][1] <- "1"
  expect_length(report_of(pull)$stops, 0L)
  expect_equal(report_of(pull)$checks$keys$detail$numbers_shared_across_sources, 1L)
  pull$observation_id[2] <- "1"
  expect_equal(unlist(report_of(pull)$stops), "keys")
})

test_that("MO records at named-place centres stop the pull above 50%, or when their share rises 2 points", {
  stops <- function(n_mo, centres, previous = NULL) {
    pull <- qa_pull(n_mo = n_mo)
    "place_centres" %in% unlist(atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull, centres = centres),
                                                previous = previous)$stops)
  }
  # The two real pulls, the frozen one and the dry pull of 2026-11-04.
  expect_false(stops(5035, 1936))
  expect_false(stops(5157, 2115))
  # The ceiling itself, and just past it.
  expect_false(stops(50, 25))
  expect_true(stops(50, 26))
  # The rise, below the ceiling: 2 points is allowed, more is not.
  expect_false(stops(50, 21, previous = list(checks = list(place_centres = list(value = 0.40)))))
  expect_true(stops(50, 21, previous = list(checks = list(place_centres = list(value = 0.39)))))
})

test_that("a source's records stop the pull only when at least 20 moved; a smaller move past a limit is still reported", {
  check <- function(before, n_mo = 50) {
    pull <- qa_pull(n_mo = n_mo)
    atlas_qa_report(pull, list(stamp = "x"), previous = list(detail = list(by_source = before)))
  }
  moved_by <- function(before, n_mo = 50) {
    report <- check(before, n_mo)
    list(stops = "sources" %in% unlist(report$stops), below = unlist(report$checks$sources$detail$below_floor))
  }
  # A fall: 19 records is past 2% but under the floor; 20 stops.
  fell_19 <- moved_by(list(iNaturalist = 100, "MO Observations" = 69))
  expect_false(fell_19$stops)
  expect_equal(fell_19$below, "MO Observations 69 -> 50")
  fell_20 <- moved_by(list(iNaturalist = 100, "MO Observations" = 70))
  expect_true(fell_20$stops)
  expect_null(fell_20$below)
  # A rise: the same floor.
  rose_19 <- moved_by(list(iNaturalist = 100, "MO Observations" = 31))
  expect_false(rose_19$stops)
  expect_equal(rose_19$below, "MO Observations 31 -> 50")
  rose_20 <- moved_by(list(iNaturalist = 100, "MO Observations" = 30))
  expect_true(rose_20$stops)
  # At least 20 records but inside the percentages: no stop and nothing to report.
  large <- moved_by(list(iNaturalist = 100, "MO Observations" = 1020), n_mo = 1000)
  expect_false(large$stops)
  expect_null(large$below)
  # The real small moves: Sequences 61 -> 43 (18 records), and a small source gone.
  pull <- qa_pull()
  sequences <- pull[rep(1L, 43), , drop = FALSE]
  sequences$id <- as.character(1000 + seq_len(43))
  sequences$source <- "Sequences"
  sequences$observation_id <- as.character(seq_len(43))
  with_sequences <- rbind(pull, sequences)
  small <- atlas_qa_report(with_sequences, list(stamp = "x"), previous = list(detail = list(by_source = list(
    iNaturalist = 100, "MO Observations" = 50, Sequences = 61, "GenBank Accessions" = 2))))
  expect_false("sources" %in% unlist(small$stops))
  expect_setequal(unlist(small$checks$sources$detail$below_floor), c("Sequences 61 -> 43", "GenBank Accessions 2 -> 0"))
  # A source vanishing still stops, when it held enough records to matter.
  vanished <- check(list(iNaturalist = 100, "MO Observations" = 50, Sequences = 61))
  expect_true("sources" %in% unlist(vanished$stops))
  expect_match(vanished$checks$sources$why, "Sequences 61 -> 0")
})

test_that("uncached records stop the pull above 5%; the privacy list shrinking more than 5% does too", {
  pull <- qa_pull()
  uncached <- atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull, unknown = 9))
  expect_true("uncached" %in% unlist(uncached$stops))
  shrank <- atlas_qa_report(pull, list(stamp = "x"), privacy = qa_privacy(pull),
                            previous = list(detail = list(privacy_list = 10)))
  expect_true("privacy_list" %in% unlist(shrank$stops))
})

test_that("disagreeing sequence names rising a point, a drop-list row, or a source moving stop the pull", {
  pull <- qa_pull()
  naming <- atlas_qa_report(pull, list(stamp = "x"), audit = qa_audit(disagree = 30),
                            previous = list(checks = list(naming = list(value = 0.01))))
  expect_true("naming" %in% unlist(naming$stops))
  dropped <- atlas_qa_report(pull, list(stamp = "x"), exclusions = c("7", "MO Observations:5003"))
  expect_equal(dropped$checks$drop_list$value, 2L)
  expect_true("drop_list" %in% unlist(dropped$stops))
  moved <- atlas_qa_report(pull, list(stamp = "x"),
                           previous = list(detail = list(by_source = list(iNaturalist = 100, "MO Observations" = 70))))
  expect_true("sources" %in% unlist(moved$stops))
  expect_match(moved$checks$sources$why, "MO Observations 70 -> 50")
})

test_that("nothing is planned from a stopped pull unless its stop is accepted by name, for that pull", {
  with_data_dir({
    atlas_write_json(list(stamp = "20261101T070000Z"), atlas_path("occurrences", "latest.json", create = TRUE))
    report <- list(pull = "20261101T070000Z", stops = list("kingdom"),
                   checks = list(kingdom = list(stop = TRUE, why = "1 modelled names are not fungi: Turdus")))
    expect_error(atlas_qa_gate(report = report, quiet = TRUE), "stopped its QA: 1 modelled names are not fungi")
    expect_error(atlas_qa_gate(accept = "20261031T070000Z:kingdom", report = report, quiet = TRUE), "stopped its QA")
    expect_error(atlas_qa_gate(accept = "20261101T070000Z:keys", report = report, quiet = TRUE), "stopped its QA")
    accepted <- atlas_qa_gate(accept = "20261101T070000Z:kingdom", report = report, quiet = TRUE)
    expect_equal(accepted$accepted, list("kingdom"))
    # A report of another pull is not this pull's.
    expect_length(atlas_qa_gate(report = list(pull = "older", stops = list("kingdom")), quiet = TRUE), 0L)
  })
})

test_that("a QA report is written beside each pull and read as the last one by the next", {
  with_data_dir({
    pull <- qa_pull()
    first <- atlas_pull_qa(pull, list(stamp = "a"), kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = "Fungi"),
                           quiet = TRUE)
    expect_true(file.exists(atlas_qa_path("a")))
    expect_true(file.exists(atlas_qa_path()))
    second <- atlas_pull_qa(pull[1:120, ], list(stamp = "b"), quiet = TRUE)
    expect_true("sources" %in% unlist(second$stops))
  })
})

test_that("kingdoms come from the cache, a new name is looked up once, and an unplaced one is asked again later", {
  with_data_dir({
    asked <- character()
    lookup <- function(name) { asked <<- c(asked, name); if (name == "Turdus migratorius") "Animalia" else NA_character_ }
    k <- atlas_name_kingdoms(c("Turdus migratorius", "Nonesuch fungus"), lookup = lookup, today = as.Date("2026-11-01"))
    expect_equal(unname(k), c(NA, "Animalia"))
    expect_setequal(asked, c("Turdus migratorius", "Nonesuch fungus"))
    asked <- character()
    atlas_name_kingdoms(c("Turdus migratorius", "Nonesuch fungus"), lookup = lookup, today = as.Date("2026-11-10"))
    expect_length(asked, 0L)
    atlas_name_kingdoms(c("Turdus migratorius", "Nonesuch fungus"), lookup = lookup, today = as.Date("2026-12-15"))
    expect_equal(asked, "Nonesuch fungus")
    # With no lookup allowed (max_new 0), nothing is asked.
    asked <- character()
    atlas_name_kingdoms("Brand new name", lookup = lookup, max_new = 0L)
    expect_length(asked, 0L)
  })
})

test_that("the nightly plans nothing from a pull that stopped its QA", {
  with_data_dir({
    atlas_write_json(list(stamp = "20261101T070000Z"), atlas_path("occurrences", "latest.json", create = TRUE))
    atlas_write_json(list(pull = "20261101T070000Z", stops = list("keys"),
                          checks = list(keys = list(stop = TRUE, why = "3 records share a source:number key"))),
                     atlas_qa_path())
    planned <- FALSE
    local_mocked_bindings(atlas_plan_job = function(...) { planned <<- TRUE; NULL },
                          atlas_finish_on_ec2 = function(...) NULL)
    expect_error(atlas_nightly(pull = FALSE, config = list(max_workers = 4), store = list(), quiet = TRUE),
                 "3 records share a source:number key")
    expect_false(planned)
  })
})

test_that("a fill paces its lookups, stops at its cap, and keeps what it learned as it goes", {
  with_data_dir({
    waits <- numeric()
    asked <- character()
    lookup <- function(name) { asked <<- c(asked, name); "Fungi" }
    names <- sprintf("Genus species%02d", 1:7)
    atlas_name_kingdoms(names, lookup = lookup, max_new = 5L, pace_seconds = 0.2,
                        wait = function(s) waits <<- c(waits, s), save_every = 2L)
    expect_length(asked, 5L)
    # A pause between lookups, none before the first.
    expect_equal(waits, rep(0.2, 4))
    cached <- utils::read.delim(gzfile(atlas_kingdoms_path()), colClasses = "character")
    expect_setequal(cached$name, names[1:5])
    # The rest are asked by the next fill, the first five not again.
    asked <- character()
    atlas_name_kingdoms(names, lookup = lookup, max_new = 5L, wait = function(s) NULL)
    expect_setequal(asked, names[6:7])
  })
})

test_that("GBIF's \"slow down\" waits a minute and asks once more", {
  calls <- 0L
  waited <- numeric()
  local_mocked_bindings(curl_fetch_memory = function(url, handle) {
    calls <<- calls + 1L
    if (calls == 1L) list(status_code = 429L, content = raw()) else
      list(status_code = 200L, content = charToRaw('{"kingdom": "Fungi", "matchType": "EXACT", "rank": "SPECIES"}'))
  }, .package = "curl")
  expect_equal(atlas_gbif_kingdom("Amanita muscaria", wait = function(s) waited <<- c(waited, s)), "Fungi")
  expect_equal(calls, 2L)
  expect_equal(waited, 60)
})

# GBIF's answers as seen on 2026-11-04, trimmed, for the names that showed what a
# lookup has to get right (Picipes, Mycena's code and Cortinarius's alternatives are
# of that shape, not copied). plain is the name asked alone; hinted its genus at
# rank GENUS with a Fungi hint; verbose its genus's alternatives.
gbif_answers <- function() {
  answer <- function(matchType, kingdom = NULL, rank = NULL, phylum = NULL) {
    Filter(Negate(is.null), list(matchType = matchType, kingdom = kingdom, rank = rank, phylum = phylum))
  }
  none <- answer("NONE")
  list(
    plain = list(
      "Amanita muscaria" = answer("EXACT", "Fungi", "SPECIES", "Basidiomycota"),
      "Russula sp. 'IN1'" = answer("HIGHERRANK", "Fungi", "GENUS", "Basidiomycota"),
      "Agaricomycetes sp. 'NY01'" = answer("HIGHERRANK", "Fungi", "CLASS", "Basidiomycota"),
      "Peziza sp. 'OR02'" = answer("HIGHERRANK", "Fungi", "KINGDOM"),
      "Hydnum atlanticum" = answer("FUZZY", "Plantae", "SPECIES", "Bryophyta"),
      "Rolandia caroliniana" = answer("HIGHERRANK", "Animalia", "KINGDOM"),
      "Picipes sp. 'BC02'" = answer("HIGHERRANK", "Fungi", "GENUS", "Basidiomycota"),
      "Melanocarpum sp. 'PR01'" = answer("HIGHERRANK", "Plantae", "GENUS", "Tracheophyta"),
      "Juglans nigra" = answer("EXACT", "Plantae", "SPECIES", "Tracheophyta"),
      "Antennaria howellii" = answer("EXACT", "Plantae", "SPECIES", "Tracheophyta"),
      "Canis latrans" = answer("EXACT", "Animalia", "SPECIES", "Chordata"),
      "Protandrena labrosa" = answer("FUZZY", "Animalia", "SPECIES", "Arthropoda"),
      "Bacillus mycoides" = answer("EXACT", "Bacteria", "SPECIES", "Firmicutes"),
      "Fuligo septica" = answer("EXACT", "Protozoa", "SPECIES", "Mycetozoa"),
      "Lycogala sp. 'IN02'" = answer("HIGHERRANK", "Protozoa", "GENUS", "Mycetozoa"),
      "Trichia sp. 'BC01'" = none,
      "Lactarius sp. 'GA01'" = none,
      "Mycena sp. 'IN1'" = none,
      "Boletus sp. 'variipes-IN01'" = answer("HIGHERRANK", "Fungi", "KINGDOM"),
      "Neoporphyrellus alboater" = none,
      "Nonesuch thing" = none,
      "Nearby sp. 'X1'" = none,
      "Vagueness alone" = answer("HIGHERRANK", "Animalia", "KINGDOM")
    ),
    hinted = list(
      Hydnum = answer("EXACT", "Fungi", "GENUS", "Basidiomycota"),
      Tricholoma = answer("EXACT", "Fungi", "GENUS", "Basidiomycota"),
      Conocybe = answer("EXACT", "Fungi", "GENUS", "Basidiomycota"),
      Cortinarius = answer("HIGHERRANK", "Fungi", "FAMILY", "Basidiomycota"),
      Lactarius = answer("EXACT", "Fungi", "GENUS", "Basidiomycota"),
      Mycena = answer("EXACT", "Fungi", "GENUS", "Basidiomycota"),
      Peziza = answer("EXACT", "Fungi", "GENUS", "Ascomycota"),
      Trichia = answer("EXACT", "Protozoa", "GENUS", "Mycetozoa"),
      Boletus = answer("HIGHERRANK", "Fungi", "KINGDOM"),
      Rolandia = none, Protandrena = none, Neoporphyrellus = none, Nonesuch = none, Nearby = none, Vagueness = none
    ),
    verbose = list(
      Boletus = list(alternatives = data.frame(
        canonicalName = c("Boletus", "Boletus", "Bolerus"), rank = "GENUS", kingdom = c("Fungi", "Fungi", "Animalia"),
        phylum = c("Basidiomycota", "Basidiomycota", "Arthropoda"), stringsAsFactors = FALSE)),
      Cortinarius = list(alternatives = data.frame(
        canonicalName = c("Cortinarius", "Cortinarius"), rank = "GENUS", kingdom = c("Fungi", "Animalia"),
        phylum = c("Basidiomycota", "Arthropoda"), stringsAsFactors = FALSE)),
      Rolandia = list(alternatives = data.frame(
        canonicalName = "Rolandia", rank = "GENUS", kingdom = "Animalia", phylum = "Arthropoda", stringsAsFactors = FALSE)),
      Nearby = list(alternatives = data.frame(
        canonicalName = c("Nearby", "Nearbya"), rank = "GENUS", kingdom = c("Animalia", "Fungi"),
        phylum = c("Arthropoda", "Ascomycota"), stringsAsFactors = FALSE)),
      Protandrena = list(), Neoporphyrellus = list(), Nonesuch = list(), Vagueness = list()
    )
  )
}

local_gbif <- function(env = parent.frame()) {
  answers <- gbif_answers()
  asked <- new.env()
  asked$n <- 0L
  local_mocked_bindings(atlas_gbif_query = function(query, wait = NULL) {
    asked$n <- asked$n + 1L
    which <- if (identical(query$verbose, "true")) "verbose" else if (!is.null(query$kingdom)) "hinted" else "plain"
    found <- answers[[which]][[query$name]]
    if (is.null(found)) stop("not recorded: ", which, " ", query$name)
    found
  }, .env = env)
  asked
}

test_that("a kingdom is believed only when GBIF's answer is about the name", {
  local_gbif()
  kingdom <- function(name) as.vector(atlas_gbif_kingdom(name, wait = function(s) NULL))
  # An exact match, or a code answered for its genus or a rank above it.
  expect_equal(kingdom("Amanita muscaria"), "Fungi")
  expect_equal(kingdom("Russula sp. 'IN1'"), "Fungi")
  expect_equal(kingdom("Agaricomycetes sp. 'NY01'"), "Fungi")
  # A fuzzy match is not, when the genus says otherwise: Hydnum atlanticum is no
  # moss. Nor is a kingdom-level fallback, read for itself.
  expect_equal(kingdom("Hydnum atlanticum"), "Fungi")
  expect_equal(kingdom("Peziza sp. 'OR02'"), "Fungi")
  # A section's epithet is not asked: Candidae is a family of animals.
  expect_equal(kingdom("Tricholoma sect. Genuina"), "Fungi")
  expect_equal(kingdom("Conocybe sect. Candidae"), "Fungi")
  # A name that opens with its rank has no genus to ask.
  expect_true(is.na(kingdom("Subgenus Lentoramaria")))
  # Written in lower case, a genus is still a genus.
  expect_equal(kingdom("picipes sp. 'BC02'"), "Fungi")
})

test_that("a non-fungus is still found, by its own name or its genus", {
  local_gbif()
  kingdom <- function(name) as.vector(atlas_gbif_kingdom(name, wait = function(s) NULL))
  expect_equal(kingdom("Juglans nigra"), "Plantae")
  expect_equal(kingdom("Canis latrans"), "Animalia")
  expect_equal(kingdom("Bacillus mycoides"), "Bacteria")
  # A binomial settles it, though its genus is also a fungus's name.
  expect_equal(kingdom("Antennaria howellii"), "Plantae")
  # A misspelt bee: nothing else is known of its genus, so the fuzzy match stands.
  expect_equal(kingdom("Protandrena labrosa"), "Animalia")
  # Two false alarms the allow list answers, kept as they read: GBIF knows only
  # an animal Rolandia and a plant Melanocarpum.
  expect_equal(kingdom("Rolandia caroliniana"), "Animalia")
  expect_equal(kingdom("Melanocarpum sp. 'PR01'"), "Plantae")
})

test_that("a genus several kingdoms share is settled by its genus, not left unknown", {
  local_gbif()
  kingdom <- function(name) as.vector(atlas_gbif_kingdom(name, wait = function(s) NULL))
  expect_equal(kingdom("Lactarius sp. 'GA01'"), "Fungi")
  expect_equal(kingdom("Mycena sp. 'IN1'"), "Fungi")
  # Several fungal entries, so no single match: read from the alternatives,
  # and only those of exactly this genus.
  expect_equal(kingdom("Boletus sp. 'variipes-IN01'"), "Fungi")
  expect_equal(kingdom("Cortinarius sect. Sanguinei"), "Fungi")
  # A genus GBIF does not hold stays unknown; it is never guessed.
  expect_true(is.na(kingdom("Neoporphyrellus alboater")))
  expect_true(is.na(kingdom("Nonesuch thing")))
  # Another genus's name among the alternatives says nothing of this one.
  expect_equal(kingdom("Nearby sp. 'X1'"), "Animalia")
  # GBIF falling back to a kingdom, with nothing else known, is not an answer.
  expect_true(is.na(kingdom("Vagueness alone")))
})

test_that("slime moulds are named as such, at any step, and an unanswered question is never a guess", {
  asked <- local_gbif()
  kingdom <- function(name) as.vector(atlas_gbif_kingdom(name, wait = function(s) NULL))
  expect_equal(kingdom("Fuligo septica"), "Mycetozoa")
  expect_equal(kingdom("Lycogala sp. 'IN02'"), "Mycetozoa")
  expect_equal(kingdom("Trichia sp. 'BC01'"), "Mycetozoa")
  # GBIF down at any step: unknown.
  local_mocked_bindings(atlas_gbif_query = function(query, wait = NULL) NULL)
  expect_true(is.na(kingdom("Amanita muscaria")))
  steps <- 0L
  local_mocked_bindings(atlas_gbif_query = function(query, wait = NULL) {
    steps <<- steps + 1L
    if (steps == 1L) list(matchType = "NONE") else NULL
  })
  expect_true(is.na(kingdom("Lactarius sp. 'GA01'")))
})

test_that("each further question to GBIF waits its turn", {
  local_gbif()
  waits <- numeric()
  atlas_gbif_kingdom("Boletus sp. 'variipes-IN01'", wait = function(s) waits <<- c(waits, s), pace_seconds = 0.2)
  expect_equal(waits, c(0.2, 0.2))
  waits <- numeric()
  atlas_gbif_kingdom("Amanita muscaria", wait = function(s) waits <<- c(waits, s), pace_seconds = 0.2)
  expect_length(waits, 0L)
})

test_that("slime moulds pass the kingdom check and are counted; anything else not fungal stops it", {
  moulds <- report_of(kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = "Mycetozoa"))
  expect_length(moulds$stops, 0L)
  expect_equal(moulds$checks$kingdom$detail$slime_moulds, 1L)
  # Another protozoan is not a slime mould.
  other <- report_of(kingdoms = c("Amanita muscaria" = "Fungi", "Russula emetica" = "Protozoa"))
  expect_equal(unlist(other$stops), "kingdom")
  expect_match(other$checks$kingdom$why, "neither fungi nor slime moulds")
})

test_that("an answer from an earlier way of asking is asked again, and a new one is kept", {
  with_data_dir({
    # A cache as the first fill wrote it, with no lookup column, one answer wrong.
    atlas_write_tsv_gz(data.frame(name = c("Hydnum atlanticum", "Amanita muscaria"), kingdom = c("Plantae", "Fungi"),
                                  checked = "2026-11-04", stringsAsFactors = FALSE), atlas_kingdoms_path())
    asked <- character()
    lookup <- function(name) { asked <<- c(asked, name); "Fungi" }
    k <- atlas_name_kingdoms(c("Hydnum atlanticum", "Amanita muscaria"), lookup = lookup, today = as.Date("2026-11-05"))
    expect_setequal(asked, c("Hydnum atlanticum", "Amanita muscaria"))
    expect_equal(k[["Hydnum atlanticum"]], "Fungi")
    # Asked this way, they are kept, even an unknown, for its month.
    asked <- character()
    atlas_name_kingdoms(c("Hydnum atlanticum", "Amanita muscaria"), lookup = lookup, today = as.Date("2026-11-06"))
    expect_length(asked, 0L)
    # With no lookup allowed, an old answer still stands rather than being lost.
    atlas_write_tsv_gz(data.frame(name = "Hydnum atlanticum", kingdom = "Plantae", checked = "2026-11-04",
                                  stringsAsFactors = FALSE), atlas_kingdoms_path())
    held <- atlas_name_kingdoms("Hydnum atlanticum", lookup = lookup, max_new = 0L, today = as.Date("2026-11-06"))
    expect_equal(held[["Hydnum atlanticum"]], "Plantae")
  })
})

test_that("fill-kingdoms fills this machine's cache from a pull, at the cap and pace given", {
  with_data_dir({
    pull <- tempfile(fileext = ".tsv.gz")
    atlas_write_tsv_gz(transform(qa_pull(), latitude = "45", longitude = "-122"), pull)
    got <- NULL
    local_mocked_bindings(atlas_name_kingdoms = function(names, lookup, max_new, pace_seconds, wait, ...) {
      got <<- list(names = sort(unique(names)), max_new = max_new, pace = pace_seconds)
      stats::setNames(rep("Fungi", length(unique(names))), sort(unique(names)))
    })
    atlas_main(c("fill-kingdoms", paste0("--pull=", pull), "--cap=30000", "--pace-ms=500"))
    expect_equal(got$names, c("Amanita muscaria", "Russula emetica"))
    expect_equal(got$max_new, 30000L)
    expect_equal(got$pace, 0.5)
  })
})

test_that("a pull whose newest first validation is more than 3 days old stops: the mirror may have stopped", {
  pull <- qa_pull()
  pull$first_green_on <- "2026-10-20"
  pull$first_green_on[5] <- "2026-10-31"
  fresh <- atlas_qa_report(pull, list(stamp = "x", pulled_at = "2026-11-03T07:00:00Z"))
  expect_equal(fresh$checks$newest_green$value, 3L)
  expect_false("newest_green" %in% unlist(fresh$stops))
  stale <- atlas_qa_report(pull, list(stamp = "x", pulled_at = "2026-11-04T07:00:00Z"))
  expect_equal(stale$checks$newest_green$value, 4L)
  expect_true("newest_green" %in% unlist(stale$stops))
  expect_match(stale$checks$newest_green$why, "is the .com mirror refreshing")
  # A pull with no first-green dates, or no date of its own, has no such check.
  expect_null(atlas_qa_report(qa_pull(), list(stamp = "x", pulled_at = "2026-11-04T07:00:00Z"))$checks$newest_green)
})

# Names leaving the pull as exactly another kingdom (Steve, 2026-11-05).

gbif_species <- function(name, kingdom, phylum = "Tracheophyta", rank = "SPECIES", match = "EXACT") {
  list(matchType = match, kingdom = kingdom, phylum = phylum, rank = rank, canonicalName = name)
}

# GBIF as a plain question and as a question for a fungus of that name.
local_exact_gbif <- function(plain, fungus = list(matchType = "NONE"), env = parent.frame()) {
  local_mocked_bindings(atlas_gbif_query = function(query, wait = NULL) {
    if (!is.null(query$kingdom)) fungus else plain
  }, .env = env)
}

marked <- function(answer) identical(attr(answer, "match", exact = TRUE), ATLAS_QA_MATCH_EXACT)
ask_exact <- function(name) atlas_gbif_kingdom(name, wait = function(s) NULL)

left_out_kingdoms <- function(kingdoms, exact = names(kingdoms)) {
  attr(kingdoms, "exact") <- exact
  kingdoms
}

left_out_pull <- function(names, records = rep(1L, length(names))) {
  data.frame(id = as.character(seq_len(sum(records))), scientific_name = rep(names, records), stringsAsFactors = FALSE)
}

test_that("only a species matched exactly in another kingdom, with no fungus of that name, may leave the pull", {
  local_exact_gbif(gbif_species("Juglans nigra", "Plantae"))
  answer <- ask_exact("Juglans nigra")
  expect_equal(as.vector(answer), "Plantae")
  expect_true(marked(answer))
  # A fungus under the same name: read as fungi, never left out.
  local_exact_gbif(gbif_species("Juglans nigra", "Plantae"), fungus = gbif_species("Juglans nigra", "Fungi", "Ascomycota"))
  answer <- ask_exact("Juglans nigra")
  expect_equal(as.vector(answer), "Fungi")
  expect_false(marked(answer))
  # GBIF's hint not answered: flagged, so it stops the night, but not left out.
  local_exact_gbif(gbif_species("Juglans nigra", "Plantae"), fungus = NULL)
  answer <- ask_exact("Juglans nigra")
  expect_equal(as.vector(answer), "Plantae")
  expect_false(marked(answer))
  # A hint that does not change GBIF's answer changes nothing.
  local_exact_gbif(gbif_species("Juglans nigra", "Plantae"), fungus = gbif_species("Juglans nigra", "Plantae"))
  expect_true(marked(ask_exact("Juglans nigra")))
})

test_that("an exact match that is not this very species is flagged, not left out", {
  # As GBIF read these three real fungi, each EXACT and each in another kingdom.
  for (case in list(list("Morchella Distantes", "Distantes", "FAMILY"), list("Lentoramaria nova", "Lentoramaria", "GENUS"),
                    list("Picipes badius", "? picipes", "UNRANKED"))) {
    local_exact_gbif(gbif_species(case[[2]], "Animalia", "Arthropoda", rank = case[[3]]))
    expect_false(marked(ask_exact(case[[1]])))
  }
  # The right words at a rank that is no species.
  local_exact_gbif(gbif_species("Lentoramaria nova", "Animalia", "Arthropoda", rank = "GENUS"))
  expect_false(marked(ask_exact("Lentoramaria nova")))
  # EXACT at species rank, but of another name.
  local_exact_gbif(gbif_species("Juglans regia", "Plantae"))
  answer <- ask_exact("Juglans nigra")
  expect_equal(as.vector(answer), "Plantae")
  expect_false(marked(answer))
  # A variety is its species, however GBIF writes it.
  local_exact_gbif(gbif_species("Prunus persica nucipersica", "Plantae", rank = "VARIETY"))
  expect_true(marked(ask_exact("Prunus persica var. nucipersica")))
})

test_that("a code, a fuzzy match, slime moulds and fungi are never marked to leave", {
  # Melanocarpum sp. 'PR01' is a fungus GBIF answers only by a plant genus.
  local_exact_gbif(gbif_species("Melanocarpum", "Plantae", rank = "GENUS", match = "HIGHERRANK"))
  answer <- ask_exact("Melanocarpum sp. 'PR01'")
  expect_equal(as.vector(answer), "Plantae")
  expect_false(marked(answer))
  local_mocked_bindings(atlas_gbif_query = function(query, wait = NULL) {
    if (identical(query$verbose, "false")) gbif_species("Hypnum atlanticum", "Plantae", "Bryophyta", match = "FUZZY") else list(matchType = "NONE")
  })
  expect_false(marked(ask_exact("Hydnum atlanticum")))
  local_exact_gbif(gbif_species("Fuligo septica", "Protozoa", "Mycetozoa"))
  expect_false(marked(ask_exact("Fuligo septica")))
  local_exact_gbif(gbif_species("Amanita muscaria", "Fungi", "Basidiomycota"))
  expect_false(marked(ask_exact("Amanita muscaria")))
  # GBIF's word for no kingdom is no kingdom.
  local_exact_gbif(gbif_species("Dubia nomen", "incertae sedis", NULL))
  answer <- ask_exact("Dubia nomen")
  expect_true(is.na(answer))
  expect_false(marked(answer))
})

test_that("a name's mark to leave is kept in the cache, and an older answer never carries one", {
  with_data_dir({
    asked <- character()
    lookup <- function(name) {
      asked <<- c(asked, name)
      if (name == "Juglans nigra") structure("Plantae", match = ATLAS_QA_MATCH_EXACT) else "Plantae"
    }
    first <- atlas_name_kingdoms(c("Juglans nigra", "Melanocarpum sp. 'PR01'"), lookup = lookup)
    expect_equal(attr(first, "exact"), "Juglans nigra")
    expect_equal(first[["Melanocarpum sp. 'PR01'"]], "Plantae")
    asked <- character()
    again <- atlas_name_kingdoms(c("Juglans nigra", "Melanocarpum sp. 'PR01'"), lookup = lookup)
    expect_length(asked, 0L)
    expect_equal(attr(again, "exact"), "Juglans nigra")
    # Written by the last version, marked or not: its answer stands while it
    # waits its turn to be asked again, but nothing leaves on it.
    atlas_write_tsv_gz(data.frame(name = "Juglans nigra", kingdom = "Plantae", checked = "2026-11-04", lookup = "2",
                                  match = ATLAS_QA_MATCH_EXACT, stringsAsFactors = FALSE), atlas_kingdoms_path())
    held <- atlas_name_kingdoms("Juglans nigra", lookup = lookup, max_new = 0L)
    expect_equal(held[["Juglans nigra"]], "Plantae")
    expect_length(attr(held, "exact"), 0L)
  })
})

test_that("an exact plant leaves the pull; the allow list, slime moulds, unknowns and fungi stay", {
  names <- c("Juglans nigra", "Prunus persica", "Melanocarpum nomen", "Fuligo septica", "Amanita muscaria", "Unknown name", "Allowed plant")
  kingdoms <- left_out_kingdoms(
    stats::setNames(c("Plantae", "Plantae", "Plantae", "Mycetozoa", "Fungi", NA, "Plantae"), names),
    # Slime moulds, fungi and unknowns marked too: the kingdom still keeps them.
    exact = setdiff(names, "Melanocarpum nomen")
  )
  got <- atlas_kingdom_left_out(left_out_pull(names, c(2L, 1L, 1L, 1L, 1L, 1L, 1L)), kingdoms, allow = "Allowed plant")
  expect_setequal(got$kept$scientific_name, setdiff(names, c("Juglans nigra", "Prunus persica")))
  expect_equal(got$info$records, 3L)
  expect_equal(got$info$names$name, c("Juglans nigra", "Prunus persica"))
  expect_equal(got$info$names$kingdom, c("Plantae", "Plantae"))
  expect_equal(got$info$names$records, c(2L, 1L))
  # With no answers, or none left out, the pull is whole and the report says so.
  whole <- atlas_kingdom_left_out(left_out_pull(names), NULL)
  expect_equal(nrow(whole$kept), length(names))
  expect_equal(whole$info$records, 0L)
  expect_equal(nrow(whole$info$names), 0L)
})

test_that("the report names what left and what is new, and a plant that left does not stop the night", {
  pull <- qa_pull()
  kingdoms <- c("Amanita muscaria" = "Fungi", "Russula emetica" = "Fungi", "Juglans nigra" = "Plantae")
  left <- list(rule = ATLAS_QA_LEFT_OUT_RULE, records = 3L,
               names = data.frame(name = c("Juglans nigra", "Prunus persica"), kingdom = "Plantae", records = c(2L, 1L)))
  report <- report_of(pull, kingdoms = kingdoms, left_out = left)
  expect_length(report$stops, 0L)
  check <- report$checks$kingdom_left_out
  expect_equal(check$value, 3L)
  expect_equal(check$detail$left_out$name, c("Juglans nigra", "Prunus persica"))
  expect_equal(check$detail$rule, ATLAS_QA_LEFT_OUT_RULE)
  expect_setequal(unlist(check$detail$new), c("Juglans nigra", "Prunus persica"))
  # Against the last pull, as the file reads back: only the newcomer is new.
  written <- tempfile(fileext = ".json")
  atlas_write_json(report_of(pull, left_out = list(rule = "r", records = 2L, names = left$names[1, ])), written)
  previous <- jsonlite::fromJSON(written, simplifyVector = TRUE)
  expect_equal(unlist(report_of(pull, left_out = left, previous = previous)$checks$kingdom_left_out$detail$new), "Prunus persica")
  # None left this pull: reported as none.
  empty <- list(rule = "r", records = 0L, names = data.frame(name = character(), kingdom = character(), records = integer()))
  none <- report_of(pull, left_out = empty, previous = previous)
  expect_equal(none$checks$kingdom_left_out$value, 0L)
  expect_length(none$stops, 0L)
  # Nothing else about a stop has changed: another kingdom still in the pull stops it.
  expect_equal(unlist(report_of(pull, kingdoms = c("Amanita muscaria" = "Plantae"), left_out = left)$stops), "kingdom")
})

test_that("too many records left out, or too many of one name, stop the night, as a fault would look", {
  pull <- qa_pull()
  many <- function(records) {
    n <- ceiling(records / 10)
    r <- rep(10L, n)
    r[[n]] <- records - 10L * (n - 1L)
    list(rule = "r", records = as.integer(records), names = data.frame(name = paste("Plant", seq_len(n)), kingdom = "Plantae", records = r))
  }
  expect_length(report_of(pull, left_out = many(ATLAS_QA_THRESHOLDS$left_out_records))$stops, 0L)
  over <- report_of(pull, left_out = many(ATLAS_QA_THRESHOLDS$left_out_records + 1L))
  expect_equal(unlist(over$stops), "kingdom_left_out")
  expect_match(over$checks$kingdom_left_out$why, "301 records of 31 names")
  one <- function(n) list(rule = "r", records = n, names = data.frame(name = "Amanita muscaria", kingdom = "Plantae", records = n))
  expect_length(report_of(pull, left_out = one(ATLAS_QA_THRESHOLDS$left_out_name_records))$stops, 0L)
  big <- report_of(pull, left_out = one(ATLAS_QA_THRESHOLDS$left_out_name_records + 1L))
  expect_equal(unlist(big$stops), "kingdom_left_out")
  expect_match(big$checks$kingdom_left_out$why, "Amanita muscaria")
  # And a stop plans nothing, as any other does.
  with_data_dir({
    atlas_write_json(list(stamp = "x"), atlas_path("occurrences", "latest.json", create = TRUE))
    over$pull <- "x"
    expect_error(atlas_qa_gate(report = over, quiet = TRUE), "is the kingdom lookup at fault")
  })
})

test_that("a pull leaves the exact names out before it is written, and says so privately", {
  records <- transform(fake_occurrences(), scientific_name = c("Amanita muscaria", "Amanita muscaria", "Juglans nigra"))
  text <- function(df) paste(c(paste(names(df), collapse = "\t"), do.call(paste, c(df, sep = "\t"))), collapse = "\n")
  pull <- function() {
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
      if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
      if (startsWith(sql, "SELECT o.id, s.species_name")) {
        return(text(data.frame(id = records$id, species_name = records$scientific_name)))
      }
      if (grepl("not_yet_validated", sql, fixed = TRUE)) return("name\tnot_yet_validated\n")
      if (grepl("max(id)", sql, fixed = TRUE)) return("top\n1\n")
      if (grepl("AS privacy", sql, fixed = TRUE)) return("source\tobservation_id\tprivacy\n")
      text(records)
    })
    atlas_pull_occurrences(host = "test", quiet = TRUE)
  }
  with_data_dir({
    atlas_name_kingdoms(c("Amanita muscaria", "Juglans nigra"), lookup = function(name) {
      if (name == "Juglans nigra") structure("Plantae", match = ATLAS_QA_MATCH_EXACT) else "Fungi"
    })
    manifest <- pull()
    kept <- atlas_read_occurrences()
    expect_false("Juglans nigra" %in% kept$scientific_name)
    expect_equal(nrow(kept), 2L)
    expect_equal(manifest$records, 2L)
    expect_equal(manifest$fingerprint, atlas_fingerprint(kept))
    expect_false("Juglans nigra" %in% jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))$scientific_name)
    expect_equal(manifest$kingdom_left_out$records, 1L)
    expect_equal(manifest$kingdom_left_out$names$name, "Juglans nigra")
    # The release's summary of a pull does not publish it.
    expect_false("kingdom_left_out" %in% names(atlas_release_pull_summary(manifest)))
    report <- jsonlite::fromJSON(atlas_qa_path())
    expect_length(report$stops, 0L)
    expect_equal(report$checks$kingdom_left_out$detail$left_out$name, "Juglans nigra")
    expect_match(jsonlite::fromJSON(atlas_left_out_notice_path())$message, "Juglans nigra (Plantae, 1)", fixed = TRUE)
    # On the allow list it comes back with the next pull, and no stop is left.
    writeLines("Juglans nigra", atlas_kingdom_allow_path())
    back <- pull()
    expect_true("Juglans nigra" %in% atlas_read_occurrences()$scientific_name)
    expect_equal(back$kingdom_left_out$records, 0L)
    expect_false(any(c("kingdom", "kingdom_left_out") %in% jsonlite::fromJSON(atlas_qa_path())$stops))
    unlink(atlas_kingdom_allow_path())
    # A kingdom cache that cannot be read: nothing left out, and the night stops.
    local_mocked_bindings(atlas_pull_kingdoms = function(names) stop("cache unreadable"))
    expect_warning(failed <- pull(), "cache unreadable")
    expect_true("Juglans nigra" %in% atlas_read_occurrences()$scientific_name)
    expect_equal(failed$kingdom_left_out$records, 0L)
    expect_equal(jsonlite::fromJSON(atlas_qa_path())$stops, "qa_failed")
  })
})

test_that("the note for the login banner gathers new names until someone clears it", {
  rows <- data.frame(name = c("Juglans nigra", "Prunus persica"), kingdom = "Plantae", records = c(2L, 1L))
  read <- function() jsonlite::fromJSON(atlas_left_out_notice_path())
  with_data_dir({
    # No new name: no note.
    atlas_note_left_out(rows, character())
    expect_false(file.exists(atlas_left_out_notice_path()))
    atlas_note_left_out(rows, "Juglans nigra", now = as.POSIXct("2026-11-05 07:00:00", tz = "UTC"))
    expect_equal(read()$state, "notice")
    expect_equal(read()$since, "2026-11-05T07:00:00Z")
    expect_match(read()$message, "1 names left the pull as not fungi: Juglans nigra (Plantae, 2)", fixed = TRUE)
    # The next new name joins it, and it stays dated from the first.
    atlas_note_left_out(rows, "Prunus persica", now = as.POSIXct("2026-11-06 07:00:00", tz = "UTC"))
    expect_equal(read()$since, "2026-11-05T07:00:00Z")
    expect_match(read()$message, "2 names left", fixed = TRUE)
    expect_match(read()$message, "Juglans nigra (Plantae, 2), Prunus persica (Plantae, 1)", fixed = TRUE)
    # A long list points at the report rather than filling the banner.
    long <- data.frame(name = paste("Plant", 1:25), kingdom = "Plantae", records = 1L)
    atlas_note_left_out(long, long$name)
    expect_match(read()$message, "27 names left", fixed = TRUE)
    expect_match(read()$message, "and 7 more (qa-latest.json)", fixed = TRUE)
    # Once cleared (alert.sh --ok writes state ok), a new name starts a new note.
    jsonlite::write_json(list(check = "pull-left-out", state = "ok", since = "x", checked = "x"), atlas_left_out_notice_path(), auto_unbox = TRUE)
    atlas_note_left_out(rows, "Prunus persica", now = as.POSIXct("2026-11-07 07:00:00", tz = "UTC"))
    expect_equal(read()$since, "2026-11-07T07:00:00Z")
    expect_match(read()$message, "^1 names left")
    # A note that cannot be written warns; the report still stands.
    local_mocked_bindings(atlas_note_left_out = function(...) stop("disk full"))
    pull <- qa_pull()
    left <- list(rule = "r", records = 1L, names = rows[1, ])
    expect_warning(report <- atlas_pull_qa(pull, list(stamp = "n"), left_out = left, quiet = TRUE), "left-out note not written")
    expect_true(file.exists(atlas_qa_path("n")))
    expect_length(report$stops, 0L)
  })
})

test_that("the login banner shows the note as written, and alert.sh clears it", {
  alert <- normalizePath(test_path("..", "..", "deploy", "lightsail", "alert.sh"), winslash = "/", mustWork = FALSE)
  # On Windows a bare "bash" is WSL's, which cannot read a Windows path.
  bash <- if (.Platform$OS.type == "windows") "C:/Program Files/Git/bin/bash.exe" else Sys.which("bash")
  skip_if(!file.exists(alert) || !nzchar(bash) || !file.exists(bash), "needs bash and the deploy directory")
  with_data_dir({
    rows <- data.frame(name = "Hydnum d'Or", kingdom = "Plantae", records = 1L)
    atlas_note_left_out(rows, rows$name, now = as.POSIXct("2026-11-05 07:00:00", tz = "UTC"))
    dir <- dirname(atlas_left_out_notice_path())
    Sys.setenv(ATLAS_HEALTH_DIR = normalizePath(dir, winslash = "/"))
    on.exit(Sys.unsetenv("ATLAS_HEALTH_DIR"), add = TRUE)
    run <- function(...) suppressWarnings(system2(bash, c(shQuote(alert), ...), stdout = TRUE, stderr = TRUE))
    banner <- run("--summary")
    expect_length(banner, 1L)
    expect_match(banner, "^ATLAS: pull-left-out since 2026-11-05T07:00:00Z: 1 names left the pull as not fungi: Hydnum d'Or \\(Plantae, 1\\)")
    expect_match(banner, "alert.sh --ok pull-left-out$")
    run("--ok", "pull-left-out")
    expect_length(run("--summary"), 0L)
    expect_equal(jsonlite::fromJSON(atlas_left_out_notice_path())$state, "ok")
  })
})
