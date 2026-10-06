# Security

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** button under this repository's Security
tab, which opens a private advisory. If that is not available to you, email
info@mycomap.org.

Please do not open a public issue for a security report.

## Reporting an exposed locality

This project models where rare fungi live, so a data problem can be a safety
problem for a species or a landowner. Report it the same private way if you
find:

- a published map, file or API response that reveals a collection site more
  precisely than 1 km;
- exact coordinates anywhere in this repository, its history, or its issues;
- a suitability map that in your judgement pinpoints a population someone
  could harm, even at the published resolution.

We would rather coarsen or withdraw a map than argue about whether the
resolution was technically within policy.

## What Atlas holds

- **Exact coordinates** of DNA-validated collections exist only in `data/` on
  the machine that pulled them. That directory is git-ignored, and CI refuses
  commits that would add data files.
- **Published output** is aggregated: 0.1° for anything drawn, 1 km or coarser
  for anything published, and no training points in any artifact. That floor
  applies to every taxon, and it is the protection doing the work.
- **No taxon is hidden or coarsened** (settled 2026-10-06). There is no
  suppression list, and no taxon, however rare, is drawn coarser than the
  floor above. A report of an exposed population (see above) is handled on
  its own merits.
- **Credentials** are never in this repository. Records arrive through an SSH
  host configured on the operator's machine, and that route is read-only,
  enforced by the database rather than by this code.
- **CI holds no secrets.** Every test runs offline, so a pull request from a
  fork has nothing to steal.

## Scope

This repository only. mycomap.org, mycomap.com and MycoMap Vision are separate
systems; report issues in those to the same address, saying which system you
mean.
