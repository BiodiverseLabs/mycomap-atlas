# Appendix S1, Section S1: ODMAP protocol (draft)

*Draft of 2026-10-13 (paper E17), following the ODMAP standard (Zurell et
al. 2020). It is written from the public Methods page and the code at the
paper branch's base commit. Values that depend on the frozen release are
marked [PENDING]; facts still to verify in code are marked [CHECK]. The
final version is checked against the frozen release's settings record.*

## Overview

| Element | Entry |
|---|---|
| Authorship | Russell, Stephen D.; contact info@mycomap.org [CHECK: the corresponding email the paper will give] |
| Model objective | Mapping and interpolation: relative habitat suitability within each taxon's accessible area (its sites buffered by 500 km), with a calibrated grade per map; strong maps are also projected over North America ("potential, not range"). Not forecasting or transfer in time. |
| Focal taxa | Every North American fungal taxon defined by an approved DNA sequence name (formal or provisional) with ≥ 3 survey sites [PENDING: N taxa in the frozen release] |
| Location | United States, Canada, Mexico, Puerto Rico, US Virgin Islands |
| Spatial scale | North America Albers Equal Area Conic (GRS80); 5 km cells (3.7 million); extent x −7,445,000 to 4,735,000 m, y −2,955,000 to 4,740,000 m |
| Temporal scale | Records of all years (each taxon page reports its record years; pre-1980 records kept); climate 1970–2000 normals; frozen release pulled 2026-10-12 |
| Biodiversity data | Presence of DNA-validated specimen records, summarised to detection and non-detection at 5 km survey sites (target group) |
| Types of predictors | Climate, topography, soil, land cover, forest type, host-tree genus shares; collecting effort for tree models |
| Hypotheses | Fungal occurrence responds to climate, soil (pH first) and, for ectomycorrhizal fungi, host trees; a map is trusted only if it beats null species that keep its own clustering |
| Assumptions | Target-group sites share the species' sampling bias; the accessible area bounds dispersal and sampling; species–environment relations are stable over the record period; validated names are correct |
| Algorithms | Maxent (maxnet), random forest (ranger, down-sampled), boosted trees (xgboost), ensembles of small models (penalised quadratic pairwise regressions) |
| Workflow | Pull → name and coordinate rules → survey sites → per-taxon training table → predictor pruning (Maxent, ESM) → nested spatial CV tuning → blocked scoring → shift null test (sequential, ≤ 99) → grade → area of applicability → maps, combined maps, release |
| Software | R 4.6.1 in a pinned container (base image by digest; packages from a dated Posit snapshot): terra, maxnet (fit adapted with a 20-step path), glmnet, ranger, xgboost, blockCV; [PENDING: package versions from the frozen release manifest] |
| Code availability | github.com/BiodiverseLabs/mycomap-atlas (GPL-3.0-or-later); Zenodo DOI for the release commit [PENDING] |
| Data availability | Layers, models and training-record ids of the frozen release on Zenodo (CC BY-SA 4.0; ids CC0 proposed) [PENDING: DOIs]; coordinates as published by each source |

## Data

### Biodiversity data

