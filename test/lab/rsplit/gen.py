# lab rsplit (for amd-perf): a table row whose long cell crosses the page foot. A4, 1in margins, 14 one-line filler rows, then the test row, then an 'after' row.
# gen.py OUTDIR. Words are numbered w001.. so line starts can be read back.
import sys, os, zipfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sqz'))
import pkg
pkg.SECT = pkg.SECT.replace('1134', '1440')   # 1in margins
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
BORD = '<w:tblBorders>' + ''.join('<w:%s w:val="single" w:sz="8" w:space="0" w:color="000000"/>' % s for s in ('top','left','bottom','right','insideH','insideV')) + '</w:tblBorders>'
def words(a, b): return ' '.join('w%03d' % i for i in range(a, b))
def para(t, ppr=''): return '<w:p><w:pPr>%s</w:pPr><w:r><w:t>%s</w:t></w:r></w:p>' % (ppr, t)
def cell(w, content, tcpr=''): return '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s</w:tcPr>%s</w:tc>' % (w, tcpr, content)
def row(cells, trpr=''): return '<w:tr>%s%s</w:tr>' % ('<w:trPr>%s</w:trPr>' % trpr if trpr else '', cells)
W1, W2 = 6000, 3000
def build(name, mode):
    trpr = ''; vm1 = vm2 = ''; kn = 'none'; widow = False
    if mode == 'cant': trpr = '<w:cantSplit/>'
    if mode == 'exact': trpr = '<w:trHeight w:val="4000" w:hRule="exact"/>'
    if mode == 'atleast': trpr = '<w:trHeight w:val="4000" w:hRule="atLeast"/>'
    if mode == 'exactcant': trpr = '<w:cantSplit/><w:trHeight w:val="4000" w:hRule="exact"/>'
    if mode == 'vmerge': vm1 = '<w:vMerge w:val="restart"/>'; vm2 = '<w:vMerge/>'
    if mode in ('kn1', 'kn2', 'three', 'three-widow'): kn = mode
    if mode == 'three-widow': widow = True
    rows = ''.join(row(cell(W1, para('filler %d' % i)) + cell(W2, para('f'))) for i in range(1, 15))
    if kn == 'none':
        long = para(words(1, 441))
    else:
        ppr = lambda first: ('<w:keepNext/>' if (kn == 'kn2' or (kn == 'kn1' and first)) else '') + ('<w:widowControl/>' if widow else '')
        long = para(words(1, 144), ppr(True)) + para(words(144, 287), ppr(False)) + para(words(287, 430), ppr(False))
    rows += row(cell(W1, long) + cell(W2, para('merged short text', ''), vm1), trpr)
    rows += row(cell(W1, para('after row')) + cell(W2, para('after') if not vm2 else para(''), vm2))
    body = '<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/>%s<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="%d"/><w:gridCol w:w="%d"/></w:tblGrid>%s</w:tbl><w:p/>' % (BORD, W1, W2, rows)
    pkg.write(os.path.join(out, name + '.docx'), body)
for n, m in [('base', ''), ('cant', 'cant'), ('exact', 'exact'), ('atleast', 'atleast'), ('exactcant', 'exactcant'), ('vmerge', 'vmerge'),
             ('three', 'three'), ('kn1', 'kn1'), ('kn2', 'kn2'), ('threewidow', 'three-widow')]:
    build(n, m)
print('10 docs')
