# MycoMap Atlas: Habitat-suitability maps with a calibrated trust grade for thousands of DNA-defined North American fungi

*Working title (118 characters; the journal allows 120, sentence case, one
colon, no uncommon acronyms). Alternative: "Which habitat maps can be
trusted? Calibrated null tests for thousands of DNA-defined North American
fungi". Living draft, version 0.9 (2026-10-13). Skeleton: headings, the
claims, the figures and tables each claim needs, and what is pending.
Methods prose is drafted from the public Methods page; Results wait for the
frozen release.*

| | |
|---|---|
| Author | Russell, Stephen D. (sole and corresponding author, as on the Zenodo records) |
| Target venue | **Ecological Monographs, Method** (Steve, 2026-10-13, "for now"); fallback MEE + a data descriptor (Appendix B) |
| Paper type | One combined methods and data paper (Steve, 2026-10-13) |
| Frozen release | **20261013T191324Z-fa1b4198** (finished 2026-10-13 19:13 UTC, 38,216 files): the finished (v5) release of the full-view refresh of the twice-cleaned October 2026 rebuild. Pull occurrences-20261012T051017Z-x73b85b36 (sha256 7d3c5d70…), 133,235 records / 16,252 taxa. Lineage in section 3.3. Zenodo: layers doi:10.5281/zenodo.23463069; models doi:10.5281/zenodo.23463939. [PENDING: code commit DOI] |
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
2. **C2. The grade predicts how a map does on records it never saw, and
   only strong maps beat distance to known records.** Of the later finds in a
   hindcast, strong maps placed 91.4% in their top half, weak maps 87.0% and
   failed maps 78.4% (strong − failed 13.0 points, 95% interval 9.0–17.2).
   On the same places strong maps placed 4.4 points (1.5–7.6) more than a
   map of distance to the taxon's known sites, a gain that comes from finds
   more than 100 km away; near known records distance alone does as well.
   Weak maps, and both looser tiers within them, do no better than distance.
   [E2, E6b done; prospective E3 PENDING]
3. **C3. Labelling by the approved sequence rather than the record's own
   name changes the maps, and about half the modellable taxa have no formal
   name.** [PENDING E9, E16] A comparison with morphology-named records
   (GBIF, E6c, P2) is not part of this claim; if it runs, it is a Discussion
   point.
4. **C4. An automated, nightly, open pipeline can do this at continental
   scale, and says which maps to trust.** The frozen release holds 9,041
   models of 6,369 taxa; 576 models of 470 taxa (7.4% of modelled taxa) are
   strong, and none of the 52 taxa with 100 or more sites. The strong share is stated plainly: most maps are
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

*Draft skeleton, 2026-10-13 (≤ 350 words, no citations or URLs, as the
journal requires). Final wording once the numbers are in.*

Automated pipelines now fit distribution models for thousands of species,
but they report each map's skill with scores that clustered collecting
inflates, and the usual null test does not correct for it. Fungi add a
second problem: morphological names often hide several lineages. We built
MycoMap Atlas, which maps every North American fungus defined by an
approved DNA sequence with at least three survey sites, from [133,235]
validated community-science records of [16,252] taxa, rebuilt nightly.
Records are compared with the other places people collected and
sequenced; Maxent, random forests, boosted trees and ensembles of small
models are tuned and scored on spatially blocked folds; and each map is
graded against null species that keep its own clustering. On simulated
species collected at the real survey sites, the usual scattered null test
passed [73]% of species with no habitat signal, and every such species
with 100 or more sites, while the clustering-preserving test passed
[2]%, at a power of [26]% [PENDING E1: final figures with intervals]. Of
the atlas's 9,041 models of 6,369 taxa, 576 across 470 taxa were graded strong; the
standard test would have called [X]% of the rest good [PENDING E1c]. Maps
graded strong placed records validated after the training cutoff in their
top half 91% of the time, against 78% for failed maps and 87% for a map of
distance to known records on the same places; weak maps did no better than
distance, and the strong maps' advantage came from finds more than 100 km
from known records. Naming records by
their sequences rather than their own names changed the maps of [N] taxa,
and about half the modelled taxa have no formal name [PENDING E9, E16]. A
pre-registered test asked whether the maps help a photo-identification
model place its answers [PENDING Q1]. The grade, not the number of maps, is
the contribution: it tells users which maps to trust. Maps, models,
layers, code and the identifiers of every training record are archived
with DOIs for reuse.

---

## 1. Introduction

*First prose draft, 2026-10-13 (~1,000 words). Citations are author–year;
the verified list is `references.md`. [CHECK] marks a fact still to source.*

Species distribution models now sit behind conservation assessments, survey
planning and biogeography, and pipelines fit them for thousands of species
at a time (Araújo et al. 2019). Fungi are largely absent from this work.
Most fungal species have never been mapped, and few have been assessed for
extinction risk (Hao et al. 2020; Mueller et al. 2022; Niskanen et al.
2023). Two features of fungal records stand in
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

*Main text kept to the method's essentials (~1,700 words); every detail is
in Appendix S1, and the ODMAP protocol is its Section S1. Numbers that
describe the data are re-read from the frozen release before submission.*

### 2.1 Records and DNA-defined taxa

