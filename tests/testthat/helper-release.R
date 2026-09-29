# A data directory as a fitting machine leaves it: the pull (with exact
# coordinates), a training table, models for two algorithms, taxon counts.
computed_data <- function() {
  occurrences <- fake_occurrences()
  stamp <- "20260101T000000Z"
  atlas_write_tsv_gz(occurrences, atlas_path("occurrences", paste0("occurrences-", stamp, ".tsv.gz")))
  atlas_write_json(list(stamp = stamp, pulled_at = "2026-01-01T00:00:00Z", records = 3, taxa = 1,
                        fingerprint = "abc", file = paste0("occurrences-", stamp, ".tsv.gz"),
                        host = "mycomap-sql", sql = "SELECT secret FROM observations"),
                   atlas_path("occurrences", "latest.json"))
  atlas_write_json(atlas_taxon_fingerprints(occurrences), atlas_path("occurrences", "taxa-latest.json"))
  atlas_write_tsv_gz(occurrences, atlas_path("training", "draft", "amanita-muscaria.tsv.gz"))
  writeLines("raw page", atlas_path("raw", "occurrences", stamp, "chunk-0001.tsv.gz", create = TRUE))
  for (algorithm in c("maxnet", "rf")) {
    dir.create(atlas_model_dir("draft", algorithm), recursive = TRUE, showWarnings = FALSE)
    atlas_write_json(list(taxon = "Amanita muscaria", algorithm = algorithm, auc_mean = 0.7),
                     atlas_model_path("Amanita muscaria", "draft", ".json", algorithm))
    writeLines(paste("raster", algorithm), atlas_model_path("Amanita muscaria", "draft", ".tif", algorithm))
    writeLines(paste("map", algorithm), atlas_model_path("Amanita muscaria", "draft", ".png", algorithm))
  }
}

new_store <- function() {
  atlas_local_store(file.path(tempdir(), paste0("store-", as.integer(stats::runif(1, 1, 1e9)))))
}
