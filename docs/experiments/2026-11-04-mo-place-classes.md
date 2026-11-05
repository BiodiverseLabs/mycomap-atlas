# MO records by how they are placed: the frozen pull against the dry pull

- **Question.** How many of the frozen pull's Mushroom Observer (MO) records
  sit at a named place's centre or had no cached MO answer, what the later
  cache check made of those, and whether the first pull after it treats any
  place its source hides as public. Serves S2.4b and Limits, and Steve's
  decision on the pull QA's `place_centre_share` limit (2026-11-04).
- **Data.** `reproducibility: frozen` for the frozen side: release
  20261013T191324Z-fa1b4198, pull occurrences-20261012T051017Z-x73b85b36
  (sha256 7d3c5d70…), and its privacy list of 2026-10-13. The other side is
  the dry-run pull 20261104T215205Z, which feeds no release, with its own
  list. Nothing here changes the frozen release, its pull or E3.
- **Code.** `2026-11-04-mo-place-classes.R` in this directory, as run: sha256
  3e9c29e7… on the Atlas box, image 91e7b5e, both data directories mounted
  read-only, `Rscript` with the paths in its header. It asks .org through
  atlas_ro.
- **Output.** Counts, shares, quantiles and distances only, in the store:
  `study/qa-place-20261104/qa-place.json` (sha256 acd19905…), and the frozen cells'
  split `study/qa-place-20261104/frozen-cells-split.json` (sha256 e7bc2ccb…).

## Result (2026-11-04)

**Classes of MO records in each pull.** "gps" is a point the observer shows;
"place" is a named place's centre, within 5 km of every point in the place;
"unknown" had no cached MO answer and was kept at .org's point (the rule then).

| Pull | MO records | gps | place | unknown | place, share of MO | place, share of those with an answer | place, share of the pull |
|---|---|---|---|---|---|---|---|
| Frozen x73b85b36 (133,235 records) | 5,035 | 2,302 | 1,936 | 797 | 38.45% | 45.68% | 1.45% |
| Dry 20261104T215205Z (136,423 records) | 5,157 | 3,042 | 2,115 | 0 | 41.01% | 41.01% | 1.55% |

**Each record, frozen pull to dry pull.**

| In the frozen pull | gps in dry | place in dry | Not in dry |
|---|---|---|---|
| gps | 2,268 | 0 | 34 |
| place | 0 | 1,916 | 20 |
| unknown | 560 | 117 | 120 |
| Not in frozen | 214 | 82 | – |

No record moved between gps and place. The rise in the share of MO, 2.56
points, splits as: unknown records becoming place +2.32, unknown records
leaving +1.00, other departures +0.05, new records −0.81.

**How far the formerly unknown records moved** (km between their point in the
two pulls):

| | Records | Median | Quartiles | 90th pct | Max | Over 5 km | Over 25 km |
|---|---|---|---|---|---|---|---|
| unknown → gps | 560 | 1.41 | 0.45 – 4.10 | 12.67 | 78.33 | 130 | 17 |
| unknown → place | 117 | 0.29 | 0 – 1.08 | 2.16 | 36.46 | 5 | 2 |

Records that kept their class (gps or place) did not move.

**What place records add in the frozen pull** (a site is a 5 km cell):
- Sites only they provide: 1,360 of 106,971 (1.27%), and 1.0% of modelled
  taxa's sites.
- 755 of 6,369 modelled taxa have such a site. Without them, 36 modelled taxa
  would fall below 3 sites, 13 below 20 and 2 below 50.
- 21 cells hold 880 of the 1,936 place records.
- These count dependence, not effect on a fit; that would need refits.

**The privacy lists.** 5,475 entries on 2026-10-13 (MO place 4,546, MO unknown
887, iNaturalist unknown 42) and 4,960 in the dry pull's (MO place 4,888, MO
unknown 27, iNaturalist unknown 45). The lists hold every eligible record, so
they are larger than the pulls' counts above.
- 4,873 entries stayed on the list, 602 left and 87 joined.
- Of the 602: 581 are in the dry pull, all formerly unknown MO records now with
  a cached answer showing the observer's GPS point; 20 are out of the dry pull
  and so unpublished; 1 is no longer on .org.

**The dry pull: 0 privacy violations.** Every record it treats as public was
checked: 3,042 MO records, all with a GPS point the observer shows, and 129,245
iNaturalist records, none uncached, obscured, with a blank obscured field or
placed coarser than 1 km.

**Limits.**
- It reads .org's caches of each source's answer, as the pull does, and asks
  neither source live. A place hidden after .org cached the answer would not
  show.
- It covers iNaturalist and MO only, the two sources with a privacy list.
  Other sources' places are not checked.

**Test.** The privacy section first ran before it had been tested (Deviations).
The same file, byte for byte, then passed 29 of 29 checks on local Postgres
against a fixture with a planted case of each violation and class.

**Not here.** The count of records public in the frozen release's cells and
private today is held for Steve's decision, with its split.

*Settled 2026-11-05 (Steve), on the split in the store and a read of iNaturalist's public
API: all 3 records obscured since the freeze were obscured by the observer's choice,
none is a protected taxon, and 1 is alone for its taxon in its cell. They leave from
the next models version under its filter, the current privacy list plus current
obscured status. No request to Zenodo; doi:10.5281/zenodo.23463939 stays as
published, and publishing that version needs his explicit OK.*

## Deviations

- 2026-11-04: the script Steve approved for the run was sha256 1e51efa6…. It was
  changed after that hash was sent, adding the privacy section, and ops copied
  the changed file, so 3e9c29e7… ran. Ops diffed the two and told Steve, who
  chose to keep the run. The planted-violation test above came after it.

## Cost

The Atlas box, about 7 minutes, in the existing server's cost: no EC2, USD 0
added, storage about 14 KB.

## Decision

Steve, 2026-11-04: raise `place_centre_share` from 10% to 50%, keep the
2-point rise rule and the definition (Atlas fix/qa-place-centre-ceiling).
