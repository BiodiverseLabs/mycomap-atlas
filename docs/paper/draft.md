# MycoMap Atlas: Habitat-suitability maps with a calibrated trust grade for thousands of DNA-defined North American fungi

*Working title (118 characters; the journal allows 120, sentence case, one
colon, no uncommon acronyms). Alternative: "Which habitat maps can be
trusted? Calibrated null tests for thousands of DNA-defined North American
fungi". Living draft, version 0.7 (2026-10-13). Skeleton: headings, the
claims, the figures and tables each claim needs, and what is pending.
Methods prose is drafted from the public Methods page; Results wait for the
frozen release.*

| | |
|---|---|
| Author | Russell, Stephen D. (sole and corresponding author, as on the Zenodo records) |
| Target venue | **Ecological Monographs, Method** (Steve, 2026-10-13, "for now"); fallback MEE + a data descriptor (Appendix B) |
| Paper type | One combined methods and data paper (Steve, 2026-10-13) |
| Frozen release | The finished release of the full-view refresh that follows the October 2026 rebuild (same pull, default maps, grades and ranks as the rebuild; full-extent rasters without the border gaps) [PENDING: id, Zenodo DOIs, code commit]. Zenodo archiving waits for it. |
| Code | github.com/BiodiverseLabs/mycomap-atlas, GPL-3.0-or-later |
| Maps | atlas.mycomap.org, CC BY-SA 4.0 |

---

## Submission format (Ecological Monographs, guidelines revised September 2026)

Read on the journal's author guidelines and ESA's Open Research Policy pages,
2026-10-13.

- **Type and length.** Method: "new technological or analytical
  developments or compare existing methods while providing guidance and
  recommendations for best practices". At least 40 manuscript pages, no
  maximum, counting title page, text, references, tables, captions and
  figures but not supporting information. A presubmission inquiry is
  encouraged: ≤ 300 words, 5–10 references, optionally 1–2 figures, naming
  the type (draft: `presubmission-inquiry.md`).
- **Title page.** Journal, type, title (≤ 120 characters, sentence case, one
  colon at most, no uncommon acronyms), author with affiliation or
  "Independent Researcher, city, state, country", one corresponding email,
  the **Open Research statement**, and 6–12 key words in alphabetical order
  separated by semicolons.
- **Order.** Abstract (≤ 350 words, new page, no citations or URLs) → text →
  Acknowledgments (one paragraph) → Author Contributions → Conflict of
  Interest statement (required) → References (Wiley's Chicago author-date
  style; permanently archived sources only) → tables (each on its own page,
  one-sentence caption, no colour or shading) → figure captions together →
  figures (one per page; colourblind-safe; maps with latitude and longitude,
  north arrow, scale bar and border; 300–600 dpi; text 6–10 pt at 8.5 or
  18 cm width).
- **Layout.** Word (or LaTeX with a PDF), 12-pt Times New Roman,
  double-spaced, continuous line numbers, numbered pages, Letter, 1-inch
  margins, left-aligned. SI units.
- **Supporting information.** Appendices as PDFs named Appendix S1, S2…;
  a single appendix with sections is preferred; each carries its own
  references; items labelled "Appendix S1: Figure S1". Spreadsheets and
  large tables cannot be supporting information; they go to a repository.
- **Open Research (ESA policy).** Novel code must be reachable by reviewers
  at submission (public GitHub is acceptable) and archived with a Zenodo DOI
  at acceptance. Data are strongly encouraged at submission and required in
  a permanent public repository at acceptance, complete enough to replicate
  every table, figure and analysis; no embargo; "available from the author"
  is not allowed. Data from public databases need query details. Repository
  packages must not be named "Appendix S#".
- **AI.** Disclose which tool and how in the section the use concerns, again
  in the Acknowledgments, and on the submission form. AI cannot be an author.
- **Review and preprints.** Usually two anonymous reviewers; author names are
  not hidden. A preprint may be only the version as first submitted,
  declared in the "Dual Publication" field.
- **Cost.** $75 per typeset page on the subscription route (ESA members can
  get grants for up to 21 pages a year in this journal); open access is
  optional at Wiley's price (not confirmed).

---

## Core claims

The paper makes four claims and asks one pre-declared question. Every figure
and table below serves one of them. (Plan revised 2026-10-13, Steve: "fully
revise the paper plan and let's continue".)

1. **C1. The usual null test cannot tell habitat from clustered collecting;
   a structure-keeping null restricted to surveyed sites can, and we measure
   both error rates.** On virtual species collected at MycoMap's real survey
   sites, nulls scattered site by site passed 73.5% of species whose finds
   followed no habitat at all (power 80%), and every such species from 100
   sites up. Nulls that keep the finds' own clustering (rotated and shifted
   together, snapped to surveyed sites) passed 2.0%, at 26% power. Structure-
   keeping nulls are not new (Beale et al. 2008; Osborne et al. 2022; Ridder
   et al. 2024); what is new is their calibration against known truth in a
   target-group design, by sample size, habitat breadth and signal strength,
   and their use to grade thousands of automatically built maps. On the
   atlas's real models, [X]% of the maps a standard test (19 scattered nulls)
   calls good are not shown to beat collecting. [pre-freeze; E1, E1b, E1c]
2. **C2. The grade predicts how a map does on data it never saw.** Records
   validated after the training cut, and after each release, fall on
   higher-ranked ground on strong maps than on weak or failed ones, and strong
   maps beat a collecting-effort baseline. [PENDING E2, E3, E6]
3. **C3. Labelling by the approved sequence rather than the record's own
   name changes the maps, and about half the modellable taxa have no formal
   name.** [PENDING E9, E16] A comparison with morphology-named records
   (GBIF, E6c, P2) is not part of this claim; if it runs, it is a Discussion
   point.
