# Plan: sequence names vs record names (paper E9)

- **Status.** Planned 2026-10-13, before code or run. Descriptive; serves C3.
- **Reproducibility.** frozen.

## Design

- **Records.** Exactly the records of the frozen pull (records with no
  approved sequence name stay out), relabelled with the record's own name
  (`observations.scientific_name`) instead of the approved sequence name.
  Name merging (spelling, author, rank-word variants) as in production.
- **Refit.** Every taxon whose record set under record names differs from
  its set under sequence names: full graded fits, every learner, into a
  private release.
- **Counted, not compared:** taxa with no counterpart (names only in one
  labelling, including provisional codes that exist only as sequence
  names).

## Outputs

Per paired taxon: map Spearman correlation over its accessible-area cells
and Schoener's D against the frozen release; grade under each labelling;
records gained and lost. Overall: records whose label differs (species,
genus) by source; taxa split, merged, gained and lost.

## Deviations

None yet.
