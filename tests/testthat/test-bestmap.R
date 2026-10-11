# The one map to show per taxon (R/bestmap.R) and its two routes. The
# answers' shape is fixed by inst/api/fixtures/best-map.json.

fixture <- function() {
  path <- testthat::test_path("..", "..", "inst", "api", "fixtures", "best-map.json")
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

# A PNG header only: enough for the size reader and a stable md5.
fake_png <- function(path, width, height, salt = "") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  int <- function(x) as.raw(c(x %/% 2^24, (x %/% 2^16) %% 256, (x %/% 2^8) %% 256, x %% 256))
  bytes <- c(as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)), int(13), charToRaw("IHDR"),
             int(width), int(height), charToRaw(paste0("rest", salt)))
  writeBin(bytes, path)
}

BOUNDS <- list(south = 30, west = -120, north = 50, east = -70)

# A fitted model with a map: grade, held-out AUC and Boyce, a null test.
fake_model <- function(name, algorithm, grade, auc, boyce = 0.5, bounds = BOUNDS, strength = 0.6) {
  atlas_write_json(list(taxon = name, algorithm = algorithm, grade = grade, auc_mean = auc, boyce = boyce,
                        map_strength = strength, bounds = bounds,
                        null = list(design = "shift", observed_auc = auc, auc_mean = 0.55, auc_sd = 0.05)),
                   atlas_model_path(name, "draft", ".json", algorithm))
  fake_png(atlas_model_path(name, "draft", ".png", algorithm), 1200, 800, paste(name, algorithm))
}

fake_ensemble <- function(name, members, bounds = BOUNDS) {
  atlas_write_json(list(taxon = name, members = lapply(members, function(a) list(algorithm = a, weight = 0.2)),
                        map_strength = 0.7, bounds = bounds),
                   atlas_ensemble_path(name, "draft", ".json"))
  fake_png(atlas_ensemble_path(name, "draft", ".png"), 1500, 900, paste(name, "ensemble"))
}

TAXA <- data.frame(
  scientific_name = c("Combined one", "Single one", "Weak one", "Sparse one", "Unfitted one", "Mycena sp. 'IN10'"),
  records = c(80L, 30L, 40L, 2L, 9L, 12L), localities = c(70L, 25L, 33L, 2L, 8L, 11L),
  fingerprint = letters[1:6], stringsAsFactors = FALSE
)

fake_world <- function() {
  fake_model("Combined one", "maxnet", "strong", 0.70)
  fake_model("Combined one", "rf", "strong", 0.74)
  fake_model("Combined one", "xgboost", "weak", 0.80)
  fake_ensemble("Combined one", c("maxnet", "rf", "xgboost"))
  fake_model("Single one", "maxnet", "strong", 0.66)
  fake_model("Single one", "rf", "strong", 0.71)
  fake_model("Single one", "xgboost", "weak", 0.90)
  fake_model("Weak one", "maxnet", "weak", 0.64)
  fake_model("Weak one", "rf", "failed", 0.48)
  fake_model("Mycena sp. 'IN10'", "esm", "strong", 0.74)
  atlas_write_json(TAXA, atlas_path("occurrences", "taxa-latest.json"))
  atlas_write_json(list(stamp = "20261012T070000Z", pulled_at = "2026-10-12T07:00:00Z", records = 173L,
                        taxa = 6L, fingerprint = "f", file = "occurrences-20261012T070000Z.tsv.gz"),
                   atlas_path("occurrences", "latest.json"))
  atlas_write_json(list(release = "20261012T080000Z-1a2b3c4d", grid = "draft", created_at = "2026-10-12T08:00:00Z"),
                   atlas_path("releases", "draft", "pulled.json"))
}

answer <- function(name, renames = NULL, show_weak = FALSE) {
  atlas_best_map_answer(name, TAXA, renames, "draft", origin = "https://atlas.example.org", show_weak = show_weak)
}

