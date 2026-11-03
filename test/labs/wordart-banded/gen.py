# Builds wordart-banded-lab.pptx: one WordArt box per slide, to measure how PowerPoint fits a
# warped word to its box (advance vs ink, per axis, per line vs widest line).
# Every box has a thin red outline so the ink can be measured against it in the print.
import zipfile, re
SRC = '../../corpus/pptx/decks/oox-tdf125582_TextOnCircle.pptx'
EMU = 12700
# (name, preset, adj or None, width pt, height pt, words (one paragraph each), autofit)
P = ('textPlain', 50000); I = ('textInflate', 20000); D = ('textDeflateInflate', 24108)
# (name, preset, adj, w, h, words, auto, extra) ; extra = dict(ins=(l,t,r,b) pt or None, ln=pt outline, sz=pt, trail=bool)
CASES = []
WORDS=['Happy','Birthday','To','You','Today']
# line counts 1-5, two sizes, the two banded presets and an unwarped control
for pre,adj in (('textDeflateInflate',None),('textDeflateInflateDeflate',None),('textNoShape',None)):
    for sz in (24,40):
        for n in (1,2,3,4,5):
            CASES.append(('B%d-%s-%d'%(n,pre,sz),pre,adj,330,250,WORDS[:n],'none',dict(sz=sz)))
# non-banded presets at 3 lines, for comparison with their one-line fits
for pre in ('textInflate','textDeflate','textCanDown','textWave1'):
    CASES.append(('B3-%s-32'%pre,pre,None,330,250,WORDS[:3],'none',dict(sz=32)))
# a non-default adjust on the banded pair, 3 lines
for pre,adj in (('textDeflateInflate',20000),('textDeflateInflate',80000),('textDeflateInflateDeflate',20000),('textDeflateInflateDeflate',80000)):
    CASES.append(('B3-%s-a%d'%(pre,adj),pre,adj,330,250,WORDS[:3],'none',dict(sz=32)))
z = zipfile.ZipFile(SRC)
files = {n: z.read(n) for n in z.namelist()}
slide = files['ppt/slides/slide1.xml'].decode()
RPR = '<a:rPr lang="en-US" sz="4000"><a:latin typeface="Arial Black"/><a:ea typeface="Arial Black"/><a:cs typeface="Arial Black"/></a:rPr>'
def make(pre, adj, w, h, words, auto, extra):
    s = re.sub(r'<a:ext cx="2160000" cy="2160000"/>', '<a:ext cx="%d" cy="%d"/>' % (w * EMU, h * EMU), slide)
    s = re.sub(r'<a:off x="\d+" y="\d+"/>', '<a:off x="%d" y="%d"/>' % ((8640763 - w * EMU) // 2, (5759450 - h * EMU) // 2), s, count=1)
    s = s.replace('<a:noFill/></p:spPr>', '<a:noFill/><a:ln w="6350"><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:ln></p:spPr>')
    gd = '<a:gd name="adj" fmla="val %d"/>' % adj if adj is not None else ''
    s = re.sub(r'<a:prstTxWarp prst="textCircle"><a:avLst>.*?</a:avLst></a:prstTxWarp>', '<a:prstTxWarp prst="%s"><a:avLst>%s</a:avLst></a:prstTxWarp>' % (pre, gd), s, flags=re.S)
    if auto == 'none':
        s = s.replace('<a:spAutoFit/>', '<a:noAutofit/>')
    rpr = RPR
    if 'sz' in extra: rpr = rpr.replace('sz="4000"', 'sz="%d"' % (extra['sz'] * 100))
    if 'ln' in extra: rpr = rpr.replace('><a:latin', '><a:ln w="%d"><a:solidFill><a:srgbClr val="808080"/></a:solidFill></a:ln><a:latin' % int(extra['ln'] * EMU), 1)
    if extra.get('ins'):
        l, t, r_, b = [int(v * EMU) for v in extra['ins']]
        s = re.sub(r'<a:bodyPr ', '<a:bodyPr lIns="%d" tIns="%d" rIns="%d" bIns="%d" ' % (l, t, r_, b), s, count=1)
    elif 'ins' in extra and extra['ins'] is None:
        pass
    words = [(' ' if extra.get('lead') else '') + t + (' ' if extra.get('trail') else '') for t in words]
    sp = extra.get('sp')
    ppr = '<a:pPr><a:lnSpc><a:spcPct val="%d"/></a:lnSpc></a:pPr>' % (sp*1000) if sp else ''
    body = ''.join('<a:p>'+ppr+'<a:r>%s<a:t xml:space="preserve">%s</a:t></a:r></a:p>' % (rpr, t) for t in words)
    m = re.search(r'<a:p>.*</a:p>', s, re.S)
    return s[:m.start()] + body + s[m.end():]
ct = files['[Content_Types].xml'].decode()
rels = files['ppt/_rels/presentation.xml.rels'].decode()
pres = files['ppt/presentation.xml'].decode()
ids = ''
out = {k: v for k, v in files.items() if not k.startswith('ppt/slides/')}
for i, (name, pre, adj, w, h, words, auto, extra) in enumerate(CASES, 1):
    out['ppt/slides/slide%d.xml' % i] = make(pre, adj, w, h, words, auto, extra).encode()
    out['ppt/slides/_rels/slide%d.xml.rels' % i] = files['ppt/slides/_rels/slide1.xml.rels']
    if i > 1:
        ct = ct.replace('</Types>', '<Override PartName="/ppt/slides/slide%d.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>' % i)
        rels = rels.replace('</Relationships>', '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide%d.xml"/></Relationships>' % (100 + i, i))
        ids += '<p:sldId id="%d" r:id="rId%d"/>' % (256 + i - 1, 100 + i)
pres = pres.replace('<p:sldId id="256" r:id="rId2"/>', '<p:sldId id="256" r:id="rId2"/>' + ids)
out['[Content_Types].xml'] = ct.encode(); out['ppt/_rels/presentation.xml.rels'] = rels.encode(); out['ppt/presentation.xml'] = pres.encode()
with zipfile.ZipFile('wordart-banded-lab.pptx', 'w', zipfile.ZIP_DEFLATED) as o:
    for k, v in out.items(): o.writestr(k, v)
open('slides.txt', 'w').write('\n'.join('%d %s' % (i, c[0]) for i, c in enumerate(CASES, 1)) + '\n')
print(len(CASES), 'slides')
