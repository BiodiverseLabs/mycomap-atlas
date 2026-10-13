# Appendix S1, Section S9: the pre-declared question on MycoMap Vision's place signal (draft)

**Coverage (measured 2026-10-13 on the frozen release 20261013T191324Z-fa1b4198,
470 taxa with a strong map):** the true taxon has a strong map for 8.6% of
Vision's v1 validation records (1,152 of 13,354) and 8.9% of its training
records, against 17.8% estimated when the test was designed (before the
shift-null rebuild). The overall effect can therefore come from about one
validation record in twelve; the depth-matched tables of mapped and
unmapped records carry the reading. Out-of-area records for the projection
test (500 km or more from any training record) are fewer still.

*Moved from the main text on 2026-10-13 (lean main text); edited only for the move.*

MycoMap Vision identifies fungi from photos by nearest reference images and
adds a place term. Its current place term is a distance kernel over DNA
records, which ranks down true species found far from known records. The
Atlas arms replace that kernel with habitat. The design was fixed on
2026-10-12, before any result, and is public in the Vision repository
(`docs/atlas-environment.md`, file version b78609d). The analysis plan was
approved in commit 5c9a4b6 and is unchanged since; b78609d only added a
later section proposing the new-find tracker, not an edit to the analysis.

- **Data.** Vision dataset release v1: training records first validated on or
  before 2026-08-17 (155,781 records), validation records after it (13,354).
  Atlas is refitted on records first validated on or before the same date
  (the hindcast release, E2), so no validation record trained a map. The
  cutoff is on the first-validation date, not the observation date.
- **Confirmation.** Settings are chosen on validation-set cross-validation
  (observer folds); the direction is then checked once on v1-test, a census
  of North American records first validated after 2026-10-12 13:17 UTC
  (≥ 3,000 records; frozen ~30 October 2026). Which Atlas release each step
  may use: validation-set results use the hindcast release only (any later
  pull contains the validation records); the v1-test check may use the
  hindcast release or the October 2026 rebuild release (pull 2026-10-12
  05:10 UTC, before v1-test opened); no nightly release pulled after
  2026-10-12 13:17 UTC is used for either.
- **Primary arm (P2c).** Each strong map's continent-wide projection, ranked
  on its in-area scale, enters as log f(rank) × trust, replacing the distance
  kernel for mapped taxa; trust = map strength × agreement among the taxon's
  strong models × applicability (cut or graded outside the AOA).
  Unmapped taxa keep the served kernel.
- **Tests.** Intersection-union: species top-1 better than no place term
  (one-sided McNemar, p < 0.05) **and** non-inferior in the 300–1,500 km band
  at a 2% margin (paired bootstrap, 10,000 resamples). Secondary arms (P2c
  without trust; in-area only; the accessible area as a range; combined with
  the kernel; a low-capacity environment head on Atlas layers, P4, with a
  coordinates-only control, P6) are Holm-adjusted and exploratory. Effects are
  reported within reference-depth bands so map quality is not confused with
  commonness.
- **Projection validity (H, E22).** For validation records of mapped taxa
  500 km or more from any training DNA record, the Boyce index of the true
  species' projected rank, and the share in cells ranked ≥ 50 with a binomial
  CI, inside and outside the AOA. This is also an independent test of the
  full-extent maps (C2).
