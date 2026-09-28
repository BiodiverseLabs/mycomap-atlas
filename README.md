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
| 4. Fits: `maxnet` at 20+ localities, `xgboost` on the richest | maxnet built; xgboost next |
| 5. Evaluation: spatially blocked folds, Boyce index, ecological review | built |
| 6. Release: rasters and metrics published together, with rollback | |

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

### Web app

```bash
./atlas api                          # development API on :5100
cd web && pnpm install && pnpm dev    # app on :5101
```

The app follows mycomap.org's design tokens so the two navigate alike, since
.org will link to it.

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

Three taxa is enough to see the direction, not to fix the constant. Re-measure
when batch fitting gives hundreds.

Below 20 presence cells a taxon is refused rather than modelled, and the
threshold bites on record counts that look generous: *Lysurus mokusin* has 105
records from 4 distinct cells — one urban population, collected over and over.

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
