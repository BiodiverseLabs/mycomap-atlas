"""Figure 2 (draft): the null tests on simulated species (E1).

Every number is copied from the registry, not computed here:
  docs/experiments/2026-10-13-prereg-e1-null-calibration.md, Result (2026-10-29)
Writes fig2.svg (vector) and fig2-data.md (the table view).
Run: python -I fig2.py   (no third-party packages)
"""
import os


class Table:
    """The table view as a Markdown table (the repo's data check refuses .csv)."""

    def __init__(self, f):
        self.f, self.first = f, True

    def writerow(self, row):
        self.f.write('| ' + ' | '.join(str(c) for c in row) + ' |\n')
        if self.first:
            self.f.write('|' + '---|' * len(row) + '\n')
            self.first = False


HERE = os.path.dirname(os.path.abspath(__file__))

SHIFT = '#2a78d6'    # categorical slot 1 (validated with slot 2, light mode)
SCATTER = '#eb6834'  # categorical slot 2
INK = '#0b0b0b'
INK2 = '#52514e'
GRID = '#e4e3df'
SURFACE = '#fcfcfb'
FONT = "font-family='Libre Franklin, Helvetica, Arial, sans-serif'"

BANDS = ['20–29', '30–49', '50–99', '100–199', '200+']
# False pass on geography species, % (shift with Wilson 95% intervals).
SHIFT_FP = {
    'Maxent': [(3.8, 1.7, 7.9), (4.4, 2.1, 8.8), (5.6, 3.0, 10.3), (4.4, 2.1, 8.8), (10.7, 6.8, 16.5)],
    'Random forest': [(2.5, 1.0, 6.3), (5.6, 3.0, 10.3), (5.6, 3.0, 10.3), (4.4, 2.1, 8.8), (6.3, 3.4, 11.1)],
}
SCATTER_FP = {
    'Maxent': [28.8, 63.1, 87.5, 96.9, 99.4],
    'Random forest': [49.4, 70.6, 91.9, 96.9, 100.0],
}
# Shift power on strong-signal habitat species, %. Weak signal is 0 everywhere.
POWER = {
    'Maxent': [11.7, 15.0, 25.8, 24.2, 28.0],
    'Random forest': [10.0, 8.3, 15.0, 14.2, 18.3],
}
# Median map-to-truth rho: passed the shift null, the rest, difference interval.
RHO = [('Maxent', 0.901, 0.606, '0.295 (0.264–0.318)'),
       ('Random forest', 0.761, 0.639, '0.123 (0.088–0.153)')]
OFFSET = {'Maxent': -5, 'Random forest': 5}


