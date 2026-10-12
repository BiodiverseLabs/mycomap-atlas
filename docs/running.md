# Running Atlas

Setting up, fitting, publishing and archiving: the commands, what each one
reads and writes, and how long they take. Server setup is in
[deploy/lightsail/README.md](../deploy/lightsail/README.md) and the AWS side in
[deploy/aws/README.md](../deploy/aws/README.md).

Back to the [README](../README.md). The method itself is in
[method.md](method.md).

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

## Data on disk

Everything lives under `data/`, which is never committed (override with
`ATLAS_DATA_DIR`):

- `raw/occurrences/<stamp>/` — every page exactly as pulled
- `occurrences/occurrences-<stamp>.tsv.gz` — the combined pull
- `occurrences/latest.json` — counts, fingerprint and the SQL used
- `occurrences/taxa-latest.json` — per-taxon records, localities, fingerprint

## Tests

```bash
Rscript -e "testthat::test_local()"
```

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

#### Finishing a release

Two products need every map at once, so no shard can make them: the "what
could grow here" index and each map's counts by state. After the job, and on
any night whose current release is not marked finished, the box launches one
more worker (`R/finish.R`). It pulls the release with its rasters, counts the
maps not yet counted, builds the index, uploads what changed and reports it in
a shard record under the job `finish-<release>`; workers may not write
releases, so the box then writes the finished release (the same files with
those added, marked `finished`) and promotes it. A worker lost without
reporting is launched again; if finishing fails, the night's fitted models
still stand and the next night tries again. `ATLAS_EC2_FINISH_HOURS` (default
3) bounds it; the first run counts every map, later ones only new ones.

```bash
./atlas finish-release --release=<id> --workers=8   # what the finishing worker runs
```

What each identity may do is enforced by AWS, not only by this code: see
[deploy/aws/README.md](../deploy/aws/README.md) for the policies, the setup and
the box's settings.

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
