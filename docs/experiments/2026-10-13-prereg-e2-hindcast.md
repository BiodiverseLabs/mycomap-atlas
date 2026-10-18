# Pre-registration: the hindcast (paper E2)

- **Status.** Pre-registered 2026-10-13, before the job is planned or run.
  Any change after launch is listed under "Deviations" below with its date
  and reason; results are reported against this file as committed.
- **Question.** Does a map's grade (strong, weak, failed) predict how it
  ranks records it never saw? Serves paper claim C2.
- **Reproducibility.** frozen (cutoff-filtered pull of the October 2026
  rebuild).

## Data

- **Training.** The October 2026 rebuild's pull, keeping only records whose
  first validation date (`first_green_on`, the earliest date a validation
  slot turned "yes") is on or before **2026-08-17**. The cutoff is on the
  first-validation date, never the observation date. Records without a
  first-validation date are dated from another source or excluded; the
  count of each is reported.
- **Fit.** The full production plan on that pull: every learner, nested
  spatial CV, shift nulls ×99 with early stopping at 5, grades, AOA,
  full-extent projection for strong models, trust signals. A private release
  that is never promoted. The same job serves MycoMap Vision's training run.
- **Test finds.** Records in the same pull whose first validation date is
  after 2026-08-17. Secondary set: of those, the records also *observed*
  after 2026-08-17 (new collections, not a validated backlog).
- **Unit.** A place: one taxon in one 5 km cell. Several finds of a taxon in
  a cell count once.
- **Kept apart, with counts:** finds of taxa with no model in the hindcast
  release; finds under a name the release does not know; finds beyond a
  model's 500 km reach; finds outside its area of applicability (in-area
  scores are primary; these are reported, not ranked).

## Scores

For each test place and each model of its taxon in the hindcast release:

- **rank**: the place's cell rank on that model's drawn map, 0–1 within the
  model's area of applicability (chance: half the places in the top half);
- **top half**, **top tenth**: shares of places with rank ≥ 0.5 and ≥ 0.9;
- **Boyce**: continuous Boyce index of the places against the map, pooled
  per grade;
- **beats effort**: the place's rank compared with the ranks, on the same
  map, of the cells where every other taxon's test finds landed; 50% is no
  better than knowing where people collect.

Each model is scored under its own grade. The map a visitor sees (the
combined map with two or more strong models, else the best strong map) is
scored too, for E15.

## Hypotheses and criteria

Intervals are 95% percentile intervals from 10,000 bootstrap resamples of
**taxa** (places are clustered within taxa). Grades with fewer than 30 ranked
places are reported, not tested.

- **H2a.** Strong models place test finds in the top half more often than
  chance: lower bound of the top-half share > 0.50.
- **H2b.** Strong models do better than failed ones: lower bound of
  (top-half share, strong − failed) > 0.
- **H2c.** Strong models beat collecting effort: lower bound of the
  beats-effort share for strong models > 0.50.

**C2 is supported** if H2a, H2b and H2c all hold. This is an
intersection-union test, so no multiplicity correction is applied within it.
If any one fails, C2 is reported as not supported, with the numbers.

## Secondary (reported, not decisive)

- Strong vs weak; weak vs failed; Boyce by grade; top tenth by grade.
- New places (> 5 km from every pre-cutoff record of the taxon) vs known
  places; distance bands 0–5, 5–25, 25–100, 100–500 km.
- Inside vs outside the area of applicability; beyond reach; and for strong
  models, the full-extent rank of places beyond 500 km.
- By learner (Maxent, RF, boosted trees, ESM) and by site band (3–4, 5–19,
  20–49, 50+).
- Combined map vs its member models (E15).
- The observed-after-cutoff subset.
- Grade agreement between the hindcast release and the October 2026 rebuild
  for taxa in both.

## Secondary hypotheses: map tiers (added 2026-10-13, before any run)

For each tier in `2026-10-13-plan-map-tiers.md` (moderate, moderate-z,
indicative), scored with the same metrics and intervals as above:

- **H2d.** Moderate maps place test finds in the top half more often than
  chance (lower bound > 0.50).
- **H2e.** Moderate maps beat collecting effort (beats-effort lower bound >
  0.50).
- **H2f.** Indicative maps place test finds in the top half more often than
  chance (lower bound > 0.50).

Also reported: the same for moderate-z; each tier against the
distance-only baseline (E6b) on the same places. These do not change H2a–c
or what supports C2; they feed Steve's choice of tiers, against the
thresholds stated in the tiers plan.

## Fairness limits (to state in the paper)

The hindcast reads today's validation state, names and coordinates for
pre-cutoff records. Design choices (layers, tuning grid, null design) were
made on data that include post-cutoff records. The rebuild lane is listing
these items; they go into the Discussion's limitations.

## Implementation (not a design change)

Code: Atlas feat/hindcast ba03e73, awaiting Steve's review.
`plan-job --hindcast --from-release=20261013T191324Z-fa1b4198 --validated-through=2026-08-17`
(the frozen release),
then `run-job-ec2` and `finish-private-release`. Checked against this file
on 2026-10-13: the filter keeps first_green_on ≤ cutoff and never uses the
observation date; undated records are left out and counted; the plan and
the finish both refuse a job that kept any post-cutoff record; every taxon
is planned afresh with tuning and shift nulls (99, stop at 5), so grades
and map strengths are the job's own; survey sites, effort, background and
reach are rebuilt from the filtered pull; outputs go only to private store
prefixes. Scoring (`score-hindcast`) uses the experiments lane's E2 scoring
code.

Data (2026-10-13, before any run; not a design change): the hindcast is
planned from the cleaned release, so its pull (x73b85b36) leaves out all 76
removed records (the 129-id exclusion list, Atlas commit 643b444) in
training and in the test finds alike. Its summary records the list's
SHA-256.

Dry run (2026-10-18, before launch; not a design change): from the frozen
release, the cutoff keeps 124,955 of 133,235 records; 0 have no first
validation date. The Vision v1 cutoff of 2026-08-17 is confirmed unchanged
after Vision's curation pause (its fixes go to a later v2).

Run (2026-10-18): private release priv-20261018T171648Z-9e3ab153, 414
strong taxa. Open before scoring: Q1's run found a cross-source id collision
in Atlas's first-validation lookup (two Vision validation records left out
there). [CHECK with the rebuild lane: whether the collision put any record
on the wrong side of the cutoff in this hindcast's training set or test
finds; if so, those records are excluded from scoring and counted, as a
deviation recorded here before scoring.]

## Deviations

None yet.
