# lab hyz (for amd-5): the lo-a594fa6b paragraph repeated, right indent stepped -40..+40 twips (2 tw = 0.1pt) so "sickness," overshoots/undershoots.
# usage: gen.py SRC_DOCX OUTDIR -> hyz0 (zone 0 as the source), hyz360, hyz720 (hyphenationZone), hyzoff (autoHyphenation off)
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); files = [(i.filename, z.read(i.filename)) for i in z.infolist() if not i.filename.endswith('/')]
doc = dict(files)['word/document.xml'].decode('utf8')
T = 'Everyone has the right to a standard of living adequate for the health and well-being of himself and of his family, including food, clothing, housing and medical care and necessary social services, and the right to security in the event of unemployment, sickness, disability, widowhood, old age or other lack of livelihood in circumstances beyond his control.'
def p(r): return ('<w:p><w:pPr><w:pStyle w:val="Normal"/><w:suppressAutoHyphens w:val="false"/><w:ind w:right="%d"/><w:jc w:val="both"/></w:pPr><w:r><w:t>%s</w:t></w:r></w:p><w:p><w:pPr><w:spacing w:after="0" w:line="40" w:lineRule="exact"/></w:pPr></w:p>' % (r, T))
body = ''.join(p(r) for r in range(-40, 42, 2))
b0 = doc.index('<w:body>') + 8; sect = doc.rindex('<w:sectPr')
new = doc[:b0] + body + doc[sect:]
sect_xml = new[new.rindex('<w:sectPr'):]
new = new.replace(sect_xml, sect_xml.replace('<w:type w:val="nextPage"/>', ''))
S = dict(files)['word/settings.xml'].decode('utf8')
def save(n, s):
    with zipfile.ZipFile(os.path.join(out, n + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for fn, b in files:
            o.writestr(fn, new.encode('utf8') if fn == 'word/document.xml' else s.encode('utf8') if fn == 'word/settings.xml' else b)
save('hyz0', S)
save('hyz360', S.replace('<w:hyphenationZone w:val="0"/>', '<w:hyphenationZone w:val="360"/>'))
save('hyz720', S.replace('<w:hyphenationZone w:val="0"/>', '<w:hyphenationZone w:val="720"/>'))
save('hyzoff', S.replace('<w:autoHyphenation w:val="true"/>', '<w:autoHyphenation w:val="false"/>'))
