# MycoMap Atlas

Species distribution models for fungi, built only from DNA-validated MycoMap
records, published as versioned maps and conservation metrics.

Atlas is a separate platform from mycomap.org. **.org is read, never written**:
records come from the read-only production SQL route, and .org calls Atlas when
it needs a map or a metric. MycoMap Vision calls Atlas for its geographic prior.

## Status: phase 1 (validated specimens)

Phase 1 trains on validated .org specimen records only. eDNA, GlobalFungi and
weighting for unassessed records are phase 2.

Measured on production 2026-09-28, the eligible universe is **127,823 records
across 17,590 taxa**. By distinct ~1 km localities: 1,343 taxa have 20 or more,
808 have 30 or more, 331 have 50 or more. About a third of the taxa with 20 or
more carry provisional temp codes, which exist in no other dataset.

### Pipeline

| Stage | State |
|---|---|
| 1. Pull the eligible universe from .org | built |
| 2. Environmental layers on the grid | built on the draft grid: climate, elevation, terrain, soil, land cover |
| 3. Target-group background from the same validated universe | built |
| 4. Fits: Maxent, boosted trees and a down-sampled random forest, side by side | built, with batch runs and a benchmark |
| 5. Evaluation: spatially blocked folds, Boyce index, ecological review | built |
| 6. Release: rasters and metrics published together, with rollback | built: S3 releases, jobs split into shards, EC2 spot workers; first real run next |

## Setup

Needs R 4.x on the path.

```bash
Rscript -e "install.packages(c('digest','jsonlite','testthat','plumber'), repos='https://cloud.r-project.org')"
```

The command line runs from the sources, with no install step:

```bash
./atlas help          # Git Bash
./atlas.ps1 help      # PowerShell
```

