# Pre-registration: prospective tracking on the frozen release (paper E3)

- **Status.** DRAFT, 2026-10-21, by the paper lane, for review by the
  method lane and Steve's approval. Not registered until Steve approves
  it and it is committed with that note. Nobody scores any test find before
  then. Changes after registration go under "Deviations", dated, before
  the read-out.
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
read-out date. If a new release goes live before the read-out, each find is
scored on the release live when its validation day began (the tracker's
rule), and finds scored on another release are reported apart.

The old-grading backfill (`2026-10-18-tracker-backfill-old-grading.md`)
scored finds up to 2026-10-12 on older releases only; no find has been
scored on fa1b4198.

## Data

- **Maps.** Release fa1b4198, as published: grades, area of applicability,
  500 km reach.
- **Test finds.** Records eligible under the release's own pull rules, read
  from a fresh pull at the read-out, whose first validation date
  (`first_green_on`) is on or after **2026-10-14** (the first full day the
  release was live) and on or before the read-out date, and whose record
  id is not in the frozen pull. Finds first validated on 2026-10-12 or
  2026-10-13 (after the pull, before the release was live) are reported
  apart.
  - **Pull rules at the read-out.** The frozen pull's own eligibility rules
    and exclusions (the rules that made x73b85b36, including its exclusion
    list of 76 erroneous records), plus every exclusion added since, applied
    to test finds: Mushroom Observer records deleted at the source with no
    cached answer; sequences flagged wrong (wrong specimen) or contaminant;
    and the current drop list. The corrected first-validation lookup (Atlas
    8edc15d, first-green dates keyed by source) is used, so the
    cross-source date collision found in E2 cannot move a record into the
    test set. The Atlas commit that makes the read-out pull is named here
    at registration and not changed after: [PENDING: SHA, from the method
    lane]. Each rule's count of removed finds is reported.
- **Unit.** A place: one taxon in one 5 km cell, as E2.
- **Matching.** A find counts for a taxon by the name the frozen release
  uses for it. A renaming of the same taxon since the pull (a new label for
  the same sequence cluster, from the name-change log) is mapped back to
  the release's name. A re-identification (the record now belongs to
  another taxon) uses the record's current identity. A find whose current
  identity has no model in the release, including one renamed or
  re-identified into such a taxon, is kept apart and counted as "no
  model", by kind of change. Finds under a name the release does not know
  and that no log entry maps are kept apart and counted.
- **Kept apart, with counts:** as E2 (taxa with no model, unknown names,
  beyond reach, outside the area of applicability); finds that are
  cross-post twins of a training record (the twin lists of S2.4b); and
  finds whose record id or twin is in the frozen pull.

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

- **Date.** [PENDING: Steve. Proposed 2026-12-15, which leaves time to
  write it up for a January submission.] One read-out; no interim look at
  outcomes. Before the read-out, only the count of finds by grade may be
  read (no ranks), to judge whether H3a–H3c will have 30 places.
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

A fresh pull and one scoring run on the operations box; one study-distance
run for the kernels on the frozen pull (EC2, about the size of E6b's). The
kernels depend only on the frozen pull, so they are built before the
read-out and the read-out itself is one scoring run.
[PENDING: estimate from E6b's ledger row.]

## Deviations

None yet.
