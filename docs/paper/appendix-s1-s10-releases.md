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
were identical and 505 kept their grade (raw rates 99.0% and 99.6%, before
the plan's cell weighting). Every ensemble (225) and boosted-trees model
(40) was identical; Maxent 127 of 128 and random forests 110 of 114. The
five that differed are full models at 20 to 49 sites, all with the same
records: one Maxent model went from failed to weak with other settings,
three random forests stayed weak with other settings, and one random
forest went from weak to strong with the same settings and map but other
tuning and fold scores. All five are taxa whose spatial block differed
between families in the hindcast (E6b), so the block is the likely cause;
whether each one's block differed on the frozen records is what the
block-only step shows [PENDING E12 block step; cell-weighted rates and κ
follow it]. Our refit checks enforce the tolerances
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
record does too. [PENDING: the BLAS build, thread setting and kernel, which
the records do not yet name.]
[PENDING: after the block step, a recommendation for releases: measure each
taxon's block once and reuse it, and/or pin the processor family or one
OpenBLAS kernel (Steve's decision).]

## S10.2 Cost and time

The ledger of every run is `docs/paper/costs.md` (E23); its tables move here at submission.
