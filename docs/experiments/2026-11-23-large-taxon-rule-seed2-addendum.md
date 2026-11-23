# Addendum to the seed-2 pre-registration of the stricter null test for maps with 200+ sites

Written on 2026-11-23 by the method lane, before any seed-2 run, with
Steve's approval ("Amend, then run", 2026-11-23). It amends
docs/experiments/2026-11-22-large-taxon-rule-seed2.md (registry entry sha256
LF 0971ad50e4e6500c8d7c66cd080a1d92a82cb9bac07f1ec8058d67fb6bccc311, CRLF
2ef1f6e1865b660afba67ffa6cb1c8e454d6dcdf94406ae4844321ecba13b443, committed
at 392e26b4). That entry is left as it was. Counts only.

## Why

As registered, each of the four parts holds only when its Wilson 95%
interval includes 5%. An interval can miss 5% from below as well as from
above. With about 160 tests at 200+ sites, a part holds for 3 to 13 false
passes. At 2 or fewer (2 of 160 gives 0.3% to 4.4%) it would fail, so a rule
whose size came out below 5% would count as a failure and not go to
production. The test is meant to catch a rule that is too loose. A rule that
is too strict is a cost in power, not a failure of size.

How often this would bite, at 160 tests per learner at 200+ sites:

| True false-pass rate | Chance of 2 or fewer, per learner |
|---|---|
| 3% | 14% |
| 4% | 4% |
| 4.5% (seed 1's estimate for random forest) | 2% |
| 5.9% (seed 1's estimate for Maxent) | 0.4% |

Maxent and random forest are fitted on the same species, so their chances
are not independent. Over all bands, about 800 tests, a part fails below 28
false passes (3.5%).

## The change

- A part whose Wilson interval lies wholly below 5% counts as
  **conservative**, not as a failure.
- A part whose interval lies wholly above 5% still fails.
- The rule for unscored learner-species stays: they are counted both ways.
  Each way, a part holds when its interval includes 5% or lies wholly below
  it. It is marked conservative when either way lies wholly below. The test
  holds only when all four parts hold.
- If the test holds with any part conservative, the rule is offered to Steve
  with that stated, and with habitat power at 200+ sites beside it. Adopting
  it remains his decision.

## Nothing else changes

- The species: 1,160 geography and 240 habitat species at 200+ sites.
- The seed: 2.
- The code: feat/large-taxon-nulls d04c60a7aa2772ad98354a69f8bb9c2526e92b60.
- The command: `study-calibration --seed=2 --workers=30 --null-rule=production
  --designs=shift --effort-arms=none --bands=habitat:200+`.
- The cap: MAX_HOURS 5, $40.
- If the amended test does not hold, the registered entry's "If the test
  does not hold" applies unchanged.

## The reader

The amended verdict is read by calibration/read_seed2_v2.py, sha256
78d2356cba96c9c667604226e53104dace75039c7cd03f453a680d7f7700d772 (LF). It
prints everything the registered reader prints, unchanged and in the same
order, then adds the amended verdict.

The registered reader stays on record: calibration/read_seed2.py, sha256 LF
f66233a4d52473dd8735bf32d0e4aea1b4934fae67518ffc8cb6404bdedb8e16, CRLF
2d588cf3e51efc32c183355d7c852ab557ccd4b8da2c7f106d7c8b22abf63b88.

The new reader was checked on seed 1's two runs (run-20261120, run-20261121).
On each, its output matches the registered reader's line for line, followed
by the added verdict. Each outcome was also checked on its own at 160
tests: 0 to 2 false passes are conservative, 3 to 13 include 5%, and 14 is
above.
