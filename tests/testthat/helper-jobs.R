# Shared by the job and EC2 tests: separate machines, one store.
#
# Every machine is a separate data directory, and the store is a folder.

# Records for taxa with the given number of distinct 5 km cells, spread over
# Oregon so each record lands in its own cell. Where a taxon sits depends on
# its name, not its place in the list, so reordering changes nothing.
synthetic_occurrences <- function(cells) {
  rows <- lapply(seq_along(cells), function(k) {
    n <- cells[[k]]
    j <- sum(utf8ToInt(names(cells)[[k]])) %% 9L
    i <- seq_len(n) - 1L
    data.frame(
      id = paste0(j, "-", i), observation_id = paste0(j, "-", i), source = "iNaturalist",
      scientific_name = names(cells)[[k]], genus = "Genus", observed_on = "2025-10-01",
      latitude = sprintf("%.4f", 40 + j * 1.3 + (i %/% 10) * 0.12),
      longitude = sprintf("%.4f", -123 + (i %% 10) * 0.12),
      state = "Oregon", country = "US", sequence_id = "1", updated_at = "2026-01-01",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# An orchestrator's data directory: a pull and a (stand-in) layer set.
orchestrator_data <- function(occurrences, layer_md5 = "m1") {
  stamp <- "20260101T000000Z"
  file <- paste0("occurrences-", stamp, ".tsv.gz")
  atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
  atlas_write_json(list(stamp = stamp, pulled_at = "2026-01-01T00:00:00Z",
                        records = nrow(occurrences), fingerprint = "f", file = file),
                   atlas_path("occurrences", "latest.json"))
  atlas_write_json(atlas_taxon_fingerprints(occurrences), atlas_path("occurrences", "taxa-latest.json"))
  dir.create(atlas_layer_dir("draft"), recursive = TRUE, showWarnings = FALSE)
  atlas_write_json(list(list(id = "fake", md5 = layer_md5, file = "fake.tif")),
                   file.path(atlas_layer_dir("draft"), "manifest.json"))
  writeLines("not a real layer", file.path(atlas_layer_dir("draft"), "fake.tif"))
}

machine <- function() file.path(tempdir(), paste0("machine-", as.integer(stats::runif(1, 1, 1e9))))
on_machine <- function(dir, code) with_env(c(ATLAS_DATA_DIR = dir), code)
fresh_store <- function() atlas_local_store(machine())

TAXA <- c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 22, "Tiny" = 5)

# Plan, run every shard on its own fresh machine, finish.
full_cycle <- function(store, boss, shards = 2L, fit = fake_fit) {
  job <- on_machine(boss, atlas_plan_job(store, algorithms = c("maxnet", "rf"),
                                         shards = shards, quiet = TRUE))
  if (is.null(job)) return(NULL)
  for (n in seq_len(job$shards)) {
    on_machine(machine(), atlas_run_shard(store, job$id, n, quiet = TRUE, fit = fit))
  }
  on_machine(boss, atlas_finish_job(store, job$id, quiet = TRUE))
}

release_paths <- function(release) vapply(release$files, function(f) f$path, "")
release_hash <- function(release, path) {
  Filter(function(f) f$path == path, release$files)[[1]]$sha256
}

# A fit that stops the whole worker once it has run `n` times, as a spot
# reclaim does. What it signals is not an error, so nothing in the batch
# catches it: the shard ends where it was, as a lost worker's would.
lost_after <- function(n, fit = fake_fit) {
  calls <- 0L
  function(name, ...) {
    if (calls >= n) {
      stop(structure(class = c("atlas_test_lost", "condition"),
                     list(message = "the worker was taken back", call = NULL)))
    }
    calls <<- calls + 1L
    fit(name, ...)
  }
}

# Runs a shard until its worker is lost; returns nothing.
run_until_lost <- function(store, job, shard, fit, ...) {
  tryCatch(on_machine(machine(), atlas_run_shard(store, job$id, shard, quiet = TRUE, fit = fit, ...)),
           atlas_test_lost = function(e) NULL)
  invisible(NULL)
}

# A fit that remembers which taxa it was asked for.
counting_fit <- function(fit = fake_fit) {
  seen <- new.env()
  seen$taxa <- character()
  f <- function(name, ...) {
    seen$taxa <- c(seen$taxa, name)
    fit(name, ...)
  }
  list(fit = f, taxa = function() seen$taxa)
}

MORE_TAXA <- c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 22, "Taxon D" = 26, "Taxon E" = 28)
