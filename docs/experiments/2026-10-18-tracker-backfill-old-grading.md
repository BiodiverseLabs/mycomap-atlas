# New-find tracker backfill under the old grading (background for E3)

- **Question.** How did the releases live before the rebuild rank the
  records first validated after them? Background for E3 and for C1's point
  about scattered nulls; not the pre-registered shift-scheme test.
- **Reproducibility.** exploratory-pre-freeze (old grading: scattered nulls).
- **Data.** Releases of 2026-10-02, 10-06 and 10-07 (scheme "skill",
  scattered nulls); finds first validated 2026-10-03 to 10-12, each scored on
  the release live when its day began; a place is one taxon in one 5 km cell.
- **Code.** The new-find tracker's backfill (Atlas tracker code, run by the
  operations lane), verified by the Atlas coordinator 2026-10-18.
- **Result.**
  - 1,464 finds: 1,201 scored, 175 of taxa with no map, 88 under a name the
    release did not know.
  - New sites (more than 5 km from the taxon's known records; 817 ranked
    places): 82% in the top half (chance 50%), 34% in the top tenth (chance
    10%), beats-effort 0.655.
  - 100–500 km from any known record (319 ranked): 69% top half,
    beats-effort 0.61.
  - Known sites: 98% top half, beats-effort 0.85 (inflated, as expected:
    the map was fitted there).
  - Old-test passed vs not passed barely separate on new sites
    (beats-effort 0.672 vs 0.625; 100–500 km 0.63 vs 0.59), consistent with
    C1: scattered nulls tell little apart.
  - Finds 500 km or more from any known record are beyond the maps' reach
    by construction (the accessible area is 500 km); that band measures
    range growth, or reach drawn too narrowly, not map skill.
- **Cost.** Read-only scoring on the Atlas server; negligible.
- **Decision.** None. The shift-graded comparison comes from the hindcast
  (E2) and from tracking once the nightly runs resume (E3).
