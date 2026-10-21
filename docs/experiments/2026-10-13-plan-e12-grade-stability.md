# Plan: reproducibility and grade stability across reruns and machines (paper E12)

- **Status.** Planned 2026-10-13, before code or run; revised the same day
  after the rebuild lane's review (gates, arms, cost basis, measures,
  boosted-tree threads).
- **Question.** When the same model is refitted from the same inputs, in
  another worker process, on the same processor family and on another, do
  its map, its held-out scores and its grade come out the same? Serves C4
  ("says which maps to trust") and qualifies C1–C2: a grade that changes
  between runs or machines is a weaker trust measure.
- **Why.** Refitting the frozen release's 576 strong models for the
  full-view refresh (release 20261013T155140Z-026d3a26) kept 573 maps within
  float32 tolerance. Three tuned Maxent models chose other settings: one a
  near-tie (*Russula* sp. 'compacta-PA01', picks 0.003 apart), and two where
  the cross-validated AUC of every candidate moved (*Stropharia hardii*:
  mean change −0.032, correlation of candidate scores 0.49; *Gliophorus
  fumosus*: median change 0.035, correlation 0.55), with the same pull,
  presences and background, and random forests byte-identical. The
  mechanism is not identified; the rebuild lane's working order of
  suspicion is process state or run-to-run effects in Maxent's CV fits,
  then BLAS-path effects, then the machine alone. The refresh check compares
  maps, not held-out scores, so a model can keep its map within tolerance
  while its AUC and Boyce shift.
- **Reproducibility.** frozen: release 20261013T191324Z-fa1b4198
  (its model index equals 026d3a26's and 79fe85f3's; recorded fit times
  come from R_main's fitting job, which every later release names as its
  base).

## Gates (cheap steps first)

