# Read seed 2's check of the stricter null test for taxa with 200+ sites
# (branch feat/large-taxon-nulls), as pre-registered before the run
# (registry/2026-11-22-large-taxon-rule-seed2.md). Written before seed 2 ran.
#
#   python -I read_seed2.py <seed-2 run dir>
#
# Reads the run's saved shard results (virtual-e1-production-nulls-seed2-*.json)
# and, for a shard that left none, its worker log lines ("[n/m] scored
# virtual-... (c cells, s s) arm:rho=..[shift=passed]", in any .log or .txt
# file under the run dir). Per learner, kind
# and band: tests, passes and the rate with its Wilson 95% interval. For
# geography species a pass is a false pass; for habitat species it is power.
#
# The success test, for Maxent and for random forest alike: the Wilson 95%
# interval of the geography false-pass rate includes 5%, over every band and
# at 200+ sites. All four must hold. A learner-species left unscored is
# counted both ways (failed, passed); the test holds only if it holds both
# ways. A test the procedure leaves untested (verdict "untested": the map
# itself could not be scored), or a learner that fails to fit (the arm's
# error), is no pass; it is counted apart and left out of the rates, as in
# seed 1's read. Habitat power at 200+ sites is reported,
# with no criterion. Counts and virtual ids only.
#
# Version 2, for the addendum of 2026-11-23
# (registry/2026-11-23-large-taxon-rule-seed2-addendum.md), written before
# any seed-2 run. Everything the registered reader (read_seed2.py, sha256 LF
# f66233a4..., CRLF 2d588cf3...) prints is printed unchanged, in the same
# order. After the registered verdict it adds the amended one: a part whose
# Wilson interval lies wholly below 5% counts as conservative, not as a
# failure; one wholly above 5% still fails. Each way of counting the
# unscored, a part holds when its interval includes 5% or lies wholly below
# it; it is marked conservative when either way lies wholly below.
import collections, glob, json, math, os, re, sys


def wilson(k, n, z=1.96):
    if not n: return (float('nan'), float('nan'))
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)


def pct(k, n):
    lo, hi = wilson(k, n)
    return f'{k:3d}/{n:4d} = {100*k/n:4.1f}% ({100*lo:.1f}-{100*hi:.1f})' if n else '   -'


def holds(k, n):
    lo, hi = wilson(k, n)
    return n > 0 and lo <= 0.05 <= hi


def outcome(k, n):
    # The addendum's three outcomes for one part, one way of counting.
    if not n: return 'none'
    lo, hi = wilson(k, n)
    if hi < 0.05: return 'below'
    if lo > 0.05: return 'above'
    return 'includes'


LINE = re.compile(r'\[\d+/\d+\] scored (virtual-(geography|habitat)-\d+) \((\d+) cells, ([0-9.]+)s\) (.*)$')
ARM = re.compile(r'(\S+?):rho=\S*?\[([^\]]*)\]')
BANDS = ['3-4', '5-9', '10-19', '20-29', '30-49', '50-99', '100-199', '200+']
# Seed 2's layout (E1's, every geography species and the habitat species at
# 200+): the geography tests each part of the success test should have.
EXPECTED = {('maxnet', 'all'): 800, ('rf', 'all'): 800, ('maxnet', '200+'): 160, ('rf', '200+'): 160}


def band_from(presences, learner):
    lows = [3, 5, 10] if learner == 'esm' else [20, 30, 50, 100, 200]
    labels = BANDS[:3] if learner == 'esm' else BANDS[3:]
    found = [label for low, label in zip(lows, labels) if presences >= low]
    return found[-1] if found else '?'