def esc(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def text(x, y, t, size=12, fill=INK2, anchor='start', weight=None):
    w = f" font-weight='{weight}'" if weight else ''
    return f"<text x='{x:.1f}' y='{y:.1f}' {FONT} font-size='{size}' fill='{fill}' text-anchor='{anchor}'{w}>{esc(t)}</text>"


def marker(x, y, learner, colour):
    if learner == 'Maxent':
        return f"<circle cx='{x:.1f}' cy='{y:.1f}' r='5' fill='{colour}' stroke='{SURFACE}' stroke-width='1.5'/>"
    return f"<rect x='{x - 4.5:.1f}' y='{y - 4.5:.1f}' width='9' height='9' transform='rotate(45 {x:.1f} {y:.1f})' fill='{colour}' stroke='{SURFACE}' stroke-width='1.5'/>"


class Axes:
    def __init__(self, x, y, w, h, ymax, step, title, ylabel, cats=BANDS):
        self.x0, self.x1 = x + 52, x + w - 12
        self.y0, self.y1 = y + h - 40, y + 34
        self.ymax, self.cats = ymax, cats
        self.out = [text(x, y + 14, title, 14, INK, weight='600')]
        v = 0
        while v <= ymax + 1e-9:
            Y = self.sy(v)
            self.out.append(f"<line x1='{self.x0}' y1='{Y:.1f}' x2='{self.x1}' y2='{Y:.1f}' stroke='{GRID}'/>")
            self.out.append(text(self.x0 - 6, Y + 4, f"{v:g}%", 11, INK2, 'end'))
            v += step
        for i, c in enumerate(cats):
            self.out.append(text(self.sx(i), self.y0 + 17, c, 11, INK2, 'middle'))
        self.out.append(text((self.x0 + self.x1) / 2, self.y0 + 33, ylabel, 11, INK2, 'middle'))

    def sx(self, i):
        n = len(self.cats)
        return self.x0 + (i + 0.5) * (self.x1 - self.x0) / n

    def sy(self, v):
        return self.y0 - v / self.ymax * (self.y0 - self.y1)

    def series(self, values, learner, colour, dash=None):
        pts = [(self.sx(i) + OFFSET[learner], self.sy(v)) for i, v in enumerate(values)]
        d = ' '.join(f"{x:.1f},{y:.1f}" for x, y in pts)
        da = f" stroke-dasharray='{dash}'" if dash else ''
        self.out.append(f"<polyline points='{d}' fill='none' stroke='{colour}' stroke-width='2'{da}/>")
        for x, y in pts:
            self.out.append(marker(x, y, learner, colour))


W, H = 1040, 640
parts = [f"<svg xmlns='http://www.w3.org/2000/svg' width='100%' viewBox='0 0 {W} {H}'>",
         f"<rect width='{W}' height='{H}' fill='{SURFACE}'/>"]

# a: scatter and shift on one scale
a = Axes(20, 16, 490, 290, 100, 20, 'a  False passes: species with no habitat', 'Detection sites')
for learner, dash in (('Maxent', None), ('Random forest', '5 3')):
    a.series(SCATTER_FP[learner], learner, SCATTER, dash)
    a.series([v[0] for v in SHIFT_FP[learner]], learner, SHIFT, dash)
a.out.append(text(a.sx(0) - 26, a.sy(70), 'Scattered nulls', 12, INK))
a.out.append(text(a.sx(2), a.sy(14), 'Shifted nulls', 12, INK, 'middle'))
parts += a.out

# b: shift alone, with intervals and the registered 5% line
b = Axes(530, 16, 490, 290, 20, 5, 'b  Shifted nulls, close up (dotted: the registered 5% bar)', 'Detection sites')
Y5 = b.sy(5)
b.out.append(f"<line x1='{b.x0}' y1='{Y5:.1f}' x2='{b.x1}' y2='{Y5:.1f}' stroke='{INK}' stroke-width='1.5' stroke-dasharray='2 3'/>")
for learner, dash in (('Maxent', None), ('Random forest', '5 3')):
    for i, (m, lo, hi) in enumerate(SHIFT_FP[learner]):
        x = b.sx(i) + OFFSET[learner] * 1.6
        b.out.append(f"<line x1='{x:.1f}' y1='{b.sy(lo):.1f}' x2='{x:.1f}' y2='{b.sy(hi):.1f}' stroke='{SHIFT}' stroke-width='2'/>")
        b.out.append(marker(x, b.sy(m), learner, SHIFT))
b.out.append(text(b.sx(4) - 16, b.sy(10.7) + 4, '10.7%', 11, INK, 'end'))
parts += b.out

# c: power
c = Axes(20, 326, 490, 270, 40, 10, 'c  Shifted nulls: habitat species caught', 'Detection sites')
for learner, dash in (('Maxent', None), ('Random forest', '5 3')):
    c.series(POWER[learner], learner, SHIFT, dash)
c.out.append(text(c.sx(2), c.sy(33), 'Strong habitat signal', 12, INK, 'middle'))
c.out.append(f"<line x1='{c.x0}' y1='{c.sy(0):.1f}' x2='{c.x1}' y2='{c.sy(0):.1f}' stroke='{INK2}' stroke-width='2'/>")
c.out.append(text(c.sx(2), c.sy(0) - 6, 'Weak signal: none passed in any band (0 of 1,199)', 11, INK, 'middle'))
parts += c.out

# d: map-to-truth rho
x0, x1, top = 530 + 120, 1020 - 30, 326 + 60
sx = lambda v: x0 + (v - 0.5) / 0.5 * (x1 - x0)
parts.append(text(530, 326 + 14, 'd  Passing picks out maps closer to the truth', 14, INK, weight='600'))
for v in (0.5, 0.6, 0.7, 0.8, 0.9, 1.0):
    parts.append(f"<line x1='{sx(v):.1f}' y1='{top - 14}' x2='{sx(v):.1f}' y2='{top + 150}' stroke='{GRID}'/>")
    parts.append(text(sx(v), top + 167, f"{v:.1f}", 11, INK2, 'middle'))
parts.append(text((x0 + x1) / 2, top + 183, 'Median map-to-truth Spearman ρ', 11, INK2, 'middle'))
for k, (learner, passed, rest, diff) in enumerate(RHO):
    y = top + 34 + k * 74
    parts.append(text(530, y + 4, learner, 12, INK))
    parts.append(f"<line x1='{sx(rest):.1f}' y1='{y}' x2='{sx(passed):.1f}' y2='{y}' stroke='{GRID}' stroke-width='3'/>")
    parts.append(f"<circle cx='{sx(rest):.1f}' cy='{y}' r='5' fill='{SURFACE}' stroke='{INK2}' stroke-width='2'/>")
    parts.append(marker(sx(passed), y, learner, SHIFT))
    parts.append(text(sx(rest), y - 11, f"{rest:.3f} the rest", 11, INK2, 'middle'))
    parts.append(text(sx(passed), y - 11, f"{passed:.3f} passed", 11, INK, 'middle'))
    parts.append(text((sx(rest) + sx(passed)) / 2, y + 21, f"difference {diff}", 11, INK2, 'middle'))

# legend
y = H - 14
parts += [marker(26, y - 4, 'Maxent', SHIFT), text(38, y, 'Maxent', 12, INK),
          marker(106, y - 4, 'Random forest', SHIFT), text(118, y, 'Random forest (dashed)', 12, INK),
          f"<line x1='268' y1='{y - 4}' x2='292' y2='{y - 4}' stroke='{SHIFT}' stroke-width='2'/>",
          text(298, y, 'Shifted nulls, with Wilson 95% intervals in b', 12, INK),
          f"<line x1='584' y1='{y - 4}' x2='608' y2='{y - 4}' stroke='{SCATTER}' stroke-width='2'/>",
          text(614, y, 'Scattered nulls', 12, INK)]
parts.append('</svg>')
open(os.path.join(HERE, 'fig2.svg'), 'w', encoding='utf-8').write('\n'.join(parts))

with open(os.path.join(HERE, 'fig2-data.md'), 'w', encoding='utf-8') as f:
    wr = Table(f)
    wr.writerow(['measure', 'learner', 'band', 'value_percent', 'ci_low', 'ci_high'])
    for learner, vals in SHIFT_FP.items():
        for band, (m, lo, hi) in zip(BANDS, vals):
            wr.writerow(['shift false pass', learner, band, m, lo, hi])
    for learner, vals in SCATTER_FP.items():
        for band, m in zip(BANDS, vals):
            wr.writerow(['scatter false pass', learner, band, m, '', ''])
    for learner, vals in POWER.items():
        for band, m in zip(BANDS, vals):
            wr.writerow(['shift power, strong signal', learner, band, m, '', ''])
    for learner, passed, rest, diff in RHO:
        wr.writerow(['median rho, passed', learner, 'all', passed, '', ''])
        wr.writerow(['median rho, rest', learner, 'all', rest, '', ''])
print('wrote fig2.svg, fig2-data.md')