test_that("two or more strong maps give their combined map, built from the strong ones only", {
  with_data_dir({
    fake_world()
    a <- answer("Combined one")
    expect_true(a$available)
    expect_equal(a$choice$kind, "ensemble")
    expect_null(a$choice$algorithm)
    expect_setequal(unlist(a$choice$members), c("maxnet", "rf"))
    expect_equal(a$choice$grade, "strong")
    md5 <- unname(tools::md5sum(atlas_ensemble_path("Combined one", "draft", ".png")))
    expect_equal(a$overlay$url, paste0("https://atlas.example.org/api/taxa/Combined%20one/ensemble.png?v=", md5))
    expect_equal(c(a$overlay$width, a$overlay$height), c(1500L, 900L))
    expect_equal(a$overlay$opacity, round(0.25 + 0.55 * 0.7, 2))
    expect_equal(a$release$id, "20261012T080000Z-1a2b3c4d")
  })
})

test_that("without a combined map the strong map with the best held-out skill is shown, never a weak one", {
  with_data_dir({
    fake_world()
    a <- answer("Single one")
    expect_equal(a$choice$kind, "model")
    expect_equal(a$choice$algorithm, "rf")
    expect_equal(a$choice$skill$auc, 0.71)
    expect_equal(a$choice$skill$null_z, round((0.71 - 0.55) / 0.05, 2))
    expect_match(a$overlay$url, "/map.png?algorithm=rf&v=", fixed = TRUE)
    # Two strong maps whose combined map has not been built: still one map.
    unlink(atlas_ensemble_path("Combined one", "draft", ".png"))
    expect_equal(answer("Combined one")$choice$algorithm, "rf")
  })
})

test_that("a taxon whose maps are weak or failed has none to show, unless faint maps are switched on", {
  with_data_dir({
    fake_world()
    a <- answer("Weak one")
    expect_false(a$available)
    expect_equal(a$reason, "no_strong_model")
    expect_null(a$choice)
    expect_null(a$overlay)
    faint <- answer("Weak one", show_weak = TRUE)
    expect_true(faint$available)
    expect_equal(faint$choice$grade, "weak")
    expect_equal(faint$choice$algorithm, "maxnet")
    expect_equal(faint$overlay$opacity, 0.25)
    expect_match(faint$caption, atlas_grade_note("weak"), fixed = TRUE)
  })
})

test_that("each reason for no map: too few sites, not fitted yet, and an unknown name", {
  with_data_dir({
    fake_world()
    sparse <- answer("Sparse one")
    expect_equal(sparse$reason, "too_few_sites")
    expect_match(sparse$reason_text, "2 independent places")
    unfitted <- answer("Unfitted one")
    expect_equal(unfitted$reason, "not_modelled")
    unknown <- answer("Nobody knowsius")
    expect_equal(unknown$reason, "not_modelled")
    expect_null(unknown$taxon)
    expect_null(unknown$matched_by)
    expect_null(unknown$page_url)
    expect_true(all(c(sparse$reason, unfitted$reason, unknown$reason) %in% ATLAS_BEST_MAP_REASONS))
    expect_false("withheld" %in% ATLAS_BEST_MAP_REASONS)
  })
})

test_that("a name is matched exactly, by spelling, folded, or through a rename", {
  with_data_dir({
    fake_world()
    expect_equal(answer("Single one")$matched_by, "exact")
    expect_equal(answer("single ONE")$matched_by, "spelling")
    folded <- answer("Single one (Fr.) Maire")
    expect_equal(folded$matched_by, "folded")
    expect_equal(folded$taxon, "Single one")
    expect_true(answer("Mycena sp. 'IN10'")$provisional)
    expect_false(answer("Single one")$provisional)
    renames <- data.frame(from = "Old single name", to = "Single one", stringsAsFactors = FALSE)
    renamed <- answer("Old single name", renames)
    expect_equal(renamed$matched_by, "renamed")
    expect_equal(renamed$taxon, "Single one")
  })
})

test_that("bounds stay within -180..180, and a map past the antimeridian says it crosses", {
  plain <- atlas_wrap_bounds(BOUNDS)
  expect_false(plain$crosses)
  expect_equal(plain$bounds$west, -120)
  across <- atlas_wrap_bounds(list(south = 20, west = -193.2, north = 72, east = -36.4))
  expect_true(across$crosses)
  expect_equal(across$bounds$west, 166.8)
  expect_equal(across$bounds$east, -36.4)
  expect_true(across$bounds$west > across$bounds$east)
})

