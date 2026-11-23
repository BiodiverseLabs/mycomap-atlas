# Outcome-blind digest of seed 2's logs and progress: names, times, counts and
# error text only. Every verdict, rho, AUC, p and per-species seconds is dropped
# before anything is printed.
import collections, glob, json, os, re, sys
job = sys.argv[1]; layout_tsv = sys.argv[2]
L = {}
for line in open(layout_tsv, encoding='utf-8').read().splitlines()[1:]:
    n, fam, kind, band, br, sig = line.split('\t'); L[n] = (fam, kind, band)
TAXON = re.compile(r'^(\d\d:\d\d:\d\d)  \[(\d+)/(\d+)\] (\S+) (virtual-\S+) ')
other = collections.Counter()
for f in sorted(glob.glob(os.path.join(job, 'logs', '*.log'))):
    times, statuses, lines = [], collections.Counter(), 0
    for text in open(f, encoding='utf-8', errors='replace'):
        lines += 1; text = text.rstrip('\n')
        m = TAXON.match(text)
        if m:
            times.append(m.group(1)); statuses[m.group(4)] += 1
            if m.group(4) != 'scored':
                # a failed row: keep its error text, not any arm detail
                other[(os.path.basename(f), 'FAILED ROW: ' + re.sub(r'\[[^\]]*\]', '[..]', text[m.end():])[:200])] += 1
            continue
        t = re.sub(r'^\d\d:\d\d:\d\d  ', '', text)
        t = re.sub(r'(rho|auc|p|boyce)=[-0-9.NA]+', r'\1=..', t)
        t = re.sub(r'(passed|failed|untested)', '<v>', t) if '=' in t else t
        t = re.sub(r'\d+', '#', t)
        other[(os.path.basename(f), t[:160])] += 1
    gaps = []
    secs = [int(a)*3600+int(b)*60+int(c) for a, b, c in (x.split(':') for x in times)]
    gaps = [b - a for a, b in zip(secs, secs[1:])]
    print(f'{os.path.basename(f):8s} lines {lines:5d}; taxon rows {dict(statuses)}; first {times[0] if times else "-"} last {times[-1] if times else "-"}; '
          f'longest gap between rows {max(gaps)/60 if gaps else 0:.0f} min')
print('\nnon-taxon log lines (digits as #, verdicts masked), by log:')
for (f, t), c in sorted(other.items()):
    print(f'  {f:8s} x{c:3d}  {t}')
print('\nprogress files: rows, distinct taxa, statuses; missing species by kind and band')
missing_all = collections.Counter(); seen_all = set()
for f in sorted(glob.glob(os.path.join(job, 'shards', '*.progress.json'))):
    d = json.load(open(f, encoding='utf-8'))
    rows = d.get('taxa', [])
    names = [r.get('taxon') for r in rows]; st = collections.Counter(r.get('status') for r in rows)
    shard = int(os.path.basename(f).split('.')[0])
    own = {n for i, n in enumerate(L) if i % 8 == shard - 1}
    miss = own - set(names); seen_all |= set(names)
    mc = collections.Counter(L[n][1] + ' ' + L[n][2] for n in miss); missing_all.update(mc)
    print(f'  shard {shard}: {len(rows)} rows, {len(set(names))} taxa, statuses {dict(st)}, not of this shard {len(set(names) - own)}; missing {len(miss)}: {dict(mc)}')
print(f'  all: {len(seen_all)} taxa saved; missing {sum(missing_all.values())}: {dict(missing_all)}')
