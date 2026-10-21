# Pre-registration: prospective tracking on the frozen release (paper E3)

- **Status.** **REGISTERED 2026-10-21**, before any outcome look: no test
  find has been counted or scored. Drafted by the paper lane, reviewed by
  the method lane (edits applied), approved by Steve with the read-out date
  2026-12-15 (relayed by the Atlas coordinator, 2026-10-21). Changes after
  registration go under "Deviations", dated, before the read-out.
- **Question.** Does a map's grade predict how it ranks records validated
  after the release was made, under the same rules as the hindcast (E2) and
  the distance baseline (E6b)? Serves C2. E2 tested the grade on a refit
  from older records; E3 tests the published maps themselves.
- **Reproducibility.** frozen (the published release; no refit).

## Why one read-out, and not daily scoring

The frozen release 20261013T191324Z-fa1b4198 has been the live release
since 2026-10-13 23:03 UTC, and with the nightly off no other release has
replaced it. Every record first validated after its pull
(occurrences-20261012T051017Z-x73b85b36) is therefore unseen by the maps,
whether it is scored the day it turns green or at a read-out months later.
So no prospective find is lost while the nightly is off. The test needs
this file registered before anyone looks, and one scoring run at the
read-out date. Every find first validated from 2026-10-14 is scored on
fa1b4198 whatever release is live by then, since any such find is unseen
by it; the nightly can resume without ending E3.

The old-grading backfill (`2026-10-18-tracker-backfill-old-grading.md`)
scored finds up to 2026-10-12 on older releases only; no find has been
scored on fa1b4198.

## Data

- **Maps.** Release fa1b4198, as published: grades, area of applicability,
  500 km reach.
- **Test finds.** Records eligible under the read-out pull's rules at a named
  commit, read from a fresh pull at the read-out, whose first validation date
  (`first_green_on`) is on or after **2026-10-14** (the first full day the
  release was live) and on or before the read-out date, and whose record
  id is not in the frozen pull. Finds first validated on 2026-10-12 or
  2026-10-13 (after the pull, before the release was live) are reported
  apart.
  - **Pull rules at the read-out.** As on Atlas main 0bdb934: first
    validation keyed by source (8edc15d); name changes (ee9f3fe); sequence
    flags (9379a64 contaminant, 06cf6ea wrong observation or specimen,
    31709fa ONT Trashcan reads), under which a flagged sequence never names
    a record, so the record keeps its other clean sequences' name, or its
    record name if none is left; the drop list (643b444); and the Mushroom
    Observer rules as there (the location box, and records deleted at the
    source with no cached answer dropped). The frozen 2026-10-12 pull
    predates the three sequence flags. The read-out applies the operations
    box's drop list (copied in if the read-out pull runs in its own data
    directory), and records its hash and removed count. The frozen pull's
    exclusion list of 76 erroneous records still applies. The read-out runs
    at a later commit that adds only the study-score mode, named at the
    read-out; any other change to the pull rules before then is a dated
    deviation. Each rule's count of removed or renamed finds is reported.
  - **Leak paths and their guards.** A record in the frozen pull: excluded
    by its id. A first-validation date moved across the cutoff by a
    cross-source collision: prevented by 8edc15d, and caught by the id rule
    in any case. A record green before the pull but missing from it:
    excluded by the date rule. A cross-post twin of a training record (the
    same find posted to two sources): cannot be detected for these records
    (the twin lists come from MycoMap Vision's v1 photo hashes, which hold
    no record validated after 2026-10-14), so it is a stated limitation; a
    near twin falls among known places, and E2 did not exclude twins
    either.
- **Unit.** A place: one taxon in one 5 km cell, as E2.
- **Matching.** A find counts for a taxon by the name the frozen release
  uses for it. Renames and respellings logged after the find's first
  validation (mycomap.org's dated, record-level name-change log, read by
  every pull into `occurrences/name-changes.json`, Atlas ee9f3fe) are
  mapped back to the release's name. Merges and splits, which have no
  unique inverse, and names that no log entry maps, are kept apart and
  counted. A find whose identity has no model in the release, including
  one renamed or re-identified into such a taxon, is kept apart and
  counted as "no model", by kind of change.
- **Kept apart, with counts:** as E2 (taxa with no model, unknown names,
  beyond reach, outside the area of applicability); merges, splits and
  unmapped names; and finds whose record id is in the frozen pull.

- **Privacy.** Scoring runs in Atlas's private compute, where exact
  coordinates stay. Anything published from E3 (the registry entry, the
  paper, supplements, the site) gives aggregate numbers only: no record
  ids, coordinates or cell ids, and no per-find listing. Records whose
  location the source hides, obscures or may hide are scored like any
  other but are never listed or drawn, as in every published layer.

## Scores and baselines

As E2: rank within each model's area of applicability, top half, top
tenth, mean rank, Boyce (reported, not tested), and beats-effort against
the cells of other taxa's finds in the same period. The distance kernel is
built as in E6b, from each taxon's training survey sites in the frozen
pull, with the bandwidth chosen on its production folds and re-ranked over
each model's area of applicability, so that every model place has a kernel
place.

## Hypotheses (bootstrap over taxa, 10,000 resamples, seed 1; 95% percentile intervals)

