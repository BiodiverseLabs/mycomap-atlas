# What is in the frozen release, by kingdom

- **Question.** What the frozen release holds besides fungi: slime moulds, plants
  and anything else; whether any has a model or a strong map; and whether any is
  in E1c's sample or E2's scores. Serves Methods 2.1, S2 and Limits. Steve decided
  on 2026-11-04 that the Atlas covers fungi and slime moulds.
- **Data.** `reproducibility: frozen`. Release 20261013T191324Z-fa1b4198, read from
  the public `/api/taxa` and `/api/models` (the same lists as E16 Part 1); E1c's two
  results files (study-20261025T160517Z-0c069800); E2's score file with per-model
  rows (study-20261026T020304Z-017e88fa). GBIF's backbone and iNaturalist's taxon
  search were asked on 2026-11-04; those answers are of that day. Names only.
- **Code.** `2026-11-04-frozen-kingdoms.py` in this directory: each taxon's first
  word asked of GBIF's species/match, with a Fungi hint where the plain answer was
  not an exact fungal match (a hint settles names several kingdoms share and does
  not force an answer). `python -I 2026-11-04-frozen-kingdoms.py <dir with the
  saved lists>`.
- **The dry pull is not used for any count here.** Its QA report (20261104T215205Z)
  flagged 49 names; only the 43 of them in the frozen list are counted, and only as
  frozen names.

## Result (2026-11-04)

**The frozen list by the kingdom of each name's first word** (all 16,252 taxa,
133,235 records, 9,041 models):

| Kingdom of the first word | Names | Records | Modelled taxa | Models | Strong taxa |
|---|---|---|---|---|---|
| Fungi | 16,073 | 132,599 | 6,333 | 8,993 | 469 |
| Slime moulds (Mycetozoa) | 41 | 61 | 3 | 3 | 0 |
| Not placed by GBIF | 136 | 573 | 33 | 45 | 1 |
| Animalia | 2 | 2 | 0 | 0 | 0 |

- This reads the first word only, so a binomial in a genus shared with a fungus counts
  under Fungi. *Antennaria howellii*, a plant, is one (below).
- **Animalia:** *Cocles* sp. 'PNW01' and Subgenus Lentoramaria, 1 record each. The
  second is a *Ramaria* subgenus read as a genus called "Subgenus". The first is
  unverified.
- **Not placed:** 77 first words GBIF does not hold or cannot settle, mostly recent
  fungal genera (*Cyanula*, *Adelphella*-like names) and names that are not taxa:
  'sample mixup', 'NA sample mixup', 'sequence mixup', 'uncultured fungus',
  'Billie Jean'. These are counted, not checked one by one.

**1. Slime moulds in the frozen pull: 42 names, 62 records.** That is 41 names (61
records) in 17 genera GBIF places in Mycetozoa, plus *Reticularia* sp. 'IN01', a
slime-mould genus whose name GBIF also holds in other kingdoms. 30 of the 42 are
provisional names. The list comes from GBIF by genus, so it could still miss a slime
mould in a shared genus.

**Models: 3 of 9,041, none strong.**

| Taxon | Learner | Grade | Detection sites |
|---|---|---|---|
| *Fuligo septica* | ESM | failed | 5 |
| *Lycogala* sp. 'IN02' | ESM | weak | 8 |
| *Arcyria* sp. 'IN03' | ESM | weak | 3 |

**2. The 6 plants the dry pull flagged.**
- **In the frozen pull: 1 of the 6.** *Antennaria howellii*: 1 record, 1 site, no
  model. It is in the 133,235 records and the 16,252 taxa.
- **Not in the frozen pull:** *Ambrosia artemisiifolia*, *Chenopodium album*,
  *Juglans nigra*, *Prunus persica*, *Rubus occidentalis*. *A. artemisiifolia* has an
  earlier record already on the drop list (S2.3).
- **Beyond the 76 already removed:** yes, *A. howellii*'s record is not among them.
- **As a background site:** every record of a pull counts towards target-group
  background and effort, so this record does too, for models within reach of its
  site. How many models that is was not counted. It adds to at most one site.
- These are iNaturalist observations of plants, with the plant's name as the record's
  own name, and sequences from runs named for fungal pools of plants. Other plant
  names in the frozen list were not looked for beyond the check below.

**3. E1c and E2.** No row for any of the 42 slime-mould names, the 6 plants or
*Hydnum atlanticum*:
- E1c's sample: 0 of 1,083 rows. Its population could hold them: the 3 slime-mould
  models are among its 9,040, about 0.03%.
- E2's per-model scores: 0 of 4,591 rows (2,567 taxa).

**4. The 470 strong taxa.**

| | Strong taxa |
|---|---|
| GBIF places in Fungi, name asked alone | 433 |
| GBIF places in Fungi by genus (shared name, or a code) | 36 |
| In a slime-mould genus | 0 |
| In a non-fungal kingdom | 0 |
| Not placed by GBIF | 1 |

The one not placed is *Neoporphyrellus alboater*. GBIF has no such genus; iNaturalist
lists it under Fungi. So 469 of 470 are fungi by GBIF, the other by iNaturalist, and
none is a slime mould or a non-fungus.

**The 1,404 names the check left unknown.** These are the dry pull's, and the list is
on the box; this entry does not hold it. The 36 strong taxa above that needed their
genus are the ones a plain query cannot place, so they are the strong taxa in that
group, as replayed on 2026-11-04 and not intersected with the list itself. All 36
resolve to Fungi, 1 stays unplaced as above. For the group as a whole, a sample of 50
frozen provisional names gave 5 no-matches, the genera tried returning GBIF's
"multiple equal matches".

**How far this goes.**
- The kingdom check found 63 of 63 non-fungal names readable from the two cleanings
  (S2.2, S2.3).
- It is not proof that every name is a fungus: 9 of its 49 flags were wrong or
  uncertain, it reads names rather than sequences, and first words in shared genera
  can pass.
- What the paper can say from this: no strong map is of a slime mould or a known
  non-fungus; one strong taxon's kingdom rests on iNaturalist, not GBIF.

## Cost

GBIF and iNaturalist's public APIs from a local PC, paced. No EC2, USD 0.

## Decision

Steve, 2026-11-04: the Atlas covers fungi and slime moulds, stated on the site and in
the paper. The frozen release does not change.