A record trains a model only when its name is confirmed by DNA: it is marked
"Validated" in at least one MycoMap validation project, by a person who
reviewed its sequences against reference data or by an automatic rule that
accepts only decisive DNA evidence (83.6% of training records carry a
person's verdict [provisional]). Records come from iNaturalist, Mushroom
Observer, MyCoPortal, GenBank and MycoMap's own sequencing, all held on
mycomap.org. Photo identifications, herbarium names and unassessed records
are excluded.

The name is the one on the record's approved sequences, not the record's
own, which is often not updated after sequencing; a record whose sequences
disagree, or name only a genus, is left out. Provisional names (sequence
clusters without a formal name, such as *Mycena* sp. 'IN10') count as taxa,
and about half the modelled taxa carry one [PENDING E16]. A model belongs to
its record set, not its name: each taxon's records are hashed into a
fingerprint, and a model is refitted when the fingerprint changes.

Coordinates must be present, not obscured and accurate to 1 km where an
accuracy is recorded (Mushroom Observer and MyCoPortal records have their
own 5 km rules), in the United States, Canada, Mexico, Puerto Rico or the
US Virgin Islands. The frozen pull holds [133,235] records of [16,252] taxa
[provisional].

*Data errors found and removed.* Two checks before the freeze removed 76
records whose name or place was wrong: 22 Mushroom Observer specimens
linked to unrelated iNaturalist observations (one a striped skunk, named
*Clitocybe deceptiva* by its fungal sequence), and 54 records of plants,
animals and a bacterium named by sequences from pooled host samples or
contaminants. The pipeline did exactly what it was built to do with wrong
links, which is why the paper reports data errors as well as model errors.
Validation, every eligibility rule with its counts, both cleanings and the
query details are in Appendix S1: Section S2.

### 2.2 Predictors, survey sites and models

Everything is modelled on a North America Albers Equal Area Conic grid of
5 km cells, with 69 predictors in eight layers: climate (WorldClim 2.1; Fick
& Hijmans 2017), elevation and terrain, topsoil chemistry and texture
(SoilGrids 2.0; Poggio et al. 2021), land cover (ESA WorldCover; Zanaga et
al. 2021), forest type (NALCMS; CEC 2023), and the share of a cell's trees
in each of 29 host genera from the United States and Canadian forest
inventories (Wilson et al. 2018; Beaudoin et al. 2014) (Appendix S1:
Section S3).

Records of all taxa are gathered into survey sites by 5 km distance
thinning. For each taxon a site is a detection if any of its records is
that taxon and a non-detection otherwise, so the background is where people
collected and sequenced other fungi (a target group; Phillips et al. 2009),
within 500 km of the taxon's sites. Taxa with 3 to 49 sites are fitted
with an ensemble of small models (ESM; Breiner et al. 2015); from 20 sites
also with Maxent (maxnet; Phillips et al. 2017) and a down-sampled random
forest (Valavi et al. 2021); and from 50 sites also with boosted trees. Settings are
tuned by nested spatial cross-validation, with blocks sized from each
taxon's spatial autocorrelation (Valavi et al. 2019), and every model is
scored on whole held-out blocks by AUC against non-detection sites and the
Boyce index (Hirzel et al. 2006). Maps are coloured by rank inside each
model's area of applicability (Meyer & Pebesma 2021). Settings, predictor
selection, effort handling and maps are in Appendix S1: Section S4.

### 2.3 The null test and the grade

A held-out score cannot say whether a map knows anything, because clustered
records are easy to separate from their background with almost any smooth
predictor (Fourcade et al. 2018). Each model is therefore refitted, with
the same untuned settings and folds, on null species. In the *shift*
design, the taxon's own detection sites are rotated by one random angle and
moved together to another surveyed place, and each point is snapped to a
survey site: the pattern's clustering is kept and its tie to environment is
broken. In the *scatter* design, used until October 2026 and close to
common practice (Raes & ter Steege 2007), null detections are drawn site by
site. Up to 99 nulls are drawn, and the sequential test of Besag & Clifford
(1991) stops once five match the map.

A model is **strong** when its held-out AUC beats its shifted nulls at
p ≤ 0.05 and its Boyce index is above zero; **weak** when it ranks held-out
ground better than chance (AUC above 0.5 and Boyce above zero) without
passing; and **failed** otherwise. Only strong maps feed anything that
makes a claim (combined maps, state lists, the location prior for MycoMap
Vision); weak and failed maps are published faint with their grade. Weak
maps were split, before any independent test, into two looser tiers:
moderate (shift p ≤ 0.20) and indicative (the rest), with registered bars
for showing them as labelled maps (Appendix S1: Section S5). After the
comparison with distance (Section 3.4) one rule was added, and it was chosen
after seeing that result: a grade carries downstream claims only if it ranks
later finds better than the distance-only map. Only strong does, so both
tiers are drawn as weak maps.

### 2.4 Calibrating the null test on simulated species

Simulated species are given a habitat, a response to two or three real
predictors, and then "collected" at MycoMap's real survey sites: each real
record at a site is the simulated species with a probability proportional to
the habitat there, so they inherit the real pattern of effort (Zurell et al.
2010). *Geography* species instead follow distance from one or two centres
and ignore the environment, so any pass is a false pass. Each goes through
the production training table, folds, fits and null test. The study
(pre-registered; Appendix S1: Section S5) crosses five site bands, two
habitat breadths and two signal strengths for 1,200 habitat species, with
800 geography species and 840 small-site species, for Maxent, random forests
and the small-model ensembles. It reports the false-pass rate and power of
each null design with Wilson intervals, and how closely passed and failed
maps match the true habitat.

### 2.5 Independent tests and baselines

Two tests use only records the maps never saw. In the **hindcast**, the
whole pipeline, null tests included, is rerun on the records first validated
on or before 17 August 2026, and the records first validated after it are
scored on those maps. In **prospective tracking**, each day's newly validated
records are scored on the release live when the day began; Atlas trains only
on validated records, so no find can have trained the map it is scored on.
Each find, counted once per taxon and 5 km cell, is scored by its rank on
the map (half land in the top half by chance), the share in the top tenth,
the Boyce index, and whether it outranks the cells where other taxa's finds
landed in the same period, so that 50% is no better than knowing where
people collect. Results are reported by grade, pre-registered with the
criteria for supporting the grade's claim (Appendix S1: Section S6).

Atlas is compared on the same finds with two baselines (Appendix S1:
Section S7). The first knows only the distance to a taxon's known sites
(Bahn & McGill 2007; Hijmans 2012): a sum of Gaussian kernels over its
training survey sites, with the bandwidth (5 to 400 km) chosen on the
taxon's own spatial folds, re-ranked over each model's area of
applicability so that the two are scored on the same places. The second is Maxent as commonly run (default settings, a
random background, random cross-validation and a scattered null test).

### 2.6 Releases and reproducibility

A server pulls eligible records nightly and refits only taxa whose
fingerprint or settings changed, on spot instances running one pinned
container; each release is content-addressed and records the code commit,
package versions, layer builds and pull fingerprint, and archived releases
carry Zenodo DOIs. Exact coordinates never leave Atlas's private compute;
records whose location the source hides, obscures or may hide are left out
of every published record-level layer. On one processor family a rerun
reproduces the release byte for byte: 507 drawn models, refitted twice in
different orders and worker splits, matched it on all 507 (E12). The test
found one fault on the way: glmnet's settings are global to an R process,
so a small-model ensemble fitted after a Maxent model in the same worker
inherited Maxent's. Production fits each learner in its own pool of
workers, so by construction no released map is affected, which the
surviving shard logs and a first rerun matching the release confirm; each
fit now sets its own. Across processor families,
some tuned Maxent models choose other settings, and the spatial block,
estimated from a variogram, can differ for some taxa [PENDING E12 arm b:
how often grades differ across families] (Appendix S1: Section S10, which
also gives the cost and time of every run).

### 2.7 Pre-declared question: a place signal for photo identification

Whether the maps carry habitat information another system can use was
tested as registered before any result (Vision repository,
`docs/atlas-environment.md`, version b78609d): MycoMap Vision's photo
identifications with the continent-wide projection of strong maps,
weighted by trust, as their place signal, against no place signal, on
records first validated after 17 August 2026, with Atlas refitted on the
records before that date (Appendix S1: Section S9).

---

## 3. Results

*Everything here is pending the frozen release. Each subsection names its
figure or table and the analysis that fills it.*

### 3.1 The records and the taxa (E16)

[PENDING: records and taxa by source; sites per taxon (distribution, with the
3 / 20 / 50 thresholds); share provisional; where records are; validation lag
(median ~8 months [pre-freeze]).] → **Table 1**; detail in S2.

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
matched shift (2/49 false, 13/50 power). → **Figure 2**; every cell in S5.

### 3.3 What the atlas contains (E16)

*Provisional facts (2026-10-13; re-read from the frozen release before
submission).* Lineage: R_main 20261013T061352Z-78dd82de (job 20261013T022520Z-2cb67f32,
image 0a9dde4) → targeted refit 20261013T063926Z-375d779c (job
20261013T062143Z-2ffed182: *Clitocybe deceptiva* × 4 learners, *Agaricus
bitorquis* × 3, same image and settings) → *Elaeagnus umbellata* retired
20261013T133737Z-79fe85f3 (job 20261013T133656Z-6a0564db) → full-view
refresh 20261013T155140Z-026d3a26 (job full-20261013T140649Z-5cf5b864, image
8b8566f; 573 full views replaced, 3 Maxent models kept, listed in the
release record) → finished (v5) **20261013T191324Z-fa1b4198** = the frozen
release (continent export, prior, privacy-filtered cells: 130,466 records).

*Grades (`docs/experiments/2026-10-19-grade-tiers-fa1b4198.md`).* The
frozen release holds 9,041 models of 6,369 taxa. A further 441 taxa with
three or more sites were refused (412 of them at 3–4 sites), and 9,442 of
the pull's 16,252 taxa have fewer than three sites. Of the models, 576 are
strong (ensembles of small models 365, Maxent 121, random forests 85,
boosted trees 5), 6,667 weak, 1,801 failed and 1 untested; 470 taxa have a
strong map, 7.4% of those modelled and 2.9% of all. Most models that are
not strong miss on the null test alone (7,073 of 8,465). The strong share of
taxa rises with sites from 2.1% at 3–4 sites to 16.4% at 20–49, then falls
to 8.0% at 50–99, and none of the 52 taxa with 100 or more sites has a
strong map: their best models score below their own shifted nulls on
average (median z −1.36), although their held-out Boyce is high (median
0.84). At 3–4 sites, 45% of the small-model ensembles fail (median held-out
AUC of those 0.41). Counting the looser tiers, 1,816 taxa (28.5%) have a
strong or moderate map and 4,856 (76.2%) at least an indicative one; neither
tier beats distance to known records (Section 3.4), so both are drawn as
weak maps. Every count by learner, band and tier is in S4.

[PENDING: strong maps by guild and region; combined maps; share of reach
inside the area of applicability; and the standard test on real models
(E1c): the share of maps 19 scattered nulls call good that are not shown to
beat collecting.] → **Table 1**, **Figure 4** (example maps across grades); detail in S4.

### 3.4 How the maps did on records they never saw (E2, E6b, E3)

*Hindcast (E2, E6b; pre-registered, results as registered).* Refitted on the
124,955 records first validated by 17 August 2026, the pipeline fitted 8,606
models (509 refused); the records validated after the cutoff gave 7,509
later-find places (taxon × 5 km cell) across 3,655 taxa. Strong maps placed
91.4% of later finds in their top half (95% interval 88.6–94.2; 214 taxa),
weak maps 87.0% and failed maps 78.4%; the strong − failed difference was
13.0 points (9.0–17.2; 735 taxa). Strong maps also put 78.5% of finds
(76.3–80.6) above the cells where other taxa's finds landed, against 71.7%
for weak and 67.2% for failed maps, and 49.6%, 45.7% and 34.3% in their top
tenth. All three registered criteria hold. The order of the grades, not the
distance from 50%, is the evidence: even failed maps place most later finds
in their top half, because later finds cluster near earlier ones.

On the same places, the distance-only map placed 87.1% of strong-map finds
in its top half, so strong maps placed 4.4 points more (1.5–7.6; 202 taxa).
The gain is in the top-half share only; the mean rank of finds did not
differ (+0.004, −0.017 to 0.027). It came from far finds: within 25 km of
known sites distance alone did as well or better (97.4% against 100%), from
25 to 100 km the two tied (92.8%), and from 100 to 500 km strong maps led
(76.0% against 61.1%; descriptive, without intervals). At places more than
5 km from any training site the gain was about the same (+4.8 points) but on
fewer places, and its interval reached zero (0.0–10.0; 168 taxa). Weak maps
ranked later finds below the distance map (87.0% against 89.4% in the top
half), and so did both looser tiers, although each cleared its registered
bar against chance: moderate −1.4 points (−3.3 to 0.5; 628 taxa),
indicative −2.6 (−3.9 to −1.4; 1,571 taxa). Four training records later
found to have been validated after the cutoff were kept out of the test
finds (none was among them), and the one affected small-site model was
refitted without its record before scoring (Appendix S1: Section S6).

*Prospective tracking (E3).* [PENDING: rank of finds on the live release by
grade, against the distance map, from the tracker's start date.] Under the
grading live before the rebuild, records first validated 3–12 October at new
sites fell in the maps' top half 82% of the time, and maps that passed
the old scattered-null test barely beat those that did not (beats-effort
0.67 against 0.63), as C1 predicts (exploratory;
`2026-10-18-tracker-backfill-old-grading.md`).

→ **Figure 3**: (a) top-half and beats-effort shares by grade, each beside
the distance map on the same places, with intervals; (b) strong maps against
the distance map by distance band (5–25, 25–100, 100–500 km); (c) prospective
finds by grade (E3). Every split (new and known places, top tenth, Boyce,
tiers, inside and outside the area of applicability, combined maps, beyond
reach) in S6. Boyce is reported in S6 only: it is near 1 for every grade on
these finds and does not separate them.

### 3.5 Against standard practice (E6)

[PENDING: self-reported CV score vs independent-test score for each
approach.] → **Figure 3** (baselines beside the grades); detail in S7.

### 3.6 What sequence names change (E9, E16)

[PENDING: records whose sequence name differs from the record name (species,
genus) by source; for affected taxa, map rank correlation, grade changes and
independent-test skill under each labelling; the share of modellable taxa
with no formal name.] → one paragraph; detail in S8. (E6c, morphology-named GBIF models, if
run, goes to the Discussion.)

### 3.7 What drives the maps (E8)

[PENDING: permutation importance by predictor group, ectomycorrhizal vs other
guilds, strong maps only.] → Appendix S1: Section S3 only (one sentence in the main text).

### 3.8 Stability across nightly releases (E11)

[PENDING: map rank correlation and grade changes between releases against the
number of new records.] → Appendix S1: Section S10.

### 3.9 Q1: maps as a place signal for photo identification (E21, E22)

Registered before any result and reported as it came out
(`2026-10-18-q1-atlas-arms.md`): with Atlas refitted on records validated
by 17 August 2026 (414 strong taxa; only 7.1% of the 12,872 validation
finds have a strongly mapped true taxon), the declared primary arm, the
continent-wide projection of strong maps weighted by trust, raised species
top-1 from 53.8% to 54.3%. The declared test passes (McNemar p = 0.0001),
but mostly because the declared selection fell back to photos alone. Used
alone, the maps added 1.3 points and held the far-find band; but against
the distance kernel over the same DNA records that they were meant to
replace, they lost 0.2 points (55 fixed, 83 broken), on mapped truths at
matched depth. Beyond 500 km the projection was not supported (inside the
area of applicability 39% of 41 finds ranked at or above the median, 95% CI
26–54%; outside it, Boyce −0.26). The habitat rank does work as a cue for
whether an identification is right (AUC 0.61; 48%, 62% and 68% right from
the lowest to the highest third of suitability). So the answer to Q1 is
yes, weakly: the maps carry habitat information another system can use,
but no more than its own distance to known records, and not beyond the
modelled area.
→ one paragraph; the design and every arm in S9.

---

## 4. The data resource

*A combined paper carries what a data descriptor would: what is deposited,
how it was checked, and how to use it. Technical validation is Results 3.2–3.5
plus E12.*

### 4.1 Data records (E12, E19)

[PENDING: one table of every deposited file of the frozen release, with
Zenodo DOI, format, size and licence:]

- **Layers series** (Zenodo): the predictor rasters on the grid, with their
  sources. CC BY-SA 4.0 (WorldClim is share-alike). **Published:**
  doi:10.5281/zenodo.23463069 (concept doi:10.5281/zenodo.23463068), with
  Steve's approval, 2026-10-18: version draft-2026-09-30-df57c9d4, 11 files,
  0.14 GB. The frozen release's predictor stack has 69 bands in eight
  layers (counted from the deposited files and the manifest, layers key
  df57c9d4); the record's summary said 68 by mistake, and a metadata-only
  correction is with Steve.
- **Models series** (Zenodo, one version per archived release).
  **Published:** doi:10.5281/zenodo.23463939 (concept
  doi:10.5281/zenodo.23463938), the frozen release 20261013T191324Z-fa1b4198,
  26 files, 13.24 GB, derived from the layers record. Per model the
  suitability raster, AOA dissimilarity raster, map image and metrics JSON
  (scores, null test, grade, importance, settings); combined maps and
  disagreement layers; full-extent rasters for strong models; per-taxon
  counts; record cells at 0.1°; state verdicts; the location prior.
  CC BY-SA 4.0.
- **Training records** (new; Steve, 2026-10-13): published for the paper's
  frozen release(s) only; the per-release lists of trained records that the
  nightly pipeline keeps stay private. The ids of every record that
  trained the frozen release, one row each: source (iNaturalist, Mushroom
  Observer, MyCoPortal, GenBank, MycoMap sequence); source id; taxon (the
  DNA name used); the approved sequence id where that sequence is public at
  source (its mycomap.org sequence page or GenBank accession); the taxon
  fingerprint; and the survey-site id, blank for records hidden, obscured or
  of unknown privacy at source. No coordinates and no cells: the fingerprint
  and site id let a reader check each taxon's record set and site grouping
  without any location. (The pipeline's private per-release lists of trained
  records are a separate, unpublished file.)
  Each id resolves to its public source page, which shows what the source
  itself shows. **Privacy rule (Steve, 2026-10-13):** records whose
  location the source hides, obscures or may hide (unknown privacy) are
  excluded from all published record-level layers, and carry no survey-site
  membership in this table (about 800 records of unknown privacy in the
  rebuild's pull [CHECK: count in the frozen pull]). Obscured iNaturalist
  coordinates never train a model. [CHECK: licence of this table, CC0
  proposed.]
- **Record cells.** The 0.1° record cells (in every release, on the live
  site and as the Zenodo "collection-cells-0.1deg" bundle) leave out those
  records; the frozen release ships the corrected file.
- **Contributors** (Steve, 2026-10-13): one row per contributor with a name
  and record counts only. Names are as public at the source: the
  iNaturalist login, the Mushroom Observer user, the MyCoPortal collector,
  GenBank's own public submitter or author field, and, for MycoMap sequence
  records, the mycomap.org uploader. There are no record ids, species or
  places in it, so it cannot be joined to the training-record table to tie a
  person to a hidden-location record. Contributors may ask to be listed
  anonymously. [PENDING: the data, after the cutover, with the provenance
  table.]
- **Code**: the repository at the release commit, with a Zenodo software
  DOI, and the container image digest.

### 4.2 Versions

The paper cites one frozen release by id and DOI: the finished release of
the full-view refresh of the cleaned October 2026 release (section 2.1:
76 erroneous records removed in two cleanings), after its finishing step:
**20261013T191324Z-fa1b4198** [PENDING: DOIs]. The live atlas keeps
rebuilding nightly; every release stays in the content-addressed store, and
archived ones keep their Zenodo DOIs, so later maps never overwrite the
paper's.

### 4.3 Usage notes

[PENDING: how to read a grade; use strong maps only for claims; suitability
is not occurrence; AOA hatching; ranks are within-taxon; the API (best-map,
maps/best, prior; rate limits); citing a release; reusing CC BY-SA maps; how
to report a problem.]

### 4.4 What it costs (E23)

[PENDING: from the ledger in `costs.md`. Cost and wall time of one full
rebuild (EC2 spot compute, storage added); a typical nightly incremental
run; the standing monthly cost (server, storage, transfer); the cost of each
analysis in this paper; and CPU seconds per model by learner and by number of
sites, so that other groups can plan an atlas of their own.] → one line in **Table 1**; the full ledger in S10.

---

## 5. Discussion

*First prose draft, 2026-10-13 (~900 words). Results are placeholders; the
reading of each paragraph is fixed only once its numbers are in.*

**The cost of an honest grade.** Most of the atlas's maps are not strong:
576 of 9,041 models, and 470 of 6,369 modelled taxa. The
standard test, rerun on the same models, would have called [X]% of them
good [PENDING E1c]. That gap is the point of the method rather than a
shortfall of the data. On simulated species collected the way MycoMap's
records are, the scattered null passed most species that follow no habitat
at all, and every one with a hundred sites or more; the shifted null passed
almost none of them, and its strong maps placed records validated later
on higher-ranked ground than weak or failed maps, and than distance to known
records. A strong
grade therefore says something a high AUC does not: that the map beats the
species' own pattern of collecting on ground it never saw. The price is
power. A strong grade caught about a quarter of simulated species that did
follow a habitat, and more sites did not raise that share [PENDING E1: by
breadth and signal strength]. "Not strong" therefore means "not shown",
not "wrong", which is why weak and failed maps are published, faint and
labelled, rather than withheld. The two looser tiers within "weak" cleared
their registered bars against chance on later finds but did no better than
distance, so they are drawn as weak maps and carry no claims [PENDING E1:
their false-pass rates].

**Why shifted nulls are strict.** A shifted copy of a species' records keeps
its clustering, and on a continent whose climate varies smoothly it often
lands on similar ground. That is the objection raised against structured
nulls in the bird–climate debate (Araújo et al. 2009; Peterson et al. 2009;
Beale et al. 2009), and our results bear it out for broad habitats
[PENDING E1: power by breadth]. On the real models, none of the 52 taxa
with 100 or more sites has a strong map: their best models score, on
average, below their own shifted nulls, although they rank held-out ground
well. A strong grade is thus hardest to earn for the most widespread and
best-collected fungi; that is a limit of the test, not evidence that they
lack habitat structure [PENDING E1: power by sites and breadth]. The debate could not settle the question
because real species have no known truth. Simulated species collected at
real survey sites measure both error rates directly, and a reader can
choose a test by the error that matters to them: a scattered null that
passes most clustered species with no habitat signal, or a shifted null
that misses most real ones.

**For other automated atlases.** Any pipeline that fits thousands of models
to clustered occurrence data faces the same problem, whatever its learners.
Three practices carry over: grade each map against nulls that keep its own
clustering and stay on surveyed ground; calibrate that grade on simulated
species that inherit the real sampling, so its error rates are known; and
test the grade on records collected or validated after the maps were made,
against distance to known records and not only against chance. In our
hindcast a distance-only map placed 87% of later finds in its top half, so
a bar at 50% cannot tell a habitat map from distance, and our weak maps,
which clear it easily, did no better than distance. Where habitat adds
nothing over distance, a map should not claim otherwise. And because the grade is the contribution, an
atlas should report how many of its maps earn it, not only how many it
draws.

**For fungi.** Naming taxa by approved DNA sequences rather than by the
record's own name changed the maps of [PENDING E9] taxa, and about half the
modelled taxa have no formal name: they are sequence clusters that can now
be mapped as soon as they have enough sites. Community sequencing is
therefore what extends the atlas: each new site moves a taxon toward its
first map or toward a strong one. Host trees ranked [PENDING E8] for
ectomycorrhizal fungi and climate for the rest, consistent with the
partner-dependence of mycorrhizal fruiting.

**Limits.** The maps describe habitat suitability, not occurrence, and are
fitted to presences against other collectors' sites, not to true
absences, which MycoMap's own soil sequencing and published metabarcoding
data could supply [PENDING E4]. Host-tree layers stop at the two national
inventories, so Alaska, Hawaii, Puerto Rico and Mexico have climate and
soil but no trees; the climate is a 1970–2000 average; provisional names can
be re-clustered. The hindcast reads today's validation state, names and
coordinates for pre-cutoff records, and the design was chosen on data that
include later records [PENDING: the rebuild lane's list]. Seventy-six
erroneous records were removed by an exclusion list rather than a new pull,
which would have moved the validation cutoff, so other models' backgrounds
still include their sites (under 0.06% of records); and the frozen pull's
naming read some sequences it should have skipped, about 527 records named
only by them and 2,287 left out, corrected from the next release on
(Appendix S1: Section S2). The pull also lost 21 validated records (20
from Mushroom Observer, 1 from MyCoPortal) to a check for obscured
iNaturalist coordinates that matched by observation number alone, and the
hindcast's training set held at most four of its 124,955 records that were
in fact validated after the cutoff, through a similar mix-up of
first-validation dates; two of them trained models, one of which
(*Sparassis spathulata*, 15 sites) is refitted without it, and all four are
kept out of the scored test finds (both bugs fixed for later pulls). Some finds appear twice, posted to both
iNaturalist and Mushroom Observer: at least about 1,630 such pairs have both
records in the training data. For the 91% whose two points lie within 5 km,
site thinning counts the find once and only the effort predictor is
slightly inflated; about 146 pairs, in 132 taxa (39 with 3–19 sites), lie
further apart and may give their taxon a second detection site. In 131 of
them the far copy is a Mushroom Observer record whose own coordinates
Atlas could not check, so it kept mycomap.org's point, often a named
place's centre; about 11% of eligible Mushroom Observer records (880 of
8,003) were placed that way in the frozen pull. Fetching their Mushroom
Observer answers (2026-10-18) cuts the far pairs to 20 for the next pull
(Appendix S1: Section S2). Fits are deterministic within a processor family
but not across families: some tuned Maxent models choose other settings,
and some taxa's spatial blocks differ, by up to 240 km [PENDING E12 arm b:
the share of grades that change]. The maps can only be as good as where people collect and
sequence.

**Where habitat adds over distance.** Near known records, distance alone
ranked later finds as well as a strong map or better; the strong maps'
advantage came from finds 100 to 500 km away (Section 3.4). That is where a
habitat model should help, since it can say that unvisited ground resembles
occupied ground, and it is also where finds are fewest, which is why the
gain at new places has an interval that reaches zero. A map's use near
known records is therefore not prediction but description, of which
nearby ground is suitable; its predictive value lies at a distance, inside
the area of applicability.

**The question asked of MycoMap Vision.** Used as a photo-identification
model's place signal, the maps helped a little on their own but no more
than a simple distance to known DNA records, and the continent-wide
projection did not hold beyond 500 km (Q1; Section 3.9 and
`docs/experiments/2026-10-18-q1-atlas-arms.md`). The likeliest reasons are
coverage (under a tenth of identifications concern a strongly mapped
species) and that a habitat map and a distance kernel are built from the
same records; their one distinct use was as a cue to whether an answer is
right, which MycoMap is now designing for validators.

**What comes next.** Metabarcoding samples as an independent
presence–absence test and in integrated models; 1 km releases; projections
under future climates; and survey guidance that sends collectors where a
map is least certain and a find would most change it.

---

## 6. Title-page and back-matter statements

- **Open Research statement** (title page; draft for submission, ESA
  options 3 and 6): "Novel code (the MycoMap Atlas R package, API and
  pipeline, GPL-3.0-or-later) is available at
  https://github.com/BiodiverseLabs/mycomap-atlas and will be archived on
  Zenodo with a DOI for the release commit upon acceptance. Data are
  provided on Zenodo: the environmental layers (doi:10.5281/zenodo.23463069),
  and every
  model of the frozen release (doi:10.5281/zenodo.23463939; suitability and area-of-applicability rasters,
  metrics, grades), and the table of training records with their
  iNaturalist, Mushroom Observer, MyCoPortal and GenBank identifiers. Record
  coordinates are those published by each source; records whose location is
  hidden, obscured or of unknown privacy at the source are excluded from all
  published record-level layers." [PENDING: DOIs; data
  citations for WorldClim, SoilGrids, ESA WorldCover, BIGMAP, the Canadian
  NFI, NALCMS, Copernicus and FungalTraits; query details for the
  mycomap.org pull, Appendix S1: Section S2.]
