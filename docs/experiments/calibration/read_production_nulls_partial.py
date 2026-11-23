# Read what the failed calibration run (study-20261120T165750Z-6d041658) left:
# the saved shard results (virtual-e1-production-nulls-*.json) and the worker
# log lines of the shards that were stopped ("[n/145] scored virtual-... (c
# cells, s s) arm:rho=..[shift=passed] ..."), paired with E1 by taxon and arm.
#
#   python -I read_production_nulls_partial.py <dir of saved .json and worker .log files> <e1shift.json> <dir of E1's virtual-e1-*.json>
#
# A species seen in more than one place (a shard's attempts) is counted once;
# its verdicts must agree, as each species' draws are seeded. Prints per
# learner and site band: species, false passes under E1's test and
# production's with Wilson 95% intervals, the paired changes, and the bounds
# if every unscored species had passed or failed. Then the time: CPU seconds
# in total, the slowest species, and production's seconds against E1's for
# the same species. Counts and virtual ids only.
import collections, glob, json, math, os, re, sys

def wilson(k, n, z=1.96):
    if not n: return (float('nan'), float('nan'))
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d; h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)

run_dir, e1_path, e1_dir = sys.argv[1], sys.argv[2], sys.argv[3]
e1, band_of = {}, {}
for r in json.load(open(e1_path)):
    if r['kind'] != 'geography' or not r['reps']: continue
    arm = r['arm'].split(':')[0]
    e1[(r['taxon'], arm)] = r['p'] <= 0.05 and (r['boyce'] if r['boyce'] is not None else -1) > 0
    band_of[r['taxon']] = r['band']
e1_seconds = {}
for f in glob.glob(os.path.join(e1_dir, '*virtual-e1-*.json')):
    for t in json.load(open(f, encoding='utf-8'))['taxa']:
        if t.get('kind') == 'geography' and t.get('seconds') is not None:
            e1_seconds[t['taxon']] = t['seconds']

new, seconds, cells, source = {}, {}, {}, collections.Counter()
conflicts = []
def put(taxon, arm, passed, secs, ncells, where, extended=None):
    key = (taxon, arm)
    if key in new and new[key][0] != passed: conflicts.append(key)
    if key not in new: source[where] += 1
    new[key] = (passed, extended if extended is not None else (new.get(key) or (None, None))[1])
    if secs is not None: seconds[taxon] = max(seconds.get(taxon, 0), secs)
    if ncells is not None: cells[taxon] = ncells

for f in sorted(glob.glob(os.path.join(run_dir, '*.json'))):
    d = json.load(open(f, encoding='utf-8'))
    if d.get('settings', {}).get('null_rule') != 'production': continue
    for t in d['taxa']:
        if t.get('status') != 'scored' or t['kind'] != 'geography': continue
        for a in t['arms']:
            s = (a.get('nulls') or {}).get('shift')
            if not s or 'verdict' not in s: continue
            put(t['taxon'], a['arm'].split(':')[0], s['verdict'] == 'passed', t.get('seconds'), t.get('presences'),
                'saved', bool(s.get('extended')))

line = re.compile(r'\[\d+/\d+\] scored (virtual-geography-\d+) \((\d+) cells, ([0-9.]+)s\) (.*)$')
arm_re = re.compile(r'(\S+?):rho=\S*?\[([^\]]*)\]')
for f in sorted(glob.glob(os.path.join(run_dir, '*.log')) + glob.glob(os.path.join(run_dir, '*.txt'))):
    for text in open(f, encoding='utf-8', errors='replace'):
        m = line.search(text.rstrip())
        if not m: continue
        taxon, ncells, secs, rest = m.group(1), int(m.group(2)), float(m.group(3)), m.group(4)
        for arm, verdicts in arm_re.findall(rest):
            shift = dict(v.split('=', 1) for v in verdicts.split(',') if '=' in v).get('shift')
            if shift is None or shift == 'error': continue
            put(taxon, arm.split(':')[0], shift == 'passed', secs, ncells, 'log')

print(f'{len(new)} learner-species under production\'s test ({dict(source)}); {len(e1)} under E1\'s; '
      f'{len(conflicts)} with verdicts that disagree between copies')
table = collections.defaultdict(lambda: [0] * 6)   # n, e1 pass, new pass, e1 only, new only, extended
for key, (passed, extended) in new.items():
    if key not in e1: continue
    old = e1[key]
    for x in (table[(key[1], band_of[key[0]])], table[(key[1], 'all')]):
        x[0] += 1; x[1] += old; x[2] += passed; x[3] += old and not passed; x[4] += passed and not old
        x[5] += bool(extended)
missing = collections.Counter(arm for (taxon, arm) in e1 if (taxon, arm) not in new)
print('learner band: species | E1 false pass | production false pass | passed under E1 only / production only | extended (saved shards only)')
for (arm, band), (n, a, b, eo, no, ex) in sorted(table.items()):
    lo1, hi1 = wilson(a, n); lo2, hi2 = wilson(b, n)
    print(f'{arm:7s} {band:8s} {n:5d} | {a:3d} = {100*a/n:4.1f}% ({100*lo1:.1f}-{100*hi1:.1f}) | '
          f'{b:3d} = {100*b/n:4.1f}% ({100*lo2:.1f}-{100*hi2:.1f}) | {eo} / {no} | {ex}')
print('unscored learner-species and the bounds they allow (all failed .. all passed):')
for arm, (n, a, b, *_rest) in sorted((k[0], v) for k, v in table.items() if k[1] == 'all'):
    m = missing[arm]; total = n + m
    print(f'  {arm:7s} unscored {m:4d} of {total:4d}: production false pass {100*b/total:.1f}% .. {100*(b+m)/total:.1f}%; '
          f'E1 on the same {total}: {100*sum(e1[k] for k in e1 if k[1] == arm)/total:.1f}%')

if seconds:
    s = sorted(seconds.values())
    print(f'time: {len(s)} species, {sum(s)/3600:.1f} CPU-h in total (one species, one process), '
          f'median {s[len(s)//2]:.0f} s, 90th {s[int(.9*len(s))]:.0f} s, slowest {s[-1]:.0f} s')
    print(f'  species over 1 h: {sum(x > 3600 for x in s)}; over 2 h: {sum(x > 7200 for x in s)}; over 3 h: {sum(x > 10800 for x in s)}')
    paired = [(seconds[t], e1_seconds[t]) for t in seconds if t in e1_seconds and e1_seconds[t] > 0]
    if paired:
        r = sorted(a / b for a, b in paired)
        print(f'  against E1 on the same {len(paired)} species (E1 ran more arms): {sum(a for a, _ in paired)/3600:.1f} vs '
              f'{sum(b for _, b in paired)/3600:.1f} CPU-h; ratio median {r[len(r)//2]:.1f}, 90th {r[int(.9*len(r))]:.1f}, max {r[-1]:.1f}')
    by_band = collections.defaultdict(list)
    for t, x in seconds.items(): by_band[band_of.get(t, '?')].append(x)
    for b in sorted(by_band):
        v = sorted(by_band[b])
        print(f'  band {b:8s} {len(v):4d} species: median {v[len(v)//2]:.0f} s, slowest {v[-1]:.0f} s')
