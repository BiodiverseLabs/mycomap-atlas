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
| Frozen release | The finished release of the full-view refresh of the *cleaned* October 2026 release: the rebuild, then a targeted release that removes 75 mislabelled record ids (2 fungi refitted, 18 non-fungal names dropped), then the full-view refresh (default maps, grades and ranks unchanged; full-extent rasters without border gaps) [PENDING: ids, Zenodo DOIs, code commit]. Zenodo archiving waits for it. |
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
   ([S/M]%) are strong. (Provisional, from the refresh's dry run: 576 strong
   models across 470 taxa, about 7% of ~6,811 modelled taxa, out of 9,042
   fitted models; by learner Maxent 121, random forest 85, boosted trees 5,
   ensembles of small models 365.) The strong share is stated plainly: most maps are
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

*Data errors found and removed.* Seventy-five mycomap.org rows had a wrong
iNaturalist id: sequencing sheets had labelled Mushroom Observer specimens
"iNat<n>", so the records pointed at unrelated iNaturalist observations
under the same number. The error was first seen by hand on one sequence on
2026-09-30. The 75 rows were found on 2026-10-13 by an audit of MycoMap
Vision's training photos, where records validated as fungi showed birds and
mammals [CHECK: confirm with Steve]. Twenty-two of them were in the pull. Two gave a fungus
one false site each (*Clitocybe deceptiva*, 1 of 53 sites; *Agaricus
bitorquis*, 1 of 25). The other 20 put 18 non-fungal names into the taxa
list with one or two sites each, too few for a model: seven birds (nine
records), two mammals (coyote, raccoon), three insects, two ferns and four
flowering plants. The false *Clitocybe deceptiva* site was an iNaturalist
observation of a striped skunk, labelled by its fungal sequence: the
pipeline did exactly what it was built to do with a wrong link, which is
why the paper reports data errors as well as model errors. The 75 ids are
excluded from the frozen release; the two fungi are refitted and the 18
names dropped. The full list is in Appendix S1: Section S2. The exclusion
list of 75 mycomap.org record ids is applied to the frozen pull and to
every later pull; each pull's manifest records the list's SHA-256 and the
number of rows removed (Atlas commit 643b444).

Each taxon's record set is hashed into a fingerprint. A model belongs to its
record set, not its name: it is refitted when the fingerprint changes, and a
provisional name can be renamed or re-clustered without leaving a stale map.

[PENDING E16: Table 1 (counts); Appendix S1: Section S2, records by source and where records
are (0.1° cells) and how they cluster.]

### 2.2 Study region, grid and predictors

Everything is modelled on a North America Albers Equal Area Conic grid with
5 km cells (3.7 million cells); the frozen release is on this grid. The
pipeline also defines a nested 1 km grid, which no release used here.

