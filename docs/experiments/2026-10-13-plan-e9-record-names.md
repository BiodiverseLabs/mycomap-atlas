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
  private release, through `plan-job --record-names --from-release=<frozen
  release>` (feat/hindcast ba03e73). The experiments lane builds the
  comparison only.
- **Counted, not compared:** taxa with no counterpart (names only in one
  labelling, including provisional codes that exist only as sequence
  names).

## Outputs

Per paired taxon: map Spearman correlation over its accessible-area cells
and Schoener's D against the frozen release; grade under each labelling;
records gained and lost. Overall: records whose label differs (species,
genus) by source; taxa split, merged, gained and lost.

## Deviations

- **2026-10-25, before launch (reading only; the design is unchanged): the
  floor any comparison with the frozen release carries.** The record-names
  job (Atlas main c56d2dc, from fa1b4198) refits only taxa whose record set
  changes. Their records differ, so none reuses a released block; each
  measures its own, on Intel (r7i, production's pin). The frozen models were
  fitted on a mix of Intel and AMD machines, mostly from the 2026-10-12 pull
  before the 76 drop-list rows were removed, while the job uses the
  release's pull. Part of any map difference therefore comes from the
  machine and the pull, not the labelling. E12 measured that part for
  unchanged records refitted on another family: 1.55% of models differ
  [0.37, 3.03], and 0.43% change grade [0, 1.24]. That floor is reported
  beside E9's correlations and grade changes.
