# The new-find tracker (R/tracker.R): records validated after a map was made,
# scored on it. The ledger of finds is private; only counts are published.

# Two releases: R1 promoted on 1 October, R2 on 5 October, each pulled an
# hour before. Both map "Amanita one" (strong, rising east) and know a
# record of it at column 15; R2 also knows "Boletus two" without a map.
two_releases <- function(store, scheme = "shift") {
  known <- rbind(tracker_records("Amanita one", 15, ids = "k1"),
                 tracker_records("Amanita one", 16, ids = "k2"))
  tracker_release(store, "R1", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z", known,
                  list(tracker_model(store, "Amanita one", scheme = scheme)), current = FALSE)
  known2 <- rbind(known, tracker_records("Boletus two", 5, ids = "k3"))
  tracker_release(store, "R2", "2026-10-05T07:00:00Z", "2026-10-05T08:00:00Z", known2,
                  list(tracker_model(store, "Amanita one", scheme = scheme)))
}

test_that("a find is scored against the release live when its first-green day began", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- rbind(
    tracker_records("Amanita one", 18, ids = "before", first_green_on = "2026-09-30"),
    # R2 was promoted during 5 October: that day's finds go against R1.
    tracker_records("Amanita one", 18, ids = "same-day", first_green_on = "2026-10-05"),
    tracker_records("Amanita one", 18, ids = "next-day", first_green_on = "2026-10-06"),
    tracker_records("Amanita one", 18, ids = "unvalidated", first_green_on = NA)
  )
  result <- tracker_run(store, finds, since = "2026-09-01")
  expect_equal(ledger_row(result, "iNaturalist:before")$status, "no_release")
  expect_equal(ledger_row(result, "iNaturalist:same-day")$release, "R1")
  expect_equal(ledger_row(result, "iNaturalist:next-day")$release, "R2")
  expect_false("iNaturalist:unvalidated" %in% result$ledger$key)
  # Finds first green before the start date are not counted at all.
  store <- fresh_store()
  two_releases(store)
  later <- tracker_run(store, finds, since = "2026-10-06")
  expect_equal(later$ledger$key, "iNaturalist:next-day")
})

test_that("the release chosen for a day is the last promoted before the day began", {
  promotions <- data.frame(release = c("A", "B", "C"),
                           promoted_at = c("2026-10-01T08:00:00Z", "2026-10-02T23:59:59Z", "2026-10-03T00:00:00Z"))
  expect_equal(atlas_tracker_live_at(c("2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"), promotions),
               c(NA, "A", "B", "C"))
})

test_that("a release whose pull is not older than the find is never used; the run only warns", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  # Promoted before 3 October began, but its pull says 3 October: a record
  # first green on the 3rd could be in it.
  tracker_release(store, "odd", "2026-10-03T07:00:00Z", "2026-10-02T08:00:00Z",
                  tracker_records("Amanita one", 15, ids = "k1"), list(tracker_model(store, "Amanita one")))
  finds <- tracker_records("Amanita one", 18, ids = "f1", first_green_on = "2026-10-03")
  dir <- machine()
  expect_error(tracker_run(store, finds, dir = dir, since = "2026-10-01"), "not before every find")
  expect_warning(
    on_machine(dir, atlas_track_new_finds_quietly(store, occurrences = finds, since = "2026-10-01",
                                                  quiet = TRUE, frozen = "")),
    "tracker did not run")
  expect_false(store$exists(atlas_tracker_key("draft")))
})

test_that("a find already in its release's pull is never scored", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- tracker_records("Amanita one", 15, ids = "k1", first_green_on = "2026-10-06")
  result <- tracker_run(store, finds, since = "2026-10-01")
  row <- ledger_row(result, "iNaturalist:k1")
  expect_equal(row$status, "in_release_pull")
  expect_true(is.na(row$rank))
  expect_equal(result$summary$finds$by_status$in_release_pull, 1L)
})

