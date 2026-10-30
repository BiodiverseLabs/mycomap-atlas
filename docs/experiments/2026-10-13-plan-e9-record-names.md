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
  - **DNA side:** every shard reported by 07:58 UTC. Its private finish
    started at 09:36, and the job ended without error.
  - **Record side:** the job reached its 8 h limit at 10:12 UTC with shard 4
    unreported, 128 of that shard's models already saved. With Steve's
    direct OK, the same job was run again at 18:27 UTC on the current image.
    Only shard 4 was relaunched, on-demand on r7i.4xlarge, resuming from
    the saved models, then its private finish, on-demand.
  - **Fitted (finished 2026-10-26).** Each side planned 1,904 models.

    | Side | Release | Fitted | Refused | Failed | Finished (UTC) | CPU-h | Est. USD |
    |---|---|---|---|---|---|---|---|
    | DNA | priv-20261026T021038Z-3ba43cf6 | 1,852 | 52 | 0 | 09:59 | 102.2 | 4.36 |
    | record | priv-20261026T021038Z-9c0ba509 | 1,860 | 44 | 0 | 19:19 | 89.3 | 2.40 |

    Strong models by learner (esm / maxnet / rf / xgboost): DNA 43 / 24 /
    16 / 1; record 63 / 22 / 17 / 2.
- **Scoring (2026-10-27).** study-20261027T175751Z-26b2c068, image bf236cf
  (Atlas feat/e9-paired-score), on 1 × r7i.xlarge on-demand (Intel Xeon
  Platinum 8488C), 17:59:42 to 19:58:31 UTC.
  - Command: `study-score --hindcast=priv-20261018T171648Z-9e3ab153
    --refits=priv-20261019T042158Z-09936f85
    --exclude=590501,586958,586894,598980 --allow-missing-excludes
    --e9=priv-20261026T021038Z-3ba43cf6,priv-20261026T021038Z-9c0ba509`,
    the DNA side first.
  - E2's registered H2a–c came out unchanged (0.9145, 0.1305, 0.7854).

## Result

