# Builds wordart-fit-lab.pptx: one WordArt box per slide, to measure how PowerPoint fits a
# warped word to its box (advance vs ink, per axis, per line vs widest line).
# Every box has a thin red outline so the ink can be measured against it in the print.
import zipfile, re
SRC = '../../corpus/pptx/decks/oox-tdf125582_TextOnCircle.pptx'
EMU = 12700
# (name, preset, adj or None, width pt, height pt, words (one paragraph each), autofit)
P = ('textPlain', 50000); I = ('textInflate', 20000); D = ('textDeflateInflate', 24108)
CASES = []
for w in ('JAVA', 'HIHI', 'jaWj'):
    for (pre, adj) in (P, I, D):
        CASES.append(('%s-%s-300' % (w, pre), pre, adj, 300, 120, [w], 'none'))
CASES += [
 ('JAVA-textPlain-200', 'textPlain', 50000, 200, 120, ['JAVA'], 'none'),
 ('JAVA-textPlain-420', 'textPlain', 50000, 420, 120, ['JAVA'], 'none'),
 ('JAVA-textInflate-420', 'textInflate', 20000, 420, 120, ['JAVA'], 'none'),
 ('JAVA-textPlain-300-spAuto', 'textPlain', 50000, 300, 120, ['JAVA'], 'sp'),
 ('JAVA+HIHI-textPlain-300', 'textPlain', 50000, 300, 200, ['JAVA', 'HIHI'], 'none'),
 ('JAVA+HIHI-textInflate-300', 'textInflate', 20000, 300, 200, ['JAVA', 'HIHI'], 'none'),
 ('JAVA+jaWjjj-textPlain-300', 'textPlain', 50000, 300, 200, ['JAVA', 'jaWjjj'], 'none'),
 ('JAVA-textPlain-slant-300', 'textPlain', 70000, 300, 120, ['JAVA'], 'none'),
]
z = zipfile.ZipFile(SRC)
files = {n: z.read(n) for n in z.namelist()}
slide = files['ppt/slides/slide1.xml'].decode()
RPR = '<a:rPr lang="en-US" sz="4000"><a:latin typeface="Arial Black"/><a:ea typeface="Arial Black"/><a:cs typeface="Arial Black"/></a:rPr>'
def make(pre, adj, w, h, words, auto):
    s = re.sub(r'<a:ext cx="2160000" cy="2160000"/>', '<a:ext cx="%d" cy="%d"/>' % (w * EMU, h * EMU), slide)
    s = re.sub(r'<a:off x="\d+" y="\d+"/>', '<a:off x="%d" y="%d"/>' % ((8640763 - w * EMU) // 2, (5759450 - h * EMU) // 2), s, count=1)
    s = s.replace('<a:noFill/></p:spPr>', '<a:noFill/><a:ln w="6350"><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:ln></p:spPr>')
    gd = '<a:gd name="adj" fmla="val %d"/>' % adj if adj is not None else ''
    s = re.sub(r'<a:prstTxWarp prst="textCircle"><a:avLst>.*?</a:avLst></a:prstTxWarp>', '<a:prstTxWarp prst="%s"><a:avLst>%s</a:avLst></a:prstTxWarp>' % (pre, gd), s, flags=re.S)
    if auto == 'none':
        s = s.replace('<a:spAutoFit/>', '<a:noAutofit/>')
    body = ''.join('<a:p><a:r>%s<a:t>%s</a:t></a:r></a:p>' % (RPR, t) for t in words)
    m = re.search(r'<a:p>.*</a:p>', s, re.S)
    return s[:m.start()] + body + s[m.end():]
ct = files['[Content_Types].xml'].decode()
rels = files['ppt/_rels/presentation.xml.rels'].decode()
pres = files['ppt/presentation.xml'].decode()
ids = ''
out = {k: v for k, v in files.items() if not k.startswith('ppt/slides/')}
for i, (name, pre, adj, w, h, words, auto) in enumerate(CASES, 1):
    out['ppt/slides/slide%d.xml' % i] = make(pre, adj, w, h, words, auto).encode()
    out['ppt/slides/_rels/slide%d.xml.rels' % i] = files['ppt/slides/_rels/slide1.xml.rels']
    if i > 1:
        ct = ct.replace('</Types>', '<Override PartName="/ppt/slides/slide%d.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>' % i)
        rels = rels.replace('</Relationships>', '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide%d.xml"/></Relationships>' % (100 + i, i))
        ids += '<p:sldId id="%d" r:id="rId%d"/>' % (256 + i - 1, 100 + i)
pres = pres.replace('<p:sldId id="256" r:id="rId2"/>', '<p:sldId id="256" r:id="rId2"/>' + ids)
out['[Content_Types].xml'] = ct.encode(); out['ppt/_rels/presentation.xml.rels'] = rels.encode(); out['ppt/presentation.xml'] = pres.encode()
with zipfile.ZipFile('wordart-fit-lab.pptx', 'w', zipfile.ZIP_DEFLATED) as o:
    for k, v in out.items(): o.writestr(k, v)
open('slides.txt', 'w').write('\n'.join('%d %s' % (i, c[0]) for i, c in enumerate(CASES, 1)) + '\n')
print(len(CASES), 'slides')
