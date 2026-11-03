# shared: lines of a pdf as (page, chars, words) ; word = (text, x0, x1) split at space gaps/space chars
import pymupdf
def lines(pdf):
    out = []
    for pg in pymupdf.open(pdf):
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars']]
                if not ch: continue
                words = []; cur = None
                for c in ch:
                    if c['c'] == ' ':
                        if cur: words.append(cur); cur = None
                    else:
                        if cur is None: cur = [c['c'], c['origin'][0], c['bbox'][2]]
                        else: cur[0] += c['c']; cur[2] = c['bbox'][2]
                if cur: words.append(cur)
                if words: out.append((pg.number + 1, words))
    return out
