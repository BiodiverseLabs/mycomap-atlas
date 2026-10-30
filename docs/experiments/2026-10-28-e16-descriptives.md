# E16: the frozen release's descriptive numbers

- **Status.** Registered 2026-10-28, before any of the numbers below is
  read. Descriptive: no hypothesis, no compute beyond counting, no launch.
  It serves paper sections 3.1, S2.4, S2.5 and 4.1, and the coverage half
  of C3, which narrows to coverage after E9 (plan-e9, Result, 784700c).
- **Reproducibility.** frozen: release 20261013T191324Z-fa1b4198 and its
  pull occurrences-20261012T051017Z-x73b85b36 (sha256 7d3c5d70…). Nothing
  here changes either, or anything E3 reads.
- **Output.** Aggregates only: counts, shares, quantiles. No record, place,
  coordinate or record id. Records whose place is hidden, obscured or
  unknown at source count only in totals.

## Part 1: from the release (read from the live API, which serves fa1b4198)

The live site's `/api/status` names release 20261013T191324Z-fa1b4198
(checked 2026-10-28). `/api/taxa` gives every taxon with its localities;
`/api/models` gives every model with its grade and detection sites. Both
are public. If either ever differs from the Zenodo models record
(doi:10.5281/zenodo.23463939), the Zenodo copy wins.

- **Provisional name.** A name `atlas_is_provisional_name` (R/bestmap.R)
  calls provisional, as the website does: a DNA lineage with a code and no
  formal epithet (quotes, "sp.", or a code such as IN10). Every other name
  counts as formal.
- **Modelled taxon.** A taxon with at least one model in the release that
  was not refused (expected 6,369). **Strong taxon.** A taxon with at least
  one strong model (expected 470).
- **Site band.**
  - For modelled and strong taxa, the band of the taxon's largest model's
    detection sites: 3–4, 5–19, 20–49, 50–99, 100+.
  - For all taxa, the band of the taxon's localities, with 1–2 added.
- **Counts.** The count and share of provisional names: in all 16,252 taxa,
  in the modelled taxa, and in the strong taxa, each overall and by band.

## Part 2: from the frozen pull (read-only, on the Atlas box, through ops)

An R script run read-only on the box over x73b85b36 and its privacy list,
writing aggregates to a JSON file that ops copies to atlas-handoff.

1. **Records and taxa by source.**
2. **Sites per taxon.** Its distribution (quantiles), and the taxa at or
   above 3, 20 and 50 sites. A site is a distinct 1 km cell of a taxon's
   records, as the release counts localities.
3. **Records by state or province.** Count and share, from each record's
   country and state fields as pulled. Records whose place is hidden,
   obscured or unknown count under their state as .org holds it, since a
   state is no finer than the source shows.
4. **Validation lag.** For records with both dates: days from observed_on
   to first_green_on. Median and quartiles, overall and by source.
5. **The naming recount** (S2.5, "about 527 / 2,287"). Against .org's
   sequences as they are today, read through the box's read-only route:
   - the pull's records whose every approved, named sequence is now trash
     (category 169), contaminant or wrong;
   - the 10/12 eligible records that the trash rule left out (the label
     audit beside the pull).
   Counts only, by source.
6. **The 76 drop-list rows' exposure** (S2.4). For the pull, the number of
   modelled taxa with at least one of the 76 rows within 500 km of one of
   their own records: their background reach, where a row could change a
   background sample. Also the taxa that had one as a presence, expected 0.
7. **Unknown privacy** (4.1, "about 800"). Counts of the pull's privacy
   list by kind (unknown, place, hidden), and those records' share of the
   pull.

## Deviations

- **2026-10-28, before Part 2 runs: half of item 5 cannot be recounted.**
  - The "2,287 left out" came from the label audit of the first pull made
    under the trash rule. No such audit exists. The only one on the box,
    occurrences/labels-latest.json, is from the 10/12 pull, before the rule
    (the operations lane searched the box and the store). No nightly pull
    has run since, and the cutover rebuilt from the 10/12 pull plus the
    drop list.
  - So item 5 reports only the first half: the pull's still-green records
    with no clean, named sequence today. The 2,287 stays a figure from the
    session record, marked as not recounted.
- The privacy list read for item 7 is the pull's own: modified 2026-10-13
  03:29:36 UTC, 19,700 bytes.
- **2026-10-29, Part 2's first run (implementation only): the naming query
  hit atlas_ro's 60 s limit.** Item 5's query joined sequences on a CASE of
  o.source, which no index serves, and the run stopped at 05:04 UTC with
  nothing written.
  - It was rewritten as one equality join per source, with the same rule
    and the same answer. On prod's read-only route it returned the same
    records as the old query on three windows covering all six sources.
  - It now asks in windows of 5,000 records, each taking 2 to 4 s.
  - The limit and the connection cap were not changed. Nothing else in the
    script changed, and the rerun succeeded on 2026-10-30.

## Results

### Part 1 (2026-10-28)

Read from the public API (`/api/taxa` and `/api/models`), which serves
fa1b4198. The counts agree with the release: 16,252 taxa, 9,041 models,
6,369 modelled taxa and 470 strong taxa.

**Provisional names** (count / share of the taxa in the row):

| Taxa | All | 1–2 sites | 3–4 | 5–19 | 20–49 | 50–99 | 100+ |
|---|---|---|---|---|---|---|---|
| All 16,252 (by localities) | 9,785 / 60.2% | 6,229 / 66.8% (9,327) | 1,286 / 61.8% (2,081) | 1,776 / 52.1% (3,412) | 402 / 38.2% (1,053) | 79 / 25.9% (305) | 13 / 17.6% (74) |
| Modelled 6,369 (by detection sites) | 3,193 / 50.1% | – | 1,003 / 60.6% (1,655) | 1,739 / 51.5% (3,374) | 375 / 37.1% (1,012) | 65 / 23.6% (276) | 11 / 21.2% (52) |
| Strong 470 (by detection sites) | 213 / 45.3% | – | 19 / 55.9% (34) | 124 / 50.0% (248) | 61 / 36.7% (166) | 9 / 40.9% (22) | none strong |

