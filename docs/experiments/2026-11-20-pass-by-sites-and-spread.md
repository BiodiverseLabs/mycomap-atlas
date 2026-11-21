# How often a map passes, by its number of sites and their spread (frozen release)

Descriptive. Registered on 2026-11-20, before anything below is computed.
Version 2: adds the population and the script's hash, and rewords one limit
(Paper Coordinator's notes); the plan is unchanged.
Version 3: adds the Results (from the run's output, below) and four notes on
them that the plan did not foresee; the plan above is unchanged from version 2.
Counts only: no taxon names, record numbers, places or coordinates leave
the Atlas box.

- **Question.** When does a taxon have enough evidence for its map to pass
  the shifted-null test (strong)? Table 1c shows the strong share by
  detection sites alone, rising from 2.1% at 3–4 sites to 16.4% at 20–49,
  then falling to 8.0% at 50–99 and 0% at 100+. This entry asks how the
  share varies jointly with sites and with how widely those sites are
  spread. It serves the paper's "when is a map worth publishing" figure.
- **Data.** `reproducibility: frozen`. Release 20261013T191324Z-fa1b4198:
  its models' published grades, from the release index and model metrics.
  Its pull occurrences-20261012T051017Z-x73b85b36 (sha256 7d3c5d70…, 133,235
  records), read on the Atlas box only. No fits, no EC2, no network beyond
  the box.
- **Population.** The 6,369 modelled taxa (3 or more detection sites, with
  at least one model not refused), the denominator of Table 1c.
- **Unit.**
  - Primary: the taxon, as in Table 1c. A taxon's band is that of its
    largest model's detection sites (E16's rule), and it passes when any
    of its models is strong.
  - Supplement: the model, per learner (ESM, Maxent, random forest,
    boosted trees), with its own detection sites.
- **Sites.** Detection sites as the fits build them: the release pull's
  points on the draft grid, gathered into 5 km survey sites
  (atlas_attach_sites, ATLAS_SITE_KM = 5). A taxon's detection sites are
  the sites holding at least one of its records. Bands, as Table 1c: 3–4,
  5–9, 10–19, 20–49, 50–99, 100+.
- **Spread, primary: occupied 100 km blocks.** The number of distinct
  100 km blocks of the Atlas grid (atlas_block_labels at 100 km, fixed
  origin, North America Albers) holding at least one of the taxon's
  detection sites. Bands: 1, 2, 3–4, 5–9, 10–19, 20+.
  - Why this measure:
    - It is the unit the test itself works in. The cross-validation holds
      out blocks, ESM's blocks are exactly 100 km, and a shifted null is
      the taxon's pattern moved whole.
    - It is computed from the sites alone.
    - One far record adds a single block, not a large area.
    - It is a count, so its bands are fixed in advance.
- **Spread, supplement: hull area.** The area (km²) of the convex hull of
  the taxon's detection sites, for taxa with 3 or more sites not all on
  one line. Bands: under 1,000; 1,000–9,999; 10,000–99,999;
  100,000–999,999; 1,000,000 or more. Its weakness: one outlying site
  inflates it, which is why it is not primary. States and provinces are
  not used: they follow political lines, and are coarse where the sites
  are dense.
- **Grade rule in force.** The frozen release's test: up to 99 shifted
  nulls on the model's own fold split, stopping at 5, passing at
  p = (1 + k) / 100 ≤ 0.05 with pooled Boyce above 0. The pooled-splits and
  near-line rule of later releases does not apply here.
- **Output.**
  - A sites × spread grid. Each cell gives its taxa, strong taxa, and the
    strong share with a Wilson 95% interval.
  - Cells with fewer than 20 taxa are shown greyed, with their counts.
  - Marginal pass curves by sites alone (this reproduces Table 1c, as a
    check) and by spread alone.
  - The same grid per learner in the supplement.
- **Exploratory (registered as such).** Does spread add to sites? A
  logistic model at the taxon level, strong ~ log(sites) + log(blocks),
  against strong ~ log(sites): a likelihood-ratio test (1 df), with both
  coefficients and their 95% intervals. No pass line is set in advance,
  and nothing is concluded from it beyond the description.
- **Code.** sites_spread.R (sha256 d7e5a201c3cf8e27b1238163a811eeceb8c8523397475df0b78917a43ce411ad), run read-only on the
  box in the deployed image.
  - It reads the release's index from the store, and fetches its pull by
    the release job's own input record into a temporary folder, checking
    it against its hash.
  - It writes sites-spread.json: counts per cell, Wilson intervals, the
    Table 1c check, the per-learner grids, the hull supplement and the
    exploratory model's summary.
  - Smoke-tested on a synthetic release (exit 0, counts only, no names).
  - Expected time: minutes on the box. Cost: none beyond the box.

## Limits

- One release, and one test per model. A grade near the pass line is one
  draw: in E11, 39% of strong models sat at k = 3–4 of 99 nulls, and 6.3%
  of refits flipped between nights. A cell's strong share is the exact
  share of its taxa graded strong in this release. Because each grade is
  one draw near the line, a re-graded release could move it by a few
  points, and a single taxon's grade in it is not settled. The figure says
  so in its caption.
- The frozen release's 1 km iNaturalist cutoff and single-split rule
  define these sites and grades. Later releases (2 km cutoff, pooled
  splits) would need their own run of this entry.
- Sites and spread describe where the taxon was collected, which mixes
  its range with where people collect.

## Notes on the results (not foreseen by the plan)

- **The 1- and 2-block bands are empty, by the refusal rule.** A map is
  refused unless its training detections fall in enough blocks: at least
  3 blocks of 100 km in the small-model design used under 20 sites (3
  folds, block_km 100, min_blocks 3; R/algorithms.R), and at least
  ATLAS_MIN_BLOCKS = 5 blocks at the full models' own block size
  (R/fit.R). A taxon whose every model is refused is outside the
  population. The blocks here are counted from all of the taxon's sites in
  the pull, which include its training sites. The smallest count among the
  6,369 taxa is 3. Every result on spread, the exploratory model included,
  is conditional on at least 3 occupied blocks.
- **One taxon has 3–4 sites and 5–9 blocks.** Its band uses its largest
  model's detection sites, which are its training presences (the release
  index). Its blocks count every site of the name in the pull. Training
  drops the sites the predictor layers cannot describe, coastal and island
  cells mostly (atlas_add_predictors, R/background.R), so a taxon can have
  more sites in the pull than in training. That mechanism is in the code;
  the taxon itself was not looked at, as names stay on the box.
