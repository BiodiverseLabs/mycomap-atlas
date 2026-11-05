"""The frozen release's share that is not macrofungi, by the families Vision used.

Each taxon takes the family of its first word: GBIF's backbone, asked with a Fungi hint
(genus_families.json); where GBIF gave none, iNaturalist's taxonomy, which is where Vision's release
took its families (inat_families.json). Groups are Vision's:
slime moulds and lichens from its pinned definition (truth-taxa-out-of-scope-v1.json), microfungi
from its scope_taxa.py. Names, records, models and strong taxa only.

    python -I 2026-11-05-frozen-macrofungi-scope.py <dir with e16_taxa*.json, e16_models.json, genus_families.json, inat_families.json> <vision definition json>
"""
import collections
import glob
import json
import sys

D = sys.argv[1].rstrip('/') + '/'
definition = json.load(open(sys.argv[2], encoding='utf-8'))
SLIME = set(definition['out_families']['slime_moulds'])
LICHEN = set(definition['out_families']['lichens'])
MIXED = {k: set(v['lichenized_genera']) for k, v in definition['mixed_families'].items() if not k.startswith('_')}
MICRO = {"Pucciniaceae", "Melampsoraceae", "Phragmidiaceae", "Coleosporiaceae", "Gymnosporangiaceae", "Pucciniastraceae",
         "Ustilaginaceae", "Erysiphaceae", "Rhytismataceae", "Venturiaceae", "Capnodiaceae", "Mycosphaerellaceae",
         "Exobasidiaceae", "Microbotryaceae", "Urocystidaceae", "Tilletiaceae", "Taphrinaceae", "Aspergillaceae",
         "Trichocomaceae", "Mucoraceae", "Pilobolaceae", "Saccharomycetaceae", "Entomophthoraceae"}
HYPOCREALES = {"Hypocreaceae", "Cordycipitaceae", "Ophiocordycipitaceae", "Clavicipitaceae", "Nectriaceae"}
BASIDIOLICHENS = {"Lichenomphalia", "Multiclavula", "Lepidostroma", "Dictyonema", "Cora"}

taxa = {}
for path in glob.glob(D + 'e16_taxa*.json'):
    j = json.load(open(path, encoding='utf-8'))
    for t in (j.get('items', []) if isinstance(j, dict) else j):
        taxa[t.get('name') or t.get('taxon') or t.get('scientific_name')] = t
models = collections.defaultdict(list)
for m in json.load(open(D + 'e16_models.json', encoding='utf-8'))['models']:
    models[m['taxon']].append(m.get('grade'))
g = json.load(open(D + 'genus_families.json', encoding='utf-8'))
inat = json.load(open(D + 'inat_families.json', encoding='utf-8'))
for word, row in inat.items():
    if row.get('family') or row.get('order') or row.get('phylum'):
        g[word] = dict(g.get(word) or {}, family=row.get('family'), order=row.get('order'), phylum=row.get('phylum'),
                       kingdom=row.get('kingdom'), from_inat=True, **{'class': row.get('class')})


def group(name):
    word = name.split(' ')[0].capitalize()
    r = g.get(word) or {}
    family = r.get('family')
    if word.endswith('aceae'):
        family = word
    if r.get('phylum') == 'Mycetozoa' or family in SLIME or word == 'Reticularia':
        return 'slime moulds'
    if word in BASIDIOLICHENS:
        return 'basidiolichens (kept in scope, as Vision)'
    if family in LICHEN or (family in MIXED and word in MIXED[family]):
        return 'lichens'
    if family in MICRO:
        return 'microfungi'
    if family in HYPOCREALES:
        return 'parasitic Hypocreales (counted as macrofungi)'
    if not family:
        return 'no family'
    return 'rest'


rows = collections.defaultdict(list)
for n in taxa:
    rows[group(n)].append(n)
total = sum(t.get('records', 0) for t in taxa.values())
print('taxa', len(taxa), 'records', total, 'models', sum(len(v) for v in models.values()), 'strong taxa',
      sum('strong' in v for v in models.values()))
for k, v in sorted(rows.items(), key=lambda kv: -len(kv[1])):
    rec = sum(taxa[n].get('records', 0) for n in v)
    print(f"{k}: names {len(v)} ({100 * len(v) / len(taxa):.2f}%), records {rec} ({100 * rec / total:.2f}%), modelled taxa {sum(n in models for n in v)}, "
          f"models {sum(len(models[n]) for n in v if n in models)}, by grade {dict(collections.Counter(x for n in v if n in models for x in models[n]))}, "
          f"strong taxa {sum('strong' in models.get(n, []) for n in v)}")
for k in ('slime moulds', 'lichens', 'microfungi', 'basidiolichens (kept in scope, as Vision)'):
    print(k, 'strong:', sorted(n for n in rows[k] if 'strong' in models.get(n, [])))
    print(k, 'families:', collections.Counter((g.get(n.split(' ')[0].capitalize()) or {}).get('family') for n in rows[k]).most_common(14))
print('no family, strong:', sorted(n for n in rows['no family'] if 'strong' in models.get(n, [])))
print('no family, by first word:', collections.Counter(n.split(' ')[0] for n in rows['no family']).most_common(40))
print('family from iNaturalist: first words', sum(1 for v in g.values() if v.get('from_inat')), 'none found', sum(1 for v in inat.values() if not v.get('found')))
print('not fungi by iNaturalist:', sorted({(w, v.get('kingdom')) for w, v in inat.items() if v.get('kingdom') not in (None, 'Fungi', 'Protozoa')}))
# What the family lists leave out: names in the rest, in classes and orders that mostly are not macrofungi.
orders = collections.Counter()
order_rec = collections.Counter()
order_strong = collections.Counter()
classes = collections.Counter()
for n in rows['rest']:
    r = g.get(n.split(' ')[0].capitalize()) or {}
    orders[r.get('order')] += 1
    order_rec[r.get('order')] += taxa[n].get('records', 0)
    order_strong[r.get('order')] += 'strong' in models.get(n, [])
    classes[r.get('class')] += 1
print('rest, by class:', classes.most_common(16))
print('rest, by order:', [(o, c, order_rec[o], order_strong[o]) for o, c in orders.most_common(45)])
