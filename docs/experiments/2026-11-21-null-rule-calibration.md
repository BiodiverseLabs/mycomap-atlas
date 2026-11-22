# Calibration of the pooled near-line null test: a declared deviation (E number: the PC's to assign)

Written on 2026-11-21 by the method lane, after both runs it describes. Counts
and virtual species only: no record numbers, places or coordinates, and no
real taxon names.

## What is declared

The null test that E1 (2026-10-25, appendix S5) measured is not the test the
next release will use. In E1's test, the map and 99 shifted nulls are scored
on one fold split; the test stops once 5 nulls do as well as the map, and the
map passes when p = (1 + k) / 100 ≤ 0.05 and its Boyce index is above 0. The
candidate test (branch feat/extended-nulls) differs in three ways:

- the map and every null are scored on 5 fold splits, and compared by their
  mean AUC;
- near the pass line the test goes on to 199 nulls, stopping once 10 do as
  well. "Near the line" means the first 99 stopped on their 50th null or
  later, or did not stop and more than 1 did as well. The pass rule is then
  p = (1 + k) / 200 ≤ 0.05;
- each null's fits are seeded from its own draw number, so a result does not
  depend on how the nulls are batched or across how many processes they are
  scored.

This entry declares that E1's false-pass rates do not carry over to the
candidate test, records the two runs that measured it, and records Steve's
decision (2026-11-21) not to adopt it until its size is corrected.

## Runs

Both runs put E1's own geography species (virtual species with no habitat
signal) through the candidate test: 1,160 species from release
20261013T191324Z-fa1b4198, seed 1. E1's pull and layers are only read; the
frozen release is unchanged. The learners are Maxent (maxnet) and random
forest at 20 to 320 sites, and ESM at 3 to 19 sites. The shift design is
used, with no effort arms. The 2 learner-species left untested were left so
by the procedure, not by the run.

1. **2026-11-20, study-20261120T165750Z-6d041658: failed, then partly
   salvaged.**
   - Code c2766e20. Near the line it went to 499 nulls, stopping at 25.
   - It ran on 8 spot r7i.8xlarge workers, about $28.
   - The run failed on spot reclaims. Two faults in the job runner caused
     this, both since fixed (fix/study-resume, Atlas main 839c113): a failing
     shard stopped its siblings, and a study shard saved nothing until it
     ended.
   - What was saved: 490 learner-species from saved results and 1,340 from
     worker log lines, for 1,073 of the 1,160 species.
   - The 87 species missing are not a random subset. About 77 are one shard
     whose logs were overwritten; about 10 are slow species still running at
     the abort.
   - Reader: calibration/read_production_nulls_partial.py (sha256 42cc4f5e…).
     Output: calibration/run-20261120-partial-read.txt.
2. **2026-11-21, study-20261121T201819Z-6d041658: the measurement.**
   - Code 5c670d62, image :study-5c670d62… (CI run 44942714408 green).
     Near the line it goes to 199 nulls, stopping at 10, with nulls scored in
     parallel at a shard's end.
   - It ran on 8 on-demand r7i.8xlarge workers, one attempt each: 12.93
     instance-hours, about $27, 2.02 h of wall time.
   - All 1,160 species were scored.
   - Reader: calibration/read_calibration_199.py (sha256 6c018355…).
     Output: calibration/run-20261121-read.txt (sha256 6f2422d6…).

## Results (run 2; Wilson 95% intervals)

| Learner | Species | E1 false pass | Candidate false pass | Passed under E1 only / candidate only (exact McNemar) |
|---|---|---|---|---|
| Maxent | 798 | 46 = 5.8% (4.3–7.6) | 52 = 6.5% (5.0–8.4) | 10 / 16 (p = 0.33) |
| Random forest | 799 | 39 = 4.9% (3.6–6.6) | 53 = 6.6% (5.1–8.6) | 8 / 22 (p = 0.016) |
| ESM | 360 | 6 = 1.7% (0.8–3.6) | 6 = 1.7% (0.8–3.6) | 1 / 1 |

- Against a true size of 5%, P(≥ 52 of 798) = 0.034 for Maxent and
  P(≥ 53 of 799) = 0.024 for random forest.
- At 200 or more sites the candidate's false-pass rate is 20/159 = 12.6%
  (8.3–18.6) for Maxent and 18/160 = 11.2% (7.2–17.1) for random forest.
  E1's was 10.7% and 6.2%; P(≥ 20 of 159 | 5%) = 0.0002.
- Of these 38 false passes, 22 passed their first 99 nulls outright (k = 0
  or 1). Their shifted nulls were nearly all placed best-effort: all of them
  for 32 of the 38, and at least 98% for the rest.
- Below 200 sites the candidate's rates are 32/639 = 5.0% for Maxent and
  35/639 = 5.5% for random forest.
- 131 of 1,957 learner-species tests went past 99 nulls.

**Sensitivity row: the 199 cap against 499** (the 1,073 species of run 1,
with run 1's caveat).

| Learner | 499/25 | 199/10 | Passed under one only (499 / 199) |
|---|---|---|---|
| Maxent | 5.7% | 5.4% | 4 / 2 |
| Random forest | 5.3% | 5.3% | 3 / 3 |
| ESM | 1.9% | 1.6% | 1 / 0 |

- Per-draw seeding makes the two runs' first stages identical, so this is a
  paired comparison of the cap alone. The cap changes nothing measurable.
- The rise against E1 comes from pooling the splits.
- Run 1 understated the false-pass rate. The 87 species it lacked passed more
  often than the rest: for random forest, 13 of 42.

**Time** (run 2).

- 198.4 species-hours. Median species 243 s, 90th percentile 1,714 s,
  slowest 6,054 s (a 200+ species).
- No species ran over 2 h; in run 1, 10 did.
- Parallel nulls did run, as a timing comparison with run 1 on identical work
  shows. Species that could use spare cores for over half their run took
  0.69 times their run-1 time, against 0.96 times for those that could not.

## Decision

Steve, 2026-11-21 (through the Atlas coordinator): "Hold: fix the size first".

- The candidate test does not go to the nightly or to a release. The nightly
  keeps E1's test.
- A size-corrected cut-off is to be designed. Its aim is about 5% false
  passes for Maxent and random forest, including at 200+ sites.
- The correction is to be checked on fresh virtual species (seed 2) before
  adoption.
- The cut-off and seed 2's success criterion will be registered in their own
  entry before seed 2 runs. Seed 1 chose the correction, so seed 1 cannot
  confirm it.

## Not measured here

- Power (habitat species): the candidate test has not been run on them. The
  power figures are still E1's single-split ones.
- Grade stability under the candidate test (E11's question).
- Learners other than Maxent, random forest and ESM. Boosted trees are not in
  E1's virtual-species design.
