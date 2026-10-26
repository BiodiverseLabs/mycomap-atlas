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

## Runs

Logged as the operations lane reports them; numbers only.

- **Dry run (2026-10-26, read-only, nothing written).**
  `plan-job --e9-pair --from-release=priv-20261018T171648Z-9e3ab153 --dry-run`
  on image bb6c799 (Atlas main with feat/e9-paired-hindcast and
  feat/e9-paired-score).
  - Records: 124,955 in the hindcast's pull, and 124,783 under their record
    names (172 not at species level).
  - Taxa: 978 paired, 129 only under DNA names, 110 only under record names.
  - Models: 1,904 on each side; 7,211 unchanged and not fitted.
  - 1,165 record-name models carry their DNA pair's measured block. The rest
    are mostly ensembles, which fit on a fixed 100 km block.
  - About 144 CPU-h, from the hindcast's own timings: at most about USD 10
    at the on-demand price.
  - The fits have Steve's go, confirmed with the operations lane at launch.
- **Fits (launched 2026-10-26 02:12 UTC).** `plan-job --e9-pair
  --from-release=priv-20261018T171648Z-9e3ab153 --shards=4` on image bf236cf
  (Atlas main, with the EC2 5xx retry fix).
  - DNA side: priv-20261026T021038Z-3ba43cf6. Record side:
    priv-20261026T021038Z-9c0ba509.
  - Both orchestrators started together on the same image, with the r7i
    pin (r7i.8xlarge, r7i.4xlarge) and MAX_HOURS 8.
  - Each finishes privately on one worker. They queue behind E1's full run
    on the vCPU quota.
  - Steve confirmed the launch directly with the operations lane.
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
- **2026-10-25, still before any fit or code: a decision rule, and the
  asymmetry stated (Paper Coordinator, after the redesign).**
  - **H9 (two-sided).** The 95% interval of the primary estimate (the
    paired DNA minus record-name difference in top-half share) excludes 0.
    - Above 0: C3 reads "DNA labels give maps that rank later finds
      better".
    - Including 0: "no detectable difference". C3 then narrows to coverage:
      the taxa only DNA can name, and the records whose label it changes.
    - Below 0: "record names do better", reported as such.
  - **The asymmetry, stated.** The primary truth is each find's DNA name. So
    the primary estimate asks which labelling better predicts the
    DNA-defined taxon's later finds. Where the names disagree, that favours
    the DNA side by construction.
  - **The check on it, a pre-specified secondary estimate.** The same paired
    difference with each side scored on its own labelling: a record-name
    map on the finds carrying that record name. It gets the same interval
    (10,000 resamples of taxa, seed 1). Both are reported side by side
    whatever they show. H9 is decided on the primary estimate only.
- **2026-10-25, still before any fit or code: two jobs launched together, not
  one (implementation; the comparison is unchanged).**
  - **Why.** A private job carries one pull, and its workers fit every task
    from it. The two labellings name the same records differently, so they
    need two pulls. Putting both in one job would mean changing the
    production shard runner.
  - **Instead, two private jobs, planned from one Atlas commit and launched
    together on one processor family (r7i):**
    - the DNA side: the E2 hindcast's changed taxa refitted through the
      existing hindcast refit (`atlas_plan_hindcast_refit`), with no records
      left out. Its records match the hindcast's, so each model reuses its
      recorded block;
    - the record side: a new hindcast record-names purpose, the hindcast
      cutoff applied and then each record named by its .org name. Each model
      reuses the block of the DNA model of the same name.
  - **What stays like-for-like:** both sides use the same records and the
    same cutoff, the same image, processor family, blocks and fit settings.
    Each side's background and effort come from the same sites. Everything
    above (H9, the secondary estimate, the reporting) is unchanged.
