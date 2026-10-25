"""Figure 3 (draft): how the maps ranked later finds in the hindcast (E2, E6b).

Every number is copied from the registry, not computed here:
  docs/experiments/2026-10-13-prereg-e2-hindcast.md, Results (by grade)
  docs/experiments/2026-10-13-prereg-e6b-distance-baseline.md, Results
Writes fig3.svg (vector, for the journal) and fig3-data.csv (the table view).
Run: python -I fig3.py   (no third-party packages)
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))

MAP = '#2a78d6'      # categorical slot 1 (validated with slot 2, light mode)
KERNEL = '#eb6834'   # categorical slot 2
INK = '#0b0b0b'
INK2 = '#52514e'
GRID = '#e4e3df'
SURFACE = '#fcfcfb'

# Panel a: top-half share of later finds, all places, by grade.
# (label, taxa, map share, map 95% interval or None, kernel share or None)
PANEL_A = [
    ('Strong', 214, 0.9145, (0.8856, 0.9419), 0.871),
    ('Weak', 2082, 0.8696, None, 0.8936),
    ('Failed', 528, 0.7840, None, None),
]
# Panel b: strong maps and their kernels on the same places, by distance
# from the taxon's training sites (descriptive; no intervals registered).
PANEL_B = [
    ('Known places (≤ 5 km)', 0.987, 0.952),
    ('5–25 km', 0.974, 1.000),
    ('25–100 km', 0.928, 0.928),
    ('100–500 km', 0.760, 0.611),
]

W, H = 1040, 420
FONT = "font-family='Libre Franklin, Helvetica, Arial, sans-serif'"


def esc(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def panel(x0, y0, w, h, title, rows, xmin, xmax, kind):
    out = []
    left = 170
    px0, px1 = x0 + left, x0 + w - 20
    sx = lambda v: px0 + (v - xmin) / (xmax - xmin) * (px1 - px0)
    top, bottom = y0 + 56, y0 + h - 46
    out.append(f"<text x='{x0}' y='{y0 + 18}' {FONT} font-size='15' font-weight='600' fill='{INK}'>{esc(title)}</text>")
    # grid and axis
    v = xmin
    while v <= xmax + 1e-9:
        X = sx(v)
        out.append(f"<line x1='{X:.1f}' y1='{top - 10}' x2='{X:.1f}' y2='{bottom}' stroke='{GRID}' stroke-width='1'/>")
        out.append(f"<text x='{X:.1f}' y='{bottom + 18}' {FONT} font-size='12' fill='{INK2}' text-anchor='middle'>{v:.1f}</text>")
        v += 0.1
    out.append(f"<text x='{(px0 + px1) / 2:.1f}' y='{bottom + 38}' {FONT} font-size='12' fill='{INK2}' text-anchor='middle'>Share of later finds in the map's top half</text>")
    n = len(rows)
    step = (bottom - top) / n
    for k, r in enumerate(rows):
        cy = top + step * (k + 0.5)
        if kind == 'a':
            label, taxa, m, ci, kern = r
            out.append(f"<text x='{x0}' y='{cy - 2:.1f}' {FONT} font-size='13' fill='{INK}'>{esc(label)}</text>")
            out.append(f"<text x='{x0}' y='{cy + 14:.1f}' {FONT} font-size='11' fill='{INK2}'>{taxa:,} taxa</text>")
        else:
            label, m, kern = r
            ci = None
            out.append(f"<text x='{x0}' y='{cy + 4:.1f}' {FONT} font-size='13' fill='{INK}'>{esc(label)}</text>")
        if kern is not None:
            out.append(f"<line x1='{sx(min(m, kern)):.1f}' y1='{cy:.1f}' x2='{sx(max(m, kern)):.1f}' y2='{cy:.1f}' stroke='{GRID}' stroke-width='3'/>")
        if ci:
            out.append(f"<line x1='{sx(ci[0]):.1f}' y1='{cy:.1f}' x2='{sx(ci[1]):.1f}' y2='{cy:.1f}' stroke='{MAP}' stroke-width='2'/>")
            for e in ci:
                out.append(f"<line x1='{sx(e):.1f}' y1='{cy - 5:.1f}' x2='{sx(e):.1f}' y2='{cy + 5:.1f}' stroke='{MAP}' stroke-width='2'/>")
        if kern is not None:
            X = sx(kern)
            out.append(f"<rect x='{X - 5.5:.1f}' y='{cy - 5.5:.1f}' width='11' height='11' transform='rotate(45 {X:.1f} {cy:.1f})' fill='{KERNEL}' stroke='{SURFACE}' stroke-width='2'/>")
        X = sx(m)
        if kern is not None and abs(kern - m) < 1e-9:
            out.append(f"<circle cx='{X:.1f}' cy='{cy:.1f}' r='3' fill='{MAP}'/>")
        else:
            out.append(f"<circle cx='{X:.1f}' cy='{cy:.1f}' r='6' fill='{MAP}' stroke='{SURFACE}' stroke-width='2'/>")
        # direct value labels: map above, kernel below
        tied = kern is not None and abs(kern - m) < 1e-9
        if not tied:
            out.append(f"<text x='{X:.1f}' y='{cy - 11:.1f}' {FONT} font-size='11' fill='{INK}' text-anchor='middle'>{m:.3f}</text>")
        if kern is not None and abs(kern - m) < 1e-9:
            out.append(f"<text x='{X:.1f}' y='{cy + 22:.1f}' {FONT} font-size='11' fill='{INK2}' text-anchor='middle'>both {kern:.3f}</text>")
        elif kern is not None:
            out.append(f"<text x='{sx(kern):.1f}' y='{cy + 22:.1f}' {FONT} font-size='11' fill='{INK2}' text-anchor='middle'>{kern:.3f}</text>")
    return out


def legend(x, y):
    return [
        f"<circle cx='{x + 6}' cy='{y - 4}' r='6' fill='{MAP}'/>",
        f"<text x='{x + 18}' y='{y}' {FONT} font-size='12' fill='{INK}'>Atlas map</text>",
        f"<rect x='{x + 100}' y='{y - 9.5}' width='11' height='11' transform='rotate(45 {x + 105.5} {y - 4})' fill='{KERNEL}'/>",
        f"<text x='{x + 118}' y='{y}' {FONT} font-size='12' fill='{INK}'>Distance to known sites, same places</text>",
        f"<line x1='{x + 360}' y1='{y - 4}' x2='{x + 384}' y2='{y - 4}' stroke='{MAP}' stroke-width='2'/>",
        f"<text x='{x + 390}' y='{y}' {FONT} font-size='12' fill='{INK}'>95% interval (bootstrap over taxa)</text>",
    ]


parts = [f"<svg xmlns='http://www.w3.org/2000/svg' width='100%' viewBox='0 0 {W} {H}'>",
         f"<rect width='{W}' height='{H}' fill='{SURFACE}'/>"]
parts += panel(20, 30, 500, 340, 'a  By grade, all places', PANEL_A, 0.5, 1.0, 'a')
parts += panel(540, 30, 500, 340, 'b  Strong maps, by distance (descriptive)', PANEL_B, 0.5, 1.0, 'b')
parts += legend(20, H - 12)
parts.append('</svg>')
open(os.path.join(HERE, 'fig3.svg'), 'w', encoding='utf-8').write('\n'.join(parts))

with open(os.path.join(HERE, 'fig3-data.csv'), 'w', newline='', encoding='utf-8') as f:
    wr = csv.writer(f)
    wr.writerow(['panel', 'row', 'taxa', 'map_top_half', 'map_ci_low', 'map_ci_high', 'kernel_top_half', 'source'])
    for label, taxa, m, ci, kern in PANEL_A:
        wr.writerow(['a', label, taxa, m, ci[0] if ci else '', ci[1] if ci else '', '' if kern is None else kern,
                     'E2 Results by grade; E6b Results (strong and weak vs kernel)'])
    for label, m, kern in PANEL_B:
        wr.writerow(['b', label, '', m, '', '', kern, 'E6b Results, strong models and their kernels by band'])
print('wrote fig3.svg, fig3-data.csv')
