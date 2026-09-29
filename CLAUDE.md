# CLAUDE.md

MycoMap Atlas: species distribution models for fungi from DNA-validated MycoMap
records. See README.md for the pipeline and data layout.

## Rules

- **mycomap.org is read-only from here.** Records come from `ssh mycomap-sql`
  (database-enforced read-only, 60 s statement cap). Never write to .org, .com,
  iNaturalist or Mushroom Observer from this repo.
- **Training data is DNA-validated only**: green in a project, red in none.
  Never train on unassessed records, on eDNA, or on MycoMap Vision's output.
  Vision calls Atlas for a prior; if Atlas learned from Vision, the two would
  feed each other their own guesses.
- **A model belongs to a record set, not a name.** About a third of the
  modelable taxa carry provisional temp codes that FungAI can rename or
  re-cluster, so invalidation keys on the record-set fingerprint.
- **Never publish a coordinate.** `data/` is never committed. Anything drawn is
  aggregated to 0.1 degrees; anything published is 1 km or coarser; no training
  points appear in any artifact. No taxon is singled out as sensitive at the
  moment (Steve, 2026-09-28) — the resolution floor above applies to all of
  them. Raise it again before the first public release of maps.
- **Only the container publishes a release.** Iterate natively, but anything
  that reaches .org is built in the pinned Docker image.
- **Releases are reproducible.** Each records the record-set fingerprint, layer
  versions, lockfile hash, seed and model settings. Same inputs, same output.
- **Statements sent to the SQL route are one line, with no double quote and no
  percent sign** — use `strpos()` and `right()` rather than `LIKE`. The string
  has to survive both a Windows command line and a POSIX shell.
- **Sampling bias is the central modelling problem.** Background points come
  from the same validated universe across all taxa (a target-group background).
  Six states and provinces hold 61% of the records, and Indiana alone holds
  12%; without that correction a model learns where sequencing happened.

## Testing

- Tests with every change: `Rscript -e "testthat::test_local()"`. Name a test
  after the rule it protects, and confirm it fails when the guard is broken.
- Modelling code also gets **simulation tests**: generate a species from a known
  response on a synthetic landscape and check the fit recovers it. Unit tests
  cannot tell a working model from a plausible-looking one.
- Evaluation is **spatially blocked**, never a random split, and reported with
  the Boyce index. Random splits flatter spatially clustered data.

## Conventions

- R 4.x. Sources in `R/`, tests in `tests/testthat/`, command line through
  `./atlas` (Git Bash) or `./atlas.ps1` (PowerShell).
- Call other packages as `pkg::fun()`. The command line can run from sources
  without installing, and that only works with explicit namespaces.
- Batch workers are separate R processes (`parallel`, PSOCK). A function sent
  to one carries its enclosing frame, so set its environment to `globalenv()`
  or every worker receives a copy of the pull; and a terra raster cannot be
  sent at all, so each worker opens the stack itself.
- Windows host: Git Bash or PowerShell, not WSL.
- The web app in `web/` follows mycomap.org's design tokens. When .org's
  palette or header changes, update `web/tailwind.config.ts` and
  `web/src/index.css` to match rather than inventing a second look.