test_that("a find's rank is the drawn map's rank at its cell", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- tracker_records("Amanita one", c(3, 11, 20), ids = c("w", "m", "e"), first_green_on = "2026-10-06")
  result <- tracker_run(store, finds, since = "2026-10-01")
  layers <- atlas_map_layers(tracker_surface())
  expected <- terra::extract(layers[["rank"]], tracker_xy(c(3, 11, 20)))$rank
  got <- result$ledger$rank[match(paste0("iNaturalist:", c("w", "m", "e")), result$ledger$key)]
  expect_equal(got, round(expected, 4))
  # A column of cells ties, so the eastmost column shares the top ranks.
  expect_true(got[[1]] < got[[2]] && got[[2]] < got[[3]])
  expect_gt(got[[3]], 0.95)
  expect_true(all(result$ledger$place == "inside"))
  # No dissimilarity layer: the release has no area of applicability to test.
  expect_true(all(result$ledger$aoa == "unknown"))
  expect_equal(result$ledger$kind, rep("best_model", 3))
})

test_that("outside the area of applicability, and beyond reach, get no rank and are counted apart", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  model <- tracker_model(store, "Amanita one", dissimilarity = tracker_dissimilarity())
  tracker_release(store, "R1", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z",
                  tracker_records("Amanita one", 15, ids = "k1"), list(model))
  finds <- tracker_records("Amanita one", c(1, 5, 11, 20), ids = c("far", "west", "east1", "east2"),
                           first_green_on = "2026-10-02")
  result <- tracker_run(store, finds, since = "2026-10-01")
  row <- function(id) ledger_row(result, paste0("iNaturalist:", id))
  expect_equal(row("far")$place, "beyond_reach")
  expect_equal(row("west")$place, "outside_aoa")
  expect_true(is.na(row("far")$rank))
  expect_true(is.na(row("west")$rank))
  # Ranked among the cells inside the area only, as the map draws them.
  layers <- atlas_map_layers(tracker_surface(), tracker_dissimilarity(), 1)
  expected <- terra::extract(layers[["rank"]], tracker_xy(c(11, 20)))$rank
  expect_equal(c(row("east1")$rank, row("east2")$rank), round(expected, 4))
  expect_lt(row("east1")$rank, 0.06)
  expect_true(all(result$ledger$aoa == "known"))
})

test_that("a strong taxon is scored on the map an app shows; any other on its models' mean", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  falling <- tracker_surface(function(col) -col)
  models <- list(
    # Two strong models and their combined map, which ranks the west highest.
    tracker_model(store, "Combined one", "maxnet"),
    tracker_model(store, "Combined one", "rf"),
    # One strong model beside a weak one that disagrees.
    tracker_model(store, "Single one", "maxnet", strength = 0.9),
    tracker_model(store, "Single one", "rf", grade = "weak", surface = falling),
    # Weak and failed only: the mean of the two, which cancel to the middle.
    tracker_model(store, "Faint one", "maxnet", grade = "weak"),
    tracker_model(store, "Faint one", "rf", grade = "failed", surface = falling)
  )
  ensemble <- tracker_ensemble(store, "Combined one", c("maxnet", "rf"))
  known <- rbind(tracker_records("Combined one", 15), tracker_records("Single one", 15),
                 tracker_records("Faint one", 15))
  tracker_release(store, "R1", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z", known, models,
                  extra_files = ensemble$files)
  finds <- rbind(tracker_records("Combined one", 20, ids = "c"),
                 tracker_records("Single one", 20, ids = "s"),
                 tracker_records("Faint one", 20, ids = "f"))
  finds$first_green_on <- "2026-10-02"
  result <- tracker_run(store, finds, since = "2026-10-01")
  row <- function(id) ledger_row(result, paste0("iNaturalist:", id))
  expect_equal(row("c")$kind, "ensemble")
  expect_lt(row("c")$rank, 0.05)
  expect_gt(row("c")$rank_maxnet, 0.95)
  expect_equal(row("s")$kind, "best_model")
  expect_gt(row("s")$rank, 0.95)
  expect_equal(row("s")$grade, "strong")
  expect_equal(row("f")$kind, "mean")
  expect_equal(row("f")$rank, 0.5)
  expect_equal(row("f")$grade, "weak")
})

