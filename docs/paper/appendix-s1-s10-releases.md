# Appendix S1, Section S10: releases, reproducibility, cost and time (draft)

*Moved from the main text on 2026-10-13 (lean main text); edited only for the move.*

## S10.1 Releases and reproducibility

A Lightsail server pulls eligible records nightly, refits only taxa whose
fingerprint or settings changed on EC2 spot workers in one pinned container
(base image by digest, R packages from a dated snapshot), and publishes a
content-addressed release recording the code commit, package versions, layer
builds and pull fingerprint. Seeds come from the fingerprint. Releases are
archived on Zenodo (layers and models series, CC BY-SA 4.0). Exact
coordinates never leave Atlas's private compute and storage; everything
published is 1 km or coarser, and records are drawn as 0.1° cells, the same
for every taxon.

Atlas is reproducible from its pinned container (base image by digest, R
packages from a dated Posit snapshot, the store's content-addressed inputs).
A rerun on the same machine reproduces maps byte for byte; we verified
this for Maxent, random forests and boosted trees, tuned and untuned, with
and without null tests. Across machines, results agree to floating-point
precision rather than bitwise (OpenBLAS selects its matrix kernels by
processor, and the area-of-applicability index is computed through one of
them): equal to within float32 storage precision (four rounding steps),
suitability to a relative 5e-7 and the index to an absolute 1e-6 (or a
relative 5e-7 where larger), where a genuinely different model differs by
1e-4 or more. Refitting the frozen release's 576 strong models for the
full-view refresh met these tolerances for 573. The other three are tuned
Maxent models whose settings choice differed: one near-tie (*Russula* sp.
'compacta-PA01'), and two (*Stropharia hardii*, *Gliophorus fumosus*) where
the cross-validated scores of every candidate differed across machines,
from the same records and background. E12 found the mechanism: fits
are bit-identical within a processor family (Intel r7i, AMD r7a) and the
three models' release fits are each reproduced on exactly one family. The release keeps their original fits and lists both
fits' settings and tuning scores. The other 573 models' chosen settings,
tuning scores, blocked AUC, pooled Boyce and per-fold AUC were identical to
four decimals, so no score drift sits behind matching maps; the changes
are confined to 3 of 121 tuned Maxent models and none of 455 other models.
On one machine, repeated fits in fresh processes and different orders were
bit-identical. E12 (`docs/experiments/2026-10-13-plan-e12-grade-stability.md`)
refitted 507 drawn models, with their null tests, on r7i twice: both runs
matched the release on all 507. The second run first differed in 191 of
225 small-model ensembles (the map's bytes, and in one model its pooled
Boyce by 0.001; every grade unchanged): glmnet's
settings are global to an R process, Maxent sets two of them, and an
ensemble fitted after a Maxent model in the same worker inherited them.
Production fits each learner in its own pool of worker processes, so
by construction every released ensemble was fitted at glmnet's defaults
and released maps are unaffected; the shard logs that survive (only each
shard's last attempt was kept) confirm that every fitting shard ran so,
and the direct evidence for the drawn sample is a1, which matched the
release on all 507. Each ensemble fit now runs at glmnet's defaults and
restores the process's settings (Atlas 5b58f30; the detection model of E14
is pinned likewise, a8861ab, though it was never affected), and the rerun
matched on 507 of 507. A second machine effect: the spatial block, the blockCV
variogram range rounded to 5 km (full models only; ensembles use a fixed
100 km block), can depend on the processor family: of
the 1,144 hindcast taxa whose Maxent was fitted on r7a, 35 had another
block when rebuilt on r7i, by 5 to 240 km, and so other folds. Across processor families
(arm b, one AMD r7a.8xlarge against a1 on Intel r7i), 502 of 507 refits
were identical and 505 kept their grade. Weighted back to the frozen
release by the draw's 24 cells (9,040 models; the one untested model is in
no cell), 98.45% of models are identical across families (differing share
1.55%, 95% interval 0.37–3.03%) and 99.57% keep their grade (grade changes
0.43%, 0.00–1.24%); Cohen's κ on grades is 0.9895 (0.9940 unweighted).
Intervals are from a bootstrap of models within cells (10,000 resamples),
each cell weighted by its share of the release. The two Intel reruns were
identical to the release for 100% of models (κ = 1). By learner, no
ensemble of small models differed (0% of 6,041) and 4.67% of the 2,999
full-design models did (plan-e12, weighted rates, with its script
`2026-10-21-e12-reading.R`). Every ensemble (225) and boosted-trees model
(40) was identical; Maxent 127 of 128 and random forests 110 of 114. The
five that differed are full models at 20 to 49 sites, all with the same
records: one Maxent model went from failed to weak with other settings,
three random forests stayed weak with other settings, and one random
forest went from weak to strong with the same settings and map but other
tuning and fold scores. A block-only step recomputed the variogram
block, without any fit, for the 282 drawn full-design models on both
families: on r7i all 282 equal the release's recorded block, and on r7a
277 do. The five whose block differs on r7a (by 10 to 90 km) are exactly
the five that differed in arm b. Split by block: of the 277 models with
the same block, 277 are identical and keep their grade (95% upper bound on
the difference rate 1.4%, Wilson); of the 5 with a changed block, none is
identical and 3 keep their grade. The block changes for 4.67% of the
release's full-design models (weighted), which is the whole of arm b's
1.55% differing share, and both grade changes are block changes. So within
one processor family refits are bit-identical to the release, and across
families they differ all and only where the spatial block differs. This
is shown for the 507-model sample; the refresh's three tuned-Maxent flips
(gate 2) fit the same mechanism (*Stropharia hardii* is in both) but are
not all in the sample (plan-e12, the block-only step and the reading,
2026-10-21). Our refit checks enforce the tolerances
and flag anything beyond them.