run_dir = sys.argv[1]
got, info, seconds, source, conflicts, settings = {}, {}, {}, collections.Counter(), [], []
untested, procedural, left_out = collections.Counter(), set(), collections.Counter()
for f in sorted(glob.glob(os.path.join(run_dir, '**', '*.json'), recursive=True)):
    try: d = json.load(open(f, encoding='utf-8'))
    except Exception: continue
    if not isinstance(d, dict) or 'taxa' not in d: continue
    s = d.get('settings', {})
    if s.get('null_rule') != 'production': continue
    settings.append((s.get('seed'), json.dumps(s.get('large')), json.dumps(s.get('bands'))))
    for t in d['taxa']:
        info[t['taxon']] = (t.get('kind'), t.get('band'), t.get('breadth'), t.get('signal'), t.get('family'))
        if t.get('status') != 'scored': continue
        seconds[t['taxon']] = t.get('seconds') or 0
        for a in t['arms']:
            n = (a.get('nulls') or {}).get('shift')
            key = (t['taxon'], a['arm'].split(':')[0])
            if a.get('error') or (n and n.get('verdict') == 'untested'):
                untested[(key[1], t.get('kind'), 'fit error' if a.get('error') else 'untested')] += 1
                procedural.add(key)
                for b in (t.get('band'), 'all'): left_out[(key[1], t.get('kind'), b)] += 1
                continue
            if not n or n.get('verdict') not in ('passed', 'failed'): continue
            if key in got and got[key]['passed'] != (n['verdict'] == 'passed'): conflicts.append(key)
            if key not in got: source['saved'] += 1
            got[key] = dict(passed=n['verdict'] == 'passed', large=n.get('large'), extended=n.get('extended'),
                            stopped=n.get('stopped_early'), reps=n.get('reps'), presences=t.get('presences'))
for f in sorted(glob.glob(os.path.join(run_dir, '**', '*.log'), recursive=True)
                + glob.glob(os.path.join(run_dir, '**', '*.txt'), recursive=True)):
    for text in open(f, encoding='utf-8', errors='replace'):
        m = LINE.search(text.rstrip())
        if not m: continue
        taxon = m.group(1)
        for arm, verdicts in ARM.findall(m.group(5)):
            shift = dict(v.split('=', 1) for v in verdicts.split(',') if '=' in v).get('shift')
            if shift not in ('passed', 'failed'): continue
            key = (taxon, arm.split(':')[0])
            if key in got:
                if got[key]['passed'] != (shift == 'passed'): conflicts.append(key)
                continue
            source['log'] += 1
            got[key] = dict(passed=shift == 'passed', large=None, extended=None, stopped=None, reps=None,
                            presences=int(m.group(3)))
            seconds.setdefault(taxon, float(m.group(4)))

print(f'settings seen (seed, large, bands): {sorted(set(settings))}')
print(f'{len(got)} learner-species tests ({dict(source)}); {len(conflicts)} with copies that disagree; '
      f'{len(info)} species named in saved results')

# Expected learner-species, from the layout: Maxent and RF for full species,
# ESM for ESM species. A species named in no saved result is counted from the
# logs alone, so unscored counts are a floor when a shard saved nothing.
expected = set()
for taxon, (kind, band, breadth, signal, family) in info.items():
    for learner in (['esm'] if family == 'esm' else ['maxnet', 'rf']):
        expected.add((taxon, learner))
band_of = {t: v[1] for t, v in info.items()}
kind_of = {t: v[0] for t, v in info.items()}

table = collections.defaultdict(lambda: [0, 0])
for (taxon, learner), v in got.items():
    kind = kind_of.get(taxon) or taxon.split('-')[1]
    band = band_of.get(taxon) or band_from(v['presences'] or 0, learner)
    for b in (band, 'all'):
        x = table[(learner, kind, b)]; x[0] += 1; x[1] += v['passed']
unscored = collections.Counter()
for (taxon, learner) in expected - set(got) - procedural:
    unscored[(learner, kind_of[taxon], band_of[taxon])] += 1
    unscored[(learner, kind_of[taxon], 'all')] += 1

print('\nlearner kind      band     | passes (false passes for geography, power for habitat) | unscored')
order = lambda k: (k[0], k[1], BANDS.index(k[2]) if k[2] in BANDS else 99)
for key in sorted(table, key=order):
    n, k = table[key]
    print(f'{key[0]:7s} {key[1]:9s} {key[2]:8s} | {pct(k, n)} | {unscored[key]}')

print(f'\nleft untested by the procedure or failed to fit (no pass, not in the rates): {dict(untested) or "none"}')
print('\nTHE SUCCESS TEST (pre-registered): Wilson 95% interval of the geography false-pass rate includes 5%')
verdicts = []
for learner in ('maxnet', 'rf'):
    for band in ('all', '200+'):
        n, k = table[(learner, 'geography', band)]
        # Unscored: what the layout should hold, less what was scored or left
        # out by the procedure, so a shard that saved nothing is counted too.
        m = max(unscored[(learner, 'geography', band)],
                EXPECTED[(learner, band)] - n - left_out[(learner, 'geography', band)])
        low, high = holds(k, n + m), holds(k + m, n + m)
        verdicts.append(low and high)
        print(f'  {learner:7s} {band:4s}: {pct(k, n + m)} if unscored failed -> {"holds" if low else "FAILS"}; '
              f'{pct(k + m, n + m)} if unscored passed -> {"holds" if high else "FAILS"}')
