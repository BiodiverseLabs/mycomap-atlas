# Null-test calibration by site band (re-read)

- **Question.** How do the false-pass rate and power of each null design vary
  with a species' number of survey sites? Serves paper claim C1 (evidence
  plan E1b) and the design of the E1 rerun.
- **Reproducibility.** exploratory-pre-freeze.
- **Data.** The virtual-species null study started 2026-10-06 09:15 UTC
  (`virtual-20261006T091510Z.json`): draft grid, layer key `df57c9d4…`,
  pull of 2026-10-06; 100 species (50 habitat, 50 geography), 99 scored, one
  geography species refused. Maxent (`maxnet:none`), 99 nulls, stop after 5,
  designs scatter, shift, shift-effort; seed 1. Original command:

  ```bash
  ./atlas study-virtual --species=100 --kinds=habitat,geography --nulls=99 \
    --null-designs=scatter,shift,shift-effort --stop-after=5 --arms=maxnet:none --workers=16
  ```

- **Method.** Read the per-species verdicts (`taxa[].nulls.<design>.skill`)
  and count passes by kind and by the study's site band. Wilson 95%
  intervals. No refit.
- **Result.**

  | Sites | Scatter false pass | Shift false pass | Shift-effort false pass | Scatter power | Shift power |
  |---|---|---|---|---|---|
  | 20–29 | 1/6 | 0/6 | 0/6 | 3/7 | 0/7 |
  | 30–49 | 9/15 | 1/15 | 2/15 | 13/15 | 5/15 |
  | 50–99 | 8/10 | 0/10 | 0/10 | 10/12 | 5/12 |
  | 100–199 | 11/11 | 0/11 | 0/11 | 9/11 | 2/11 |
  | 200+ | 7/7 | 0/7 | 0/7 | 5/5 | 1/5 |
  | All | 36/49, 73% (60–84) | 1/49, 2% (0–11) | 2/49, 4% (1–14) | 40/50, 80% (67–89) | 13/50, 26% (16–40) |

  - Scattered nulls pass every geography species from 100 sites up.
  - Shifted nulls keep false passes near zero in every band, but their power
    does not rise with sites (2/11 at 100–199, 1/5 at 200+).
  - Habitat species passing the shift test have maps closer to the true
    habitat: median Spearman ρ 0.83 (13 passed) vs 0.73 (37 not); under
    scatter, 0.79 (40) vs 0.60 (10).
  - Mean nulls drawn per species: scatter 86.9, shift 29.2, shift-effort 29.4.
- **Decision.** None new; production already uses shift nulls (2026-10-08).
  For the E1 rerun: more species per band, a habitat-breadth stratum to
  explain the flat power, and the random forest and small-model ensembles as
  well as Maxent.