4. **C4. An automated, nightly, open pipeline can do this at continental
   scale, and says which maps to trust.** [N] taxa, [M] maps, of which [S]
   ([S/M]%) are strong. The strong share is stated plainly: most maps are
   weak or failed, and they are still published, drawn faint with their
   grade, because the grade is the contribution, not the map count. Every map
   is versioned, citable and reproducible from a pinned container and
   archived data. [PENDING E16, E12]

**Q1 (pre-declared question, not a claim). Do the maps carry habitat
information another system can use?** The registered test: used as the place
signal for MycoMap Vision's photo identifications, a continent-wide
projection of strong maps, weighted by trust, against no place signal
(species top-1 better overall, and not worse by more than 2% for finds
300–1,500 km from the nearest DNA record). Pre-declared before any result
(Vision repository, `docs/atlas-environment.md`). The outcome is reported
either way, a null result included. Q1 is the first section cut if the
monograph runs long. [PENDING E21, E22]

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

*First prose draft, 2026-10-13 (~1,000 words). Citations are author–year
until the reference list is verified; [CHECK] marks a fact still to source.*

Species distribution models now sit behind conservation assessments, survey
planning and biogeography, and pipelines fit them for thousands of species
at a time (Araújo et al. 2019). Fungi are largely absent from this work.
Most fungal species have never been mapped, and few have been assessed for
extinction risk [CHECK: a source for the fungal assessment gap and a review
of fungal distribution modelling]. Two features of fungal records stand in
the way, and both also affect automated atlases of other groups: the names
are unreliable, and the records are clustered where people collect.

The first is names. Many fungal morphospecies hide several lineages with
different ranges, and one lineage can carry several names in different
regions [CHECK: cite cryptic diversity in macrofungi]. A map fitted to a
morphological name averages over whatever the name covers, and it is
confidently wrong where the lineages part. DNA barcodes resolve many of
these cases [CHECK: ITS barcode reference], and community science now
produces sequenced, georeferenced collections at a continental scale:
volunteers collect and photograph a specimen, a sequencing network reads
its barcode, and validators compare the sequence with reference data before
the record's name is accepted. Many of the lineages found this way have no
formal name yet and carry provisional names that are clusters of sequences
rather than described species. They can be mapped as long as a map belongs
to its set of records rather than to a name that may later change.

The second is clustered collecting. Records concentrate where collectors
and sequencing projects are: in the data used here, six states and
provinces hold 61% of the records and Indiana alone 12%. Two practices
address this when fitting and evaluating a model. A target-group background
compares a species' records with other records collected the same way
(Phillips et al. 2009). Spatially blocked cross-validation scores a model on
whole regions it did not see (Roberts et al. 2017; Valavi et al. 2019).
Neither makes a score absolute. Within a few hundred kilometres of a
cluster of records, almost any smooth predictor separates the cluster from
its background, so a model can score well without learning habitat:
predictors made from paintings matched real environmental layers for many
species (Fourcade et al. 2018). A map's score alone therefore cannot say
whether the map knows anything.

The usual check is a null test: the model is refitted on null species of
randomly drawn occurrences, and its score must beat theirs (Raes & ter
Steege 2007). Null occurrences scattered one by one, however, lose the
clustering the real species has, so under clustered sampling they set a bar
that clustering alone can clear. Null patterns that keep spatial structure
were proposed in macroecology, where they found most bird–climate
associations no better than chance (Beale et al. 2008). That result was
disputed, partly because shifted patterns keep the environment's own
spatial structure and so may be too strict a test (Araújo et al. 2009;
Peterson et al. 2009; Beale et al. 2009). Structure-keeping nulls are now
available for distribution models, as simulated occurrences that keep
within- and between-species structure (Osborne et al. 2022) and as
environmental layers shifted and rotated under the sampling area (Ridder et
al. 2024). What is still missing is a measurement of how often each kind of
null test passes a species with no habitat signal, and how often it passes
one with a signal, under realistic target-group sampling. Without those two
error rates an atlas cannot say how far to trust a map that passed, and none
of the large automated atlases grades its maps this way [CHECK: confirm for
the main existing atlases]. A habitat model should also beat a model that
knows only how far a place is from known records (Bahn & McGill 2007).

This paper describes MycoMap Atlas, which maps every North American fungus
defined by DNA with enough sites to fit a model, from validated
community-science collections, and rebuilds the maps every night. Its
central method is a calibrated trust grade. We make four claims. First
(C1), on virtual species collected at the atlas's real survey sites, the
usual scattered null test passes most species that follow no habitat at
all, while a null that keeps each species' clustering and stays on surveyed
sites holds false passes near the nominal rate, at a measured cost in power.
Second (C2), the grade this test gives each map (strong, weak or failed)
predicts how the map ranks records validated after it was made. Third (C3),
labelling records by their approved sequence rather than by the record's
own name changes the maps, and about half of the modellable taxa have no
formal name. Fourth (C4), the whole pipeline runs automatically at a
continental scale and says which of its maps to trust: most are weak or
failed, and they are published with that grade rather than hidden. We also
report a test registered in advance: whether the maps carry habitat
information that another system, a photo-identification model, can use
(Q1). The maps, models, layers, code and the identifiers of every training
record are archived for reuse.

---

## 2. Materials and methods

*Drafted from the public Methods page (atlas.mycomap.org/methods). Numbers in
this section that describe the data are re-read from the frozen release
before submission. ODMAP protocol in Appendix S1: Section S1 (E17).*

### 2.1 Records and DNA-defined taxa

A record trains a model only when its name is confirmed by DNA: it is marked
correct ("Validated") in at least one MycoMap validation project, whatever
another project said. Photo identifications, herbarium names and unassessed
records are excluded.

