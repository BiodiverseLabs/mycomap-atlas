# E11: grade stability between two nightly releases (20261118 → 20261119)

Descriptive and exploratory. Written on 2026-11-19, after the flips it
describes were seen; nothing here was planned before them. Counts and taxon
names only: no record numbers, places or coordinates.

- **Question.** When a model is refitted because its records changed, how
  often does its grade move across the strong line, and how much of that is
  the null test's own chance rather than the evidence? Serves the paper's
  stability evidence (E11, "Stability across nightly releases").
- **Data.** Two consecutive releases: 20261118T112141Z-42873a81 (the earlier)
  and 20261119T110027Z-7f37e0fd (the later, the first timed nightly, job
  b1a428e6, code e05d2f7). For every model whose metrics changed between them
  and whose `built_at` differs, the release store's model metrics, read
  read-only (refits-42873a81-to-7f37e0fd.tsv, sha256 8af43920…, 2,360 rows;
  the strong flips alone in strong-churn-42873a81-to-7f37e0fd.tsv, sha256
  0cb41122…, 147 rows). Columns per side: grade, presences, null reps,
  null auc_p, stopped early, pooled Boyce, cross-validated AUC, block size and
  source. Taxon and learner only.
- **Code.** e11_figures.py (sha256 3b54a0d5…), run on the refit table.
  Monte Carlo figures use exact binomial and negative-binomial
  probabilities; no random numbers.
- **Rule in force.** Both releases graded a map strong when, of up to 99
  shifted nulls (stopping once 5 did as well), at most 4 did at least as well
  as the map (p = (1 + k) / 100 ≤ 0.05), and its pooled Boyce index was above
  0. Weak and failed as in the release notes.

## Result

**The refit set.** 2,360 models changed: 138 are new in the later release,
33 left it (refused or retired), and 2,189 are in both. 2,174 of those have a
grade on both sides (15 carry no grade on one side). By learner: ESM 935,
Maxent 590, random forest 590, boosted trees 245 (all 2,360 rows).

**Across the strong line.** Of the 2,174 graded in both: strong 169 → 147,
79 left strong and 57 joined, net −22. Counting the new and departed models
too: 80 left and 67 joined, net −13 models (−6 taxa: 50 out, 44 in). Over the
whole release, strong models went from 630 to 617.

**Flips per refit, by learner and site band** (band by detection sites in the
later release; graded in both):

| Learner | Band | Refits | Flips | Per refit |
|---|---|---|---|---|
| ESM | 3–4 | 50 | 1 | 0.020 |
| ESM | 5–9 | 178 | 15 | 0.084 |
| ESM | 10–19 | 238 | 20 | 0.084 |
| ESM | 20–49 | 344 | 28 | 0.081 |
| Maxent | 20–29 | 128 | 12 | 0.094 |
| Maxent | 30–49 | 194 | 14 | 0.072 |
| Maxent | 50–99 | 181 | 10 | 0.055 |
| Maxent | 100–199 | 57 | 1 | 0.018 |
| Maxent | 200+ | 5 | 0 | 0 |
| Random forest | 20–29 | 128 | 10 | 0.078 |
| Random forest | 30–49 | 194 | 11 | 0.057 |
| Random forest | 50–99 | 181 | 8 | 0.044 |
| Random forest | 100–199 | 57 | 1 | 0.018 |
| Random forest | 200+ | 5 | 0 | 0 |
| Boosted trees | 50–99 | 172 | 4 | 0.023 |
| Boosted trees | 100–199 | 57 | 1 | 0.018 |
| Boosted trees | 200+ | 5 | 0 | 0 |

136 flips in 2,174 refits (6.3%).

**How close strong maps sat to the line.** The 169 models strong in the
earlier release, by k, the number of its 99 nulls that did at least as well:
k = 0: 35, k = 1: 40, k = 2: 28, k = 3: 41, k = 4: 25. So 66 (39%) were one or
two nulls from failing.

**What chance alone would give.** If a refit changed nothing but the null
draws, each model would face the same chance π that a null does as well as
it. For each model, π was taken from its earlier test (uniform prior over π,
updated by that test's outcome), and the probability that a fresh test of 99
lands on the other side of the line was summed over models, with the Boyce
index held as it was. Expected: 38.1 strong models falling out and 31.6
coming in, about 70 flips, against the 136 seen.

**Which flips chance explains.** For each of the 136 flips, a likelihood
ratio test (1 df) asked whether one π explains both releases' null
outcomes:

| | Flips |
|---|---|
| One π fits both (LR < 3.84): the null test's own chance | 54 |
| Borderline (3.84 ≤ LR < 6.63) | 28 |
| π moved (LR ≥ 6.63, p < 0.01): the evidence changed | 52 |
| The Boyce index crossed 0 while one π fits | 2 |

**What changed in the evidence.** Detection sites, later minus earlier:

| | 0 | +1 | +2 to +5 | over +5 | fewer |
|---|---|---|---|---|---|
| All 2,174 refits | 246 | 1,227 | 589 | 15 | 97 |
| The 136 flips | 14 | 83 | 33 | 2 | 4 |

The block size or its source changed in 7 of the 136 flips (random forest 4,
Maxent 3). ESM's block is fixed at 100 km.

**Reading.** About half the flips are what the null test's own chance gives
at unchanged evidence. Most of the rest followed a change of one or a few
detection sites, which re-deals the spatial folds and the null draws for the
whole taxon. Near the line, a grade from one fold split and 99 nulls is not
stable between nights. Flips per refit fall with site count for the full
models (about 0.09 at 20–29 sites to 0.02 at 100–199) and stay near 0.08 for
ESM from 5 sites up.

**Limits.**
- One pair of releases, one night. The rates are for this night's refit set,
  which is the taxa whose records changed, not a sample of all taxa.
- The Monte Carlo expectation takes π from one earlier test per model under
  a uniform prior. It is an estimate, and it holds the Boyce index fixed.
- Map agreement between the releases (rank correlation of the maps) was not
  measured: it needs both releases' rasters.
- Fit times, processors and blocks: both releases ran on Intel Xeon 8488C
  workers; within one processor family a fit is the same on the same
  evidence.

**What came of it.** The owner chose to change the null test (several fold
splits pooled, and more nulls near the line). Releases from the first one
built under that rule are graded by it; this entry describes the rule before
it.
