#!/usr/bin/env python3
"""Lab p3b (for amd-4): why lo-tdf169524's dash-bullet paragraphs are 0.3 pt taller in PowerPoint. usage: gen.py DECK.pptx OUT.pptx
Slide 1 is the deck's slide untouched; the others vary the dash paragraphs (marL 576000, Symbol bullet 75%, spcAft 567)."""
import sys, zipfile, re
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
s0 = z.read('ppt/slides/slide1.xml').decode()
DASH = re.compile(r'<a:pPr marL="576000" lvl="1" indent="-360000" algn="l">.*?</a:pPr>', re.S)
def sub(f):
    return DASH.sub(lambda m: f(m.group(0)), s0)
V = [('deck as is', s0),
     ('dash: no bullet', sub(lambda p: re.sub(r'<a:buClr>.*?<a:buChar[^>]*/>', '<a:buNone/>', p, flags=re.S))),
     ('dash: Arial bullet', sub(lambda p: re.sub(r'<a:buFont typeface="Symbol"[^>]*/>', '<a:buFont typeface="Arial"/>', p))),
     ('dash: bullet 100%', sub(lambda p: p.replace('buSzPct val="75000"', 'buSzPct val="100000"'))),
     ('dash: spcAft 0', sub(lambda p: re.sub(r'<a:spcAft>.*?</a:spcAft>', '<a:spcAft><a:spcPts val="0"/></a:spcAft>', p, flags=re.S))),
     ('dash: spcAft 1701', sub(lambda p: p.replace('<a:spcPts val="567"/>', '<a:spcPts val="1701"/>'))),
     ('dash: lvl 0 (no lvl attr)', sub(lambda p: p.replace(' lvl="1"', ''))),
     ('dash: marL 216000 indent -216000', sub(lambda p: p.replace('marL="576000"', 'marL="216000"').replace('indent="-360000"', 'indent="-216000"'))),
     ('dash: bullet char "-" Arial', sub(lambda p: re.sub(r'<a:buFont typeface="Symbol"[^>]*/>\s*<a:buChar[^>]*/>', '<a:buFont typeface="Arial"/><a:buChar char="-"/>', p))),
     ]
n = len(V)
ct = z.read('[Content_Types].xml').decode()
rels = z.read('ppt/slides/_rels/slide1.xml.rels').decode()
pres = z.read('ppt/presentation.xml').decode()
prels = z.read('ppt/_rels/presentation.xml.rels').decode()
extra_ct = ''.join('<Override PartName="/ppt/slides/slide%d.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>' % i for i in range(2, n + 1))
ct = ct.replace('</Types>', extra_ct + '</Types>')
ids = ''.join('<p:sldId id="%d" r:id="rIdS%d"/>' % (256 + i, i) for i in range(1, n))
pres = pres.replace('</p:sldIdLst>', ids + '</p:sldIdLst>')
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
