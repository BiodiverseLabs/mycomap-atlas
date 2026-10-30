# Appendix S1: Section S5. Calibrating the null test on simulated species (E1)

*Draft, 2026-10-29. Every number is copied from the registry entry
`docs/experiments/2026-10-13-prereg-e1-null-calibration.md` (Result,
2026-10-29), not recomputed here. The design, hypotheses, amendments and
the reader's implementation choices were registered before launch.*

## S5.1 Design in brief

- **Species.** 2,840 simulated species, each "collected" at the frozen
  pull's real survey sites with its real effort.
  - Full models (Maxent and random forest), five site bands (20–29, 30–49,
    50–99, 100–199, 200+): 800 geography species (detections around one or
    two centres, no habitat in their making) and 1,200 habitat species (two
    breadths × two signal strengths × 60 per band and cell).
  - Ensembles of small models (ESM), three bands (3–4, 5–9, 10–19): 360
    geography and 480 habitat species (two strengths).
  - A species counts in the band of its realised detection sites.
- **Null designs.** Scatter (null detections drawn site by site) and shift
  (the species' own detection sites rotated and moved together to other
  surveyed ground, each point snapped to a survey site); up to 99 nulls,
  stopping at the fifth match; the production pass rule (AUC p ≤ 0.05 and
  Boyce > 0).
- **"False pass"** means a pass of a geography species, whose detections
  follow geography and effort alone; it does not mean a map that is wrong
  about a real species.
- **Run.** study-20261025T212753Z-55239fbd, 20 shards, all on r7i.8xlarge
  (Intel Sapphire Rapids): spot, then on-demand one shard at a time after
  the spot run's limit. All 2,840 species scored; 32 Maxent arm errors
  (glmnet failed to complete its path), 28 of them in effort arms no test
  reads and 4 in Maxent's own fits at 200+ sites (1 geography, 3 habitat
  species); one geography species drew no null replicate in either design
  and its results were written as an empty record, which stopped the
  reader. It is read as not passed (primary) and left out as a
  sensitivity, a choice written down before any result was read (prereg,
  Deviations, e8e9fc5); the sensitivity changes no verdict. This is the
  only judgement made at read time.
- **Deviations.** Logged in the prereg before any reading: glmnet's settings
  set per fit; a first attempt lost to an AWS error; about a dozen
  in-progress log lines seen by accident during a liveness check, from an
  attempt whose results were then lost (the relaunch recomputes those
  species with the same seed, so their counted verdicts will likely equal
  the ones seen; the reader had been fixed and reviewed before, so this
  cannot affect the analysis); the move to on-demand machines.

## S5.2 Registered hypotheses

| | Maxent | Random forest | Criterion | Holds |
|---|---|---|---|---|
| H1a: shift false pass | 46/799 = 5.8% (4.3–7.6) | 39/800 = 4.9% (3.6–6.6) | upper bound ≤ 5% and every band ≤ 5% | no, no |
| H1b: scatter false pass | 600/799 = 75.1% (72.0–78.0) | 654/800 = 81.8% (78.9–84.3) | lower bound > 20%, rising with band | yes, yes |
| H1c: power and habitat breadth | logit −10.7 (z −7.3, p 2.5e-13) | −10.4 (z −5.8, p 7.1e-9) | two-sided p < 0.05 | yes, yes (lower for wider habitats) |
| H1d: narrow habitats, power rises with band | 17.2%, trend p 0.00034 | 11.3%, p 0.014 | one-sided p < 0.05 | yes, yes |
| H1e: passed maps closer to truth | median ρ 0.901 vs 0.606; difference 0.295 (0.264–0.318); p 2.0e-44 | 0.761 vs 0.639; 0.123 (0.088–0.153); p 3.5e-10 | one-sided p < 0.05 | yes, yes |
| H1f: strong beats weak signal | z 0.03, p 0.49 | z 0.03, p 0.49 | one-sided p < 0.05 | no, no (complete separation: weak passed 0/599 and 0/600) |

**C1 is not supported, as registered or by band.** Under the amendment of
2026-10-25, a band qualifies when its own Wilson upper bound is at most 5%,
which at 160 species allows at most 2 false passes; every band had 4 or
more. The band decisions would have been uncorrected for testing five
bands.

## S5.3 False passes by site band