`pull-occurrences` needs the `mycomap-sql` SSH host (.org's read-only route):

```bash
./atlas pull-occurrences --dry-run        # print the SQL and stop
./atlas pull-occurrences --max-rows=500   # smoke test
./atlas pull-occurrences                  # the whole universe
./atlas status
```

### The release image

Releases are computed in the Docker image, never on a laptop, so a
Windows-versus-Linux difference cannot change a published map. Everything
that decides the output is pinned: the base image by digest
(`rocker/geospatial:4.6.1`), R packages to a dated Posit Package Manager
snapshot (`CRAN_SNAPSHOT`), and the code by the commit passed in as
`ATLAS_COMMIT`, which every release records. The build runs the whole test
suite, so an image whose tests fail is never built.

```bash
docker build --build-arg ATLAS_COMMIT=$(git rev-parse HEAD) -t mycomap-atlas .
docker run --rm -v "$PWD/data:/data" mycomap-atlas fit-all --workers=8
docker run --rm -v "$PWD/data:/data" -e ATLAS_STORE=s3://bucket/atlas   -e AWS_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY mycomap-atlas publish-release
```

The container computes as an ordinary user, with data mounted at `/data`. It
talks to S3 through `paws`, so it carries no AWS CLI.

### Web app

```bash
./atlas api                          # development API on :5100
cd web && pnpm install && pnpm dev    # app on :5101
```

The app carries mycomap.org's look the way MycoMap Vision does — the same
header, logo, footer, colour tokens, cream page-title band and shadcn
components — so someone moving between the three sites feels they never left.
Search is on every page (the header box, or `/` and Ctrl+K): it forgives typos,
word order and the many spellings of a provisional code, offers genera, and
puts taxa with maps first (`R/search.R`, `/api/search`). Its pages: the home
page (what Atlas is, a species search and a live map),
**Maps** (every fitted model), **Models** (the benchmark), **Taxa** (everything
in the validated universe), **Methods** (the method in full), **Data**
(training records and layers), **Sources** (every dataset, package and paper,
with links, and every product of the pipeline with whether it is published)
and **Developers** (the API reference).

The API reference and the Sources page are drawn from `inst/api/openapi.json`
and `inst/api/sources.json`, which the API also serves at `/api/openapi.json`
and `/api/sources`. Two tests keep them honest: `test-openapi.R` fails when a
route or parameter in `inst/plumber/atlas.R` and the spec disagree, and
`test-sources.R` fails when the code calls a package, or the web app depends
on one, that is not credited. Add a route or a dependency and its entry in the
same pull request.
When .org's header or palette changes, change `web/src/components/Layout.tsx`,
`web/src/index.css` and `web/tailwind.config.ts` to match.

## The grid

Everything is modelled on North America Albers Equal Area Conic, so a cell
covers the same ground in Oaxaca and in Nunavut. That matters twice: predicted
habitat is reported in km², and spatial blocking needs real distances.

Two grids share one extent and origin, and their cells nest exactly:

| Grid | Cell | Cells | Purpose |
|---|---|---|---|
| `draft` | 5 km | 3.7 million | developing the pipeline |
| `production` | 1 km | 94 million | releases |

```bash
./atlas build-layers --only=elevation,bioclim,terrain
```

```bash
./atlas layers
```

Sources are global, because the obvious United States products (TreeMap, NLCD,
PAD-US) stop at the lower 48 while British Columbia alone holds 8% of the
records.

The exception is the host-tree layer (`hosts`, R/hosts.R): 20 bands, the
share of a cell's trees in each of 19 ectomycorrhizal host genera
(`host_pinus`, `host_quercus`, ...) and the share that are conifers
(`host_conifer`), 0 to 1. No continental tree-species map exists, so it joins
the two national forest inventories:

| Where | Source | Read as |
|---|---|---|
| Lower 48 | USFS FIA BIGMAP 2018 species biomass (public domain), from its ImageServer | 250 m point samples, averaged; genus biomass over the biomass of all species |
| Canada | NFI kNN 2011 species composition, 250 m (Open Government Licence - Canada) | species percentages summed by genus (an NFI `_Spp` file is unidentified members of the genus, not a total), over needleleaf + broadleaf |

Where there are no trees the share is 0. Alaska, Hawaii, Puerto Rico and
Mexico are in neither inventory. One layer's gap must not take ground away
from every model, so there the shares are filled with 0 and a twenty-first
band, `host_known`, is 0 (1 wherever an inventory spoke): those records still
train models, those places are still mapped, and a model can tell "no such
trees" from "nobody mapped the trees" (`atlas_fill_outside`, R/layers.R).
BIGMAP's own
`SPCD_0000_Total` is not used as the denominator: it is modelled apart from
the species and runs about 15% above their sum. Both inventories are summed
onto 1 km cells once, under `data/layers/raw/hosts/`, and each grid is built
from those sums (a first build reads all 327 BIGMAP species, about two to
three hours, and 2 GB of NFI files).

```bash
./atlas build-layers --only=hosts --grid=draft
```

### Candidate layers

Five more layers are built only into a separate data directory, and measured
by `./atlas sweep-layers` before any of them is fitted on in production
(R/layersweep.R): forest type (`foresttype`, NALCMS 2020), water balance and
fruiting-season climate (`waterbalance`, ClimateNA 1991-2020 and
TerraClimate), carbonate bedrock (`bedrock`, GLiM), landform (`landform`:
wetness, northness, heat load) and a second host-tree layer (`hosts_wilson`,
bands `hostw_*`: USFS basal area 2000-2009 with the Canadian inventory, ten
genera), kept as a rival to `hosts` so the two can be compared. The sweep
scores every arm on the same sites and folds, under the design production
uses, and reports how many records each layer cannot describe.

On the draft grid, 99.3% of pulled records land on a cell with climate data;
five records fall outside the grid altogether.

## Training data

A taxon's training table has one row per **survey site** inside its accessible
area: detected (the taxon was collected there) or not (other DNA-validated
fungi were collected there, but not it), with the site's predictors and its
**effort**, log(1 + records of other taxa at the site). The comparison is the
**target group**: every DNA-validated record of every taxon.

```bash
./atlas training --taxon="Trametes versicolor"
```

Why not a random background: six states and provinces hold 61% of the records,
and Indiana alone holds 12%. Sampled at random from the continent, background
points would report that Indiana's climate suits almost every fungus. The
target group carries the same bias as the presences, so the model answers a
better question — given that somebody collected and sequenced a fungus here,
what makes it this species rather than another?

Sites (`R/sites.R`) are made once from the whole pull: cells with records are
thinned by distance, busiest first, so no two sites are closer than 5 km, and
every other record joins its nearest site. Both detections and non-detections
count once per site. An earlier design counted presences per cell but drew the
background per record, so a wood collected a hundred times counted a hundred
times against every species found there, and well-surveyed ground looked worse
than it was. Effort is now a predictor instead, held at the median of the
taxon's detection sites whenever a map is drawn or scored (Warton, Renner &
Ramp 2013; Fithian et al. 2015). A taxon's own records are left out of its
sites' effort, or a fungus collected a hundred times in one wood would make
that wood look well surveyed by being there. The spacing is in km, not cells, so the 1 km
grid does not turn one foray into five presences.

