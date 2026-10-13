# E12 step 0: held-out scores of the 576 refreshed strong models

- **Question.** Behind the 573 maps that matched within float32 tolerance in
  the full-view refresh, did any held-out scores move? First step of E12
  (`2026-10-13-plan-e12-grade-stability.md`).
- **Reproducibility.** frozen (the frozen release's refresh).
- **Data.** Refresh job full-20261013T140649Z-5cf5b864 against release
  79fe85f3; all 576 strong models. Refresh workers by last attempt: shards
  1, 2 and 4 on r7i (Intel Xeon Platinum 8488C), shard 3 on r7a (AMD EPYC
  9R14); every shard was relaunched at least once and only the last attempt
  is logged. (Corrected: an earlier note said all refresh workers were
  r7i.)
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
  score drift behind matching maps. The processor that fitted the frozen
  release's models was not recorded (R_main, job 20261013T022520Z-2cb67f32,
  predates per-model machine records, its type list allowed r7a and r7i,
  and EC2 no longer holds the instances), and the refits ran on both
  families. The three changed models were refitted on workers whose last
  attempt was Intel; the 28 tuned Maxent models refitted on AMD all
  reproduced. The pattern is consistent with a rare, processor-dependent
  effect but does not establish it. The controlled test is `study-repro`
  (r7i ×2, r7a ×2, frozen inputs); per-model machine recording is in place
  from Atlas commit c099bc7 on.
- **Cost.** Read-only; no compute billed.
- **Decision.** None; E12 proceeds to the cross-family gate (`study-repro`).
