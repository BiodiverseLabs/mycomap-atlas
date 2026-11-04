"""E1c's estimate, as fixed in 2026-10-13-plan-e1c-standard-test-real-models.md.

Among the frozen release's models that pass the standard test, the share not
graded strong, weighted back to the release's composition by stratum
(learner x site band x grade), with a 95% interval from 10,000 bootstrap
resamples within strata (seed 1). Also by learner and by site band, and the
reverse share (strong models that fail the standard test).

Reads the two results files of study-20261025T160517Z-0c069800 (no coordinates
or record ids in them). Standard library only.

    python -I 2026-11-04-e1c-reading.py <dir holding the two rescan-*.json>
"""
import collections
import glob
import json
import os
import random
import sys

REPS = 10000
SEED = 1


def load(folder):
    rows, population = [], None
    for path in sorted(glob.glob(os.path.join(folder, 'rescan-*.json'))):
        d = json.load(open(path, encoding='utf-8'))
        population = d['strata']['population']
        sampled = d['strata']['sampled']
        rows += d['taxa']
    return rows, population, sampled


def estimate(pass_rate, population, keep=lambda s: True):
    """Weighted share of passing models that are not strong, over kept strata."""
    passing = not_strong = 0.0
    for stratum, n in population.items():
        if not keep(stratum):
            continue
        estimated = n * pass_rate.get(stratum, 0.0)
        passing += estimated
        if not stratum.endswith('/ strong'):
            not_strong += estimated
    return not_strong / passing if passing else float('nan')


def reverse(pass_rate, population, keep=lambda s: True):
    """Weighted share of strong models that fail the standard test."""
    total = failed = 0.0
    for stratum, n in population.items():
        if stratum.endswith('/ strong') and keep(stratum):
            total += n
            failed += n * (1 - pass_rate.get(stratum, 0.0))
    return failed / total if total else float('nan')


def passing_share(pass_rate, population, keep=lambda s: True):
    """Weighted share of all models that pass the standard test."""
    total = passed = 0.0
    for stratum, n in population.items():
        if keep(stratum):
            total += n
            passed += n * pass_rate.get(stratum, 0.0)
    return passed / total if total else float('nan')


def main(folder):
    rows, population, sampled = load(folder)
    by_stratum = collections.defaultdict(list)
    disagree = 0
    for r in rows:
        s = r['scatter']
        passed = s['verdict'] == 'passed'
        rule = s['auc_p'] <= 0.05 and s['boyce'] is not None and s['boyce'] > 0
        if passed != rule:
            disagree += 1
        by_stratum[f"{r['algorithm']} / {r['band']} / {r['grade']}"].append(1 if passed else 0)

    # Checks: the files' own strata, and the verdict against the plan's rule.
    counted = {k: len(v) for k, v in by_stratum.items()}
    assert counted == sampled, 'rows do not match the sampled strata'
    assert set(counted) <= set(population), 'a sampled stratum is not in the population'
    out = {'models': len(rows), 'population': sum(population.values()),
           'strata': len(population), 'strata_sampled': len(counted),
           'census_strata': sum(1 for k in counted if counted[k] == population[k]),
           'verdict_disagrees_with_rule': disagree}

    rate = {k: sum(v) / len(v) for k, v in by_stratum.items()}
    splits = {'all': lambda s: True}
    for algo in ('esm', 'maxnet', 'rf', 'xgboost'):
        splits[algo] = lambda s, a=algo: s.startswith(a + ' /')
    for band in ('3-4', '5-19', '20-49', '50-99', '100+'):
        splits[band] = lambda s, b=band: s.split(' / ')[1] == b

    rng = random.Random(SEED)
    boots = {k: [] for k in splits}
    boots_rev = {k: [] for k in splits}
    boots_pass = []
    keys = sorted(by_stratum)
    for _ in range(REPS):
        r = {}
        for k in keys:
            v = by_stratum[k]
            r[k] = sum(rng.choices(v, k=len(v))) / len(v)
        for name, keep in splits.items():
            boots[name].append(estimate(r, population, keep))
            boots_rev[name].append(reverse(r, population, keep))
        boots_pass.append(passing_share(r, population))

    def ci(values):
        v = sorted(x for x in values if x == x)
        if not v:
            return [None, None]
        return [round(v[int(0.025 * len(v))], 4), round(v[min(len(v) - 1, int(0.975 * len(v)))], 4)]

    out['share_passing_not_strong'] = {
        k: {'estimate': round(estimate(rate, population, keep), 4), 'ci95': ci(boots[k])}
        for k, keep in splits.items()}
    out['share_strong_failing'] = {
        k: {'estimate': round(reverse(rate, population, keep), 4), 'ci95': ci(boots_rev[k])}
        for k, keep in splits.items()}
    out['share_of_all_models_passing'] = {
        'estimate': round(passing_share(rate, population), 4), 'ci95': ci(boots_pass)}
    print(json.dumps(out, indent=1))  # NaN: no strong models in that split (100+)


if __name__ == '__main__':
    main(sys.argv[1])