The accessible area is the taxon's own sites buffered by 500 km, because a
species is not absent from Yukon merely because nobody looked there. The seed
comes from the taxon's record-set fingerprint, so the same records always draw
the same sites and folds, and changed records draw new ones.

## Fitting and scoring

```bash
./atlas fit --taxon="Armillaria nabsnona"
```

Maxent is fitted through `maxnet`, the reference implementation by Maxent's own
author. Folds are whole spatial blocks, never a random split: fungal records
are clustered — one foray yields thirty collections from one wood — and a
random hold-out puts near neighbours on both sides, reporting a score that only
says the model can interpolate 200 m.

- **Block size** comes from blockCV: the range of a variogram of the taxon's
  detections, rounded to 5 km and held between 50 and 300 km (`--block-km=N`
  fixes it). Blocks holding detections are dealt to folds first, evenly. A
  taxon needs detections in at least 5 blocks to be scored at all.
- **Settings are tuned in nested spatial folds**: each held-out region is
  scored by a model whose settings (Maxent's feature classes and regularisation
  multiplier, the trees' depth and count, the forest's mtry) were chosen on
  inner folds of the other regions only.
- **Null models** (`--nulls=N`, default 19): the same number of sites drawn at
  random from all surveyed sites, busier ones more often, fitted and scored the
  same way. The taxon and its nulls go through one procedure, the algorithm's
  untuned settings, because settings tuned on the real detections and handed
  to the nulls would favour the taxon. A map is `skill: passed` when the
  taxon's AUC beats every null (p ≤ 0.05) and its Boyce index is above zero;
  failed maps are drawn faint, hidden from the Maps list by default and left
  out of the Explore index and release consumers.
- **One Boyce index** (`boyce`), over the held-out scores of every fold
  together. Twenty sites leave four detections in a fold, too few for an index
  of their own; the mean over folds is kept as `boyce_mean`.

The measurements below were taken under the earlier design (per-cell presences,
per-record background, fixed 200 km blocks, default settings).

**Read AUC as comparative, not absolute.** Against a target-group background it
measures how distinguishable a species is from where fungi get collected at
all, so a generalist scores near 0.5 by construction. That is the honest
answer, not a broken model. Measured on the draft grid:

| Taxon | Presence cells | Predictors | Blocked AUC |
|---|---|---|---|
| *Mycena* sp. 'IN10' | 150 | 19 | 0.70 |
| *Trametes versicolor*, everywhere there is wood | 294 | 18 | 0.57 |
| *Armillaria nabsnona*, coastal Pacific Northwest | 47 | 11 | 0.58 |

*A. nabsnona* scored 0.72 in an earlier run, and that number was wrong. Slope
was empty on every coastal cell, so those records were dropped — from the
presences and, more damagingly, from the background. A coastal species
compared against an inland-only background is trivially separable. Fixing the
terrain layer lowered the score, which is the direction of truth rather than a
regression.

## Choosing predictors

Thirty-three predictors is a lot of rope for a taxon with forty-seven records,
and the nineteen bioclim variables are near-copies of one another. Correlated
predictors are pruned before fitting, keeping whichever of a pair comes first
in a fixed **ecological** order — soil pH, moisture, then temperature, then what the
fungus grows on, then soil, then the shape of the ground. Where the host trees
go depends on the guild of the fungus's genus in FungalTraits (Põlme et al.
2020): straight after soil pH for ectomycorrhizal genera, after temperature for
everything else, and each model records its guild and the order it was given.
The trees have an allowance: a third of an ectomycorrhizal fungus's predictors,
a fifth of any other's. The twenty host bands are barely correlated, so without
it a fungus with forty sites spent its ten predictors on soil pH and nine
trees and had no climate at all. The ones kept are the conifer share and then
the commonest trees of the region, judged on the non-detection sites, never on
the detections.
FungalTraits' licence is unclear, so the table is used for lookup only: fetch
it into the data directory with `./atlas fetch-guilds`; it is never committed,
released or served. Without it every guild reads "unknown". A changed table
makes every Maxent model stale (its hash is in the settings); the tree models
take every predictor and are unaffected. When two variables
are interchangeable to the model, the one a mycologist would name survives,
which also keeps the response curves readable. Correlations are measured on
the background, never on the presences: forty-seven records cannot estimate a
correlation matrix.

