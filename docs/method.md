# How Atlas builds a map

The method in full: which records count, the grid, how a taxon's training table
is made, how models are fitted, scored and compared, and how the published
products are derived. The [Methods page](https://atlas.mycomap.org/methods) on
the site says the same for readers of the maps; this file is the developer's
version, with the commands and the measurements behind each choice.

Back to the [README](../README.md). Running the pipeline is in
[running.md](running.md).

## The records

### Eligibility

A record is eligible when it is **green in at least one validation project** (a
red in another project does not rule it out), has coordinates that are present,
unobscured, and accurate to within 1 km where an accuracy was recorded, sits in
North America, and carries a species-level name (provisional temp codes
included).

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

The decay-host layer (`hostsdecay`) adds 10 more genera the same way: the
trees wood-decay and parasitic fungi live on (maple, ash, elm, juniper,
cedar, tulip tree, cherry, sweetgum, sycamore, black locust), as shares of the
same tree totals, read from the host layer's cached sums rather than summed
again. It reads only those genera's 52 BIGMAP species (about 50 minutes) and
17 NFI files, into its own cache files. NFI does not map tulip tree,
sweetgum, sycamore or black locust, so they are 0 in Canada. It is filled
where the inventories are silent exactly as the host layer is, and leaves the
saying of it to `host_known`. Its bands follow the host genera in Maxent's
order and count toward the same allowance.

```bash
./atlas build-layers --only=hosts --grid=draft
./atlas build-layers --only=hostsdecay --grid=draft   # after hosts
```

### The production layers, and the candidates

Production fits on eight layers (`ATLAS_PRODUCTION_LAYERS`, R/layersweep.R):
climate, elevation, terrain, soil, land cover, host trees, decay and parasite
hosts, and forest type
(`foresttype`, NALCMS 2020, with Hawaii and the Caribbean filled from
Copernicus Global Land Cover). Any other layer is a candidate: built only into
a separate data directory and measured by `./atlas sweep-layers` before it is
fitted on (R/layersweep.R). The sweep scores every arm on the same sites and
folds, under the design production uses, and reports how many records each
layer cannot describe and what each predictor and layer was worth on held-out
ground.

Measured on 152 taxa (2026-09-30): host trees earned their place (+0.008 +/-
0.004 blocked AUC when added, and the second most important layer after
climate, most of all for ectomycorrhizal fungi); forest type was kept; water
balance and fruiting-season climate (`waterbalance`, ClimateNA 1991-2020 and
TerraClimate) is held as a candidate; carbonate bedrock, landform (wetness,
northness, heat load) and a second host-tree layer from USFS basal area added
nothing and were dropped. Round 2 on 158 taxa (2026-09-30): the decay and
parasite hosts came out +0.0018 +/- 0.0013 AUC (+0.004 for taxa with 30-49
sites, maple doing most of the work) and joined production on that and on
ecology; cropland, bare ground and moss/lichen from WorldCover made Maxent
slightly worse (-0.0019 +/- 0.0009) and were dropped.

## Training data

A taxon's training table has one row per **survey site** inside its accessible
area: detected (the taxon was collected there) or not (other DNA-validated
fungi were collected there, but not it), with the site's predictors and its
**effort**, log(records at the site, the taxon's own counted once). The comparison is the
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
Ramp 2013; Fithian et al. 2015). A taxon's own records count once towards
its sites' effort, however many there are, or a fungus collected a hundred
times in one wood would make that wood look well surveyed by being there.
The trees use effort; Maxent does not. Measured twice on 150-odd taxa,
Maxent scored better without it (+0.017 and +0.020 blocked AUC, Boyce
unchanged), while the forest's Boyce fell 0.084 without it. Effort still
decides where the null models draw their sites, for Maxent too. The spacing is in km, not cells, so the 1 km
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
  failed maps are drawn faint (25%, against 80% for a passing map; a slider
  under each map lets the viewer change either), hidden from the Maps list by default and left
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
a fifth of any other's, the decay and parasite hosts included (they come after
the host genera). The twenty host bands are barely correlated, so without
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
for a widespread taxon at the thousand trees the benchmark used), since every
tree has to be asked about every cell. Forests are now 250 trees: on 24 taxa
that ranked cells within 0.994 of a thousand trees, every cell within one
decile, at about a sixth of the time.

### Colours are ranks

The models put their scores on different scales — on *Pluteus petasatus*,
Maxent spans 0.03–1.00 across its map, boosted trees 0.27–0.63 — so each map
is drawn by percentile: the darkest green is the ground that model rates
highest. Ranks are taken on the equal-area grid, before the map is warped to
Mercator, and only over ground inside the map's area of applicability (below);
ground outside it is hatched grey. Stored rasters keep the raw values.
`./atlas redraw-maps --workers=12` redraws every map without refitting.

How strongly a map is drawn follows its skill. `map_strength` is 0 for a map
that failed its null test, and for one that passed runs from 0.4 (just past
p = 0.05) to 1 (blocked AUC five null standard deviations above its nulls).
The site starts each map's opacity between 25% and 80% in proportion; the
viewer can still move it.

