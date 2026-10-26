# Appendix S1: Section S6. Independent tests: the hindcast, the distance baseline and prospective tracking

*Draft, 2026-10-25. Every number is copied from the registry entries named
in each heading and is not recomputed here. E3 (prospective tracking) is
registered and reads out about 2026-12-16.*

## S6.1 Design in brief

- **Hindcast (E2).** The whole pipeline, null tests included, was rerun on
  the records of the frozen pull first validated on or before 2026-08-17
  (124,955 of 133,235 kept; none undated). 9,115 models were planned, 8,606
  fitted and 509 refused; 414 taxa had a strong model; 289 CPU-hours.
  Private release priv-20261018T171648Z-9e3ab153. One small-site model
  (*Sparassis spathulata*) was refitted without a training record that had
  in fact been validated after the cutoff, before any scoring
  (priv-20261019T042158Z-09936f85; still weak, 14 sites). Four such
  records were kept out of the test finds; none was among them
  (`2026-10-13-prereg-e2-hindcast.md`, Deviations).
- **Test finds.** Records first validated after the cutoff, counted once per
  taxon and 5 km cell (a "place").
- **Scores.** A place's rank on the map within the model's area of
  applicability (0–1; half land in the top half by chance); the shares in
  the top half and top tenth; mean rank; the Boyce index; and "beats
  effort", whether the place outranks the cells of other taxa's later finds
  in the same period. Intervals are 95% percentile intervals from 10,000
  bootstrap resamples of taxa (seed 1).
- **Distance baseline (E6b).** Per taxon, a sum of Gaussian kernels over its
  training survey sites, with the bandwidth (5, 10, 25, 50, 100, 200 or
  400 km) chosen on the taxon's production spatial folds by blocked AUC,
  re-ranked over each model's own area-of-applicability cells, so every
  model place has a kernel place (`2026-10-13-prereg-e6b-distance-baseline.md`).
  The kernel's own AUC is the best of seven on one set of folds and is not
  nested; it is not used in any test.

## S6.2 Hindcast: registered hypotheses (E2)

Scored 2026-10-19, study-20261019T181851Z-35fc3d63. 7,509 places across
3,655 taxa; none off the grid; kept apart: undated 0, observed before the
cutoff 0, excluded 0, held 0.

| | Estimate | 95% interval | Taxa | Holds |
|---|---|---|---|---|
| H2a: strong, top-half share | 0.9145 | 0.8856–0.9419 | 214 | yes |
| H2b: strong − failed, top-half share | 0.1305 | 0.0898–0.1719 | 735 | yes |
| H2c: strong, beats-effort share | 0.7854 | 0.7627–0.8056 | 214 | yes |
| H2d: moderate, top-half share | 0.8876 | 0.8684–0.9058 | 660 | yes |
| H2e: moderate, beats-effort share | 0.7536 | 0.7396–0.7674 | 660 | yes |
| H2f: indicative, top-half share | 0.8655 | 0.8537–0.8767 | 1,666 | yes |
| moderate-z, top-half share (reported) | 0.8981 | 0.8774–0.9174 | 515 | |
| moderate-z, beats-effort share (reported) | 0.7623 | 0.7477–0.7770 | 515 | |

## S6.3 Hindcast by grade (E2)

Per-model rows. "New" places are more than 5 km from any of the taxon's
training sites; "known" places are within 5 km.

| Grade | Rows | Taxa | Ranked places | Top half | Top tenth | Mean rank | Beats effort | Boyce |
|---|---|---|---|---|---|---|---|---|
| strong, all | 736 | 214 | 486 | 0.9145 | 0.4957 | 0.8186 | 0.7854 | 0.968 |
| strong, new | 506 | 183 | 334 | 0.8783 | 0.4000 | 0.7730 | 0.7369 | 0.971 |
| strong, known | 230 | 89 | 152 | 0.9870 | 0.6870 | 0.9099 | 0.8823 | 0.843 |
| weak, all | 11,690 | 2,082 | 5,094 | 0.8696 | 0.4566 | 0.7894 | 0.7166 | 1.000 |
| weak, new | 8,650 | 1,882 | 3,788 | 0.8394 | 0.3713 | 0.7520 | 0.6742 | 0.999 |
| weak, known | 3,040 | 773 | 1,306 | 0.9509 | 0.6858 | 0.8900 | 0.8305 | 0.999 |
| failed, all | 1,177 | 528 | 904 | 0.7840 | 0.3433 | 0.7178 | 0.6716 | 0.995 |
| failed, new | 939 | 485 | 695 | 0.7409 | 0.2666 | 0.6774 | 0.6266 | 0.991 |
| failed, known | 238 | 135 | 209 | 0.9286 | 0.6008 | 0.8534 | 0.8227 | 0.976 |
| untested, all | 23 | 2 | 23 | not tested (< 30 places) | | | | |

