# Appendix S1: Section S11. Data records and usage notes

*Draft, 2026-10-25. File lists and sizes were read from Zenodo's public
API on 2026-10-25; contents from the layers manifest and Atlas's archive
and layer code (operations lane, 2026-10-25).*

## S11.1 Records on Zenodo

| Record | DOI | Version | Files | Size | Licence |
|---|---|---|---|---|---|
| Environmental layers | 10.5281/zenodo.23463069 (concept 23463068) | draft-2026-09-30-df57c9d4 | 11 | 0.15 GB | CC BY-SA 4.0 |
| Models of the frozen release | 10.5281/zenodo.23463939 (concept 23463938) | 20261013T191324Z-fa1b4198 | 26 | 14.21 GB (13.24 GiB) | CC BY-SA 4.0 |
| Training records, contributors, model lineage | next version of the models record | [PENDING: E19, E20] | | | training-record table CC0 1.0; the rest CC BY-SA 4.0 |

### Layers record (eight files, 77 bands: the 69 predictors plus coverage and fill flags)

| File | Size | Contents |
|---|---|---|
| bioclim.tif | 62.6 MB | WorldClim 2.1 bioclimatic variables (1970–2000) |
| hosts.tif | 20.9 MB | host trees: share of trees by genus and the conifer share, 21 bands (20 hosts, among them *Pinus*, *Quercus*, *Picea*, *Abies*, *Pseudotsuga*, *Tsuga*, *Betula*, *Populus*, *Fagus*, *Larix* and *Castanea*, plus a coverage flag); USFS FIA BIGMAP 2018 (lower 48) and Canada NFI kNN 2011 |
| hostsdecay.tif | 7.4 MB | decay and parasite hosts: share of trees by genus, 10 bands (*Acer*, *Fraxinus*, *Ulmus*, *Juniperus*, *Thuja*, *Liriodendron*, *Prunus*, *Liquidambar*, *Platanus*, *Robinia*); same sources |
| foresttype.tif | 6.6 MB | needleleaf, broadleaf and mixed forest shares, plus a coverage flag (4 bands); NALCMS Land Cover 2020 v2, 30 m (CEC), with Copernicus 2019 filling Hawaii and the Caribbean |
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
| maps-esm.tar | 7.72 GB | ensembles of small models |
| maps-maxnet.tar | 2.98 GB | Maxent models |
| maps-rf.tar | 2.64 GB | random forests |
| maps-xgboost.tar | 641.6 MB | boosted trees |
| maps-ensemble.tar | 109.8 MB | for each of the 77 taxa with two or more strong maps, the combined map (3-band GeoTIFF: weighted mean rank; the members' weighted rank SD as disagreement; the share of members known) with its drawn map and disagreement map (PNG); each ensemble's settings and statistics are in scores.tar.gz |
| scores.tar.gz | 39.0 MB | every model's metrics JSON: held-out scores, null test, grade, importance, settings, and the pooled Boyce index |
| release.json | 10.4 MB | the release manifest and model index (taxon, algorithm, fingerprint, presences, settings key, refused) |
| taxa.json | 3.2 MB | per-taxon counts and status |
| collection-cells-0.1deg.tsv.gz | 784.3 kB | record cells at 0.1°, without records whose location the source hides, obscures or may hide |
| taxa-by-state-province.tsv.gz | 408.3 kB | state and province verdicts |
| prior-ranks.tsv.gz / .parquet | 11.2 / 15.2 MB | the location prior: suitability ranks |
| prior-aoa.tsv.gz / .parquet | 11.4 / 19.2 MB | the location prior: area of applicability |
| prior-models.tsv, prior-taxa.tsv, prior-grid.json | 20.8, 28.3, 4.3 kB | the prior's models, taxa and grid |
| explore-index-20km.tsv.gz / .json | 9.0 MB / 0.7 kB | the Explore index: every strong map's rank in each 20 km cell (cell, taxon, algorithm, rank); the .json gives the grid and how to place a point in a cell |
| renames.json, name-merges.json | 98.8, 23.1 kB | names changed or merged since earlier pulls |
| taxa-not-yet-validated.tsv.gz | 0.8 kB | per taxon (57 rows), the count of its records on mycomap.org not yet validated, and how many of those have coordinates |
| pull.json | 0.3 kB | the pull's id, time and counts (the published pull, after the 76-record exclusion) |
| layers-manifest.json | 8.9 kB | the layers the models were fitted on (links the layers record) |
| README.md, CHECKSUMS.sha256 | 2.8, 2.1 kB | description; sha256 of every file |

Each maps-<model>.tar holds, per taxon, the raw suitability raster (.tif),
the area-of-applicability dissimilarity raster (.di.tif, a continuous
dissimilarity index rather than a binary mask) and the drawn map (.png, Web
Mercator, coloured by percentile). The rasters are GeoTIFF on North America
Albers Equal Area, inside the 500 km accessible area; for strong models the
same three files come again beyond it (.full.*). Each model's scores, folds,
predictors and settings are in scores.tar.gz.

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
