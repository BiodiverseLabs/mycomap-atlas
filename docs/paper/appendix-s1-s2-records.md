# Appendix S1, Section S2: records and data quality (draft)

*Draft of 2026-10-13. Query details for the mycomap.org pull are still to
write (from `R/occurrences.R` at the frozen release's commit).*

## S2.0 Eligibility, validation and naming

*Moved from the main text on 2026-10-13 (lean main text); edited only for the move.*

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


## S2.1 How the records were pulled

[PENDING: the eligibility rules as executed; the read-only route; the pull's
date, record count and fingerprint; the side queries (first validation date,
validation provenance, observer names) and how they join; what is private.]

## S2.2 Records removed before the frozen release: first cleaning (22 records)

Seventy-five mycomap.org rows had a wrong iNaturalist id. Sequencing sheets
had labelled Mushroom Observer specimens "iNat<n>", so the records pointed at
unrelated iNaturalist observations under the same number. The error was
first noticed by hand on 2026-09-30, on one sequence linked to an
iNaturalist dragonfly observation instead of the Mushroom Observer
specimen of the same number. The 75 rows were found on 2026-10-13 by an
audit of MycoMap Vision's training references, in which 41 records showed
animal photos, each with a Mushroom Observer twin in the same validation
project (confirmed by Steve, 2026-10-13). A separate
Vision export bug (Mushroom Observer and MyCoPortal ids fetched as
iNaturalist ids, found 2026-10-09) had a different cause and is not part of
this correction. Twenty-two of the 75 were in the October 2026 pull
(pull x2dd5cb30 after removal: 133,289 records, 16,303 taxa). All 75 ids are
excluded from the frozen release and from the hindcast's pull.

| Kind | Name (as labelled in the pull) | Records |
|---|---|---|
| Fungus (one false site) | *Clitocybe deceptiva* (the record was an iNaturalist observation of *Mephitis mephitis*) | 1 |
| Fungus (one false site) | *Agaricus bitorquis* | 1 |
| Bird | *Calypte anna* | 2 |
| Bird | *Anas platyrhynchos* | 2 |
| Bird | *Dryobates borealis* | 1 |
| Bird | *Columbina passerina* | 1 |
| Bird | *Cyanocitta stelleri* | 1 |
| Bird | *Melozone crissalis* | 1 |
| Bird | *Spizelloides arborea* | 1 |
| Mammal | *Canis latrans* | 1 |
| Mammal | *Procyon lotor* | 1 |
| Insect | *Argia moesta* | 1 |
| Insect | *Argia translata* | 1 |
| Insect | *Taeniaptera trivittata* | 1 |
| Fern | *Pteris vittata* | 1 |
| Fern | *Astrolepis integerrima* | 1 |
| Flowering plant | *Hesperidanthus linearifolius* | 1 |
| Flowering plant | *Karwinskia humboldtiana* | 1 |
| Flowering plant | *Catesbaea parviflora* | 1 |
| Flowering plant | *Pithecellobium keyense* | 1 |
| **Total** | 20 names | **22** |

The two fungi lost one site each (*C. deceptiva* 53 → 52, *A. bitorquis*
25 → 24) and were refitted (job 20261013T062143Z-2ffed182, release
20261013T063926Z-375d779c); the 18 non-fungal names had one or two sites,
too few for a model, and were dropped.

## S2.3 Second cleaning (54 records)

A rule from MycoMap Vision's data checks (`taxonomy.nonfungal`) plus a
by-taxon match found 54 more records under 51 non-fungal sequence names:
45 plants and mosses, 5 animals (3 bees, a dragonfly, a purple finch) and
one bacterium (*Bacillus mycoides*, 2 records). Most come from pooled
host-sample projects, where the record is the host plant or insect and the
fungal sequences were named after it on mycomap.com; two are fungal
records whose approved sequence was a contaminant (a *Phaeolus* record with
a finch sequence, an *Umbelopsis* record with *Bacillus*). Only one had a
model, *Elaeagnus umbellata* (autumn olive; 3 sites, small-site ensemble),
which was retired (job 20261013T133656Z-6a0564db, release
20261013T133737Z-79fe85f3); nothing was refitted. After removal the frozen
pull (x73b85b36, sha256 7d3c5d70…) holds 133,235 records and 16,252 taxa.
All 54 are iNaturalist records. By kingdom (full id-level list on Zenodo
with the training-record table, under the same privacy rule):

| Kingdom | Names | Records | Notes |
|---|---|---|---|
| Plants (incl. 3 mosses) | 45 | 47 | *Elaeagnus umbellata* 3 records, the only one with a model (retired); 44 others, 1 record each |
| Animals | 5 | 5 | 3 bees (*Dieunomia heteropoda*, *Megachile latimanus*, *Protandrena labrosa*), a dragonfly (*Orthemis ferruginea*), a purple finch (*Haemorhous purpureus*: a *Phaeolus* record named by a contaminant sequence) |
| Bacteria | 1 | 2 | *Bacillus mycoides*; one record is *Umbelopsis* sp. 'CA01' named by a contaminant sequence |
| **Total** | **51** | **54** | |

The 44 single-record plant names: *Achillea millefolium*, *Adiantum
pedatum*, *Ambrosia artemisiifolia*, *Aquilegia canadensis*, *Brasenia
schreberi*, *Cercis canadensis*, *Chimaphila maculata*, *Chrysogonum
virginianum*, *Dicranum montanum*, *Fagus grandifolia*, *Fragaria
virginiana*, *Geranium maculatum*, *Hamamelis virginiana*, *Hedera helix*,
*Hepatica americana*, *Hieracium longipilum*, *Ilex opaca*, *Impatiens
capensis*, *Krigia biflora*, *Laportea canadensis*, *Lespedeza procumbens*,
*Leucobryum glaucum*, *Ostrya virginiana*, *Persicaria longiseta*,
*Phalaris arundinacea*, *Podophyllum peltatum*, *Polytrichum formosum*,
*Potentilla indica*, *Potentilla simplex*, *Prunus serotina*, *Quercus
alba*, *Rosa multiflora*, *Rubus allegheniensis*, *Rubus phoenicolasius*,
*Rudbeckia hirta*, *Sanguinaria canadensis*, *Schizachyrium scoparium*,
*Symplocarpus foetidus*, *Thaspium trifoliatum*, *Trifolium repens*,
*Trillium grandiflorum*, *Verbesina walteri*, *Viola pubescens*, *Zizia
aurea*.

The hindcast is planned from the frozen release, whose base job (the
retirement job 20261013T133656Z-6a0564db) read this pull, x73b85b36.

## S2.4 What the removed records still touch

The exclusion list now holds 129 mycomap.org ids (the 75 of the first
cleaning, 22 of them in the pull, and the 54 of the second). It is
versioned: each pull's manifest records its SHA-256 and the number of rows
removed (Atlas commit 643b444), and it applies to every later pull. Only
the taxa the removed records named were refitted or retired; other models'
survey sites, effort and background were built from the whole pull and
still include the 76 records (under 0.06% of the pull's records). No
removed record is a presence of any published model: rebuilding all 6,369
modelled taxa's record sets from the cleaned pull for E3's kernels, every
one matched its model's recorded fingerprint, which is the exact record set
(E3 kernel run, 2026-10-21).

For the first 22, measured on the 2026-10-06 pull, which holds them at the
same places [PENDING: the same figures for all 76 on the frozen pull]: they
fall in 19 of 8,803 survey sites (0.22%); 16 of those consist only of these
records (13 of one record, 3 of two), and 3 are real sites with one such
record each (of 5, 17 and 110 records). Of the 1,291 taxa with full models
(20 or more detection sites), 1,288 have at least one of the 19 sites in
their background, as expected when a background is every survey site within
500 km: a median of 5 such sites per taxon (at most 18), a median 0.13% of
its background sites (at most 0.45%), each entering as a non-detection at
the lowest effort (one record). Of the 5,666 small-site taxa (3–19 sites),
5,150 have at least one in their background: a median of 3 (at most 15), a
median 0.11% of their background sites but up to 5.2% for the most affected
taxon (*Oudemansiella* sp. 'TX01', 3 sites), whose 500 km area is sparsely
surveyed; 18 taxa exceed 1% and 71 exceed 0.5%, all small-site models. None
is a detection site of any modelled taxon. These taxa were not refitted
(Steve, 2026-10-13: too few records to matter).

## S2.4b Finds posted to two platforms

Some finds were posted to both iNaturalist and Mushroom Observer. Starting
from MycoMap Vision's twin pairs (two records of the same label whose photos
differ by at most 3 bits of a perceptual hash), 2,627 same-label pairs, of
which 1,724 have both records eligible for Atlas and about 1,632 have both
named at species level by the pull's rule. Their two placed points are a
median 0.58 km apart (90th percentile 4.1 km): 1,486 pairs (91%) lie within
5 km, where site thinning counts the find once and only the effort
predictor (records per site) is slightly inflated; 146 lie further apart
and may give their taxon a second detection site, 10 of them over 50 km
apart (maximum 9,336 km). The 146 touch 132 distinct taxa, by the release's
own site counts 1 with 1–2 sites, 39 with 3–19, 53 with 20–49 and 39 with
50 or more. In 131 of the 146 the far copy is a Mushroom Observer record
with no cached Mushroom Observer answer, which Atlas places at
mycomap.org's point (usually a named location's centre) rather than
dropping it; so most are a coarse Mushroom Observer point, not a wrong
observation. Of 8,003 eligible Mushroom Observer records, 880 (11%) are
placed that way in the frozen pull. Their Mushroom Observer answers were
fetched on 2026-10-18, after the freeze. On the live database afterwards,
by the same method, about 1,588 pairs have both copies kept and named
(Atlas's Mushroom Observer rule now drops copies placed only by a location
box wider than 5 km); 1,568 (98.7%) lie within 5 km and 20 further apart (3
over 50 km), and the median separation where Mushroom Observer gives a GPS
point is 0.08 km. These later figures describe the next pull, not the
frozen release, which keeps the 146.
These figures are approximate: they apply the pull's rules to the live
database read-only on 2026-10-18, not to the frozen pull itself; the name
check is a simplified match (about ±1%); and they are a lower bound,
because twins can be detected only where both records have photos in
Vision's v1 dataset. Twins are not merged in the frozen release.