1. **Step 0, read-only (rebuild lane's script, run by ops).** For all 576
   refreshed models: chosen setting, per-candidate tuning AUCs, mean blocked
   AUC, pooled Boyce and per-fold AUC, release vs refit, by learner. Also
   the cost basis below.
2. **Same-machine test of the two taxa** (*Stropharia hardii*, *Gliophorus
   fumosus*): first on a local PC with a development pull: **passed
   2026-10-13**, six fresh processes bit-identical
   (`2026-10-13-e12-local-two-taxon-gate.md`); then `study-repro` with
   the release image on the frozen inputs, one EC2 worker per family (r7i,
   r7a), 3 taxa × 2 fresh runs, compared with each other and with the
   release (awaiting Steve's go).
   - **Different answers on the same machine:** a non-determinism bug. Stop
     the paper's run queue (the coordinator's rule), find and fix it, and
     then run E12 to confirm the fix.
   - **Identical:** run E12 as designed.

   **Result (2026-10-19): passed; the difference is the processor family.**
   Both jobs ran release fa1b4198 on source job 20261013T022520Z-2cb67f32
   (the original 10/12 pull), image 8bfc98d, 3 tuned Maxent models × 2
   fresh-process runs, no nulls:

   | Job | Machine | Runs agree | Same as the release |
   |---|---|---|---|
   | study-20261019T180106Z-5b4bbf44 | r7i.large, Intel Xeon Platinum 8488C, libblas.so.3 | 3/3 | *Stropharia hardii*, *Russula* sp. 'compacta-PA01' |
   | study-20261019T181116Z-179c6d90 | r7a.large, AMD EPYC 9R14, libblas.so.3 | 3/3 | *Gliophorus fumosus* |

   - **Within one family every refit is bit-identical across fresh
     processes**, for all three models on both families. So there is no
     run-to-run or process-state non-determinism, and the queue does not
     stop.
   - **Across families, tuned Maxent's choice can flip.** Each model's
     release fit is reproduced on exactly one family, and the other family
     gives another setting. *Gliophorus fumosus* on Intel: maximum tuning
     change 0.0693, correlation 0.546. *Stropharia hardii* on AMD: 0.0472,
     0.492. *Russula* on AMD: 0.0129, 0.973.
   - **These are the refresh's three flips, number for number.** The
     refresh's maximum tuning changes were 0.069 (*Gliophorus*, Intel) and
     0.047 and 0.013 (*Stropharia*, *Russula*, AMD). So the release fitted
     *Gliophorus* on AMD and the other two on Intel. The refresh refitted
     *Gliophorus* on Intel and the other two on an AMD attempt of its
     shard 4, before that shard's reclaim moved it to Intel.
   - **Results:** study/<job>/repro-<label>-20261013T191324Z-fa1b4198.json
     for each job.
   - **Reading for the paper:** the reproducibility claim holds per
     processor family. Across families, a small share of tuned Maxent
     models choose other settings; arm b measures that share. E12 runs as
     designed.

## Design

- **Sample (fixed 2026-10-13, before any cost or result was seen).** Strata
  = learner (Maxent, RF, boosted trees, ESM) × site band (3–4, 5–19, 20–49,
  50+) × grade (strong, weak, failed) in the frozen release, empty cells
  skipped; models graded "untested" (no null test, so no grade to compare)
  are left out and counted. Bands use each model's detection sites in the
  release index. Within each cell, sort taxa by name, then
  `set.seed(1)` afresh for that cell (Mersenne-Twister, Rejection sampling)
  and order by `sample.int(n)`; take the first 25 (all, if fewer). A cell's
  draw never depends on the others. Implemented as `study-e12-draw`
  (branch study/refit-repro 72166b0), which also writes each drawn model's
  recorded fit seconds (from the job that fitted it; a missing time takes
  its cell's median and is flagged). Cost rule, applied once from step 0's recorded
  seconds: if the 50+ site Maxent cells together exceed half the estimated
  cost, keep only the first 10 of each of those cells in the same seeded
  order. Analyses weight each cell back to its share of the release.
- **Arms**, each a full graded refit from the frozen pull with the frozen
  settings and seeds, nulls included (null draws are seeded, so they are a
  fair test, and grade agreement needs the null p):
  - (a1) on r7i (Intel);
  - (a2) on r7i again, with a *different shard split and model order*, so
    each fit sits at a different position in its worker process (tests
    state carried between fits);
  - (b) on r7a (AMD);
  - (c) free fourth observation: the frozen release's own metrics, from
    machines of unknown family (R_main's shards ran r7i and r7a after spot
    reclaims, and its records do not say which fitted which model), for the
    576 strong models.
  - Every model's result records the machine that fitted it
    (feat/result-machine). xgboost's thread count is pinned in every arm and
    recorded (multithreaded tree building is a known source of run-to-run
    differences).
- **Measures.** Grade agreement (strong/weak/failed) with Cohen's κ and the
  share of flips by type; chosen-setting agreement; the per-candidate
  tuning-score vector and its correlation between runs; per-fold AUC; |Δ| of
  blocked AUC, pooled Boyce, null-test p and map strength; map difference
  against the float32 tolerance. Reported for a1 vs a2 (same family, other
  process state), a vs b (across families), and each vs c, by learner and
  site band.

## Reading

- a1 ≠ a2 means non-determinism within one machine type: report it and fix
  it before submission.
- Differences only between a and b are machine effects: report the
  grade-flip rate with its interval, and state it wherever grades are used.
- If flips concentrate in small-site tuned Maxent, say so, and test whether
  a more stable tuning rule (a fixed path, or a tie tolerance) removes them;
  that is a method change for a later release, not the frozen one.
- **The block size is a second machine effect (added 2026-10-20, before any
  arm).** E6b found that a full-design model's block size depends on the
  processor family for some taxa. The block is the blockCV variogram range
  rounded to 5 km, and the same records gave gaps of 5 to 240 km between
  r7a and r7i (*Hemimycena* sp. 'lactea-PNW04': 300 against 60 km). That
  was 35 of the 1,144 hindcast taxa whose maxnet was fitted on r7a (E6b
  prereg, Deviations, 2026-10-20). A different block means different
  folds, and so different tuning, AUC, null test and possibly grade. So
  a-vs-b differences in full-design models (Maxent, RF, boosted trees) have
  two possible sources, the block and the tuning; ESM's blocks are a fixed
  100 km.
  - The arms do not record the block. After the arms, a short step computes
    the variogram block alone (no fit) for every drawn full-design model,
    once on r7i and once on r7a. Same-family runs are deterministic (gate 2),
    so these are the blocks the arms used.
  - The reading then splits each a-vs-b difference into "block changed" or
    "same block", and reports the grade-flip rate for each. Only the
    "same block" share is the tuning or numerics effect that the bullet
    above reads.

## Cost

Estimated from R_main's own shard records rather than a flat rate: for the
drawn sample, the sum of each model's recorded `seconds` (nulls included) ×
3 fits. The first guess of 30–60 CPU-h was low, because the sample
over-represents rich taxa.
Gate: feat/result-machine merged (done).

**The draw and its cost (2026-10-19, before any arm).** `study-e12-draw`
on release fa1b4198, read-only (atlas-box, image 8bfc98d):

- **507 models in 24 cells**, 0 with imputed times. Left out of the index:
  1 untested, 493 refused; 9,040 kept.
- **Cap not applied.** The 50+ site Maxent cells are 0.275 of the cost,
  under the plan's 0.5 trigger.
- **109.7 CPU-h for three fits each**, about 36.6 per arm:

| Learner | Models | CPU-h (3 fits) |
|---|---|---|
| ESM | 225 | 31.6 |
| Maxent | 128 | 45.0 |
| Random forest | 114 | 25.3 |
| Boosted trees | 40 | 7.8 |

The draw file (per model: cell, rank, recorded seconds) is
atlas-box:/home/ubuntu/seamcheck/gt/e12-draw.csv, private (taxon names and
numbers only).

## Implementation (not a design change)

The arms are `study-repro --draw`, and they run at Atlas main 679b2cc
(branch study/e12-arms 04fb517; Steve reviewed it, and it was merged with
the full suite at 1,187/0), in that commit's image.

- **The sample.** Each worker recomputes the sample from the release by
  this plan's rule, with the same code as `study-e12-draw`. It records the
  sample's key, so the arms can be shown to have fitted the same 507
  models.
- **Inputs, settings and nulls.** Each model is fitted on the inputs and
  fit settings of the job that fitted it (the frozen release holds models
  of more than one job and pull), with that job's nulls: 99, stopping at 5.
- **Processes.** The models run in fresh worker processes, each in a fixed
  order. Every result records its worker, its place in that order, the
  process and the machine.
- **Commands** (on atlas-box, in the 679b2cc image):
  - a1: `plan-study --command=study-repro --shards=2 --args="--draw
    --release=20261013T191324Z-fa1b4198 --label=a1 --workers=16"`, run on
    r7i.8xlarge;
  - a2: the same with `--shards=3` and `--label=a2 --order=reverse`, on
    r7i.8xlarge;
  - b: as a1 with `--label=b`, on r7a.8xlarge.
- **Workers.** 16 per 256 GB worker leaves room for a rich Maxent fit's
  ~9 GB peak with nulls.
- **Smoke run (2026-10-20, before any arm):**
  study-20261020T052712Z-5b79132a, at Atlas 6dbdba8 (which adds
  `--draw --limit` and the run guard). The first 4 drawn models, 2 worker
  processes, r7i.large, production nulls. Result: 4 fitted, the same
  records as the release 4/4, the same grade 4/4, identical to the release
  4/4. The arms run at 6dbdba8 or later. A shard with more than 5% of its
  models unfitted fails as a whole.
- **Image for the arms (2026-10-20).** All three arms (a1, a2 and b) run
  on the 6dbdba8 image, the one the smoke run passed on: not the 679b2cc
  image named above, and not a later one. 6dbdba8 is 679b2cc plus
  fix/study-distance-layers 00e7209. 00e7209 does not change how `--draw`
  fits a model: the arms' worker fit is the same code. For the arms it adds
  only `--limit` (the smoke run's first models; the arms set no limit) and
  the stop when more than 5% of a shard's models are unfitted, checked
  after its results file is written. Its other changes (the layer fetch,
  the worker layer check) are in the distance and default-practice
  studies, which the arms do not use.
- **The block-only step (written 2026-10-21, before it runs).** It is
  `study-repro --draw --blocks` (Atlas study/e12-blocks b407054, merged
  before the run). It takes the same drawn sample as the arms (the same
  sample key), keeps the full-design models (Maxent, random forest, boosted
  trees: 282 of the 507), and for each one builds the training table its fit
  builds: the fitting job's inputs and settings, and the model's
  fingerprint, so the same sites and seed. It then measures the spatial
  block alone (`atlas_block_size`), with no fit, and records it beside the
  block the release fit recorded. ESM's block is a fixed 100 km and is not
  measured.
  - Runs: once on r7i.2xlarge (`--label=r7i`) and once on r7a.2xlarge
    (`--label=r7a`), one shard each, `--workers=4`. Each about 20 to 40
    minutes, well under $1 together.
  - Fits are deterministic within a family (gate 2), so each run's blocks
    are the ones that family's arms fitted on: r7i for a1 and a2, r7a for b.
  - Reading: each of b's 5 differing models, and each of the 277 that did
    not differ, is classed "block changed" (r7i ≠ r7a) or "same block". The
    cross-family grade changes are reported in each class, as this plan's
    Reading already sets out (2026-10-20). A model whose r7i block differs
    from its release's recorded block is reported too: the release itself
    was fitted on both families.
  - Test before the run: on a synthetic taxon whose block sits inside the
    50 to 300 km limits, the step gives exactly the block a real fit
    records.

## Runs

Logged by the rebuild lane as ops reports them. Numbers only; the reading
waits for all three arms and the block-only step.

- **a1 (2026-10-20): done.** study-20261020T182524Z-717cf60a, image
  6dbdba8, 2 shards, both on r7i.8xlarge. 507 models drawn (254 + 253), 507
  fitted. Against the frozen release: same records 507, same grade 507,
  identical 507.
- **b (2026-10-20): first launch lost, nothing saved.**
  study-20261020T182526Z-95330a0a. Its 8 r7a.8xlarge spot workers were
  reclaimed between 18:30 and 19:15 UTC (Server.SpotInstanceTermination),
  and the orchestrator stopped after 4 attempts on shard 1 without a
  result. No model from it is read. Steve chose to run b again on spot
  later, with the same plan and image; that is a relaunch, not a design
  change.
- **a2 (2026-10-20): done, and did not match a1.**
  study-20261020T212937Z-cfac20a6, image 6dbdba8, 3 shards on r7i.8xlarge
  (41 to 45 min each), `--order=reverse`. 507 fitted; same records 507,
  same grade 507, identical to the release 316. All 191 that differ are
  ensembles (ESM), 191 of the 225 drawn: the map's bytes in 190, the map
  and pooled Boyce in 1 (*Heliocybe sulcata*, 0.054 against 0.055).
  Maxent 128/128, RF 114/114 and boosted trees 40/40 are identical. Cause
  and handling: Deviations, 2026-10-20.
- **a2 again (2026-10-21): identical to the release.**
  study-20261021T002552Z-cfac20a6, image 1a9c3ae (Atlas main with
  5b58f30 and a8861ab), 3 shards on r7i.8xlarge (40.4, 43.9 and 48.5 min),
  `--order=reverse`, finished 01:16 UTC. 507 fitted; same records 507, same
  grade 507, identical to the release 507. The 191 ensembles that differed
  in the first a2 are now identical. a1 and a2 agree model for model.
- **b (2026-10-21): done.** study-20261021T011833Z-c7b64a0a, image 1a9c3ae,
  one r7a.8xlarge on-demand (AMD EPYC 9R14), `--shards=1 --workers=16`,
  seeded order, 01:20 to 02:53 UTC (93 min). 507 fitted; same records 507,
  same grade 505, identical to the release 502. Every ensemble (225) and
  every boosted-trees model (40) is identical; Maxent 127 of 128 and random
  forest 110 of 114. The 5 that differ, all at 20–49 sites, all with the
  same records:

  | Taxon | Learner | Grade, release → b | Parts that differ | Largest tuning-score change; correlation of the tuning tables |
  |---|---|---|---|---|
  | *Leucopholiota decorosa* | Maxent | failed → weak | settings, tuning, AUC, Boyce, fold AUC, map | 0.132; −0.575 |
  | *Galerina* sp. 'WI01' | RF | weak → weak | settings, tuning, AUC, Boyce, fold AUC, map | 0.0547; −0.912 |
  | *Stropharia hardii* | RF | weak → weak | settings, tuning, AUC, Boyce, fold AUC, map | 0.029; −0.958 |
  | *Clavulinopsis appalachiensis* | RF | weak → strong | tuning, AUC, Boyce, fold AUC (same settings and map) | 0.0598; 0.286 |
  | *Tricholoma focale* | RF | weak → weak | settings, tuning, AUC, Boyce, fold AUC, map | 0.0345; −0.493 |

  *Leucopholiota decorosa*'s Maxent: the release chose lq, regmult 2 (AUC
  0.556, Boyce −0.107); b chose lqh, regmult 0.5 (AUC 0.604, Boyce 0.251).
  All five taxa are among the 35 whose variogram block differed between
  r7a and r7i in E6b (E6b prereg, Deviations, 2026-10-20), there on the
  hindcast's records. Whether each of the five rebuilt another block here
  is what the block-only step measures; the reading waits for it.

- **Reading note (2026-10-20, after a1, before b).** The release's own
  machine family for the 507 cannot be recovered. R_main's job
  (20261013T022520Z-2cb67f32) and the targeted and retire jobs recorded no
  machine per shard or model. Their instances are gone, and gate 2 placed
  its three taxa by which family's refit matched, not from a record. So
  arm (c) has no family to report by. a1 matched the release for all 507,
  so b against a1 is the cross-family test by itself:
  - a model where b differs from a1 is family-sensitive, and its release fit
    was on r7i;
  - a model where b matches a1 is stable across families, whichever family
    fitted it in the release.
  The flip rate is then b's differences over the 507 (weighted by cell, as
  planned), and "stable" holds whatever the release's family mix.

## Deviations

- **2026-10-20, after a2 and before b: a fix to the ensembles' fits, and
  a2 run again.** a2's first run (study-20261020T212937Z-cfac20a6) gave
  other map bytes for 191 of the 225 drawn ensembles, with every grade
  unchanged, where a1 gave the release's own for all 225. By this plan's
  Reading, a difference between a1 and a2 is non-determinism within one
  machine type, to be explained and fixed before the study reports.
  - **Cause.** glmnet's settings are global to an R process, and every
    Maxent fit sets two of them (pmin = 1e-8, fdev = 0) and leaves them
    set. An ensemble's small models (ridge glmnet) inherit whatever the
    process holds. In a2, every ensemble had a Maxent fit before it in its
    worker process, and 191 differ. In a1, none had, and all 225 match.
    Production fits each learner in a fresh pool of worker processes, and
    every fitting shard of R_main, the targeted job, the full-view refresh,
    the hindcast and the leave-out refit ran with 32 workers. So every
    released ensemble was fitted at glmnet's own defaults. In a local test,
    the same ensemble fitted under the two settings differed in every cell
    of sparse, heavy-tailed data (by up to 0.027 in suitability), and not
    at all on tamer data.
  - **Fix.** Atlas fix/esm-glmnet-defaults 5b58f30 fits each small model at
    glmnet's defaults and puts the process's settings back after. That is
    the state every released ensemble was fitted in, so released maps are
    reproduced and not changed. fix/detection-glmnet-pin a8861ab, stacked
    on it, pins the detection model too (E1 and E14 only; it was never
    affected). Maxent, RF and boosted trees are unchanged.
  - **a2 again**, on the image built from Atlas main at the merge of
    a8861ab (it holds 5b58f30): the same command as the first a2, 3 shards
    on r7i.8xlarge spot, `--order=reverse`, the same draw and nulls.
    Expected: identical to the release for all 507. The ensembles' fits no
    longer depend on what ran before them, and nothing else changed. If any
    model still differs from a1, b does not run until it is explained.
  - **a1 stands.** Its ensembles ran with no Maxent fit before them, at
    glmnet's defaults, which is what the fix pins. The other learners' code
    is unchanged.
  - **b then runs** on the same image as a2's rerun, on one r7a.8xlarge
    on-demand (`--shards=1 --workers=16`; Steve, 2026-10-20). Spot
    capacity for 2 × r7a.8xlarge could not be had (first launch,
    study-20261020T182526Z-95330a0a, reclaimed). Every r7a size is the same
    processor family, and fits are deterministic within a family (gate 2).
    A different shard split moves models to other worker processes, which
    a2's rerun tests.
  - **Result of a2's rerun (2026-10-21):** 507 of 507 identical to the
    release (study-20261021T002552Z-cfac20a6, image 1a9c3ae), as expected.
    The fix is confirmed, and a different split and order no longer change
    any fit. b may run.
