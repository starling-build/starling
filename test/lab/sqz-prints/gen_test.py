# lab sqz (for amd-5): space squeeze before hyphenating/wrapping. Per (font,size,nspaces) line L whose natural width W was measured (SQZ-NATURAL.tsv);
# the paragraph "L + continuation" is set in a column of W - d pt, d = 0.1/0.3/0.6/1.0, left and justified; docs: sqzOn (autoHyphenation, zone 0), sqzOff, sqzOn360 (zone 360 tw).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg; from pkg import write; from lines import *
if len(sys.argv) > 3: pkg.COMPAT_ON = True; SFX = '15'
else: SFX = ''
nat, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
W = {}
for l in open(nat, encoding='utf8'):
    if l[0] == '#': continue
    f, s, n, w = l.split('\t')[:4]; W[(f, int(s), int(n))] = float(w)
DS = [0.1, 0.3, 0.6, 1.0]
def doc(hy, zone, name):
    body = ''
    for f in FONTS:
        for s in SIZES:
            for n in (1, 3, 8):
                for d in DS:
                    for al in ('left', 'both'):
                        ri = 9638 - round((W[(f, s, n)] - d) * 20)
                        body += '<w:p><w:pPr><w:ind w:right="%d"/><w:jc w:val="%s"/></w:pPr>%s</w:p>' % (ri, al, run(f, s, LINES[n] + CONT))
    write(os.path.join(out, name + SFX + '.docx'), body, hy, zone)
doc(True, 0, 'sqzOn'); doc(False, 0, 'sqzOff'); doc(True, 360, 'sqzOn360')
