# Appendix S1, Section S2: records and data quality (draft)

*Draft of 2026-10-13. Query details for the mycomap.org pull are still to
write (from `R/occurrences.R` at the frozen release's commit).*

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
still include the 76 records (under 0.06% of all records).

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
