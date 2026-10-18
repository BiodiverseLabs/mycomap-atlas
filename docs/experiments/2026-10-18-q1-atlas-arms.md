# Q1 result: Atlas maps as MycoMap Vision's place signal (paper E21, E22)

- **Question.** The pre-declared question Q1: do the maps carry habitat
  information another system can use? Registered in the Vision repository
  (`docs/atlas-environment.md`, version b78609d, analysis plan unchanged
  since 5c9a4b6).
- **Reproducibility.** frozen. Atlas hindcast release
  priv-20261018T171648Z-9e3ab153 (trained on records first validated on or
  before 2026-08-17; 414 strong taxa). Vision v1 validation set with erratum
  r4 and answer key species-rank-2026-10-18.
- **Code and write-up.** Vision research repository, commit 9fefcbb,
  `experiments/2026-10-18-atlas-arms.md` (run by the Vision place-scoring
  lane; this entry summarises it).
- **Data notes.** 12,872 finds scored. Two validation records were left out
  after a leak found by the run: a cross-source id collision in Atlas's
  first-validation lookup (brought to Steve by the Atlas operations lane;
  see the E2 pre-registration). Only 7.1% of validation records have a true
  taxon with a strong map in the hindcast release.
- **Result (out-of-fold species top-1, %).**

  | Arm | Top-1 | vs photos only |
  |---|---|---|
  | Photos only (P0) | 53.81 | — |
  | DNA-distance boost (P1) | 56.15 | +2.34 |
  | Served prior (penalty-500) | 56.85 | +3.03 |
  | **P2c, as declared** | 54.26 | +0.45 |
  | P2c without the band rule | 55.93 | +2.12 |
  | P2c on top of the served prior | 56.62 | +2.81 |
  | P3, max(DNA, Atlas) | 56.14 | +2.33 |
  | P2b, Atlas alone | — | +1.29, holds the 300–1,500 km band |

  - **Declared primary test:** passes (McNemar p = 0.0001), but only because
    the declared selection falls back to photos-only in most folds.
  - **Against the DNA boost it was meant to replace:** the Atlas term loses
    by 0.22 points (55 fixed, 83 broken), on mapped truths at matched
    reference depth.
  - **Projection validity (H), finds 500 km or more from any training
    record, 52 records:** inside the area of applicability (41), Boyce 0.75
    but 39% ranked at or above the median (95% CI 26–54%), so not valid by
    the declared criterion (the interval must exclude 50% upward); outside
    it (11), Boyce −0.26.
  - **Habitat rank as a cue:** the served answer's habitat rank separates
    right from wrong answers with AUC 0.61; the share right is 48%, 62% and
    68% in the low, middle and high suitability terciles.
- **Reading.** The maps carry some habitat information that another system
  can use: alone they add 1.3 points and hold the far-find band, and the
  habitat rank works as a cue for whether an identification is right. But
  they add nothing beyond a distance kernel over the same DNA records, and
  the continent-wide projection is not supported beyond 500 km. Coverage
  limits all of this: under 8% of records have a strongly mapped truth.
- **Cost.** [PENDING: from the Vision lane's run record; the hindcast's own
  cost is logged separately.]
- **Decision (Steve, 2026-10-18).** The Atlas prior stays off in Vision; a
  validator-only habitat-fit cue is to be designed, as a mockup first.