How much that helps depends entirely on how many records there are. Blocked
AUC across a threshold sweep:

| Predictors kept | *A. nabsnona* (47) | *Mycena* 'IN10' (150) | *T. versicolor* (294) |
|---|---|---|---|
| ~10–13 (r < 0.5) | **0.610** | 0.689 | 0.552 |
| ~14–17 (r < 0.6) | 0.594 | 0.690 | 0.566 |
| ~17–19 (r < 0.7) | 0.552 | 0.700 | 0.574 |
| all 33 | 0.512 | **0.706** | **0.580** |

A sparse taxon gains a tenth of an AUC from a short list; a well-recorded one
loses a little. So the count is capped in proportion to the presences, roughly
one predictor per four records, and the cap stops binding once a taxon is well
recorded. The ratio is the mechanism; the correlation threshold only decides
which of two twins gets dropped.

Those three taxa overstated it. A sweep over 153 taxa (`./atlas
sweep-predictors`, up to 40 per band of presence cells) scored each taxon at
several ratios on one set of folds, so every comparison is a taxon against
itself. Differences from one per four, with standard errors:

| Ratio | AUC, 20–29 cells | Boyce, 20–29 | Boyce, 30–49 | Boyce, all |
|---|---|---|---|---|
| 1 per 2 | +0.003 ± 0.010 | −0.030 ± 0.026 | −0.062 ± 0.026 | −0.024 ± 0.010 |
| 1 per 3 | +0.002 ± 0.006 | +0.012 ± 0.026 | −0.015 ± 0.021 | −0.002 ± 0.009 |
| 1 per 6 | 0.000 ± 0.002 | +0.006 ± 0.006 | +0.024 ± 0.022 | +0.015 ± 0.008 |
| no cap | −0.016 ± 0.012 | −0.089 ± 0.033 | −0.070 ± 0.027 | −0.041 ± 0.012 |

The cap earns its place, but not through AUC: across sparse taxa it is worth
about 0.02 of AUC, not the tenth *A. nabsnona* suggested. Where it shows is
Boyce — whether higher suitability really holds more records — which falls
clearly without a cap. One per four sits within noise of the best on both
measures; one per six trades a little AUC for a little Boyce, and one per two
is worse. The ratio stays at four. Above about 100 presence cells no ratio
binds, since correlation pruning alone leaves 18 predictors.

Below 20 presence cells a taxon is refused rather than modelled, and the
threshold bites on record counts that look generous: *Lysurus mokusin* has 105
records from 4 distinct cells — one urban population, collected over and over.

## Fitting every taxon

```bash
./atlas fit-all --limit=24 --workers=12   # a trial on the 24 richest taxa
./atlas fit-all --workers=12              # every taxon with 20+ presence cells
./atlas fit-all --no-predict              # scores only, no maps
```

A batch reads and projects the pull once and opens the predictor stack once,
then fits each taxon in turn, richest first. It refits only what changed: a
stored model is skipped when its record-set fingerprint **and** its settings
match, and the settings include which build of each layer it was fitted on. A
nightly run after a quiet day fits almost nothing; a run after a layer rebuild
fits everything. `--force` refits regardless, which is what to use after a
change to the fitting code itself.

One taxon failing never stops the run. A refusal (too few presence cells once
cells without predictor data are dropped) and a failure (anything else) are
counted apart. Progress goes to `data/batches/<grid>/batch-<stamp>.log`, flushed
line by line, and the summary to `batch-<stamp>.json` and `latest.json`,
rewritten after every taxon so a stopped run still says what it finished. A
run with any failure exits non-zero.

Where the time goes, measured on the draft grid:

| Stage | *A. nabsnona* (47 cells) | *T. versicolor* (294 cells) |
|---|---|---|
| Read and project the pull (once per batch) | 15 s | — |
| Training table and predictors | 0.7 s | 1.4 s |
| Five blocked cross-validation fits | 27.7 s | 63.2 s |
| Final fit | 9.7 s | 12.6 s |
| Predict, write and draw the map | 5.3 s | 13.0 s |

The fitting is the cost, not the map, so `--no-predict` saves only about a
tenth. What makes a full run practical is `--workers`: each worker is a
separate R process holding its own stack, fitting one taxon at a time and
taking the next as soon as it finishes. A worker holds 0.8–1 GB.

