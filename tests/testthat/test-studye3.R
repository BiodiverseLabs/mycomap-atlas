# Paper E3 (study-score --release): a published release scored on the finds
# first validated after it, under the name each had that day; every record
# the release trained on, or that falls outside the window, kept apart and
# counted; and a counts-only look that holds no score.

# A change in the name-change log, as atlas_read_name_changes keeps it.
log_change <- function(id, day, kind, old, new, records, respelling = FALSE) {
  list(id = id, logged_at = paste0(day, "T12:00:00Z"), kind = kind, old_name = old, new_name = new,
       respelling = respelling, records = records)
}

# The release's pull (80 records, first validated before its pull of
# 2026-10-12) and a fresh pull holding them again plus later records.
e3_world <- function() {
  set.seed(9)
  place <- function(n) list(lat = as.character(40 + stats::runif(n, 0, 0.5)),
                            lng = as.character(-85 + stats::runif(n, 0, 0.5)))
  p <- place(80)
  release_pull <- data.frame(
    id = as.character(1000 + 1:80), source = "iNaturalist", observation_id = as.character(1:80),
    scientific_name = rep(sprintf("T%02d", 1:20), length.out = 80), latitude = p$lat, longitude = p$lng,
    first_green_on = "2026-08-01", stringsAsFactors = FALSE)
  later <- data.frame(
    rows = c(rep("window", 40), "before_live", "before_live", "after_until", "green_before_pull", "undated",
             "off_grid", "same_id", "renamed", "respelled", "chained", "merged", "split", "same_day",
             "changed_before"),
    stringsAsFactors = FALSE)
  n <- nrow(later)
  q <- place(n)
  later$id <- as.character(2000 + seq_len(n))
  later$source <- "iNaturalist"
  later$observation_id <- as.character(500 + seq_len(n))
  later$scientific_name <- sprintf("T%02d", (seq_len(n) %% 20) + 1)
  later$latitude <- q$lat
  later$longitude <- q$lng
  later$first_green_on <- "2026-10-20"
  later$first_green_on[later$rows == "before_live"] <- c("2026-10-12", "2026-10-13")
  later$first_green_on[later$rows == "after_until"] <- "2026-12-20"
  later$first_green_on[later$rows == "green_before_pull"] <- "2026-10-01"
  later$first_green_on[later$rows == "undated"] <- NA
  later$latitude[later$rows == "off_grid"] <- NA
  # A record of the release under another key but the same .org row.
  later$id[later$rows == "same_id"] <- release_pull$id[[3]]
  # Names now, after changes the log records.
  later$scientific_name[later$rows == "renamed"] <- "T05 newname"
  later$scientific_name[later$rows == "respelled"] <- "T06 spelt"
  later$scientific_name[later$rows == "chained"] <- "T07 third"
  later$scientific_name[later$rows == "changed_before"] <- "T08 renamed early"
  ref <- function(row) paste0("inat:", later$observation_id[later$rows == row])
  changes <- list(
    log_change(1, "2026-10-25", "rename", "T05", "T05 newname", ref("renamed")),
    log_change(2, "2026-10-25", "rename", "T06", "T06 spelt", ref("respelled"), respelling = TRUE),
    log_change(3, "2026-10-22", "rename", "T07", "T07 second", ref("chained")),
    log_change(4, "2026-10-28", "rename", "T07 second", "T07 third", ref("chained")),
    log_change(5, "2026-10-25", "merge", "T09", "T10", ref("merged")),
    log_change(6, "2026-10-25", "split", "T11", "T11a", ref("split")),
    log_change(7, "2026-10-20", "rename", "T12", "T12b", ref("same_day")),
    # Logged before the find was validated: it was validated under the new name.
    log_change(8, "2026-10-15", "rename", "T08", "T08 renamed early", ref("changed_before"))
  )
  fresh <- rbind(release_pull, later[, names(release_pull)])
  view <- list(manifest = list(purpose = NULL), pulled_at = "2026-10-12T05:10:17Z",
               pull = data.frame(key = paste("iNaturalist", release_pull$observation_id, sep = ":"),
                                 stringsAsFactors = FALSE),
               names = c(sprintf("T%02d", 1:20), "T08 renamed early"), renames = NULL)
  list(release_pull = release_pull, fresh = fresh, later = later, changes = changes, view = view)
}

