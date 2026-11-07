import sys, pymupdf
# chars.py MODE ... ; prints doc, page, line, idx, char, codepoint, x0, x1, baseline, font, size
def lines(pdf):
    d = pymupdf.open(pdf)
    for pi, p in enumerate(d):
        rows = []
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(c['c'] for s in l['spans'] for c in s['chars'])
                if t.strip(): rows.append((l['spans'][0]['origin'][1], l))
        for i, (y, l) in enumerate(sorted(rows, key=lambda r: (round(r[0], 1), r[1]['bbox'][0]))): yield pi + 1, i + 1, y, l
def dump(doc, pdf, keep):
    for pg, ln, y, l in lines(pdf):
        if not keep(pg, ln, l): continue
        k = 0
        for s in l['spans']:
            for c in s['chars']:
                k += 1
                print('%s\t%d\t%d\t%d\t%s\t%04X\t%.3f\t%.3f\t%.2f\t%s\t%g' % (doc, pg, ln, k, c['c'] if c['c'].strip() else '_', ord(c['c']), c['bbox'][0], c['bbox'][2], c['origin'][1], s['font'], round(s['size'], 2)))
HDR = 'doc\tpage\tline\tidx\tchar\tcodepoint\tx0\tx1\tbaseline\tfont\tsize'
