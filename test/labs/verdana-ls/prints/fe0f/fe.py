import sys, pymupdf
print('doc\tline\tidx\tcodepoint\tchar\tfont\tsize\ttext_color\tx0\ty0\tx1\ty1\tadvance')
for doc, f in (('pptx', sys.argv[1]), ('docx', sys.argv[2])):
    p = pymupdf.open(f)[0]
    for b in p.get_text('rawdict')['blocks']:
        if b['type'] == 1: print('%s\t-\t-\timage\t-\t-\t-\t-\t%.2f\t%.2f\t%.2f\t%.2f\t-' % ((doc,) + tuple(b['bbox']))); continue
        for li, l in enumerate(b['lines']):
            for s in l['spans']:
                cs = s['chars']
                for i, c in enumerate(cs):
                    adv = (cs[i + 1]['origin'][0] - c['origin'][0]) if i + 1 < len(cs) else c['bbox'][2] - c['origin'][0]
                    print('%s\t%.1f\t%d\tU+%04X\t%s\t%s\t%.2f\t%06x\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f' % (doc, l['spans'][0]['origin'][1], i, ord(c['c']), c['c'] if ord(c['c']) > 32 else '_', s['font'], s['size'], s['color'], *c['bbox'], adv))