### Where a map applies

Parts of a 500 km circle hold conditions no survey site has. Maxent clamps
and trees hold their edge values there, so without a mask the map would show
a confident colour resting on no data. Every fit computes the dissimilarity
index of Meyer & Pebesma (2021) over its map (R/aoa.R). Predictors are
standardised by the training sites and weighted by the model's own
permutation importance on held-out ground. The index is the distance to the
nearest training site, divided by the mean distance between training sites.
The threshold is the upper whisker of the training sites' own index against
the other folds, as CAST sets it. The index is written beside the map as
`<taxon>.di.tif`, and the metrics keep the threshold and the share of the
accessible area inside it.

The search is exact. On a loaded PC with all 69 predictors weighted equally
(the worst case), a widespread taxon's 377,000–456,000 cells took 10–13
minutes. Real fits weight about a dozen predictors, and the cost scales with
them.

### The ensemble

`./atlas build-ensembles` averages each taxon's passing models into one map
(R/ensemble.R). Each member is ranked over the ground inside its own area of
applicability, and the ranks are averaged, weighted by blocked AUC above 0.5.
A cell takes its rank only from members that know it. Beside the average is
a disagreement layer: the weighted standard deviation of the members' ranks,
0 where they agree and 0.5 where two put a place at opposite ends. A taxon
needs two passing models for an ensemble. Each member's raster md5 is kept,
and an ensemble is rebuilt only when a member changes. Ensembles ship in
releases under `models/<grid>/ensemble/`.

The Models page in the app shows the latest benchmark and, for the maps in
production, how many taxa each model has mapped and their median scores.

## Taxa with few sites: ensembles of small models

A taxon with 3 to 19 detection sites is too sparse for the three models and
gets one map from an ensemble of small models instead (`esm`, R/esm.R;
Breiner et al. 2015). Every pair of its first ten predictors, chosen in
Maxent's ecological order with the same host-tree allowance, gets a ridge
logistic regression on the two variables, their squares and effort, with
detections and non-detections weighing the same. Each is scored on blocks
held out inside the training sites, and the map averages them weighted by
Somers' D there; a small model no better than chance has no say.

These taxa are scored on three folds of 100 km blocks, not five of up to 300
km: at 300 km only 38% of taxa with 5-7 sites, and none with 3-4, have
detections in five blocks; at 100 km, 98% and 80% have them in three.

```bash
./atlas fit --taxon="Rhodotus reticeps" --algorithm=esm
./atlas study-sparse --per-band=40 --workers=16            # how few sites carry a map
```

`study-sparse` thins well-recorded taxa (40+ sites) to 5, 8, 12 and 16
detection sites, fits the ensemble, Maxent and the forest on what is left,
and scores each on every held-out detection. Measured on 118 taxa
(2026-09-30):

| Sites | Ensemble AUC / Boyce | Maxent | Random forest |
|---|---|---|---|
| 3 | 0.592 / 0.495 | 0.570 / 0.305 | 0.500 / — |
| 4 | 0.608 / 0.564 | 0.578 / 0.402 | 0.500 / — |
| 5 | 0.603 / 0.598 | 0.580 / 0.394 | 0.500 / — |
| 8 | 0.623 / 0.677 | 0.598 / 0.492 | 0.617 / 0.480 |
| 12 | 0.630 / 0.681 | 0.605 / 0.552 | 0.641 / 0.590 |
| 16 | 0.635 / 0.654 | 0.607 / 0.522 | 0.652 / 0.604 |
| all | 0.657 / 0.717 | 0.652 / 0.677 | 0.692 / 0.776 |

At 3 sites 40% of the thinned taxa still showed clear skill (AUC above 0.6
and a positive Boyce index) and 8% were no better than chance; at 4, 58% and
9%. Every ensemble map from 3 sites up is drawn, faint when it fails its null
test (Steve, 2026-10-04).

A sparse taxon's own null test has little power: the null models' AUC spreads
by 0.25 at 3-4 sites, 0.18 at 5-7 and 0.10 at 16-19, so even a sound map
rarely beats all nineteen. In the first full build 4% of 1,801 ensembles from
3-4 sites passed (fewer than chance alone lets through) and 40% from 16-19.
Until 2026-10-04 a map from 3 or 4 sites was drawn only when it passed
(`map_withheld`); those are fitted again and drawn. The site labels a failed
ensemble "too few sites to tell" (`web/src/lib/sparseSkill.ts`), a hint about
where to look rather than a finding. It used to add how often maps of its size
had clear skill in the study above; that rate came from common, widespread
fungi thinned at random, and a taxon with a handful of sites is usually rare or
regional, so it is no longer offered as reassurance (2026-10-06). An algorithm can
still hold maps back below a site count (`map_needs_skill_below`); none does.

## Virtual species: testing the method where the answer is known

Blocked AUC and Boyce score a map against held-out detections, and those
carry the same sampling bias as the training detections. A model that learns
where people collect can score well on them. So the method is also tested on
virtual species (R/virtual.R), whose habitat is written down first.

