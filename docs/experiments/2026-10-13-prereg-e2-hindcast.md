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

Run (finished 2026-10-18 22:23 UTC): private release
priv-20261018T171648Z-9e3ab153; 9,115 models planned, 8,606 fitted, 509
refused, 0 failed; 414 strong taxa; 110,615 trained record ids. In the
hindcast, *Sparassis spathulata* is a small-model ensemble at 15 sites, and
586958 is the only record in its 5 km site, so the leave-out refit takes it
to 14 sites, still within the small-model range. Cost: 289 CPU-h, about
USD 5.71 of compute (spot reclaims on all four shards, an on-demand
finish).

## Deviations

- **2026-10-18, before any scoring: first-validation dates colliding
  across sources.** Atlas's first-validation lookup matched records by
  observation number alone, so a record could take another source's date
  (fix: keyed on source and number, Atlas branch fix/first-green-by-source
  46556a9). A read-only rebuild from the live database, which reproduces
  the known frozen values, finds at most 65 records with a wrong date, of
  which 61 stay on the same side of the cutoff. At most **4 crossed it, all
  wrongly into training** (truly first validated after 2026-08-17): mycomap.org
  ids 590501 (*Amanita pantherinoides*), 586958 (*Sparassis spathulata*),
  586894 (*Fibroporia albicans*) and 598980 (*Pluteus* sp. 'plautus-PNW09',
  whose date is the pull day and may postdate the pull). None can be wrongly
  in the test set: the fix only moves dates later. **Handling, as
  pre-registered:** these records are excluded from the scored test finds
  and counted; each added one presence to one taxon's training, so the
  affected taxa are noted, and refitted only if a scored taxon with 3–19
  sites is among them (none refitted unless that holds).
  - **Exact check (operations lane, read-only, 2026-10-18)** against the
    frozen pull x73b85b36 and the hindcast's trained-id list and model
    table:
    - 590501, *Amanita pantherinoides*: in the pull with first_green_on
      2025-03-20 (taken from MyCoPortal record 355385); **in the trained
      ids**; hindcast 73 sites, Maxent, random forest and boosted trees all
      weak. → noted.
    - 586958, *Sparassis spathulata*: in the pull with first_green_on
      2026-02-12, before it was collected (taken from MyCoPortal record
      658533); **in the trained ids**; hindcast 15 sites, small-model
      ensemble only, weak. → the 3–19-site case: refitted without this
      record if the taxon has any scored test finds; otherwise noted. It
      has one (mycomap.org 593531, first validated 2026-08-25, an
      iNaturalist record whose own date the collision does not touch), so
      by the rule its hindcast model is refitted without 586958 before
      scoring. Steve's go: 2026-10-18 (to the paper coordinator). No
      supported command yet: the existing exclusion tool would rewrite the
      frozen pull, so a one-taxon leave-out refit is being added to the
      hindcast tooling (code, review, then a ~1-minute run). Scoring of all
      other taxa may proceed meanwhile; *Sparassis spathulata*'s one test
      find is scored only after the refit. Code: Atlas branch
      feat/hindcast-leave-out ba7578dc (plan-job --hindcast --taxa
      --algorithms=esm --leave-out=586958, from the hindcast release; a new
      private release identical to the hindcast except for this one model,
      marked refit_of, with both fits' grades and scores in its record; the
      hindcast release untouched; 1,149 tests pass). Awaiting Steve's SHA
      review, then the operations lane's merge and run. **Scoring the held
      find:** the E2 scorer is not wired to read a refit, so the one held
      find (593531) is scored against the refitted model's raster, read from
      the refit release's manifest, with the same metrics, and recorded with
      the E2 results. *(Superseded 2026-10-19 by the last entry below: the
      find is scored inside the single E2 run on the refit, with no separate
      raster read.)*
    - **Refit done** 2026-10-19 04:31 UTC: private release
      priv-20261019T042158Z-09936f85 (code merged as Atlas main 35aec02;
      1 record left out of 124,955; 1 model; about 0.02 CPU-h). Hindcast
      fit: ESM, weak, 15 presences, AUC 0.692, null p 0.50 (10 nulls).
      Refit: ESM, **weak**, 14 presences, AUC 0.666, null p 0.31 (16 nulls).
      The grade is unchanged. Trained ids 110,614 (the hindcast's minus
      one). Pooled Boyce for both fits is read from the model JSONs
      (field `boyce`); the refit's provenance block shows NA because of a
      models-table export bug that affects no scored output. [PENDING: both
      fits' pooled Boyce.]
  - **Exclusion list, as the scorer applies it:** the scorer takes test
    finds from the frozen pull's own first-validation dates, in which all
    four ids carry pre-cutoff dates (or are absent), so none can appear as
    a test find; the exclusion is a safeguard with nothing to match, and
    the run uses the scorer's allow-missing option and reports 0 matched.
    - 586894, *Fibroporia albicans*: in the pull with first_green_on
      2025-08-06, before collection; not in the trained ids (no hindcast
      model for the taxon). It still sat in the training pull's survey
      sites. → noted.
    - 598980: not in the frozen pull. → nothing to do.
  - Net: at most 4 of the hindcast's 124,955 training records were
    post-cutoff; two trained models. **Test-find exclusion list** for the
    scorer (any that appear as test finds under corrected dates are left
    out and counted): mycomap.org 590501, 586958, 586894, 598980. The
    hindcast run is kept, not rerun (the Atlas coordinator's
    recommendation); the only refit is *Sparassis spathulata*'s model,
    which is a small-model ensemble at 15 sites, so no Maxent or random
    forest model of it exists to exclude.
- **2026-10-19, before any scoring: one run in place of hold-then-rerun.**
  The entry above holds *Sparassis spathulata*'s test find until the refit
  and then scores it separately. Instead, E2 is scored in **one run**:
  - *Sparassis spathulata* is scored on the refit's ESM, private release
    priv-20261019T042158Z-09936f85 (the hindcast's model fitted again
    without 586958, with the same settings, seeds and shifted-null test).
    Every other taxon is scored on the hindcast, private release
    priv-20261018T171648Z-9e3ab153.
  - The 4 leaks (mycomap.org 590501, 586958, 586894, 598980) are excluded
    from the test finds. Because the frozen pull dates them before the
    cutoff or lacks them, the run passes `--allow-missing-excludes`. The
    first run omits that flag and is refused, and the refusal names the
    ids not found among the later finds. Those ids are recorded with the
    results.
  - The scored models and test finds are identical to hold-then-rerun. The
    only difference: *Sparassis spathulata*'s places enter the single
    bootstrap over taxa rather than a second run. Its held find (593531)
    is therefore scored like every other find, with no separate raster
    read.
  - Code: `study-score --refits`, Atlas branch study/score-exclusions
    444d41e (pending merge). A refit is used only if its manifest names
    this hindcast as the one it refits, and no taxon may come from two
    refits. The run records each refit's release and taxa in its
    settings. Command:
    `./atlas study-score --hindcast=priv-20261018T171648Z-9e3ab153
    --refits=priv-20261019T042158Z-09936f85
    --exclude=590501,586958,586894,598980 --allow-missing-excludes`.
- **2026-10-19, before any scoring: the 4 excludes matched no later find,
  and no later find is a twin of a leaked record.** The naming run refused
  with "--exclude names no later find for 590501, 586958, 586894, 598980",
  as the entry above anticipated. The reason: E2's split is made from the
  frozen pull (x73b85b36), which still carries the 4 records' old,
  cross-source first-validation dates. So in the split, as in the hindcast,
  they are training records, never test finds, and the training-records
  check (the split trains on exactly the hindcast's records) holds without
  them. The exclusions therefore remove nothing, and the run's
  `--allow-missing-excludes` is expected.
  The remaining risk runs the other way: a later find that is the same
  specimen as a leaked training record, under another source or number,
  would be scored against a model trained on its own twin. Checked
  read-only on mycomap.org (rebuild lane, 2026-10-19):
  - 586958, *Sparassis spathulata*: its later find, 593531, is scored on
    the leave-out refit, which never saw 586958 (entry above).
  - 590501, *Amanita pantherinoides* (MO 355385, collected 2019-01-12):
    three records with the same DNA name lie within 6 km: iNaturalist
    24744428 (mycomap.org 590522, collected 2019-05-05) and 45205980
    (590579, 2020-05-05), both 3.0 km away and validated in October 2026,
    so both are later finds; and MO 549653 (576965, 2024-05-21, 5.8 km).
    **None is a twin:** the collection dates differ by months to years. The
    two later finds are separate collections near the leaked record, which
    makes them 0-5 km "known" places. The effect is declared, not
    corrected: one taxon, with 73 sites and all three models weak.
  - 586894, *Fibroporia albicans*: no record with its DNA name within
    5 km; and with 1 site it has no model, so nothing is scored.
  - 598980, *Pluteus* sp. 'plautus-PNW09': no other record with its DNA
    name within 5 km. It shares its point with many records at one MO
    place centre, but none has that name.
  **Handling:** no further exclusion and no further refit. This entry
  records that the 4 excludes matched nothing, and why.

## Results

Run 2026-10-19 (`study-score`, one-shard EC2 study job
study-20261019T181851Z-35fc3d63, started 18:20:38 UTC, 2,861 s). Results
file: study/study-20261019T181851Z-35fc3d63/score-priv-20261018T171648Z-9e3ab153-20261019T182038Z.json.
Numbers only; read out by the rebuild lane.

**Settings.** Hindcast priv-20261018T171648Z-9e3ab153, from release
20261013T191324Z-fa1b4198, cutoff 2026-08-17, observed_after false, 10,000
bootstrap resamples of taxa, seed 1. Refit used: priv-20261019T042158Z-09936f85
(*Sparassis spathulata*). Excludes: 4 given, 4 not found among the later
finds, 0 known leaks (as recorded in Deviations, 2026-10-19). Kept apart:
undated 0, off-grid 0, observed-before 0, excluded 0, held 0.

**Places.** 7,509 places (taxon × 5 km cell) across 3,655 taxa; 0 off the grid.

**Primary hypotheses** (95% percentile intervals, bootstrap over taxa):

| | Estimate | 95% interval | Taxa | Holds |
|---|---|---|---|---|
| H2a: strong, top-half share | 0.9145 | [0.8856, 0.9419] | 214 | yes |
| H2b: strong − failed, top-half share | 0.1305 | [0.0898, 0.1719] | 735 | yes |
| H2c: strong, beats-effort share | 0.7854 | [0.7627, 0.8056] | 214 | yes |

C2: supported (H2a, H2b and H2c all hold).

**Secondary hypotheses, map tiers:**

| | Estimate | 95% interval | Taxa | Holds |
|---|---|---|---|---|
| H2d: moderate, top-half share | 0.8876 | [0.8684, 0.9058] | 660 | yes |
| H2e: moderate, beats-effort share | 0.7536 | [0.7396, 0.7674] | 660 | yes |
| H2f: indicative, top-half share | 0.8655 | [0.8537, 0.8767] | 1,666 | yes |
| moderate-z, top-half share | 0.8981 | [0.8774, 0.9174] | 515 | (reported) |
| moderate-z, beats-effort share | 0.7623 | [0.7477, 0.7770] | 515 | (reported) |

**By grade** (per-model rows; "places" = ranked places; all places / new
places > 5 km / known places):

| Grade | Rows | Taxa | Ranked places | Top half | Top tenth | Mean rank | Beats effort | Boyce |
|---|---|---|---|---|---|---|---|---|
| strong, all | 736 | 214 | 486 | 0.9145 | 0.4957 | 0.8186 | 0.7854 | 0.968 |
| strong, new | 506 | 183 | 334 | 0.8783 | 0.4000 | 0.7730 | 0.7369 | 0.971 |
| strong, known | 230 | 89 | 152 | 0.9870 | 0.6870 | 0.9099 | 0.8823 | 0.843 |
| weak, all | 11,690 | 2,082 | 5,094 | 0.8696 | 0.4566 | 0.7894 | 0.7166 | 1.000 |
| weak, new | 8,650 | 1,882 | 3,788 | 0.8394 | 0.3713 | 0.7520 | 0.6742 | 0.999 |
| weak, known | 3,040 | 773 | 1,306 | 0.9509 | 0.6858 | 0.8900 | 0.8305 | 0.999 |
| failed, all | 1,177 | 528 | 904 | 0.7840 | 0.3433 | 0.7178 | 0.6716 | 0.995 |
| failed, new | 939 | 485 | 695 | 0.7409 | 0.2666 | 0.6774 | 0.6266 | 0.991 |
| failed, known | 238 | 135 | 209 | 0.9286 | 0.6008 | 0.8534 | 0.8227 | 0.976 |
| untested, all | 23 | 2 | 23 | not tested (< 30 places) | | | | |

Rows outside the area of applicability: strong 1, weak 16, failed 1.
Beyond reach (500 km): strong 45, weak 477, failed 139.

**By tier**, all places: moderate 2,237 rows, 660 taxa, 1,519 places, top
half 0.8876, top tenth 0.5120, beats effort 0.7536, Boyce 0.999; indicative
9,448 rows, 1,666 taxa, 4,335 places, 0.8655, 0.4437, 0.7080, 1.000; failed
(by tier) 1,182 rows, 531 taxa, 909 places, 0.7841, 0.3426, 0.6714, 0.996;
moderate-z 1,641 rows, 515 taxa, 1,159 places, 0.8981, 0.5156, 0.7623, 0.998.
New places only: moderate 0.8534 / 0.7099 (top half / beats effort);
indicative 0.8362 / 0.6662; moderate-z 0.8636 / 0.7228.

**Combined maps**, all places: 523 rows, 214 taxa, 486 places, top half
0.9218, top tenth 0.5185, beats effort 0.7868, Boyce 0.981; new places
0.8892 / 0.7392; known places 0.9934 / 0.8915.