Rows outside the area of applicability: strong 1, weak 16, failed 1.
Beyond the 500 km reach: strong 45, weak 477, failed 139. The Boyce index
is near 1 for every grade on these finds and does not separate them, so
the main text does not use it.

**By tier**, all places:

| Tier | Rows | Taxa | Places | Top half | Top tenth | Beats effort | Boyce |
|---|---|---|---|---|---|---|---|
| moderate | 2,237 | 660 | 1,519 | 0.8876 | 0.5120 | 0.7536 | 0.999 |
| indicative | 9,448 | 1,666 | 4,335 | 0.8655 | 0.4437 | 0.7080 | 1.000 |
| failed (by tier) | 1,182 | 531 | 909 | 0.7841 | 0.3426 | 0.6714 | 0.996 |
| moderate-z | 1,641 | 515 | 1,159 | 0.8981 | 0.5156 | 0.7623 | 0.998 |

New places only (top half / beats effort): moderate 0.8534 / 0.7099;
indicative 0.8362 / 0.6662; moderate-z 0.8636 / 0.7228.

**Combined maps**, all places: 523 rows, 214 taxa, 486 places, top half
0.9218, top tenth 0.5185, beats effort 0.7868, Boyce 0.981; new places
0.8892 / 0.7392; known places 0.9934 / 0.8915 (top half / beats effort).

**Re-scores, 2026-10-26** (`2026-10-13-prereg-e2-hindcast.md`, Results,
"Re-scores of 2026-10-26"). Rerunning all finds gave H2a–H2c exactly as
above.

*The registered secondary set: finds also observed after the cutoff.* Of
the later finds, 7,913 were observed before the cutoff, leaving 337 places
of 285 taxa. Strong maps have 18 ranked places, below the 30-place
minimum, so H2a–H2c are untested on this set (not failed). Weak maps: 218
taxa, 242 places, top half 0.894, beats effort 0.657 (new places 0.897 /
0.653). Failed maps: 52 taxa, 49 places, 0.796 / 0.647. H2d 0.8952
(0.8261–0.9519), H2e 0.6861 (0.6197–0.7496), H2f 0.8938 (0.8540–0.9283):
all hold.

*Exploratory: H2a–H2c within the models' site bands* (all finds):

| Site band | Taxa | Places | H2a strong top half | H2b strong − failed | H2c strong beats effort |
|---|---|---|---|---|---|
| 3–4 | 322 | 323 | too few places | too few places | too few places |
| 5–19 | 1,231 | 1,799 | 0.890 (0.833–0.941) | 0.179 (0.096–0.259) | 0.816 (0.784–0.845) |
| 20–49 | 723 | 1,947 | 0.922 (0.885–0.955) | 0.090 (0.038–0.142) | 0.778 (0.749–0.805) |
| 50–99 | 246 | 1,305 | 0.914 (0.833–1.000) | 0.034 (−0.070–0.156) | 0.774 (0.677–0.825) |
| 100+ | 45 | 363 | too few places | too few places | too few places |

*Exploratory: each model's null-test z against its later finds* (4,367
models with both; computed from the per-model table, no interval).
Spearman correlation of z with later-find mean rank 0.142, with top-half
share 0.124. Median mean rank by quarter of z: below −0.65, 0.805; −0.65 to
0.23, 0.810; 0.23 to 0.86, 0.819; 0.86 and up, 0.878. The median top-half
share is 1.0 in every quarter, because most models have few later finds.

## S6.4 Against distance to known records (E6b)

Scored 2026-10-20, study-20261020T232528Z-05216058, with E2's settings
(E2's own numbers in this run equal E2's). 2,567 taxa had a kernel and
later finds. 35 kernels whose block differed between processor families
were rebuilt on the hindcast's own family and all matched
(`2026-10-13-prereg-e6b-distance-baseline.md`, Deviations).

**Registered hypothesis**, strong model minus kernel on the same places:

