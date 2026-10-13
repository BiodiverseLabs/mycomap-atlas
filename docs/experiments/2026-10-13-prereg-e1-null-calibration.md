# Pre-registration: null-test calibration on virtual species (paper E1)

- **Status.** Pre-registered 2026-10-13, before the study is run. Any change
  after launch is listed under "Deviations" below with its date and reason.
- **Question.** How often does each null design pass a species with no
  habitat signal (false pass), and how often a species with one (power), by
  sample size, habitat breadth and learner? Does passing select maps closer to
  the true habitat? Serves paper claim C1 (and C2 for map-to-truth).
- **Reproducibility.** frozen (the frozen release's pull and layers).
- **Earlier result.** `2026-10-13-null-calibration-by-band.md`
  (exploratory, 99 species, Maxent only).

## Design

- **Species.** `study-virtual`, collected at the real survey sites of the
  frozen pull with MycoMap's real effort.
  - **Full models** (Maxent and random forest), 5 site bands (20–29, 30–49,
    50–99, 100–199, 200+) × 2 kinds × 2 strata × 40 = 800 species. Habitat
    kind strata: **narrow** and **wide** response widths (the generator's
    bell width halved and doubled against its current draw). Geography kind
    strata: one or two centres.
  - **Small-model ensembles**, 3 site bands (3–4, 5–9, 10–19) × 2 kinds × 60
    = 360 species.
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
- **H1e (passing selects better maps).** Among habitat species, the
  map-to-truth Spearman ρ is higher for shift-passed maps than for the rest:
  one-sided Wilcoxon p < 0.05, with the median difference and its interval.

**C1 is supported** if H1a, H1b and H1e hold for Maxent and for RF. H1c and
H1d explain the power; they do not decide C1. The ESM results are reported
by band against the same criteria but are secondary, because nulls at 3–19
sites are known to be weak.

## Reporting

False pass and power by design × learner × band × stratum, with intervals;
nulls drawn per species (cost); and ρ by grade.

## Deviations

None yet.
