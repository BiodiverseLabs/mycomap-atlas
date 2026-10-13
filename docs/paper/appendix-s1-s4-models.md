# Appendix S1, Section S4: models, evaluation and maps (draft)

*Moved from the main text on 2026-10-13 (lean main text); edited only for the move.*

## S4.1 Survey sites, target-group background and effort

All eligible records of every taxon are gathered into survey sites by
greedy distance thinning at 5 km, busiest place first. For each taxon a site
is a detection if any of its records is that taxon, and a non-detection
otherwise (a target-group background; Phillips et al. 2009), each counted
once. Sites are drawn from the taxon's accessible area, its own sites
buffered by 500 km. Effort, the log of a site's records with the taxon's own
records counted once, is a predictor for the tree models and held at the
median of detection sites when maps are drawn or scored (Warton et al. 2013;
Fithian et al. 2015). Maxent is fitted without it: on virtual species with a
known habitat, effort as a covariate, offset or weight made Maxent's maps
slightly worse (E14) [pre-freeze].

## S4.2 Models, tuning and scoring

| Sites | Models |
|---|---|
| 3–19 | ensemble of small models (ESM; Breiner et al. 2015): every pair of the first ten predictors, quadratic, penalised, weighted by held-out skill |
| 20–49 | Maxent (maxnet; Phillips et al. 2017), random forest (down-sampled, ranger; Valavi et al. 2021), ESM |
| 50+ | Maxent, random forest, boosted trees (xgboost) |

Settings are tuned by nested spatial cross-validation (Maxent feature classes
and regularisation multiplier 0.25–4; tree depth; mtry). Blocks are sized from
a variogram of each taxon's sites with blockCV (Valavi et al. 2019), held to
50–300 km, dealt into five folds with detection blocks first; taxa with fewer
than 20 sites use three folds of 100 km blocks. A kNNDM-style check (Milà et
al. 2022) compared cross-validation distances with mapping distances (E13).
Scores are blocked AUC against the taxon's non-detection sites and the Boyce
index (Hirzel et al. 2006) pooled over folds. [CHECK: the maxnet glmnet path
settings, 20 steps with a pass cap, belong in S1.]

## S4.3 The null test and the grade in full

Each model is refitted, with the same untuned settings and folds, on null
species. In the production design (*shift*), the taxon's own detection sites
are rotated by one random angle and moved together to another surveyed place
(busier places more often), and each point is snapped to a free survey site;
the pattern's clustering is kept and its tie to environment is broken.
Previously (*scatter*) null detections were drawn site by site. Up to 99
nulls are drawn; the sequential test of Besag & Clifford (1991) stops once 5
nulls match the map. A model passes when its blocked AUC beats the nulls at
p ≤ 0.05 and its pooled Boyce index is above 0. Benjamini–Hochberg q-values
across taxa are recorded but do not decide (with 99 nulls the smallest p is
about 0.01).

Grades: **strong** (passed against shift nulls); **weak** (held-out skill,
but not shown to beat clustered collecting); **failed** (no better than
chance on held-out ground); **untested**. Only strong maps are used
downstream: the combined map, state verdicts, the "what could grow here"
index, the location prior for MycoMap Vision, and the sitemap. Map opacity
follows a map strength from the margin over the nulls.

## S4.4 Area of applicability, maps and combined maps

Each model has an area of applicability (Meyer & Pebesma 2021), from
importance-weighted standardised distances to training sites with the
cross-validation threshold; cells outside are hatched and unranked. Maps are
coloured by rank within the area of applicability. Strong maps are also
projected over North America on the same scale ("potential, not range"),
with the AOA computed over the full extent. When two or more of a taxon's
models are strong, they are averaged by rank, weighted by AUC − 0.5, with a
disagreement layer.
