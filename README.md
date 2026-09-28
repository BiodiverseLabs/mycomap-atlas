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
| 2. Environmental layers (climate, soil, terrain, forest, host), versioned | next |
| 3. Target-group background from the same validated universe | next |
| 4. Fits: `maxnet` at 20+ localities, `xgboost` on the richest | |
| 5. Evaluation: spatially blocked folds, Boyce index, ecological review | |
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