- **H3a.** Strong maps: top-half share, lower bound > 0.5.
- **H3b.** Strong minus failed: top-half share, lower bound > 0.
- **H3c.** Strong minus the distance kernel on the same places: top-half
  share, lower bound > 0. (In E6b this was the registered test; here it is
  registered for the published maps.)
- **Reported, not tested:** beats-effort, top tenth and mean rank by grade;
  weak, moderate and indicative against the kernel; new (> 5 km) and known
  places; distance bands 5–25, 25–100, 100–500 km; inside and outside the
  area of applicability; combined maps.
- **Too few finds.** A grade with fewer than 30 ranked places is reported
  as untested (E2's rule). If strong maps have fewer than 30 ranked places
  at the read-out, H3a–H3c are reported as untested and descriptive only.

## Read-out

- **Date.** **2026-12-15** (Steve): test finds are those first validated
  from 2026-10-14 to 2026-12-15 inclusive, and the scoring run follows
  (about 2026-12-16). One read-out; no interim look at outcomes. The only
  interim look allowed is `--counts-only`: the count of finds by grade (no
  ranks), to judge whether H3a–H3c will have 30 places.
- **Recorded at the read-out:** the read-out pull's commit and id, and the
  name-change log's cursor (the last change it holds).
- **What the result does to C2.** H3a–H3c hold: the published maps behave
  as the hindcast's did, and C2 cites both. H3c fails with H3a and H3b
  holding: C2 states that the published strong maps beat chance and failed
  maps on later finds, but not distance, and the Discussion weighs this
  against E6b. H3a or H3b fails: C2 is narrowed to the hindcast and the
  difference is discussed.

## Expected sample (from registered data only)

No post-pull find has been counted for this estimate. E2's test window
(first validated 2026-08-18 to the pull on 2026-10-12, about 1.8 months)
gave 8,280 records and 7,509 places, of which strong maps ranked 486
places of 214 taxa: about 4,000 places and 260 strong-map places a month.
The old-grading backfill gave 1,464 finds in the 10 days to 2026-10-12, a
similar pace. The frozen release has more strong taxa (470) than the
hindcast (414). So about two months of finds (to mid-December) should give
roughly 500 strong-map places, the size at which H6b's interval cleared
zero in E6b (486 places, lower bound 0.015). One month would likely leave
H3c's interval spanning zero for an effect of E6b's size. [Estimate only;
the pace of validation varies.]

## Cost

- **Code.** A small study-score mode, built and reviewed before the
  read-out (about 1–2 days with tests, after Steve's approval): a published
  release, a local fresh pull, first validation on or after a date, record
  id not in the release's pull, and a counts-only switch. Today study-score
  accepts only a private hindcast.
- **Kernels.** study-distance on fa1b4198, about E6b's size: 3 × 8xlarge
  for about 1–1.5 h, about USD 3–5 on spot. Run on r7i, then refit any
  block mismatch on r7a as in E6b (fa1b4198 has no per-model machine
  record). The kernels depend only on the frozen pull, so they are built
  before the read-out.
- **Read-out.** A fresh pull made on the operations box (in a separate
  data directory, so the live site keeps its pull) and staged to a private
  store prefix, then scored on one small EC2 worker (about USD 0.30), since
  E2's scoring did not fit the box's memory cap.

## Implementation (not a design change)

Recorded 2026-10-21, after registration and before any outcome look, from
the method lane's read-out mode (Atlas study/e3-readout 44d007a, one
commit on 674c5e4, built against this file at 77a2520, awaiting Steve's
review). 44d007a adds the pull's naming audit to the results file (how the
pull named its records, including the sequences its flags set aside),
beside the drop list's and the Mushroom Observer counts. H3a, H3b and H3c
are wired as E2's H2a and H2b and E6b's H6b on these finds, unchanged;
`--counts-only` writes no rank, share or score, and a test checks that.

- **Record id rule.** "Not in the frozen pull" is checked by source key
  and by mycomap.org row id, and a find matching either is excluded: a
  stricter reading that also catches a record re-keyed between pulls.
- **Names.** A find counts under its name on its first-validation day.
  Renames and respellings logged after that day are undone, a chain back
  to the first change's old name. Merges and splits are kept apart.
- **Kept-apart categories**, as the results file names them:
  in_release_pull, undated, green_before_pull, before_live (the finds of
  2026-10-12 and 10-13), after_until, name_merge, name_split,
  name_same_day, off_grid; then the scorer's own classes (no model,
  unknown name, outside the area of applicability, beyond reach). The
  counts of names undone, by rename and respelling, are reported.

## Deviations

- **2026-10-21, after registration and before any outcome look: same-day
  name changes kept apart.** A rename or respelling logged on the find's
  first-validation day itself is kept apart (name_same_day), because the
  log's time cannot say whether the change came before or after the
  validation. This adds one kept-apart class; the hypotheses, the test
  set's dates and the scores are unchanged.
- **2026-10-21, before any outcome look: rule counts at the pull level.**
  The registered text says each rule's count of removed or renamed finds
  is reported. The pull does not trace these among test finds alone (a
  removed row is not in it, and a record renamed by a sequence flag
  carries only its final name), so each rule's count is reported as the
  pull records it, over all its records: the drop list's removed rows,
  the Mushroom Observer rules' counts, and the naming audit. The test set,
  hypotheses and scores are unchanged.
