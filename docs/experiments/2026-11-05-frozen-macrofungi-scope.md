# How much of the frozen release is not macrofungi

- **Question.** The paper's scope word is macrofungi, as in Vision's paper (Steve,
  2026-11-04), and the data does not change. How much of the frozen release is slime
  moulds, lichens or microfungi, by names, records, models and strong maps, measured
  the way Vision measured it?
- **Data.** `reproducibility: frozen`. Release 20261013T191324Z-fa1b4198, read from
  the public `/api/taxa` and `/api/models`. Names only.
- **Taxonomy used, and from when.** A family for each taxon's first word, asked on
  2026-11-04:
  - GBIF's backbone, with a Fungi hint;
  - for the 177 first words GBIF gave no family, iNaturalist's taxonomy, which is where
    Vision's release took its families (143 found, 34 not).
- **Lists used.** Vision's, unchanged:
  - slime moulds and lichens from its pinned definition
    `paper/scope/truth-taxa-out-of-scope-v1.json` (19 and 46 families, and four mixed
    families by genus), research repo;
  - microfungi from `paper/cvpr2027/scope_taxa.py` (23 families).
  - Also counted as slime moulds: any name GBIF or iNaturalist places in Mycetozoa,
    since GBIF files some, such as *Lycogala*, in a family (Tubiferaceae) Vision's list
    does not name.
  - Basidiolichens stay in scope, as in Vision's (*Lichenomphalia*, *Multiclavula* and
    similar genera).
- **Code.** In this directory: `2026-11-05-genus-families.py` then
  `2026-11-05-inat-families.py` make the two family lookups, each taking the directory
  of saved lists, and `python -I 2026-11-05-frozen-macrofungi-scope.py <dir> <vision
  definition>` reads them.

## Result (2026-11-05)

Of 16,252 taxa, 133,235 records, 9,041 models and 470 strong taxa:

| Group | Names | Share | Records | Share | Modelled taxa | Models (strong / weak / failed) | Strong taxa |
|---|---|---|---|---|---|---|---|
| Slime moulds | 44 | 0.27% | 64 | 0.05% | 3 | 3 (0 / 2 / 1) | 0 |
| Lichens | 75 | 0.46% | 102 | 0.08% | 2 | 2 (0 / 2 / 0) | 0 |
| Microfungi | 238 | 1.46% | 416 | 0.31% | 34 | 34 (1 / 17 / 16) | 1 |
| **Not macrofungi, together** | **357** | **2.20%** | **582** | **0.44%** | **39** | **39 (1 / 21 / 17)** | **1** |
| Parasitic Hypocreales (counted as macrofungi, as Vision) | 314 | 1.93% | 1,867 | 1.40% | 105 | 141 (2 / 98 / 41) | 2 |
| Basidiolichens (in scope, as Vision) | 7 | 0.04% | 95 | 0.07% | 4 | 8 (0 / 6 / 2) | 0 |
| No family from either source | 221 | 1.36% | 795 | 0.60% | 36 | 52 (3 / 35 / 14) | 1 |
| Everything else | 15,353 | 94.47% | 129,896 | 97.49% | 6,185 | 8,801 (570 / 6,507 / 1,723, 1 untested) | 466 |

**Beside Vision's.** Its v1 test, by the same lists: 0.40% of records not macrofungi,
0.12% slime moulds and lichens. Here: 0.44% and 0.12%. Vision's denominator is its own
US, Canada and Puerto Rico records, and it did not count names, so only the record
shares compare, and only roughly.

**The one strong map outside macrofungi:** *Apiosporina collinsii* (Venturiaceae;
family from iNaturalist). One ESM model, strong, 3 records. Vision's list counts
Venturiaceae as microfungi, so it is here. It is a plant-associated ascomycete, not a
slime mould or a non-fungus.

**The one strong taxon with no family:** *Protohydnum album*. Neither source gives it
a family. The other 220 names in that row are mostly codes named only to order or class
(*Helotiales* sp., *Agaricales* sp., *Polyporales* sp.).

**So the paper may say:** about 0.4% of records and 2.2% of names are not macrofungi by
Vision's lists, and 1 of 470 strong taxa. It should not say "no strong map outside
macrofungi", nor give 0.44% as exact.

**Limits.**
- **The lists are short and hand-made, and were written for Vision's records.** The
  microfungal list names 23 families. It misses microfungi in families it does not name:
  Everything else holds 47 Pleosporales names, 25 Diaporthales, 13 Botryosphaeriales,
  12 Eurotiales, 11 Mortierellales and 10 Capnodiales, and these are not counted as
  microfungi here. So 0.44% is a floor for what a broader definition would give, not a
  measured total.
- **The other way too:** a family on the list can hold visible fruiting bodies. Rhytismataceae
  is 50 of the 238 names, and Vision itself keeps microfungi in its scored set.
- **A family is read from a name's first word.** A taxon's own family can differ, a
  code's genus can be wrong, and a genus in two kingdoms takes the Fungi answer under
  the hint.
- **Two taxonomies.** GBIF and iNaturalist place some genera differently. Vision used
  iNaturalist's alone; this uses GBIF's first. Not reconciled.
- **Names, not sequences.** This takes each name as given.
- **Not taxa.** 'sample mixup' and similar names are in the counts, in the no-family row.

**Correction to `2026-11-04-frozen-kingdoms.md`.** That entry counted 42 slime-mould
names and 62 records, using GBIF by genus. With iNaturalist's taxonomy added, it is **44
names and 64 records**: also *Nannengaella globulifera* and *Tasmaniomyxa* sp. 'BC01',
1 record each, neither modelled. The models (3) and strong taxa (0) do not change.

## Cost

GBIF's and iNaturalist's public APIs from a local PC, paced. No EC2, USD 0.

## Decision

None from this entry. Steve, 2026-11-04: the paper's scope word is macrofungi, and the
data does not change. Slime moulds stay on the kingdom check's allow list.