**H9 does not hold: no detectable difference.** The primary estimate, the
paired DNA-name minus record-name difference in top-half share of later
finds (truth: each find's DNA name), is **−0.0027 [−0.0106, 0.0050]**.
That is over 550 taxa and 1,176 models present under both labellings, with
10,000 resamples of taxa (0 dropped). Under the decision rule (43de9a5),
C3 narrows to coverage: the taxa only DNA can name, and the records whose
label it changes.

**The pre-specified secondary** (the record side scored on its own
labelling): **−0.0038 [−0.0120, 0.0041]**, over 547 taxa and 1,173 models.
It also shows no difference. The primary truth was expected to favour the
DNA side where names disagree (43de9a5), and it does not.

Reported (primary pairing; top half / top tenth / mean rank / beats effort
/ Boyce):

| Side | Places | All | New places | Known places |
|---|---|---|---|---|
| DNA | 1,676 | 0.871 / 0.479 / 0.797 / 0.705 / 0.999 | 0.838 / 0.386 / 0.755 / 0.654 | 0.952 / 0.704 / 0.898 / 0.828 |
| record | 1,670 | 0.874 / 0.479 / 0.796 / 0.703 / 0.995 | 0.841 / 0.383 / 0.755 / 0.652 | 0.952 / 0.710 / 0.896 / 0.824 |

By grade, on the paired models (taxa, places, top half, beats effort):

| Grade | DNA | Record |
|---|---|---|
| strong | 36 taxa, 70 places, 0.891, 0.727 | 41 taxa, 92 places, 0.887, 0.774 |
| weak | 489 taxa, 1,584 places, 0.878, 0.709 | 477 taxa, 1,556 places, 0.881, 0.705 |
| failed | 87 taxa, 188 places, 0.755, 0.637 | 97 taxa, 225 places, 0.774, 0.645 |

Of the 978 taxa paired at planning, 550 have later finds ranked by models
on both sides. The rest have no ranked later finds under one labelling or
the other.

**Also reported: the two releases compared (descriptive; no hypothesis).**
The run: `study-compare --frozen=priv-20261026T021038Z-3ba43cf6
--record=priv-20261026T021038Z-9c0ba509`, job study-20261029T044506Z-e883f8f5,
image bf236cf (Atlas main, with fix/study-compare-out 29ddeb8). It ran on 1 ×
r7i.xlarge on-demand, 04:47 to 04:56 UTC on 2026-10-29. Steve confirmed it
directly with the operations lane.

- **Records whose label differs, by source** (each record's DNA name against
  its record name; 124,955 records):

  | Source | Records | Same | Spelling only | Another species, same genus | Another genus | No species-level record name |
  |---|---|---|---|---|---|---|
  | iNaturalist | 118,703 | 117,226 | 89 | 1,120 | 238 | 30 |
  | MO Observations | 4,593 | 4,207 | 21 | 282 | 39 | 44 |
  | MycoPortal | 1,344 | 845 | 9 | 271 | 149 | 70 |
  | MyCoPortal | 252 | 125 | 1 | 64 | 35 | 27 |
  | Sequences | 61 | 57 | 0 | 1 | 2 | 1 |
  | GenBank Accessions | 2 | 2 | 0 | 0 | 0 | 0 |
  | **All** | **124,955** | **122,462** | **120** | **1,738** | **463** | **172** |

  The DNA names another species or genus than the record name for 2,201
  records (1.8%). By source: iNaturalist 1.1%, MO 7.0%, MycoPortal 31.2%,
  MyCoPortal 39.3%.
- **Taxa.** 15,770 under DNA names and 15,633 under record names.
  - 656 DNA taxa split: their records go to two or more record-name taxa.
  - 737 record-name taxa merged: two or more DNA taxa feed each.
  - 469 names exist only under record names, and 606 only under DNA names.
  - 1,331 taxa changed their record set; 13,833 did not.
- **Models.** The DNA release has 1,852 fitted models and the record-name
  release 1,860.
  - 1,702 pairs have the same taxon and learner on both sides; these are
    the maps compared.
  - 158 record-name models have no DNA counterpart: 112 ESM, 21 Maxent, 21
    RF and 4 XGBoost. Their grades are 5 strong, 95 weak and 58 failed.
  - 44 DNA models belong to taxa with no record under record names.
  - 106 DNA models belong to taxa that have records under record names but
    no record-name model of the same learner.
- **Map agreement** over the cells both maps give a value (Spearman: 1,700
  pairs, since 2 Maxent pairs have a constant map; Schoener's D: 1,702
  pairs):

  | | Pairs | Spearman median [IQR] | 10th pct | ≥ 0.9 | Schoener's D median [IQR] | 10th pct | ≥ 0.9 |
  |---|---|---|---|---|---|---|---|
  | All | 1,700 / 1,702 | 0.958 [0.892, 0.990] | 0.747 | 72.6% | 0.957 [0.918, 0.976] | 0.835 | 80.0% |
  | ESM | 823 | 0.970 [0.883, 0.995] | 0.700 | | 0.969 [0.930, 0.987] | 0.882 | |
  | Maxent | 379 / 381 | 0.974 [0.873, 0.997] | 0.687 | | 0.911 [0.812, 0.971] | 0.671 | |
  | RF | 381 | 0.948 [0.916, 0.968] | 0.866 | | 0.960 [0.952, 0.967] | 0.943 | |
  | XGBoost | 117 | 0.910 [0.839, 0.961] | 0.785 | | 0.918 [0.838, 0.949] | 0.757 | |

  - The lowest values are Spearman −0.179 (an ESM pair) and D 0.420 (a
    Maxent pair). 58 pairs have Spearman below 0.5 (40 ESM, 17 Maxent, 1
    XGBoost, 0 RF).
  - **Pairs with the same presence count** (287): median Spearman 0.987 and
    D 0.979. **Pairs with different counts** (1,413): 0.951 and 0.953.
  - No pair's maps are identical.
- **Grades of the 1,702 pairs** (DNA name → record name):

  | DNA \ record | strong | weak | failed |
  |---|---|---|---|
  | strong (77) | 44 | 32 | 1 |
  | weak (1,412) | 54 | 1,267 | 91 |
  | failed (212) | 1 | 81 | 130 |
  | untested (1) | 0 | 1 | 0 |

  - 1,441 pairs (84.7%) keep their grade and 261 change: 136 up, 124 down,
    and 1 untested becomes weak.
  - 77 pairs are strong under DNA names and 99 under record names. 44 are
    strong under both.

These are descriptive and decide nothing. H9 (above) is the registered
comparison.

**Deviations, dated.**
- 2026-10-25, before any fit: two jobs launched together instead of one,
  since a job carries one pull (0ac3547). The comparison is unchanged.
- 2026-10-26, during the fits: the record side reached its 8 h limit with
  shard 4 unreported. The same job was run again (Steve's direct OK); only
  shard 4 was relaunched, on-demand, on the same image and processor
  family, resuming from its 128 saved models. A fit saved before a reclaim
  is the same fit; nothing in the design changes.
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