- **Blocks and sites are tied by construction.** There are at least 3
  blocks (above), and blocks are at most the sites apart from the one
  taxon above. For example, 1,654 of the 1,655 taxa with 3–4 sites have
  3–4 blocks. The exploratory coefficient on log(blocks) (−0.91, 95%
  interval −1.39 to −0.43; likelihood ratio 13.1, p = 0.0003) therefore
  describes this release under that construction. It is not a finding
  about spread.
- **Per learner.** Maxent and random forest have models only from 20
  sites, and boosted trees from 50, in this release. Their empty
  lower rows are the learners' own site minimums, not missing data.

## Results

Run on the Atlas box by ops, with Steve's OK, at 22:58 UTC on 2026-11-20,
in the deployed image 821d125c, with sites_spread.R at the hash above. Exit
0. Output sites-spread.json, sha256
96d76c154bf5e3c995fb91a9ac2e03fad504c23621a0c5d764b84be9120f1c13 (43,609
bytes; counts only). Every number below is copied from that file. A cell
reads strong/taxa = share (Wilson 95% interval); (g) marks a cell under
20 taxa, shown greyed in the figure; — is a cell with no taxa.

**Check.** The sites marginal reproduces Table 1c exactly
(table_1c_check.reproduced = true): 6,369 modelled taxa.

### Sites × occupied 100 km blocks (taxa; primary)