test_that("the best map is chosen by the same rule as the app's", {
  m <- function(grade, strength, auc) list(metrics = list(map_strength = strength, auc_mean = auc, bounds = list()),
                                           grade = grade)
  # Map strength first, then AUC; never AUC alone.
  expect_equal(atlas_best_rule(list(maxnet = m("strong", 0.6, 0.9), rf = m("strong", 0.9, 0.7)))$algorithm, "rf")
  expect_equal(atlas_best_rule(list(maxnet = m("strong", 0.9, 0.9), rf = m("strong", 0.9, 0.7)))$algorithm, "maxnet")
  expect_null(atlas_best_rule(list(maxnet = m("weak", 0.9, 0.9))))
  ensemble <- list(bounds = list(), members = list(list(algorithm = "maxnet", weight = 0.2),
                                                   list(algorithm = "rf", weight = 0.3)))
  both <- list(maxnet = m("strong", 0.6, 0.9), rf = m("strong", 0.9, 0.7))
  expect_equal(atlas_best_rule(both, ensemble)$kind, "ensemble")
  # A combined map whose members are no longer both strong is not the answer.
  expect_equal(atlas_best_rule(list(maxnet = m("weak", 0.6, 0.9), rf = m("strong", 0.9, 0.7)), ensemble)$kind, "model")
})

test_that("a release from before DNA naming scores a find by its record's own name", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  # A release fitted on record names (its pull has no record_name column).
  tracker_release(store, "R1", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z",
                  tracker_records("Tubaria sp. 'IN01'", 15),
                  list(tracker_model(store, "Tubaria sp. 'IN01'", scheme = "skill")))
  # The newest pull names it by its DNA, Tubaria hiemalis, and keeps the record name.
  finds <- rbind(
    tracker_records("Tubaria hiemalis", 20, ids = "t", first_green_on = "2026-10-02", record_name = "Tubaria sp. 'IN01'"),
    tracker_records("Nothing known", 20, ids = "n", first_green_on = "2026-10-02", record_name = "Nothing knownii")
  )
  result <- tracker_run(store, finds, since = "2026-10-01")
  t <- ledger_row(result, "iNaturalist:t")
  expect_equal(t$status, "scored")
  expect_equal(t$taxon, "Tubaria sp. 'IN01'")
  expect_equal(t$naming, "record")
  expect_equal(t$scheme, "skill")
  expect_equal(t$grade, "passed")
  expect_equal(ledger_row(result, "iNaturalist:n")$status, "not_in_release")
})

test_that("a taxon the release knows without a map is no_map, not missing from it", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- tracker_records("Boletus two", 6, ids = "b", first_green_on = "2026-10-06")
  result <- tracker_run(store, finds, since = "2026-10-01")
  row <- ledger_row(result, "iNaturalist:b")
  expect_equal(row$status, "no_map")
  expect_equal(row$band, "under_100")
})

test_that("a new site is new for its taxon; new ground for anyone is counted apart", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- rbind(
    # In the cell of a known Amanita record: neither a new site nor new ground.
    tracker_records("Amanita one", 16, ids = "near", first_green_on = "2026-10-06"),
    # In the cell where only Boletus two was known: a new site for Amanita,
    # but not new ground.
    tracker_records("Amanita one", 5, ids = "boletus-cell", first_green_on = "2026-10-06"),
    tracker_records("Amanita one", 8, row = 3, ids = "fresh", first_green_on = "2026-10-06")
  )
  result <- tracker_run(store, finds, since = "2026-10-01")
  row <- function(id) ledger_row(result, paste0("iNaturalist:", id))
  expect_false(row("near")$new_site)
  expect_false(row("near")$new_area)
  expect_true(row("boletus-cell")$new_site)
  expect_false(row("boletus-cell")$new_area)
  expect_true(row("fresh")$new_site)
  expect_true(row("fresh")$new_area)
  expect_equal(row("near")$band, "under_100")
  expect_equal(atlas_tracker_band(c(99, 100, 499.9, 500, NA)),
               c("under_100", "100_500", "100_500", "500_plus", "none"))
})

test_that("a find is scored once; one the pull drops or renames is retracted, and restored when it returns", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- tracker_records("Amanita one", c(18, 19), ids = c("a", "b"), first_green_on = "2026-10-06")
  dir <- machine()
  first <- tracker_run(store, finds, dir = dir, since = "2026-10-01", now = as.POSIXct("2026-10-07 06:00", tz = "UTC"))
  expect_equal(nrow(first$ledger), 2L)
  # The next day: "a" lost its green (gone from the pull), "b" is renamed.
  next_day <- finds[finds$observation_id == "b", ]
  next_day$scientific_name <- "Amanita other"
  second <- tracker_run(store, next_day, dir = machine(), since = "2026-10-01", now = as.POSIXct("2026-10-08 06:00", tz = "UTC"))
  expect_equal(nrow(second$ledger), 2L)
  expect_equal(ledger_row(second, "iNaturalist:a")$retracted_why, "no longer in the pull")
  expect_equal(ledger_row(second, "iNaturalist:b")$retracted_why, "renamed")
  expect_equal(ledger_row(second, "iNaturalist:a")$retracted_on, "2026-10-08")
  # Still scored against the release it first was: never re-scored.
  expect_equal(ledger_row(second, "iNaturalist:b")$release, "R2")
  expect_equal(second$summary$finds$retracted, 2L)
  third <- tracker_run(store, finds, dir = machine(), since = "2026-10-01", now = as.POSIXct("2026-10-09 06:00", tz = "UTC"))
  expect_true(all(is.na(third$ledger$retracted_on)))
  expect_equal(nrow(third$ledger), 2L)
  # The store holds the ledger: a machine whose data directory was replaced
  # (a release cutover) carries on from it.
  expect_equal(nrow(atlas_tracker_read_table(on_machine(dir, atlas_tracker_local()))), 2L)
})

