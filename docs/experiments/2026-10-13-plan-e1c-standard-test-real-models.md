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
  115), up to 50 per cell, close to the plan's estimate of about 1,000;
  about 30 CPU-h by the code's estimate, below the plan's 100–200. Steve confirmed it
  directly with the operations lane. Pooled with `study-rescan
  --pool-from` once both shards report.
  - **It left no result.** Both shards stopped within about 6 minutes:
    "no layers built for the draft grid". study-rescan fetches each model's
    pull, but not the layers; the job was planned without
    `--from-release`, so no layers were fetched. About 0.2 instance-h
    (spot), at most USD 0.45. Nothing from it is used. The rerun is planned
    with `--from-release=20261013T191324Z-fa1b4198`, after a check that
    every fitting job behind the release lists the same layers.
  - **Rerun (launched 2026-10-25 16:05 UTC):**
    study-20261025T160517Z-0c069800, the same image and arguments, planned
    with `--from-release=20261013T191324Z-fa1b4198`, on 2 × r7i.8xlarge
    (spot). The check passed first. The 9 layers/ entries (path and sha256)
    of fa1b4198's job are identical in R_main 20261013T022520Z-2cb67f32, in
    the full-view refresh full-20261013T140649Z-5cf5b864 (and each of its
    shard inputs), and in the targeted job 20261013T062143Z-2ffed182. So
    every model in the sample was fitted on these layers. Steve confirmed
    it directly with the operations lane.
  - **Result (2026-10-25).** Both shards on r7i.8xlarge (Intel Xeon
    Platinum 8488C), spot.
    - The first workers were reclaimed at about 16:14 UTC, before
      reporting.
    - The second attempt ran shard 1 from 16:16:34 to 16:36:02 UTC and
      shard 2 from 16:16:32 to 16:35:16 UTC.
    - `study-rescan --pool-from=study/study-20261025T160517Z-0c069800/`:
      1,083 of 1,083 sampled models over 2 shards, 0 without a verdict, 0
      rebuild mismatches; readable.
    - Unweighted counts, as a check (the estimate is weighted by stratum):

      | Learner | Models | Passed the standard test | Of those, not strong | Strong but failed it |
      |---|---|---|---|---|
      | esm | 426 | 159 | 51 | 26 |
      | maxnet | 278 | 155 | 90 | 1 |
      | rf | 264 | 165 | 105 | 1 |
      | xgboost | 115 | 83 | 78 | 0 |

    - The weighted share and its interval are read from the two results
      files and the strata (the Paper Coordinator's reading):
      `study/study-20261025T160517Z-0c069800/rescan-20261013T191324Z-fa1b4198-shard-{1,2}of2-20261025T16172{9,8}Z.json`.
    - Cost: about 1 instance-h of r7i.8xlarge spot, including the
      reclaimed attempt, at most USD 2.1. The run without layers adds at
      most USD 0.45.

## Result (2026-11-04, the Paper Coordinator's reading)

From the two results files of study-20261025T160517Z-0c069800 (sha256
438a8f66… and a4bcfbda…, copied by the operations lane with Steve's
confirmation), with `2026-11-04-e1c-reading.py` beside this plan (sha256
45ab2261…; standard library, no local paths). Numbers only. The estimate
and its interval are the ones fixed in Design above; the reading was made
late (the run finished 2026-10-25) but nothing in it was chosen after
seeing the numbers.

- **Checks.** 1,083 models over 29 strata; 0 dropped; the rows match the
  files' sampled counts; the release holds 9,040 testable models in those
  strata; every "passed" equals the plan's rule (AUC p ≤ 0.05 and pooled
  Boyce > 0), 0 disagree. 11 strata are censuses (every model sampled); they
  are resampled like the rest, as the plan says, which makes the interval
  slightly wider than a finite-population one.
- **The estimate.** Among models that pass the standard test, the share not
  graded strong, weighted by stratum: **84.2% [82.2, 85.9]**.
- **How many pass.** The standard test passes 35.7% [31.9, 39.8] of the
  release's models (weighted). Strong models are 576 of 9,040 (6.4%).

| Split | Passed, not strong | 95% interval | Strong that fail the standard test | 95% interval |
|---|---|---|---|---|
| All | 84.2% | 82.2–85.9 | 11.2% | 6.7–16.2 |
| ESM | 81.0% | 76.2–84.5 | 16.9% | 9.8–24.8 |
| Maxent | 81.5% | 77.7–84.2 | 1.7% | 0.0–5.2 |
| Random forest | 88.6% | 86.4–90.2 | 1.2% | 0.0–3.5 |
| Boosted trees | 98.0% | 97.8–98.2 | 0% | 0–0 |
| 3–4 sites | 75.6% | 0.0–88.5 | 50.0% | 32.4–67.7 |
| 5–19 sites | 75.2% | 62.1–82.4 | 18.0% | 8.0–30.0 |
| 20–49 sites | 83.8% | 81.6–85.5 | 0.8% | 0.0–2.4 |
| 50–99 sites | 95.0% | 94.5–95.5 | 3.1% | 0.0–9.4 |
| 100+ sites | 100% | 100–100 | no strong models | |

- The 3–4-site interval is very wide because few models there pass; some
  resamples have none.
- "Not strong" means not shown to beat collecting by the shifted null, which
  E1 found has low power. It does not mean the map is wrong.

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
