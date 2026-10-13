# Plan: "default practice" Maxent (paper E6a)

- **Status.** Planned 2026-10-13, before code or run. Descriptive; serves C1
  and C2: what a common default workflow reports about itself, against how
  it does on later finds.
- **Reproducibility.** frozen (the hindcast pull, E2).

## Design

- **Data.** The hindcast pull (records first validated on or before
  2026-08-17), every taxon with ≥ 20 sites, so its maps can be scored on the
  E2 test places.
- **Model.** The package's own `maxnet::maxnet` with its defaults:
  `default.features` (feature classes chosen by sample size, as most users
  run it), regularisation multiplier 1, its full lambda path (not Atlas's
  20-step path),
  every production predictor, no pruning, no effort term; 10,000 background
  points: random grid cells with complete predictors inside the taxon's
  500 km accessible area (not the target-group sites). Predictors constant
  over a fit's points (detections and background, in each CV fold, the final
  fit and each null) are left out, because maxnet cannot fit them; the count
  is reported. Nothing that varies is pruned. (Added 2026-10-13, before any
  run, on the experiments lane's finding.)
- **Its own evaluation.** Random 5-fold cross-validation AUC, reported as
  the model's own score; and the null test as Raes & ter Steege (2007) run
  it: the model's TRAINING AUC (fit on all points against the background)
  against the training AUC of 19 null species of as many points as
  detections, drawn uniformly over the accessible area, all against the same
  10,000 background points; pass = p ≤ 0.05. (Settled 2026-10-13 with the
  experiments lane, before code.)
- **Scored on E2.** Its rasters, ranked over the accessible-area cells (E6a
  has no area of applicability), scored on the E2 test places with the E2
  metrics.

## Outputs

Own-CV AUC and pass rate, against its E2 scores; beside the production
models' blocked AUC, grades and E2 scores for the same taxa.

## Deviations

None yet.
