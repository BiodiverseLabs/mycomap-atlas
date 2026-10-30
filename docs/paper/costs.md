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
they are replaced by billed figures where AWS can still provide them. Rows
from 2026-10-19 on are computed by the operations lane (2026-10-21) as
instance-hours from the workers' shard records × the us-east-2 on-demand
Linux price (USD/h: r7i.large 0.1323, r7i.xlarge 0.2646, r7i.8xlarge
2.1168, r7a.large 0.15214, r7a.xlarge 0.30428, r7a.8xlarge 2.43424); for
spot runs that is an upper bound (≤). They leave out the Lightsail box,
the orchestrator, S3 and boot time before a worker writes its start.

| Date (UTC) | Element | Run id | Where | Models | Fit CPU-h | Wall | Compute USD | Storage | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-30 | First EC2 trial (development) | 20260930T063855Z-512266e7 | EC2 spot, 1 worker | 9 | ≈ 5 | 83 min | [PENDING billing] | — | first worker reclaimed after 11 min |
| 2026-10-01 | First full build (development; old design) | 20261001T233057Z-239fad9a | EC2 spot | 8,727 fits | [PENDING] | ≈ 4.8 h | [PENDING billing] | ≈ 2.4 GB (draft release, without full rasters) [CHECK] | 6 h deadline |
| 2026-10-06 | Virtual-species null study (development) | virtual-20261006T091510Z | local PC | 99 species × 3 designs | [PENDING from results file] | ≈ 2 days (shared PC) | 0 (local) | — | basis of E1b |
| 2026-10-12 | Rebuild pilot (development) | 20261012T135059Z-fd7c13c5 | EC2 spot, 4 × m7i.8xlarge | 281 planned, 211 timed | [PENDING job-timing] | 2 h (cap) | ≈ 6.5 | — | one shard stalled on one taxon (fixed before the full run) |
| 2026-10-13 | October rebuild, first launch | 20261013T001819Z-2cb67f32 | EC2 spot, ≤ 4 workers | 9,534 planned | [PENDING] | [PENDING] | [PENDING] (cap ≈ 32) | ≈ 16 GB per release with rasters [CHECK] | relaunched as below |
| 2026-10-13 | October rebuild (full job) → R_main 20261013T061352Z-78dd82de | 20261013T022520Z-2cb67f32 | EC2 spot, image 0a9dde4 | 9,534 planned; 9,042 fitted, 492 refused, 0 failed; 797 retired | [PENDING job-timing] | 4 shards, started 02:28–03:57, finished 05:43–06:09 UTC; 8.42 instance-h (shard records, no instance type) | [PENDING billing] | [PENDING] | 4 spot reclaims, all resumed; 118,657 training records |
| 2026-10-13 | Targeted refit (cleaned release; 22 records removed) | 20261013T062143Z-2ffed182 | EC2 spot, image 0a9dde4 | 7 (2 taxa) | [PENDING] | [PENDING] | [PENDING billing] | [PENDING] | |
| 2026-10-13 | Second cleaning: *Elaeagnus umbellata* retired | 20261013T133656Z-6a0564db | — | 1 retired | 0 | [PENDING] | ≈ 0 | — | no refits |
| 2026-10-13 | Full-view refresh | full-20261013T140649Z-5cf5b864 → 20261013T155140Z-026d3a26 | EC2 spot (r7i ×3, r7a ×1 by last attempt), image 8b8566f | 576 strong models refitted; 573 full views replaced, 3 kept | ≈ 35 (estimate) | [PENDING] | [PENDING billing] | [PENDING] | |
| 2026-10-13 | Finishing (v5) → frozen release | → 20261013T191324Z-fa1b4198 | EC2 spot | — | [PENDING] | ends 19:13 UTC | [PENDING billing] | 38,216 files, 14.45 GB (sum of the manifest's file sizes) | continent export, prior, privacy-filtered cells |
| 2026-10-18 | Hindcast (E2; also Vision's training run) | priv-20261018T171648Z-9e3ab153 | EC2 spot, on-demand finish | 9,115 planned; 8,606 fitted, 509 refused, 0 failed | 289 | ends 22:23 UTC | ≈ 5.71 (the job's own estimate in summary.json; billing to confirm) | [PENDING] | spot reclaims on all 4 shards at 17:57 (shard 2 twice more); 110,615 trained ids |
| 2026-10-13 | E1 cost pilot (development; `2026-10-13-e1-cost-pilot.md`) | — | local PC, 2 processes × 1 core | 4 virtual species, Maxent + RF + ESM, scatter and shift ×99 per learner | 0.56 | 29 min | 0 (local) | 0 | per null CV: Maxent ≈ 5.2 s, RF ≈ 2.2 s, ESM ≈ 4.4 s; no species at 200+ sites |
| 2026-10-13 | E6a cost pilot (development; `2026-10-13-e6a-cost-pilot.md`) | — | local PC, 1 core | 2 taxa, default maxnet, 5-fold CV + 3 nulls each | 0.25 | 16 min | 0 (local) | 0 | lqh at 31 sites ≈ 16 min per taxon with 19 nulls; lqph at 102 sites ≈ 28 min |
| 2026-10-19 | Sparassis leave-out refit (E2 deviation) | priv-20261019T042158Z-09936f85 | EC2 | 1 | [PENDING] | [PENDING] | [PENDING billing] (no cost in summary.json) | — | |
| 2026-10-19 | E2 scoring | study-20261019T181851Z-35fc3d63 | 1 × r7i.xlarge, spot | — | — | 18:20–19:08 UTC; 0.80 instance-h | ≤ 0.21 | — | |
| 2026-10-19 | E12 gate, r7i | study-20261019T180106Z-5b4bbf44 | 1 × r7i.large, spot | 3 × 2 runs | — | 18:03–18:09; 0.11 instance-h | ≤ 0.01 | — | |
| 2026-10-19 | E12 gate, r7a | study-20261019T181116Z-179c6d90 | 1 × r7a.large, spot | 3 × 2 runs | — | 18:13–18:19; 0.11 instance-h | ≤ 0.02 | — | |
| 2026-10-20 | E6b kernels | study-20261020T053446Z-1552e567 | 3 × r7i.8xlarge, spot | 6,059 kernels | — | 05:36–08:19 (shards 1.54, 1.64, 1.57 h); 4.75 instance-h | ≤ 10.06 | — | |
| 2026-10-20 | E6b kernels, r7a patch | study-20261020T221806Z-9620406f | 1 × r7a.xlarge, spot | 35 kernels | — | 22:19–22:22; 0.04 instance-h | ≤ 0.01 | — | |
| 2026-10-20 | E6b scoring | study-20261020T232528Z-05216058 | 1 × r7i.xlarge, spot | — | — | 23:27–00:55; 1.48 instance-h | ≤ 0.39 | — | |
| 2026-10-20 | E12 arm a1 | study-20261020T182524Z-717cf60a | 2 × r7i.8xlarge, spot | 507 | — | 18:28–19:37; 2.08 instance-h | ≤ 4.39 | — | |
| 2026-10-20 | E12 arm a2, first run | study-20261020T212937Z-cfac20a6 | 3 × r7i.8xlarge, spot | 507 | — | 21:32–22:17; 2.10 instance-h | ≤ 4.45 | — | found the glmnet leak |
| 2026-10-21 | E12 arm a2, rerun | study-20261021T002552Z-cfac20a6 | 3 × r7i.8xlarge, spot | 507 | — | 00:28–01:16; 2.21 instance-h | ≤ 4.69 | — | |
| 2026-10-20 | E12 arm b, first launch (lost) | study-20261020T182526Z-95330a0a | r7a.8xlarge, spot | 0 | — | reclaimed 8 times in ~45 min; no shard record | unknown, small | — | |
| 2026-10-21 | E12 arm b | study-20261021T011833Z-c7b64a0a | 1 × r7a.8xlarge, on-demand | 507 | — | 01:20–02:53; 1.55 instance-h | ≈ 3.77 | — | |
| 2026-10-21 | E12 block-only step, r7i | study-20261021T054022Z-81a7fb86 | 1 × r7i.2xlarge, on-demand | 282 blocks, no fit | — | 0.13 instance-h | ≈ 0.07 | — | |
| 2026-10-21 | E12 block-only step, r7a | study-20261021T052557Z-bc3f9b50 | 1 × r7a.2xlarge, spot | 282 blocks, no fit | — | 0.13 instance-h | ≤ 0.08 | — | |
| 2026-10-21 | E3 kernels, main | study-20261021T052559Z-eff180db | 3 × r7i.8xlarge, spot | 5,679 scored, 690 mismatch, 0 refused or failed | — | 05:28–07:08 UTC; 5.0 instance-h | ≤ 10.6 | — | mismatches under review before any r7a patch |
| 2026-10-21 | E3 kernels, patch 1 spot attempt (no result) | study-20261021T142054Z-a972d74e | r7i.4xlarge × 4 attempts, spot | 0 kept | — | 14:27–17:10 UTC in 4 attempts; 0.68 instance-h (launch to reclaim, incl. boot) | ≤ 0.72 | — | reclaimed 4 times |
| 2026-10-21 | E3 kernels, patch 1 rerun | study-20261021T185333Z-a972d74e | 1 × r7i.4xlarge, on-demand | 681 scored, 9 mismatch | — | 18:55–19:10 UTC; 0.25 instance-h | ≈ 0.27 | — | rebuilt from R_main's pull |
| 2026-10-25 | E3 kernels, patch 2 | study-20261025T145556Z-26f877fe | 1 × r7a.xlarge, spot | 9 scored | — | 14:57–15:00 UTC; 0.04 instance-h | ≤ 0.01 | — | completes 6,369 / 6,369 |
| 2026-10-25 | E6a default-practice fits | study-20261025T164211Z-4ffa4776 | 8 × r7i.8xlarge, spot (reclaims) | 1,260 taxa | ≈ 324 (code's estimate) | 16:42–20:35 UTC; ≈ 14.6 instance-h (8 reported shards 11.19, 7 reclaimed attempts 2.91, boot ≈ 0.5) | ≤ 31 | — | 15 launches for 8 shards |
| 2026-10-25 | E6a scoring | study-20261025T211731Z-017e88fa | 1 × r7i.xlarge, on-demand | — | — | 21:19–22:11 UTC; 0.87 instance-h | ≈ 0.23 | — | |
| 2026-10-26 | E2 re-score, all finds | study-20261026T004856Z-35fc3d63 | 1 × r7i.xlarge, on-demand | — | — | 00:50–01:43 UTC | ≈ 0.23 | — | |
| 2026-10-26 | E2 re-score, observed after the cutoff | study-20261026T004853Z-bb7457e9 | 1 × r7i.xlarge, on-demand | — | — | 00:50–01:00 UTC | ≈ 0.04 | — | |
| 2026-10-26 | E6a paired re-score | study-20261026T020304Z-017e88fa | 1 × r7i.xlarge, on-demand | — | — | 02:05–03:20 UTC | ≈ 0.33 | — | |
| 2026-10-25/29 | E1 full run (virtual-species calibration) | study-20261025T212753Z-55239fbd | r7i.8xlarge: spot (incl. the attempt lost to an AWS 5xx and reclaims), then on-demand | 2,840 species | — | ≈ 63.6 instance-h (spot ≈ 30.8, on-demand 32.8) | ≤ 134 (spot ≤ 65; on-demand ≈ 69) | — | on-demand inside Steve's 40 h limit |
| 2026-10-26 | E9 DNA-name fits | priv-20261026T021038Z-3ba43cf6 | r7i.8xlarge × 3 + r7i.4xlarge, spot | 1,852 fitted, 52 refused | — | ≈ 5.8 instance-h + finish worker | ≤ 13 | — | |
| 2026-10-26 | E9 record-name fits | priv-20261026T021038Z-9c0ba509 | r7i spot; shard 4 resumed on-demand r7i.4xlarge | 1,860 fitted, 44 refused | — | [PENDING final] | ≤ 12 so far | — | hit the 8 h limit; shard 4 relaunched (Steve's OK) |
| 2026-10-28 | E9 scoring | — | 1 × r7i.xlarge, on-demand | — | — | about 2 h | ≈ 0.53 | — | |
| 2026-10-29 | E9 study-compare | — | 1 shard | — | — | — | ≈ 0.05 | — | |
| 2026-10-28 | E16 descriptives | — | the public API and the Atlas box (read-only) | — | — | — | 0 (no EC2) | — | |
| — | E1c, E3 read-out | [PENDING] | | | | | est. E1 27–46 (doubled sizes); E1c 5–10; E9 8–15; E6a 12–15 | | estimates from Appendix A and the pilots |

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
