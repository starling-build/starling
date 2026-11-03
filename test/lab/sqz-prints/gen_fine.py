# lab sqz fine sweep: justified, compat 15, autoHyphenation on (zone 0); overrun d stepped finely until the word no longer stays. n=1: .1..1.0 step .1; n=3: .2..2.4 step .2; n=8: .4..6.4 step .4
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg; from pkg import write; from lines import *
pkg.COMPAT_ON = True
nat, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
W = {}
for l in open(nat, encoding='utf8'):
    if l[0] != '#': f, s, n, w = l.split('\t')[:4]; W[(f, int(s), int(n))] = float(w)
DS = {1: [round(.1 * k, 1) for k in range(1, 11)], 3: [round(.2 * k, 1) for k in range(1, 13)], 8: [round(.4 * k, 1) for k in range(1, 17)]}
body = ''
for f in FONTS:
    for s in SIZES:
        for n in (1, 3, 8):
            for d in DS[n]:
                ri = 9638 - round((W[(f, s, n)] - d) * 20)
                body += '<w:p><w:pPr><w:ind w:right="%d"/><w:jc w:val="both"/></w:pPr>%s</w:p>' % (ri, run(f, s, LINES[n] + CONT))
write(os.path.join(out, 'sqzX.docx'), body, True, 0)
