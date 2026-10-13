# E6a cost pilot (calibration, not a result)

- **Question.** What does one default-practice Maxent taxon cost, so that the
  E6a estimate can be set? Serves E6a planning and E23; tests no hypothesis.
- **Reproducibility.** exploratory-pre-freeze (development pilot).
- **Data.** The local development pull (2026-10-06, sha256 prefix
  636dd0f203d94fa2) and draft layers (69 predictors, layer key
  df57c9d4…0d12b49), not the hindcast pull. One real taxon near each of 31
  and 102 detection sites.
- **Code.** study/e6a-default-maxent @ b15dafe, `atlas_default_taxon` with
  nulls = 3 (timing only), 10,000 background points, 5 random folds.
- **Result.** lqh at 31 sites: 30 s per fit, 41 s per null fit, ≈ 16 min per
  taxon with 19 nulls. lqph at 102 sites: 63 s per fit, 68 s per null fit,
  ≈ 28 min per taxon. Scaled to ~650 taxa with 20+ sites: ≈ 230 CPU-h, up to
  ~300. The two taxa's own scores are not reported; a timing run is not a
  result.
- **Cost.** Local PC, 1 core; fit CPU-hours 0.25 (912 s); billed
  instance-hours 0; wall time 16 min (plus a first attempt that stopped at
  once on the constant-predictor error, since fixed); compute USD 0; storage
  added 0.
- **Decision.** Planning constants set from it (study/e6a-default-maxent @
  3fd342f); predictors constant over a fit's points are left out (plan-e6a,
  e681151).