| Sites \ Blocks | 1 | 2 | 3–4 | 5–9 | 10–19 | 20+ |
|---|---|---|---|---|---|---|
| 3–4 | — | — | 34/1654 = 2.1% (1.5%–2.9%) | 0/1 = 0.0% (0.0%–79.3%) (g) | — | — |
| 5–9 | — | — | 18/460 = 3.9% (2.5%–6.1%) | 91/1510 = 6.0% (4.9%–7.3%) | — | — |
| 10–19 | — | — | 0/8 = 0.0% (0.0%–32.4%) (g) | 68/556 = 12.2% (9.8%–15.2%) | 71/840 = 8.5% (6.8%–10.5%) | — |
| 20–49 | — | — | — | 3/10 = 30.0% (10.8%–60.3%) (g) | 94/510 = 18.4% (15.3%–22.0%) | 69/492 = 14.0% (11.2%–17.4%) |
| 50–99 | — | — | — | — | 4/8 = 50.0% (21.5%–78.5%) (g) | 18/268 = 6.7% (4.3%–10.4%) |
| 100+ | — | — | — | — | — | 0/52 = 0.0% (0.0%–6.9%) |

### Marginal: by sites (the Table 1c check)

| Sites | Taxa | Strong | Share (Wilson 95%) |
|---|---|---|---|
| 3–4 | 1,655 | 34 | 2.1% (1.5%–2.9%) |
| 5–9 | 1,970 | 109 | 5.5% (4.6%–6.6%) |
| 10–19 | 1,404 | 139 | 9.9% (8.5%–11.6%) |
| 20–49 | 1,012 | 166 | 16.4% (14.2%–18.8%) |
| 50–99 | 276 | 22 | 8.0% (5.3%–11.8%) |
| 100+ | 52 | 0 | 0.0% (0.0%–6.9%) |

### Marginal: by occupied 100 km blocks

| Blocks | Taxa | Strong | Share (Wilson 95%) |
|---|---|---|---|
| 1 | 0 | 0 | — |
| 2 | 0 | 0 | — |
| 3–4 | 2,122 | 52 | 2.5% (1.9%–3.2%) |
| 5–9 | 2,077 | 162 | 7.8% (6.7%–9.0%) |
| 10–19 | 1,358 | 169 | 12.4% (10.8%–14.3%) |
| 20+ | 812 | 87 | 10.7% (8.8%–13.0%) |

### Supplement: sites × hull area (km²)

Every modelled taxon had a hull (taxa without one: 0).

| Sites \ Hull km² | under 1,000 | 1,000–9,999 | 10,000–99,999 | 100,000–999,999 | 1,000,000+ |
|---|---|---|---|---|---|
| 3–4 | 1/38 = 2.6% (0.5%–13.5%) | 8/220 = 3.6% (1.8%–7.0%) | 11/630 = 1.8% (1.0%–3.1%) | 13/606 = 2.1% (1.3%–3.6%) | 1/161 = 0.6% (0.1%–3.4%) |
| 5–9 | 0/2 = 0.0% (0.0%–65.8%) (g) | 8/68 = 11.8% (6.1%–21.5%) | 19/393 = 4.8% (3.1%–7.4%) | 72/1095 = 6.6% (5.2%–8.2%) | 10/412 = 2.4% (1.3%–4.4%) |
| 10–19 | — | 0/5 = 0.0% (0.0%–43.5%) (g) | 11/63 = 17.5% (10.0%–28.6%) | 93/714 = 13.0% (10.8%–15.7%) | 35/622 = 5.6% (4.1%–7.7%) |
| 20–49 | — | — | 4/5 = 80.0% (37.5%–96.4%) (g) | 57/277 = 20.6% (16.2%–25.7%) | 105/730 = 14.4% (12.0%–17.1%) |
| 50–99 | — | — | 1/1 = 100.0% (20.6%–100.0%) (g) | 8/19 = 42.1% (23.1%–63.7%) (g) | 13/256 = 5.1% (3.0%–8.5%) |
| 100+ | — | — | — | — | 0/52 = 0.0% (0.0%–6.9%) |

| Hull km² | Taxa | Strong | Share (Wilson 95%) |
|---|---|---|---|
| under 1,000 | 40 | 1 | 2.5% (0.4%–12.9%) |
| 1,000–9,999 | 293 | 16 | 5.5% (3.4%–8.7%) |
| 10,000–99,999 | 1,092 | 46 | 4.2% (3.2%–5.6%) |
| 100,000–999,999 | 2,711 | 243 | 9.0% (8.0%–10.1%) |
| 1,000,000+ | 2,233 | 164 | 7.3% (6.3%–8.5%) |