test_that("the live release is recorded at every run", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  dir <- machine()
  tracker_run(store, tracker_records("Amanita one", 18, first_green_on = "2026-10-06"), dir = dir, since = "2026-10-01")
  tracker_run(store, tracker_records("Amanita one", 18, first_green_on = "2026-10-06"), dir = dir, since = "2026-10-01")
  runs <- on_machine(dir, atlas_tracker_load(store, "draft", "runs.tsv.gz"))
  expect_equal(nrow(runs), 2L)
  expect_equal(runs$current_release, c("R2", "R2"))
  expect_equal(runs$current_promoted_at, c("2026-10-05T08:00:00Z", "2026-10-05T08:00:00Z"))
  # What a run saw is itself a promotion record, should the store lose one.
  promotions <- atlas_tracker_promotions(NULL, "draft", runs, frozen = "")
  expect_equal(promotions$release, "R2")
})

test_that("the frozen promotion history is in order and names real release ids", {
  frozen <- jsonlite::fromJSON(atlas_tracker_promotions_file("draft", testthat::test_path("..", "..")))$promotions
  expect_gt(nrow(frozen), 0)
  expect_true(all(grepl("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$", frozen$release)))
  expect_false(is.unsorted(frozen$promoted_at))
  expect_equal(atlas_tracker_live_at("2026-10-08", frozen), "20261007T085351Z-89ef2317")
  expect_equal(atlas_tracker_live_at("2026-10-07", frozen), "20261006T082050Z-d5bb064c")
})

# ---- statistics --------------------------------------------------------------

test_that("Boyce: finds that follow the ranks score near 1, finds that ignore them near 0", {
  set.seed(1)
  following <- stats::rbeta(4000, 4, 1)
  ignoring <- stats::runif(4000)
  expect_gt(atlas_tracker_boyce(following), 0.9)
  expect_lt(abs(atlas_tracker_boyce(ignoring)), 0.5)
  expect_true(is.na(atlas_tracker_boyce(0.5)))
})

test_that("simulated finds: habitat signal beats the effort baseline, effort alone does not", {
  # A synthetic landscape of 2,000 cells with a true habitat (h) and where
  # people look (effort). The map ranks cells by h. Finds of a species with
  # a real response come where it lives among the places people look; finds
  # of one that ignores habitat come wherever people look. Effort favours
  # good habitat, as surveyors do, so the uniform Boyce flatters both; the
  # effort-corrected one tells them apart.
  set.seed(42)
  n <- 2000
  h <- stats::runif(n)
  rank <- atlas_rank_scale(h)
  effort <- exp(2 * h)
  draw <- function(weight, k) sample.int(n, k, replace = TRUE, prob = weight)
  real <- rank[draw(effort * h^3, 600)]
  blind <- rank[draw(effort, 600)]
  looked <- rank[draw(effort, 3000)]
  expected <- tabulate(pmin(100L, floor(looked * 100) + 1L), nbins = 100L)
  expect_gt(atlas_tracker_boyce(blind), 0.5)
  expect_lt(atlas_tracker_boyce(blind, expected), 0.5)
  expect_gt(atlas_tracker_boyce(real, expected), 0.7)
  beats <- function(x) mean(vapply(x, function(r) (sum(looked < r) + 0.5 * sum(looked == r)) / length(looked), 0))
  expect_lt(abs(beats(blind) - 0.5), 0.05)
  expect_gt(beats(real), 0.6)
})

