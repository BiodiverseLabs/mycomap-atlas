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
- **Standard test.** The old production design (`atlas_null_test`): 19
  scattered nulls, no early stop, the model's untuned settings, the same
  folds; pass = AUC p ≤ 0.05 and the release's pooled Boyce (from the
  model's tuned cross-validation, as production's skill rule used) > 0. Each
  model's training table and folds are rebuilt from the frozen pull, with the
  block size taken from the release record (not re-run through the
  variogram). A rebuild counts as matching only if all of these agree with
  the release record: fingerprint; detection-site count; predictor set;
  seed; detection sites in every fold; and the untuned AUC at the recorded
  three decimals, |round(ours, 3) − recorded| ≤ 0.001 (one rounding step,
  for a cross-processor last-bit difference). The release stores that AUC
  rounded to three decimals, so the 1e-9 comparison first planned is not
  possible (amended 2026-10-13 before code was pushed, on the experiments
  lane's finding). A model failing any check is dropped and counted; if more
  than 2% are dropped, stop and report before going on.
- **Estimate.** Among models that pass the standard test, the share not
  graded strong, weighted back to the release's composition by stratum,
  with a 95% interval from 10,000 bootstrap resamples within strata. Also
  reported by learner and site band, and the reverse share (strong models
  that fail the standard test).

## Cost

About 1,000 models × 19 nulls; est. 100–200 CPU-h. Needs a small study
command in the rebuild lane that rescans a release's models with a chosen
null design.

## Runs

Logged as the operations lane reports them; numbers only.

- **Rescan (launched 2026-10-25 15:52 UTC).**
  study-20261025T155216Z-725a1d1e, image c56d2dc, `plan-study
  --command=study-rescan --shards=2 --args="--release=20261013T191324Z-fa1b4198
  --seed=1 --workers=30"`, 2 × r7i.8xlarge (spot). The sample is 1,083 of
  the release's 9,040 testable models (esm 426, maxnet 278, rf 264, xgboost
  115), up to 50 per cell, so fewer than the plan's estimate of about
  1,000–3,000; about 30 CPU-h by the code's estimate. Steve confirmed it
  directly with the operations lane. Pooled with `study-rescan
  --pool-from` once both shards report.

## Deviations

- **2026-10-25, before launch (implementation only; the estimate, its
  interval and the 2% stop are unchanged): each model is rebuilt from the
  pull it was fitted on, not from the frozen release's pull.**
  - **Why.** The frozen release fa1b4198 names the pull
    occurrences-20261012T051017Z-x73b85b36. Most of its models were fitted
    on the 2026-10-12 pull before the 76 drop-list rows were removed. A
    taxon's background is drawn from other taxa's records, so a training
    table rebuilt from the release's pull differs, and its folds with it,
    wherever one of those rows lay within reach. The E3 kernels met exactly
    this (E3 prereg, Deviations, 2026-10-21).
  - **What the code does.** `study-rescan` (Atlas main c56d2dc) already
    traces each model's fitting job through the release chain
    (`atlas_refresh_sources`) and rebuilds from that job's pull. It uses
    the block size the release recorded, so the variogram, which can differ
    between processor families, is never run again. Every match check
    stands as planned.
  - **Run.** On one processor family, Intel (r7i). E12 found no model with
    the same block that differs across families (0 of 277).
