# Plan: looser map tiers, judged on simulated species and later finds (paper E24)

- **Status.** Pre-specified 2026-10-13, before E1 or E2 has run (Steve: "I
  want to have some form of map for most species… we aren't yet on the
  mark here"). The tier rules and the evidence each must meet are fixed
  here; Steve chooses which tiers to use, and for what, after seeing both
  results.
- **Question.** Is there a looser grade than "strong" that still carries a
  real habitat signal, often enough to show more species' maps, and how
  often does it pass maps that know nothing?
- **Why.** In the frozen release (provisional) 576 of 9,042 models, across
  470 of ~6,811 modelled taxa, are strong. On simulated species, the strong
  test passed 2% of habitat-free species but only 26% of real-habitat ones,
  and its power did not rise with sites; ~5,700 modelled taxa have 3–19
  sites, where null tests have little power. "Not strong" therefore often
  means "not shown", not "wrong".

## The tiers

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

None yet.
