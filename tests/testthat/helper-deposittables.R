# The training-record and lineage tables' fixture (R/deposittables.R, R/trainingtables.R).

# A store with one job that fitted Taxon A (maxnet and rf) and Taxon B on one
# pull, whose Taxon C has no model; the release's index and a tree holding
# the models' metrics. second_job adds another job on the same pull that
# fitted nothing listed here. mo makes Taxon B's first mo records Mushroom
# Observer records. sequences gives each record a sequence id of its own,
# seq-1 onwards, and Taxon B's first two none.
tables_fixture <- function(second_job = FALSE, mo = 0L, sequences = FALSE) {
  store <- fresh_store()
  boss <- machine()
  out <- on_machine(boss, {
    occurrences <- synthetic_occurrences(c("Taxon A" = 25, "Taxon B" = 30, "Taxon C" = 20))
    # A second record of Taxon A at its first record's place: one site, two records.
    twin <- occurrences[occurrences$scientific_name == "Taxon A", ][1, ]
    twin$id <- twin$observation_id <- "twin-1"
    occurrences <- rbind(occurrences, twin)
    if (sequences) {
      occurrences$sequence_id <- paste0("seq-", seq_len(nrow(occurrences)))
      occurrences$sequence_id[which(occurrences$scientific_name == "Taxon B")[1:2]] <- ""
    }
    if (mo) occurrences$source[which(occurrences$scientific_name == "Taxon B")[seq_len(mo)]] <- ATLAS_MO_SOURCE
    orchestrator_data(occurrences)
    pull <- atlas_file_entries(file.path("occurrences", "occurrences-20260101T000000Z.tsv.gz"))
    atlas_upload_objects(store, pull)
    summary <- list(stamp = "20260101T000000Z", pulled_at = "2026-01-01T00:00:00Z", records = nrow(occurrences),
                    fingerprint = strrep("ab", 32))
    models <- list(c("Taxon A", "maxnet"), c("Taxon A", "rf"), c("Taxon B", "maxnet"))
    atlas_store_json(store, "jobs/draft/20261005T000000Z-job/job.json", list(
      id = "20261005T000000Z-job", created_at = "2026-10-05T00:00:00Z", inputs = pull, pull = summary,
      tasks = lapply(models, function(m) list(taxon = m[[1]], algorithm = m[[2]]))
    ))
    if (second_job) {
      atlas_store_json(store, "jobs/draft/20261007T000000Z-refresh/job.json", list(
        id = "20261007T000000Z-refresh", created_at = "2026-10-07T00:00:00Z", inputs = pull, pull = summary,
        tasks = list(list(taxon = "Taxon B", algorithm = "maxnet"))
      ))
    }
    tree <- tempfile("tree-")
    index <- list()
    for (m in models) {
      path <- atlas_with_data_dir(tree, atlas_model_path(m[[1]], "draft", ".json", m[[2]]))
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      built <- if (second_job && m[[1]] == "Taxon B") "2026-10-08T00:00:00Z" else "2026-10-06T00:00:00Z"
      atlas_write_json(list(taxon = m[[1]], algorithm = m[[2]], built_at = built,
                            settings = list(buffer_km = 500, thin_km = ATLAS_SITE_KM)), path)
      index[[length(index) + 1L]] <- list(taxon = m[[1]], algorithm = m[[2]],
                                          fingerprint = unname(atlas_fingerprints_for(occurrences, m[[1]])))
    }
    list(occurrences = occurrences, tree = tree, manifest = list(id = "r1", index = index))
  })
  c(out, list(store = store, land = terra::rast(getOption("atlas.block_land"))))
}

store_hashes <- function(store) {
  root <- sub("^file://", "", store$uri)
  files <- list.files(root, recursive = TRUE)
  stats::setNames(vapply(file.path(root, files), atlas_sha256, ""), files)
}
