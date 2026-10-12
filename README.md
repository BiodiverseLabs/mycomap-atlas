# MycoMap Atlas

Where could a fungus grow? Atlas answers that for North American fungi, using
only records whose identity was confirmed by DNA. It fits species distribution
models to MycoMap's DNA-validated collections and publishes the results as
versioned maps, scores and conservation metrics.

**See it live at [atlas.mycomap.org](https://atlas.mycomap.org).** Search for a
species, open its map, or click anywhere to see which fungi the models think
could grow there.

Atlas is part of [MycoMap](https://mycomap.org) but runs as its own service.
It reads mycomap.org's records through a read-only route and never writes
back; mycomap.org calls Atlas when it needs a map or a metric, and MycoMap
Vision (photo identification) calls it for a geographic prior.

## How it works

1. **Pull the records.** Every DNA-validated North American record with
   usable coordinates is pulled from mycomap.org. Exact coordinates stay on
   Atlas's own private machines and never reach this repository, a release or
   the API.
2. **Describe the land.** Climate, elevation, terrain, soil, land cover, forest
   type and host trees are put on one equal-area grid covering Mexico to
   northern Canada.
3. **Correct for where people collect.** A handful of states hold most
   sequenced collections. Each taxon is compared with every *other*
   DNA-validated fungus collected nearby (a target-group background), so the
   models learn what separates species, not where sequencing happened.
4. **Fit and test.** Maxent, boosted trees and a random forest are fitted side
   by side and scored on whole regions held out from training (spatially
   blocked cross-validation), against null models that keep the data's
   clustering. Taxa with only a few sites get ensembles of small models.
5. **Publish.** Maps, scores and per-state summaries are released together,
   versioned and reproducible: each release records its records'
   fingerprint, layer builds, code commit and package versions, and can be
   rolled back. Releases are built to be archived on Zenodo with DOIs; none
   has been deposited yet.

The full method, with the measurements behind each choice, is in
[docs/method.md](docs/method.md) and, for readers of the maps, on the site's
[Methods page](https://atlas.mycomap.org/methods).

## What is published, and what never is

- **Published:** suitability maps at 1 km or coarser, model scores, per-taxon
  counts, and where each taxon was collected aggregated to 0.1° cells.
- **Never published:** exact coordinates, raw pulls, training tables or
  training points, in any release, API response or commit. CI refuses any
  commit that adds data files.
- **No taxon is hidden or treated differently.** The same aggregation floor
  applies to every species. If you think a published map exposes a
  population, report it privately (see [SECURITY.md](SECURITY.md)).

## Status: phase 1 (validated specimens)

Phase 1 trains on validated mycomap.org specimen records only. eDNA, GlobalFungi and
weighting for unassessed records are phase 2.

Measured on production 2026-09-28, the eligible universe is **127,823 records
across 17,590 taxa**. By distinct ~1 km localities: 1,343 taxa have 20 or more,
808 have 30 or more, 331 have 50 or more. About a third of the taxa with 20 or
more carry provisional temp codes, which exist in no other dataset.

### Pipeline

| Stage | State |
|---|---|
| 1. Pull the eligible universe from mycomap.org | built |
| 2. Environmental layers on the grid | built: climate, elevation, terrain, soil, land cover, host trees (and wood-decay hosts), forest type in production; more held as sweep candidates |
| 3. Target-group background from the same validated universe | built |
| 4. Fits: Maxent, boosted trees and a down-sampled random forest, side by side | built, with batch runs and a benchmark; a small-model ensemble for taxa with too few sites for the full models |
| 5. Evaluation: spatially blocked folds, Boyce index, ecological review | built, with null models that keep a taxon's clustering, q-values, an area of applicability, and a virtual-species test bed |
| 6. Release: rasters and metrics published together, with rollback | running: nightly releases from EC2 spot workers since 2026-09-30. The nightly timer is paused while the method changes merged 2026-10-07 (every model is now stale) wait for one full rebuild |

## Using Atlas

- **The site:** [atlas.mycomap.org](https://atlas.mycomap.org) — maps, model
  scores, every taxon in the validated universe, data sources and the method.
- **The API:** open for reading, documented on the
  [Developers page](https://atlas.mycomap.org/developers) and in
  [`inst/api/openapi.json`](inst/api/openapi.json). It is in beta; breaking
  changes are announced in the [CHANGELOG](CHANGELOG.md) at least 30 days
  ahead. Raster downloads and higher rate limits need a sign-in or token:
  [docs/access.md](docs/access.md).
- **Citing:** every taxon page gives a citation with the release id; the
  current release is also in `/api/status`. The site's
  [Methods page](https://atlas.mycomap.org/methods) says how to cite the data
  and packages behind it.

## Running it yourself

Needs R 4.x; the web app needs Node and pnpm.

```bash
Rscript -e "install.packages(c('digest','jsonlite','testthat','plumber','terra','geodata'), repos='https://cloud.r-project.org')"
Rscript -e "testthat::test_local()"   # the tests run offline, no credentials
./atlas help                           # Git Bash; ./atlas.ps1 help in PowerShell
```

Pulling records needs access to mycomap.org's read-only SQL route, which most
contributors will not have; everything else, including the whole test suite,
works without it. The rest is in [docs/running.md](docs/running.md).

## Repository layout

| Path | What is there |
|---|---|
| `R/` | the pipeline: pulling records, layers, fitting, scoring, releases, the API |
| `inst/plumber/atlas.R` | the HTTP API's routes |
| `inst/api/` | the OpenAPI spec and the credited sources list, served by the API |
| `web/` | the site (React and Vite), styled to match mycomap.org |
| `tests/testthat/` | the test suite, all offline, on synthetic records |
| `deploy/` | server ([Lightsail](deploy/lightsail/README.md)) and [AWS](deploy/aws/README.md) setup |
| `tools/` | the CI guard that keeps data out of git, and boundary builders |
| `docs/` | [method](docs/method.md), [running](docs/running.md), [access](docs/access.md) |
| `atlas`, `atlas.ps1` | the command line, run straight from the sources |

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first: two
of its rules protect real collection localities. Report security problems and
exposed localities privately, as [SECURITY.md](SECURITY.md) describes. Contact:
info@mycomap.org.

## Licence

GPL-3.0-or-later; see [LICENSE.md](LICENSE.md). The modelling stack Atlas is
built on — terra, ENMeval, blockCV, ecospat — is GPL, so this is the licence
that fits without an argument.

Published maps, rasters and model outputs are CC BY-SA 4.0, separate from the
code: they are derived from WorldClim 2.1, which is CC BY-SA 4.0, and
ShareAlike carries over. The Zenodo archives say so, every map image and
raster response carries `Link: <https://creativecommons.org/licenses/by-sa/4.0/>; rel="license"`,
and the site shows the licence and the sources' credits beside every map and in
the footer. Each layer's own terms are in `inst/api/sources.json`; the Canadian
forest inventory requires the line "Contains information licensed under the
Open Government Licence - Canada".

The MycoMap name and logo (`web/public/mycomap-logo.png`, `web/public/favicon.png`)
are MycoMap's marks and are not covered by the GPL. A fork may keep the code but
should replace them.
