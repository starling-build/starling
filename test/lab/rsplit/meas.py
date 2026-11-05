import sys, glob, os, re, pymupdf
# meas.py DIR > RSPLIT-WORD.tsv. Per doc, per page: lines of the test row's long cell (first word of each line wNNN), y of first/last, horizontal rules (y, x0-x1), page the 'after row' lands on.
d = sys.argv[1]
print('# doc\tpage\tn_long_lines\tfirst_word\tlast_word\ty_first_baseline\ty_last_baseline\ty_after_row\ttable_bottom_rule_y\ttop_rule_y\trules_y (all horizontal rules wider than 200pt)')
for f in sorted(glob.glob(os.path.join(d, '*-orig.pdf'))):
    k = os.path.basename(f)[:-9]
    for pg in pymupdf.open(f):
        ls = []; after = ''
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).strip()
                if re.match(r'^w\d{3}', t) and l['bbox'][0] < 200: ls.append((l['spans'][0]['origin'][1], t.split()[0]))
                if t.startswith('after row'): after = '%.2f' % l['spans'][0]['origin'][1]
        rules = set()
        for dr in pg.get_drawings():
            for it in dr['items']:
                if it[0] == 'l' and abs(it[1].y - it[2].y) < 0.1 and abs(it[1].x - it[2].x) > 200: rules.add(round(it[1].y, 2))
                if it[0] == 're' and it[1].height < 3 and it[1].width > 200: rules.add(round(it[1].y0, 2))
        ls.sort(); rs = sorted(rules)
        print('%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' % (k, pg.number + 1, len(ls), ls[0][1] if ls else '', ls[-1][1] if ls else '', '%.2f' % ls[0][0] if ls else '', '%.2f' % ls[-1][0] if ls else '', after, '%.2f' % rs[-1] if rs else '', '%.2f' % rs[0] if rs else '', ' '.join('%.1f' % r for r in rs[-3:])))