### Supplement: per learner (models; sites are the model's own, blocks its taxon's)

**ESM**: 6,041 models, 365 strong.

| Sites \ Blocks | 1 | 2 | 3–4 | 5–9 | 10–19 | 20+ |
|---|---|---|---|---|---|---|
| 3–4 | — | — | 34/1654 = 2.1% (1.5%–2.9%) | 0/1 = 0.0% (0.0%–79.3%) (g) | — | — |
| 5–9 | — | — | 18/460 = 3.9% (2.5%–6.1%) | 91/1510 = 6.0% (4.9%–7.3%) | — | — |
| 10–19 | — | — | 0/8 = 0.0% (0.0%–32.4%) (g) | 68/556 = 12.2% (9.8%–15.2%) | 71/840 = 8.5% (6.8%–10.5%) | — |
| 20–49 | — | — | — | 2/10 = 20.0% (5.7%–51.0%) (g) | 49/510 = 9.6% (7.3%–12.5%) | 32/492 = 6.5% (4.6%–9.0%) |
| 50–99 | — | — | — | — | — | — |
| 100+ | — | — | — | — | — | — |

**Maxent**: 1,336 models, 121 strong.

| Sites \ Blocks | 1 | 2 | 3–4 | 5–9 | 10–19 | 20+ |
|---|---|---|---|---|---|---|
| 3–4 | — | — | — | — | — | — |
| 5–9 | — | — | — | — | — | — |
| 10–19 | — | — | — | — | — | — |
| 20–49 | — | — | — | 1/6 = 16.7% (3.0%–56.4%) (g) | 58/510 = 11.4% (8.9%–14.4%) | 46/492 = 9.3% (7.1%–12.2%) |
| 50–99 | — | — | — | — | 3/8 = 37.5% (13.7%–69.4%) (g) | 13/268 = 4.9% (2.9%–8.1%) |
| 100+ | — | — | — | — | — | 0/52 = 0.0% (0.0%–6.9%) |

**Random forest**: 1,336 models, 85 strong.

| Sites \ Blocks | 1 | 2 | 3–4 | 5–9 | 10–19 | 20+ |
|---|---|---|---|---|---|---|
| 3–4 | — | — | — | — | — | — |
| 5–9 | — | — | — | — | — | — |
| 10–19 | — | — | — | — | — | — |
| 20–49 | — | — | — | 0/6 = 0.0% (0.0%–39.0%) (g) | 45/510 = 8.8% (6.7%–11.6%) | 29/492 = 5.9% (4.1%–8.3%) |
| 50–99 | — | — | — | — | 2/8 = 25.0% (7.1%–59.1%) (g) | 9/268 = 3.4% (1.8%–6.3%) |
| 100+ | — | — | — | — | — | 0/52 = 0.0% (0.0%–6.9%) |

**Boosted trees**: 328 models, 5 strong.

| Sites \ Blocks | 1 | 2 | 3–4 | 5–9 | 10–19 | 20+ |
|---|---|---|---|---|---|---|
| 3–4 | — | — | — | — | — | — |
| 5–9 | — | — | — | — | — | — |
| 10–19 | — | — | — | — | — | — |
| 20–49 | — | — | — | — | — | — |
| 50–99 | — | — | — | — | 0/8 = 0.0% (0.0%–32.4%) (g) | 5/268 = 1.9% (0.8%–4.3%) |
| 100+ | — | — | — | — | — | 0/52 = 0.0% (0.0%–6.9%) |

### Exploratory model (registered as exploratory)

strong ~ log(sites) + log(blocks), against strong ~ log(sites); taxa, binomial: 6,369 taxa, likelihood ratio 13.071 on 1 df, p = 0.0003.

| Term | Estimate | 95% interval (Wald) |
|---|---|---|
| (Intercept) | -3.7525 | -4.0315 to -3.4736 |
| log(sites) | 1.315 | 0.9017 to 1.7283 |
| log(blocks) | -0.912 | -1.3942 to -0.4297 |
