# Experiment registry

One file per analysis that feeds the paper or a method decision, named
`YYYY-MM-DD-<slug>.md` after the day it ran. A result that is not here cannot
be cited in the paper.

Each file says:

- **Question** — one sentence, and the claim or decision it serves (the
  paper's evidence plan IDs, e.g. E1, are in `docs/paper/draft.md`,
  Appendix A).
- **Data** — the release id, pull fingerprint and layer key it read. An
  analysis run before the paper's frozen release is marked
  `reproducibility: exploratory-pre-freeze`; one on the frozen release,
  `reproducibility: frozen`.
- **Code** — the commit, and the one command that reruns it.
- **Result** — the numbers, with intervals, and where the results file lives
  in the store (never a local path, never a record or coordinate).
- **Decision** — what was decided from it, by whom, or "none".

Results files hold no coordinates, but they stay in the store or the data
directory, not in git (`tools/check-no-data.sh`).
