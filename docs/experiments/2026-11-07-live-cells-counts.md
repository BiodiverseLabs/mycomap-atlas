# Live collection cells against the published file, 13 October to 6 November 2026

Cleared for the public branch by Steve, 2026-11-07, with the final S10 text. No taxon names, ids, places or coordinates.

- **Question.** What the API's collection-cell routes served that release fa1b4198's published
  cells file leaves out under its privacy list, counted by records, cells and taxa, and what the
  box's copy from before the cutover held. Serves S10 and 4.3: the 323 and the 1,765.
- **Data.** `reproducibility: frozen`. Pull occurrences-20261012T051017Z-x73b85b36 (sha256
  7d3c5d70…), its privacy list privacy-latest.tsv.gz of 2026-10-13 03:29:36 UTC (sha256
  e918824d…, 5,475 entries, 2,769 in the pull), and the release's published cells.tsv.gz (sha256
  e1d61995…, the file in the Zenodo manifest). Before the cutover: the box's copy
  /srv/atlas/data-prev, holding pull occurrences-20261007T070605Z (sha256 97622786…) and release
  20261007T085351Z-89ef2317. Nothing here changes the frozen release, its pull or E3.
- **Code.** `live_cells_counts.R`, as run: sha256 4b7fdbe2… on the Atlas box, 2026-11-07 about
  16:56 UTC, image ghcr.io/biodiverselabs/mycomap-atlas:309cd6c (digest sha256:45f39305…, the
  one the API ran), `--entrypoint Rscript`, `--network none`, data directories
  mounted read-only. It asks nothing over the network. It computes the served cells the way the
  routes did before the fix (from the pull, with no list).
- **Output.** Counts, file names, dates and hashes only, in the store:
  `study/live-cells-20261106/live-cells-counts.json` (sha256 0231a225…).

## Result (2026-11-07)

**Served against published.** A cell is one taxon in one 0.1 degree cell.

| | Records | Taxa | Cells |
|---|---|---|---|
| Served by the routes (pull, no list) | 133,235 | 16,252 | 103,095 |
| Published file (pull less the list) | 130,466 | 15,929 | 101,330 |
| Difference | 2,769 (2.08% of the pull) | 323 | 1,765 |

The pull less the list reproduces the published file exactly. Every record in the difference is
on the list: 1,936 MO records at a named place's centre, 797 MO records with no cached answer
when the list was made, 36 iNaturalist records with no cached answer.

**Cells.** 1,765 served cells are not in the file at all (1,868 records; 1,678 of those cells
hold one record). 790 cells are in the file with a lower count (901 records). No served cell is
lower than the file, and no cell in the file is unserved; 100,540 are the same.

**Taxa.** 1,765 taxa are served differently from the file: 323 appear only in the served cells
(each has every record on the list), and 1,442 are in the file and differ (1,077 with an extra
cell, 365 with higher counts only). The count of taxa that differ and the count of extra cells
are separate quantities that happen to be equal (1,765); cite each by name.

**Period.** From the box's journal: the API was restarted on the cutover at 23:02:17 UTC on 13
October and answering from 23:02:58; it was restarted on the fix at 00:06:06 UTC on 6 November
and answering from 00:06:57 (7:06 PM EST, 5 November). Cited, as in the paper, by the answering
times to the minute: from 23:03 UTC on 13 October to 00:07 UTC on 6 November (19:07 EST, 5
November); the gap is contained in that span. The data directory holds no pull newer
than x73b85b36 (file of 13 October 13:34 UTC), and `latest.json`, which names it, was last
modified 13 October 13:34:54 UTC, so the routes had no other pull to read in that span. The API ran
four images in that span, each named in the journal and the registry (read-only, 2026-11-07): the
cutover's bc2a7a5 (23:02 UTC, 13 October), then 5753802 (18 October, 19:39 UTC), 7915ff8 (21
October, 05:18 UTC) and 91e7b5e (1 November, 22:05 UTC). In each, `cached_cells_source` in
inst/plumber/atlas.R reads the pull whenever the box holds one, and the routes call
`atlas_public_cells_table` with no list. Ops confirmed the gap at 00:23 UTC on 5 November;
the fix was serving from 00:07 UTC on 6 November and was verified on 6 November: every differing
taxon equals the file, and the 323 serve no cells.

**Before the cutover.** The box's pre-cutover copy of its data directory (pull of 7 October,
131,041 records and 17,538 taxa; release 89ef2317, never deposited on Zenodo) has no list of its own: none existed before 13 October 03:29 UTC. Its
published cells file equals that pull with no list. It holds 4,493 records that are on the list of
13 October: 4,385 MO place-centre records, 99 MO records with no cached answer and 9 iNaturalist
records with no cached answer. So 13 October is when the site and the published file began to
differ, not when these records first appeared: before it, they were in both.

**Limits.**
- Counts only; no request logs were read. nginx access logs on the box start 23 October, and
  nothing here says whether anyone read these routes.
- When the routes first became publicly reachable is not measured. The journal starts 29
  September, the API's first start that day.
- Releases between 29 September and 6 October are not on the box's copy and are not counted.
- The list covers iNaturalist and MO only; the 1,694 records from other sources in the frozen
  pull have no list.
- The list is dated 13 October. 3 iNaturalist records obscured since are in both the served and
  the published cells.