## S2.5 Set-aside, contaminant and misattributed sequences in the naming (frozen pull only)

Atlas names each record by the species name of its approved DNA sequences
on mycomap.org. In the frozen pull this naming also read three kinds of
sequence it should have ignored: those the sequencing pipeline had set aside
(a "trash" category the mirror still marks approved; 180,631 sequences on
2026-10-13); those flagged as contaminants, reads of a different organism
than the specimen (31,130), which mycomap.org's own validation already
excludes; and those flagged as belonging to a different observation or
specimen (13,526 approved). About 527 records were named only by such
sequences (for example an iNaturalist record named *Bacillus mycoides* by
three contaminant reads, one of those removed in the second cleaning), and
about 2,287 more had such a sequence with a
different name from their own sequences and were left out under the rule
that drops records whose sequences disagree: about 0.37% of the ~141,800
records with named sequences named on a weaker basis, and about 1.6% left
out that might otherwise have been modelled. Of the 527, 25 come from the
third kind alone and have no approved sequence left once it is excluded;
they are passed to data review. Figures read-only on production,
2026-10-13 (trash and contaminant counts from the data inputs lane; the
third kind from the rebuild lane, by Atlas's own naming rule). All three
kinds are excluded from the next pull on (Atlas commits 31709fa, 9379a64,
06cf6ea); the frozen release keeps them (Steve). [CHECK: these counts were
taken on the pull before the second cleaning; recount on x73b85b36.] [PENDING E16: a read-only script, run on
the Atlas server with the bogus-record counts, labels every record first
validated by 2026-10-12 with and without set-aside, contaminant-flagged
and misattributed sequences and reports
records joining, leaving and renamed; taxa whose record sets change; taxa
crossing 3 and 20 sites either way; and, for taxa with 20+ sites, the median
and maximum share of detection sites changed. Worded as "as of the frozen
pull's records, with the sequence mirror of <run date>".]