| Element | Entry |
|---|---|
| Taxon names | The approved sequence name of each record (formal or provisional); spelling, punctuation, author and rank-word variants merged; a model belongs to its record set (fingerprint), not its name |
| Taxonomic reference | No external authority: each record takes its approved sequence's name as curated on mycomap.org. Spellings that differ only in punctuation (quote marks, spaces, "sp-X" vs sp. 'X'), letter case or an author citation are merged under the majority spelling; letters and digits are never changed (IN1 ≠ IN01); renames are detected between consecutive pulls. No MycoBank, Index Fungorum or GBIF lookup. |
| Ecological level | Species and provisional species-level lineages |
| Data sources | iNaturalist, Mushroom Observer, MyCoPortal, GenBank and MycoMap sequence records held on mycomap.org; [PENDING E16: counts by source] |
| Sampling design | Opportunistic community-science collecting with sequencing; no designed survey |
| Sample size | Survey sites per taxon: ≥ 3 for ESM, ≥ 20 in ≥ 5 blocks for Maxent and RF, ≥ 50 for boosted trees [PENDING: distribution] |
| Clipping | North America; each taxon's accessible area (own sites + 500 km) |
| Scaling | Records thinned to survey sites: greedy 5 km distance thinning, busiest place first; every record joins its nearest site |
| Cleaning | Validated in ≥ 1 project; coordinates present, not obscured, accuracy ≤ 1 km where recorded; Mushroom Observer: visible GPS or a named place whose half-diagonal ≤ 5 km (coordinate from the source's own answer); MyCoPortal: own coordinates ≤ 5 km or a non-centroid locality; one approved species-level sequence name; [PENDING E16: records dropped per rule] |
| Absence data | None; non-detection survey sites stand in (target group) |
| Background data | Every other survey site in the accessible area (500 km around the detection sites), each counted once (Phillips et al. 2009); up to 10,000 per taxon, above that a simple random sample without replacement seeded from the record fingerprint, so a refit draws the same sites. Effort is a predictor for the tree models, never a weight. |
| Errors and biases | Spatially clustered effort (six states/provinces 61% of records); identification errors limited by DNA validation (E7b sensitivity); coordinate error handled by the 1 km / 5 km rules (E7c) |

### Data partitioning

| Element | Entry |
|---|---|
| Training | All folds but one, per outer fold |
| Validation | Inner spatial folds (3) within the training folds, for tuning only |
| Test | Outer spatial blocks (5 folds; blockCV range of detections, 50–300 km); small taxa 3 folds of 100 km blocks. Independent tests: the hindcast (records first validated after 2026-08-17, E2) and prospective tracking (E3) |

### Predictors

| Element | Entry |
|---|---|
| Names | 69 bands in 8 layers: bioclim bio1–19 (19); elevation (1); terrain: slope, roughness (2); soil 0–5 cm: pH, SOC, N, clay, sand, CEC (6); land cover: trees, shrubs, grassland, wetland, water, built (6); forest type: needleleaf, broadleaf, mixed, known (4); hosts: conifer share + 19 genera + host_known (21); decay hosts: Acer, Fraxinus, Ulmus, Juniperus, Thuja, Liriodendron, Prunus, Liquidambar, Platanus, Robinia (10). Plus log effort for the tree models. [CHECK: the frozen layer manifest's sha256] |
| Sources | WorldClim 2.1; SoilGrids 2.0; ESA WorldCover; BIGMAP (US) and Canadian NFI kNN; NALCMS 2020, Copernicus Global Land Cover 2019 (Hawaii, Caribbean) |
| Spatial extent and resolution | North America on the 5 km grid; sources cropped, reprojected and averaged (never interpolated); gaps filled from neighbours within 10 km |
| Projection | North America Albers Equal Area Conic |
| Temporal extent | Climate 1970–2000; inventories 2011 (Canada) and 2018 (US); land cover 2019–2021 |
| Processing | Averaging per cell; sea level filled as 0 before slope; host shares 0 with a "not mapped" flag outside the inventories |
| Errors | Inventories are themselves models; no host data for Alaska, Hawaii, Puerto Rico and Mexico |
| Dimension reduction | Maxent and ESM: pruning at \|r\| ≥ 0.7 on non-detection sites in a fixed ecological order (soil pH first; host trees after pH for ectomycorrhizal genera per FungalTraits), host allowance (⅓ ECM, ⅕ others), cap of one predictor per four detection sites; tree models take all predictors |

## Model

| Element | Entry |
|---|---|
| Variable pre-selection | As above |
| Multicollinearity | Pruning at \|r\| ≥ 0.7 (Maxent, ESM) |
| Model settings | Maxent: feature classes lq or lqh, regularisation multiplier 0.25–4 (tuned), cloglog, clamped, no effort; RF: 250 probability trees, down-sampled, mtry 2/√p/p⁄3 (tuned), effort as predictor held at the detection-site median; xgboost: depth 2/3/5 (tuned), learning rate 0.05, rounds by early stopping, effort as for RF; ESM: every pair of the first 10 predictors, quadratic, penalised (λ 0.01), weighted by inner-fold skill |
| Model estimates | Permutation importance on held-out folds, per predictor and layer group |
| Model selection, averaging | Nested spatial CV picks settings; combined map = rank average of strong models weighted by AUC − 0.5, with a disagreement layer |
| Non-independence | Spatial blocking; survey-site thinning; target-group background; structured null test |
| Threshold selection | None for maps (ranks); state verdicts use the 10th-percentile training-presence threshold; "what could grow here" uses rank ≥ 50 |

## Assessment

| Element | Entry |
|---|---|
| Performance statistics | Blocked AUC against non-detection sites; continuous Boyce index pooled over folds; independent tests (E2, E3): rank, top half, top tenth, Boyce, beats-effort |
| Plausibility | Null test against 99 shift nulls (sequential stop at 5), pass = p ≤ 0.05 and Boyce > 0 → grade strong/weak/failed; calibrated on virtual species (E1); area of applicability (Meyer & Pebesma 2021); per-taxon response and importance pages |

## Prediction

| Element | Entry |
|---|---|
| Output | Suitability rasters (raw), maps coloured by rank inside the area of applicability, area-of-applicability dissimilarity, combined maps and disagreement, full-extent projection for strong maps, state verdicts, a 20 km location prior |
| Uncertainty | Grade and map strength; area of applicability (hatched outside); disagreement between strong models; [PENDING: E10 inside vs outside AOA] |
