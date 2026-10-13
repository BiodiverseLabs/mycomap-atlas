# E12 gate: two taxa, one machine, six fresh processes (calibration, not a result)

- **Question.** Do the two Maxent models whose cross-validated scores moved
  between machines in the refresh (*Stropharia hardii*, *Gliophorus
  fumosus*) come out the same when refitted repeatedly on one machine, in
  different orders and process states? First gate of E12
  (`2026-10-13-plan-e12-grade-stability.md`).
- **Reproducibility.** exploratory-pre-freeze (development pull).
- **Data.** The 2026-10-06 development pull (not the frozen pull
  x73b85b36); draft layers. *Stropharia hardii* 42 presences here,
  *Gliophorus fumosus* 21.
- **Code.** Production Maxent tuning, no nulls; nothing written to the
  store. Windows, R 4.6.1, reference BLAS, one thread.
- **Runs.** Six fresh R processes: runs 1 and 2 in the same order; run 3 in
  reverse order; run 4 after two other taxa (*Russula* sp. 'compacta-PA01',
  *Laetiporus sulphureus*) in the same process; runs 5 and 6 through the new
  fresh-process study path.
- **Result.** Every run bit-identical: same presences, background and
  predictors; same chosen settings (*Stropharia* lq / 2, *Gliophorus*
  lqh / 0.5); all ten tuning AUCs equal to four decimals; per-fold AUC, mean
  AUC and Boyce equal; default raster SHA-256 equal across the study-path
  runs.
- **Reading.** No run-to-run or process-state non-determinism in the Maxent
  path on one machine. Production workers already pin one BLAS thread, so
  thread effects are excluded. The processor (OpenBLAS kernel selection or
  the maths library by CPU) is the leading explanation for the refresh's
  differences; not confirmed until the release image runs on the frozen
  inputs on both families (next gate: `study-repro`, one EC2 worker per
  family, 3 taxa × 2 fresh runs, compared with each other and with the
  release; branch study/refit-repro d5ee4ef, awaiting Steve's go). Caveat:
  this machine used reference BLAS, production uses OpenBLAS.
- **Cost.** Local PC, one core; compute USD 0; storage added 0.
  [PENDING: CPU-hours and wall time from the rebuild lane.]
- **Decision.** The same-machine gate passes on this machine; E12 proceeds
  to the cross-family gate.