*Validation.* A validation project is a list of records, each with one or
more sequences (ITS in most cases). Each sequence is searched against
MycoMap's reference database (MycoBLAST) and NCBI GenBank. A record is
validated either by hand, by a project member (project leaders,
contributors, lab contributors or approved members) who reviews the record's
sequences, BLAST results and name, or automatically, by the platform's
analysis of the BLAST results; a person starts every automatic run, and
any member can confirm or overturn its verdict. Automatic validation applies
only when the DNA evidence is decisive: every target sequence (contaminant
and non-target sequences excluded) has a finished BLAST analysis, all name
the same species, and at least one reaches ≥ 70% analysis confidence and was
assembled from at least three reads; the record is then marked correct under
that species, and the name is written back to iNaturalist or Mushroom
Observer with an explanatory comment. Anything short of that goes to a
person. Each verdict records who made it and when. Only a project's own
"Validated" counts; an echo of another project's verdict does not. Records
that one project validates and another rejects count as validated, because
the validating project settled the name. [CHECK: cite the mycomap.org
Handbook and the eligibility code.]

Of an approximation of the training set (145,256 eligible records rebuilt
read-only from production on 2026-10-13, against the rebuild pull's 138,410
eligible and 133,311 kept), 83.6% carry a person's verdict, 5.3% an
automatic verdict later confirmed by a person, and 11.1% an automatic
verdict only; automatic validation touched iNaturalist records almost
exclusively (MyCoPortal and GenBank records are all manual). 27.9% are
validated in two or more projects. "Manual" here means no automatic-
validation log entry, and that log begins on 2026-03-17, so earlier
automatic verdicts count as manual. [PENDING E16: the same figures for the
frozen pull's records, if provenance can be joined to them.] E7b measures
what the validation level does to the maps, each arm against the
production rule: automatic-only verdicts excluded; manual verdicts only;
validated in at least two projects; no rejection anywhere. Records come from
iNaturalist, Mushroom
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

Everything is modelled on a North America Albers Equal Area Conic grid with
5 km cells (3.7 million cells); the frozen release is on this grid. The
pipeline also defines a nested 1 km grid, which no release used here.

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
layer sweeps and not adopted (Appendix S1: Section S3; E8).

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
for every taxon.

Atlas is reproducible from its pinned container (base image by digest, R
packages from a dated Posit snapshot, the store's content-addressed inputs).
On one processor family a rerun reproduces every map byte for byte; we
verified this for Maxent, random forests and boosted trees, tuned and
untuned, with and without null tests. Across processor families, results
agree to floating-point precision rather than bitwise: OpenBLAS selects its
matrix kernels by processor, and the area-of-applicability index is computed
through one of them. Suitability values agree to a relative 1e-9, and the
index to an absolute 1e-6 on a scale whose thresholds lie between about 0.3
and 1. Grades, ranks and every published product built from them are
unchanged. Our refit checks enforce exactly these tolerances and refuse
anything beyond them.

Published records follow their source's privacy: a record hidden or
obscured at its source, or of unknown privacy there, stays so in every
published dataset. [PENDING: the rebuild lane's check of the 0.1° record
cells and other published layers for such records, and whether the frozen
release applies it at finishing.]

Each shard's record names its instance type,
processor and BLAS. [PENDING E12: the numbers from the rerun.]

### 2.12 Pre-declared question Q1: a place signal for photo identification (E21, E22)

MycoMap Vision identifies fungi from photos by nearest reference images and
adds a place term. Its current place term is a distance kernel over DNA
records, which ranks down true species found far from known records. The
Atlas arms replace that kernel with habitat. The design was fixed on
2026-10-12, before any result, and is public in the Vision repository
(`docs/atlas-environment.md`, file version b78609d). The analysis plan was
approved in commit 5c9a4b6 and is unchanged since; b78609d only added a
later section proposing the new-find tracker, not an edit to the analysis.

- **Data.** Vision dataset release v1: training records first validated on or
  before 2026-08-17 (155,781 records), validation records after it (13,354).
  Atlas is refitted on records first validated on or before the same date
  (the hindcast release, E2), so no validation record trained a map. The
  cutoff is on the first-validation date, not the observation date.
- **Confirmation.** Settings are chosen on validation-set cross-validation
  (observer folds); the direction is then checked once on v1-test, a census
  of North American records first validated after 2026-10-12 13:17 UTC
  (≥ 3,000 records; frozen ~30 October 2026). Which Atlas release each step
  may use: validation-set results use the hindcast release only (any later
  pull contains the validation records); the v1-test check may use the
  hindcast release or the October 2026 rebuild release (pull 2026-10-12
  05:10 UTC, before v1-test opened); no nightly release pulled after
  2026-10-12 13:17 UTC is used for either.
- **Primary arm (P2c).** Each strong map's continent-wide projection, ranked
  on its in-area scale, enters as log f(rank) × trust, replacing the distance
  kernel for mapped taxa; trust = map strength × agreement among the taxon's
  strong models × applicability (cut or graded outside the AOA).
  Unmapped taxa keep the served kernel.
- **Tests.** Intersection-union: species top-1 better than no place term
  (one-sided McNemar, p < 0.05) **and** non-inferior in the 300–1,500 km band
  at a 2% margin (paired bootstrap, 10,000 resamples). Secondary arms (P2c
  without trust; in-area only; the accessible area as a range; combined with
  the kernel; a low-capacity environment head on Atlas layers, P4, with a
  coordinates-only control, P6) are Holm-adjusted and exploratory. Effects are
  reported within reference-depth bands so map quality is not confused with
  commonness.
- **Projection validity (H, E22).** For validation records of mapped taxa
  500 km or more from any training DNA record, the Boyce index of the true
  species' projected rank, and the share in cells ranked ≥ 50 with a binomial
  CI, inside and outside the AOA. This is also an independent test of the
  full-extent maps (C2).

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

[PENDING: models, maps and taxa by grade × learner × site band, with the
strong share stated up front (C4); strong maps by guild and region; how many
taxa have a strong map; combined maps; share of reach inside AOA; and the
standard test on real models (E1c): the share of maps 19 scattered nulls call
good that are not shown to beat collecting.] → **Table 3**, **Figure 4** (example maps across grades).

### 3.4 How the maps did on records they never saw (E2, E3, E15)

[PENDING: rank of hindcast and prospective finds by grade; top half / top
tenth / Boyce / beats-effort with intervals; new sites vs near known sites;
inside vs outside AOA; combined vs single maps.] → **Figure 5**.

### 3.5 Against standard practice (E6)

[PENDING: self-reported CV score vs independent-test score for each
approach.] → **Figure 6**.

### 3.6 What sequence names change (E9, E16)

[PENDING: records whose sequence name differs from the record name (species,
genus) by source; for affected taxa, map rank correlation, grade changes and
independent-test skill under each labelling; the share of modellable taxa
with no formal name.] → **Figure 7**. (E6c, morphology-named GBIF models, if
run, goes to the Discussion.)

### 3.7 What drives the maps (E8)

[PENDING: permutation importance by predictor group, ectomycorrhizal vs other
guilds, strong maps only; layer-sweep results in S3.] → **Figure 8**.

### 3.8 Stability across nightly releases (E11)

[PENDING: map rank correlation and grade changes between releases against the
number of new records.] → Appendix S1: Section S4, or main text if striking.

### 3.9 Q1: maps as a place signal for photo identification (E21, E22)

[PENDING: primary test (P2c vs no place term: overall McNemar; 300–1,500 km
band lower bound vs −2%); P2c vs the served kernel; trust weighting (P2c vs
P2c-u); depth-matched effects; P4 vs P6; projection validity H. Confirmed on
the fresh v1-test set when it exists. Reported whatever the result.]
→ **Figure 9** (cut first if the monograph runs long).

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
- **Training records** (new; Steve, 2026-10-13): published for the paper's
  frozen release(s) only; the per-release lists of trained records that the
  nightly pipeline keeps stay private. The ids of every record that
  trained the frozen release, with source (iNaturalist, Mushroom Observer,
  MyCoPortal, GenBank, MycoMap sequence), the DNA name used, the sequence it
  came from, the taxon fingerprint and the survey site it joined, but no
  coordinates. Each id resolves to its public source page, which shows what
  the source itself shows. **Privacy rule (Steve, 2026-10-13):** a record
  hidden or obscured at its source stays hidden or obscured in every
  published dataset. Records whose location is hidden or obscured at the
  source, or whose privacy at the source is unknown (about 800 records in
  the rebuild's pull [CHECK: count in the frozen pull]), are listed with
  their id but **no survey-site membership**. Obscured iNaturalist
  coordinates never train a model. [CHECK: licence of this table, CC0
  proposed.]
- **Pending check (asked of the rebuild lane):** whether the 0.1° record
  cells and any other published layer need the same treatment for hidden,
  obscured and unknown-privacy records, and whether that can be applied when
  the frozen release is finished.
- **Contributors** (Steve, 2026-10-13): one row per contributor, holding the
  name or username as public at the source and record counts only. There
  are no record ids, species or places in it, so it cannot be joined to the
  training-record table to tie a person to a hidden-location record.
  Contributors may ask to be listed anonymously. [PENDING: the coordinator
  is confirming this shape with Steve.]
- **Code**: the repository at the release commit, with a Zenodo software
  DOI, and the container image digest.

### 4.2 Versions

The paper cites one frozen release by id and DOI: the finished release of
the full-view refresh, whose default maps, grades and ranks equal the
October 2026 rebuild's and whose full-extent rasters have no border gaps
[PENDING: id, DOIs]. The live atlas keeps
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

## 6. Title-page and back-matter statements

- **Open Research statement** (title page; draft for submission, ESA
  options 3 and 6): "Novel code (the MycoMap Atlas R package, API and
  pipeline, GPL-3.0-or-later) is available at
  https://github.com/BiodiverseLabs/mycomap-atlas and will be archived on
  Zenodo with a DOI for the release commit upon acceptance. Data are
  provided for peer review on Zenodo [links]: the environmental layers, every
  model of the frozen release (suitability and area-of-applicability rasters,
  metrics, grades), and the table of training records with their
  iNaturalist, Mushroom Observer, MyCoPortal and GenBank identifiers. Record
  coordinates are those published by each source; records hidden or
  obscured at their source, or of unknown privacy there, stay so in every
  published dataset and carry no survey-site membership." [PENDING: DOIs; data
  citations for WorldClim, SoilGrids, ESA WorldCover, BIGMAP, the Canadian
  NFI, NALCMS, Copernicus and FungalTraits; query details for the
  mycomap.org pull, Appendix S1: Section S6.]
- **Acknowledgments** (one paragraph): collectors, validators, the
  sequencing network, data providers [PENDING: Steve to choose; proposal
  below, after community-science practice], and the AI disclosure: "Much of
  the pipeline's code and the first drafts of this manuscript were written
  with an AI assistant (Claude, Anthropic; model versions in Appendix S1)
  under the author's direction; the author reviewed all code and text and is
  responsible for them." The same disclosure goes in Methods 2.11 and on the
  submission form.
- **Author Contributions:** sole author.
- **Conflict of Interest statement** (required): "The author declares no
  conflict of interest." (Steve, 2026-10-13.)

**Crediting contributors (adopted, Steve 2026-10-13).** The journal does not allow
group authors, so contributors are credited three ways, as large
community-science papers do:

1. *Acknowledgments*, collectively: the collectors and observers on
   iNaturalist, Mushroom Observer and MyCoPortal's herbaria; MycoMap's
   validators; the sequencing network's labs. Name individually only the few
   people who did substantial work beyond contributing records (for example
   project leaders, lab leads, the most active validators), with their
   permission.
2. *Every collector credited in the data*: a contributor table on Zenodo
   (shape and opt-out in section 4.1)
   beside the training-record table (observer name or username as given at
   the source, and record counts), derived from the record ids. Names are
   already public at each source; the source-privacy rule still applies to
   locations.
3. *Source citations*: iNaturalist, Mushroom Observer, MyCoPortal and
   GenBank as data sources in the References; and, if practical, a GBIF
   derived-dataset DOI for the iNaturalist and Mushroom Observer records used,
   so their GBIF datasets count this paper as a use (iNaturalist asks large
   studies to cite a GBIF DOI).

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
| Fig 9 | Q1: photo identification with Atlas as the place signal: top-1 by distance band and arm; projection validity beyond 500 km | Q1 | E21, E22 |
| Table 1 | Records and taxa by source and rule | C4 | E16 |
| Table 2 | Predictors and sources | methods | layer manifest |
| Table 3 | Models and maps by grade × learner × site band | C2, C4 | release |
| Table 4 | Evidence summary: each claim, its tests, the result | all | |

Supporting information: one Appendix S1 with sections, as the journal
prefers. Section S1 ODMAP protocol (Zurell et al. 2020); S2 virtual-species
design; S3 layer and predictor sweeps; S4 sensitivity analyses (E7) and
stability (E11); S5 small-site maps; S6 reproducibility and data query
details (E12). Tables of records or results go to Zenodo, not the appendix.
Maps in figures need latitude and longitude, a north arrow, a scale bar and
a border.

---

## Appendix A. Evidence plan

IDs here are the Atlas paper's; cite them elsewhere as "Atlas E<n>" (the
Vision paper has its own E-numbers). What a reviewer in species distribution
modelling and in mycology will expect, what exists, and what is to run. Priority: **P1** a core claim
depends on it, or reviewers will certainly ask; **P2** strengthens a claim or
answers a likely question; **P3** supplementary. Costs are estimates to be
confirmed by the rebuild lane; EC2 spot runs at roughly $0.05 per CPU-hour.
Steve set the compute budget on 2026-10-13: run each analysis at the size
its claim needs, not the cheapest ("$100 is no problem" for E1, E6 and E9).
A separate experiments session builds the study code (E1 knobs, E1c rescan,
E6b, E9 arm, E6a) from the pre-registrations and plans in
`docs/experiments/`, reviewed by the rebuild lane. Every analysis runs on the frozen release
and its pull, and gets an entry in
the experiment registry (`docs/experiments/`, one file per run: question,
data, command, result, release, commit).

