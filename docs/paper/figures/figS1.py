"""Appendix S1: Figure S1 (draft): how often a taxon's map is strong, by its detection sites
and by how many 100 km blocks those sites occupy (frozen release; descriptive).

Every number is copied from the registry, not computed here:
  docs/experiments/2026-11-20-pass-by-sites-and-spread.md, Results
  (shares and Wilson 95% intervals as the entry gives them, to 0.1%).
Writes figS1.svg (vector, for the journal) and figS1-data.md.
Run: python -I figS1.py   (no third-party packages)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

SITES = ['3–4', '5–9', '10–19', '20–49', '50–99', '100+']
BLOCKS = ['3–4', '5–9', '10–19', '20+']   # 1 and 2 blocks: drawn as one refused column
GREY_BELOW = 20

# (sites band, blocks band): (taxa, strong, share, wilson low, wilson high)
GRID = {
    ('3–4', '3–4'): (1654, 34, 0.021, 0.015, 0.029),
    ('3–4', '5–9'): (1, 0, 0.000, 0.000, 0.793),
    ('5–9', '3–4'): (460, 18, 0.039, 0.025, 0.061),
    ('5–9', '5–9'): (1510, 91, 0.060, 0.049, 0.073),
    ('10–19', '3–4'): (8, 0, 0.000, 0.000, 0.324),
    ('10–19', '5–9'): (556, 68, 0.122, 0.098, 0.152),
    ('10–19', '10–19'): (840, 71, 0.085, 0.068, 0.105),
    ('20–49', '5–9'): (10, 3, 0.300, 0.108, 0.603),
    ('20–49', '10–19'): (510, 94, 0.184, 0.153, 0.220),
    ('20–49', '20+'): (492, 69, 0.140, 0.112, 0.174),
    ('50–99', '10–19'): (8, 4, 0.500, 0.215, 0.785),
    ('50–99', '20+'): (268, 18, 0.067, 0.043, 0.104),
    ('100+', '20+'): (52, 0, 0.000, 0.000, 0.069),
}
# Marginals, with Wilson 95% intervals: (band, taxa, strong, share, low, high)
BY_SITES = [  # reproduces Table 1c
    ('3–4', 1655, 34, 0.021, 0.015, 0.029),
    ('5–9', 1970, 109, 0.055, 0.046, 0.066),
    ('10–19', 1404, 139, 0.099, 0.085, 0.116),
    ('20–49', 1012, 166, 0.164, 0.142, 0.188),
    ('50–99', 276, 22, 0.080, 0.053, 0.118),
    ('100+', 52, 0, 0.000, 0.000, 0.069),
]
BY_BLOCKS = [
    ('3–4', 2122, 52, 0.025, 0.019, 0.032),
    ('5–9', 2077, 162, 0.078, 0.067, 0.090),
    ('10–19', 1358, 169, 0.124, 0.108, 0.143),
    ('20+', 812, 87, 0.107, 0.088, 0.130),
]

INK = '#0b0b0b'
INK2 = '#52514e'
MUTED = '#8a8984'
GRID_LINE = '#e4e3df'
SURFACE = '#fcfcfb'
GREY_FILL = '#ecebe7'
DOT = '#2a78d6'
RAMP = ['#cde2fb', '#b7d3f6', '#9ec5f4', '#86b6ef', '#6da7ec', '#5598e7', '#3987e5',
        '#2a78d6', '#256abf', '#1c5cab', '#184f95', '#104281']
SHARE_MAX = 0.20
FONT = "font-family='Libre Franklin, Helvetica, Arial, sans-serif'"


def esc(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def text(x, y, s, size=12, fill=INK, anchor='start', weight='normal', extra=''):
    return (f"<text x='{x:.1f}' y='{y:.1f}' {FONT} font-size='{size}' fill='{fill}' "
            f"text-anchor='{anchor}' font-weight='{weight}' {extra}>{esc(s)}</text>")


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def ramp(v):
    t = max(0.0, min(1.0, v / SHARE_MAX)) * (len(RAMP) - 1)
    i = min(int(t), len(RAMP) - 2)
    f = t - i
    a, b = hexrgb(RAMP[i]), hexrgb(RAMP[i + 1])
    return '#' + ''.join(f'{round(a[k] + (b[k] - a[k]) * f):02x}' for k in range(3))


def luminance(h):
    def ch(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in hexrgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def heatmap(x0, y0):
    out = []
    cw, ch = 92, 52
    left, top = 64, 44
    out.append(text(x0, y0 + 14, 'a', 15, weight='bold'))
    out.append(text(x0 + 18, y0 + 14, 'Strong share by sites and occupied 100 km blocks', 13, weight='bold'))
    gx, gy = x0 + left, y0 + top
    # Bands 1 and 2 blocks: no taxon can be modelled there (refused by design).
    rw = 66
    out.append(f"<rect x='{gx + 1:.1f}' y='{gy + 1:.1f}' width='{rw - 4}' height='{ch * len(SITES) - 2}' "
               f"fill='{SURFACE}' stroke='{MUTED}' stroke-dasharray='4 3' rx='2'/>")
    mx, my = gx + (rw - 2) / 2, gy + ch * len(SITES) / 2
    out.append(text(mx - 6, my, 'Refused by design:', 11, INK2, 'middle',
                    extra=f"transform='rotate(-90 {mx - 6:.1f} {my:.1f})'"))
    out.append(text(mx + 9, my, 'a map needs 3 or more blocks', 11, INK2, 'middle',
                    extra=f"transform='rotate(-90 {mx + 9:.1f} {my:.1f})'"))
    out.append(text(mx, gy + ch * len(SITES) + 18, '1–2', 12, INK2, 'middle'))
    gx += rw
    out.append(text(gx + cw * len(BLOCKS) / 2, gy - 10, 'Occupied 100 km blocks', 12, INK2, 'middle'))
    for j, b in enumerate(BLOCKS):
        out.append(text(gx + cw * j + cw / 2, gy + ch * len(SITES) + 18, b, 12, INK2, 'middle'))
    out.append(text(x0 + 14, gy + ch * len(SITES) / 2, 'Detection sites', 12, INK2, 'middle',
                    extra=f"transform='rotate(-90 {x0 + 14:.1f} {gy + ch * len(SITES) / 2:.1f})'"))
    for i, s in enumerate(SITES):
        out.append(text(gx - rw - 8, gy + ch * i + ch / 2 + 4, s, 12, INK2, 'end'))
        for j, b in enumerate(BLOCKS):
            x, y = gx + cw * j, gy + ch * i
            cell = GRID.get((s, b))
            if cell is None:
                out.append(f"<rect x='{x + 1:.1f}' y='{y + 1:.1f}' width='{cw - 2}' height='{ch - 2}' "
                           f"fill='{SURFACE}' stroke='{GRID_LINE}' rx='2'/>")
                out.append(text(x + cw / 2, y + ch / 2 + 4, '–', 12, MUTED, 'middle'))
                continue
            n, k = cell[0], cell[1]
            if n < GREY_BELOW:
                out.append(f"<rect x='{x + 1:.1f}' y='{y + 1:.1f}' width='{cw - 2}' height='{ch - 2}' "
                           f"fill='{GREY_FILL}' stroke='{GRID_LINE}' rx='2'/>")
                out.append(text(x + cw / 2, y + ch / 2 + 4, f'{k} of {n}', 11, INK2, 'middle'))
                continue
            share = cell[2]
            fill = ramp(share)
            ink = '#ffffff' if luminance(fill) < 0.25 else INK
            ink2 = '#ffffff' if luminance(fill) < 0.25 else INK2
            out.append(f"<rect x='{x + 1:.1f}' y='{y + 1:.1f}' width='{cw - 2}' height='{ch - 2}' "
                       f"fill='{fill}' stroke='{SURFACE}' stroke-width='2' rx='2'/>")
            out.append(text(x + cw / 2, y + ch / 2 - 2, f'{100 * share:.1f}%', 13, ink, 'middle', 'bold'))
            out.append(text(x + cw / 2, y + ch / 2 + 14, f'{k} of {n:,}', 11, ink2, 'middle'))
    # colour key
    ky = gy + ch * len(SITES) + 40
    kw = cw * len(BLOCKS)
    steps = 48
    for q in range(steps):
        out.append(f"<rect x='{gx + kw * q / steps:.1f}' y='{ky:.1f}' width='{kw / steps + 0.5:.1f}' "
                   f"height='10' fill='{ramp(SHARE_MAX * (q + 0.5) / steps)}'/>")
    for v in (0, 0.05, 0.10, 0.15, 0.20):
        tx = gx + kw * v / SHARE_MAX
        out.append(text(tx, ky + 24, f'{int(100 * v)}%' + ('+' if v == SHARE_MAX else ''), 11, INK2, 'middle'))
    out.append(f"<rect x='{gx:.1f}' y='{ky + 34:.1f}' width='14' height='10' fill='{GREY_FILL}' stroke='{GRID_LINE}'/>")
    out.append(text(gx + 20, ky + 43, f'fewer than {GREY_BELOW} taxa (strong of all)', 11, INK2))
    out.append(text(gx + 220, ky + 43, '–  no taxa', 11, INK2))
    return out, ky + 50


def dots(x0, y0, w, label, title, rows, xlabel):
    out = []
    h = 210
    left, top, bottom = 50, 44, 46
    out.append(text(x0, y0 + 14, label, 15, weight='bold'))
    out.append(text(x0 + 18, y0 + 14, title, 13, weight='bold'))
    px, py = x0 + left, y0 + top
    pw, ph = w - left - 10, h - top - bottom
    ymax = 0.20
    for v in (0, 0.05, 0.10, 0.15, 0.20):
        yy = py + ph - ph * v / ymax
        out.append(f"<line x1='{px:.1f}' y1='{yy:.1f}' x2='{px + pw:.1f}' y2='{yy:.1f}' stroke='{GRID_LINE}'/>")
        out.append(text(px - 6, yy + 4, f'{int(100 * v)}%', 11, INK2, 'end'))
    step = pw / len(rows)
    for i, (band, n, k, share, lo, hi) in enumerate(rows):
        cx = px + step * i + step / 2
        y = lambda v: py + ph - ph * v / ymax
        out.append(f"<line x1='{cx:.1f}' y1='{y(lo):.1f}' x2='{cx:.1f}' y2='{y(hi):.1f}' "
                   f"stroke='{DOT}' stroke-width='2' stroke-linecap='round'/>")
        out.append(f"<circle cx='{cx:.1f}' cy='{y(share):.1f}' r='4.5' fill='{DOT}' stroke='{SURFACE}' stroke-width='2'/>")
        out.append(text(cx, py + ph + 16, band, 11, INK2, 'middle'))
        out.append(text(cx, py + ph + 30, f'n {n:,}', 10, MUTED, 'middle'))
    out.append(text(px + pw / 2, py + ph + 44, xlabel, 12, INK2, 'middle'))
    return out


def main():
    W = 1040
    parts, hb = heatmap(20, 20)
    rx = 540
    parts += dots(rx, 20, 480, 'b', 'By detection sites (Table 1c)', BY_SITES, 'Detection sites')
    parts += dots(rx, 250, 480, 'c', 'By occupied 100 km blocks', BY_BLOCKS, 'Occupied 100 km blocks')
    H = max(hb, 480) + 20
    svg = (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {W} {H}' width='{W}' height='{H}'>"
           f"<rect width='{W}' height='{H}' fill='{SURFACE}'/>" + ''.join(parts) + '</svg>\n')
    with open(os.path.join(HERE, 'figS1.svg'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(svg)
    with open(os.path.join(HERE, 'figS1-data.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('| panel | sites | blocks | taxa | strong | share | wilson_low | wilson_high |\n|---|---|---|---|---|---|---|---|\n')
        for s in SITES:
            for b in BLOCKS:
                c = GRID.get((s, b))
                if c:
                    f.write(f"| a | {s} | {b} | {c[0]} | {c[1]} | {c[2]:.3f} | {c[3]:.3f} | {c[4]:.3f} |\n")
        for r in BY_SITES:
            f.write(f"| b | {r[0]} | all | {r[1]} | {r[2]} | {r[3]:.3f} | {r[4]:.3f} | {r[5]:.3f} |\n")
        for r in BY_BLOCKS:
            f.write(f"| c | all | {r[0]} | {r[1]} | {r[2]} | {r[3]:.3f} | {r[4]:.3f} | {r[5]:.3f} |\n")
    print('ok', W, H)


main()