Sixty-nine predictor bands in eight layers (Appendix S1: Section S3): 19 WorldClim 2.1
bioclimatic variables (1970–2000) and elevation (Fick & Hijmans 2017); slope
and roughness derived on the grid; topsoil (0–5 cm) pH, organic carbon, total
nitrogen, clay, sand and cation exchange capacity from SoilGrids 2.0 (Poggio
et al. 2021); six land-cover fractions from ESA WorldCover (Zanaga et al.
2021); the share of a cell's trees in each of 29 host genera (19 mainly
mycorrhizal hosts plus the conifer share, and 10 genera hosting decay and
parasitic fungi: maple, ash, elm, juniper, cedar, tulip tree, cherry,
sweetgum, sycamore, black locust), from BIGMAP in the United States (USDA
Forest Service FIA, n.d.; Wilson et al. 2018) and the Canadian National
Forest Inventory kNN maps (Beaudoin et al. 2014), with a flag where neither
inventory reaches (Alaska, Hawaii, Puerto Rico, Mexico); and needleleaf,
broadleaf and mixed forest shares from NALCMS (CEC 2023), filled from
Copernicus Global Land Cover (Buchhorn et al. 2020) on Hawaii and the
Caribbean, with a flag. The tree models also take log collecting effort;
Maxent does not. [CHECK: the frozen release's layer manifest (sha256) once
the rebuild finishes; the count above is from the rebuild lane's copy.]

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
A rerun on the same machine reproduces maps byte for byte; we verified
this for Maxent, random forests and boosted trees, tuned and untuned, with
and without null tests. Across machines, results agree to floating-point
precision rather than bitwise (OpenBLAS selects its matrix kernels by
processor, and the area-of-applicability index is computed through one of
them): equal to within float32 storage precision (four rounding steps),
suitability to a relative 5e-7 and the index to an absolute 1e-6 (or a
relative 5e-7 where larger), where a genuinely different model differs by
1e-4 or more. Refitting the frozen release's 576 strong models for the
full-view refresh met these tolerances for 573. The other three are tuned
Maxent models whose settings choice differed: one near-tie (*Russula* sp.
'compacta-PA01'), and two (*Stropharia hardii*, *Gliophorus fumosus*) where
the cross-validated scores of every candidate differed across machines,
from the same records and background; the mechanism is under
investigation (E12). The release keeps their original fits and lists both
fits' settings and tuning scores. Because the refit check compares maps,
not held-out scores, E12 measures how stable scores and grades are across
reruns and machines [PENDING E12]. Our refit checks enforce the tolerances
and flag anything beyond them.

Published records follow their source's privacy: records whose location
is hidden, obscured or of unknown privacy at the source are excluded from
all published record-level layers. In practice that is the 0.1° record
cells, from which about 0.5% of records (those of unknown privacy, whose
0.1° cell would be finer than iNaturalist's own obscuring) are dropped; no
model is refitted. Everything else published is map-derived or coarse
(state counts, the 500 km accessible area). The frozen release ships the
corrected cells file.

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
submission).* Lineage: rebuild release R_main 20261013T061352Z-78dd82de
(job 20261013T022520Z-2cb67f32, image 0a9dde4) → cleaned release (targeted
refit job 20261013T062143Z-2ffed182: *Clitocybe deceptiva* × 4 learners,
*Agaricus bitorquis* × 3, same image and settings) → full-view refresh
(release 20261013T155140Z-026d3a26) → its FINISHED release (continent
export, prior, clean cells) = the frozen release [PENDING: id]. Rebuild: 9,534 models planned, 9,042 fitted, 492
refused (too little evidence after site thinning or blocking), 0 failed;
797 old models retired; 118,657 training records; 4 spot reclaims, all
resumed. Cleaned pull occurrences-20261012T051017Z-x73b85b36 (sha256
7d3c5d70…) [CHECK: an earlier message gave -x2dd5cb30; confirm which]:
133,289 records, 16,303 taxa (the original 133,311 / 16,321 minus 22 rows and 18
names; the original kept untouched).

[PENDING: models, maps and taxa by grade × learner × site band, with the
strong share stated up front (C4); strong maps by guild and region; how many
taxa have a strong map; combined maps; share of reach inside AOA; and the
standard test on real models (E1c): the share of maps 19 scattered nulls call
good that are not shown to beat collecting.] → **Table 1**, **Figure 4** (example maps across grades); detail in S4.

### 3.4 How the maps did on records they never saw (E2, E3, E15)

[PENDING: rank of hindcast and prospective finds by grade; top half / top
tenth / Boyce / beats-effort with intervals; new sites vs near known sites;
inside vs outside AOA; combined vs single maps.] → **Figure 3**; every split in S6.

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

[PENDING: primary test (P2c vs no place term: overall McNemar; 300–1,500 km
band lower bound vs −2%); P2c vs the served kernel; trust weighting (P2c vs
P2c-u); depth-matched effects; P4 vs P6; projection validity H. Confirmed on
the fresh v1-test set when it exists. Reported whatever the result.]
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
  location is hidden, obscured or of unknown privacy at the source are
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
75 mislabelled ids removed, two fungi refitted, 18 non-fungal names dropped),
whose full-extent rasters have no border gaps [PENDING: ids, DOIs]. The live atlas keeps
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

[PENDING. Paragraph plan:]