Published records follow their source's privacy: records whose location
the source hides, obscures or may hide (unknown privacy) are excluded from
all published record-level layers. In practice that is the 0.1° record
cells, from which about 0.5% of records (those of unknown privacy, whose
0.1° cell would be finer than iNaturalist's own obscuring) are dropped; no
model is refitted. Everything else published is map-derived or coarse
(state counts, the 500 km accessible area). The frozen release ships the
corrected cells file.

Each shard's record names its instance type,
processor and BLAS library file, and since the hindcast each model's
record does too. Fits run one BLAS thread per worker process (OpenBLAS
0.3.26, pthread build; OPENBLAS_NUM_THREADS and OMP_NUM_THREADS are set to 1
in every worker since 2026-09-30, checked by a test). E12's two reruns on
r7i ran with up to 32 threads per worker and both matched the release on
all 507 models, so the thread count does not change a fit (plan-e12,
implementation notes). [PENDING: the CPU kernel
OpenBLAS selects, which the records do not yet name.]
For releases after the frozen one (decided 2026-10-21), each taxon's block
is recorded once and reused for every learner, retry and refit, which
changes no released number and lets the frozen release refit identically
on either family from its recorded blocks; until that is in place,
production fits run on r7i only. Each result will also record its BLAS
build, thread setting and processor [PENDING: in place from the release
that carries it].

## S10.1b The public API

All endpoints are GET and described in `/api/openapi.json` (as served by
image 7915ff8, deployed 2026-10-21). `/api/taxa/{name}/card.jpg` serves a
1200 × 630 preview image for each of the 470 taxa with a strong map (404
otherwise), and link-preview robots get `/share/taxa/{name}`.

- Site and data: `/api/openapi.json`, `/api/sources`, `/api/downloads`
  (Zenodo), `/api/status`, `/api/me`, `/api/layers`, `/api/algorithms`,
  `/api/benchmarks/latest`, `/api/tracker`.
- Taxa: `/api/search`, `/api/taxa`, `/api/names/{name}`,
  `/api/taxa/{name}`, `/api/taxa/{name}/cells`, `/api/taxa/{name}/regions`,
  `/api/regions`, `/api/checklist.csv`.
- Maps: `/api/taxa/{name}/best-map`, `/api/maps/best`,
  `/api/taxa/{name}/model`, `/api/models`; images
  `/api/taxa/{name}/map.png`, `image.png`, `ensemble`, `ensemble.png`,
  `card.jpg`; `/api/taxa/{name}/raster.tif` with sign-in or a token.
- Location prior: `/api/here`, `/api/prior`, `/api/prior/{file}`.

Rate limits per caller and minute: anonymous 300 (per visitor address),
standard token or signed-in person 1,200, bulk token 6,000; over the limit
the API answers 429 with `X-RateLimit-Limit` and `X-RateLimit-Remaining`.
Tokens are issued per mycomap.org account and approved by an administrator
there, and are sent as `Authorization: Bearer <token>`; a live token or
session also unlocks downloads. Map problems are reported through the
site's "Report a map problem" link (a GitHub issue on the code repository,
bug template) or to info@mycomap.org.

## S10.2 Cost and time

The ledger of every run is `docs/paper/costs.md` (E23); its tables move here at submission.
