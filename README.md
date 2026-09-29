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
| 6. Release: rasters and metrics published together, with rollback | release format built (S3 or a folder); remote compute next |

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
Its pages: a species search (home), **Maps** (every fitted model), **Taxa**
(everything in the validated universe), **Data** (training records and
layers) and **How it works** (the method, for people rather than developers).
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
records. What that costs: there is no continental tree-species layer, so v1
carries tree cover as a fraction rather than host identity, and a model cannot
be read as knowing which host a fungus needs.

On the draft grid, 99.3% of pulled records land on a cell with climate data;
five records fall outside the grid altogether.

## Training data

A taxon's training table is its presences — one row per occupied cell — plus a
background drawn from the **target group**: every DNA-validated record of every
taxon, inside that taxon's accessible area.

```bash
./atlas training --taxon="Trametes versicolor"
```

Why not a random background: six states and provinces hold 61% of the records,
and Indiana alone holds 12%. Sampled at random from the continent, background
points would report that Indiana's climate suits almost every fungus. The
target group carries the same bias as the presences, so the model answers a
better question — given that somebody collected and sequenced a fungus here,
what makes it this species rather than another?

Two details matter. The background keeps its density, so a cell collected from
a hundred times counts a hundred times; that is the effort signal, not noise.
And the accessible area is the taxon's own cells buffered by 500 km, because a
species is not absent from Yukon merely because nobody looked there.

The seed comes from the taxon's record-set fingerprint, so the same records
always draw the same background, and changed records draw a new one.

## Fitting and scoring

```bash
./atlas fit --taxon="Armillaria nabsnona"
```

Maxent is fitted through `maxnet`, the reference implementation by Maxent's own
author. Folds are whole spatial blocks of 200 km, never a random split: fungal
records are clustered — one foray yields thirty collections from one wood — and
a random hold-out puts near neighbours on both sides, reporting a score that
only says the model can interpolate 200 m.

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
in a fixed **ecological** order — moisture, then temperature, then what the
fungus grows on, then soil, then the shape of the ground. When two variables
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

Exact coordinates never leave the machine that pulled them. Anything drawn on a
map is aggregated to 0.1 degrees, and published rasters are 1 km or coarser.

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
