# Pre-registration: null-test calibration on virtual species (paper E1)

- **Status.** Pre-registered 2026-10-13, before the study is run; amended
  the same day, still before launch (see "Amendments"). Any change after
  launch is listed under "Deviations" below with its date and reason.
- **Question.** How often does each null design pass a species with no
  habitat signal (false pass), and how often a species with one (power), by
  sample size, habitat breadth, signal strength and learner? Does passing select maps closer to
  the true habitat? Serves paper claim C1 (and C2 for map-to-truth).
- **Reproducibility.** frozen (the frozen release's pull and layers).
- **Earlier result.** `2026-10-13-null-calibration-by-band.md`
  (exploratory, 99 species, Maxent only).

## Design

- **Species.** `study-virtual`, collected at the real survey sites of the
  frozen pull with MycoMap's real effort.
  - **Full models** (Maxent and random forest), 5 site bands (20–29, 30–49,
    50–99, 100–199, 200+).
    - Habitat species: 2 breadths × 2 signal strengths × 30 per band = 600.
      **Breadth**: narrow and wide response widths (the generator's bell
      width halved and doubled against its current draw). **Signal
      strength**: how strongly detections follow the habitat. *Strong*: each
      real record at a site is the virtual species with probability
      proportional to the habitat there (the current generator). *Weak*:
      half of that probability follows the habitat and half is the same at
      every site, so the species is found partly regardless of habitat.
    - Geography species: one or two centres × 40 per band = 400.
  - **Small-model ensembles**, 3 site bands (3–4, 5–9, 10–19): habitat 2
    signal strengths × 40 and geography 60 per band = 420 species.
  - **Realised breadth** per habitat species: the share of its accessible
    area's survey sites with true suitability ≥ 0.5. It is the continuous
    covariate for H1c.
- **Null designs.** scatter and shift, 99 nulls each, sequential stop at 5,
  production pass rule (AUC p ≤ 0.05 and Boyce > 0). Seeds fixed from the
  species spec.
- **Also run, secondary:** shift-effort; the effort arms (none, covariate,
  offset, weights) for Maxent, as in E14.
- **Later and exploratory:** a shift-and-rotate-of-predictors arm after
  Ridder et al. (2024). It is queued after this core and is not part of
  these hypotheses.

## Hypotheses and criteria

Intervals are Wilson 95% intervals for proportions and bootstrap intervals
(10,000 resamples of species) for differences.

- **H1a (calibration).** Shift nulls hold the false-pass rate at or below
  5%: the pooled upper bound ≤ 5% for each learner (Maxent, RF), and the
  point estimate ≤ 5% in every site band.
- **H1b (the usual test fails).** Scatter nulls exceed it: the pooled
  false-pass lower bound > 20%, rising with site band (Cochran–Armitage trend
  test, one-sided p < 0.05).
- **H1c (what limits power).** Shift power differs with habitat breadth. We
  expect it to be **lower** for wide habitats, because a broad, spatially
  smooth habitat can survive a shift. Logistic regression of pass on
  realised breadth and site band; two-sided p < 0.05 on breadth, with the
  direction reported.
- **H1d.** Within narrow habitats, shift power rises with site band
  (trend test, one-sided p < 0.05).
- **H1f (signal strength).** Shift power is higher for strong-signal than
  weak-signal habitat species (one-sided p < 0.05 on strength in the H1c
  model). The fitted model gives power as a curve over site count, breadth
  and strength.
- **H1e (passing selects better maps).** Among habitat species, the
  map-to-truth Spearman ρ is higher for shift-passed maps than for the rest:
  one-sided Wilcoxon p < 0.05, with the median difference and its interval.

**C1 is supported** if H1a, H1b and H1e hold for Maxent and for RF. H1c,
H1d and H1f describe the power; they do not decide C1. The ESM results are reported
by band against the same criteria but are secondary, because nulls at 3–19
sites are known to be weak.

## Secondary analysis: map tiers (added 2026-10-13, before launch)

For each tier in `2026-10-13-plan-map-tiers.md` (strong, moderate,
moderate-z, indicative), applied to the shift-design results already
recorded for every species: false pass (geography species) and power
(habitat species) by learner, band, breadth and signal strength, with
Wilson intervals; and map-to-truth ρ by tier. No extra fits. This analysis
does not change H1a–H1f or what supports C1.

## Reporting

False pass and power by design × learner × band × breadth × strength, with
intervals; the fitted power curve; nulls drawn per species (cost); and ρ by
grade.

## Amendments (before launch)

- 2026-10-13: signal-strength axis added (Steve, via the Atlas coordinator)
  so that power is a curve; habitat species per cell reduced from 40 to 30
  to keep cells balanced (600 + 400 full-model species, 420 ESM); H1f
  added.
- 2026-10-13 (design questions from the experiments lane, agreed before
  code):
  - **Bands by realised count.** The generator matches *expected* detection
    sites to a target; a species counts in the band of its *realised*
    detection sites. The target is drawn uniformly inside the band; a species
    whose realised count falls outside the band is redrawn with the next
    deterministic seed index, at most 20 times; a cell stops when full. The
    redraws and any failures are reported per cell.
  - **Weak signal:** detection probability per record = rate × (0.5 · h /
    mean h + 0.5), mean h over every survey site in the pull where h > 0
    (the ground the habitat reaches; the accessible area does not exist
    before collection), with the
    rate solved as for strong species so the expected number of detection
    sites matches the target. The same matching rule as strong.
  - **Breadth** halves or doubles the bell-shaped responses' widths only;
    rising responses (cover, host trees) are unchanged. Realised breadth
    (the covariate) captures the result.
  - **Realised breadth** uses suitability ≥ 0.5 on the absolute habitat
    scale (peak = 1).
  - **Nulls:** Maxent and RF both run scatter and shift ×99 with stop at 5,
    as registered (C1 needs both learners; RF fits are cheaper than Maxent's).
    The effort arms (E14) are Maxent only, on the 1,000 full-model species
    (habitat and geography), without nulls.
  - **Learners per species:** full-model species get Maxent and RF (not ESM,
    even at 20–49 sites); ESM species get ESM only. Map-to-truth ρ and the
    scatter and shift verdicts are computed per learner, and H1e is tested
    per learner.

- 2026-10-13 (counts only, before launch; hypotheses and criteria
  unchanged): the local calibration pilot priced the study at about 270–460
  CPU-h, about a fifth of the estimate, so species per cell are doubled to
  tighten the intervals, above all H1a's ≤ 5% false-pass bound. Habitat
  species 30 → 60 per band × breadth × strength cell (1,200); geography
  species 40 → 80 per band × centre-count cell (800); ESM habitat 40 → 80 per
  band × strength and geography 60 → 120 per band (840). With 160 geography
  species per band, zero passes give a Wilson upper bound of 2.3%, and the
  ≤ 5% point estimate allows up to 8 passes per band. Cells the generator
  cannot fill within its redraw limit (most likely narrow habitats at 200+
  sites) are reported with their counts, not padded.

- 2026-10-25 (independent review, accepted by Steve; before any E1 outcome
  is read: the smoke run's verdicts are not read, and the full run has not
  launched):
  - **What "false pass" means.** A false pass is a pass of a species whose
    detections follow geography and effort alone: a geography species,
    collected at the real survey sites in proportion to the real records
    there and around one or two centres, with no habitat in its making. It
    does not mean a map that is wrong about a real species.
  - **If a learner or band fails H1a.** C1 is decided per learner and per
    band; a failing learner or band is reported as failing, never dropped.
    - **Learner first.** If H1a holds for a learner as registered (pooled
      bound and every band), C1 for that learner is decided as registered.
    - **Otherwise, band by band.** H1a holds *in a band* when that band's
      shift false-pass Wilson upper bound is at most 5%. With 160 geography
      species, that is at most 2 passes.
    - C1 is then supported for that learner in exactly the bands where H1a
      holds, if two more conditions hold:
      - the band's scatter false-pass Wilson lower bound is above 20% (H1b's
        level; its trend across bands is not asked of one band);
      - H1e holds for the learner over the habitat species of those bands.
    - Every other band is reported as failing H1a, with its rate and
      interval. This covers random forest, the 100–199 and 200+ bands, and
      any other learner or band.
  - **Best-effort shifted nulls, reported by band.** When all 200 draws of a
    shifted null are rejected, R/nulls.R keeps the least bad draw and marks
    it best-effort.
    - Reported per learner and site band: the share of shifted nulls that
      were best-effort (best-effort nulls over nulls drawn), and the share of
      species with any.
    - This lets the paper say what the shift null is at 200+ sites.
    - It is reported only and changes no verdict.

## Runs

Logged as the operations lane reports them; numbers only.

- **Smoke run (launched 2026-10-25 15:40 UTC).**
  study-20261025T153943Z-9806a01c, image c56d2dc, `plan-study
  --command=study-calibration --shards=1
  --from-release=20261013T191324Z-fa1b4198 --args="--per-cell=1 --seed=1
  --workers=30"`, one r7i.8xlarge. Its job record lists the pull
  occurrences-20261012T051017Z-x73b85b36 (sha256 7d3c5d70…), the frozen
  release's. Steve confirmed it directly with the operations lane. Only
  statuses, errors, fill and timings are read from it (Deviations,
  2026-10-25).

## Deviations

- **2026-10-20, before launch (implementation only; no hypothesis,
  criterion, count or learner changes): glmnet's settings are set in each
  fit, not inherited from the process.** glmnet keeps its settings for the
  whole R process, and every Maxent fit sets two of them (pmin = 1e-8,
  fdev = 0) and leaves them set. E12's arm a2 found that the small-model
  ensemble (ESM) fit after a Maxent model in the same process gives a
  slightly different map: 191 of 225 maps differed in their bytes, with no
  grade changed (E12 plan, 2026-10-20). Production fits ESM in worker
  processes of its own, so every released ensemble was fitted at glmnet's
  defaults. `study-virtual` can fit Maxent and ESM species in one worker,
  so E1's ESM arm would have depended on the order of its species.
  - **ESM** now fits at glmnet's defaults, as every released ensemble was
    (Atlas fix/esm-glmnet-defaults 5b58f30).
  - **The detection model** (E14's effort arm, on the same species) reads
    only glmnet's convergence settings, which no Atlas code changes, so it
    was never affected. It is pinned all the same, to Maxent's settings,
    since it shares Maxent's features and penalty path (Atlas
    fix/detection-glmnet-pin a8861ab).
  - The cost pilot ran before these changes. Its timings stand, and none of
    its fits is reported.
- **2026-10-25, before launch (implementation only; no hypothesis,
  criterion, count or learner changes): what the run is, written before the
  smoke run.**
  - **Code and inputs.** Atlas main c56d2dc, which holds the glmnet fixes
    above. `plan-study --from-release=20261013T191324Z-fa1b4198` fetches
    the frozen release's job inputs onto every worker: the pull
    occurrences-20261012T051017Z-x73b85b36 (the 2026-10-12 pull less the 76
    drop-list rows) and the frozen layers. These are the "real survey sites"
    and "real effort" of the design. The job record lists them, with their
    hashes.
  - **One processor family.** A species' block size is measured by the
    variogram, and the measurement can differ between processor families,
    though within a family it is exact (E12, 2026-10-21: all 507 refits were
    bit-identical within a family, and only the block differed across
    families). So every E1 shard runs on Intel Sapphire Rapids (r7i). A
    rerun on that family reproduces E1 exactly; each shard's record names
    its machine, and each species' row holds its block. This is not a design
    change: production also measures a block once per taxon.
  - **The smoke run** (`--per-cell=1`) is one species per cell, 39 in all,
    on the full run's image, inputs and machine type. It checks the pipeline
    and the timing. Because the layout is smaller, its species are not the
    full run's, and no verdict, pass rate or map-to-truth ρ from it is read
    or reported. Only its statuses, errors, fill table and timings are read,
    as with the cost pilot. The full run's size is unchanged; only its cost
    estimate is updated from the smoke run.
  - **Shards.** The full layout is split into 20 shards, every 20th species
    from a different start (`atlas_study_shard`), so each shard holds a
    balanced share of every cell. The results are the union of the 20
    shards' files. A shard keeps nothing until it reports, so a reclaimed
    spot worker reruns its shard from the start with the same seeds and
    gives the same rows.
  - **Analysis.** The tests of H1a–H1f, and the tier analysis, read the
    pooled long rows (`atlas_calibration_long`). Their code is written and
    reviewed before the full run's results are opened, and nothing about
    the tests is changed after.
