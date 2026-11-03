#!/usr/bin/env python3
"""Lab p3c (for amd-4): does PowerPoint round the space BEFORE a paragraph and an exact line spacing to whole points too? (p3b: the space after 5.67 -> 6.) usage: gen.py DECK.pptx OUT.pptx
Slides vary lo-tdf169524's dash paragraphs (24 pt Arial, three in a row)."""
import sys, zipfile, re
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
s0 = z.read('ppt/slides/slide1.xml').decode()
DASH = re.compile(r'<a:pPr marL="576000" lvl="1" indent="-360000" algn="l">.*?</a:pPr>', re.S)
def sub(f):
    return DASH.sub(lambda m: f(m.group(0)), s0)
def aft(x):  # spcAft replaced
    return lambda p: re.sub(r'<a:spcAft>.*?</a:spcAft>', '<a:spcAft><a:spcPts val="%d"/></a:spcAft>' % x, p, flags=re.S)
def bef(x):  # spcAft 0, spcBef x
    return lambda p: re.sub(r'<a:spcAft>.*?</a:spcAft>', '<a:spcBef><a:spcPts val="%d"/></a:spcBef><a:spcAft><a:spcPts val="0"/></a:spcAft>' % x, p, flags=re.S)
def lnp(x):  # exact line spacing, spcAft 0
    return lambda p: re.sub(r'<a:spcAft>.*?</a:spcAft>', '<a:lnSpc><a:spcPts val="%d"/></a:lnSpc><a:spcAft><a:spcPts val="0"/></a:spcAft>' % x, p, flags=re.S)
def lnc(x):  # percentage line spacing, spcAft 0
    return lambda p: re.sub(r'<a:spcAft>.*?</a:spcAft>', '<a:lnSpc><a:spcPct val="%d"/></a:lnSpc><a:spcAft><a:spcPts val="0"/></a:spcAft>' % x, p, flags=re.S)
V = [('deck as is', s0)]
for x in (567, 641, 250, 1701, 349, 99, 1250):
    V.append(('dash: spcBef %d, spcAft 0' % x, sub(bef(x))))
for x in (349, 1250, 599, 650, 99):
    V.append(('dash: spcAft %d' % x, sub(aft(x))))
for x in (2750, 2733, 3000, 2999, 2401):
    V.append(('dash: lnSpc exact %d, spcAft 0' % x, sub(lnp(x))))
for x in (100000, 110000, 95000):
    V.append(('dash: lnSpc %d%%, spcAft 0' % (x // 1000), sub(lnc(x))))
n = len(V)
ct = z.read('[Content_Types].xml').decode()
rels = z.read('ppt/slides/_rels/slide1.xml.rels').decode()
pres = z.read('ppt/presentation.xml').decode()
prels = z.read('ppt/_rels/presentation.xml.rels').decode()
ct = ct.replace('</Types>', ''.join('<Override PartName="/ppt/slides/slide%d.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>' % i for i in range(2, n + 1)) + '</Types>')
pres = pres.replace('</p:sldIdLst>', ''.join('<p:sldId id="%d" r:id="rIdS%d"/>' % (256 + i, i) for i in range(1, n)) + '</p:sldIdLst>')
prels = prels.replace('</Relationships>', ''.join('<Relationship Id="rIdS%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide%d.xml"/>' % (i, i + 1) for i in range(1, n)) + '</Relationships>')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as o:
    for it in z.namelist():
        d = z.read(it)
        if it == '[Content_Types].xml': d = ct.encode()
        elif it == 'ppt/presentation.xml': d = pres.encode()
        elif it == 'ppt/_rels/presentation.xml.rels': d = prels.encode()
        elif it == 'ppt/slides/slide1.xml': d = V[0][1].encode()
        o.writestr(it, d)
    for i in range(1, n):
        o.writestr('ppt/slides/slide%d.xml' % (i + 1), V[i][1])
        o.writestr('ppt/slides/_rels/slide%d.xml.rels' % (i + 1), rels)
with open(out.rsplit('.', 1)[0] + '-cells.tsv', 'w') as f:
    for i, v in enumerate(V): f.write('%d\t%s\n' % (i + 1, v[0]))
