# Read the new-rule calibration (199 nulls at most, stop after 10, per-draw
# seeding, parallel nulls; study-20261121T201819Z-6d041658): its saved shard
# results (virtual-e1-production-nulls-*.json) and, for any shard that left
# no results, its worker log lines ("[n/145] scored virtual-... (c cells,
# s s) arm:rho=..[shift=passed] ..."). Each species' verdict is paired by
# taxon and learner with E1 and with the 11/20 499/25 salvage (the
# sensitivity row: 1,073 species, not a random subset).
#
#   python -I read_calibration_199.py <new run dir> <e1shift.json> <E1 virtual-e1-*.json dir> <11/20 salvage dir>
#
# Prints per learner and site band: species, false passes under E1, the new
# rule and (on the salvage's species) 499/25, with Wilson 95% intervals; the
# paired changes; how many tests went past 99 nulls; the species left
# unscored and the bounds they allow; and the time: species seconds in total
# (each species' own clock: with forked nulls a species' CPU is more than its
# seconds, so the run's real CPU is the workers' instance time), the slowest
# species and band medians. Counts and virtual ids only.
import collections, glob, json, math, os, re, sys


def wilson(k, n, z=1.96):
    if not n: return (float('nan'), float('nan'))
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)


def pct(k, n):
    lo, hi = wilson(k, n)
    return f'{k:3d} = {100*k/n:4.1f}% ({100*lo:.1f}-{100*hi:.1f})' if n else '  -'


LINE = re.compile(r'\[\d+/\d+\] scored (virtual-geography-\d+) \((\d+) cells, ([0-9.]+)s\) (.*)$')
ARM = re.compile(r'(\S+?):rho=\S*?\[([^\]]*)\]')


def read_run(run_dir, rule=None):
    """{(taxon, learner): (passed, extended or None)}, {taxon: seconds}, sources, conflicts."""
    got, seconds, source, conflicts = {}, {}, collections.Counter(), []

    def put(taxon, arm, passed, secs, where, extended=None):
        key = (taxon, arm)
        if key in got and got[key][0] != passed: conflicts.append(key)
        if key not in got: source[where] += 1
        old_ext = got[key][1] if key in got else None
        got[key] = (passed, extended if extended is not None else old_ext)
        if secs is not None: seconds[taxon] = max(seconds.get(taxon, 0), secs)

    for f in sorted(glob.glob(os.path.join(run_dir, '**', '*.json'), recursive=True)):
        try: d = json.load(open(f, encoding='utf-8'))
        except Exception: continue
        if not isinstance(d, dict) or 'taxa' not in d: continue
        if d.get('settings', {}).get('null_rule') != 'production': continue
        for t in d['taxa']:
            if t.get('status') != 'scored' or t.get('kind') != 'geography': continue
            for a in t['arms']:
                s = (a.get('nulls') or {}).get('shift')
                if not s or 'verdict' not in s: continue
                put(t['taxon'], a['arm'].split(':')[0], s['verdict'] == 'passed', t.get('seconds'), 'saved',
                    bool(s.get('extended')))
    for f in sorted(glob.glob(os.path.join(run_dir, '**', '*.log'), recursive=True)
                    + glob.glob(os.path.join(run_dir, '**', '*.txt'), recursive=True)):
        for text in open(f, encoding='utf-8', errors='replace'):
            m = LINE.search(text.rstrip())
            if not m: continue
            taxon, secs, rest = m.group(1), float(m.group(3)), m.group(4)
            for arm, verdicts in ARM.findall(rest):
                shift = dict(v.split('=', 1) for v in verdicts.split(',') if '=' in v).get('shift')
                if shift is None or shift == 'error': continue
                put(taxon, arm.split(':')[0], shift == 'passed', secs, 'log')
    return got, seconds, source, conflicts


new_dir, e1_path, e1_dir, salvage_dir = sys.argv[1:5]
e1, band_of = {}, {}
for r in json.load(open(e1_path)):
    if r['kind'] != 'geography' or not r['reps']: continue
    e1[(r['taxon'], r['arm'].split(':')[0])] = r['p'] <= 0.05 and (r['boyce'] if r['boyce'] is not None else -1) > 0
    band_of[r['taxon']] = r['band']
