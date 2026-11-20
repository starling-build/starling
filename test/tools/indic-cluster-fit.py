#!/usr/bin/env python3
"""Per-cluster advances of an Indic face, read from Word's own prints.

usage: PRINTS_GLOB='/data/corpus-cache/staging/{dx2,xb}/word-win/*-orig.pdf' \\
       $HOME/venv-word/bin/python test/tools/indic-cluster-fit.py FACE BLOCK [OUT]
  FACE   the embedded font's name in the print, as pymupdf lists it ("Kokila", "Kokila,Bold", "NirmalaUI")
  BLOCK  the script's Unicode block start: 0x900 Devanagari, 0x980 Bengali, 0xA00 Gurmukhi, 0xA80 Gujarati, 0xC00 Telugu
         (blocks that share Devanagari's layout: consonants +0x15..+0x39, nukta +0x3C, matras +0x3E..+0x4C, virama +0x4D)
  OUT    Swift dictionary lines `"\\u{915}\\u{93E}": 1.0409,` (default /tmp/cluster_<FACE>.txt)

Each word's width is its first glyph's origin to the following space's origin, in em. A word is a run of characters
between spaces in a span set in FACE. The pre-base vowel sign (+0x3F) is moved back after its consonant (Word's text
layer lists glyphs in visual order). A word is a sum of cluster advances; the fit is ridge least squares, the worst
tenth of the words dropped and refitted. Only clusters met 3+ times are written. Prints made before the face arrived
on the print box (cloud fonts) use a substitute: check the face is really the named one (the span font is).
Words: a few hundred per cluster of data is enough for rms 0.005 em (Kokila: 12,944 words, 749 clusters).
"""
import glob, os, sys, unicodedata
import numpy as np, pymupdf

FACE = sys.argv[1]
B = int(sys.argv[2], 0)
OUT = sys.argv[3] if len(sys.argv) > 3 else '/tmp/cluster_%s.txt' % FACE.replace(',', '_')
PATTERN = os.environ.get('PRINTS_GLOB', '/data/corpus-cache/staging/*/word-win/*-orig.pdf')

def pats(p):
    if '{' not in p: return [p]
    a, rest = p.split('{', 1); mid, z = rest.split('}', 1)
    return [x for m in mid.split(',') for x in pats(a + m + z)]

cons = lambda v: B + 0x15 <= v <= B + 0x39 or (B == 0x900 and 0x958 <= v <= 0x95F)
matra = lambda v: B + 0x3E <= v <= B + 0x4C or B + 0x01 <= v <= B + 0x03 or v in (B + 0x62, B + 0x63)
nukta, virama, ikar = B + 0x3C, B + 0x4D, B + 0x3F

def group(u, i):
    """end index of the consonant (conjunct) group starting at i"""
    j = i
    while j < len(u) and cons(ord(u[j])):
        j += 1
        if j < len(u) and ord(u[j]) == nukta: j += 1
        if j + 1 < len(u) and ord(u[j]) == virama and cons(ord(u[j + 1])): j += 1
        else: break
    return j

def clusters(u):
    out = []; i = 0
    while i < len(u):
        j = group(u, i) if cons(ord(u[i])) else i + 1
        while cons(ord(u[i])) and j < len(u) and matra(ord(u[j])): j += 1
        out.append(u[i:j]); i = j
    return out

def norm(t):
    r = []; i = 0
    while i < len(t):
        if ord(t[i]) == ikar and i + 1 < len(t):
            j = group(t, i + 1); r.append(t[i + 1:j]); r.append(t[i]); i = j
        else: r.append(t[i]); i += 1
    return ''.join(r)

inblock = lambda q: B <= ord(q) < B + 0x80 or q in '‌‍'
X = []; Y = []
for pat in pats(PATTERN):
    for p in sorted(glob.glob(pat, recursive=True)):
        try: d = pymupdf.open(p)
        except Exception: continue
        for pg in d:
            for b in pg.get_text('rawdict')['blocks']:
                for ln in b.get('lines', []):
                    # words run across spans: Word often draws the spaces in another face (Arial), so the word
                    # ends at the next space of any span, not at a space inside the face's own span
                    cs = [(c, s['font'].split('+')[-1] == FACE, s['size']) for s in ln['spans'] for c in s['chars']]
                    cur = []; x0 = None; sz = 0
                    for k, (c, face, size) in enumerate(cs):
                        if c['c'] in ' \xa0':
                            # a stray space before a combining mark (Word's text layer splits words there) is not a word end
                            if cur and k + 1 < len(cs) and cs[k + 1][1] and (matra(ord(cs[k + 1][0]['c'])) or ord(cs[k + 1][0]['c']) in (nukta, virama)): continue
                            if cur and all(inblock(q) for q in cur):
                                X.append(norm(''.join(cur))); Y.append((c['origin'][0] - x0) / sz)
                            cur = []; x0 = None
                        elif face:
                            if x0 is None: x0 = c['origin'][0]; sz = size
                            cur.append(c['c'])
                        else:
                            cur = []; x0 = None
if not X: sys.exit('no words found: check FACE and PRINTS_GLOB')
keys = sorted({c for t in X for c in clusters(t)}); idx = {k: i for i, k in enumerate(keys)}
y = np.array(Y); ix = list(range(len(X)))
def design(rows):
    A = np.zeros((len(rows), len(keys)))
    for r, i in enumerate(rows):
        for c in clusters(X[i]): A[r, idx[c]] += 1
    return A
for rnd in range(2):
    A = design(ix); yy = y[ix]
    sol = np.linalg.solve(A.T @ A + 1e-3 * np.eye(len(keys)), A.T @ yy)
    err = np.abs(A @ sol - yy)
    if rnd == 0:
        thr = np.quantile(err, 0.9); ix = [i for i, e in zip(ix, err) if e <= thr]
cnt = A.sum(0)
print('%s: %d words, %d clusters, rms %.4f em' % (FACE, len(X), len(keys), np.sqrt((err ** 2).mean())))
with open(OUT, 'w') as f:
    seen = set()  # Swift String keys compare canonically (U+95B == U+91C U+93C): a duplicate traps the dictionary literal
    for k, i in sorted(idx.items(), key=lambda t: -cnt[t[1]]):
        n = unicodedata.normalize('NFC', k)
        if n in seen: continue
        seen.add(n)
        if cnt[i] >= 3: f.write('        "%s": %.4f,\n' % (''.join('\\u{%X}' % ord(q) for q in k), sol[i]))
print('wrote', OUT)
