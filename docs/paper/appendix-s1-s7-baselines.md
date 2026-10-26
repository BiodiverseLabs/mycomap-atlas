# Appendix S1: Section S7. Against standard practice: the distance baseline and default Maxent

*Draft, 2026-10-26. Numbers are copied from the registry entries named
here, not recomputed. Both comparisons use the hindcast's later finds and
E2's scores (Section S6).*

## S7.1 Distance to known records (E6b)

A sum of Gaussian kernels over each taxon's training survey sites, with the
bandwidth chosen on the taxon's own spatial folds, re-ranked over each
model's area of applicability. The registered test (H6b) and every split
are in Section S6.4. In brief: strong maps placed 4.4 points more later
finds in their top half than the kernel on the same places (0.0147–0.0755;
202 taxa), with no difference in mean rank; the gain came from finds 100 to
500 km from known records (descriptive); weak maps and both looser tiers
did no better than the kernel.

## S7.2 Maxent as commonly run (E6a)

`2026-10-13-plan-e6a-default-maxent.md` (planned before any run;
descriptive; the paired comparison exploratory).

**Design.** For the 1,260 hindcast taxa with 20 or more sites (feature
classes lqh for 1,173, lqph for 87): maxnet's defaults (feature classes by
sample size, regularisation multiplier 1, its full lambda path), every
production predictor, no effort term, and 10,000 background points drawn
at random from grid cells inside the taxon's 500 km accessible area rather
than at the surveyed sites. Its own evaluation: random 5-fold
cross-validated AUC, and the null test as Raes & ter Steege (2007) ran it,
the model's training AUC against the training AUCs of 19 null species of
as many points, drawn uniformly over the accessible area (pass at
p ≤ 0.05). Fitted on the hindcast's own pull (study-20261025T164211Z-4ffa4776,
8 shards, r7i.8xlarge spot), scored on E2's later finds
(study-20261025T211731Z-017e88fa), and scored again paired with Atlas's
models (study-20261026T020304Z-017e88fa).

**Its own verdicts.** 1,002 of the 1,014 taxa with later finds passed the
null test. Cross-validated AUC over the 999 taxa with ranked later finds:
median 0.892 (10th to 90th percentile 0.818 to 0.950).

| Default map's later finds in its top half | Taxa | Median CV AUC |
|---|---|---|
| below 0.5 | 12 | 0.867 |
| 0.5 to 0.9 | 91 | 0.878 |
| 0.9 and up | 896 | 0.894 |

**On later finds, as first scored** (default ranked over its whole
accessible area, Atlas within its area of applicability; per ranked place,
different taxon sets):

| Maps | Taxa | Places | Top half | Top tenth | Mean rank | Beats effort | Boyce |
|---|---|---|---|---|---|---|---|
| Default practice, passed | 1,002 | 3,587 | 0.964 | 0.746 | 0.909 | 0.679 | 0.989 |
| Atlas strong, same taxa | 117 | 347 | 0.920 | 0.497 | 0.821 | 0.777 | 0.903 |
| Atlas weak, same taxa | 990 | 3,544 | 0.875 | 0.469 | 0.795 | 0.714 | 0.999 |
| Atlas failed, same taxa | 164 | 471 | 0.838 | 0.424 | 0.764 | 0.683 | 0.986 |

New places only (top half / beats effort): default 0.951 / 0.603; strong
0.886 / 0.724; weak 0.843 / 0.667; failed 0.795 / 0.621. The 12 failed
default maps have 28 ranked places, too few for shares.

**Paired, on the same footing (exploratory).** Each default map ranked
again over its Atlas model's area of applicability, as E6b's kernel was;
default minus Atlas on the same taxa and places, with 95% intervals from
10,000 resamples of taxa:

| Atlas grade | Taxa | Places | Top half | Beats effort | Mean rank |
|---|---|---|---|---|---|
| strong | 114 | 347 | +0.029 (−0.009 to 0.069) | −0.060 (−0.087 to −0.034) | +0.071 (0.044 to 0.097) |
| weak | 975 | 3,544 | +0.087 (0.076 to 0.098) | −0.037 (−0.045 to −0.030) | +0.111 (0.103 to 0.118) |
| failed | 159 | 471 | +0.104 (0.070 to 0.141) | −0.012 (−0.034 to 0.010) | +0.124 (0.100 to 0.149) |

**Reading.** On the map's own cells, default practice ranks later finds
higher than Atlas's maps of the same taxa. Against the cells of other
taxa's later finds in the same period, which removes the advantage of
ranking well-collected ground high, it does worse than strong and weak
maps and no differently from failed ones. Its own null test passes almost
every taxon, and its cross-validated AUC barely tracks how its maps did.
This is the pattern a random background predicts: the model learns where
people collect, and later finds are collected there too.

**Cost.** Fits about 324 CPU-hours by the code's estimate (8 shards,
r7i.8xlarge spot, with reclaims); scoring about USD 0.23 and the paired
re-score about USD 0.33 (`costs.md`).
