# Every first word in the frozen release's taxa list: GBIF's phylum, class, order and family, under a Fungi hint.
# Public names only; paced. Writes genus_families.json in the scratchpad.
import glob
import json
import subprocess
import sys
import time
import urllib.parse

S = sys.argv[1].rstrip('/') + '/'
taxa = {}
for path in glob.glob(S + 'e16_taxa*.json'):
    j = json.load(open(path, encoding='utf-8'))
    for t in (j.get('items', []) if isinstance(j, dict) else j):
        taxa[t.get('name') or t.get('taxon') or t.get('scientific_name')] = t
words = sorted({n.split(' ')[0].capitalize() for n in taxa if n})
print('words', len(words), flush=True)


def ask(**q):
    r = subprocess.run(['curl', '-s', '-m', '20', '-A', 'MycoMap Atlas (atlas.mycomap.org; info@mycomap.org)',
                        'https://api.gbif.org/v1/species/match?' + urllib.parse.urlencode(q)], capture_output=True)
    time.sleep(0.25)
    try:
        return json.loads(r.stdout.decode('utf-8'))
    except Exception:
        return {}


keep = ('matchType', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'rank', 'canonicalName', 'status')
out = {}
for i, w in enumerate(words):
    a = ask(name=w, rank='GENUS', kingdom='Fungi', strict='true')
    if a.get('matchType') != 'EXACT':
        b = ask(name=w, kingdom='Fungi', strict='true')
        if b.get('matchType') == 'EXACT':
            a = b
    out[w] = {k: a.get(k) for k in keep}
    if i % 200 == 0:
        json.dump(out, open(S + 'genus_families.json', 'w', encoding='utf-8'))
        print(i, flush=True)
json.dump(out, open(S + 'genus_families.json', 'w', encoding='utf-8'))
print('done', len(out), flush=True)
