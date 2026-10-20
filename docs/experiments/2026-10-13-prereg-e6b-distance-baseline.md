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