On a 24-core machine, the 24 richest taxa (107 to 294 cells) took 217 s on 12
workers, against roughly 40 minutes one after another. Fits slow down when
they share the machine — *T. versicolor* took 140 s instead of 90 — but
throughput still rose elevenfold. Smaller taxa are quicker, so ~800 taxa on 12
workers is on the order of an hour or two.

## Three models, side by side

Every taxon is fitted three ways, and the app shows the three maps next to
each other, panning together, with their scores in one table:

| Model | Package | Predictors |
|---|---|---|
| Maxent | `maxnet` | pruned for correlation, capped by records |
| Boosted trees | `xgboost` | all of them |
| Down-sampled random forest | `ranger` | all of them |

They share the training table, the background and the spatial folds; only
the learner differs. Boosted trees give presences and background equal total
weight, and choose their tree count by early stopping on spatially blocked
folds inside the training data. The random forest grows each tree on as many
background records as presences, drawn afresh per tree (Valavi et al. 2021,
2022).

```bash
./atlas fit --taxon="Pluteus petasatus" --algorithm=rf
./atlas fit-all --algorithms=all --workers=12
./atlas benchmark-models --per-band=250 --workers=14
```

Maxent keeps its original paths (`models/<grid>/<taxon>.*`); the others live
in `models/<grid>/<algorithm>/`. Each model has its own currency check, so a
nightly run refits each only when its own inputs change.

### The benchmark

`benchmark-models` scores every taxon with 50+ presence cells under each model
on one set of folds, so each comparison is a taxon against itself. On the
draft grid, 268 taxa, differences from Maxent with standard errors:

| Model | AUC | Boyce | Best AUC | Scoring time |
|---|---|---|---|---|
| Random forest | +0.020 ± 0.002 | +0.131 ± 0.010 | 54% | 13 s |
| Boosted trees | −0.002 ± 0.003 | −0.016 ± 0.011 | 15% | 11 s |
| Boosted trees on Maxent's predictors | −0.011 ± 0.003 | −0.015 ± 0.011 | 10% | 8 s |
| Maxent | — | — | 21% | 58 s |

The down-sampled forest is clearly ahead, on both measures and in every band
of presence cells.

Extending the benchmark down to 20 presence cells (475 taxa) found where
boosted trees break: at 20–29 cells their Boyce was 0.35 below Maxent's and
negative on average, so their maps ranked ground backwards; at 30–49 it was
0.24 below. From 50 cells they match Maxent. So boosted trees are only fitted
and shown from 50 presence cells (`min_presences` in `R/algorithms.R`); below
that the taxon page says why their map is missing, and a full `fit-all`
removes tree maps for taxa under the line. The forest never did worse than
Maxent in any band, and Maxent still had the best AUC for a third of the
sparsest taxa. Boosted trees match Maxent, and do worse when restricted to
Maxent's predictors, which is why the trees get every predictor. Scoring time
is the five blocked folds; drawing a forest's map is slower (about 2.5 minutes
for a widespread taxon), since a thousand trees have to be asked about every
cell.

### Colours are ranks

The models put their scores on different scales — on *Pluteus petasatus*,
Maxent spans 0.03–1.00 across its map, boosted trees 0.27–0.63 — so each map
is drawn by percentile within its own accessible area: the darkest green is
the ground that model rates highest. Stored rasters keep the raw values.
`./atlas redraw-maps --workers=12` redraws every map without refitting.

The Models page in the app shows the latest benchmark and, for the maps in
production, how many taxa each model has mapped and their median scores.

## Releases

Atlas is computed remotely and pulled everywhere else. No machine is the
source of truth; a store is: an S3 bucket in production, a plain folder on a
laptop or in tests.

```bash
./atlas publish-release --store=s3://bucket/atlas --note="weekly refresh"
./atlas pull-release    --store=s3://bucket/atlas      # only what changed
./atlas releases        --store=s3://bucket/atlas      # * marks the current one
./atlas promote-release --store=s3://bucket/atlas --release=<id>   # roll back
```

`ATLAS_STORE` saves repeating `--store`. Inside the store:

```
objects/<aa>/<sha256>          every file ever published, stored once by content
releases/<grid>/<id>.json      a manifest: path -> sha256, plus provenance
current/<grid>.json            which release is live
```

A release that changes 200 taxa uploads only their files, a pull downloads
only files whose content changed and checks each against its hash, and rolling
back rewrites one pointer. A publish identical to the current release is
skipped. Each manifest records the code commit, package versions, the layer
builds and the pull's fingerprint.