test_that("pooled shares wait for 30 ranked places and Boyce for 50; a place is a taxon's cell in a window", {
  finds <- function(n, cells = seq_len(n)) {
    data.frame(key = paste0("k", seq_len(n)), release = "R", taxon = "T", cell = cells,
               rank = seq(0, 1, length.out = n), place = "inside", aoa = "known", stringsAsFactors = FALSE)
  }
  small <- atlas_tracker_row(finds(29), data.frame(key = character(), tg_percentile = numeric()), list())
  expect_null(small$top_half)
  expect_equal(small$ranked, 29L)
  enough <- atlas_tracker_row(finds(30), data.frame(key = character(), tg_percentile = numeric()), list())
  expect_equal(enough$top_half, 0.5)
  expect_length(enough$top_half_ci, 2)
  expect_null(enough$boyce)
  expect_false(is.null(atlas_tracker_row(finds(50), data.frame(key = character(), tg_percentile = numeric()), list())$boyce))
  # Forty finds in four cells are four places.
  clustered <- atlas_tracker_row(finds(40, rep(1:4, each = 10)), data.frame(key = character(), tg_percentile = numeric()), list())
  expect_equal(clustered$places, 4L)
  expect_equal(clustered$finds, 40L)
})

test_that("per-taxon tallies under five finds say only 'fewer than 5'", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  few <- tracker_records("Amanita one", 17:20, first_green_on = "2026-10-06")
  result <- tracker_run(store, few, since = "2026-10-01")
  tally <- result$summary$taxa[[1]]
  expect_equal(tally$finds_text, "fewer than 5")
  expect_null(tally$finds)
  expect_null(tally$top_half)
  for_page <- atlas_tracker_for(result$summary, "Amanita one")
  expect_setequal(names(for_page), c("since", "finds_text"))

  five <- tracker_records("Amanita one", 16:20, first_green_on = "2026-10-06")
  result <- tracker_run(store, five, since = "2026-10-01")
  tally <- result$summary$taxa[[1]]
  expect_equal(tally$finds, 5L)
  # The first four were dropped by this pull (retracted): only the five count.
  live <- result$ledger[is.na(result$ledger$retracted_on), ]
  expect_equal(nrow(live), 5L)
  expect_equal(tally$top_half, sum(live$rank >= 0.5))
})

test_that("the summary keeps old-scheme and new-scheme releases apart, and headlines new sites", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  tracker_release(store, "old", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z",
                  tracker_records("Amanita one", 15), list(tracker_model(store, "Amanita one", scheme = "skill")),
                  current = FALSE)
  tracker_release(store, "new", "2026-10-05T07:00:00Z", "2026-10-05T08:00:00Z",
                  tracker_records("Amanita one", 15), list(tracker_model(store, "Amanita one", scheme = "shift")))
  finds <- rbind(tracker_records("Amanita one", 3:20, rows = 2, first_green_on = "2026-10-02"),
                 tracker_records("Amanita one", 3:20, rows = 4, first_green_on = "2026-10-03"),
                 tracker_records("Amanita one", 3:20, rows = 6, first_green_on = "2026-10-06"),
                 tracker_records("Amanita one", 3:20, rows = 8, first_green_on = "2026-10-07"))
  summary <- tracker_run(store, finds, since = "2026-10-01")$summary
  schemes <- unique(vapply(summary$rows, `[[`, "", "scheme"))
  expect_setequal(schemes, c("shift", "skill"))
  skill_grades <- unique(vapply(Filter(function(r) r$scheme == "skill", summary$rows), `[[`, "", "grade"))
  expect_true(all(skill_grades %in% c("any", "passed", "failed", "untested")))
  expect_equal(summary$headline$scheme, "shift")
  expect_equal(summary$headline$grade, "strong")
  expect_equal(summary$headline$subset, "new_site")
  expect_equal(summary$headline$places, 36L)
  expect_equal(summary$current_release$id, "new")
})

# ---- privacy -----------------------------------------------------------------