e1_seconds = {}
for f in glob.glob(os.path.join(e1_dir, '*virtual-e1-*.json')):
    for t in json.load(open(f, encoding='utf-8'))['taxa']:
        if t.get('kind') == 'geography' and t.get('seconds') is not None:
            e1_seconds[t['taxon']] = t['seconds']

new, seconds, source, conflicts = read_run(new_dir)
old, old_seconds, old_source, _ = read_run(salvage_dir)
print(f'new rule: {len(new)} learner-species ({dict(source)}); {len(conflicts)} with copies that disagree')
print(f'499/25 salvage: {len(old)} learner-species ({dict(old_source)}); E1: {len(e1)}')

# Rows: n, E1 pass, new pass, E1 only, new only, extended (saved only),
#       on the salvage's species: n, 499 pass, new pass, 499 only, new only.
table = collections.defaultdict(lambda: [0] * 10)
for key, (passed, extended) in new.items():
    if key not in e1: continue
    for x in (table[(key[1], band_of[key[0]])], table[(key[1], 'all')]):
        a = e1[key]
        x[0] += 1; x[1] += a; x[2] += passed; x[3] += a and not passed; x[4] += passed and not a
        x[5] += bool(extended)
        if key in old:
            b = old[key][0]
            x[6] += 1; x[7] += b; x[8] += passed; x[9] += (b and not passed) * 1
print('\nlearner band | species | E1 false pass | new-rule false pass | E1 only / new only | went past 99 (saved)')
for (arm, band), x in sorted(table.items()):
    print(f'{arm:7s} {band:8s} {x[0]:5d} | {pct(x[1], x[0])} | {pct(x[2], x[0])} | {x[3]} / {x[4]} | {x[5]}')
print('\non the salvage\'s species: learner | species | 499/25 false pass | new-rule false pass | 499 only / new only')
for (arm, band), x in sorted(table.items()):
    if band != 'all': continue
    only_new = sum(1 for k, (p, _) in new.items() if k[1] == arm and k in old and k in e1 and p and not old[k][0])
    print(f'{arm:7s} {x[6]:5d} | {pct(x[7], x[6])} | {pct(x[8], x[6])} | {x[9]} / {only_new}')

missing = collections.Counter(arm for (taxon, arm) in e1 if (taxon, arm) not in new)
print('\nunscored learner-species and the bounds they allow (all failed .. all passed):')
for arm, x in sorted((k[0], v) for k, v in table.items() if k[1] == 'all'):
    m = missing[arm]; total = x[0] + m
    e1_all = sum(e1[k] for k in e1 if k[1] == arm)
    print(f'  {arm:7s} unscored {m:4d} of {total:4d}: new-rule false pass {100*x[2]/total:.1f}% .. '
          f'{100*(x[2]+m)/total:.1f}%; E1 on all {total}: {100*e1_all/total:.1f}%')

if seconds:
    s = sorted(seconds.values())
    print(f'\ntime: {len(s)} species, {sum(s)/3600:.1f} species-hours (each species\' own clock), '
          f'median {s[len(s)//2]:.0f} s, 90th {s[int(.9*len(s))]:.0f} s, slowest {s[-1]:.0f} s')
    print(f'  species over 1 h: {sum(x > 3600 for x in s)}; over 2 h: {sum(x > 7200 for x in s)}')
    both = [t for t in seconds if t in old_seconds]
    if both:
        print(f'  on the {len(both)} species also in the salvage: {sum(seconds[t] for t in both)/3600:.1f} h '
              f'vs 499/25 {sum(old_seconds[t] for t in both)/3600:.1f} h')
    paired = [t for t in seconds if e1_seconds.get(t, 0) > 0]
    if paired:
        r = sorted(seconds[t] / e1_seconds[t] for t in paired)
        print(f'  against E1 on {len(paired)} species (E1 ran more arms): ratio median {r[len(r)//2]:.1f}, '
              f'90th {r[int(.9*len(r))]:.1f}, max {r[-1]:.1f}')
    by_band = collections.defaultdict(list)
    for t, x in seconds.items(): by_band[band_of.get(t, '?')].append(x)
    for b in sorted(by_band):
        v = sorted(by_band[b])
        print(f'  band {b:8s} {len(v):4d} species: median {v[len(v)//2]:.0f} s, slowest {v[-1]:.0f} s')