- **Acknowledgments** (one paragraph): collectors, validators, the
  sequencing network, data providers [PENDING: Steve to choose; proposal
  below, after community-science practice], and the AI disclosure: "Much of
  the pipeline's code and the first drafts of this manuscript were written
  with an AI assistant (Claude, Anthropic; model versions in Appendix S1)
  under the author's direction; the author reviewed all code and text and is
  responsible for them." The same disclosure goes in Methods 2.6 and on the
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

## Main text and supplement (Steve, 2026-10-13)

The main text stays short and carries only the claims and the evidence that
decides them; everything else goes to one Appendix S1 with sections (the
journal's preference). Data tables go to Zenodo, never the appendix.

**Budget for the main text:** about 5,500 words (abstract ≤ 350;
Introduction ~800; Methods ~1,800; Results ~1,400; data and reuse ~300;
Discussion ~900), about 55 references, four figures and two tables. In the
journal's layout (double-spaced, 12 pt, references, tables, captions and
figures all counted) that is about 41 pages, just over the Method type's
40-page minimum; if it falls short, a fifth figure comes back from the
appendix rather than words being added.

| Section | Stays in the main text | Moves to Appendix S1 |
|---|---|---|
| 1 Introduction | the problem, the gap, C1–C4 and Q1 in a paragraph | — |
| 2.1 Records | DNA-defined taxa, validation in two sentences, the eligibility rule in one paragraph | S2: validation provenance, every rule with counts, the data errors and exclusion list, query details, contributors |
| 2.2 Predictors, sites, models | two paragraphs: layers by group, target-group survey sites, the learners and nested spatial CV | S3: the 69 predictors, pruning and host allowance, layer sweeps, importance (E8); S4: model settings, tuning grids, small-site ensembles, thresholds |
| 2.3–2.4 Null test and calibration | in full: the shift null, the grade, the simulated-species design | S5: generator details, every cell, effort arms (E14), the earlier study (E1b) |
| 2.5 Independent tests and baselines | in full but brief: hindcast, tracker, scores, baselines | S6: every split; S7: baseline details |
| 2.6 Releases and reproducibility | three sentences | S10: release format, tolerances, rerun (E12), stability (E11), cost and time (E23) |
| 2.7 / 3.9 Q1 | one paragraph each | S9: the registered design, every arm, projection validity |
| 3 Results | calibration (C1), the atlas by grade (C4), independent tests against baselines (C2), sequence names (C3, one paragraph) | S5–S10 |
| 4 Data and reuse | one paragraph: what is deposited, the frozen release, licences, one line of cost | S11: the deposit table and usage notes; S10: the cost table |
| 5 Discussion | grades and power, implications for automated SDM, fungi, limits | — |

