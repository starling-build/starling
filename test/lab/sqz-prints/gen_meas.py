import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg; from pkg import write; from lines import *
if len(sys.argv) > 2: pkg.COMPAT_ON = True
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
body = ''.join('<w:p><w:pPr><w:ind w:right="-9000"/><w:jc w:val="left"/></w:pPr>%s</w:p>' % run(f, s, LINES[n]) for f in FONTS for s in SIZES for n in (1, 3, 8))
write(os.path.join(out, 'sqzm%s.docx' % ('15' if len(sys.argv) > 2 else '')), body)
