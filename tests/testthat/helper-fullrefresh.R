# Shared by the full-view refresh tests (test-fullrefresh.R) and the EC2 tests.

REFRESH_GRADES <- list("Taxon A" = "strong", "Taxon B" = "strong", "Taxon C" = "weak")

# R_main: Taxon A and B strong (Maxent and forest), C weak, each strong model
# with a full view drawn the old way (a stand-in for the streaked ones).
refresh_setup <- function() {
  store <- fresh_store()
  boss <- machine()
  on_machine(boss, orchestrator_data(synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 22))))
  fit <- map_fit(REFRESH_GRADES)
  old_views <- function(name, fingerprint, grid = "draft", algorithm = "maxnet", ...) {
    strong <- identical(REFRESH_GRADES[[name]], "strong")
    args <- list(...)
    args$full <- strong
    out <- do.call(fit, c(list(name, fingerprint, grid = grid, algorithm = algorithm), args))
    if (strong) {
      writeLines("the old full view", atlas_model_path(name, grid, ".full.png", algorithm))
      metrics <- out$metrics
      metrics$full_map$bounds <- list(south = 1, west = 2, north = 3, east = 4)
      atlas_write_json(metrics, atlas_model_path(name, grid, ".json", algorithm))
      out$metrics <- metrics
    }
    out
  }
  main <- full_cycle(store, boss, fit = old_views)
  list(store = store, boss = boss, main = main)
}

# Plan, run and publish a refresh of R_main with the given fit.
run_refresh <- function(setup, fit = map_fit(), publish = TRUE) {
  job <- on_machine(setup$boss, atlas_plan_full_refresh(setup$store, setup$main$id, shards = 2L, quiet = TRUE))
  for (n in seq_len(job$shards)) on_machine(machine(), atlas_run_shard(setup$store, job$id, n, quiet = TRUE, fit = fit))
  release <- if (publish) on_machine(setup$boss, atlas_finish_full_refresh(setup$store, job$id, quiet = TRUE))
  list(job = job, release = release)
}