**Main display items**

| # | Content | Claim | Source |
|---|---|---|---|
| Figure 1 | How a map is graded: pipeline in one strip, with scattered vs shifted nulls drawn on one species | C1, C4 | schematic |
| Figure 2 | Null calibration: false-pass rate and power by design and number of sites (power curve by breadth and signal strength as small panels); inset: the share of real maps a standard test calls good that are not strong (E1c) | C1 | E1, E1c |
| Figure 3 | Independent tests: where later finds fall on strong, weak and failed maps, against the distance-only and default-Maxent baselines; new vs known places | C2 | E2, E3, E6a/b |
| Figure 4 | Example maps across grades (strong ectomycorrhizal, strong saprotroph, weak, small-site), with applicability hatching | C2, C4 | frozen release |
| Table 1 | The atlas at a glance: records, taxa (share provisional), maps by grade and learner, cost and wall time of one rebuild and per month | C3, C4 | E16, E23 |
| Table 2 | Each claim, its test, its criterion and the result | all | — |

**Appendix S1 sections**

| Section | Content | Evidence |
|---|---|---|
| S1 | ODMAP protocol | E17 |
| S2 | Records and data quality: eligibility with counts, validation provenance, coordinate rules, data errors and the exclusion list, query details, contributor table | E16, E19 |
| S3 | Predictors, selection, layer sweeps, variable importance by guild | E8 |
| S4 | Models: settings, tuning, small-site ensembles, area of applicability, thresholds and verdicts | E18 |
| S5 | Null-test calibration in full; effort handling; the earlier study; the standard test on real models | E1, E1b, E1c, E14 |
| S6 | Independent tests in full: every split (distance, applicability, learner, site band), combined maps, the tracker | E2, E3, E10, E15 |
| S7 | Baselines: default-practice Maxent, distance-only, morphology-named models | E6a, E6b, E6c |
| S8 | Sequence names vs record names; sensitivity to sites, validation level, coordinate precision, old records | E9, E7 |
| S9 | Q1: MycoMap Vision's place signal, the registered design and every arm | E21, E22 |
| S10 | Releases, reproducibility, stability across nightly releases, cost and time | E11, E12, E23 |
| S11 | Data records and usage notes | E19, E20 |

