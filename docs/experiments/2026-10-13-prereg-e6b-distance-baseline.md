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

## Deviations

None yet.
