# Main tables (draft)

*Draft, 2026-11-05. Numbers are copied from the registry entries named under
each table, not recomputed here; learner totals in Table 1 are sums of the
registry's cells. "Holds" is the registered criterion's outcome, not a
reading of it.*

## Table 1. The atlas at a glance (frozen release 20261013T191324Z-fa1b4198)

**a. Records and taxa**

| | Count | Only a provisional name |
|---|---|---|
| Records in the pull | 133,235 (iNaturalist 94.9%, Mushroom Observer 3.8%, MyCoPortal 1.2%) | |
| Taxa | 16,252 | 9,785 (60.2%) |
| Fewer than 3 sites, never modelled | 9,442 | |
| 3 or more sites, refused | 441 | |
| Modelled | 6,369 | 3,193 (50.1%) |
| With a strong map | 470 (7.4% of modelled, 2.9% of all) | 213 (45.3%) |

**b. Models by learner and grade**

| Learner | Models | Strong | Weak | Failed | Untested |
|---|---|---|---|---|---|
| Ensemble of small models | 6,041 | 365 | 4,141 | 1,535 | 0 |
| Maxent | 1,336 | 121 | 1,060 | 154 | 1 |
| Random forest | 1,336 | 85 | 1,153 | 98 | 0 |
| Boosted trees | 328 | 5 | 313 | 10 | 0 |
| **All** | **9,041** | **576** | **6,667** | **1,797** | **1** |

**c. Modelled taxa by sites (a taxon's band and grade are its best model's)**

| Sites | Taxa | Strong | Strong share |
|---|---|---|---|
| 3–4 | 1,655 | 34 | 2.1% |
| 5–9 | 1,970 | 109 | 5.5% |
| 10–19 | 1,404 | 139 | 9.9% |
| 20–49 | 1,012 | 166 | 16.4% |
| 50–99 | 276 | 22 | 8.0% |
| 100+ | 52 | 0 | 0% |

**d. Cost and time.** [PENDING: one full rebuild and the standing monthly
cost, compute and storage, once billed figures are in (`costs.md`).]

Sources: `2026-10-28-e16-descriptives.md`, `2026-10-19-grade-tiers-fa1b4198.md`,
`costs.md`.

## Table 2. Each claim, its test, its criterion and the result

Intervals are 95%. "Reg." is registered before the result; "Desc." is
descriptive, with no pass line.

| Claim | Test | Kind | Criterion | Result | Outcome |
|---|---|---|---|---|---|
| C1 | H1a: shifted nulls, false pass on simulated species with no habitat | Reg. | upper bound ≤ 5% and every site band ≤ 5%, each learner | Maxent 5.8% (4.3–7.6); random forest 4.9% (3.6–6.6) | Does not hold, either learner |
| C1 | H1b: scattered nulls, same species | Reg. | lower bound > 20%, rising with site band | Maxent 75.1% (72.0–78.0); random forest 81.8% (78.9–84.3) | Holds, both |
| C1 | H1e: passing shifted nulls picks maps closer to the true habitat | Reg. | one-sided p < 0.05 | median ρ 0.901 vs 0.606 (Maxent), 0.761 vs 0.639 (random forest) | Holds, both |
| C1 | **As a whole:** H1a, H1b and H1e for both learners | Reg. | all hold | H1a fails, also by the band fallback | **Not supported as registered** |
| C1 | E1c: the standard test on real models | Desc. | none | passes 35.7% (31.9–39.8); of those, 84.2% (82.2–85.9) not strong | Reported |
| C2 | H2a: strong maps, later finds in the top half | Reg. | lower bound > 0.50 | 0.915 (0.886–0.942) | Holds |
| C2 | H2b: strong − failed, top-half share | Reg. | lower bound > 0 | 0.131 (0.090–0.172) | Holds |
| C2 | H2c: strong maps beat collecting effort | Reg. | lower bound > 0.50 | 0.785 (0.763–0.806) | Holds |
| C2 | H6b: strong − distance map on the same places, top-half share | Reg. | lower bound > 0 | 0.044 (0.015–0.076); mean rank does not differ | Holds |
| C2 | H3a–c: the same on finds validated after the freeze (E3) | Reg. | as H2a, H2b, H6b | [PENDING read-out about 2026-12-16] | Pending |
| C3 | H9: DNA − record names, top-half share, paired | Reg. | interval excludes 0 | −0.003 (−0.011 to 0.005); 550 taxa | Does not hold; by the registered rule C3 rests on coverage |
| C3 | E16: taxa with only a provisional name | Desc. | none | 50.1% of modelled, 45.3% of strong | Reported |
| C4 | E12: the same family, refit | Desc. | none | 507 of 507 identical | Reported |
| C4 | E12: the other family, refit | Desc. | none | weighted to the release, grade changes 0.43% (0–1.24); κ 0.99 | Reported |
| Q1 | Strong maps as Vision's place signal | Reg. | top-1 better (one-sided McNemar, p < 0.05) and non-inferior at 300–1,500 km (2% margin) | 53.8% → 54.3%; p = 0.0001; mostly the declared selection falling back to photos alone; loses to the distance kernel by 0.2 points | Declared test passes; answer "yes, weakly" |

Sources: `2026-10-13-prereg-e1-null-calibration.md`,
`2026-10-13-plan-e1c-standard-test-real-models.md`,
`2026-10-13-prereg-e2-hindcast.md`, `2026-10-13-prereg-e6b-distance-baseline.md`,
`2026-10-21-prereg-e3-prospective.md`, `2026-10-13-plan-e9-record-names.md`,
`2026-10-28-e16-descriptives.md`, `2026-10-13-plan-e12-grade-stability.md`,
`2026-10-18-q1-atlas-arms.md`.