The numbers in brackets are each band's taxa. Half of the modelled taxa,
and 45% of the strong ones, carry a provisional name. The share falls with
sites: from about 61% at 3–4 sites to about 21–24% at 50 and up.

### Part 2 (2026-10-30)

The run:
- The script e16_part2.R (sha256 93223c26…62cdec) was run read-only on the
  Atlas box by the operations lane, with Steve's confirmation. Image bf236cf,
  data mounted read-only, 03:59 to 04:06 UTC.
- The script's first run, on 2026-10-29, stopped at atlas_ro's 60 s
  statement limit (Deviations, 2026-10-29).
- Its output, e16-part2.json (sha256 1693ee0e…), holds aggregates only.

The frozen pull holds 133,235 records and 16,252 taxa, which agrees with the
release.

1. **Records and taxa by source.**

   | Source | Records | Share | Taxa |
   |---|---|---|---|
   | iNaturalist | 126,506 | 94.9% | 15,034 |
   | MO Observations | 5,035 | 3.8% | 2,737 |
   | MyCoPortal (both spellings) | 1,631 | 1.2% | 927 + 249 |
   | Sequences | 61 | <0.1% | 56 |
   | GenBank Accessions | 2 | <0.1% | 2 |

   MycoPortal (1,344 records) and MyCoPortal (287) are one portal under two
   .org source spellings, by import date. No record number appears under
   both (plan-e9, Result). Their taxa are counted per spelling, so a taxon
   under both is counted twice.
2. **Sites per taxon** (distinct 1 km cells; 16,248 taxa with a placed
   record):
   - Median 2; quartiles 1 and 6; 10th to 90th percentile 1 to 16; maximum
     325.
   - 6,810 taxa have at least 3 sites, 1,341 at least 20 and 328 at least
     50.
   - The release modelled 6,369 taxa. It counts sites as detection sites,
     after its own filters and refusals, so the two counts differ; the
     difference is not broken down here.
3. **Records by state or province** (105 country / state values as pulled):
   - **Largest:** California 19,484 (14.6%), Indiana 17,016 (12.8%),
     Michigan 15,786 (11.8%) and British Columbia 12,988 (9.7%). These four
     hold 49.0%.
   - **Next:** Washington 6.4%, Pennsylvania 5.2%, New Brunswick 3.4%,
     Missouri 3.1%, New York 3.0%, Ohio 3.0%, Virginia 2.1%, Florida 2.0%,
     Oregon 1.8%, Quebec 1.4% and Puerto Rico 1.2%.
   - **Small values:** 35 values hold fewer than 10 records each. Some are
     the source's own variants rather than states: Puerto Rico
     municipalities given as states, a country written "Pu", and a
     mis-encoded "Río Grande".
   - For publication, states under 10 records are grouped as "other" and
     variants are left as pulled. No single small value is reported.
4. **Validation lag** (days from observed_on to first_green_on; all 133,235
   records have both dates):

   | Source | Median | Quartiles | 10th–90th pct |
   |---|---|---|---|
   | iNaturalist | 243 | 146 – 470 | 83 – 933 |
   | MO Observations | 920 | 375 – 1,364 | 228 – 2,797 |

   - Two MO records have a negative lag, the earliest −360 days.
   - The other sources' observed_on is not a field date the lag can use.
     - MycoPortal and MyCoPortal are herbarium specimens: their medians on
       .org are 1956 and 1962, the oldest 1875. Their "lag" is the
       specimen's age when it was first validated (medians 24,877 and 5,999
       days).
     - Every Sequences record on .org has observed_on 1970-01-01, a
       placeholder (prod, read-only, 2026-10-30).
     - GenBank has 2 records.
   - So the lag is reported for iNaturalist and MO only. The all-source
     median (254 days) is not used.
5. **The naming recount** (half of the item; Deviations, 2026-10-28).
   - Every record of the pull is still green on .org today: 133,235, none
     no longer green.
   - **268** of them have no approved, clean, named sequence today: 164
     iNaturalist, 42 MO, 37 MycoPortal, 7 MyCoPortal and 18 Sequences.
     Every approved named sequence of these records is now trash, a
     contaminant or wrong.
   - The session record's "about 527" was counted at the trash rule
     (2026-10-13). This recount is against .org's sequences on 2026-10-30,
     which have changed since, so the two are not of the same moment. The
     difference is not reconciled.
   - The "2,287 left out" remains not recounted.
6. **The 76 drop-list rows.**
   - 30 of them can be placed. The others have no place Atlas uses.
   - 6,041 of the 6,369 modelled taxa (94.9%) have one of those 30 within
     500 km of their own records, so a drop-list row was within background
     reach of nearly every model.
   - 2 dropped rows carry the name of a modelled taxon, one each for 2
     taxa. Neither was a presence in the release, as expected: the release
     was fitted on x73b85b36, which excludes them.
7. **Privacy list** (dated 2026-10-13, 5,475 entries).
   - 2,769 of its records are in the pull (2.1% of it):
     - **place:** 1,936 MO records with no GPS point their observer shows,
       placed at their named place's centre;
     - **unknown:** 833 records whose source answer .org has not cached
       (797 MO, 36 iNaturalist).
   - The "about 800" unknown in 4.1 is 833.
