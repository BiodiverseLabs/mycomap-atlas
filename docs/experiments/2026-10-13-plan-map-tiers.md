# Plan: looser map tiers, judged on simulated species and later finds (paper E24)

- **Status.** Pre-specified 2026-10-13, before E1 or E2 has run (Steve: "I
  want to have some form of map for most species… we aren't yet on the
  mark here"). The tier rules and the evidence each must meet are fixed
  here; Steve chooses which tiers to use, and for what, after seeing both
  results.
- **Question.** Is there a looser grade than "strong" that still carries a
  real habitat signal, often enough to show more species' maps, and how
  often does it pass maps that know nothing?
- **Release.** Scored on the frozen release 20261013T191324Z-fa1b4198.
- **Why.** In the frozen release (provisional) 576 of 9,042 models, across
  470 of ~6,811 modelled taxa, are strong. On simulated species, the strong
  test passed 2% of habitat-free species but only 26% of real-habitat ones,
  and its power did not rise with sites; ~5,700 modelled taxa have 3–19
  sites, where null tests have little power. "Not strong" therefore often
  means "not shown", not "wrong".

## The tiers

**Which Boyce:** the pooled Boyce index over held-out spatial folds, the same
value the production grade uses for every learner (R/fit.R: computed as
`boyce_pooled`, stored in each model's JSON as `boyce`). The hindcast's
(and its refit's) `models.tsv.gz` export left its `boyce_pooled` column
empty for all models (an export bug, reported 2026-10-19 for a one-line fix),
so tier analyses read `boyce` from each model's JSON until it is fixed.

All use only what every graded model already stores (no refit): the shift
null test's p, the observed held-out AUC and the pooled Boyce index, and
the null AUCs' mean and spread. The p follows R/nulls.R: a test that stops
early (five matches) has p = 5 / nulls scored, so p ≤ 0.20 means 25 or more
nulls scored before the fifth match; a test that runs to 99 without
stopping has at most four matches, so p = (1 + matches) / (1 + nulls) ≤
0.05, which is a pass (strong if Boyce > 0). Moderate needs a shift-null
p: a model graded only against scattered nulls can reach indicative at
most (the grade breakdown reports whether any such model is in the frozen
release). The null AUCs' mean and spread, needed for moderate-z in E1, are
recorded once study/calibration-tier-fields 520fac9 merges, before E1
launches.

| Tier | Rule (applied in order) | Today |
|---|---|---|
| **Strong** | shift p ≤ 0.05 and Boyce > 0 | unchanged |
| **Moderate** (new) | not strong; shift p ≤ 0.20 (beats at least 80% of shifted nulls: 25 or more drawn before the fifth match) and Boyce > 0 and AUC > 0.5 | part of "weak" |
| **Indicative** | not strong or moderate; AUC > 0.5 and Boyce > 0 | the rest of "weak" |
| **Failed** | everything else | unchanged |

A second, continuous variant is scored alongside, not instead: **moderate-z**
= not strong; effect size z = (observed AUC − mean null AUC) / SD of null
AUCs ≥ 1, and Boyce > 0. It is reported so the p-based rule can be checked
against it; the p-based rule is primary.

A taxon's tier is its best model's tier.

## Evidence each tier is judged on

1. **Simulated species (E1, secondary analysis; no extra compute).** For
   each tier, the share of habitat-free (geography) species it passes
   (false pass) and the share of habitat species (power), by learner, site
   band, breadth and signal strength, with Wilson intervals; and map-to-truth
   Spearman ρ by tier.
2. **Later finds (E2, secondary hypotheses).** For each tier, the share of
   test finds in the top half and top tenth, Boyce, and beats-effort, with
   intervals by bootstrap over taxa; and the same for the distance-only
   baseline (E6b) on the same places.
3. **Real models (E1c, the grade breakdown).** How many models and taxa
   each tier adds, by learner and site band.

## What the numbers will be read against (stated now)

These are the thresholds the coordinator will put to Steve with the
results; Steve decides.

- **For the claims the atlas makes downstream** (Explore, likely-by-state
  lists, combined maps, the app's species map, the Vision prior): a tier
  qualifies if its E1 pooled false pass is ≤ 10% for Maxent and for random
  forest (Wilson upper bound ≤ 15%), **and** its E2 top-half share and
  beats-effort share both have lower bounds above 0.5.
- **For display on the species page, labelled:** a tier qualifies if its E2
  top-half share has a lower bound above 0.5, whatever its false-pass rate,
  with the label stating that rate.
- **Neither:** the tier stays as today's faint "weak" map.

Results are reported in full whatever the choice, in Appendix S1 (S5 for
E1, S6 for E2).

## For species with 1–2 sites

No model is possible. A separate, clearly labelled product (for example,
known sites with similar habitat nearby) is a design question for the
rebuild lane and Steve, outside this plan.

## Deviations

- **2026-10-20, chosen AFTER seeing E6b's results (Steve): a tier carries
  downstream claims only if it beats the distance-only baseline.** This
  adds to the bar for downstream claims above (Explore, likely-by-state
  lists, the Vision prior and the other uses listed there). It was not
  stated before the results, and is reported as a post-hoc choice.
  - **The criterion.** On the same places, the tier's top-half share minus
    the distance kernel's has a 95% lower bound above 0. That is the test
    H6b applies to strong maps (bootstrap over taxa, as E2).
  - **Why.** The bar stated above asks whether a tier ranks later finds
    better than chance (lower bounds above 0.5). A model that knows only
    the distance to a taxon's known records already clears it by a wide
    margin: the kernel's top-half share is 0.871 on the strong maps'
    places, and 0.882 over its own reach. So that bar cannot tell a habitat
    map from distance to known records. A downstream claim says the map
    adds something about habitat, and a tier that does no better than
    distance does not support that.
  - **What it decides** (E6b prereg, Results):
    - strong: beats the kernel, +0.0435 [0.0147, 0.0755], so it carries
      claims.
    - moderate: does not beat it, −0.0142 [−0.0334, 0.0050], and its mean
      rank of finds is lower than the kernel's, −0.0168 [−0.0299, −0.0037].
      So moderate carries no downstream claims, whatever E1 shows.
    - indicative: ranks below the kernel, −0.0263 [−0.0393, −0.0140], so
      it carries no downstream claims.
  - **E1 is unchanged.** It runs and is reported as pre-registered,
    including every tier's false-pass rate and power. The bar stated above
    and every tier's E2 numbers are reported in full as well (Appendix S1,
    S5 and S6).
- **2026-10-20 (Steve): moderate and indicative maps stay as today's faint
  "weak" map.** No promotion on the species page, no promoting label and no
  new claim, although both clear the labelled-display bar above (top-half
  lower bounds 0.868 and 0.854). Moderate maps do no better than a
  distance-only map at ranking later finds, and indicative maps do worse.
  Neither tier exists in the release, the API or the web app: tiers are
  computed only by the E2 scorer. Both are graded "weak", which the site
  already draws faint, on the taxon page only, with the weak note. So this
  needs no change to the site.
