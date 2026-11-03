# lab sqz2 (for amd-5): isolate the a594 gap. Times New Roman 14, compat 15, justified, autoHyphenation on (zone 0), column 481.9 pt (as lo-a594fa6b).
# Target line = "essary social services, and the right to security in the event of unemployment, sickness[,]" (13 spaces); its natural overrun is tuned by w:spacing (character spacing) on the run "ness" (4 chars, 0.05 pt per twip each).
# cases: a = line is the paragraph's first line, word ends with a comma | c = same, no comma | b1 = the line follows a hyphenated line (the real a594 paragraph), comma | b2 = same, no comma.
# usage: gen_a594.py WNAT_COMMA WNAT_NOCOMMA OUTDIR   (natural widths from sqz2n; pass 0 0 to write the natural-width measurement doc instead)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg; from pkg import write; pkg.COMPAT_ON = True
wc, wn, out = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]; os.makedirs(out, exist_ok=True)
F = 'Times New Roman'
def r(t, sp=0): return '<w:r><w:rPr><w:rFonts w:ascii="%s" w:hAnsi="%s"/><w:sz w:val="28"/><w:szCs w:val="28"/><w:lang w:val="en-US"/>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (F, F, '<w:spacing w:val="%d"/>' % sp if sp else '', t)
HEAD = 'essary social services, and the right to security in the event of unemployment, sick'
PRE = 'Everyone has the right to a standard of living adequate for the health and well-being of himself and of his family, including food, clothing, housing and medical care and nec'
def para(first, comma, sp, pre=False):
    tail = (', disability, widowhood, old age or other lack of livelihood in circumstances beyond his control.' if comma else ' disability, widowhood, old age or other lack of livelihood in circumstances beyond his control.')
    # comma: the word is "sickness," followed by " disability,..." ; no comma: "sickness" followed by " disability..."
    t = ',' + ' disability, widowhood, old age or other lack of livelihood in circumstances beyond his control.' if comma else ' disability, widowhood, old age or other lack of livelihood in circumstances beyond his control.'
    return '<w:p><w:pPr><w:jc w:val="both"/></w:pPr>%s%s%s%s</w:p>' % (r(PRE) if pre else '', r(HEAD), r('ness', sp), r(t))
if wc == 0:   # natural-width doc: the head text alone, unwrapped (left aligned, wide)
    body = ''.join('<w:p><w:pPr><w:ind w:right="-6000"/><w:jc w:val="left"/></w:pPr>%s%s%s</w:p>' % (r(HEAD), r('ness'), r(c)) for c in (',', ''))
    write(os.path.join(out, 'sqz2n.docx'), body, True, 0)
else:
    cases = []; body = ''
    # d = W_nat + 0.2*val - 481.9 ; val from -15 .. +45 step 2 (about 0.4 pt)
    for name, comma, pre, W in (('a', True, False, wc), ('c', False, False, wn), ('b1', True, True, wc), ('b2', False, True, wn)):
        for val in range(-15, 47, 2):
            cases.append((name, val, round(W + 0.2 * val - 481.9, 2))); body += para(None, comma, val, pre)
    write(os.path.join(out, 'sqz2.docx'), body, True, 0)
    open(os.path.join(out, 'cases.tsv'), 'w').write('\n'.join('%s\t%d\t%.2f' % c for c in cases))
