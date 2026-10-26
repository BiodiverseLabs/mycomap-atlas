# Plan: "default practice" Maxent (paper E6a)

- **Status.** Planned 2026-10-13, before code or run. Descriptive; serves C1
  and C2: what a common default workflow reports about itself, against how
  it does on later finds.
- **Reproducibility.** frozen (the hindcast pull, E2).

## Design

- **Data.** The hindcast pull (records first validated on or before
  2026-08-17), every taxon with ≥ 20 sites, so its maps can be scored on the
  E2 test places.
- **Model.** The package's own `maxnet::maxnet` with its defaults:
  `default.features` (feature classes chosen by sample size, as most users
  run it), regularisation multiplier 1, its full lambda path (not Atlas's
  20-step path),
  every production predictor, no pruning, no effort term; 10,000 background
  points: random grid cells with complete predictors inside the taxon's
  500 km accessible area (not the target-group sites). Predictors constant
  over a fit's points (detections and background, in each CV fold, the final
  fit and each null) are left out, because maxnet cannot fit them; the count
  is reported. Nothing that varies is pruned. (Added 2026-10-13, before any
  run, on the experiments lane's finding.)
- **Its own evaluation.** Random 5-fold cross-validation AUC, reported as
  the model's own score; and the null test as Raes & ter Steege (2007) run
  it: the model's TRAINING AUC (fit on all points against the background)
  against the training AUC of 19 null species of as many points as
  detections, drawn uniformly over the accessible area, all against the same
  10,000 background points; pass = p ≤ 0.05. (Settled 2026-10-13 with the
  experiments lane, before code.)
- **Scored on E2.** Its rasters, ranked over the accessible-area cells (E6a
  has no area of applicability), scored on the E2 test places with the E2
  metrics.

## Outputs

Own-CV AUC and pass rate, against its E2 scores; beside the production
models' blocked AUC, grades and E2 scores for the same taxa.

## Runs

Logged as the operations lane reports them; numbers only.

- **Default-practice fits (launched 2026-10-25 16:42 UTC).**
  study-20261025T164211Z-4ffa4776, image c56d2dc.
  - Command: `plan-study --command=study-default --shards=8
    --from-release=20261013T191324Z-fa1b4198
    --args="--release=priv-20261018T171648Z-9e3ab153 --workers=30"`, on
    r7i.8xlarge (spot).
  - 1,260 taxa with 20+ sites in the hindcast (lqh 1,173, lqph 87), about
    324 CPU-h by the code's estimate.
  - The training data is the hindcast's own pull. `--from-release` brings
    only the layers. The 9 layer files of fa1b4198's job and the hindcast's
    job are identical (path and sha256), checked before planning.
  - Steve confirmed it directly with the operations lane.
  - **Result (2026-10-25).** All 8 shards succeeded on r7i.8xlarge (Intel
    Xeon Platinum 8488C), spot. The last reported at 20:35 UTC. There were
    spot reclaims on the way (shards 1, 2 and 3 ran three attempts each, and
    shard 4 two); a reclaimed study shard starts over, so none of it is
    lost work in the results. The run gave 8 results files.
- **Scoring (launched 2026-10-25 21:17 UTC).**
  study-20261025T211731Z-017e88fa, image d2ff016, on 1 × r7i.xlarge
  (on-demand).
  - Command: E2's final study-score arguments with
    `--defaults-from=study-20261025T164211Z-4ffa4776` (Atlas
    feat/score-defaults-from 828ac6f).
  - **Result (2026-10-25).** Ran 21:19:25 to 22:11:46 UTC on r7i.xlarge
    (Intel Xeon Platinum 8488C), on-demand, about 0.87 instance-h, about
    USD 0.23.
    - E2's registered H2a–c came out exactly as in E2's own run (0.9145,
      0.1305, 0.7854), so the scorer did not change.
    - **Default practice's own test:** 1,002 of the 1,014 taxa with later
      finds passed it (12 failed).
    - **On later finds** (top half / top tenth / mean rank / beats effort
      / Boyce), counted per ranked place:

      | Maps | Taxa | Places | Top half | Top tenth | Mean rank | Beats effort | Boyce |
      |---|---|---|---|---|---|---|---|
      | Default practice, passed | 1,002 | 3,587 | 0.964 | 0.746 | 0.909 | 0.679 | 0.989 |
      | Atlas strong, same taxa | 117 | 347 | 0.920 | 0.497 | 0.821 | 0.777 | 0.903 |
      | Atlas weak, same taxa | 990 | 3,544 | 0.875 | 0.469 | 0.795 | 0.714 | 0.999 |
      | Atlas failed, same taxa | 164 | 471 | 0.838 | 0.424 | 0.764 | 0.683 | 0.986 |

    - **New places only:**

      | Maps | Top half | Beats effort |
      |---|---|---|
      | Default practice, passed | 0.951 | 0.603 |
      | Atlas strong | 0.886 | 0.724 |
      | Atlas weak | 0.843 | 0.667 |
      | Atlas failed | 0.795 | 0.621 |

    - The 12 failed default maps have 28 ranked places, too few for
      shares.
    - The full numbers, by split, are in the results file
      (study/study-20261025T211731Z-017e88fa/). Their reading is the
      paper's.
- **On the same footing (exploratory; the independent review, Steve
  approved 2026-10-25).** study-20261026T020304Z-017e88fa, image bf236cf
  (Atlas feat/e6a-paired 0cd5b81), the same arguments, on 1 × r7i.xlarge
  on-demand. Ran 02:05 to 03:20 UTC, about USD 0.33. E2's H2a–c again came
  out exactly the same.
  - **Paired by taxon.** Each default map was ranked again over its Atlas
    model's area of applicability, as E6b's kernel was. The table gives
    default minus Atlas, with 95% intervals from 10,000 resamples of taxa:

    | Atlas grade | Taxa | Places | Top half | Beats effort | Mean rank |
    |---|---|---|---|---|---|
    | strong | 114 | 347 | +0.029 [−0.009, 0.069] | −0.060 [−0.087, −0.034] | +0.071 [0.044, 0.097] |
    | weak | 975 | 3,544 | +0.087 [0.076, 0.098] | −0.037 [−0.045, −0.030] | +0.111 [0.103, 0.118] |
    | failed | 159 | 471 | +0.104 [0.070, 0.141] | −0.012 [−0.034, 0.010] | +0.124 [0.100, 0.149] |

  - **Default practice's own random-CV AUC** (999 taxa with ranked later
    finds): median 0.892 (10th to 90th percentile 0.818 to 0.950).

    | How its map did on later finds (top-half share) | Taxa | Median CV AUC |
    |---|---|---|
    | below 0.5 | 12 | 0.867 |
    | 0.5 to 0.9 | 91 | 0.878 |
    | 0.9 and up | 896 | 0.894 |

  - Exploratory and unregistered. Their reading is the paper's.

## Deviations

None yet.
