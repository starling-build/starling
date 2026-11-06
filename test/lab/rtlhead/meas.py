import sys, pymupdf
# meas.py PDF > RTLHEAD-WORD.tsv: per paragraph (order spacing 0/12 x run 12/15/20 x markcs unset/10/15/20): grey box top/bottom, text baseline, box height. Page y in pt.
d = pymupdf.open(sys.argv[1]); p = d[0]
boxes = sorted([dr['rect'] for dr in p.get_drawings() if dr.get('fill') and abs(dr['fill'][0] - 0.851) < 0.01 and abs(dr['fill'][2] - 0.851) < 0.01], key=lambda r: r.y0)
txt = sorted(((l['spans'][0]['origin'][1], ''.join(s['text'] for s in l['spans'])) for b in p.get_text('dict')['blocks'] for l in b.get('lines', []) if 'sp' in ''.join(s['text'] for s in l['spans'])))
print('# pages\t%d' % len(d))
print('# n\tspacing\trun\tmarkcs\tbox_top\tbox_bottom\tbox_h\tbaseline\tbaseline_minus_top\tbottom_minus_baseline')
n = 0
for sp in (0, 12):
    for run in (12, 15, 20):
        for m in (0, 10, 15, 20):
            n += 1
            b = boxes[n - 1] if n <= len(boxes) else None; t = txt[n - 1][0] if n <= len(txt) else None
            print('%d\t%d\t%d\t%d\t%s' % (n, sp, run, m, '\t'.join(['%.2f' % x for x in ((b.y0, b.y1, b.height, t, t - b.y0, b.y1 - t) if b and t else [])])))
print('# boxes %d texts %d' % (len(boxes), len(txt)), file=sys.stderr)
