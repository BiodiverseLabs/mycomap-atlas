# Appendix S1: Section S11. Data records and usage notes

*Draft, 2026-10-25. File lists and sizes were read from Zenodo's public
API on 2026-10-25. What each file holds is stated where the paper or the
release records it; the rest is marked [CHECK] for the operations lane.*

## S11.1 Records on Zenodo

| Record | DOI | Version | Files | Size | Licence |
|---|---|---|---|---|---|
| Environmental layers | 10.5281/zenodo.23463069 (concept 23463068) | draft-2026-09-30-df57c9d4 | 11 | 0.15 GB | CC BY-SA 4.0 |
| Models of the frozen release | 10.5281/zenodo.23463939 (concept 23463938) | 20261013T191324Z-fa1b4198 | 26 | 14.21 GB (13.24 GiB) | CC BY-SA 4.0 |
| Training records, contributors, model lineage | next version of the models record | [PENDING: E19, E20] | | | training-record table CC0 1.0; the rest CC BY-SA 4.0 |

### Layers record (69 predictor bands in eight layers)

| File | Size | Contents |
|---|---|---|
| bioclim.tif | 62.6 MB | WorldClim 2.1 bioclimatic variables (1970–2000) |
| hosts.tif | 20.9 MB | host-tree layers from the two national forest inventories [CHECK: band list] |
| hostsdecay.tif | 7.4 MB | host-tree layers with distance decay [CHECK] |
| foresttype.tif | 6.6 MB | forest type [CHECK] |
| soil.tif | 20.6 MB | topsoil chemistry and texture |
| landcover.tif | 17.4 MB | North American land cover 2020 (30 m source, resampled) |
| elevation.tif | 3.6 MB | elevation |
| terrain.tif | 7.6 MB | terrain derivatives |
| layers-manifest.json | 8.9 kB | every band's name, source, build and checksum (layers key df57c9d4) |
| README.md, CHECKSUMS.sha256 | 1.0 kB, 0.8 kB | description; sha256 of every file |

Band-level sources and credits are in Section S3.

### Models record

| File | Size | Contents |
|---|---|---|
| maps-esm.tar | 7.72 GB | ensembles of small models: per model the suitability raster, the area-of-applicability raster and the map image |
| maps-maxnet.tar | 2.98 GB | Maxent models, as above |
| maps-rf.tar | 2.64 GB | random forests, as above |
| maps-xgboost.tar | 641.6 MB | boosted trees, as above |
| maps-ensemble.tar | 109.8 MB | combined maps and disagreement layers |

Full-extent rasters for strong models are in the release [CHECK: which bundle holds them].
| scores.tar.gz | 39.0 MB | every model's metrics JSON: held-out scores, null test, grade, importance, settings, and the pooled Boyce index |
| release.json | 10.4 MB | the release manifest and model index (taxon, algorithm, fingerprint, presences, settings key, refused) |
| taxa.json | 3.2 MB | per-taxon counts and status |
| collection-cells-0.1deg.tsv.gz | 784.3 kB | record cells at 0.1°, without records whose location the source hides, obscures or may hide |
| taxa-by-state-province.tsv.gz | 408.3 kB | state and province verdicts |
| prior-ranks.tsv.gz / .parquet | 11.2 / 15.2 MB | the location prior: suitability ranks |
| prior-aoa.tsv.gz / .parquet | 11.4 / 19.2 MB | the location prior: area of applicability |
| prior-models.tsv, prior-taxa.tsv, prior-grid.json | 20.8, 28.3, 4.3 kB | the prior's models, taxa and grid |
| explore-index-20km.tsv.gz / .json | 9.0 MB / 0.7 kB | the 20 km index behind the site's Explore view [CHECK] |
| renames.json, name-merges.json | 98.8, 23.1 kB | names changed or merged since earlier pulls |
| taxa-not-yet-validated.tsv.gz | 0.8 kB | [CHECK: contents] |
| pull.json | 0.3 kB | the pull's id, time and counts (the published pull, after the 76-record exclusion) |
| layers-manifest.json | 8.9 kB | the layers the models were fitted on (links the layers record) |
| README.md, CHECKSUMS.sha256 | 2.8, 2.1 kB | description; sha256 of every file |

The record's description states that the published counts (133,235
records, 16,252 taxa) are after the 76-record exclusion and that most models
were fitted on the pull before it (metadata edit, 2026-10-21). The deposit
does not name each model's fitting job; the next version adds a lineage
table (algorithm, taxon, fitting job, pull sha256) with the training-record
and contributor tables (Section S10; Open decisions 8).

## S11.2 Usage notes

- **Read the grade first.** Only strong maps support a claim about habitat.
  In the hindcast they were also the only grade to rank later finds better
  than distance to known records, and that gain was modest and came mostly
  from finds 100 to 500 km away (Section S6). Weak maps, including the
  moderate and indicative tiers, describe which ground near known records
  resembles occupied ground; failed maps did worse than weak ones.
- **Suitability is a rank within one taxon**, fitted against other
  collectors' survey sites rather than true absences. It is not a
  probability of occurrence and is not comparable between taxa.
- **The area of applicability** is hatched on every map; outside it the
  model extrapolates. Nothing is drawn beyond a taxon's 500 km accessible
  area.
- **Small samples.** Maps of taxa with 3 to 19 sites are ensembles of small
  models; at 3–4 sites 45% of them fail the null test.
- **Privacy.** Records whose location the source hides, obscures or may hide
  never appear in a published record-level layer, and carry no survey-site
  id in the training-record table.
- **Citing.** Cite a map by its release id and the release's DOI. Maps and
  rasters are CC BY-SA 4.0, so derived maps carry the same licence; the
  training-record table will be CC0 1.0.
- **Programmatic access.** The public, read-only API and its rate limits are
  listed in Section S10 (S10.1b).
- **Reporting a problem.** The site's "Report a map problem" link opens an
  issue on the code repository; or write to info@mycomap.org.
