# Plan: "default practice" Maxent (paper E6a)

- **Status.** Planned 2026-10-13, before code or run. Descriptive; serves C1
  and C2: what a common default workflow reports about itself, against how
  it does on later finds.
- **Reproducibility.** frozen (the hindcast pull, E2).

## Design

- **Data.** The hindcast pull (records first validated on or before
  2026-08-17), every taxon with ≥ 20 sites, so its maps can be scored on the
  E2 test places.
- **Model.** maxnet with its defaults: `default.features` (feature classes
  chosen by sample size, as most users run it), regularisation multiplier 1,
  every production predictor, no pruning, no effort term; 10,000 background
  points drawn uniformly over the taxon's accessible area (not the
  target-group sites).
- **Its own evaluation.** Random 5-fold cross-validation AUC; a null test as
  commonly run (Raes & ter Steege 2007): 19 null species of as many points as
  detections, drawn uniformly over the accessible area; pass = observed AUC
  above the nulls at p ≤ 0.05.
- **Scored on E2.** Its rasters, ranked over the accessible area, scored on
  the E2 test places with the E2 metrics.

## Outputs

Own-CV AUC and pass rate, against its E2 scores; beside the production
models' blocked AUC, grades and E2 scores for the same taxa.

## Deviations

None yet.