What goes in is an allowlist: every algorithm's scores, rasters and maps, the
per-taxon counts, a summary of the pull (without its SQL or host), the layer
manifest, the newest benchmark, and where each taxon was collected as 0.1°
cells. Raw pulls, training tables and exact coordinates are never published.
A machine that only pulls releases, like the web server, answers every API
route from them. A pull also removes local model files the release does not
have, so the machine shows exactly what was published (`--keep-local` to
keep them).

On the draft grid today a release is 8,153 files and 2.4 GB: publishing it the
first time took 54 s into a local folder, a first pull 2 min 14 s, and a pull
with nothing new 17 s.

## What could grow here

The Explore page (`/here`, route `/api/here`) answers a click on the map with
every mapped fungus whose maps rate that place highly. Asking 2,700 rasters
about a point takes a minute, so it answers from an index built once from the
maps (`R/here.R`):

```bash
./atlas build-here-index            # after a batch of fits or a redraw
```

The continent is cut into 20 km squares aligned with the grid. For each model
the index keeps the squares where it ranks the ground in the top half of its
own accessible area, as the same percentile the maps are coloured by. A
taxon's score at a place is the mean of its models' ranks there, a model that
does not rate it in its top half counting as zero, so one keen model among
three indifferent ones does not top the list. Taxa collected within 25 km are
marked, counted from the 0.1° public cells, and taxa collected nearby with no
map yet are listed apart as survey targets. The index holds ranks by square
and nothing about records; it ships with every release. The API projects a
click onto the grid in plain R (Snyder's Albers formulas, tested against
terra to within a metre), so the web server needs no GDAL.

## Archives on Zenodo

Big downloads live on Zenodo, versioned, each version with its own DOI.
Two records per grid, each a series of versions under one concept DOI:

| Series | Holds | New version when |
|---|---|---|
| `layers-<grid>` | the predictor GeoTIFFs and their manifest | a layer is rebuilt |
| `models-<grid>` | per-model map archives, all scores, taxon counts, 0.1° collection cells, the release manifest | a release is archived |

Every version carries a README and `CHECKSUMS.sha256`. A models version names
the layers version it was fitted on (matched by the layer builds, not by
date) and links it as `isDerivedFrom`. An unchanged release or layer build is
never deposited twice.

```bash
./atlas archive-release --sandbox --dry-run          # what would go up, and how big
./atlas archive-release --sandbox                    # a draft on sandbox.zenodo.org
./atlas archive-publish --series=models-draft-sandbox
./atlas archive-release --publish                    # the real thing, DOIs minted
./atlas archives                                     # every version and its DOI
```

A run leaves a draft unless given `--publish`, because publishing mints the
DOI and can never be undone; check the draft on Zenodo, then
`archive-publish` (or `archive-discard`). The token is `ZENODO_TOKEN`, a
personal access token with `deposit:write` and `deposit:actions`; the sandbox
needs its own token from sandbox.zenodo.org. Which release went to which DOI
is kept in `archives/<series>.json` in the store, pulled with every release,
and served at `/api/downloads`. Sandbox series end in `-sandbox` and never
mix with real ones. Creators, licence, keywords and related identifiers are
in `inst/archive/zenodo.json`.

A record holds at most 100 files and 50 GB, which is why maps are packed per
model. The draft grid's models come to about 2.3 GB and the 1 km layers to
2.2 GB; 1 km models will be far larger, and the archive refuses anything over
the limit before uploading.

## Access, sign-in and tokens

Reads are open: every page, map image, score and count is served to anyone.
Two things need the caller to be known, as a person signed in on the site or
a script with a token: **downloading a model's GeoTIFF**
(`/api/taxa/<name>/raster.tif`) and a **higher rate limit**.

Every caller is rate limited: anonymous callers per address, signed-in people
per person, tokens per token. Tokens identify a caller; they do not protect
the server, since a flood arrives before any key can be checked. Caching does
that work: responses carry `Cache-Control`, and a map requested with its
version (`?v=`) never changes at that address, so a CDN in front of the API
answers repeat requests without reaching it. `/api/me` and downloads are
`private, no-store`.

**Signing in** uses mycomap.org's sign-in bridge; Atlas has no accounts. The
browser goes to `/auth/dev-bridge/start`, on to mycomap.org, and back to
`/auth/dev-bridge/callback` with a token .org signed with its Ed25519 private
key. Atlas holds only the public key, so it can check a token but never make
one. The token must be fresh (60 s), for this site's origin and for the nonce
this browser was given; then Atlas sets its own cookie, `__Host-atlas_session`
(HMAC-signed, 14 days, HttpOnly, Secure, SameSite=Lax), and nothing is shared
with mycomap.org's cookies. `POST /auth/logout` from the site's own pages
clears it. The code is in `R/auth.R`.