test_that("nothing published carries a record id or a coordinate; the ledger stays private", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- tracker_records("Amanita one", 3:20, rows = 2, ids = paste0("secret", 1:18), first_green_on = "2026-10-06")
  dir <- machine()
  result <- tracker_run(store, finds, dir = dir, since = "2026-10-01")

  keys <- sub("^/", "", store$list(""))
  private <- keys[grepl("ledger[.]tsv|runs[.]tsv", keys)]
  expect_setequal(private, c("private/tracker/draft/ledger.tsv.gz", "private/tracker/draft/runs.tsv.gz"))
  expect_true(store$exists(atlas_tracker_summary_key()))

  published <- c(on_machine(dir, readLines(atlas_tracker_summary_path(), warn = FALSE)),
                 jsonlite::toJSON(on_machine(dir, atlas_tracker_answer()), auto_unbox = TRUE, null = "null"),
                 jsonlite::toJSON(atlas_tracker_for(result$summary, "Amanita one"), auto_unbox = TRUE))
  text <- paste(published, collapse = "\n")
  expect_false(grepl("secret", text))
  for (lat in finds$latitude) expect_false(grepl(substr(lat, 1, 6), text, fixed = TRUE))
  json_keys <- function(x) if (is.list(x)) c(names(x), unlist(lapply(x, json_keys))) else character()
  forbidden <- c("key", "observation_id", "source", "lat", "lng", "latitude", "longitude", "cell", "nearest_km", "x", "y")
  expect_equal(intersect(json_keys(result$summary), forbidden), character(0))

  on_machine(dir, {
    # Not on the release allowlist, whatever lands under data/.
    expect_false(any(grepl("tracker|^private/", atlas_release_files("draft"))))
  })
  # No route serves the ledger, and the spec names none.
  routes <- readLines(api_file(), warn = FALSE)
  expect_false(any(grepl("ledger[.]tsv|private/tracker|atlas_tracker_(load|local|key)", routes)))
  spec <- jsonlite::fromJSON(testthat::test_path("..", "..", "inst", "api", "openapi.json"), simplifyVector = FALSE)
  expect_false(any(grepl("ledger|private", names(spec$paths))))
  # Nor the sitemap or a Zenodo bundle.
  expect_false(grepl("tracker", paste(deparse(atlas_sitemap_xml), collapse = "")))
  expect_false(any(grepl("tracker|private", deparse(atlas_archive_models_bundle))))
})

test_that("the tracker leaves every fingerprint and fit setting alone", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- tracker_records("Amanita one", 3:20, first_green_on = "2026-10-06")
  before_rows <- atlas_fingerprint(finds[, ATLAS_OCCURRENCE_FIELDS])
  before_taxa <- atlas_taxon_fingerprints(finds)
  result <- tracker_run(store, finds, since = "2026-10-01")
  expect_identical(atlas_fingerprint(finds[, ATLAS_OCCURRENCE_FIELDS]), before_rows)
  expect_identical(atlas_taxon_fingerprints(finds), before_taxa)
  # Neither the fingerprint fields nor any fit setting name the tracker.
  expect_false(any(grepl("tracker|first_green", ATLAS_FINGERPRINT_FIELDS)))
  settings_text <- paste(deparse(atlas_fit_settings), collapse = "")
  expect_false(grepl("tracker", settings_text))
  # And it writes nothing a job or a release reads.
  expect_false(any(grepl("^(occurrences|models|public|index|releases|current)/", store$list("private/"))))
})

# ---- the API -----------------------------------------------------------------

test_that("GET /api/tracker answers not_started, then the summary; a taxon page gets its tally", {
  skip_if_not_installed("terra")
  with_data_dir({
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      empty <- call_api(api, "/api/tracker")
      expect_equal(empty$status, 200L)
      expect_equal(jsonlite::fromJSON(empty$body)$status, "not_started")

      store <- fresh_store()
      two_releases(store)
      finds <- tracker_records("Amanita one", 3:20, first_green_on = "2026-10-06")
      atlas_track_new_finds(store, occurrences = finds, since = "2026-10-01", quiet = TRUE, frozen = "")
      full <- call_api(api, "/api/tracker")
      body <- jsonlite::fromJSON(full$body, simplifyVector = FALSE)
      expect_equal(body$status, "tracking")
      expect_equal(body$finds$by_status$scored, 18L)
      expect_match(full$body, "\"beats_effort\":null", fixed = TRUE)

      atlas_write_json(list(file = "occurrences-t.tsv.gz", pulled_at = "2026-10-06T07:00:00Z", records = 1),
                       atlas_path("occurrences", "latest.json"))
      atlas_write_json(list(list(scientific_name = "Amanita one", records = 1, localities = 1, fingerprint = "f")),
                       atlas_path("occurrences", "taxa-latest.json"))
      taxon <- jsonlite::fromJSON(call_api(api, "/api/taxa/Amanita%20one")$body, simplifyVector = FALSE)
      expect_equal(taxon$new_finds$finds, 18L)
    })
  })
})

