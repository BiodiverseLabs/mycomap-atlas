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
- **2026-10-25, before any fit or code: redesigned as a paired hindcast of
  both labellings, scored on later finds (the independent review,
  approved by Steve).** This replaces the design above and the note just
  before it.
  - **Why.** As planned, E9 compares a record-name refit with frozen models
    fitted on other machines from another pull, and measures only map
    agreement, which mostly says that different records give different
    maps. C3 needs a test of skill on records the models never saw.
  - **Taxa.** Those whose record set differs between DNA names and record
    names on the hindcast's pull (cutoff 2026-08-17, the E2 hindcast's).
    Taxa whose records do not change are identical under both labellings
    and are not refitted.
  - **Fits.** One private job fits each such taxon twice, under its DNA
    name and under its record name: same pull, image, processor family
    (r7i) and fit settings. The record-name model reuses its DNA pair's
    spatial block, so no block differs by machine (E12). Full graded fits,
    every learner, as production.
  - **Scoring.** Both sides on E2's later finds, with E2's exclusions and
    refits as in E2's final command.
    - **Primary truth: each find's DNA name.** A record-name map is scored
      on the finds whose DNA name is its taxon.
    - **Secondary:** each side scored on its own labelling.
  - **Primary estimate** (descriptive, as E2's metrics): the paired
    difference, DNA minus record name, in top-half share of later finds.
    Taken over taxa present under both labellings, with a 95% interval from
    10,000 bootstrap resamples of taxa (seed 1).
  - **Also reported:** Boyce, beats-effort, new and known places and
    distance bands, by site band; grade under each labelling; map Spearman
    and Schoener's D for each pair; taxa only one labelling has, counted;
    records whose label differs, by source.
  - **Reproducibility.** frozen (the hindcast's pull; Atlas main at the
    commit that runs it, recorded with the run).
  - **Cost.** About 550–650 CPU-h for both sides, about 20–25 instance-h
    of r7i.8xlarge: at most about USD 55 at the on-demand price, likely
    USD 20–30 on spot. Scoring under USD 1. The fit run has its own launch
    go.
