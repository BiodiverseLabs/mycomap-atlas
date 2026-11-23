# The seed-1 figures behind the count of the stricter test for taxa with 200+
# sites (feat/large-taxon-nulls): for each count in the grid {1, 2, 3} of 199,
# the false-pass rate the 11/21 calibration run implies for Maxent and random
# forest at 200+ sites, and overall with the rule below 200 unchanged.
#
#   python -I grid_large_rule.py <11/21 run dir>
#
# From each saved shift test: k, the nulls at least as good as the map, and
# how many were scored. A test that stopped at its first stage (5 of at most
# 99) or at 10 when extended fails under every count in the grid. An
# extended test that did not stop scored 199 nulls, so its k is known. A
# clear pass at 99 (k = 0 or 1, not extended) has unknown k over nulls 100 to
# 199: the bounds count it as failing (low) or passing (high), and the
# estimate weighs it by the beta-binomial chance that the next 100 nulls add
# at most count - k as good (uniform prior on the map's null exceedance
# probability). A pass also needs the learner's Boyce above 0, as production
# grades. Counts and virtual ids only.
import collections, glob, json, math, os, sys


def betabinom_pmf(j, n, a, b):
    lb = lambda x, y: math.lgamma(x) + math.lgamma(y) - math.lgamma(x + y)
    return math.exp(math.lgamma(n + 1) - math.lgamma(j + 1) - math.lgamma(n - j + 1)
                    + lb(j + a, n - j + b) - lb(a, b))


def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return c - h, c + h


run_dir = sys.argv[1]
tests = {}
for f in sorted(glob.glob(os.path.join(run_dir, '**', '*.json'), recursive=True)):
    try: d = json.load(open(f, encoding='utf-8'))
    except Exception: continue
    if not isinstance(d, dict) or d.get('settings', {}).get('null_rule') != 'production': continue
    for t in d['taxa']:
        if t.get('status') != 'scored' or t.get('kind') != 'geography': continue
        for a in t['arms']:
            learner = a['arm'].split(':')[0]
            s = (a.get('nulls') or {}).get('shift')
            if learner not in ('maxnet', 'rf') or not s or s.get('verdict') not in ('passed', 'failed'): continue
            if s['stopped_early']:
                k = None  # stopped: fails under every count in the grid
            else:
                k = round(s['p'] * (s['reps'] + 1)) - 1
            tests[(t['taxon'], learner)] = dict(big=t['presences'] >= 200, k=k, reps=s['reps'],
                                                extended=bool(s.get('extended')),
                                                boyce_ok=(a.get('boyce') or -1) > 0,
                                                passed=s['verdict'] == 'passed')
print(f'{len(tests)} learner-species tests read')
for learner in ('maxnet', 'rf'):
    rows = [v for (t, l), v in tests.items() if l == learner]
    big = [v for v in rows if v['big']]
    below_pass = sum(v['passed'] for v in rows if not v['big'])
    print(f'\n{learner}: {len(big)} at 200+ (candidate rule passes {sum(v["passed"] for v in big)}), '
          f'{len(rows) - len(big)} below (passes {below_pass}, unchanged)')
    for kmax in (1, 2, 3):
        sure = unsure = 0; est = 0.0
        for v in big:
            if v['k'] is None or not v['boyce_ok']: continue
            if v['extended'] or v['reps'] >= 199:
                if v['reps'] >= 199 and v['k'] <= kmax: sure += 1; est += 1
            elif v['k'] <= kmax:
                unsure += 1
                a, b = v['k'] + 1, v['reps'] - v['k'] + 1
                est += sum(betabinom_pmf(j, 199 - v['reps'], a, b) for j in range(kmax - v['k'] + 1))
        n = len(big); lo, hi = sure, sure + unsure
        overall_n = len(rows)
        print(f'  count {kmax} (p <= {(kmax + 1) / 200:.3f}): 200+ {100*lo/n:.1f}-{100*hi/n:.1f}%, '
              f'estimate {100*est/n:.1f}% ({sure} sure, {unsure} uncertain); overall '
              f'{100*(below_pass+lo)/overall_n:.1f}-{100*(below_pass+hi)/overall_n:.1f}%, '
              f'estimate {100*(below_pass+est)/overall_n:.1f}%')
