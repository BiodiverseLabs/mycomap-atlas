# Plan: the standard null test on the atlas's real models (paper E1c)

- **Status.** Planned 2026-10-13, before any code or run. Descriptive, with
  no hypothesis test; the estimate and its interval are fixed here.
- **Question.** Of the frozen release's maps that the standard test calls
  good, what share are not shown to beat collecting? Serves paper claim C1:
  "[X]% of maps a standard test calls good are not shown to beat
  collecting".
- **Reproducibility.** frozen.

## Design

- **Models.** Every model of the frozen release has a shift-null result
  (99 nulls, stop at 5). Draw a sample stratified by learner (Maxent, RF,
  boosted trees, ESM) × site band (3–4, 5–19, 20–49, 50–99, 100+) × grade
  (strong, weak, failed): up to 50 models per cell, all of them where a cell
  has fewer. Seed fixed and recorded.
- **Standard test.** The old production design: 19 scattered nulls, the
  model's untuned settings, the same folds; pass = AUC p ≤ 0.05 and Boyce > 0.
- **Estimate.** Among models that pass the standard test, the share not
  graded strong, weighted back to the release's composition by stratum,
  with a 95% interval from 10,000 bootstrap resamples within strata. Also
  reported by learner and site band, and the reverse share (strong models
  that fail the standard test).

## Cost

About 1,000 models × 19 nulls; est. 100–200 CPU-h. Needs a small study
command in the rebuild lane that rescans a release's models with a chosen
null design.

## Deviations

None yet.
