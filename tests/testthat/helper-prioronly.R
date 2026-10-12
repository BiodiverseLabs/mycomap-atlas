# Shared by the prior-only job tests (test-prioronly.R) and the EC2 tests.

PRIOR_ONLY_CUTOFF <- "2026-08-31"

# A pull whose records carry first green dates. Taxon A: 25 records, 8 of
# them validated after the cutoff, so 17 stay (below the 20-site minimum).
# Taxon B: 30 records, 5 after the cutoff and 6 never dated, so 25 stay.
# Taxon C: 22 records, all early, but weak in the main release.
dated_occurrences <- function() {
  occ <- synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 22))
  occ$first_green_on <- "2026-05-01"
  a <- which(occ$scientific_name == "Taxon A")
  occ$first_green_on[a[1:8]] <- "2026-09-15"
  b <- which(occ$scientific_name == "Taxon B")
  occ$first_green_on[b[1:5]] <- "2026-10-01"
  occ$first_green_on[b[6:11]] <- NA
  occ
}

# A fit that draws a real (small) map, records the settings it was asked to
# fit with, and gives each taxon the grade it is told to.
map_fit <- function(grades = list(), seen = new.env()) {
  seen$calls <- list()
  function(name, fingerprint, grid = "draft", algorithm = "maxnet", ...) {
    args <- list(...)
    seen$calls[[length(seen$calls) + 1L]] <- c(list(taxon = name, algorithm = algorithm),
                                               args[intersect(names(args), c("nulls", "n_background", "buffer_km",
                                                                              "folds", "block_km", "regmult",
                                                                              "correlation", "min_presences",
                                                                              "layers", "tune"))])
    out <- fake_fit(name, fingerprint, grid = grid, algorithm = algorithm, ...)
    r <- terra::rast(ncols = 20, nrows = 20, xmin = -2.2e6, xmax = -2.1e6, ymin = 5e5, ymax = 6e5, crs = ATLAS_CRS)
    terra::values(r) <- seq_len(terra::ncell(r))
    terra::writeRaster(r, atlas_model_path(name, grid, ".tif", algorithm), overwrite = TRUE)
    metrics <- out$metrics
    metrics$map <- "x.png"
    metrics$auc_mean <- 0.7
    if (!is.null(grades[[name]])) metrics$grade <- grades[[name]]
    atlas_write_json(metrics, atlas_model_path(name, grid, ".json", algorithm))
    list(metrics = metrics)
  }
}

# A store whose current release (R_main) was fitted on the dated pull, with
# Taxon A and B strong and Taxon C weak.
prior_only_setup <- function() {
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(dated_occurrences()))
  main_seen <- new.env()
  main <- full_cycle(store, boss,
                     fit = map_fit(list("Taxon A" = "strong", "Taxon B" = "strong", "Taxon C" = "weak"), main_seen))
  list(store = store, boss = boss, main = main, main_seen = main_seen)
}

# A stand-in for the prior build: the files atlas_build_prior writes, without
# reading rasters.
stub_prior_build <- function(grid = "draft", quiet = TRUE) {
  models <- atlas_strong_maps(grid)
  dir.create(atlas_prior_dir(grid), recursive = TRUE, showWarnings = FALSE)
  taxa <- data.frame(taxon_id = seq_along(unique(models$taxon)), name = sort(unique(models$taxon)))
  ranks <- data.frame(taxon_id = integer(), cell_id = integer(), rank = integer())
  atlas_write_tsv_gz(ranks, atlas_prior_path("ranks.tsv.gz", grid))
  utils::write.table(taxa, atlas_prior_path("taxa.tsv", grid), sep = "\t", quote = FALSE, row.names = FALSE)
  atlas_write_json(list(taxa = nrow(taxa), rows = 0L), atlas_prior_path("grid.json", grid))
  list(taxa = taxa, ranks = ranks)
}
