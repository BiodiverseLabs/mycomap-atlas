# Per-taxon fingerprints over listed records: sizing, and which points they hash

Cleared for the public branch by Steve, 2026-11-07, with the final S10 text. No taxon names, ids, places or coordinates.

- **Question.** Release fa1b4198 published, for every taxon, an unsalted SHA-256 fingerprint over
  its records' id, scientific name, latitude, longitude and date, and each model's seed (the first
  7 hex digits of it), in the API and the 19 October Zenodo version. How many taxa's fingerprints
  cover a record on the privacy list, how many cover only such records, and what point each listed
  record contributes to the hash, measured against what its source shows now. Serves S10 and 4.x.
- **Data.** `reproducibility: frozen`. Pull occurrences-20261012T051017Z-x73b85b36 (sha256
  7d3c5d70…), its privacy list of 2026-10-13 03:29 UTC (5,475 entries, 2,769 in the pull), and
  the release's list of modelled taxa (modelled-taxa-fa1b4198.txt, sha256 270ac0b1…). For the
  points: the dry-run pull 20261104T215205Z, which feeds no release, and .org's current records
  and source cache, read through atlas_ro. Nothing here changes the frozen release, its pull or E3.
- **Code.** `fingerprint_sizing.R` (sha256 4d0b123d…, run 2026-11-07 16:47 UTC) and
  `fingerprint_points.R` (sha256 653d578f…, run about 16:57 UTC), on the Atlas box, image
  ghcr.io/biodiverselabs/mycomap-atlas:309cd6c (digest sha256:45f39305…), `--entrypoint Rscript`,
  `--network host` for the SQL route, data directories mounted read-only. No guess is tried; both
  only count.
- **Output.** Counts only, in the store: `study/fingerprint-20261107/fingerprint-sizing.json`
  (sha256 76040f5f…) and `study/fingerprint-20261107/fingerprint-points.json` (sha256 d36a676c…).

## Result (2026-11-07)

**Taxa whose fingerprint covers a listed record.** Frozen pull: 133,235 records, 16,252 taxa.

| | Taxa |
|---|---|
| Cover at least one listed record | 1,765 |
| Every record listed | 323 (1 record: 291; 2: 29; 3-5: 3) |
| Listed and public records both | 1,442 (1 listed record: 938; 2: 274; 3-5: 204; 6-10: 25; over 10: 1) |
| Modelled, covering a listed record | 1,310 (seed published too) |

Of the 291 one-record taxa, 270 are MO records at a named place's centre, which MO shows; 17 are
MO and 4 iNaturalist records with no cached answer when the list was made. So up to 21 one-record
taxa may have a fingerprint over a point their source does not show; the run does not split them
further.

**What the listed records contribute, against the source now.**

| Listed records | Records | The hashed point is |
|---|---|---|
| MO, place | 1,936 | the named place's centre, which MO shows |
| MO, no answer then | 147 | the named place's centre |
| | 8 | the point the observer shows |
| | 434 | another point; the observer shows a different one |
| | 184 | another point; the observer shows none |
| | 24 | no answer now (15 at 5 decimals, 9 at 6) |
| iNaturalist, no answer then | 36 | no answer now |

2,091 of the 2,769 hash a point the source shows; 678 do not, or it is not known. The 2,302 MO
records not on the list all hash the point the observer shows.

**Which point is hashed, by source.** iNaturalist (126,506): .org's stored point, which is
iNaturalist's public location; records iNaturalist reported obscured, or placed no better than
1 km, in the cached answer at the time of the pull were left out of the pull. MO (5,035): the
observer's shown point (2,302), the named place's centre (1,936), or, with no cached answer,
.org's stored point (797). MyCoPortal (1,631, under two source spellings), sequence records (61)
and GenBank (2): .org's stored point, with no privacy list.

**Against the next pull (2026-11-04) and .org now.** iNaturalist records not on the list: 126,184
keep the same point, 41 have another, 245 are not in the next pull; the 36 on the list: 33 keep
the same point, 3 are not in the next pull. Of the 289 that moved or left (41 + 245 + 3), .org
still holds the frozen point for 245 (242 unlisted and the 3 listed that left); the 41 that moved
are not obscured now and .org holds another point; and 3 unlisted records that left are obscured
at iNaturalist now, with another point at .org (the 3 records obscured after the list). MO: of 820 that moved or left, .org still holds the frozen
point for 763, including 760 of the 766 listed records with no answer then. So for the MO records
the source now shows differently or not at all, the hashed point is .org's own stored point.

**Since.** The API and web app have carried no per-taxon fingerprint or per-model seed since
image c11c5fd (digest sha256:4d8598e7…) first answered, at 17:36 UTC on 7 November 2026. Ops
checked that day: no key named `fingerprint` or `seed` at any depth in /api/taxa, /api/taxa/<name>
(20 of 20), /model (10 of 10), /api/models or the ensemble answers (8 of 8), locally and at the
edge, while /api/status keeps the whole pull's fingerprint. The 19 October Zenodo version still
holds both until the next version.

**Limits.**
- Counts only. Whether anyone tested a guess against these fingerprints is not known.
- Testing a guess needs the record's id, name and date as well. For one-record taxa those are the
  taxon's only record; for the others every record of the taxon is needed exactly.
- The whole pull's fingerprint (in /api/status and the Zenodo README) hashes all 133,235 records at
  once and is not counted here.
- The list covers iNaturalist and MO only, and is dated 13 October.