test_that("the OpenAPI example for /api/tracker has the summary's shape", {
  skip_if_not_installed("terra")
  spec <- jsonlite::fromJSON(testthat::test_path("..", "..", "inst", "api", "openapi.json"), simplifyVector = FALSE)
  example <- spec$paths[["/api/tracker"]]$get$responses[["200"]]$content[["application/json"]]$example
  expect_false(is.null(example))
  store <- fresh_store()
  two_releases(store)
  summary <- tracker_run(store, tracker_records("Amanita one", 3:20, first_green_on = "2026-10-06"), since = "2026-10-01")$summary
  expect_setequal(names(example), names(summary))
  expect_setequal(names(example$rows[[1]]), names(summary$rows[[1]]))
  expect_setequal(names(example$headline), names(summary$headline))
  expect_true(all(names(example$taxa[[1]]) %in% names(summary$taxa[[1]])))
})

test_that("the command only warns when it cannot run, and still succeeds", {
  with_data_dir(with_env(c(ATLAS_STORE = NA), {
    expect_warning(code <- atlas_main(c("track-new-finds")), "tracker did not run")
    expect_equal(code, 0L)
  }))
})

test_that("a taxon's tally counts finds since the map it shows now, even one redrawn without a refit", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  known <- tracker_records("Amanita one", 15, ids = "k1")
  # The same record set (fingerprint) in both releases, but R2's map is drawn anew.
  tracker_release(store, "R1", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z", known,
                  list(tracker_model(store, "Amanita one")), current = FALSE)
  tracker_release(store, "R2", "2026-10-05T07:00:00Z", "2026-10-05T08:00:00Z", known,
                  list(tracker_model(store, "Amanita one", surface = tracker_surface(function(col) col^2 + 1))))
  finds <- rbind(tracker_records("Amanita one", 11:16, first_green_on = "2026-10-03"),
                 tracker_records("Amanita one", 11:15, first_green_on = "2026-10-06"))
  result <- tracker_run(store, finds, since = "2026-10-01")
  tally <- atlas_tracker_for(result$summary, "Amanita one")
  expect_equal(tally$finds, 5L)
  expect_equal(tally$since, "2026-10-06")
})

test_that("organic finds are evaluated; triage, priority-sorted and automatic finds each get their own row", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  finds <- do.call(rbind, lapply(c(2, 4, 6, 8, 10, 12), function(r) {
    tracker_records("Amanita one", 3:20, rows = r, first_green_on = "2026-10-06")
  }))
  finds$channel <- rep(c(NA, "organic", "triage", "priority_sort", "auto", "something_new"), each = 18)
  result <- tracker_run(store, finds, since = "2026-10-01")
  expect_equal(sum(!is.na(result$ledger$channel)), 90L)
  rows <- result$summary$rows
  by_subset <- function(name) Filter(function(r) r$subset == name, rows)
  for (channel in c("triage", "priority_sort", "auto", "other")) {
    expect_length(by_subset(paste0("channel_", channel)), 1L)
    expect_equal(by_subset(paste0("channel_", channel))[[1]]$finds, 18L)
  }
  # Unrecorded and organic finds are the evaluated ones.
  evaluated <- Filter(function(r) r$subset == "all" && r$grade == "any" && r$release == "all", rows)[[1]]
  expect_equal(evaluated$finds, 36L)
  expect_equal(result$summary$headline$places, 36L)
  expect_equal(result$summary$finds$held_out$auto, 18L)
  expect_equal(result$summary$finds$held_out$other, 18L)
  expect_equal(atlas_tracker_for(result$summary, "Amanita one")$finds, 36L)
  # A channel .org adds later is held out as "other", never published by its own name.
  expect_false(grepl("something_new", jsonlite::toJSON(result$summary, auto_unbox = TRUE, null = "null")))
})

test_that("the summary says which pull it read, so the site can say scoring waits for the nightly", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  dir <- machine()
  on_machine(dir, atlas_write_json(list(file = "occurrences-x.tsv.gz", pulled_at = "2026-10-06T07:00:00Z"),
                                   atlas_path("occurrences", "latest.json")))
  result <- tracker_run(store, tracker_records("Amanita one", 18, first_green_on = "2026-10-06"), dir = dir,
                        since = "2026-10-01")
  expect_equal(result$summary$pulled_at, "2026-10-06T07:00:00Z")
})

