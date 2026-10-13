# Appendix S1, Section S2: records and data quality (draft)

*Draft of 2026-10-13. Query details for the mycomap.org pull are still to
write (from `R/occurrences.R` at the frozen release's commit).*

## S2.1 How the records were pulled

[PENDING: the eligibility rules as executed; the read-only route; the pull's
date, record count and fingerprint; the side queries (first validation date,
validation provenance, observer names) and how they join; what is private.]

## S2.2 Records removed before the frozen release

Seventy-five mycomap.org rows had a wrong iNaturalist id. Sequencing sheets
had labelled Mushroom Observer specimens "iNat<n>", so the records pointed at
unrelated iNaturalist observations under the same number. The error was
first noticed by hand on 2026-09-30, on one sequence linked to an
iNaturalist dragonfly observation instead of the Mushroom Observer
specimen of the same number. The 75 rows were found on 2026-10-13 by an
audit of MycoMap Vision's training references, in which 41 records showed
animal photos, each with a Mushroom Observer twin in the same validation
project [CHECK: confirm with Steve or the Vision retrain lane]. A separate
Vision export bug (Mushroom Observer and MyCoPortal ids fetched as
iNaturalist ids, found 2026-10-09) had a different cause and is not part of
this correction. Twenty-two of the 75 were
in the October 2026 pull. All 75 ids are excluded from the frozen release
and from the hindcast's pull.

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
25 → 24) and were refitted; the 18 non-fungal names had one or two sites,
too few for a model, and were dropped. The other models' survey sites,
effort and background still include these 22 of about 133,000 records
(less than 0.02% of all records). Measured on the 2026-10-06 pull, which
holds the same 22 records at the same places (exact frozen-pull figures
pending): the 22 records fall in 19 of 8,803 survey sites (0.22%); 16 of
those consist only of these records (13 of one record, 3 of two), and 3 are
real sites with one such record each (of 5, 17 and 110 records). Of the
1,291 taxa with full models (20 or more detection sites), 1,288 have at
least one of the 19 sites in their background, as expected when a
background is every survey site within 500 km: a median of 5 such sites per
taxon (at most 18), a median 0.13% of its background sites (at most 0.45%),
each entering as a non-detection at the lowest effort (one record). Of the
5,666 small-site taxa (3–19 sites, ensembles of small models), 5,150 have at
least one in their background: a median of 3 such sites (at most 15), a
median 0.11% of their background sites but up to 5.2% for the most affected
taxon (*Oudemansiella* sp. 'TX01', 3 sites), whose 500 km area is sparsely
surveyed; 18 taxa exceed 1% and 71 exceed 0.5%, all small-site models.
These taxa were not refitted (Steve, 2026-10-13). None is
a detection site of any modelled taxon: the two fungi involved are refitted
on the cleaned pull, and the 18 other names are not modelled. The exclusion list is versioned: each
pull's manifest records its SHA-256 and the number of rows removed (Atlas
commit 643b444), and it applies to every later pull.

## S2.3 Set-aside and contaminant sequences in the naming (frozen pull only)

Atlas names each record by the species name of its approved DNA sequences
on mycomap.org. In the frozen pull this naming also read two kinds of
sequence it should have ignored: those the sequencing pipeline had set aside
(a "trash" category the mirror still marks approved; 180,631 sequences on
2026-10-13) and those flagged as contaminants, reads of a different organism
than the specimen (31,130), which mycomap.org's own validation already
excludes. About 502 records were named only by such sequences (for example
an iNaturalist record named *Bacillus mycoides* by three contaminant reads),
and about 2,281 more had such a sequence with a different name from their
own sequences and were left out under the rule that drops records whose
sequences disagree: about 0.35% of the ~141,800 records with named
sequences named on a weaker basis, and about 1.6% left out that might
otherwise have been modelled. Figures from the data inputs lane, read-only
on production, 2026-10-13. Both kinds are excluded from the next pull on
(Atlas commits 31709fa and 9379a64); the frozen release keeps them
(Steve). [PENDING E16: a read-only script, run on
the Atlas server with the bogus-record counts, labels every record first
validated by 2026-10-12 with and without set-aside and contaminant-flagged
sequences and reports
records joining, leaving and renamed; taxa whose record sets change; taxa
crossing 3 and 20 sites either way; and, for taxa with 20+ sites, the median
and maximum share of detection sites changed. Worded as "as of the frozen
pull's records, with the sequence mirror of <run date>".]