test_that("a find counts under the name it had on the day it was first validated", {
  w <- e3_world()
  l <- w$later
  rows <- c("renamed", "respelled", "chained", "merged", "split", "same_day", "changed_before", "window")
  at <- atlas_e3_name_at_green(paste0("inat:", l$observation_id[match(rows, l$rows)]), rep("2026-10-20", length(rows)),
                               w$changes)
  rownames(at) <- rows
  expect_equal(at["renamed", "name"], "T05")
  expect_equal(at["renamed", "kind"], "rename")
  expect_equal(at["respelled", "kind"], "respelling")
  # Two later renames are undone in turn, back to the first one's old name.
  expect_equal(at["chained", "name"], "T07")
  expect_true(is.na(at["merged", "name"]))
  expect_equal(at["merged", "kind"], "merge")
  expect_equal(at["split", "kind"], "split")
  expect_equal(at["same_day", "kind"], "same_day")
  # A change logged before the validation leaves the name as it is.
  expect_true(is.na(at["changed_before", "kind"]))
  expect_true(is.na(at["window", "kind"]))
})

test_that("the split keeps every training record and every out-of-window find apart, and counts why", {
  skip_if_not_installed("terra")
  w <- e3_world()
  s <- atlas_e3_split(w$release_pull, w$fresh, "2026-10-12", "2026-10-14", "2026-12-15", w$changes)
  k <- unlist(s$kept_apart)
  expect_equal(k[["in_release_pull"]], 81L)
  expect_equal(k[["before_live"]], 2L)
  expect_equal(k[["after_until"]], 1L)
  expect_equal(k[["green_before_pull"]], 1L)
  expect_equal(k[["undated"]], 1L)
  expect_equal(k[["off_grid"]], 1L)
  expect_equal(k[["name_merge"]], 1L)
  expect_equal(k[["name_split"]], 1L)
  expect_equal(k[["name_same_day"]], 1L)
  # The window's forty, the renamed, the respelled, the chained and the one
  # validated under its new name (the same-.org-row record is the release's).
  expect_equal(s$test_finds, 44L)
  scored <- s$finds[is.na(s$finds$kept_apart), , drop = FALSE]
  expect_false(any(scored$key %in% s$release_keys))
  expect_true(all(scored$first_green_on >= "2026-10-14" & scored$first_green_on <= "2026-12-15"))
  # Each renamed find, by its own record, under its name on its validation day.
  taxon_of <- function(row) scored$taxon[scored$key == paste0("iNaturalist:", w$later$observation_id[w$later$rows == row])]
  expect_equal(taxon_of("renamed"), "T05")
  expect_equal(taxon_of("respelled"), "T06")
  expect_equal(taxon_of("chained"), "T07")
  expect_equal(taxon_of("changed_before"), "T08 renamed early")
  expect_equal(unlist(s$names_undone), c(rename = 2L, respelling = 1L))
  expect_equal(nrow(s$training), 80L)
  # A window that starts on or before the release's pull is refused.
  expect_error(atlas_e3_split(w$release_pull, w$fresh, "2026-10-12", "2026-10-12", "2026-12-15"), "after the release's pull")
  expect_error(atlas_e3_split(w$release_pull, w$fresh, "2026-10-12", "2026-10-14", "2026-10-13"), "before --from")
})

e3_maps <- function(w) {
  xy <- atlas_albers(as.numeric(w$fresh$latitude), as.numeric(w$fresh$longitude))
  ok <- is.finite(xy[, "x"])
  grid <- terra::rast(nrows = 20, ncols = 20, crs = ATLAS_CRS,
                      xmin = min(xy[ok, "x"]) - 5e4, xmax = max(xy[ok, "x"]) + 5e4,
                      ymin = min(xy[ok, "y"]) - 5e4, ymax = max(xy[ok, "y"]) + 5e4)
  terra::values(grid) <- seq_len(400)
  atlas_tracker_layers(grid)
}

test_that("a read-out scores the published release's own maps and writes no record, place or rank of one", {
  skip_if_not_installed("terra")
  w <- e3_world()
  layers <- e3_maps(w)
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) {
    list(maxnet = list(layers = layers, grade = "strong", tier = "strong", learner = "maxnet", kind = "model"))
  })
  fresh <- list(pull = w$fresh, manifest = list(file = "occurrences-x.tsv.gz", pulled_at = "2026-12-15T05:00:00Z",
                                                records = nrow(w$fresh), since = NA),
                changes = list(cursor = 8, changes = w$changes))
  with_data_dir({
    result <- atlas_e3_study(store = NULL, release = "r1", from = "2026-10-14", until = "2026-12-15", reps = 50,
                             view = w$view, release_pull = w$release_pull, fresh = fresh, quiet = TRUE)
    expect_equal(result$finds$test_finds, 44L)
    expect_true(isTRUE(result$e3$H3a$tested))
    expect_false(is.null(result$e3$H3a$estimate))
    expect_equal(result$e3$H3c$why, "no kernels given")
    expect_equal(result$settings$fresh_pull$name_change_cursor, 8)
    expect_equal(result$settings$release_pulled_at, "2026-10-12T05:10:17Z")
    text <- paste(readLines(result$path, warn = FALSE), collapse = "\n")
    expect_false(grepl("iNaturalist:|inat:", text))
    expect_false(grepl("\"key\"|\"latitude\"|\"x\":", text))
  })
})