| | Estimate | 95% interval | Taxa | Places | Holds |
|---|---|---|---|---|---|
| H6b: top-half share | +0.0435 | 0.0147–0.0755 | 202 | 486 | yes |
| mean rank difference (reported) | +0.0042 | −0.0166 to 0.0267 | 202 | 486 | |
| new places only: top-half share | +0.0478 | 0.0000–0.0996 | 168 | 334 | no (lower bound 0) |
| new places: mean rank difference | +0.0079 | −0.0207 to 0.0378 | 168 | 334 | |

**Tiers against the kernel** (reported):

| Tier | Top-half difference | 95% interval | Mean rank difference | 95% interval | Taxa | Places |
|---|---|---|---|---|---|---|
| moderate | −0.0142 | −0.0334 to 0.0050 | −0.0168 | −0.0299 to −0.0037 | 628 | 1,519 |
| indicative | −0.0263 | −0.0393 to −0.0140 | −0.0297 | −0.0378 to −0.0217 | 1,571 | 4,335 |

**Strong models and their kernels**, top-half share, the same 736 rows and
214 taxa (descriptive; the bands carry no intervals):

| Places | Strong models | Kernel |
|---|---|---|
| all | 0.914 | 0.871 |
| new (> 5 km) | 0.878 | 0.830 |
| known | 0.987 | 0.952 |
| 5–25 km | 0.974 | 1.000 |
| 25–100 km | 0.928 | 0.928 |
| 100–500 km | 0.760 | 0.611 |

The two near bands in full (the two sides have the same counts):

| Band | Ranked | Places | Top half | Top tenth | Mean rank | Beats effort | Boyce |
|---|---|---|---|---|---|---|---|
| 5–25 km, model | 113 | 80 | 0.9735 | 0.6283 | 0.8777 | 0.7958 | 0.870 |
| 5–25 km, kernel | 113 | 80 | 1.0000 | 0.6991 | 0.9161 | 0.7708 | 0.933 |
| 25–100 km, model | 180 | 127 | 0.9278 | 0.4444 | 0.8161 | 0.7722 | 0.962 |
| 25–100 km, kernel | 180 | 127 | 0.9278 | 0.5611 | 0.8408 | 0.6780 | 0.876 |

No strong-model place lies beyond 500 km.

**Weak models and their kernels**, the same places (reported, no interval;
11,690 rows, 2,082 taxa, 5,094 ranked places on each side):

| Places | Top half, weak / kernel | Top tenth, weak / kernel | Mean rank, weak / kernel |
|---|---|---|---|
| all | 0.8696 / 0.8936 | 0.4566 / 0.5158 | 0.7894 / 0.8167 |
| new (> 5 km) | 0.8394 / 0.8624 | 0.3713 / 0.4316 | 0.7520 / 0.7793 |
| known | 0.9509 / 0.9776 | 0.6858 / 0.7421 | 0.8900 / 0.9171 |

**The kernel over its own 500 km reach**, all taxa (secondary): 6,206 rows,
462 beyond reach; top-half share 0.882 (new places 0.853, known 0.971,
100–500 km 0.707).

## S6.5 What the comparison decided, and when

The registered bar for showing a looser tier as a labelled map was a lower
bound above 0.5 on its later finds. A model that knows only the distance to
known records clears that bar easily (0.871 on the strong maps' places,
0.882 over its own reach), so it cannot tell a habitat map from distance.
After seeing E6b's results, Steve added a rule, reported here as a post-hoc
choice: a tier carries downstream claims only if its top-half share minus
the kernel's has a 95% lower bound above 0 (the test H6b applies to strong
maps). Strong passes it; moderate (−0.0142, −0.0334 to 0.0050) and
indicative (−0.0263, −0.0393 to −0.0140) do not, so both are drawn as
weak maps (`2026-10-13-plan-map-tiers.md`, 2026-10-20). Every tier's E2
numbers are reported in full above, and E1 reports every tier's false-pass
rate and power as registered.

## S6.6 Prospective test on the published maps (E3)

Registered 2026-10-21 (`2026-10-21-prereg-e3-prospective.md`): finds first
validated from 2026-10-14 to 2026-12-15, none of which the frozen release
saw, scored on the published maps with E2's scores and against E6b-style
kernels built from the frozen release's fitting pulls (all 6,369 modelled
taxa have one). Hypotheses H3a–H3c mirror H2a, H2b and H6b. [PENDING:
read-out about 2026-12-16.]