**Tokens** are issued by mycomap.org, per account, and approved there by an
admin (`https://mycomap.org/atlas-tokens`). A script sends
`Authorization: Bearer <token>`. Atlas asks .org's introspection route whether
a token is live and caches the answer for five minutes (a minute for a
rejection), keyed by a hash of the token. A token .org rejects gets `401` with
the reason. If .org cannot be reached the caller is treated as anonymous for
that request (read at the anonymous rate, no downloads), and nothing is
cached. The code is in `R/access.R`.

**Downloads** (`R/download.R`): the public server keeps only a release's PNGs
and JSON, so a raster is looked up in the current release's manifest and
answered with a `302` to a presigned S3 link that works for five minutes. A
file on the machine, or a store that is a local folder, is sent directly.

**Addresses.** The API trusts `X-Forwarded-For` only when the request comes
from this machine (nginx on the same host), and only its right-most entry, the
one nginx wrote. Behind Cloudflare, nginx has to restore the visitor's address
first (`set_real_ip_from` for Cloudflare's ranges and
`real_ip_header CF-Connecting-IP`), or everyone arriving through one
Cloudflare edge shares an allowance.

The settings are environment variables, so no secret enters the repository.
Anything missing is named in a `[CONFIG-ALERT]` line when the API starts, and
that feature stays off rather than the API failing:

