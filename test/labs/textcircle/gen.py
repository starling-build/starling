# Builds textcircle-lab.pptx: one slide per case, from the checked-in TextOnCircle deck.
import zipfile, re, sys
SRC = '../../corpus/pptx/decks/oox-tdf125582_TextOnCircle.pptx'
EMU = 12700
# (name, width pt, height pt, font pt, paragraphs)
CASES = [
 ('c170-1p-40', 170, 170, 40, ['Fontwork type']),
 ('c170-2p-40', 170, 170, 40, ['Fontwork 40pt', 'type Circle curve']),
 ('c170-3p-40', 170, 170, 40, ['Fontwork 40pt', 'type Circle curve', 'third line here']),
 ('c170-2p-20', 170, 170, 20, ['Fontwork 20pt', 'type Circle curve']),
 ('c250x120-2p-40', 250, 120, 40, ['Fontwork 40pt', 'type Circle curve']),
]
z = zipfile.ZipFile(SRC)
files = {n: z.read(n) for n in z.namelist()}
slide = files['ppt/slides/slide1.xml'].decode()
def make(w, h, sz, paras):
    s = re.sub(r'<a:ext cx="2160000" cy="2160000"/>', '<a:ext cx="%d" cy="%d"/>' % (w*EMU, h*EMU), slide)
    s = re.sub(r'<a:off x="\d+" y="\d+"/>', '<a:off x="%d" y="%d"/>' % ((8640763-w*EMU)//2, (5759450-h*EMU)//2), s, count=1)
    m = re.search(r'<a:p>.*</a:p>', s, re.S)
    rpr = re.search(r'<a:rPr.*?</a:rPr>', s, re.S).group(0).replace('sz="4000"', 'sz="%d"' % (sz*100))
    body = ''.join('<a:p><a:r>%s<a:t>%s</a:t></a:r></a:p>' % (rpr, t) for t in paras)
    return s[:m.start()] + body + s[m.end():]
ct = files['[Content_Types].xml'].decode()
rels = files['ppt/_rels/presentation.xml.rels'].decode()
pres = files['ppt/presentation.xml'].decode()
ids = ''
out = {k: v for k, v in files.items() if not k.startswith('ppt/slides/')}
for i, (name, w, h, sz, paras) in enumerate(CASES, 1):
    out['ppt/slides/slide%d.xml' % i] = make(w, h, sz, paras).encode()
    out['ppt/slides/_rels/slide%d.xml.rels' % i] = files['ppt/slides/_rels/slide1.xml.rels']
    if i > 1:
        ct = ct.replace('</Types>', '<Override PartName="/ppt/slides/slide%d.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>' % i)
        rels = rels.replace('</Relationships>', '<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide%d.xml"/></Relationships>' % (100+i, i))
        ids += '<p:sldId id="%d" r:id="rId%d"/>' % (256+i-1, 100+i)
pres = pres.replace('<p:sldId id="256" r:id="rId2"/>', '<p:sldId id="256" r:id="rId2"/>' + ids)
out['[Content_Types].xml'] = ct.encode(); out['ppt/_rels/presentation.xml.rels'] = rels.encode(); out['ppt/presentation.xml'] = pres.encode()
with zipfile.ZipFile('textcircle-lab.pptx', 'w', zipfile.ZIP_DEFLATED) as o:
    for k, v in out.items(): o.writestr(k, v)
print(len(CASES), 'slides')
