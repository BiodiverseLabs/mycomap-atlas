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
from the same records and background; the mechanism is under
investigation (E12). The release keeps their original fits and lists both
fits' settings and tuning scores. The other 573 models' chosen settings,
tuning scores, blocked AUC, pooled Boyce and per-fold AUC were identical to
four decimals, so no score drift sits behind matching maps; the changes
are confined to 3 of 121 tuned Maxent models and none of 455 other models.
On one machine, repeated fits in fresh processes and different orders were
bit-identical. E12 measures how often grades differ across processor
families [PENDING E12]. Our refit checks enforce the tolerances
and flag anything beyond them.

Published records follow their source's privacy: records whose location
is hidden, obscured or of unknown privacy at the source are excluded from
all published record-level layers. In practice that is the 0.1° record
cells, from which about 0.5% of records (those of unknown privacy, whose
0.1° cell would be finer than iNaturalist's own obscuring) are dropped; no
model is refitted. Everything else published is map-derived or coarse
(state counts, the 500 km accessible area). The frozen release ships the
corrected cells file.

Each shard's record names its instance type,
processor and BLAS. [PENDING E12: the numbers from the rerun.]

## S10.2 Cost and time

The ledger of every run is `docs/paper/costs.md` (E23); its tables move here at submission.