A habitat species answers to two or three real predictors: one climate
variable plus soil, cover or host trees, with optima drawn from where people
actually collect. It is then collected the way MycoMap's records were. At
every real survey site, each of the site's real records is the species with a
chance proportional to the habitat there, so a site worked a hundred times
has a hundred chances. The records drawn are relabelled, and the species goes
through the same training table, blocks and folds as a real taxon. A
geography species ignores the environment and follows only distance from one
or two centres. Any map of one shows nothing but clustering, so if it passes
the null test, that pass is false.

Every species is fitted under several arms on the same table and folds:

- Maxent's four ways of handling effort (`effort_mode` in R/fit.R): none
  (production), effort as a predictor, background weighted by records, and
  log effort as an offset.
- A detection model (R/detection.R): a binomial on survey sites, with
  complementary log-log link and log effort as an offset (Fithian et
  al. 2015).
- The forest as production fits it.

Each arm is scored as production scores it, and against the truth: the
Spearman correlation of its map with the true habitat over cells of the
accessible area. With `--nulls`, production Maxent also runs its null test,
which gives the false-pass rate on geography species and the power on
habitat species.

```bash
./atlas study-virtual --species=100 --kinds=habitat,geography --nulls=19 --workers=16
```

Background weights and the offset are the same model in maxnet's
formulation. They give identical maps, which checks the wiring of both.

### Null models that keep clustering

A lineage named for one region sits in that region, and within a 500 km
circle almost any smooth predictor tells a cluster from the rest. The
production nulls draw detection sites one by one ("scatter"), so a clustered
taxon can beat them on clustering alone. R/nulls.R adds two designs that keep
the pattern's shape:

- **shift**: the real detections are rotated by one random angle, moved to a
  random survey site and snapped to free sites.
- **shift-effort**: the same, but each point snaps among nearby sites in
  proportion to their records.

The sequential test (Besag & Clifford 1991) draws up to 99 nulls and stops
once a set number have done as well as the map. That gives the same verdict
at 0.05 as drawing them all. `atlas_null_qvalues` gives Benjamini-Hochberg
q-values across taxa. The virtual-species study compares the designs:

```bash
./atlas study-virtual --species=100 --kinds=habitat,geography --nulls=99 \
  --null-designs=scatter,shift,shift-effort --stop-after=5 --arms=maxnet:none --workers=16
```

### Block size

`./atlas study-blocks` asks kNNDM's question (Milà et al. 2022; Linnenbrink
et al. 2024): which block size makes the distances cross-validation tests at
match the distances a map predicts at? For each candidate size, it compares
each held-out site's distance to the nearest training site with each mapped
cell's distance to the nearest survey site, as a Wasserstein distance in km.
It is measured over every cell of the accessible area, over cells near a
survey site, and against distances to detections.

On 153 taxa (2026-10-05), 100–200 km fit every cell best. The 300 km ceiling
tests harder ground than the map's: held-out sites sit a median 79 km from
training sites, mapped cells 35 km from a site. Measured to detections, even
400 km falls short, because mapped cells sit about 150 km from the nearest
detection. blockCV gave 8 taxa blocks of 50–85 km. Every size up to 400 km
leaves about 99% of taxa scorable.

## What could grow here

The Explore page (`/here`, route `/api/here`) answers a click on the map with
every mapped fungus whose maps rate that place highly. Asking 2,700 rasters
about a point takes a minute, so it answers from an index built once from the
maps (`R/here.R`). Every release a job makes is finished on EC2, which builds
it (see [Finishing a release](running.md#finishing-a-release)); by hand, on a machine with the rasters:

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

## Where a species is likely, by state

A taxon page lists the states and provinces where it has DNA-validated
records and where its maps say it is likely though nobody has sequenced it
there yet; `/api/checklist.csv` gives the same per state, for spreadsheets
(`R/predictions.R`, `R/regions.R`).

Each map is counted by state when it is drawn, on the 5 km grid: the cells it
reaches (500 km from a record) and the cells it rates at least as highly as
the poorer tenth of the places the species was found, the 10th-percentile
training presence threshold. Over a species' maps that beat their null
models, a state is likely when that covers a tenth of it on average (the maps
agree), possible when it does on one map only (they disagree), beyond reach
when less than a tenth of it is reached, and unlikely otherwise. Counting one
map's tenth as likely was weighed and kept apart instead: on 40 species it
added 12% more likely states, nearly all resting on a single map. A fixed cut such
as "top quarter" was tried first and dropped: it called Trametes versicolor
unlikely in half the states it has been collected in. State outlines come from
Natural Earth, simplified into `inst/boundaries` by `tools/build-boundaries.R`.

Maps fitted before this are counted when their release is finished
([Finishing a release](running.md#finishing-a-release)),
or by hand on a machine with the rasters:

```bash
./atlas count-regions --workers=8 --only-missing
```

`/api/taxa/<name>/image.png` draws a taxon's map as one picture, over
Natural Earth land and borders, for Excel's `=IMAGE()`, documents and slides.
