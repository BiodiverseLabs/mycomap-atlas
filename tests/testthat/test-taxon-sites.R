# Each taxon's 5 km survey sites on /api/taxa (R/sites.R, atlas_add_sites):
# counted as the fits count them, for every taxon, never in the fingerprint.

tsv_text <- function(df) {
  con <- textConnection("out", "w", local = TRUE)
  utils::write.table(df, con, sep = "\t", row.names = FALSE, quote = FALSE, na = "")
  close(con)
  paste(out, collapse = "\n")
}

# Taxon A: 12 records about 10 km apart (12 sites). Taxon B: 4 records in one
# spot (1 site). Taxon C: 2 records off the grid, in Europe (0 sites).
site_records <- function() {
  spread <- synthetic_occurrences(c("Taxon A" = 12))
  bunched <- synthetic_occurrences(c("Taxon B" = 1))[rep(1, 4), ]
  bunched$id <- bunched$observation_id <- paste0("b", 1:4)
  away <- synthetic_occurrences(c("Taxon C" = 2))
  away$latitude <- c("48.85", "48.86")
  away$longitude <- c("2.35", "2.36")
  away$id <- away$observation_id <- paste0("c", 1:2)
  out <- rbind(spread, bunched, away)
  rownames(out) <- NULL
  # Numeric, as .org's are: the pull's first-green query spans a page's id range.
  out$id <- as.character(seq_len(nrow(out)))
  out
}

test_that("sites are counted as the fits count them: one per 5 km site with a record", {
  skip_if_not_installed("terra")
  sites <- atlas_taxon_sites(site_records())
  expect_equal(sites[["Taxon A"]], 12L)
  expect_equal(sites[["Taxon B"]], 1L)
  expect_equal(sites[["Taxon C"]], 0L)
  # The same number a batch decides a map's minimum on.
  points <- atlas_occurrence_points(site_records())
  counts <- atlas_presence_site_counts(points)
  expect_equal(sites[counts$scientific_name], stats::setNames(counts$cells, counts$scientific_name))
})

test_that("every taxon gets a count, and the fingerprints stay exactly as they were", {
  skip_if_not_installed("terra")
  records <- site_records()
  taxa <- atlas_taxon_fingerprints(records)
  with_sites <- atlas_add_sites(taxa, records)
  expect_setequal(with_sites$scientific_name, taxa$scientific_name)
  expect_true(all(is.finite(with_sites$sites)))
  expect_identical(with_sites$fingerprint, taxa$fingerprint)
  expect_identical(with_sites[names(taxa)], taxa)
})

test_that("a pull carries sites, keeps its fingerprint, and survives a count that fails", {
  skip_if_not_installed("terra")
  records <- site_records()
  pull <- function() {
    testthat::local_mocked_bindings(atlas_run_sql = function(sql, host) {
      if (startsWith(sql, "SELECT g.observation_id")) return(first_green_none)
      # Each record's approved sequence names it as the record does.
      if (startsWith(sql, "SELECT o.id, s.species_name")) {
        return(tsv_text(data.frame(id = records$id, species_name = records$scientific_name)))
      }
      if (grepl("not_yet_validated", sql, fixed = TRUE)) return("taxon\tnot_yet_validated\twith_coordinates")
      tsv_text(records)
    })
    atlas_pull_occurrences(host = "test", quiet = TRUE)
  }
  with_data_dir({
    counted <- pull()
    taxa <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
    expect_equal(taxa$sites[taxa$scientific_name == "Taxon A"], 12L)

    testthat::local_mocked_bindings(atlas_taxon_sites = function(...) stop("no grid today"))
    expect_warning(failed <- pull(), "survey sites not counted")
    expect_identical(failed$fingerprint, counted$fingerprint)
    bare <- jsonlite::fromJSON(atlas_path("occurrences", "taxa-latest.json"))
    expect_false("sites" %in% names(bare))
    expect_identical(bare$fingerprint, taxa$fingerprint)
  })
})

test_that("the taxa list and one taxon's answer carry sites, and no coordinates", {
  skip_if_not_installed("terra")
  records <- site_records()
  with_data_dir({
    atlas_write_json(atlas_add_sites(atlas_taxon_fingerprints(records), records),
                     atlas_path("occurrences", "taxa-latest.json"))
    with_env(c(ATLAS_DATA_DIR = atlas_data_dir()), {
      api <- test_api(c(ATLAS_DATA_DIR = atlas_data_dir()))
      list_rows <- jsonlite::fromJSON(call_api(api, "/api/taxa")$body)$items
      expect_true("sites" %in% names(list_rows))
      expect_equal(list_rows$sites[list_rows$scientific_name == "Taxon C"], 0L)
      one <- jsonlite::fromJSON(call_api(api, "/api/taxa/Taxon%20B")$body)
      expect_equal(one$sites, 1L)
      expect_false(any(c("lat", "lng", "latitude", "longitude") %in% c(names(list_rows), names(one))))
    })
  })
})