| Variable | Default | Meaning |
|---|---|---|
| `ATLAS_PUBLIC_ORIGIN` | unset | This site's origin, e.g. `https://atlas.mycomap.org`. Sign-in tokens must name it exactly, and sign-out must come from it. |
| `ATLAS_SIGNIN_ISSUER` | `https://mycomap.org` | Who signs people in, and whose introspection route checks tokens. |
| `ATLAS_BRIDGE_PUBLIC_KEY` | unset | .org's bridge public key (Ed25519, PEM; literal `
` allowed). |
| `ATLAS_SESSION_SECRET` | unset | At least 32 characters, for signing the session cookie. Unset, sign-in answers 503 and nobody is signed in. Changing it signs everyone out. |
| `ATLAS_INTROSPECTION_SECRET` | unset | The shared secret .org gave Atlas for its introspection route. Unset, tokens are ignored. |
| `ATLAS_KEY_INTROSPECT_URL` | issuer's `/api/service-keys/introspect` | Only to point at a stand-in. |
| `ATLAS_STORE` | unset | The release store; downloads not on disk are looked up there. |
| `ATLAS_RATE_ANONYMOUS` / `_STANDARD` / `_BULK` | 300 / 1,200 / 6,000 | Requests per minute. Signed-in people get the standard rate. The spec's `x-rate-limits` must match the defaults (a test checks). |
| `ATLAS_REQUIRE_TOKEN` | off | `true` makes every route need a token or a session. |
| `ATLAS_ALLOWED_ORIGINS` | the dev app | `*` on the public server, so any site can call the API from a browser. No response allows credentials, so another site's page never uses a visitor's session. |

## Jobs: one refit, split across machines

A job recomputes whatever changed, on as many machines as are to hand. Three
steps, each on whatever machine suits it:

```bash
./atlas publish-layers --store=$S                      # once per layer build
./atlas plan-job   --store=$S --shards=8               # the small always-on box
./atlas run-shard  --store=$S --job=<id> --shard=3     # each worker, from an empty disk
./atlas job-status --store=$S --job=<id>
./atlas finish-job --store=$S --job=<id>               # back on the small box
```

- **plan** compares each taxon's record set with the current release's model
  index, lists the (taxon, model) pairs to fit, splits them into shards of
  similar cost (a forest's map, and a big range, cost most), and puts the job
  and its inputs — the pull and the layers — in the store. It reads the
  release's index rather than its models, so it needs no model files. With
  nothing changed there is nothing to plan.
- **run** fetches the inputs, fits exactly its share, uploads the results, and
  writes the shard's record last, so a record means the shard finished.
- **finish** checks every shard reported and that no other release became
  current meanwhile, then builds the new release from the old one: refitted
  models replaced, retired and refused ones removed, public files refreshed. A
  model that failed keeps its previous version and is planned again next time.
  A refusal is recorded against its record set, so it is not retried until the
  records change.

On the draft grid, a real two-shard job — each worker starting from an empty
data directory — fetched 103 MB of inputs, fitted its model and uploaded it in
40–66 s, and finishing assembled the 8,153-file release from the previous one.

### On EC2

In production the small box plans and finishes, and every fit runs on EC2
spot workers it launches for the job, one per shard:

```bash
./atlas nightly                      # pull, plan, run on EC2, finish: the box's cron job
./atlas run-job-ec2 --job=<id>       # run an already planned job
./atlas pull-release --no-rasters    # the box keeps maps and scores; rasters stay in S3
```

The box plans with whatever FungalTraits table it holds (`./atlas
fetch-guilds`, once) and ships it to the workers as a job input, never as a
release file. A worker whose table differs from the plan's refuses its shard.

A worker boots Amazon Linux, pulls the release image built from the box's own
commit (CI publishes one for every commit on main), runs its shard and shuts
down, which deletes it. A shard whose spot instance is reclaimed is launched
again, up to three times; with no spot capacity, a launch tries each allowed
instance type in each zone and otherwise waits for the next poll. Every
worker has a shutdown timer set to the job's deadline (6 h by default), and
if the job fails or overruns, the box terminates them all; the next night's
plan picks the same work up. A box without layers of its own plans from the
layer set in the store and fetches only its manifest.

What each identity may do is enforced by AWS, not only by this code: see
[deploy/aws/README.md](deploy/aws/README.md) for the policies, the setup and
the box's settings.

## Data

Everything lives under `data/`, which is never committed (override with
`ATLAS_DATA_DIR`):

- `raw/occurrences/<stamp>/` — every page exactly as pulled
- `occurrences/occurrences-<stamp>.tsv.gz` — the combined pull
- `occurrences/latest.json` — counts, fingerprint and the SQL used
- `occurrences/taxa-latest.json` — per-taxon records, localities, fingerprint

### Eligibility

A record is eligible when it is **green in at least one validation project and
red in none**, has coordinates that are present, unobscured, and accurate to
within 1 km where an accuracy was recorded, sits in North America, and carries
a species-level name (provisional temp codes included).

Records green only in a fourth or later project are missed, because .org
flattens three validation slots. Vision has the same limitation, and the fix
for both is a shared view on .org rather than a change here.

### One taxon, one name

.org holds some taxa under several spellings: *Mycena* sp. 'IN10' and
*Mycena* "sp-IN10", 'fuscidisca PNW10' and 'fuscidisca-PNW10', curly quotes
and straight, a trailing non-breaking space. Spellings that differ only in
punctuation, or only by an author citation (*Pluteus cervinus* (Schaeff.) P.
Kumm.), are merged and modelled under the one most records use; letters and
digits are never touched, so 'IN1' and 'IN01' stay apart, and a name with a
digit keeps every word, because "Cuphophyllus pratensis PNW06" is a lineage
code, not an author. Every record
keeps its original spelling, and `occurrences/name-merges.json` (published in
releases) lists every merge so the names can be fixed on .org. On the
2026-09-28 pull, 423 spellings merged in all (59 of them by author
citation), leaving 17,161 taxa. `./atlas refresh-names` rebuilds the counts
and the report from an existing pull.

Without the merge the records were split between spellings, and where two
spellings both cleared the threshold they shared a file name and one map
silently replaced the other. A fit now refuses to overwrite another taxon's
model.

### Coordinates

Exact coordinates stay inside Atlas's own private compute and storage: the
machine that pulled them, the EC2 workers a job runs on, and the private S3
bucket that carries the pull to those workers. They are never published — not
in a release, the API, the web app or this repository. Anything drawn on a map
is aggregated to 0.1 degrees, and published rasters are 1 km or coarser.

## Tests

```bash
Rscript -e "testthat::test_local()"
```

## Licence

GPL-3.0-or-later; see [LICENSE.md](LICENSE.md). The modelling stack Atlas is
built on — terra, ENMeval, blockCV, ecospat — is GPL, so this is the licence
that fits without an argument.

Published maps and metrics are a separate question from the code. Their terms
follow the source layers, and WorldClim's CC BY-SA 4.0 has to be settled before
the first release.

The MycoMap name and logo (`web/public/mycomap-logo.png`, `web/public/favicon.png`)
are MycoMap's marks and are not covered by the GPL. A fork may keep the code but
should replace them.
