# lab sqz3 (for amd-5): is the squeeze limit a property of the line's words/space count? Prefixes of the lo-a594fa6b sentence (TNR 14, compat 15, justified, hyphenation OFF, no commas):
# the first k words (k = 4, 9, 12, 14, 16 -> 3, 8, 11, 13, 15 spaces), column = natural width - d, d stepped; continuation = the real next words.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg; from pkg import write; from lines import run; pkg.COMPAT_ON = True
W = 'Everyone has the right to a standard of living adequate for the health and well-being of himself and of his family, including food, clothing, housing and medical care and necessary social services'.split()
KS = [4, 9, 12, 14, 16]
mode, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
F = 'Times New Roman'
if mode == 'n':
    body = ''.join('<w:p><w:pPr><w:ind w:right="-6000"/><w:jc w:val="left"/></w:pPr>%s</w:p>' % run(F, 14, ' '.join(W[:k])) for k in KS)
    write(os.path.join(out, 'sqz3n.docx'), body, False, 0)
else:
    nat = [float(x) for x in sys.argv[3].split(',')]
    DS = [round(.5 * i, 1) for i in range(1, 25)]
    body = ''; cases = []
    for k, w in zip(KS, nat):
        for d in DS:
            ri = 9638 - round((w - d) * 20); cases.append((k, d))
            body += '<w:p><w:pPr><w:ind w:right="%d"/><w:jc w:val="both"/></w:pPr>%s</w:p>' % (ri, run(F, 14, ' '.join(W)))
    write(os.path.join(out, 'sqz3.docx'), body, False, 0)
    open(os.path.join(out, 'cases.tsv'), 'w').write('\n'.join('%d\t%.1f' % c for c in cases))
