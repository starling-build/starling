#!/usr/bin/env python3
"""meas.py PDF > TABR-WORD.tsv: per line (3 blocks x 10 stops): tag, stop (twips), stop_x (pt from page left = 76.55 + stop/20), '12' x0/x1 and y, same-line?, number of leader dots, first/last dot x0, dot pitch (min/max of consecutive x0 diffs). right margin x = 518.95."""
import sys, re, pymupdf
STOPS = [8848] + list(range(8900, 9301, 50))
p = pymupdf.open(sys.argv[1])[0]
lines = []
for b in p.get_text('rawdict')['blocks']:
    for l in b.get('lines', []):
        cs = [c for s in l['spans'] for c in s['chars']]
        if cs: lines.append((l['bbox'][1], cs, l))
lines.sort(key=lambda t: t[0])
print('# tag\tstop_tw\tstop_x_pt\ttext_start_y\tn_dots\tfirst_dot_x0\tlast_dot_x1\tpitch_min\tpitch_max\tnum12_x0\tnum12_x1\tnum_y\tnum_on_same_line\tover_right_margin_pt (num x1 - 518.95)')
# join pieces by y: an entry may be split into several pdf lines (text, dots, number): group by baseline
rows = {}
for y, cs, l in lines:
    for c in cs:
        key = round(c['origin'][1], 0)
        rows.setdefault(key, []).append(c)
n = 0
for key in sorted(rows):
    cs = sorted(rows[key], key=lambda c: c['origin'][0])
    t = ''.join(c['c'] for c in cs)
    m = re.match(r'Entry ([STH])(\d)', t)
    if not m: continue
    dots = [c for c in cs if c['c'] == '.']
    d12 = [c for c in cs if c['c'] in '12' and c['bbox'][0] > 300]
    pit = [dots[i + 1]['origin'][0] - dots[i]['origin'][0] for i in range(len(dots) - 1)]
    stop = STOPS[int(m.group(2))]
    num = d12[-2:] if len(d12) >= 2 else d12
    print('%s%s\t%d\t%.2f\t%.1f\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%.1f\t%s\t%s' % (
        m.group(1), m.group(2), stop, 76.55 + stop / 20, key, len(dots),
        '%.2f' % dots[0]['bbox'][0] if dots else '-', '%.2f' % dots[-1]['bbox'][2] if dots else '-',
        '%.2f' % min(pit) if pit else '-', '%.2f' % max(pit) if pit else '-',
        '%.2f' % num[0]['bbox'][0] if num else '-', '%.2f' % num[-1]['bbox'][2] if num else '-', key, 'yes' if num else 'NO',
        '%.2f' % (num[-1]['bbox'][2] - 518.95) if num else '-'))
    n += 1
print('# lines', n, file=sys.stderr)
