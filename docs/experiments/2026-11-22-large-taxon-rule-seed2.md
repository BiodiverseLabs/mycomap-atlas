# Pre-registration: the stricter null test for maps with 200+ sites, checked on fresh virtual species (seed 2) (E number: the PC's to assign)

Written on 2026-11-22 by the method lane, before seed 2 ran. It follows
E1d (registry/2026-11-21-null-rule-calibration.md, sha256 7dd1db3b…). It uses
counts and virtual species only: no record numbers, places or coordinates,
and no real taxon names.

## The correction

E1d measured the candidate test: pooled over 5 fold splits, going on to 199
nulls near the pass line. At 200 or more sites it passed 12.6% of Maxent and
11.2% of random-forest geography species, which have no habitat signal.
Below 200 sites it passed 5.0% and 5.5%. Steve decided on 2026-11-21 not to
adopt it until its size was corrected. On 2026-11-22 he approved this
correction:

- **Below 200 detection sites:** unchanged. The test is E1d's candidate.
- **At 200 or more sites:**
  - The test draws up to 199 shifted nulls, pooled over the 5 splits.
  - The first 99 give no clear pass.
  - The test stops once 3 nulls have done at least as well as the map.
  - The map passes when p ≤ 0.015 and its Boyce index is above 0. With 199
    nulls scored, p = (1 + k) / 200, so it passes when k ≤ 2. A test that
    stops fails, because p = 3 / scored is above 0.015 for any count of
    nulls up to 199.
  - The near-line extension does not apply.
- **Sites** means the taxon's detection sites in the table the null test
  runs on. This is the same count that places a virtual species in its band.
- The rule covers every learner. ESM is never fitted at 200+ sites.

Code: branch feat/large-taxon-nulls, commit
d04c60a7aa2772ad98354a69f8bb9c2526e92b60, off feat/extended-nulls 5c670d62.
- `ATLAS_NULL_LARGE = list(sites = 200, reps = 199, stop_after = 3, alpha = 0.015)`
- `atlas_null_plan`
- the verdict, `atlas_skill`, reads the test's own alpha

## How the count was chosen, on seed 1

The plan sent to Steve on 2026-11-21 set a grid of 1, 2 or 3 nulls of 199.
It said to take the largest count whose estimated false-pass rate on seed 1
was at most about 6%, for both Maxent and random forest at 200+ sites. The
grid and the criterion were written after seed 1 had been read. So seed 1 is
the data the count was chosen on, and it cannot confirm the choice.

The estimates come from calibration/grid_large_rule.py (sha256 501e49ca…) on
the 11/21 run; output calibration/run-20261121-grid.txt (sha256 e3175fbf…).
- A clear pass at 99 nulls has unknown k over nulls 100 to 199. Each is
  weighed by the beta-binomial chance that those nulls add few enough as
  good.
- The bounds count each such test as failing (low) or passing (high).

| Count of 199 | Maxent at 200+ | Random forest at 200+ | Maxent overall | Random forest overall |
|---|---|---|---|---|
| 1 (p ≤ 0.010) | 4.7% (0–7.5) | 3.4% (0–6.2) | 5.0% | 5.1% |
| **2 (p ≤ 0.015)** | **5.9% (0–7.5)** | **4.5% (0–6.2)** | **5.2%** | **5.3%** |
| 3 (p ≤ 0.020) | 6.6% (0–7.5) | 5.2% (0–6.2) | 5.3% | 5.4% |

Count 2 is the largest count that meets the criterion. At count 3, Maxent's
estimate is 6.6%.

None of seed 1's extended 200+ false passes had k ≤ 3 of 199; they had 4 to
9. Every remaining false pass at 200+ is a clear pass on the first 99 (12
for Maxent, 10 for random forest), and the rule's effect rests on how those
fare over the next 100 nulls. Seed 2 measures this directly.

## Seed 2

**Species.** Seed 2's draws of E1's layout, from the same frozen release
20261013T191324Z-fa1b4198, pull x73b85b36 and layers, which are only read:
- every geography species: 800 full-model and 360 ESM, 1,160 in all;
- the habitat species at 200+ sites: 2 breadths × 2 signals × 60 = 240.

That is 1,400 species. They are drawn from the same seeds that seed 2 of the
full layout would use.

**Learners and design.** As in E1d: Maxent and random forest for full-model
species, ESM for ESM species, shift nulls only, and no effort arms.

**Run.**
- Command: `study-calibration --seed=2 --workers=30 --null-rule=production
  --designs=shift --effort-arms=none --bands=habitat:200+`, at the commit
  above, the study image built from it
  (`:study-d04c60a7…`).
- 8 spot r7i.8xlarge workers, MAX_HOURS 5, capped at $40 (Steve,
  2026-11-22). Ops launches it.

**Reader.** calibration/read_seed2.py, sha256 2d588cf3…, written before the
run. Run on seed 1's two runs, it reproduces their figures. It reads the
saved shard results, and the worker log lines for a shard that saved none.

## The success test

For Maxent and for random forest alike, the Wilson 95% interval of the
geography false-pass rate must include 5%:

1. over every band, and
2. at 200+ sites.

All four parts must hold.

- A learner-species left unscored by the run is counted both ways, failed
  and passed. The test holds only if it holds both ways.
- A test the procedure leaves untested, or a learner that fails to fit, is
  no pass. It is counted apart and left out of the rates, as in seed 1.
- With about 160 tests at 200+ sites, the interval test allows up to 13
  false passes (8.1%). Over all bands, with about 800 tests, it allows about
  51 (6.4%). It is a check that the correction brings the size near 5%, not
  a test of equivalence. The reader also prints each part's binomial tail
  against a true 5%, as description only.

**If the test holds:** the rule is offered to Steve for production, with
seed 2's figures. Adopting it is his decision.

**If the test does not hold:** the rule does not go to production. It is not
tuned on seed 2. The next step is a new design, for example the placement of
shifted nulls for big taxa (see below), registered before any further run.

## Reported with no criterion

- **Power at 200+ sites:** the habitat species' pass rate, by learner,
  breadth and signal. Seed 2's habitat species are new draws, so E1's
  single-split power at 200+ (seed 1) is context, not a paired comparison.
- ESM's false-pass rate. ESM is never fitted at 200+ sites, so the rule
  does not touch it.
- The false-pass rate by band below 200 sites: E1d's candidate on fresh
  species.
- How many 200+ tests stopped, and how many passed.
- Time: species-hours, the slowest species, and instance-hours and cost
  from ops.

## Not measured here

- **Grade stability** under the corrected test, E11's question. Below 200
  sites the test is E1d's candidate, which E11 has not been rerun on either.
- **Learners other than Maxent, random forest and ESM.** In production,
  boosted trees at 200+ sites get the same rule without a calibration of
  their own.
- **Why the pooled test is oversized at 200+.** Seed 1's 200+ false passes
  had nearly all their shifted nulls placed best-effort. Steve has noted the
  placement of nulls for big taxa as a later project.

## Correction to E1d

E1d says that 2 learner-species were left untested by the procedure. Three
learner-species of seed 1 went unscored:
- 2 were left untested by the procedure: one Maxent and one random forest,
  of the same species, in the 100–199 band;
- 1 was a Maxent fit that failed at 200+ sites (glmnet did not complete its
  regularization path).

E1d's tables are right: Maxent 798 and random forest 799.