| ID | Analysis | Claim | Exists? | Data / method | Cost / time | Priority |
|---|---|---|---|---|---|---|
| E16 | Records, taxa, sites, provisional share, sampling bias, validation lag | C3, C4 | Partly (counts in memory and Methods page) | Frozen pull + release index; read-only | 1–2 days, no compute | P1 |
| E1b | Re-read the existing null study by site band | C1 | **Done 2026-10-13** (`docs/experiments/2026-10-13-null-calibration-by-band.md`): see 3.2 | 2026-10-06 virtual-species results file | read-only | P1 |
| E1 | **Pre-registered** (`docs/experiments/2026-10-13-prereg-e1-null-calibration.md`, amended 2026-10-13 before launch). Null calibration rerun: false pass and power by design × site band × habitat breadth × signal strength × learner (Maxent, RF, ESM), so power is a curve; map-to-truth ρ by grade | C1, C2 | Pre-freeze: 99 species, Maxent, 3 designs; power flat with sites (E1b) | `study-virtual` on the frozen pull and layers. Full models: habitat 5 site bands × 2 breadths × 2 signal strengths × 30 = 600, geography 5 bands × 2 centre counts × 40 = 400; Maxent and RF; scatter and shift ×99, stop at 5. ESM: 3 bands × (habitat 2 strengths × 40 + geography 60) = 420. Effort arms (E14) on the same species | est. 1,400–2,000 CPU-h ($70–100), ~15–20 h wall on 4 workers | P1 |
| E1c | **Planned** (`docs/experiments/2026-10-13-plan-e1c-standard-test-real-models.md`). Real models: share of the frozen release's maps that pass the standard test (19 scattered nulls, the old production design) but not the shift test | C1 | Shift results exist for every model of the frozen release; scatter does not | Scatter ×19 on a sample stratified by learner × site band × grade (~50 per cell, ~1,000 models); report the share with a CI, weighted to the release | est. 100–200 CPU-h ($5–10), ~1 day code | P1 |
| E2 | **Pre-registered** (`docs/experiments/2026-10-13-prereg-e2-hindcast.md`). Hindcast: full graded job on records first validated ≤ 2026-08-17; score later finds by grade, new vs known places | C2 | **Approved 2026-10-13**: Vision's training run becomes this full graded job (nulls on, private never-promotable release); code ~1–1.5 days in the rebuild lane, after the full-view refresh | Cutoff-filtered pull; test set = first green > cutoff (optionally observed > cutoff); undated records dated or excluded, with a count | ~250–500 CPU-h ($10–25), runs after the cutover on Steve's go | P1 |
| E3 | Prospective tracker by grade | C2 | Built; ships at the rebuild cutover; backfill from 2026-10-03 | Daily scoring of new finds on the live release | ~0 compute; needs months of finds (3–6) | P1 (clock starts at cutover) |
| E9 | **Planned** (`docs/experiments/2026-10-13-plan-e9-record-names.md`). Sequence names vs record names: refit affected taxa both ways | C3 | Counts yes (4,878 records with a different species or genus; ~1,435 taxa with ≥10 localities change) [pre-freeze]; refits no | Production (sequence names) is the frozen release; refit every taxon whose record set differs under record names (full graded fits, all learners); map Spearman and Schoener's D, grade changes, E2/E3 skill | est. 150–300 CPU-h ($8–15), 2–3 days | P1 |
| E6a | **Planned** (`docs/experiments/2026-10-13-plan-e6a-default-maxent.md`). Default-practice Maxent on the hindcast pull (maxnet default.features, regmult 1, 10,000 uniform background points over the accessible area, random 5-fold CV, 19 uniform nulls as commonly run) | C1, C2 | No | New study arm over every taxon with ≥20 sites; its own CV score and pass rate vs its score on E2/E3 finds | est. ~200 CPU-h ($10), ~3 days code | P1 |
| E6b | **Pre-registered** (`docs/experiments/2026-10-13-prereg-e6b-distance-baseline.md`). Spatial-only baseline (distance to known sites), paired with each model on its own AOA cells. **Runs first after E2**, because its result shapes C2's wording | C2 | No (shift nulls are related but not a baseline) | Kernel/distance model on the hindcast's training sites; scored on the E2 finds with the E2 metrics | small compute, ~2 days code | P1 |
| E12 | Reproducibility: rerun a random sample of taxa from the frozen pull; (a) byte identity on ONE pinned instance family (e.g. r7i, Intel); (b) a cross-family comparison reported separately against the stated tolerances (suitability relative 1e-9, AOA index absolute 1e-6; grades and ranks identical); Zenodo DOIs for layers, models, code | C4 | Machinery yes (fingerprints, pinned image, content-addressed store, refit tolerance checks, shard records name instance/CPU/BLAS); demo no; layers deposit held | Fresh workers, 20–50 taxa, both families | ~20 CPU-h, 1 day | P1 |
| E17 | ODMAP protocol | all | No | Writing from Methods + code | 1–2 days | P1 |
| E4 | Presence–absence test: GlobalFungi + MycoMap soil cores, by UNITE species hypothesis | C2 | No | Feasibility first: how many Atlas taxa map 1:1 to an SH with enough North American samples | Feasibility 2–3 days; full 1–2 weeks; small compute | P1 feasibility, P2 full |
| E6c | Morphology-named GBIF Maxent for formally named species, scored on DNA-defined finds | C3 | No | GBIF download with DOI; name matching; same pipeline | ~100 CPU-h, ~1 week | P2 |
| E7 | Sensitivity: (a) site count (thinning study), (b) validation level (automatic-only verdicts excluded, −11%; manual verdicts only; ≥ 2 projects; no rejection anywhere; needs per-record validation provenance joined to the frozen pull), (c) coordinate precision (1 vs 5 km; MO/MyCoPortal rules), (d) pre-1980 records | C2, C4 | (a) pre-freeze, 118 taxa, old nulls; (b–d) no | Paired arms on a stratified ~150-taxon panel; skill, map correlation, grade changes | ~20–40 CPU-h per arm, ~1 week | P2 |
| E8 | Variable and layer importance by guild | secondary | Yes in every model's metrics; layer sweeps pre-freeze | Aggregate over strong maps from the release | ~1 day, read-only | P2 |
| E10 | AOA and extrapolation: share of reach inside AOA; finds inside vs outside | C2 | Partly (per-model applicability; tracker counts outside-AOA finds) | Release + E2/E3 | ~1 day | P2 |
| E11 | Stability across nightly releases | C4 | No; releases are kept indefinitely | Per-taxon rank correlation and grade flips vs new records | ~2 days code, ≥4 weeks of nightlies | P2 |
| E14 | Effort handling on virtual species | methods | Pre-freeze, 198 species | Rerun inside E1 | inside E1 | P2 |
| E15 | Combined map vs its members on independent finds | C2 | No | From E2/E3 | hours, after E2 | P2 |
| E18 | Small-site maps: grades and power at 3–19 sites | secondary | Pre-freeze (thinning study; first-build pass rates) | Inside E1 + E7a | inside E1 | P2 |
| E5 | Expert and checklist comparison: state verdicts vs independent checklists; expert ranges for ~20 well-known taxa | C2 | No | Curated panel; expert time | 1–2 weeks, mostly expert time | P3 (P2 if a reviewer-friendly panel exists) |
| E6d | biomod2-style default ensemble | C2 | No | Same sites | ~1 week | P3 |
| E13 | Block-size check (kNNDM-style distance matching) | methods | Pre-freeze, 153 taxa | Rerun `study-blocks` | ~10 CPU-h | P3 |

