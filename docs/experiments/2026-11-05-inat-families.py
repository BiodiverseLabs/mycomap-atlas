# For first words GBIF gave no family: iNaturalist's family, order and class, as Vision's release took its families.
import glob
import json
import subprocess
import sys
import time
import urllib.parse

S = sys.argv[1].rstrip('/') + '/'
g = json.load(open(S + 'genus_families.json', encoding='utf-8'))
taxa = {}
for path in glob.glob(S + 'e16_taxa*.json'):
    j = json.load(open(path, encoding='utf-8'))
    for t in (j.get('items', []) if isinstance(j, dict) else j):
        taxa[t.get('name') or t.get('taxon') or t.get('scientific_name')] = t
words = sorted({n.split(' ')[0].capitalize() for n in taxa if n
                if not (g.get(n.split(' ')[0].capitalize()) or {}).get('family') and not n.split(' ')[0].endswith('aceae')})
print('words', len(words), flush=True)


def get(url):
    r = subprocess.run(['curl', '-s', '-m', '30', '-A', 'MycoMap Atlas (atlas.mycomap.org; info@mycomap.org)', url], capture_output=True)
    time.sleep(1.1)
    try:
        return json.loads(r.stdout.decode('utf-8'))
    except Exception:
        return {}


out = {}
for i, w in enumerate(words):
    found = None
    for t in get('https://api.inaturalist.org/v1/taxa?per_page=10&is_active=true&q=' + urllib.parse.quote(w)).get('results', []):
        if t.get('name') == w:
            found = t
            break
    row = {'found': bool(found)}
    if found:
        row['rank'] = found.get('rank')
        row['iconic'] = found.get('iconic_taxon_name')
        full = get('https://api.inaturalist.org/v1/taxa/%d' % found['id']).get('results', [])
        if full:
            for a in full[0].get('ancestors', []):
                if a.get('rank') in ('kingdom', 'phylum', 'class', 'order', 'family'):
                    row[a['rank']] = a.get('name')
    out[w] = row
    if i % 25 == 0:
        json.dump(out, open(S + 'inat_families.json', 'w', encoding='utf-8'))
        print(i, flush=True)
json.dump(out, open(S + 'inat_families.json', 'w', encoding='utf-8'))
print('done', len(out), flush=True)