test_that("a counts-only look gives counts of finds and places by grade, and no score at all", {
  skip_if_not_installed("terra")
  w <- e3_world()
  layers <- e3_maps(w)
  local_mocked_bindings(atlas_score_model_maps = function(view, taxon) {
    list(maxnet = list(layers = layers, grade = "strong", tier = "strong", learner = "maxnet", kind = "model"))
  })
  fresh <- list(pull = w$fresh, manifest = list(since = NA), changes = list(cursor = 8, changes = w$changes))
  with_data_dir({
    result <- atlas_e3_study(store = NULL, release = "r1", from = "2026-10-14", until = "2026-12-15", counts_only = TRUE,
                             view = w$view, release_pull = w$release_pull, fresh = fresh, quiet = TRUE)
    expect_equal(result$study, "e3-counts")
    expect_gt(result$counts$by_grade$strong$ranked_places, 0L)
    text <- paste(readLines(result$path, warn = FALSE), collapse = "\n")
    for (word in c("top_half", "top_tenth", "mean_rank", "rank\"", "boyce", "beats_effort", "estimate", "H3a")) {
      expect_false(grepl(word, text, fixed = TRUE), info = word)
    }
  })
})

test_that("a hindcast, a partial pull and a non-private stage are refused", {
  skip_if_not_installed("terra")
  w <- e3_world()
  hind <- w$view
  hind$manifest$purpose <- "hindcast"
  expect_error(atlas_e3_study(store = NULL, release = "h1", from = "2026-10-14", until = "2026-12-15", view = hind,
                              release_pull = w$release_pull, fresh = list(), quiet = TRUE), "is a hindcast")
  store <- fresh_store()
  with_data_dir({
    dir.create(atlas_path("occurrences"), recursive = TRUE)
    atlas_write_tsv_gz(w$fresh, atlas_path("occurrences", "occurrences-x.tsv.gz"))
    atlas_write_json(list(file = "occurrences-x.tsv.gz", since = "2026-10-01"), atlas_path("occurrences", "latest.json"))
    expect_error(atlas_e3_fresh(NULL), "needs a full pull")
    atlas_write_json(list(file = "occurrences-x.tsv.gz", since = NA, pulled_at = "2026-12-15T05:00:00Z"),
                     atlas_path("occurrences", "latest.json"))
    expect_error(atlas_stage_pull(store, "study/e3/"), "private")
    keys <- atlas_stage_pull(store, "private/study/e3-pull/")
    expect_setequal(keys, c("private/study/e3-pull/occurrences-x.tsv.gz", "private/study/e3-pull/latest.json"))
  })
  # A study job reads the staged pull back, whole.
  staged <- atlas_e3_fresh(store, "private/study/e3-pull/")
  expect_equal(nrow(staged$pull), nrow(w$fresh))
  expect_equal(staged$manifest$pulled_at, "2026-12-15T05:00:00Z")
})

test_that("study-score --release runs E3, and needs its window", {
  got <- NULL
  local_mocked_bindings(atlas_e3_study = function(...) { got <<- list(...); invisible(list()) },
                        atlas_score_study = function(...) stop("E2 ran instead"),
                        atlas_flag_store = function(flags) NULL)
  atlas_main(c("study-score", "--release=r1", "--from=2026-10-14", "--until=2026-12-15",
               "--finds-pull=private/study/e3-pull/", "--counts-only", "--shard=1/1", "--out=study/x/"))
  expect_equal(got$release, "r1")
  expect_equal(got$from, "2026-10-14")
  expect_equal(got$finds_pull, "private/study/e3-pull/")
  expect_true(got$counts_only)
  expect_error(atlas_main(c("study-score", "--release=r1")), "needs --from")
  expect_error(atlas_main(c("study-score", "--release=r1", "--hindcast=h1", "--from=2026-10-14", "--until=2026-12-15")),
               "not both")
})
