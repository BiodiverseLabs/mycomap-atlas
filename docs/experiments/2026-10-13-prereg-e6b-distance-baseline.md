# Pre-registration: the distance-only baseline (paper E6b)

- **Status.** Pre-registered 2026-10-13, before code or run. Changes after
  launch go under "Deviations".
- **Question.** Do strong maps rank later finds better than a model that
  knows only how far a place is from the taxon's known sites? Serves C2; its
  result sets C2's wording, so it runs first after the hindcast (E2).
- **Reproducibility.** frozen (the hindcast pull and release, E2).

## Design

- **Taxa.** Every taxon with any model in the hindcast release, at every
  grade.
- **Kernel.** Per taxon, the sum of Gaussian kernels over its detection
  survey sites in the hindcast's training data (5 km thinned sites,
  unweighted). Bandwidth from {5, 10, 25, 50, 100, 200, 400} km, chosen on
  the taxon's production spatial folds (same blocks) by blocked AUC against
  its non-detection sites, ties to the smaller bandwidth. Training data
  only.
- **Scoring, primary (paired).** For each hindcast model, the kernel is
  re-ranked over that model's own area-of-applicability cells, and the same
  test places are scored with the E2 metrics and units (place = taxon × 5 km
  cell; rank, top half, top tenth, Boyce, beats-effort; the same kept-apart
  rules). So every model row has a kernel row on identical places and cells.
- **Scoring, secondary.** The kernel ranked over its own 500 km reach.

## Hypothesis and criteria

- **H6b.** For strong models, the top-half share minus the kernel's on the
  same places has a 95% lower bound > 0 (bootstrap over taxa, 10,000
  resamples). Also reported: mean rank difference, Boyce, by grade, by new vs
  known places, and by distance band.

## What the result does to C2's wording

- **H6b holds:** "strong maps rank new finds better than chance, than weak
  and failed maps, and than distance to known records."
- **H6b fails but E2 holds:** C2 says the grade predicts performance, and
  states plainly that strong maps do not beat distance to known records on
  these finds. The Discussion then asks where habitat adds over distance:
  new places and far finds, from the secondary splits.

## Implementation (not a design change)

Recorded 2026-10-19, before any run, by the rebuild lane (the experiments
lane that wrote the code is offline). Code: `study-distance` on Atlas main
(R/studydistance.R), run on the hindcast release
priv-20261018T171648Z-9e3ab153; its kernels are scored by `study-score
--kernels`, a second scoring run after E2's own. Two properties of the code,
which the run's own settings also record, for the write-up:

- **The kernel's own AUC is not nested.** Its bandwidth is the best of the
  seven candidates by blocked AUC on one set of folds, and the AUC reported
  beside it is that same best value, so it reads optimistic next to the
  habitat models' nested AUC. H6b does not use it: H6b scores both maps on
  the later finds.
- **Taxa with 20 to 49 sites take the full models' folds.** Their bandwidth
  is chosen on the folds of the full models (Maxent and random forest),
  also where the kernel is paired with the same taxon's small-model
  ensemble, which is fitted on its own folds.

## Deviations

- **2026-10-19, before any run: one taxon's kernel keeps a record its
  habitat model does not.** The kernels are built from the hindcast's
  training pull, which holds the 4 records whose first-validation date was
  wrong when the hindcast was planned (E2 prereg, Deviations, 2026-10-18).
  For three of their taxa the kernel and the hindcast model trained on the
  same records, so the pairs stay like for like (and *Fibroporia albicans*,
  at 1 site, has no model and so no kernel). For *Sparassis spathulata*,
  E2 scores the leave-out refit of its small-model ensemble without
  mycomap.org 586958 (priv-20261019T042158Z-09936f85), while its kernel is
  built with 586958's survey site. **Handling (Steve, 2026-10-19):** keep
  the pair in H6b and declare the asymmetry: one detection site of 15 in
  one taxon of about 6,100. 586958 itself is excluded from the scored test
  finds, as in E2.
