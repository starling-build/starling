# lab sqz4 (for amd-5): what makes a594 line 1 (15 spaces) stricter? Variants of the first 16 words (TNR 14, compat 15, justified, hyphenation off) + the real continuation:
# base | nowb: "well-being" -> "wellbeing" | nohim: "himself" -> "balance" | both. Column = the variant's natural width - d (d 3.0..8.0 step 0.25).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg; from pkg import write; from lines import run; pkg.COMPAT_ON = True
LINE = 'Everyone has the right to a standard of living adequate for the health and well-being of'
REST = ' himself and of his family, including food, clothing, housing and medical care and necessary social services'
V = {'base': (LINE, 'himself'), 'nowb': (LINE.replace('well-being', 'wellbeing'), 'himself'), 'nohim': (LINE, 'balance'), 'both': (LINE.replace('well-being', 'wellbeing'), 'balance')}
mode, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True); F = 'Times New Roman'
def text(v): return V[v][0] + ' ' + V[v][1] + REST[len(' himself'):]
if mode == 'n':
    body = ''.join('<w:p><w:pPr><w:ind w:right="-6000"/><w:jc w:val="left"/></w:pPr>%s</w:p>' % run(F, 14, V[v][0]) for v in V)
    write(os.path.join(out, 'sqz4n.docx'), body, False, 0)
else:
    nat = dict(zip(V, [float(x) for x in sys.argv[3].split(',')])); DS = [round(3 + .25 * i, 2) for i in range(21)]; body = ''; cases = []
    for v in V:
        for d in DS:
            ri = 9638 - round((nat[v] - d) * 20); cases.append((v, d))
            body += '<w:p><w:pPr><w:ind w:right="%d"/><w:jc w:val="both"/></w:pPr>%s</w:p>' % (ri, run(F, 14, text(v)))
    write(os.path.join(out, 'sqz4.docx'), body, False, 0)
    open(os.path.join(out, 'cases.tsv'), 'w').write('\n'.join('%s\t%.2f' % c for c in cases))