Moved out of the main text from the earlier plan: the records map and
site-count figure, the predictor table, the sequence-name figure, the
drivers figure, the Q1 figure, the models-by-grade table (folded into
Table 1) and the cost table (a line in Table 1, full in S10). Maps in
figures need latitude and longitude, a north arrow, a scale bar and a
border.

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
| E1 | **Pre-registered** (`docs/experiments/2026-10-13-prereg-e1-null-calibration.md`, amended 2026-10-13 before launch). Null calibration rerun: false pass and power by design × site band × habitat breadth × signal strength × learner (Maxent, RF, ESM), so power is a curve; map-to-truth ρ by grade | C1, C2 | Pre-freeze: 99 species, Maxent, 3 designs; power flat with sites (E1b) | `study-virtual` on the frozen pull and layers. Full models: habitat 5 site bands × 2 breadths × 2 signal strengths × 60 = 1,200, geography 5 bands × 2 centre counts × 80 = 800; Maxent and RF; scatter and shift ×99, stop at 5. ESM: 3 bands × (habitat 2 strengths × 80 + geography 120) = 840. Effort arms (E14) on the same species. Sizes doubled 2026-10-13 after the calibration pilot (`2026-10-13-e1-cost-pilot.md`) | est. 540–920 CPU-h ($27–46), pilot-scaled (`2026-10-13-e1-cost-pilot.md`), with an allowance for 200+ sites | P1 |
| E1c | **Planned** (`docs/experiments/2026-10-13-plan-e1c-standard-test-real-models.md`). Real models: share of the frozen release's maps that pass the standard test (19 scattered nulls, the old production design) but not the shift test | C1 | Shift results exist for every model of the frozen release; scatter does not | Scatter ×19 on a sample stratified by learner × site band × grade (~50 per cell, ~1,000 models); report the share with a CI, weighted to the release | est. 100–200 CPU-h ($5–10), ~1 day code | P1 |
| E2 | **Done 2026-10-19, C2 supported** (study-20261019T181851Z-35fc3d63; H2a 0.914 [0.886, 0.942], H2b 0.131 [0.090, 0.172], H2c 0.785 [0.763, 0.806]; tiers H2d–f hold; Results 3.4). **Pre-registered** (`docs/experiments/2026-10-13-prereg-e2-hindcast.md`). Hindcast: full graded job on records first validated ≤ 2026-08-17; score later finds by grade, new vs known places | C2 | **Approved 2026-10-13**: Vision's training run becomes this full graded job (nulls on, private never-promotable release); code ~1–1.5 days in the rebuild lane, after the full-view refresh | Cutoff-filtered pull; test set = first green > cutoff (optionally observed > cutoff); undated records dated or excluded, with a count | ~250–500 CPU-h ($10–25), runs after the cutover on Steve's go | P1 |
| E3 | Prospective tracker by grade | C2 | Built; ships at the rebuild cutover; backfill from 2026-10-03 | Daily scoring of new finds on the live release | ~0 compute; needs months of finds (3–6) | P1 (clock starts at cutover) |
| E9 | **Planned** (`docs/experiments/2026-10-13-plan-e9-record-names.md`); the refit runs as a private job (`plan-job --record-names`, on feat/hindcast ba03e73), the experiments lane builds only the comparison. Sequence names vs record names: refit affected taxa both ways | C3 | Counts yes (4,878 records with a different species or genus; ~1,435 taxa with ≥10 localities change) [pre-freeze]; refits no | Production (sequence names) is the frozen release; refit every taxon whose record set differs under record names (full graded fits, all learners); map Spearman and Schoener's D, grade changes, E2/E3 skill | est. 150–300 CPU-h ($8–15), 2–3 days | P1 |
| E6a | **Planned** (`docs/experiments/2026-10-13-plan-e6a-default-maxent.md`). Default-practice Maxent on the hindcast pull (maxnet default.features, regmult 1, 10,000 uniform background points over the accessible area, random 5-fold CV, 19 uniform nulls as commonly run) | C1, C2 | No | New study arm over every taxon with ≥20 sites; its own CV score and pass rate vs its score on E2/E3 finds | est. 230–300 CPU-h ($12–15), from the cost pilot (`2026-10-13-e6a-cost-pilot.md`) | P1 |
| E6b | **Done 2026-10-21** (study-20261020T232528Z-05216058): H6b holds, +0.0435 [0.0147, 0.0755], top-half share only; new places [0, 0.0996] not; moderate and indicative do not beat the kernel; advantage from 100–500 km finds (Results 3.4). **Pre-registered** (`docs/experiments/2026-10-13-prereg-e6b-distance-baseline.md`). Spatial-only baseline (distance to known sites), paired with each model on its own AOA cells. **Runs first after E2**, because its result shapes C2's wording | C2 | No (shift nulls are related but not a baseline) | Kernel/distance model on the hindcast's training sites; scored on the E2 finds with the E2 metrics | small compute, ~2 days code | P1 |
| E12 | **Running**: gate 2 passed (bit-identical within a processor family; the refresh's three Maxent flips are the family); a1 and the rerun of a2 match the release on 507/507; a2's first run found the glmnet-settings leak into ensembles, fixed (Atlas 5b58f30), released maps unaffected by construction (separate worker pools per learner; surviving shard logs; a1 = release on 507/507); the variogram block depends on the family (35 of the 1,144 hindcast taxa fitted on r7a; up to 240 km); arm b (r7a, on-demand) running, then the block-only step. Plan: `docs/experiments/2026-10-13-plan-e12-grade-stability.md`. Reproducibility and GRADE STABILITY: step 0, read-only scores of the 576 refreshed models vs release; gated on a same-machine test of the two taxa; then full graded refits of ~600–900 stratified models on r7i twice (second with a different shard split and order), on r7a once, plus the release itself, measuring grade agreement (κ), setting flips, |Δ| AUC/Boyce/p/strength and map tolerance. First evidence: 3 of 576 strong Maxent models changed setting on refit, 2 with every candidate's CV score moving; mechanism unknown. Gate: per-model machine records (feat/result-machine); Zenodo DOIs for layers, models, code | C4 | Machinery yes (fingerprints, pinned image, content-addressed store, refit tolerance checks, shard records name instance/CPU/BLAS); demo no; layers deposit held | Fresh workers; stratified sample; both families | cost from R_main's recorded seconds × 3 (step 0; first guess 30–60 CPU-h likely low) | **P1, raised**: a grade that changes with the machine weakens C4 |
| E17 | ODMAP protocol (`docs/paper/appendix-s1-odmap.md`) | all | **Draft 2026-10-13**; final check against the frozen release | Writing from Methods + code | 1–2 days | P1 |
| E4 | Presence–absence test: GlobalFungi + MycoMap soil cores, by UNITE species hypothesis | C2 | No | Feasibility first: how many Atlas taxa map 1:1 to an SH with enough North American samples | Feasibility 2–3 days; full 1–2 weeks; small compute | P1 feasibility, P2 full |
| E6c | Morphology-named GBIF Maxent for formally named species, scored on DNA-defined finds | C3 | No | GBIF download with DOI; name matching; same pipeline | ~100 CPU-h, ~1 week | P2 |
| E7 | Sensitivity: (a) site count (thinning study), (b) validation level (automatic-only verdicts excluded, −11%; manual verdicts only; ≥ 2 projects; no rejection anywhere; needs per-record validation provenance joined to the frozen pull), (c) coordinate precision (1 vs 5 km; MO/MyCoPortal rules), (d) pre-1980 records | C2, C4 | (a) pre-freeze, 118 taxa, old nulls; (b–d) no | Paired arms on a stratified ~150-taxon panel; skill, map correlation, grade changes | ~20–40 CPU-h per arm, ~1 week | P2 |
| E8 | Variable and layer importance by guild | secondary | Yes in every model's metrics; layer sweeps pre-freeze | Aggregate over strong maps from the release | ~1 day, read-only | P2 |
| E10 | AOA and extrapolation: share of reach inside AOA; finds inside vs outside | C2 | Partly (per-model applicability; tracker counts outside-AOA finds) | Release + E2/E3 | ~1 day | P2 |
| E11 | Stability across nightly releases | C4 | No; releases are kept indefinitely | Per-taxon rank correlation and grade flips vs new records | ~2 days code, ≥4 weeks of nightlies | P2 |
| E14 | Effort handling on virtual species | methods | Pre-freeze, 198 species | Rerun inside E1 | inside E1 | P2 |
| E15 | Combined map vs its members on independent finds | C2 | No | From E2/E3 | hours, after E2 | P2 |
| E18 | Small-site maps: grades and power at 3–19 sites (ESM alone there; ESM also runs at 20–49 beside Maxent and RF) | secondary | Pre-freeze (thinning study; first-build pass rates) | Inside E1 + E7a | inside E1 | P2 |
| E5 | Expert and checklist comparison: state verdicts vs independent checklists; expert ranges for ~20 well-known taxa | C2 | No | Curated panel; expert time | 1–2 weeks, mostly expert time | P3 (P2 if a reviewer-friendly panel exists) |
| E6d | biomod2-style default ensemble | C2 | No | Same sites | ~1 week | P3 |
| E13 | Block-size check (kNNDM-style distance matching) | methods | Pre-freeze, 153 taxa | Rerun `study-blocks` | ~10 CPU-h | P3 |

**Order:** see the Path section below.

| ID | Also needed for a combined paper | Priority |
|---|---|---|
| E19 | Training-record table for the frozen release (source, source id, taxon, public sequence id, fingerprint, survey-site id blank where the source hides the location; no coordinates or cells) and its Zenodo record; built after the frozen release | P1 |
| E20 | Data-records table and usage notes (section 4) | P1 |
| E24 | **E2 half done**: both tiers clear their chance bars on later finds but not the distance kernel, so they carry no claims and are drawn as weak (Steve, 2026-10-20, chosen after E6b and reported as such); E1 half pending. Looser map tiers (moderate, indicative) judged on simulated species (E1) and later finds (E2), pre-specified with the thresholds Steve's choice will be read against (`docs/experiments/2026-10-13-plan-map-tiers.md`; Steve, 2026-10-13: "some form of map for most species") | P1 |
| E23 | Cost and time ledger (`costs.md`): per run, CPU-hours, billed instance-hours, instance types, wall time, compute USD, storage added; standing monthly costs (Steve, 2026-10-13) | P1 |

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

**Paused and resumed 2026-10-18 (Steve).** Vision's curation fixes go to
a later v2; the v1 cutoff of 2026-08-17 holds, so the hindcast (E2, also
Vision's training run) proceeds exactly as pre-registered. Its dry run from
the frozen release keeps 124,955 of 133,235 records, none undated. Launch on
Steve's direct go through the operations lane.

Set 2026-10-13 with the Atlas coordinator after Steve's revision. Every launch
gets Steve's direct go through the operations lane; every run gets a
`docs/experiments` entry, pre-registered where there is a hypothesis.

| # | Item | Gate | Target |
|---|---|---|---|
| 0 | Rebuild cutover: **done** 2026-10-13 23:03 UTC (atlas.mycomap.org serves 20261013T191324Z-fa1b4198, image bc2a7a5, shift grading; the full-view toggle is off on the site by Steve's choice, the full-extent rasters are in the release). Nightly tracking (E3) starts once the tracker backfill and daily unit are on | Steve's go | E3 start date [PENDING] |
| 1 | Full-view refresh → **frozen release**: **done**, 20261013T191324Z-fa1b4198 (2026-10-13); then the Zenodo re-archive (layers, models, training records, contributors) | Steve's go, after the cutover | October 2026 |
| 2 | **E2 hindcast** (also Vision's training run; Q1's Atlas input) | **done**: run 2026-10-18 (priv-20261018T171648Z-9e3ab153), scored 2026-10-19 in one run with the *Sparassis spathulata* refit (study-20261019T181851Z-35fc3d63); C2 supported | done |
| 2b | **E12 first step** and same-machine gate | **done** 2026-10-19: deterministic per processor family | done |
| 3 | **E6b** distance-only baseline on the E2 finds | **done** 2026-10-21 (study-20261020T232528Z-05216058); then Steve's post-hoc tier rule (plan-map-tiers, 2026-10-20) | done |
| 4 | **Presubmission inquiry** to Ecological Monographs | E2 and E6b numbers are in: redraft `presubmission-inquiry.md`, then Steve sends | November 2026 |
| 5 | **E1c** standard test on real models | rebuild-lane code; the frozen release | November 2026 |
| 6 | **E1** virtual-species calibration (pre-registered, amended) | breadth and strength knobs in `study-virtual`; tier fields (study/calibration-tier-fields 520fac9) merged; Steve's go | November 2026 |
| 7 | **E9** sequence vs record names | the same private-job code (`--record-names`); comparison code (experiments lane); Steve's go | November 2026 |
| 8 | **E6a** default-practice Maxent | new study arm; Steve's go | November–December 2026 |
| 9 | **E12** reproducibility rerun (**running**: a1 and a2 = release 507/507, glmnet leak fixed 5b58f30, arm b on r7a under way); E16 descriptives; E17 ODMAP | the frozen release; per-model machine records (feat/result-machine c099bc7, awaiting Steve's review; best merged before the hindcast so every paper job records which processor fitted each model) | December 2026 |
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
3. **Frozen release: settled.** 20261013T191324Z-fa1b4198 (finished
   2026-10-13 19:13 UTC). The hindcast plans from it. Steve item after the
   cutover: the Zenodo re-archive from it (layers, models, training-record
   ids, contributor table), discarding the layers draft held since
   2026-09-29.
3b. **Map tiers (Steve, 2026-10-13):** looser tiers below "strong" so most
   species get some form of map; rules and the evidence thresholds fixed
   before E1 and E2 (E24). Steve chooses which tiers feed which products
   after both results; whether they appear in the paper is separate.
   **Decided 2026-10-20 (Steve), after E6b:** a tier carries downstream
   claims only if it beats the distance-only map, so only strong does;
   moderate and indicative stay drawn as faint weak maps
   (`2026-10-13-plan-map-tiers.md`). Stated in the paper as chosen after
   the result. E1's tier rates are still reported as registered.
4. **Crediting contributors:** the full plan in section 6 adopted (Steve,
   2026-10-13). No individuals named for now (Steve, 2026-10-13); revisit
   before submission. Data item: observer name or username per training record for the
   Zenodo contributor table (asked of the coordinator).
5. **Zenodo:** both records PUBLISHED with Steve's approval: layers
   doi:10.5281/zenodo.23463069 and models doi:10.5281/zenodo.23463939
   (creators Russell, Stephen D., then MycoMap.org; CC BY-SA 4.0). The
   training-record and contributor tables (E19, E20) follow.
6. **Training-record table columns:** settled 2026-10-13 (section 4.1):
   source, source id, taxon, public sequence id, fingerprint, survey-site id
   (blank where the source hides the location). Built as E19 after the frozen
   release. The 0.1° cells question is settled too.
7. **Reproducibility across processor families (Steve, after E12 arm b):**
   whether future releases measure each taxon's spatial block once and
   reuse it across learners and machines, and/or force one OpenBLAS kernel
   (or pin the processor family), so that a refit on another machine gives
   the same folds and settings. Affects releases after the frozen one, and
   how 2.6 and S10 state reproducibility.

---

## Changelog

- **0.16.6 (2026-10-19).** 69 predictor bands confirmed from the deposit.
- **0.17.1 (2026-10-21).** grade_tiers written up (3.3, C4, abstract,
  Discussion): 9,041 models of 6,369 taxa, 576 strong of 470 taxa; none
  strong at 100+ sites. The earlier 9,042 was R_main's fitted count
  (costs.md), before the release's later steps.
- **0.17.0 (2026-10-21).** E2 and E6b written up: Results 3.4, C2,
  abstract, Methods 2.3 (tiers, the post-hoc distance bar) and 2.5 (kernel).
- **0.16.5 (2026-10-19).** Models record published
  (doi:10.5281/zenodo.23463939); both data records cited.
- **0.16.4 (2026-10-18).** First DOI: Zenodo layers published; hindcast
  finished (8,606 fitted, 289 CPU-h, ~$5.71).
- **0.16.3 (2026-10-18).** Limitations: at most 4 of 124,955 hindcast
  training records were post-cutoff; test-find exclusion list sent to the
  experiments lane.
- **0.16.2 (2026-10-18).** E2 deviation: exact check, two records trained
  hindcast models.
- **0.16.1 (2026-10-18).** E2 deviation logged before scoring (≤ 4
  post-cutoff records in training, excluded from scoring); obscured-check
  number collision (21 records lost) in Limitations.
- **0.16 (2026-10-18).** Q1 answered (Vision place-signal arms on the
  hindcast): weakly yes; loses to the DNA kernel by 0.2 points; projection
  not valid beyond 500 km. Hindcast release recorded.
- **0.15.8 (2026-10-18).** ESM range corrected to 3–49 sites (ESM alone at
  3–19); privacy wording mirrors the Zenodo records (hides, obscures or may
  hide).
- **0.15.7 (2026-10-18).** Tracker backfill under the old grading logged
  as background for E3 (new sites 82% top half; old pass vs not barely
  separate).
- **0.15.6 (2026-10-18).** Twins after the Mushroom Observer backfill: 20
  far pairs in the next pull (the frozen pull keeps 146).
- **0.15.5 (2026-10-18).** Twins: the 146 far pairs touch 132 taxa (39
  small-site), mostly unchecked Mushroom Observer points (880 of 8,003
  eligible MO records).
- **0.15.4 (2026-10-18).** Cross-posted twins quantified (~1,630 pairs;
  146 over 5 km apart may double a detection site).
- **0.15.3 (2026-10-18).** Resumed: v1 cutoff holds, the hindcast proceeds
  as pre-registered (dry run 124,955 of 133,235 records kept, 0 undated);
  cross-posted twin records added to Limitations.
- **0.15.2 (2026-10-18).** Paper runs paused by Steve pending Vision v2
  curation.
- **0.15.1 (2026-10-13).** Cutover done (23:03 UTC); E3 start date pending.
- **0.15 (2026-10-13).** Frozen release pinned: 20261013T191324Z-fa1b4198,
  with its full lineage.
- **0.14 (2026-10-13).** Abstract skeleton (under 350 words) with
  placeholders.
- **0.13 (2026-10-13).** Discussion drafted as prose (~900 words) with
  placeholders for results.
- **0.12 (2026-10-13).** Methods cut to the lean budget (~1,700 words);
  the previous text moved unchanged into Appendix S1 Sections S2 (S2.0),
  S3, S4, S9 and S10.
- **0.11 (2026-10-13).** Looser map tiers pre-specified (E24): moderate
  (shift p ≤ 0.20), indicative (AUC > 0.5, Boyce > 0), with a continuous
  variant; added to the E1 and E2 pre-registrations as secondary analyses.
- **0.10.1 (2026-10-13).** Reproducibility: scores of the other 573
  refreshed models identical; same-machine refits bit-identical.
- **0.10 (2026-10-13).** Second cleaning recorded (54 non-fungal records;
  76 removed in all; 129-id list); data-error and limitation passages cut
  to a few sentences with the detail in Appendix S1: Section S2.
- **0.9.10 (2026-10-13).** Frozen release = the refresh's finished release
  (id pending); E12 first step placed right after the hindcast, with its
  stop rule.
- **0.9.9 (2026-10-13).** Reproducibility: of the three changed Maxent
  fits, one is a near-tie and two had every candidate's score move across
  machines (mechanism unknown); E12 becomes a planned grade-stability test.
- **0.9.8 (2026-10-13).** Reproducibility claim corrected: 573 of 576
  strong models refit within float32 tolerance; 3 tuned Maxent models chose
  different settings (originals kept); "across machines" until the
  processor per model is known; E12 extended.
- **0.9.7 (2026-10-13).** Naming limitation: a third kind (sequences
  flagged as another observation's), ≈ 527 named / ≈ 2,287 left out.
- **0.9.6 (2026-10-13).** Naming limitation widened to contaminant-flagged
  sequences as well as set-aside ones (≈ 502 records named by them, ≈ 2,281
  left out).
- **0.9.5 (2026-10-13).** Provisional strong-map count (576 models, 470
  taxa, ~7%) in C4 and the Discussion; the like-for-like old-test
  comparison is E1c.
- **0.9.4 (2026-10-13).** Limitation: set-aside ("trash") sequences used
  for naming in the frozen pull (≈ 380 records named by them, 2,023 left
  out), fixed from the next pull.
- **0.9.3 (2026-10-13).** Provisional rebuild facts and release lineage
  (3.3, costs.md).
- **0.9.2 (2026-10-13).** Steve: no refit for background exposure; shares
  stated openly (18 taxa above 1%, 71 above 0.5%, all small-site).
- **0.9.1 (2026-10-13).** Limitation quantified: 19 of 8,803 survey sites;
  median 0.13% (max 0.45%) of a model's background sites.
- **0.9 (2026-10-13).** Lean main text, detail to the appendix (Steve):
  a word budget (~5,500), four figures and two tables in the main text, and
  Appendix S1 reorganised into sections S1–S11.
- **0.8.3 (2026-10-13).** Limitations paragraph and exclusion-list note on
  the targeted fix, from the rebuild lane.
- **0.8.2 (2026-10-13).** How the mislabelled rows were found: Vision's
  photo audit (to confirm with Steve).
- **0.8.1 (2026-10-13).** Data-error paragraph with the exact taxa and the
  skunk record.
- **0.8 (2026-10-13).** Data errors found and removed (75 mislabelled
  iNaturalist ids; 22 in the pull): the frozen release is the refresh of a
  cleaned release, and the hindcast reads the cleaned pull.
- **0.7.9 (2026-10-13).** E1 species per cell doubled (counts only) after
  the calibration pilot priced the study at about a fifth of the estimate.
- **0.7.8 (2026-10-13).** Hindcast code pushed early (feat/hindcast
  ba03e73), checked against the E2 pre-registration; E9 runs through the
  same private-job code.
- **0.7.7 (2026-10-13).** Cost and time ledger (E23, `costs.md`), section
  4.4 and Table 5 (Steve).
- **0.7.6 (2026-10-13).** Training-record table columns settled (E19).
- **0.7.5 (2026-10-13).** Predictors corrected to the production layer
  manifest: 69 bands, 29 host genera + conifer share (the public Methods
  page says 75 and 16 further genera); background cap 10,000 non-detection
  sites; no external name authority (ODMAP).
- **0.7.4 (2026-10-13).** Verified reference list (`references.md`, 44
  entries, two datasets without DOI); Introduction cites the fungal SDM review
  and the Red List gap.
- **0.7.3 (2026-10-13).** Tolerances corrected to float32 storage
  precision; record-level privacy rule applied to the 0.1° cells (about 0.5%
  of records dropped, no refit); training-record columns to confirm.
- **0.7.2 (2026-10-13).** Contributor table confirmed by Steve: names by
  source as public there, counts only, opt-out.
- **0.7.1 (2026-10-13).** ODMAP protocol drafted (Appendix S1, Section S1).
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
