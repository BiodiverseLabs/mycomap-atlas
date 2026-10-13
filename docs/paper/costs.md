# Cost and time ledger

What each part of Atlas cost to compute and store, for the paper's section
4.4 and Table 5 (Steve, 2026-10-13: "people will find it interesting"). One
row per job or study. Every number names its source. Development runs before
the frozen release are kept, marked as such, because the paper can report
what building the method cost as well as what one rebuild costs.

## What to record for every run

| Field | Meaning | Source |
|---|---|---|
| Element | What the run is for (rebuild, refresh, hindcast E2, E1, …) | registry entry |
| Run id | Job id or study stamp | store / registry |
| Where | EC2 spot, the Lightsail box, or a local PC | job record |
| Models / fits | Models fitted (and null fits, where counted apart) | job record |
| Fit CPU-hours | Sum of per-model seconds ÷ 3600 (`atlas job-timing`) | shard records |
| Instance-hours billed | Launch to termination per worker, including spot reclaims and idle time | EC2 records (operations lane) |
| Instance types | e.g. m7i.8xlarge, c7i.8xlarge (32 vCPU) | shard records |
| Wall time | Plan to promotion | job record |
| Compute cost (USD) | Billed spot price × instance-hours; check against AWS Cost Explorer for the day | AWS (operations lane) |
| Storage added (GB) | New bytes in the content-addressed store for the release | release manifest |
| Storage cost (USD/month) | S3 Standard at the bucket's region price | AWS price list |
| Notes | Partial runs, retries, deadline hits | job record |

Standing costs, recorded monthly: the Lightsail server, the S3 bucket's total
size, data transfer out, and anything else on the Atlas account. Zenodo
archives cost nothing. Runs on a local PC are recorded with CPU-hours and
wall time and USD 0 of cloud cost (electricity not counted; say so).

## Ledger

Figures marked ≈ are estimates or come from progress notes, not from billing;
they are replaced by billed figures where AWS can still provide them.

| Date (UTC) | Element | Run id | Where | Models | Fit CPU-h | Wall | Compute USD | Storage | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-30 | First EC2 trial (development) | 20260930T063855Z-512266e7 | EC2 spot, 1 worker | 9 | ≈ 5 | 83 min | [PENDING billing] | — | first worker reclaimed after 11 min |
| 2026-10-01 | First full build (development; old design) | 20261001T233057Z-239fad9a | EC2 spot | 8,727 fits | [PENDING] | ≈ 4.8 h | [PENDING billing] | ≈ 2.4 GB (draft release, without full rasters) [CHECK] | 6 h deadline |
| 2026-10-06 | Virtual-species null study (development) | virtual-20261006T091510Z | local PC | 99 species × 3 designs | [PENDING from results file] | ≈ 2 days (shared PC) | 0 (local) | — | basis of E1b |
| 2026-10-12 | Rebuild pilot (development) | 20261012T135059Z-fd7c13c5 | EC2 spot, 4 × m7i.8xlarge | 281 planned, 211 timed | [PENDING job-timing] | 2 h (cap) | ≈ 6.5 | — | one shard stalled on one taxon (fixed before the full run) |
| 2026-10-13 | October rebuild, first launch | 20261013T001819Z-2cb67f32 | EC2 spot, ≤ 4 workers | 9,534 planned | [PENDING] | [PENDING] | [PENDING] (cap ≈ 32) | ≈ 16 GB per release with rasters [CHECK] | relaunched as below |
| 2026-10-13 | October rebuild (full job) → R_main 20261013T061352Z-78dd82de | 20261013T022520Z-2cb67f32 | EC2 spot, image 0a9dde4 | 9,534 planned; 9,042 fitted, 492 refused, 0 failed; 797 retired | [PENDING job-timing] | [PENDING] | [PENDING billing] | [PENDING] | 4 spot reclaims, all resumed; 118,657 training records |
| 2026-10-13 | Targeted refit (cleaned release; 22 records removed) | 20261013T062143Z-2ffed182 | EC2 spot, image 0a9dde4 | 7 (2 taxa) | [PENDING] | [PENDING] | [PENDING billing] | [PENDING] | |
| — | Full-view refresh → frozen release | [PENDING] (dry run on 20261013T063926Z-375d779c) | EC2 spot | 576 strong models (470 taxa) | ≈ 35 (estimate) | ≈ 0.4 h (estimate) | ≈ 1–2 (estimate) | [PENDING] | refits strong models only; default maps, grades and ranks unchanged |
| — | Hindcast (E2) | [PENDING] | EC2 spot | | | | est. 10–25 | | |
| 2026-10-13 | E1 cost pilot (development; `2026-10-13-e1-cost-pilot.md`) | — | local PC, 2 processes × 1 core | 4 virtual species, Maxent + RF + ESM, scatter and shift ×99 per learner | 0.56 | 29 min | 0 (local) | 0 | per null CV: Maxent ≈ 5.2 s, RF ≈ 2.2 s, ESM ≈ 4.4 s; no species at 200+ sites |
| 2026-10-13 | E6a cost pilot (development; `2026-10-13-e6a-cost-pilot.md`) | — | local PC, 1 core | 2 taxa, default maxnet, 5-fold CV + 3 nulls each | 0.25 | 16 min | 0 (local) | 0 | lqh at 31 sites ≈ 16 min per taxon with 19 nulls; lqph at 102 sites ≈ 28 min |
| — | E6b, E1c, E1, E9, E6a | [PENDING] | | | | | est. E1 27–46 (doubled sizes); E1c 5–10; E9 8–15; E6a 12–15 | | estimates from Appendix A and the pilots |

## Standing costs

| Item | Cost | Source |
|---|---|---|
| Lightsail server (2 GB plan, API, web, nightly orchestration) | [PENDING: plan price] | AWS Lightsail |
| S3 bucket (total stored, monthly) | [PENDING] | AWS billing |
| Data transfer out | [PENDING] | AWS billing |
| Monthly AWS budget alarm | USD 200 | the account's budget setting |
| Zenodo | 0 | — |

## For the paper

Section 4.4 reports: the cost and wall time of one full rebuild (compute and
storage); a typical nightly incremental run; the standing monthly cost; the
cost of each paper analysis; and CPU time per model by learner and by
number of sites (from job-timing), which is what lets other groups plan a
similar atlas.
