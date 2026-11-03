# lab hyz (for amd-5): the lo-a594fa6b paragraph repeated, right indent stepped -40..+40 twips (2 tw = 0.1pt) so "sickness," overshoots/undershoots.
# usage: gen.py SRC_DOCX OUTDIR -> hyz0 (zone 0 as the source), hyz360, hyz720 (hyphenationZone), hyzoff (autoHyphenation off)
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); files = [(i.filename, z.read(i.filename)) for i in z.infolist() if not i.filename.endswith('/')]
doc = dict(files)['word/document.xml'].decode('utf8')
T = 'realization, through national effort and international co-operation and in accordance with the organization and resources of each State, of the economic, social and cultural rights indispensable for his dignity and the free development of his personality.'
def p(r): return ('<w:p><w:pPr><w:pStyle w:val="Normal"/><w:suppressAutoHyphens w:val="false"/><w:ind w:right="%d"/><w:jc w:val="both"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p><w:p><w:pPr><w:spacing w:after="0" w:line="40" w:lineRule="exact"/></w:pPr></w:p>' % (r, T))
body = ''.join(p(r) for r in range(-300, 101, 5))
b0 = doc.index('<w:body>') + 8; sect = doc.rindex('<w:sectPr')
new = doc[:b0] + body + doc[sect:]
sect_xml = new[new.rindex('<w:sectPr'):]
new = new.replace(sect_xml, sect_xml.replace('<w:type w:val="nextPage"/>', ''))
S = dict(files)['word/settings.xml'].decode('utf8')
def save(n, s):
    with zipfile.ZipFile(os.path.join(out, n + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for fn, b in files:
            o.writestr(fn, new.encode('utf8') if fn == 'word/document.xml' else s.encode('utf8') if fn == 'word/settings.xml' else b)

save('ac2', S)
save('ac2off', S.replace('<w:autoHyphenation w:val="true"/>', '<w:autoHyphenation w:val="false"/>'))
