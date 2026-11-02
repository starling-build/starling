import pymupdf, glob, os
rows = ['# case\tpages\tfirst_glyph_x(min over text lines)\tright_most_line_end_x(max)\tn_lines\tfirst line text\tall line x0 distinct']
for f in sorted(glob.glob('run/*-orig.pdf')):
    d = pymupdf.open(f); mn = 1e9; mx = -1e9; n = 0; xs = set(); first = ''; pm = {}
    for pi, p in enumerate(d):
        for b in p.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).strip()
                if not t or t in ('body start', 'End') or t.startswith('July'): continue
                ch = [c for s in l['spans'] for c in s['chars']] if 'chars' in l['spans'][0] else None
                x0, x1 = l['bbox'][0], l['bbox'][2]
                mn = min(mn, x0); mx = max(mx, x1); pm[pi] = max(pm.get(pi, -1e9), x1); n += 1; xs.add(round(x0, 1)); first = first or t[:20]
    rows.append('\t'.join(map(str, [os.path.basename(f).replace('-orig.pdf', ''), len(d), round(mn, 2), round(mx, 2), round(pm.get(0, 0), 2), round(pm.get(1, 0), 2), n, sorted(xs)])))
open('NEST-WORD.tsv', 'w', encoding='utf8').write('\n'.join(rows) + '\n'); print('\n'.join(rows))
