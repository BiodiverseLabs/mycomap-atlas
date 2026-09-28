# Pipeline. `targets` caches every step by the hash of its inputs, which is
# exactly the nightly rule: when a record is validated its taxon's fingerprint
# changes, that taxon refits, and nothing else runs.
#
# Stages still to come: environmental layers, target-group background, model
# fits, spatially blocked evaluation, raster prediction, release manifest.

library(targets)

tar_option_set(packages = c("mycomapatlas"))

list(
  tar_target(
    occurrence_file,
    {
      manifest <- atlas_read_manifest()
      if (is.null(manifest)) {
        stop("nothing pulled yet: run ./atlas pull-occurrences", call. = FALSE)
      }
      atlas_path("occurrences", manifest$file)
    },
    format = "file"
  ),
  tar_target(occurrences, atlas_read_occurrences(occurrence_file)),
  tar_target(taxa, atlas_taxon_fingerprints(occurrences))
)