1. The cost of an honest grade: about 7% of modelled taxa have a strong
   map [provisional: 470 of ~6,811]. Under the old scattered-null test the
   October 7 release had 1,835 taxa with a passing map, but data, naming
   rules and design all changed between the two releases; the like-for-like
   figure is E1c (the standard test rerun on the frozen release's own
   models), which is the number to quote.
   What a grade means and does not: strong = beats its own collecting pattern
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
   Twenty-two records in the frozen pull (of about 133,000) were later
   found to be erroneous: Mushroom Observer specimens linked on mycomap.org
   to unrelated iNaturalist observations, which gave them the wrong taxon
   and place. Rather than pull the database again, which would have moved
   the validation cutoff that the hindcast and Vision's held-out test depend
   on, we removed them from the frozen pull by an explicit, versioned
   exclusion list. We refitted the two fungal taxa whose record sets changed
   (*Clitocybe deceptiva* and *Agaricus bitorquis*, one record each), fully
   graded with the same settings, in a release that supersedes the main one.
   The other 18 affected names were non-fungal, with one or two records
   each, too few for any model; they no longer appear in the published
   taxa, cells or counts. Models of unaffected taxa were not refitted.
   Because survey sites, effort and background are built from the whole
   pull, their inputs still reflect these 22 records, less than 0.02% of all
   records. They formed 16 survey sites of their own and fell in 3 others
   (19 of 8,803 sites); they made up a median 0.13% (at most 0.45%) of the
   non-detection sites behind any full model's background, and a median
   0.11% for small-site models, with a tail of sparsely surveyed southern
   taxa up to 5.2% (*Oudemansiella* sp. 'TX01', 3 sites); 18 taxa exceed 1%
   and 71 exceed 0.5%, all small-site models. Each such site enters at the
   lowest effort, and none is a detection site of any modelled taxon [PENDING: exact
   figures on the frozen pull; these are from the 2026-10-06 pull, which
   holds the same 22 records]. A full refit on the cleaned pull would remove
   this; we did not refit, judging 22 records among more than 130,000 too few
   to matter, and report the shares instead. Separately, the frozen pull's
   naming also read three kinds of sequence it should have ignored: those
   the sequencing pipeline had set aside (a "trash" category), those flagged
   as contaminants (reads of a different organism than the specimen, which
   mycomap.org's own validation already excludes), and those flagged as
   belonging to a different observation or specimen. About 527 records
   (≈ 0.37% of the ~141,800 with named sequences) were named only by such
   sequences, for example an iNaturalist record named *Bacillus mycoides*
   by three contaminant reads, and about 2,287 (≈ 1.6%) were left out because
   such a sequence disagreed with their others. This adds a few weakly
   supported records and removes some well-supported ones; we expect little
   effect on maps and grades [PENDING E16: the taxa whose record sets
   change]. Later releases exclude all three kinds (Atlas commits 31709fa,
   9379a64 and 06cf6ea).
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
| 2.2–2.5 Predictors, sites, models | one paragraph each: layers by group, target-group survey sites, the learners and nested spatial CV | S3: the 69 predictors, pruning and host allowance, layer sweeps, importance (E8); S4: model settings, tuning grids, small-site ensembles, thresholds |
| 2.6–2.7 Null test and calibration | in full: the shift null, the grade, the virtual-species design | S5: generator details, every cell, effort arms (E14), the earlier study (E1b) |
| 2.8 Applicability and maps | two sentences | S4 |
| 2.9–2.10 Independent tests and baselines | in full but brief: hindcast, tracker, scores, baselines | S6: every split; S7: baseline details |
| 2.11 Releases and reproducibility | three sentences | S10: release format, tolerances, rerun (E12), stability (E11), cost and time (E23) |
| 2.12 / 3.9 Q1 | one paragraph each | S9: the registered design, every arm, projection validity |
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
| E2 | **Pre-registered** (`docs/experiments/2026-10-13-prereg-e2-hindcast.md`). Hindcast: full graded job on records first validated ≤ 2026-08-17; score later finds by grade, new vs known places | C2 | **Approved 2026-10-13**: Vision's training run becomes this full graded job (nulls on, private never-promotable release); code ~1–1.5 days in the rebuild lane, after the full-view refresh | Cutoff-filtered pull; test set = first green > cutoff (optionally observed > cutoff); undated records dated or excluded, with a count | ~250–500 CPU-h ($10–25), runs after the cutover on Steve's go | P1 |
| E3 | Prospective tracker by grade | C2 | Built; ships at the rebuild cutover; backfill from 2026-10-03 | Daily scoring of new finds on the live release | ~0 compute; needs months of finds (3–6) | P1 (clock starts at cutover) |
| E9 | **Planned** (`docs/experiments/2026-10-13-plan-e9-record-names.md`); the refit runs as a private job (`plan-job --record-names`, on feat/hindcast ba03e73), the experiments lane builds only the comparison. Sequence names vs record names: refit affected taxa both ways | C3 | Counts yes (4,878 records with a different species or genus; ~1,435 taxa with ≥10 localities change) [pre-freeze]; refits no | Production (sequence names) is the frozen release; refit every taxon whose record set differs under record names (full graded fits, all learners); map Spearman and Schoener's D, grade changes, E2/E3 skill | est. 150–300 CPU-h ($8–15), 2–3 days | P1 |
| E6a | **Planned** (`docs/experiments/2026-10-13-plan-e6a-default-maxent.md`). Default-practice Maxent on the hindcast pull (maxnet default.features, regmult 1, 10,000 uniform background points over the accessible area, random 5-fold CV, 19 uniform nulls as commonly run) | C1, C2 | No | New study arm over every taxon with ≥20 sites; its own CV score and pass rate vs its score on E2/E3 finds | est. 230–300 CPU-h ($12–15), from the cost pilot (`2026-10-13-e6a-cost-pilot.md`) | P1 |
| E6b | **Pre-registered** (`docs/experiments/2026-10-13-prereg-e6b-distance-baseline.md`). Spatial-only baseline (distance to known sites), paired with each model on its own AOA cells. **Runs first after E2**, because its result shapes C2's wording | C2 | No (shift nulls are related but not a baseline) | Kernel/distance model on the hindcast's training sites; scored on the E2 finds with the E2 metrics | small compute, ~2 days code | P1 |
| E12 | **Planned** (`docs/experiments/2026-10-13-plan-e12-grade-stability.md`). Reproducibility and GRADE STABILITY: step 0, read-only scores of the 576 refreshed models vs release; then full graded refits of ~600–900 stratified models twice on one family (r7i) and once on another (r7a), measuring grade agreement (κ), setting flips, |Δ| AUC/Boyce/p/strength and map tolerance. First evidence: 3 of 576 strong Maxent models changed setting on refit, 2 with every candidate's CV score moving; mechanism unknown. Gate: per-model machine records (feat/result-machine); Zenodo DOIs for layers, models, code | C4 | Machinery yes (fingerprints, pinned image, content-addressed store, refit tolerance checks, shard records name instance/CPU/BLAS); demo no; layers deposit held | Fresh workers; stratified sample; both families | est. 30–60 CPU-h, a few dollars; ~2 days code | **P1, raised**: a grade that changes with the machine weakens C4 |
| E17 | ODMAP protocol (`docs/paper/appendix-s1-odmap.md`) | all | **Draft 2026-10-13**; final check against the frozen release | Writing from Methods + code | 1–2 days | P1 |
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
| E19 | Training-record table for the frozen release (source, source id, taxon, public sequence id, fingerprint, survey-site id blank where the source hides the location; no coordinates or cells) and its Zenodo record; built after the frozen release | P1 |
| E20 | Data-records table and usage notes (section 4) | P1 |
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

Set 2026-10-13 with the Atlas coordinator after Steve's revision. Every launch
gets Steve's direct go through the operations lane; every run gets a
`docs/experiments` entry, pre-registered where there is a hypothesis.

| # | Item | Gate | Target |
|---|---|---|---|
| 0 | Rebuild cutover; nightly tracking (E3) starts | Steve's go | October 2026 |
| 1 | Full-view refresh → **frozen release** (id, then Zenodo layers, models, training records) | rebuild-lane code; Steve's go | October 2026 |
| 2 | **E2 hindcast** (also Vision's training run; Q1's Atlas input) | code pushed early (feat/hindcast ba03e73: `plan-job --hindcast --validated-through=2026-08-17`), awaiting Steve's review; E2 scoring code (experiments lane); Steve's go | can launch soon after the cutover, well before ~25 October 2026 (Vision freezes its test set ~30 October) |
| 2b | **E12 first step**: read-only scores of all 576 refreshed models, and a same-machine double run of *Stropharia hardii* and *Gliophorus fumosus* | Steve's go | right after the hindcast. Same-machine differences = a bug: the queue stops until fixed. Machine dependence only = E12's full run moves before E1 |
| 3 | **E6b** distance-only baseline on the E2 finds | rebuild-lane code; E2 | early November 2026 |
| 4 | **Presubmission inquiry** to Ecological Monographs | first E2 numbers | November 2026 |
| 5 | **E1c** standard test on real models | rebuild-lane code; the frozen release | November 2026 |
| 6 | **E1** virtual-species calibration (pre-registered, amended) | breadth and strength knobs in `study-virtual`; Steve's go | November 2026 |
| 7 | **E9** sequence vs record names | the same private-job code (`--record-names`); comparison code (experiments lane); Steve's go | November 2026 |
| 8 | **E6a** default-practice Maxent | new study arm; Steve's go | November–December 2026 |
| 9 | **E12** reproducibility rerun; E16 descriptives; E17 ODMAP | the frozen release; per-model machine records (feat/result-machine c099bc7, awaiting Steve's review; best merged before the hindcast so every paper job records which processor fitted each model) | December 2026 |
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
3. **Frozen release:** the full-view refresh of the cleaned release
   (Steve's targeted fix, 2026-10-13: 75 mislabelled ids removed, 2 fungi
   refitted, 18 names dropped). The hindcast reads the cleaned pull. Waiting
   for both releases, then for ids and Zenodo DOIs.
4. **Crediting contributors:** the full plan in section 6 adopted (Steve,
   2026-10-13). No individuals named for now (Steve, 2026-10-13); revisit
   before submission. Data item: observer name or username per training record for the
   Zenodo contributor table (asked of the coordinator).
5. **Zenodo layers archive:** Steve, 2026-10-13: "probably" discard the
   draft held since 2026-09-29 and re-archive the frozen release's layers,
   once that release exists (operations lane, Steve's go).
6. **Training-record table columns:** settled 2026-10-13 (section 4.1):
   source, source id, taxon, public sequence id, fingerprint, survey-site id
   (blank where the source hides the location). Built as E19 after the frozen
   release. The 0.1° cells question is settled too.

---

## Changelog

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
