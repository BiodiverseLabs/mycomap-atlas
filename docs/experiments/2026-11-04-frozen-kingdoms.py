# Every first word in the frozen release's taxa list, asked of GBIF once: kingdom and phylum.
# Public names only; paced for GBIF. Writes genus_kingdoms.json in the scratchpad.
import glob
import json
import subprocess
import time
import urllib.parse

import sys
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


out = {}
for i, w in enumerate(words):
    a = ask(name=w)
    row = {'plain': [a.get('matchType'), a.get('kingdom'), a.get('phylum'), a.get('rank'), (a.get('note') or '')[:40]]}
    if a.get('matchType') != 'EXACT' or a.get('kingdom') != 'Fungi':
        b = ask(name=w, kingdom='Fungi', strict='true')
        row['hint'] = [b.get('matchType'), b.get('kingdom'), b.get('phylum'), b.get('rank')]
    out[w] = row
    if i % 200 == 0:
        json.dump(out, open(S + 'genus_kingdoms.json', 'w', encoding='utf-8'))
        print(i, flush=True)
json.dump(out, open(S + 'genus_kingdoms.json', 'w', encoding='utf-8'))
print('done', len(out), flush=True)
