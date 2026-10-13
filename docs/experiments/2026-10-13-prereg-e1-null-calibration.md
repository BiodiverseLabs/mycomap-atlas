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

## Reporting

False pass and power by design × learner × band × breadth × strength, with
intervals; the fitted power curve; nulls drawn per species (cost); and ρ by
grade.

## Amendments (before launch)

- 2026-10-13: signal-strength axis added (Steve, via the Atlas coordinator)
  so that power is a curve; habitat species per cell reduced from 40 to 30
  to keep cells balanced (600 + 400 full-model species, 420 ESM); H1f
  added.

## Deviations

None yet.
