# E1 cost pilot (calibration, not a result)

- **Question.** What does one virtual species cost per learner and null
  design, so that the E1 compute estimate can be set? Serves E1 planning and
  E23; tests no hypothesis.
- **Reproducibility.** exploratory-pre-freeze (development pilot).
- **Data.** A local development pull (2026-10-06, file sha256 prefix
  636dd0f203d94fa2) and draft layers (layer key df57c9d4…0d12b49), not the
  frozen pull.
- **Code.** study/e1-virtual-knobs @ e99ecd5 (pre-review; later review fixes
  touch no timing path). The four species are the first species of four
  layout cells from `atlas_calibration_layout()`, run through
  `atlas_calibration_study(layout = <those rows>)`, seed 1, nulls 99, stop at
  5, workers 1. There is no CLI rerun command, because a pilot picks cells by
  hand.
- **Result.**

  | Cell | Detection sites | Draws | Seconds | Maxent (s) | RF (s) | ESM (s) | Scatter | Shift |
  |---|---|---|---|---|---|---|---|---|
  | full/habitat/50–99/narrow/strong | 51 | 1 | 894 | 607 | 248 | – | pass, 100 drawn (both) | fail, 10 drawn (both) |
  | full/geography/100–199/2 centres | 117 | 3 | 848 | 541 | 217 | – | pass, 100 drawn (both) | fail, 10 drawn (both) |
  | full/habitat/20–29/wide/weak | 23 | 2 | 98 | 28 | 57 | – | fail, 20 and 10 drawn | fail, 10 drawn |
  | esm/habitat/5–9/strong | 8 | 1 | 92 | – | – | 89 | fail, 10 drawn | fail, 10 drawn |

  - Unit cost per null cross-validation: Maxent ≈ 5.2 s (5 folds, roughly
    flat from 51 to 117 sites); RF ≈ 2.2 s; ESM ≈ 4.4 s (3 folds). The effort
    arms take 10–30 s per species.
  - Scaled to the then pre-registered 1,420 species: ≈ 270 CPU-h on this
    machine's cores, ≈ 460 CPU-h if every test drew all 99 nulls. Assumed:
    scattered nulls pass about 80%; shifted nulls pass about 30% of habitat
    and 5% of geography species (from E1b).
  - Caveats: four species; none in the 200+ band; a shared PC, not EC2.
  - Results files stay on the development machine; not stored.
- **Cost.** Local PC (Windows, R 4.6.1), 2 processes × 1 core; fit
  CPU-hours 0.56 (2,026 s); billed instance-hours 0; wall time 29 min;
  compute USD 0; storage added 0.
- **Decision.** E1 species per cell doubled, counts only, before launch
  (Atlas Paper Coordinator, 2026-10-13; see the E1 pre-registration's
  amendments). The launch estimate goes to Steve with the go.