| Band | Maxent shift | Random forest shift | Maxent scatter | Random forest scatter |
|---|---|---|---|---|
| 20–29 | 6/160 = 3.8% (1.7–7.9) | 4/160 = 2.5% (1.0–6.3) | 28.8% | 49.4% |
| 30–49 | 7/160 = 4.4% (2.1–8.8) | 9/160 = 5.6% (3.0–10.3) | 63.1% | 70.6% |
| 50–99 | 9/160 = 5.6% (3.0–10.3) | 9/160 = 5.6% (3.0–10.3) | 87.5% | 91.9% |
| 100–199 | 7/160 = 4.4% (2.1–8.8) | 7/160 = 4.4% (2.1–8.8) | 96.9% | 96.9% |
| 200+ | 17/159 = 10.7% (6.8–16.5) | 10/160 = 6.3% (3.4–11.1) | 99.4% | 100% |

Scatter trend, one-sided: Maxent p 3.6e-59, random forest p 4.2e-40.

## S5.4 Power of the shifted null

No weak-signal habitat species passed (0/599 Maxent, 0/600 random forest),
in any band. Strong-signal species, by band:

| Learner | 20–29 | 30–49 | 50–99 | 100–199 | 200+ | All |
|---|---|---|---|---|---|---|
| Maxent | 11.7% (14/120) | 15.0% | 25.8% | 24.2% | 28.0% (33/118) | 20.9% (125/598) |
| Random forest | 10.0% (12/120) | 8.3% | 15.0% | 14.2% | 18.3% (22/120) | 13.2% (79/600) |

Narrow habitats (both strengths): Maxent 8.3% at 20–29 rising to 22.7% at
200+; random forest 9.2% to 15.8%.

## S5.5 Ensembles of small models (secondary)

Shift false pass 6/360 = 1.7% (0.8–3.6), by band 0/120, 1/120 and 5/120;
scatter 61/360 = 16.9% (13.4–21.2), by band 0%, 8.3% and 42.5%. Shift power:
strong signal 8/240 (3.3%), weak 0/240. H1e on 8 passed species: median ρ
0.708 vs 0.480, difference 0.228 (0.128–0.296), p 0.0026. Below 20 sites,
both nulls almost never pass anything.

## S5.6 Map tiers (secondary; at or above each tier, geography species)

| Tier | Maxent | Random forest | ESM |
|---|---|---|---|
| strong (the shift test) | 5.8% | 4.9% | 1.7% |
| moderate | 20.4% | 17.1% | 11.9% |
| moderate (z) | 16.8% | 14.0% | 10.6% |
| indicative | 94.6% | 97.4% | 73.9% |

On habitat species the moderate tier passed 32.4% of strong-signal and 1.5%
of weak-signal Maxent species (random forest 26.7% and 0.5%). Median
map-to-truth ρ by tier (Maxent / random forest): strong 0.901 / 0.761,
moderate 0.870 / 0.770, indicative 0.607 / 0.644, failed 0.359 / 0.478.
Before any run, a tier was to carry downstream claims only if its pooled
false pass was at most 10% for Maxent and for random forest
(`2026-10-13-plan-map-tiers.md`); no looser tier meets it.

## S5.7 Nulls drawn and best-effort shifts

The shift design's sequential stop drew a median of 10 nulls per test;
scatter drew a median of 100 for Maxent and random forest and 20 for ESM.
When all 200 candidate shifts of a null are rejected, the least bad is kept
and marked best-effort. Share of shifted nulls that were best-effort:

| Band | Maxent | Random forest | ESM |
|---|---|---|---|
| 3–4 | – | – | 42% |
| 5–9 | – | – | 41% |
| 10–19 | – | – | 52% |
| 20–29 | 69% | 68% | – |
| 30–49 | 70% | 70% | – |
| 50–99 | 81% | 82% | – |
| 100–199 | 91% | 92% | – |
| 200+ | 97% | 97% | – |

The 200+ band, where nearly every shifted null is best-effort, is also
where Maxent's false passes were highest; the study does not test whether
one causes the other.

## S5.8 The pilot

Before the freeze, an exploratory study of 49 geography and 50 habitat
species (Maxent only; `2026-10-13-null-calibration-by-band.md`) gave
scatter 36/49 false passes and shift 1/49 (2%), with shift power 13/50. The
full study replaces those figures.

## S5.9 Cost

About 63.6 instance-hours of r7i.8xlarge (spot about 30.8, including the
lost first attempt and reclaims; on-demand 32.8), at most about USD 134 at
list price (`costs.md`).
