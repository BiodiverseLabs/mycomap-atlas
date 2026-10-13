# MycoMap Atlas: habitat-suitability maps with a calibrated trust grade for thousands of DNA-defined North American fungi

*Working title. Living draft, version 0.2 (2026-10-13). Skeleton: headings,
the claims, the figures and tables each claim needs, and what is pending.
Methods prose is drafted from the public Methods page; Results wait for the
frozen release.*

| | |
|---|---|
| Author | Russell, Stephen D. (sole and corresponding author, as on the Zenodo records) |
| Target venue | [PENDING: top five being checked (Appendix B); Steve decides] |
| Paper type | One combined methods and data paper (Steve, 2026-10-13) |
| Frozen release | [PENDING: the first complete release after the October 2026 rebuild; id, Zenodo DOI, code commit] |
| Code | github.com/BiodiverseLabs/mycomap-atlas, GPL-3.0-or-later |
| Maps | atlas.mycomap.org, CC BY-SA 4.0 |

---

## Core claims

The paper makes four claims. Every figure and table below serves one of them.

1. **C1. Standard null tests cannot tell habitat from clustered collecting;
   spatially structured nulls can.** On virtual species collected at
   MycoMap's real survey sites, nulls scattered site by site passed 73.5% of
   species whose finds followed no habitat at all (power 80%). Nulls that keep
   the finds' own clustering (rotated and shifted together) passed 2.0% of
   them, at 26% power. [pre-freeze; E1, E1b]
2. **C2. The grade predicts how a map does on data it never saw.** Records
   validated after the training cut, and after each release, fall on
   higher-ranked ground on strong maps than on weak or failed ones, and strong
   maps beat a collecting-effort baseline. [PENDING E2, E3, E6]
3. **C3. Naming taxa by DNA changes the maps.** Labelling by the approved
   sequence rather than the record's own name moves several thousand records
   between taxa, about half the modellable taxa have no formal name, and maps
   from morphology-named records differ from DNA-defined ones on the same
   independent test. [PENDING E9, E6c, E16]
4. **C4. An automated, nightly, open pipeline can do this at continental
   scale.** N taxa, M maps, of which S are strong; every map versioned,
   citable and reproducible from a pinned container and archived data.
   [PENDING E16, E12]

Secondary: ensembles of small models give maps from 3 sites with labels that
say how little such a map can claim (E7a, E18); host trees and soil pH matter
most for ectomycorrhizal fungi, climate for the rest (E8).

---

## Abstract

[PENDING: write last. ~250–350 words depending on venue. Shape: problem
(fungal names unreliable, records clustered, automated SDMs give no honest
trust measure) → what we built (DNA-defined taxa, target-group survey sites,
four learners, nested spatial CV, structured nulls, AOA) → C1 numbers → C2
numbers → C3 numbers → resource (N taxa, S strong, nightly, open, DOI).]

---

## 1. Introduction

[PENDING: ~900–1,200 words. Paragraph plan:]

1. **Fungi are missing from distribution maps.** Most fungal species have no
   map, and the ones that do rest on herbarium and photo names. [CHECK: cite
   a fungal SDM review and the fungal conservation-assessment gap (IUCN
   fungal assessments).]
