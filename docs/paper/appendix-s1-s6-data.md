# Appendix S1, Section S6: data query details and data corrections (draft)

*Draft of 2026-10-13. Query details for the mycomap.org pull are still to
write (from `R/occurrences.R` at the frozen release's commit).*

## S6.1 How the records were pulled

[PENDING: the eligibility rules as executed; the read-only route; the pull's
date, record count and fingerprint; the side queries (first validation date,
validation provenance, observer names) and how they join; what is private.]

## S6.2 Records removed before the frozen release

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
iNaturalist ids, found 2026-10-09) had a different cause and did not affect
Atlas. Twenty-two were
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
[PENDING: the rebuild lane's wording].
