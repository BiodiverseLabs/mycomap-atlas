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

## Deviations

None yet.
