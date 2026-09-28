# Contributing to MycoMap Atlas

Atlas builds species distribution models for fungi from DNA-validated MycoMap
records. Contributions are welcome — please read the rules below first, because
two of them exist to protect real collection localities rather than code
quality.

## The rules

**1. Nothing from `data/` ever enters git.** That directory holds exact
coordinates of DNA-validated collections. It is git-ignored, and CI refuses any
commit that adds a file under it, any raster or record table, or any file over
2 MB. Don't work around the guard — if you need a fixture, extend the synthetic
records in `tests/testthat/helper-occurrences.R`.

**2. Never paste a coordinate.** Not in an issue, a pull request, a log
excerpt, or a screenshot. Round to 0.1°, or name the state or province. This
applies to error output too: if a traceback contains coordinates, trim it.

**3. mycomap.org is read-only from here.** Records arrive through a read-only
SQL route. No code in this repository may write to mycomap.org, mycomap.com,
iNaturalist or Mushroom Observer.

**4. Tests stay offline.** No test may need the network, an SSH host, or any
credential. That is what lets CI run without a single secret, including on pull
requests from forks. Anything that would need a live source belongs behind a
function you can test with a synthetic input.

**5. Published output is aggregated.** Anything drawn on a map is aggregated to
0.1°; anything published is 1 km or coarser; no training points appear in any
artifact. If you add an output, keep it that way and add a test that says so.

**6. A model belongs to a record set, not a name.** About a third of the
modelable taxa carry provisional temp codes that can be renamed or re-clustered
upstream, so invalidation keys on the record-set fingerprint.

## Getting set up

R 4.x, and pnpm for the web app.

```bash
Rscript -e "install.packages(c('digest','jsonlite','testthat','plumber','terra','geodata'), repos='https://cloud.r-project.org')"
```

```bash
Rscript -e "testthat::test_local()"
```

The command line runs from the sources without installing the package:
`./atlas help` in Git Bash, `./atlas.ps1 help` in PowerShell. R's Windows
installer does not put R on PATH; both launchers find it anyway.

Pulling records needs the `mycomap-sql` SSH host, which most contributors will
not have. Everything except `pull-occurrences` works without it, and the tests
never touch it.

## Tests

Every behaviour change gets a test, in the same change as the code.

- Name a test after the rule it protects, not the function it calls.
- Check the test can fail: break the code under test once, watch it go red,
  then restore it.
- Modelling code also gets a **simulation test** — generate a species from a
  known response on a synthetic landscape and check the fit recovers it. A unit
  test cannot tell a working model from a plausible-looking one.
- Evaluation is spatially blocked, never a random split. Random splits flatter
  spatially clustered data, and every fungal dataset is spatially clustered.

## Adding an environmental layer

Layers live in the registry in `R/layers.R`. A new entry needs:

- **North American coverage.** The grid spans Mexico to northern Canada, so
  United States products such as TreeMap, NLCD and PAD-US cannot be the only
  source for a layer. British Columbia alone holds 8% of the records.
- `title`, `source`, `url`, `license`, `citation`, `method` — provenance is not
  optional, and a test enforces it.
- A `rename` step that names bands by parsed identity rather than by position.
  A mislabelled bio variable is a wrong model that still looks right.
- A note about what the layer does **not** say. Tree cover is a fraction, not
  host identity, and the registry says so.

## Pull requests

Keep them to one topic. Explain any new dependency — the web app's dependency
tree is a supply-chain surface, and R packages are pulled at build time. Expect
review before merge; nothing merges automatically.
