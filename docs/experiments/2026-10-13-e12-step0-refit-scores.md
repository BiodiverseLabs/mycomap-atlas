# E12 step 0: held-out scores of the 576 refreshed strong models

- **Question.** Behind the 573 maps that matched within float32 tolerance in
  the full-view refresh, did any held-out scores move? First step of E12
  (`2026-10-13-plan-e12-grade-stability.md`).
- **Reproducibility.** frozen (the frozen release's refresh).
- **Data.** Refresh job full-20261013T140649Z-5cf5b864 (all workers r7i)
  against release 79fe85f3 (R_main's shards ran r7i ×3, r7a ×1, with no
  per-model record of which); all 576 strong models.
- **Code.** The rebuild lane's read-only `refit_scores`, run by the
  operations lane on the Atlas server.
- **Result.**

  | Learner | Models | Settings changed | Tuning AUC moved > 0.001 | Mean AUC moved | Boyce moved |
  |---|---|---|---|---|---|
  | Maxent | 121 | 3 | 3 (max 0.069) | 3 (max 0.066) | 3 (max 0.191) |
  | Random forest | 85 | 0 | 0 | 0 | 0 |
  | Boosted trees | 5 | 0 | 0 | 0 | 0 |
  | Small-model ensembles | 365 | 0 | 0 | 0 | 0 |

  Every other model's chosen settings, tuning AUCs, mean AUC, pooled Boyce
  and per-fold AUC are identical to four decimals. Score changes are
  confined to the three models whose maps changed: 3 of 121 tuned Maxent
  models and 0 of 455 others. All three have 21–45 detection sites, in the 20–49 band
  (Maxent is fitted only from 20 sites).
- **Reading.** The map check and the score check agree; there is no hidden
  score drift behind matching maps. Probably only about a quarter of models
  crossed processor families (refit on r7i, original on r7i or r7a), so the
  cross-family rate among tuned Maxent may be higher than 3 in 121.
  [PENDING: the shard and attempt of the three changed models, and how many
  unchanged Maxent models were also r7a-fitted (asked of the operations
  lane).]
- **Cost.** Read-only; no compute billed.
- **Decision.** None; E12 proceeds to the cross-family gate (`study-repro`).