# Same keys at every level, and the same JSON type wherever both have a value.
same_shape <- function(real, contract, where = "answer") {
  if (is.list(contract) && !is.null(names(contract))) {
    expect_true(is.list(real) && !is.null(names(real)), label = paste(where, "is an object"))
    expect_setequal(names(real), names(contract))
    for (k in intersect(names(real), names(contract))) {
      if (!is.null(real[[k]]) && !is.null(contract[[k]])) same_shape(real[[k]], contract[[k]], paste(where, k, sep = "$"))
    }
  } else if (is.list(contract)) {
    expect_true(is.list(real) && is.null(names(real)), label = paste(where, "is an array"))
    if (length(real) && length(contract)) same_shape(real[[1]], contract[[1]], paste0(where, "[1]"))
  } else {
    kind <- function(x) if (is.logical(x)) "boolean" else if (is.numeric(x)) "number" else "string"
    expect_equal(kind(real), kind(contract), label = where)
  }
}

as_json <- function(x) {
  jsonlite::fromJSON(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA)),
                     simplifyVector = FALSE)
}

test_that("every answer has exactly the contract's shape", {
  with_data_dir({
    fake_world()
    contract <- fixture()
    cases <- list(combined = "Combined one", single = "mycena sp. 'IN10'", no_strong_model = "Weak one",
                  too_few_sites = "Sparse one", not_modelled = "Nobody knowsius")
    for (case in names(cases)) {
      same_shape(as_json(answer(cases[[case]])), contract$best_map[[case]], case)
    }
    models <- data.frame(taxon = TAXA$scientific_name, presences = TAXA$localities, stringsAsFactors = FALSE)
    index <- as_json(atlas_best_maps(models, "draft", origin = "https://atlas.example.org"))
    same_shape(index, contract$maps_best, "maps_best")
    expect_setequal(vapply(index$items, function(i) i$taxon, ""), c("Combined one", "Single one", "Mycena sp. 'IN10'"))
    expect_equal(index$count, 3L)
    expect_equal(index$grading, "shift")
  })
})

test_that("no answer carries a coordinate or a record, only a map's bounds", {
  with_data_dir({
    fake_world()
    keys <- function(x) if (is.list(x)) c(names(x), unlist(lapply(x, keys))) else character()
    forbidden <- c("lat", "lng", "latitude", "longitude", "cells", "records", "observation_id", "fingerprint")
    for (name in c(TAXA$scientific_name, "Nobody knowsius")) {
      found <- intersect(keys(answer(name)), forbidden)
      expect_equal(found, character(0), label = name)
    }
  })
})

test_that("anyone may ask the routes; nulls are null; the list has an ETag; status names the grading", {
  with_data_dir({
    fake_world()
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      one <- call_api(api, "/api/taxa/Single%20one/best-map")
      expect_equal(one$status, 200L)
      body <- jsonlite::fromJSON(one$body, simplifyVector = FALSE)
      expect_true(body$available)
      expect_null(body$reason)
      expect_match(one$body, "\"reason\":null", fixed = TRUE)
      none <- call_api(api, "/api/taxa/Nobody%20knowsius/best-map")
      expect_equal(none$status, 200L)
      expect_match(none$body, "\"choice\":null", fixed = TRUE)

      list1 <- call_api(api, "/api/maps/best")
      expect_equal(list1$status, 200L)
      etag <- header_values(list1, "ETag")
      expect_match(etag, "^\"[0-9a-f]{32}\"$")
      again <- call_api(api, "/api/maps/best", headers = list("If-None-Match" = etag))
      expect_equal(again$status, 304L)
      stale <- call_api(api, "/api/maps/best", headers = list("If-None-Match" = "\"not-this\""))
      expect_equal(stale$status, 200L)

      status <- jsonlite::fromJSON(call_api(api, "/api/status")$body)
      expect_equal(status$grading, "shift")
    })
  })
})
