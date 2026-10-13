# Plan: reproducibility and grade stability across reruns and machines (paper E12)

- **Status.** Planned 2026-10-13, before code or run.
- **Question.** When the same model is refitted from the same inputs, on the
  same processor family and on another, do its map, its held-out scores and
  its grade come out the same? Serves C4 ("says which maps to trust") and
  qualifies C1–C2: a grade that changes with the machine is a weaker trust
  measure.
- **Why now.** Refitting the frozen release's 576 strong models for the
  full-view refresh (release 20261013T155140Z-026d3a26) kept 573 maps within
  float32 tolerance. Three tuned Maxent models chose other settings: one a
  near-tie (*Russula* sp. 'compacta-PA01', picks 0.003 apart), and two where
  the cross-validated AUC of every candidate moved (*Stropharia hardii*: mean
  change −0.032, correlation of candidate scores 0.49; *Gliophorus fumosus*:
  median change 0.035, correlation 0.55), with the same pull, presences and
  background, and random forests byte-identical. The mechanism is not
  identified. The refresh check compares maps, not held-out scores, so a
  model can keep its map within tolerance while its AUC and Boyce shift.
- **Reproducibility.** frozen.

## Design

- **Step 0 (read-only, the rebuild lane's script, run by ops).** For all 576
  refreshed models: chosen setting, per-candidate tuning AUCs, mean blocked
  AUC, pooled Boyce and per-fold AUC, release vs refit, by learner.
- **Sample.** Stratified by learner (Maxent, RF, boosted trees, ESM) × site
  band (3–4, 5–19, 20–49, 50+) × grade (strong, weak, failed), up to 25 per
  cell, seed recorded (≈ 600–900 models).
- **Arms.** Full graded refits from the frozen pull with the frozen settings
  and seeds, nulls included: (a) twice on one pinned instance family (the
  original's, r7i), (b) once on another (r7a). Every model's result records
  the machine that fitted it (feat/result-machine).
- **Measures.** Grade agreement (strong/weak/failed) with Cohen's κ and the
  share of flips by type; chosen-setting agreement; |Δ| of blocked AUC,
  pooled Boyce, null-test p and map strength; map difference against the
  float32 tolerance. Reported for (a) within family and (b) across families,
  by learner and site band.

## Reading

- Any difference within (a) means a non-determinism inside one machine
  type: report it and fix it before submission.
- Differences only in (b) are machine effects: report the grade-flip rate
  with its interval, and state it in the paper wherever grades are used.
- If grade flips concentrate in small-site tuned Maxent, say so, and test
  whether a more stable tuning rule (e.g. a fixed path or a tie tolerance)
  removes them; that would be a method change for a later release, not the
  frozen one.

## Cost

Est. 30–60 CPU-h (≈ 0.05 CPU-h per model with nulls, three fits each), a few
dollars. Gate: feat/result-machine merged.

## Deviations

None yet.
