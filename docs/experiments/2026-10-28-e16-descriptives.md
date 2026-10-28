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

## Results

None yet.