**Order:** see the Path section below.

| ID | Also needed for a combined paper | Priority |
|---|---|---|
| E19 | Training-record table for the frozen release (ids, source, DNA name, sequence, fingerprint, survey site; no coordinates) and its Zenodo record; no site membership for records hidden, obscured or of unknown privacy at source (Steve, 2026-10-13) | P1 |
| E20 | Data-records table and usage notes (section 4) | P1 |

| ID | Pre-declared question Q1 | Exists? | Data / method | Cost / time | Priority |
|---|---|---|---|---|---|
| E21 | Vision place-signal arms: P2c primary; P2c-u, P2a/b, P2d, P3, P4, P5 secondary; P6 control | Design pre-declared 2026-10-12; Vision v1 cut 2026-10-12; needs the hindcast release (E2), its continent-wide projection of strong maps and the trust signals | Vision v1 val; run on the Vision side (Vision coordinator) | Atlas side inside E2; Vision side CPU hours | P1 (Steve, 2026-10-13) |
| E22 | Projection validity (H): Boyce and share ≥ 50 for val finds 500+ km from training records, inside/outside AOA | Pre-declared | Same run | inside E21 | P1 |

---

## Appendix B. Venue and scope

Facts read on each journal's own pages on 2026-10-12 and 2026-10-13
(metrics: each journal's metrics page, 2025 figures). "nc" = not confirmed.
**Decided 2026-10-13 (Steve): Ecological Monographs, Method, "for now".**
Fallback: (b) below. Licence stays CC BY-SA 4.0 (Steve), so Ecography, GEB
and Scientific Data stay closed.

### Scope, two ways

- **(a) One combined methods and data paper** (Steve's choice, 2026-10-13).
  It needs, beyond the methods and results: a data-records section (every
  deposited file with DOI, format, licence: section 4.1), technical validation
  (the null calibration, hindcast, tracker and reproducibility rerun:
  Results 3.2–3.5 and E12), usage notes (4.3) and a versioned archive (the
  frozen release on Zenodo, 4.2). All four are in the outline now. Length is
  ~7,000–9,000 words, 9 figures and 4 tables, so it needs a journal without a
  tight cap.
- **(b) A methods paper plus a companion data descriptor.** Methods in MEE
  (C1, C2, Q1); the descriptor cites the same frozen release. The usual
  descriptor journals require CC0 or CC BY data (Scientific Data, with an
  exception for share-alike forced by inputs; GigaScience CC0), which
  conflicts with the CC BY-SA maps. Two reviews, two fees, more total work.

**Recommendation: (a), in Ecological Monographs (Method).** It is the one
journal where the combined paper fits without cutting. It has no data-licence
conflict, and it published the presence-only SDM benchmark this paper
extends (Valavi et al. 2022, doi:10.1002/ecm.1486). Keep (b) as the fallback
if the presubmission inquiry is declined.

### Top five for the combined paper

| Rank | Journal (type) | Words / display items | Data and code | AI declaration | Preprint | Access, cost | JIF; median days to first decision / acceptance | Comparable recent papers |
|---|---|---|---|---|---|---|---|---|
| 1 | **Ecological Monographs** (Method; presubmission inquiry encouraged) | ≥ 40 manuscript pages, no maximum; abstract ≤ 350; no figure or reference caps | ESA Open Research: data and new code in a permanent public repository at acceptance; no licence rule (ESA's Dryad is CC0, so maps go on Zenodo) | tool and use in the relevant section, Acknowledgments and submission form | original submission only | hybrid; $75 per typeset page on the subscription route (ESA member grants up to 21 pages/yr); OA price nc | 9.0; 19 / 242 | Valavi et al. 2022 presence-only SDM benchmark (10.1002/ecm.1486); cross-validation for model selection review 2023 (10.1002/ecm.1557) |
| 2 | **Methods in Ecology and Evolution** (Research Article, or Workflow) | 7,000–8,000 words **including** references, captions, statements; no display cap | public archive, every result recreatable; anonymised at submission; no licence rule | Methods, tool name and version; annotate AI-written code | allowed | gold OA $3,500 (Workflow $2,600) | 5.7; 15 / 148 | Ridder et al. 2024 shift-&-rotate nulls (10.1111/2041-210X.14443); Meyer & Pebesma 2021 AOA (10.1111/2041-210X.13650); ENMeval 2.0 (10.1111/2041-210X.13628) |
| 3 | **Diversity and Distributions** (Method or Data paper) | 6,000 words excluding abstract, references, captions, tables; long tables online | mandatory, no embargo; code mandatory for new methods; no licence rule | Methods or Acknowledgements | allowed | gold OA $4,150 (waiver if unfunded) | 4.2; 11 / 226 | eBird community-science SDM guidelines 2021 (10.1111/ddi.13271); threshold selection 2025 (10.1111/ddi.70019). Needs a conservation-implications section |
| 4 | **Ecological Applications** (Article) | ≤ 60 manuscript pages | as Ecological Monographs | as Ecological Monographs | as Ecological Monographs | hybrid, $75/page | 4.6; 35 / 218 | Fink et al. 2020 eBird full-annual-cycle distributions (10.1002/eap.2056) |
| 5 | **Fungal Diversity** (Research Article or Data Paper; BioAcademic Press since 2026) | no word limit | GenBank/TreeBASE rules; no licence or code rule | mandatory statement: tool, version, purpose | allowed | gold OA CC BY, $3,200 up to 60 pages (Data Paper $1,600) | 24.8; 29 days (pre-2026) / nc | Global Soil Mycobiome dataset 2021 (10.1007/s13225-021-00493-7); global polypore distribution 2026 (10.65390/fdiv.2026.136002). Taxonomy-heavy scope; SDM review would be weaker |

One-line reasons: (1) fits the whole paper and has published the closest
benchmark; (2) the core methods audience and the shift-&-rotate paper's home,
but the cap forces most of the data, C3, C4 and Q1 into supplements; (3) has a
data-paper type and no licence rule, but adds a conservation section; (4)
room and an applied angle, slowest first decision; (5) mycology readers and
high JIF, weak SDM fit.

**Excluded for the licence conflict** (data must be CC0 or CC BY, or no
stricter than CC BY): Ecography (5,000 words, 6 display items), Global Ecology
and Biogeography, Scientific Data, GigaScience. Nature Ecology & Evolution
(3,500-word Article, $12,850 OA or free subscription) is a long shot that
would need the paper restructured around C1. Global Change Biology's scope
needs an environmental-change focus. Mycologia (checked 2026-10-08): no word
limit found, AI declaration required, OA $3,940.

---

## Path

Set 2026-10-13 with the Atlas coordinator after Steve's revision. Every launch
gets Steve's direct go through the operations lane; every run gets a
`docs/experiments` entry, pre-registered where there is a hypothesis.

| # | Item | Gate | Target |
|---|---|---|---|
| 0 | Rebuild cutover; nightly tracking (E3) starts | Steve's go | October 2026 |
| 1 | Full-view refresh → **frozen release** (id, then Zenodo layers, models, training records) | rebuild-lane code; Steve's go | October 2026 |
| 2 | **E2 hindcast** (also Vision's training run; Q1's Atlas input) | hindcast code (~1–1.5 days); the refresh; Steve's go | run by ~25 October 2026 (Vision freezes its test set ~30 October) |
| 3 | **E6b** distance-only baseline on the E2 finds | rebuild-lane code; E2 | early November 2026 |
| 4 | **Presubmission inquiry** to Ecological Monographs | first E2 numbers | November 2026 |
| 5 | **E1c** standard test on real models | rebuild-lane code; the frozen release | November 2026 |
| 6 | **E1** virtual-species calibration (pre-registered, amended) | breadth and strength knobs in `study-virtual`; Steve's go | November 2026 |
| 7 | **E9** sequence vs record names | record-name arm; Steve's go | November 2026 |
| 8 | **E6a** default-practice Maxent | new study arm; Steve's go | November–December 2026 |
| 9 | **E12** reproducibility rerun; E16 descriptives; E17 ODMAP | the frozen release; rebuild-lane tolerance wording | December 2026 |
| 10 | Q1 arms (E21, E22) | Vision side, after E2 | November 2026 |
| 11 | P2 items as time allows: E4 full, E6c, E7, E8, E10, E11, E15 | each its own go | December 2026 – January 2027 |
| 12 | **Submission**, once E1, E2, E6a/b, E9, E12, E16 and E17 are done, with whatever E3 has accumulated; more E3 added at revision | Steve | **aim January 2027** |

E4 feasibility (P1) runs whenever a slot is free; it is read-only work.

---

## Open decisions

Settled 2026-10-13 (Steve): one combined methods and data paper; sole
author, Russell, Stephen D.; training-record ids public for the frozen
release(s) only; compute at the size the claims need; Ecological Monographs
(Method) for now; C5 made a pre-declared question (Q1); C3 narrowed; plan
revised (Path).

1. **Licence:** maps and rasters stay CC BY-SA 4.0 (Steve, 2026-10-13);
   Ecological Monographs sets no data licence. Ecography, GEB and Scientific
   Data stay closed.
2. **Conflict of interest:** "The author declares no conflict of
   interest." (Steve, 2026-10-13.)
3. **Frozen release:** decided by the coordinator 2026-10-13: the
   full-view refresh's finished release. Waiting for it to run, then for its
   id and Zenodo DOIs.
4. **Crediting contributors:** the full plan in section 6 adopted (Steve,
   2026-10-13). Steve item: the few people to thank by name (each asked
   first). Data item: observer name or username per training record for the
   Zenodo contributor table (asked of the coordinator).
5. **Zenodo layers archive:** Steve, 2026-10-13: "probably" discard the
   draft held since 2026-09-29 and re-archive the frozen release's layers,
   once that release exists (operations lane, Steve's go).
6. **Privacy of other published layers:** whether the 0.1° record cells
   and other layers need the source-privacy rule, and whether the frozen
   release can apply it at finishing (asked of the rebuild lane).

---

## Changelog

- **0.7 (2026-10-13).** Introduction drafted as prose (~1,000 words);
  contributor table shape and opt-out in 4.1.
- **0.6.6 (2026-10-13).** Contributor credit plan adopted; licence stays
  CC BY-SA (Steve).
- **0.6.5 (2026-10-13).** Validation paragraph filled from the data
  inputs lane: the automatic-validation rule and approximate manual/automatic
  shares; E7b gains the "automatic-only excluded" arm.
- **0.6.4 (2026-10-13).** Design questions from the experiments lane
  settled before code: E1 amended (realised-count bands, weak-signal
  matching, bell-only breadth, absolute realised breadth, RF nulls kept);
  E1c details; E6b pre-registered (paired with each model on its AOA
  cells); E9 and E6a planned (E6a on the hindcast pull, maxnet
  default.features, uniform nulls).
- **0.6.3 (2026-10-13).** Conflict of interest: none (Steve). Contributor
  credit proposal. Zenodo layers: discard and re-archive at the frozen
  release.
- **0.6.2 (2026-10-13).** Source-privacy rule (Steve): hidden, obscured
  and unknown-privacy records keep that status in every published dataset
  and get no survey-site membership; site membership otherwise un-held;
  pending check on the 0.1° cells. Budget confirmed; experiments session.
- **0.6.1 (2026-10-13).** Reproducibility claim in 2.11 from the rebuild
  lane (byte-identical within a processor family; stated tolerances across
  families); E12 design split accordingly.
- **0.6 (2026-10-13).** Plan revised (Steve via the coordinator): C5 became
  pre-declared question Q1; C3 narrowed to what E9 and E16 support; C4 states
  the strong share and what weak and failed maps are for; E1 gains a
  signal-strength axis; new E1c (standard test on real models); E6b runs
  first after E2; validation paragraph in 2.1; the frozen release is 5 km;
  training-record ids public for frozen releases only; a Path section with
  gates and a January 2027 submission aim.
- **0.5.1 (2026-10-13).** Frozen release = the full-view refresh's
  finished release; E1 and E2 pre-registered; reproducibility claim marked
  [CHECK]; survey-site membership column held.
- **0.5 (2026-10-13).** Shaped to Ecological Monographs (Method): submission
  format section, Open Research statement draft, AI disclosure in three
  places, conflict-of-interest slot, one Appendix S1 with sections,
  presubmission inquiry draft.
- **0.4 (2026-10-13).** Appendix B rewritten: scope two ways, top five
  for a combined paper with review times and comparable papers; Ecological
  Monographs recommended. C1 reworded and Introduction extended for prior
  work on structure-keeping nulls (Osborne et al. 2022; Ridder et al. 2024).
- **0.3.1 (2026-10-13).** Pre-declaration cited as b78609d (plan approved
  5c9a4b6, unchanged); v1-test confirmation and its leakage rule; "Atlas
  E<n>" citation note.
- **0.3 (2026-10-13).** C5 added: Atlas maps as Vision's place signal
  (pre-declared arms moved here from the Vision paper, Steve), with methods
  2.12, results 3.9, Figure 9, E21–E22.
- **0.2 (2026-10-13).** Steve's decisions: combined methods and data paper
  (new section 4, the data resource), sole author, public training-record
  ids, budget at the size the claims need (E1, E6a, E9 resized). E2 approved
  as the full graded hindcast. Hindcast fairness noted in Discussion.
- **0.1.1 (2026-10-13).** Appendix B venue facts and recommendation; E1b
  results in 3.2; null-model debate references in the Introduction.
- **0.1 (2026-10-13).** Skeleton: core claims, outline, figure and table
  plan, methods drafted from the Methods page, evidence plan, open decisions.