test_that("the tracker reads the promotion records atlas_promote_release writes, not only the pointer", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  tracker_release(store, "R1", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z",
                  tracker_records("Amanita one", 15), list(tracker_model(store, "Amanita one")), current = FALSE)
  tracker_release(store, "R2", "2026-10-05T07:00:00Z", "2026-10-05T08:00:00Z",
                  tracker_records("Amanita one", 15), list(tracker_model(store, "Amanita one")), current = FALSE)
  # Start from the real promotion records alone.
  for (key in store$list("promotions/")) unlink(file.path(sub("^file://", "", store$uri), sub("^/", "", key)))
  atlas_promote_release(store, "R1", quiet = TRUE)
  atlas_promote_release(store, "R2", quiet = TRUE)
  promotions <- atlas_tracker_promotions(store, "draft", frozen = "")
  # The pointer names only R2; R1's promotion comes from its record.
  expect_true(all(c("R1", "R2") %in% promotions$release))
})

test_that("a find whose place is corrected into another cell is retracted as moved and scored where it is now", {
  skip_if_not_installed("terra")
  store <- fresh_store()
  two_releases(store)
  dir <- machine()
  find <- tracker_records("Amanita one", 19, ids = "m", first_green_on = "2026-10-06")
  first <- tracker_run(store, find, dir = dir, since = "2026-10-01", now = as.POSIXct("2026-10-07 06:00", tz = "UTC"))
  rank_before <- ledger_row(first, "iNaturalist:m")$rank
  # .org corrects its coordinates (same name) to the far west of the map.
  corrected <- tracker_records("Amanita one", 4, ids = "m", first_green_on = "2026-10-06")
  second <- tracker_run(store, corrected, dir = dir, since = "2026-10-01", now = as.POSIXct("2026-10-08 06:00", tz = "UTC"))
  rows <- ledger_row(second, "iNaturalist:m")
  expect_equal(nrow(rows), 2L)
  old <- rows[!is.na(rows$retracted_why), ]
  new <- rows[is.na(rows$retracted_why), ]
  expect_equal(old$retracted_why, "moved")
  expect_equal(old$retracted_on, "2026-10-08")
  expect_equal(new$release, "R2")
  expect_lt(new$rank, rank_before)
  # Counted once, at its new place; and a later run leaves it alone.
  expect_equal(second$summary$finds$by_status$scored, 1L)
  third <- tracker_run(store, corrected, dir = dir, since = "2026-10-01", now = as.POSIXct("2026-10-09 06:00", tz = "UTC"))
  expect_equal(nrow(ledger_row(third, "iNaturalist:m")), 2L)
  expect_equal(sum(is.na(ledger_row(third, "iNaturalist:m")$retracted_why)), 1L)
})

test_that("a run holds one taxon's maps at a time, and no raster's values beyond the two it reads", {
  skip_if_not_installed("terra")
  # A backfill scores hundreds of taxa on a box with about 1 GB to spare;
  # keeping every taxon's maps was killed for memory (2026-10-14).
  store <- fresh_store()
  taxa <- c("Amanita one", "Boletus two", "Cortinarius three")
  tracker_release(store, "R1", "2026-10-01T07:00:00Z", "2026-10-01T08:00:00Z",
                  do.call(rbind, lapply(taxa, function(t) tracker_records(t, 15))),
                  lapply(taxa, function(t) tracker_model(store, t)))
  finds <- do.call(rbind, lapply(taxa, function(t) tracker_records(t, 18, first_green_on = "2026-10-02")))
  on_machine(machine(), {
    view <- atlas_tracker_view(store, "R1")
    finds$key <- paste(finds$source, finds$observation_id, sep = ":")
    rows <- atlas_tracker_score_release(finds, view, "2026-10-01T08:00:00Z", "now", "record")
    expect_true(all(rows$status == "scored"))
    held <- setdiff(ls(view), c("id", "grid", "store", "cache", "shas", "entries", "pulled_at", "scheme",
                                "naming", "pull", "cells", "names", "modelled", "renames",
                                "last_taxon", "last_maps"))
    expect_equal(held, character(0))
    expect_equal(view$last_taxon, "Cortinarius three")
    expect_false(terra::hasValues(view$last_maps$models$maxnet$raster))
    expect_null(view$manifest)
  })
})