print(f'  the success test {"HOLDS" if all(verdicts) else "DOES NOT HOLD"} ({sum(verdicts)} of 4 parts hold)')

print('\nTHE SUCCESS TEST AS AMENDED (addendum 2026-11-23): an interval wholly below 5% is conservative, not a failure; wholly above still fails')
amended, conservative = [], []
for learner in ('maxnet', 'rf'):
    for band in ('all', '200+'):
        n, k = table[(learner, 'geography', band)]
        m = max(unscored[(learner, 'geography', band)],
                EXPECTED[(learner, band)] - n - left_out[(learner, 'geography', band)])
        low, high = outcome(k, n + m), outcome(k + m, n + m)
        ok = low in ('includes', 'below') and high in ('includes', 'below')
        amended.append(ok)
        if ok and 'below' in (low, high): conservative.append(f'{learner} {band}')
        allowed = [j for j in range(n + m + 1) if outcome(j, n + m) in ('includes', 'below')]
        print(f'  {learner:7s} {band:4s}: if unscored failed -> {low}; if unscored passed -> {high}; '
              f'part {"holds" + (" (conservative)" if ok and "below" in (low, high) else "") if ok else "FAILS"}; '
              f'at {n + m} tests it holds for 0 to {max(allowed) if allowed else "-"} false passes')
if not all(amended):
    print(f'  the amended success test DOES NOT HOLD ({sum(amended)} of 4 parts hold)')
elif conservative:
    print(f'  the amended success test HOLDS, conservative in: {", ".join(conservative)}; '
          'offered to Steve with that stated and habitat power at 200+ beside it')
else:
    print('  the amended success test HOLDS (4 of 4 parts hold, none conservative)')
# Descriptive, no criterion: P(at least k false passes | a true 5%), and the
# most false passes the interval test allows at that many tests.
tail = lambda k, n: sum(math.comb(n, j) * 0.05 ** j * 0.95 ** (n - j) for j in range(k, n + 1))
for learner in ('maxnet', 'rf'):
    for band in ('all', '200+'):
        n, k = table[(learner, 'geography', band)]
        if not n: continue
        allowed = max((j for j in range(n + 1) if holds(j, n)), default=None)
        print(f'  {learner:7s} {band:4s}: P(>= {k} of {n} | 5%) = {tail(k, n):.3f}; the interval test allows up to {allowed}')

print('\nstricter test (large) by learner: tests, stopped, passed (saved results only)')
for learner in ('maxnet', 'rf'):
    big = [v for (t, l), v in got.items() if l == learner and v['large']]
    print(f'  {learner}: {len(big)} tests, {sum(bool(v["stopped"]) for v in big)} stopped, '
          f'{sum(v["passed"] for v in big)} passed; at 200+ sites without the flag: '
          f'{sum(1 for (t, l), v in got.items() if l == learner and v["large"] is False and (v["presences"] or 0) >= 200)}')

print('\nhabitat power at 200+ sites by breadth and signal (no criterion)')
power = collections.defaultdict(lambda: [0, 0])
for (taxon, learner), v in got.items():
    if kind_of.get(taxon) != 'habitat': continue
    _, band, breadth, signal, _ = info[taxon]
    if band != '200+': continue
    for key in ((learner, breadth, signal), (learner, 'all', 'all')):
        x = power[key]; x[0] += 1; x[1] += v['passed']
for key in sorted(power):
    n, k = power[key]
    print(f'  {key[0]:7s} {key[1]:6s} {key[2]:6s}: {pct(k, n)}')

if seconds:
    s = sorted(seconds.values())
    print(f'\ntime: {len(s)} species, {sum(s)/3600:.1f} species-hours, median {s[len(s)//2]:.0f} s, '
          f'90th {s[int(.9*len(s))]:.0f} s, slowest {s[-1]:.0f} s; over 2 h: {sum(x > 7200 for x in s)}')