- **2026-10-20: first launch fitted nothing; relaunched after a fix.** The
  first launch, study-20261019T182203Z-1552e567 (2026-10-19, image
  8bfc98d), failed on all 6,094 taxa before any kernel was fitted. Its
  workers had no predictor layers: a study job fetches no inputs for a
  private hindcast, and every taxon then failed on a missing argument.
  Nothing from that launch was read or used.
  - **Fix:** Atlas fix/study-distance-layers 00e7209, merged as 6dbdba8.
    The study now fetches the hindcast's layers itself (never the pull, and
    never over different local layers). A shard where more than 5% of taxa
    fail now fails as a whole.
  - **Smoke run:** study-20261020T052710Z-4abaca1f, 5 taxa: 5 scored, 0
    failed, 5 kernels.
  - **Relaunch:** study-20261020T053446Z-1552e567 (image 6dbdba8, 3 shards,
    30 workers each, r7i/r7a.8xlarge), launched 2026-10-20 05:34 UTC.
  - The design, kernels and scoring are unchanged; the implementation
    notes above still hold.
- **2026-10-20, before scoring: 35 kernels refused over a processor-family
  difference in the block size; they are rebuilt on the fitting family.**
  The relaunch scored 6,059 of 6,094 taxa, refused 0 and failed 0. It
  refused 35 as "mismatch": the kernel's check found that its rebuilt folds
  were not the hindcast model's. For each of the 35, the records, detection
  sites, design (full) and seed matched. Only the block size differed, and
  so the folds.
  - **Cause.** A full-design model's block size is the blockCV variogram
    range, rounded to 5 km. The kernel is checked against the taxon's
    maxnet model, and all 35 of those were fitted on r7a.8xlarge (AMD). All
    three E6b shards ran on r7i.8xlarge (Intel). On the other family the
    variogram fit lands on a different range for these taxa: gaps of 5 to
    240 km (*Hemimycena* sp. 'lactea-PNW04': 300 km rebuilt against 60 km
    recorded). Same-family fits are deterministic (E12 plan, gate 2).
  - **Rate.** Every one of the hindcast's 1,256 full-design taxa has a
    maxnet model: 1,144 fitted on r7a and 112 on r7i. 35 of the 1,144 (3.1%)
    measured a different block on r7i; none of the 112 did. No small-model
    taxon was refused, as their blocks are a fixed 100 km. The hindcast's
    8,606 fitted models: r7a 2,554, r7i 6,052; full-design models r7a
    1,366, r7i 1,446.
  - **Handling (Steve, 2026-10-20): rebuild, so that nothing drops out of
    H6b.** The 35 are rebuilt on r7a by the same procedure and the same
    check (`study-distance --taxa`, Atlas fix/e6b-patch-taxa), and
    study-score reads that job as a patch over the main run
    (`--kernels-from=MAIN,PATCH`). The patch may hold only taxa the main run
    did not score. A taxon that still differs on r7a stays out of the paired
    scores, and is counted here when the patch has run. Four of the 35 have
    a strong hindcast model: *Crassisporium funariophilum*, *Cystoagaricus
    subamarus*, *Lactarius griseus* and *Lactarius luculentus* var.
    *laetus*.
  - **For the write-up.** Production's own spatial folds depend on the
    processor family for some full-design taxa. A taxon's models can be
    fitted on different families within one release (its maxnet on one, its
    random forest on the other), so their folds can differ. The kernel's
    bandwidth is chosen on the maxnet model's folds, as recorded.
  - **Patch run (2026-10-20): all 35 match on r7a.**
    study-20261020T221806Z-9620406f, image a49a698 (fix/e6b-patch-taxa
    c76884d merged), one r7a.xlarge (AMD EPYC 9R14), 22:18 to 22:23 UTC.
    `--taxa` held the 35. Result: 35 scored, 0 refused, 0 mismatch, 0
    failed, 35 kernels. Every rebuilt block and set of folds matched the
    hindcast's record on the hindcast's own family, so no taxon stays out of
    H6b. The kernels are scored as
    `--kernels-from=study-20261020T053446Z-1552e567,study-20261020T221806Z-9620406f`
    (study-20261020T222337Z-05216058).

## Results

Run 2026-10-20 (`study-score`, one-shard EC2 study job
study-20261020T232528Z-05216058, Atlas image 50be1dc, r7i.xlarge, 23:27 to
00:55 UTC). Results file:
study/study-20261020T232528Z-05216058/score-priv-20261018T171648Z-9e3ab153-20261020T232715Z.json.
Numbers only; read out by the rebuild lane.