2. **Names are the first problem.** Morphological names lump cryptic species
   and split one species across regions; DNA barcoding by community
   scientists now produces sequenced, georeferenced collections at scale
   (MycoMap's sequencing network, FunDiS [CHECK]), many under provisional
   names that are clusters of sequences, not ranges.
3. **Clustered collecting is the second.** Records concentrate where
   collectors and sequencers live (here six states and provinces hold 61% of
   records). Target-group backgrounds (Phillips et al. 2009) and spatial
   blocking (Roberts et al. 2017; Valavi et al. 2019) address part of it.
4. **Automated SDM at scale has no honest trust measure.** Atlases that fit
   thousands of models report AUC, which spatial clustering inflates and
   which pseudo-predictors made from paintings can match (Fourcade et al.
   2018, Glob. Ecol. Biogeogr. 27:245–256). Null models (Raes & ter Steege
   2007) are the standard check, but scattered nulls inherit none of the
   clustering. Spatially structured nulls were argued for in macroecology
   (Beale et al. 2008, PNAS 105:14908–14912), and contested as too strict
   because shifted patterns keep the environment's own autocorrelation
   (Araújo et al. 2009; Peterson et al. 2009; reply Beale et al. 2009, PNAS
   106:E41–E43) [CHECK: the two 2009 letters' citations]. Environment-based
   models also need to beat spatial interpolation (Bahn & McGill 2007, Glob.
   Ecol. Biogeogr. 16:733–742).
5. **What this paper does.** C1–C4 in a sentence each, and what the resource
   offers (maps, grades, API, releases).

---

## 2. Materials and methods

*Drafted from the public Methods page (atlas.mycomap.org/methods). Numbers in
this section that describe the data are re-read from the frozen release
before submission. ODMAP protocol in Supplement S1 (E17).*

### 2.1 Records and DNA-defined taxa

A record trains a model only when its name is confirmed by DNA: it is marked
correct in at least one MycoMap validation project after its sequence was
compared with reference data, whatever another project said [CHECK: describe
the validation workflow and who validates, briefly, with a reference to
mycomap.org documentation]. Photo identifications, herbarium names and
unassessed records are excluded. Records come from iNaturalist, Mushroom
Observer, MyCoPortal and MycoMap's own sequence and GenBank imports, all held
on mycomap.org.

The name is the one on the record's approved sequences, not the record's own
name, which is often not updated after the sequence is named. A record whose
approved sequences name two species, name only a genus, or that has no
approved named sequence, is excluded (E9 measures what this changes).
Provisional names (DNA clusters without a formal name, e.g. *Mycena* sp.
'IN10') count as taxa; spelling, punctuation, author-citation and rank-word
variants are merged before modelling [CHECK: final merge counts from the
frozen pull].

Coordinates must be present and not obscured, accurate to 1 km where an
accuracy was recorded, and in the United States, Canada, Mexico, Puerto Rico
or the US Virgin Islands. Mushroom Observer records need a GPS point the
observer shows, or a named location whose centre is within 5 km of all of
it; MyCoPortal records need MyCoPortal's own coordinates accurate to 5 km, or
a locality that is not a shared county or state centroid. [PENDING E16: the
records kept and dropped by each rule, by source.]

Each taxon's record set is hashed into a fingerprint. A model belongs to its
record set, not its name: it is refitted when the fingerprint changes, and a
provisional name can be renamed or re-clustered without leaving a stale map.

[PENDING E16: Table 1, records and taxa by source; Figure 2, where records
are (0.1° cells) and how they cluster.]

### 2.2 Study region, grid and predictors

Everything is modelled on a North America Albers Equal Area Conic grid at
5 km (draft) and 1 km (production), with nesting cells. [CHECK: which grid
the frozen release uses; at the time of writing releases are 5 km.]

Seventy-five predictors in eight groups (Table 2): 19 WorldClim 2.1
bioclimatic variables (1970–2000) and elevation (Fick & Hijmans 2017); slope
and roughness derived on the grid; topsoil (0–5 cm) pH, organic carbon, total
nitrogen, clay, sand and cation exchange capacity from SoilGrids 2.0 (Poggio
et al. 2021); land-cover fractions from ESA WorldCover (Zanaga et al. 2021);
the share of a cell's trees in each of 35 host genera, from BIGMAP (United
States) and the Canadian National Forest Inventory kNN maps (Beaudoin et al.
2014), with a flag where neither inventory reaches (Alaska, Hawaii, Puerto
Rico, Mexico); and needleleaf, broadleaf and mixed forest shares from NALCMS,
filled from Copernicus Global Land Cover on Hawaii and the Caribbean.
[CHECK: the BIGMAP citation, NALCMS and Copernicus citations, and the final
predictor count in the frozen layer manifest.]

Sources are cropped, reprojected and averaged onto the grid (never
interpolated); land cells left empty are filled from neighbours within
10 km. Candidate layers (water balance, bedrock, landform, ClimateNA
1991–2020 normals, single tree species) were built and tested in paired
layer sweeps and not adopted (Supplement S3; E8).

### 2.3 Survey sites, target-group background and effort

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

### 2.4 Predictor selection

For Maxent and the small-model ensembles, predictors correlated at |r| ≥ 0.7
on non-detection sites are pruned, keeping the earlier one in a fixed
ecological order (soil pH first; host trees second for ectomycorrhizal genera
per FungalTraits, Põlme et al. 2020), with an allowance for host-tree bands
and a cap of one predictor per four detection sites (set by a 153-taxon sweep
[pre-freeze]). The tree models receive all predictors.

### 2.5 Models and evaluation

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

### 2.6 The null test and the grade

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

### 2.7 Calibrating the null test on virtual species

Virtual species are given a habitat (a response to two or three real
predictors, always one climate driver) and then "collected" at MycoMap's real
survey sites: each real record at a site is the virtual species with a
probability proportional to the habitat there. *Geography* species instead
follow distance from one or two centres and ignore the environment, so any
pass is a false pass. Each species goes through the production training
table, folds, fits and null test. False-pass rate = share of geography
species passing; power = share of habitat species passing; both with Wilson
95% intervals, by site band and null design. [pre-freeze: 99 species, Maxent
only; PENDING E1 rerun on the frozen pull with more species and all learners.]

### 2.8 Area of applicability, maps and combined maps

Each model has an area of applicability (Meyer & Pebesma 2021), from
importance-weighted standardised distances to training sites with the
cross-validation threshold; cells outside are hatched and unranked. Maps are
coloured by rank within the area of applicability. Strong maps are also
projected over North America on the same scale ("potential, not range"),
with the AOA computed over the full extent. When two or more of a taxon's
models are strong, they are averaged by rank, weighted by AUC − 0.5, with a
disagreement layer.

### 2.9 Independent validation

- **Hindcast (E2).** The full pipeline, null tests included, is rerun on the
  records first validated on or before a cutoff date; records first
  validated after it are scored on those maps at their own cells.
- **Prospective tracking (E3).** Each day, records first validated that day
  are scored on the release live when the day began. Atlas trains only on
  validated records, so no find can have trained the map it is scored on.
- **Scores.** Each find's rank on the map (0–1; chance puts half in the top
  half); the share in the top half and top tenth; Boyce; and "beats effort":
  the find's rank compared with the ranks of the cells where every other
  taxon's finds landed in the same period, so 50% is no better than knowing
  where people collect. Finds outside the AOA or beyond reach are counted
  apart. Several finds of one taxon in one 5 km cell count once. Results by
  grade, by new site (> 5 km from the taxon's known records) and by distance.
- **Presence–absence (E4).** [PENDING feasibility: soil and eDNA samples from
  GlobalFungi (Větrovský et al. 2020) and MycoMap's own soil cores, matched
  to Atlas taxa through UNITE species hypotheses; eDNA never trains a model.]

### 2.10 Baseline comparisons

[PENDING E6: (a) "default practice" Maxent: random background over North
America, random 5-fold CV, default settings; (b) a spatial-only model
(distance to known sites; Bahn & McGill 2007); (c) Maxent on
morphology-named GBIF records of the same formally named species; (d)
optionally a biomod2-style default ensemble. All scored on the E2/E3
independent finds, alongside the cross-validation scores each approach
reports for itself.]

### 2.11 Releases, nightly rebuilds and reproducibility

A Lightsail server pulls eligible records nightly, refits only taxa whose
fingerprint or settings changed on EC2 spot workers in one pinned container
(base image by digest, R packages from a dated snapshot), and publishes a
content-addressed release recording the code commit, package versions, layer
builds and pull fingerprint. Seeds come from the fingerprint. Releases are
archived on Zenodo (layers and models series, CC BY-SA 4.0). Exact
coordinates never leave Atlas's private compute and storage; everything
published is 1 km or coarser, and records are drawn as 0.1° cells, the same
for every taxon. [PENDING E12: rerun a sample of taxa from the frozen pull
and compare hashes.]

---

## 3. Results

*Everything here is pending the frozen release. Each subsection names its
figure or table and the analysis that fills it.*

### 3.1 The records and the taxa (E16)

[PENDING: records and taxa by source; sites per taxon (distribution, with the
3 / 20 / 50 thresholds); share provisional; where records are; validation lag
(median ~8 months [pre-freeze]).] → **Figure 2**, **Table 1**.

### 3.2 Calibrating the null test (E1, E1b)

[pre-freeze, E1b re-read of the 2026-10-06 study: 49 geography and 50
habitat species, Maxent, Wilson 95% intervals. PENDING E1 rerun.]

| Sites | Scatter false pass | Shift false pass | Scatter power | Shift power |
|---|---|---|---|---|
| 20–29 | 1/6 | 0/6 | 3/7 | 0/7 |
| 30–49 | 9/15 | 1/15 | 13/15 | 5/15 |
| 50–99 | 8/10 | 0/10 | 10/12 | 5/12 |
| 100–199 | 11/11 | 0/11 | 9/11 | 2/11 |
| 200+ | 7/7 | 0/7 | 5/5 | 1/5 |
| All | 36/49 = 73% (60–84) | 1/49 = 2% (0–11) | 40/50 = 80% (67–89) | 13/50 = 26% (16–40) |

Scattered nulls pass every habitat-free species from 100 sites up, so with
them a pass says more about record count than habitat. Shifted nulls hold
false passes near zero in every band, but their power does not rise with
sites (2/11 and 1/5 above 100), which the rerun must explain: a widespread
habitat that is itself spatially smooth may survive a shift [E1: stratify by
habitat breadth]. Habitat species that passed the shift test had maps closer
to the true habitat (median Spearman ρ 0.83 vs 0.73 for those that did not),
a first sign that the grade selects better maps (C2). Early stopping drew a
mean of 29 shifted nulls per species instead of 99. Shift-effort nulls
matched shift (2/49 false, 13/50 power). → **Figure 3**.

### 3.3 What the atlas contains (E16)

[PENDING: models, maps and taxa by grade × learner × site band; strong maps
by guild and region; how many taxa have a strong map; combined maps; share
of reach inside AOA.] → **Table 3**, **Figure 4** (example maps across grades).

### 3.4 How the maps did on records they never saw (E2, E3, E15)

[PENDING: rank of hindcast and prospective finds by grade; top half / top
tenth / Boyce / beats-effort with intervals; new sites vs near known sites;
inside vs outside AOA; combined vs single maps.] → **Figure 5**.

### 3.5 Against standard practice (E6)

[PENDING: self-reported CV score vs independent-test score for each
approach.] → **Figure 6**.

### 3.6 What DNA names change (E9, E6c)

[PENDING: records whose sequence name differs from the record name (species,
genus) by source; for affected taxa, map rank correlation, grade changes and
independent-test skill under each labelling.] → **Figure 7**.

### 3.7 What drives the maps (E8)

[PENDING: permutation importance by predictor group, ectomycorrhizal vs other
guilds, strong maps only; layer-sweep results in S3.] → **Figure 8**.

### 3.8 Stability across nightly releases (E11)

[PENDING: map rank correlation and grade changes between releases against the
number of new records.] → Supplement S4 or main text if striking.

---

## 4. The data resource

*A combined paper carries what a data descriptor would: what is deposited,
how it was checked, and how to use it. Technical validation is Results 3.2–3.5
plus E12.*

### 4.1 Data records (E12, E19)

[PENDING: one table of every deposited file of the frozen release, with
Zenodo DOI, format, size and licence:]

- **Layers series** (Zenodo): the predictor rasters on the grid, with their
  sources. CC BY-SA 4.0 (WorldClim is share-alike).
- **Models series** (Zenodo, one version per archived release): per model the
  suitability raster, AOA dissimilarity raster, map image and metrics JSON
  (scores, null test, grade, importance, settings); combined maps and
  disagreement layers; full-extent rasters for strong models; per-taxon
  counts; record cells at 0.1°; state verdicts; the location prior.
  CC BY-SA 4.0.
- **Training records** (new; Steve, 2026-10-13): the ids of every record that
  trained the frozen release, with source (iNaturalist, Mushroom Observer,
  MyCoPortal, GenBank, MycoMap sequence), the DNA name used, the sequence it
  came from, the taxon fingerprint and survey-site membership, but no
  coordinates. Each id resolves to its public source page, which shows what
  the source itself shows (obscured iNaturalist records are not used).
  [CHECK: licence of this table, CC0 proposed.]
- **Code**: the repository at the release commit, with a Zenodo software
  DOI, and the container image digest.

### 4.2 Versions

The paper cites one frozen release by id and DOI. The live atlas keeps
rebuilding nightly; every release stays in the content-addressed store, and
archived ones keep their Zenodo DOIs, so later maps never overwrite the
paper's.

### 4.3 Usage notes

[PENDING: how to read a grade; use strong maps only for claims; suitability
is not occurrence; AOA hatching; ranks are within-taxon; the API (best-map,
maps/best, prior; rate limits); citing a release; reusing CC BY-SA maps; how
to report a problem.]

---

## 5. Discussion

[PENDING. Paragraph plan:]

1. What a grade means and does not: strong = beats its own collecting pattern
   on held-out ground; weak and failed maps are not shown to be wrong; low
   power (C1) means many real signals are left unclaimed; that is the price
   of an honest claim. Engage the Beale–Araújo–Peterson debate directly: our
   virtual species measure both error rates where the truth is known, which
   that debate could not, and E1 tests whether the flat power comes from
   smooth, broad habitats surviving a shift.
2. Implications for other automated SDM atlases and for null tests in SDM
   generally (scattered nulls with clustered target-group data).
3. Fungi: DNA-defined and provisional taxa as mappable units; what the drivers
   say by guild; the value of community sequencing for map coverage (each new
   site moves a taxon toward a map).
4. Limits: suitability, not occurrence; no true absences (until E4); host
   layers stop at national inventories; 1970–2000 climate; provisional names
   can be re-clustered; the maps can only be as good as where people collect
   and sequence. Hindcast fairness (E2): the hindcast uses today's
   validation state, names and coordinates for pre-cutoff records, and the
   design (layers, tuning grid, null design) was chosen on data that include
   post-cutoff records [PENDING: the rebuild lane's list of such items].
5. What comes next: eDNA as an independent test and in integrated models,
   1 km releases, climate projections, survey guidance.

---

## 6. Data, code and AI-use statements

- **Data availability.** Layers, models and the training-record ids of the
  frozen release on Zenodo (section 4.1, DOIs pending). Exact coordinates
  are not redistributed; each record's public coordinates are at its source.
  [CHECK: wording against the chosen journal's policy; GEB, Ecography and
  Scientific Data restrict data licences to CC BY or CC0, Appendix B.]
- **Code availability.** GitHub repository (GPL-3.0-or-later) and a Zenodo
  software DOI for the commit of the frozen release [PENDING].
- **Generative AI.** [PENDING: the declaration the chosen journal requires.
  Much of the pipeline's code and this draft were written with an AI
  assistant (Claude, Anthropic) under the author's direction and review; AI is
  not an author. Wording to match the venue's policy.]
- **Author contributions** (CRediT): sole author. **Acknowledgements**
  (collectors, validators, the sequencing network, data providers)
  [PENDING: whether a contributor list or consortium acknowledgement is
  wanted; to raise with Steve, not to add unasked].

---

## Figures and tables

| # | Content | Claim | Source |
|---|---|---|---|
| Fig 1 | Pipeline: records → DNA names → survey sites → models → nulls → grade → AOA → release | all | schematic |
| Fig 2 | Records as 0.1° cells; sites per taxon; provisional share | C3, C4 | E16 |
| Fig 3 | False-pass rate and power by null design × site band (virtual species), with an inset of scatter vs shift nulls | C1 | E1 |
| Fig 4 | Example maps: strong ECM, strong saprotroph, weak, small-site ESM; AOA hatching; disagreement layer | C2, C4 | release |
| Fig 5 | Independent finds by grade: rank distributions, top half/top tenth, beats-effort, new sites | C2 | E2, E3 |
| Fig 6 | Self-reported vs independent skill for Atlas and baselines | C1, C2 | E6 |
| Fig 7 | Sequence-name vs record-name maps and skill | C3 | E9 |
| Fig 8 | Predictor-group importance by guild | secondary | E8 |
| Table 1 | Records and taxa by source and rule | C4 | E16 |
| Table 2 | Predictors and sources | methods | layer manifest |
| Table 3 | Models and maps by grade × learner × site band | C2, C4 | release |
| Table 4 | Evidence summary: each claim, its tests, the result | all | |

Supplements: S1 ODMAP protocol (Zurell et al. 2020); S2 virtual-species
design; S3 layer and predictor sweeps; S4 sensitivity analyses (E7) and
stability (E11); S5 small-site maps; S6 reproducibility (E12).

---

## Appendix A. Evidence plan

What a reviewer in species distribution modelling and in mycology will
expect, what exists, and what is to run. Priority: **P1** a core claim
depends on it, or reviewers will certainly ask; **P2** strengthens a claim or
answers a likely question; **P3** supplementary. Costs are estimates to be
confirmed by the rebuild lane; EC2 spot runs at roughly $0.05 per CPU-hour.
Steve set the compute budget on 2026-10-13: run each analysis at the size
its claim needs, not the cheapest. Every analysis runs on the frozen release
and its pull, and gets an entry in
the experiment registry (`docs/experiments/`, one file per run: question,
data, command, result, release, commit).

| ID | Analysis | Claim | Exists? | Data / method | Cost / time | Priority |
|---|---|---|---|---|---|---|
| E16 | Records, taxa, sites, provisional share, sampling bias, validation lag | C3, C4 | Partly (counts in memory and Methods page) | Frozen pull + release index; read-only | 1–2 days, no compute | P1 |
| E1b | Re-read the existing null study by site band | C1 | **Done 2026-10-13** (`docs/experiments/2026-10-13-null-calibration-by-band.md`): see 3.2 | 2026-10-06 virtual-species results file | read-only | P1 |
| E1 | Null calibration rerun: false pass and power by design × site band × habitat breadth × learner (Maxent, RF, ESM); map-to-truth ρ by grade | C1, C2 | Pre-freeze: 99 species, Maxent, 3 designs; power flat with sites (E1b) | `study-virtual` on the frozen pull and layers. Full models: 5 site bands × 2 habitat-breadth strata × 2 kinds × 40 species = 800 species, Maxent and RF, scatter and shift nulls ×99, stop at 5. ESM: 3 bands (3–4, 5–9, 10–19) × 2 kinds × 60 = 360 species. Effort arms (E14) on the same species. Wilson CIs ≈ ±8–11 points per band | est. 1,000–1,500 CPU-h ($50–75), ~12 h wall on 4 workers | P1 |
| E2 | Hindcast: full graded job on records first validated ≤ 2026-08-17; score later finds by grade, new vs known places | C2 | **Approved 2026-10-13**: Vision's training run becomes this full graded job (nulls on, private never-promotable release); code ~1–1.5 days in the rebuild lane, after the full-view refresh | Cutoff-filtered pull; test set = first green > cutoff (optionally observed > cutoff); undated records dated or excluded, with a count | ~250–500 CPU-h ($10–25), runs after the cutover on Steve's go | P1 |
| E3 | Prospective tracker by grade | C2 | Built; ships at the rebuild cutover; backfill from 2026-10-03 | Daily scoring of new finds on the live release | ~0 compute; needs months of finds (3–6) | P1 (clock starts at cutover) |
| E9 | Sequence names vs record names: refit affected taxa both ways | C3 | Counts yes (4,878 records with a different species or genus; ~1,435 taxa with ≥10 localities change) [pre-freeze]; refits no | Production (sequence names) is the frozen release; refit every taxon whose record set differs under record names (full graded fits, all learners); map Spearman and Schoener's D, grade changes, E2/E3 skill | est. 150–300 CPU-h ($8–15), 2–3 days | P1 |
| E6a | Default-practice Maxent (random background over the accessible area, random 5-fold CV, default maxnet settings, 19 scattered nulls as commonly run) | C1, C2 | No | New study arm over every taxon with ≥20 sites; its own CV score and pass rate vs its score on E2/E3 finds | est. ~200 CPU-h ($10), ~3 days code | P1 |
| E6b | Spatial-only baseline (distance to known sites) | C2 | No (shift nulls are related but not a baseline) | Kernel/distance model on the same sites; E2/E3 finds | small compute, ~2 days | P1 |
| E12 | Reproducibility: rerun a random sample of taxa from the frozen pull, compare metrics and raster hashes; Zenodo DOIs for layers, models, code | C4 | Machinery yes (fingerprints, pinned image, content-addressed store, Zenodo sandbox tested); demo no; layers deposit held | Fresh worker, 20–50 taxa | ~10 CPU-h, 1 day | P1 |
| E17 | ODMAP protocol | all | No | Writing from Methods + code | 1–2 days | P1 |
| E4 | Presence–absence test: GlobalFungi + MycoMap soil cores, by UNITE species hypothesis | C2 | No | Feasibility first: how many Atlas taxa map 1:1 to an SH with enough North American samples | Feasibility 2–3 days; full 1–2 weeks; small compute | P1 feasibility, P2 full |
| E6c | Morphology-named GBIF Maxent for formally named species, scored on DNA-defined finds | C3 | No | GBIF download with DOI; name matching; same pipeline | ~100 CPU-h, ~1 week | P2 |
| E7 | Sensitivity: (a) site count (thinning study), (b) validation level (≥1 vs ≥2 projects; contested records), (c) coordinate precision (1 vs 5 km; MO/MyCoPortal rules), (d) pre-1980 records | C2, C4 | (a) pre-freeze, 118 taxa, old nulls; (b–d) no | Paired arms on a stratified ~150-taxon panel; skill, map correlation, grade changes | ~20–40 CPU-h per arm, ~1 week | P2 |
| E8 | Variable and layer importance by guild | secondary | Yes in every model's metrics; layer sweeps pre-freeze | Aggregate over strong maps from the release | ~1 day, read-only | P2 |
| E10 | AOA and extrapolation: share of reach inside AOA; finds inside vs outside | C2 | Partly (per-model applicability; tracker counts outside-AOA finds) | Release + E2/E3 | ~1 day | P2 |
| E11 | Stability across nightly releases | C4 | No; releases are kept indefinitely | Per-taxon rank correlation and grade flips vs new records | ~2 days code, ≥4 weeks of nightlies | P2 |
| E14 | Effort handling on virtual species | methods | Pre-freeze, 198 species | Rerun inside E1 | inside E1 | P2 |
| E15 | Combined map vs its members on independent finds | C2 | No | From E2/E3 | hours, after E2 | P2 |
| E18 | Small-site maps: grades and power at 3–19 sites | secondary | Pre-freeze (thinning study; first-build pass rates) | Inside E1 + E7a | inside E1 | P2 |
| E5 | Expert and checklist comparison: state verdicts vs independent checklists; expert ranges for ~20 well-known taxa | C2 | No | Curated panel; expert time | 1–2 weeks, mostly expert time | P3 (P2 if a reviewer-friendly panel exists) |
| E6d | biomod2-style default ensemble | C2 | No | Same sites | ~1 week | P3 |
| E13 | Block-size check (kNNDM-style distance matching) | methods | Pre-freeze, 153 taxa | Rerun `study-blocks` | ~10 CPU-h | P3 |

**Order (set with the Atlas coordinator, 2026-10-13):** nothing before the
cutover → the full-view refresh → E2 (hindcast code, then the run) → E1 →
E9 → E6a/b (new study arms, queued with the rebuild lane after the hindcast
code) → E12 → E7, E6c, E4 full. Each launch gets Steve's direct go. E1b is
done; E16 is read-only; E3 needs only time from the cutover.

| ID | Also needed for a combined paper | Priority |
|---|---|---|
| E19 | Training-record table for the frozen release (ids, source, DNA name, sequence, fingerprint; no coordinates) and its Zenodo record | P1 |
| E20 | Data-records table and usage notes (section 4) | P1 |

---

## Appendix B. Venue

Facts read on each journal's own author pages on 2026-10-12, except where
marked. JIF and median days to first decision are from each journal's home
page. Steve decides.

| | Methods in Ecology and Evolution | Ecography | Global Ecology and Biogeography | Diversity and Distributions | Scientific Data |
|---|---|---|---|---|---|
| Type for us | Research Article (or Workflow) | Original Research Paper | Method | Method | Data Descriptor |
| Words | 7,000–8,000 **including** references, captions, tables | ≤ 5,000 main text | ~10 printed pages (~5,000 words, ~50 refs) | ≤ 6,000 main text | no limit; no results or discussion allowed |
| Abstract | ≤ 350, numbered paragraphs 1–4 | ≤ 300 | ≤ 300, Aim / Innovation / Main conclusions | ≤ 300, structured | ≤ 170, unstructured |
| Figures + tables | no limit stated | ≤ 6 display items | 6–8 | no limit stated | ≤ 8 figs, ≤ 10 tables recommended |
| Data | public archive with DOI, every result recreatable; anonymised for review | Zenodo/Dryad DOI at acceptance; anonymised for review | public repository, not GitHub; **data licence CC0 or CC BY only** | mandatory, no embargo, no "on request" | **CC0 or CC BY only** (an exception for share-alike forced by inputs); static DOI'd version |
| Code | available to reviewers, public at acceptance, DOI recommended | archived with DOI | archived | mandatory for new methods | available, with DOI |
| Generative AI | not an author; describe use in Methods with tool name and version; mark LLM-written code | not an author; AI statement for any content use incl. code | Wiley policy: Methods/Acknowledgements disclosure | not an author; Methods or Acknowledgements | not an author; document in Methods |
| Preprint | allowed | allowed | allowed (non-commercial server) | allowed (non-commercial server) | allowed |
| Access, APC | gold OA, US$3,500 (20% off for BES members; waivers on request) | gold OA, US$3,190 | hybrid: free route, or OA US$5,250 | gold OA, US$4,150 (waiver if unfunded) | gold OA, US$2,690 |
| Review | double-anonymous | double-anonymous | double-anonymous | double-anonymous | technical soundness, not impact |
| JIF / first decision | 5.7 / 15 days | 5.3 / 8 days | 6.5 / 12 days | 4.2 / 11 days | 7.2 / 11 days |
| Fit | best for C1–C2 as a general method, simulations first; "workflows that link existing methods" are not new methods | good, but 6 display items is tight for 8 figures | good for critical evaluation; desk-rejects many | needs a conservation-implications section | the data paper, later |

Mycology venues checked too: IMA Fungus (Pensoft; gold OA, €1,950 up to 20
pages; AI declared in Methods; no word limit) and Fungal Ecology (Elsevier,
hybrid, OA US$3,600; guide not readable, so limits not confirmed). Both reach
mycologists but not SDM methodologists. Mycologia (checked 2026-10-08 for the
Vision paper): no word limit found, AI declaration required, OA US$3,940.

**Licence conflict.** Atlas maps are CC BY-SA 4.0 because WorldClim, an
input, is share-alike. Scientific Data and GEB accept only CC0 or CC BY for
deposited data (Scientific Data allows share-alike forced by third-party
inputs), and Ecography asks for repositories no more restrictive than CC BY.
MEE and Diversity and Distributions state no data-licence rule.

**Recommendation: Methods in Ecology and Evolution, Research Article.**
Frame C1 and C2 as a general method (structured null tests that grade
automatically built SDMs, calibrated on virtual species and validated on
independent finds), with the fungal atlas as its application. Simulations
come first, as MEE asks. MEE counts references and captions in its
7,000–8,000 words, so C3 (DNA names) is kept to one results section and the
mycology goes to a second paper. Its double-anonymous review needs an
anonymised code and data link at submission. Second choice: Ecography (main
text ≤ 5,000 words, 6 display items). Later: a Scientific Data descriptor of
a frozen release, arguing the share-alike exception, and a mycology results
paper (drivers by guild, provisional taxa; Mycologia or IMA Fungus) that also
cites MycoMap Vision.

---

## Open decisions

Settled 2026-10-13 (Steve): one combined methods and data paper; sole
author, Russell, Stephen D.; training-record ids public; compute at the size
the claims need.

1. **Venue:** top five being checked (Appendix B).
2. **Frozen release:** the rebuild's release, or its successor if the
   strong-only full-view refresh runs (default maps, grades and ranks
   byte-identical; only full-extent files change). The coordinator confirms.
3. **Acknowledgements:** whether to list contributors and collectors.

---

## Changelog

- **0.2 (2026-10-13).** Steve's decisions: combined methods and data paper
  (new section 4, the data resource), sole author, public training-record
  ids, budget at the size the claims need (E1, E6a, E9 resized). E2 approved
  as the full graded hindcast. Hindcast fairness noted in Discussion.
- **0.1.1 (2026-10-13).** Appendix B venue facts and recommendation; E1b
  results in 3.2; null-model debate references in the Introduction.
- **0.1 (2026-10-13).** Skeleton: core claims, outline, figure and table
  plan, methods drafted from the Methods page, evidence plan, open decisions.
