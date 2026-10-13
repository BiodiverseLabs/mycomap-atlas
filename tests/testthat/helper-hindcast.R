# Shared by the private-release tests (test-hindcast.R) and the EC2 tests.

HINDCAST_CUTOFF <- "2026-08-17"

# A pull whose dates pull apart. Taxon A: 40 records, the last 10 first
# validated after the cutoff, 4 of those observed long before it (they go);
# 3 early-validated ones observed after the cutoff (they stay). Taxon B: 30,
# 5 with no first green date (left out by a hindcast). Taxon C: 22, all
# early. Every record also carries its .org name: Taxon B's are a genus only.
hindcast_occurrences <- function() {
  occ <- synthetic_occurrences(c("Taxon A" = 40, "Taxon B" = 30, "Taxon C" = 22))
  occ$first_green_on <- "2026-05-01"
  occ$record_name <- occ$scientific_name
  a <- which(occ$scientific_name == "Taxon A")
  occ$first_green_on[a[31:40]] <- "2026-09-15"
  occ$observed_on[a[31:34]] <- "2019-06-01"
  occ$observed_on[a[1:3]] <- "2026-09-30"
  b <- which(occ$scientific_name == "Taxon B")
  occ$first_green_on[b[1:5]] <- NA
  occ$record_name[b] <- "Genus sp."
  occ$record_name[which(occ$scientific_name == "Taxon C")] <- "Taxon Cee"
  occ
}

hindcast_setup <- function() {
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, {
    orchestrator_data(hindcast_occurrences())
    # A rename the release carries, as a pull records one (R/names.R).
    atlas_write_json(data.frame(from = "Taxon Old", to = "Taxon A", records = 3L, moved = 3L,
                                seen = "2026-10-01"), atlas_renames_path())
  })
  main <- full_cycle(store, boss, fit = map_fit(list("Taxon A" = "strong", "Taxon B" = "strong", "Taxon C" = "weak")))
  list(store = store, boss = boss, main = main)
}

job_pull <- function(store, job) {
  entry <- atlas_job_pull_entry(job)
  file <- tempfile(fileext = ".tsv.gz")
  store$get(atlas_object_key(entry$sha256), file)
  atlas_read_occurrences(file)
}

# A stand-in for finishing's builders: the files they write, no rasters read.
stub_finish_build <- function(grid, quiet) {
  stub_prior_build(grid)
  stub_continent_build(grid)
  dir.create(dirname(atlas_here_index_path(grid)), recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(stub = TRUE), atlas_here_index_path(grid))
}