**Settings.** As E2 (hindcast priv-20261018T171648Z-9e3ab153, the
*Sparassis spathulata* refit, the same 4 excludes, 10,000 bootstrap
resamples of taxa, seed 1). Kernels from the main run
study-20261020T053446Z-1552e567 (6,059) and the r7a patch
study-20261020T221806Z-9620406f (35), all 35 patched kernels used. E2's own
numbers in this run equal E2's (H2a 0.9145, H2b 0.1305, H2c 0.7854; C2
supported; H2d, H2e, H2f and moderate-z hold).

**Taxa with a kernel and later finds:** 2,567.

**Primary hypothesis** (strong model minus kernel, on the same places;
95% percentile intervals, bootstrap over taxa):

| | Estimate | 95% interval | Taxa | Places | Holds |
|---|---|---|---|---|---|
| H6b: top-half share | +0.0435 | [0.0147, 0.0755] | 202 | 486 | yes |
| H6b: mean rank difference (reported) | +0.0042 | [−0.0166, 0.0267] | 202 | 486 | |
| H6b, new places only: top-half share | +0.0478 | [0.0000, 0.0996] | 168 | 334 | no (lower bound 0) |
| H6b, new places: mean rank difference | +0.0079 | [−0.0207, 0.0378] | 168 | 334 | |

**Tiers against the kernel** (tier model minus kernel, the same places;
reported):

| Tier | Top-half difference | 95% interval | Mean rank difference | 95% interval | Taxa | Places |
|---|---|---|---|---|---|---|
| moderate | −0.0142 | [−0.0334, 0.0050] | −0.0168 | [−0.0299, −0.0037] | 628 | 1,519 |
| indicative | −0.0263 | [−0.0393, −0.0140] | −0.0297 | [−0.0378, −0.0217] | 1,571 | 4,335 |

**Strong models and their kernels, top-half share, same taxa**
(736 rows, 214 taxa):

| Places | Strong models | Kernel |
|---|---|---|
| all | 0.914 | 0.871 |
| new (> 5 km) | 0.878 | 0.830 |
| known | 0.987 | 0.952 |
| band 5–25 km | 0.974 | 1.000 |
| band 25–100 km | 0.928 | 0.928 |
| band 100–500 km | 0.760 | 0.611 |

The near bands in full (strong models against their kernels on the same
places; the two sides have the same counts):

| Band | Ranked | Places | Top half | Top tenth | Mean rank | Beats effort | Boyce |
|---|---|---|---|---|---|---|---|
| 5–25 km, model | 113 | 80 | 0.9735 | 0.6283 | 0.8777 | 0.7958 | 0.870 |
| 5–25 km, kernel | 113 | 80 | 1.0000 | 0.6991 | 0.9161 | 0.7708 | 0.933 |
| 25–100 km, model | 180 | 127 | 0.9278 | 0.4444 | 0.8161 | 0.7722 | 0.962 |
| 25–100 km, kernel | 180 | 127 | 0.9278 | 0.5611 | 0.8408 | 0.6780 | 0.876 |

No strong-model place lies beyond 500 km.

*Sparassis spathulata*'s kernel kept 586958's site (Deviations,
2026-10-19). It has 1 later-find place (new, 100–500 km) of the 486 in
H6b.

**Secondary: the kernel over its own 500 km reach**, all taxa: 6,206 rows,
462 beyond reach; top-half share 0.882 (new places 0.853, known 0.971,
100–500 km 0.707).

## Notes for the write-up (rebuild lane, 2026-10-20)

Not results: a reading of the numbers above for the Discussion, descriptive
only (the bands carry no intervals).

- **Near known records, distance alone does as well as or better than a
  strong habitat map, and the strong maps' advantage comes from far
  finds.**

  | Band | Strong map | Kernel |
  |---|---|---|
  | 5–25 km | 0.974 | 1.000 |
  | 25–100 km | 0.928 | 0.928 |
  | 100–500 km | 0.760 | 0.611 |

  This is the "habitat adds over distance at far finds" question the
  Design anticipated (What the result does to C2's wording).
- **New places.** The new-places split (more than 5 km) gains about as much
  as the whole (+0.0478 against +0.0435), but on fewer places, and its
  interval reaches 0. It reads as too little power, not as no effect. The
  new places that carry the gain are the far ones.
- **Wording.** H6b measures later finds at all places, so C2 should say
  "later finds", not "new finds". The advantage is in the top-half share;
  the mean rank of finds does not differ.
- **Tiers.** Moderate and indicative maps do not beat the kernel, and
  indicative ranks below it. They now carry no downstream claims
  (plan-map-tiers, Deviations, 2026-10-20).
