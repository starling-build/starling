import zipfile, re, sys, os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile('src/orig.docx'); f = {n: z.read(n) for n in z.namelist()}
d0 = f['word/document.xml'].decode('utf8'); st0 = f['word/settings.xml'].decode('utf8')
TC = list(re.finditer(r'<w:tcMar>.*?</w:tcMar>', d0, re.S)); assert len(TC) == 2
TM = list(re.finditer(r'<w:tblCellMar>.*?</w:tblCellMar>', d0, re.S)); assert len(TM) == 2
PP = re.search(r'<w:tblpPr [^>]*/>', d0).group(0)


def setlr(block, v):
    b = re.sub(r'(<w:left w:w=")\d+', r'\g<1>%d' % v, block); return re.sub(r'(<w:right w:w=")\d+', r'\g<1>%d' % v, b)


def build(name, outer_lr=None, inner_lr=None, inner_ind=None, nofloat=False, outer_default=False, compat=None):
    d = d0
    # replace from the end so spans stay valid: inner tcMar (TC[1]), outer tcMar (TC[0]); inner tblCellMar TM[1], outer TM[0]
    reps = []
    if inner_lr is not None: reps.append((TC[1].span(), setlr(TC[1].group(0), inner_lr)))
    if outer_lr is not None: reps.append((TC[0].span(), setlr(TC[0].group(0), outer_lr)))
    if outer_default:
        ob = re.sub(r'<w:left w:w="\d+" w:type="dxa"/>|<w:right w:w="\d+" w:type="dxa"/>', '', TC[0].group(0)); reps.append((TC[0].span(), ob))
        reps.append((TM[0].span(), ''))
    if inner_ind is not None:
        reps.append((TM[1].span(), '<w:tblInd w:w="%d" w:type="dxa"/>' % inner_ind + TM[1].group(0)))
    if nofloat:
        m = re.search(r'<w:tblpPr [^>]*/>', d0); reps.append((m.span(), ''))
    for (a, b), t in sorted(reps, key=lambda r: -r[0][0]):
        d = d[:a] + t + d[b:]
    g = dict(f); g['word/document.xml'] = d.encode('utf8')
    if compat:
        g['word/settings.xml'] = st0.replace('w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="12"', 'w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="%d"' % compat).encode('utf8')
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for n, v in g.items(): o.writestr(n, v)


build('base')
for v in (0, 108, 540): build('n1_%d' % v, inner_lr=v)
for v in (108, 270): build('n2_%d' % v, outer_lr=v)
for v in (0, 108, -108): build('n3_%s' % ('m108' if v < 0 else v), inner_ind=v)
build('n4_nofloat', nofloat=True)
build('n5_outerdefault', outer_default=True)
build('n6_c12', compat=12); build('n6_c15', compat=15)
print(sorted(os.listdir(out)))
