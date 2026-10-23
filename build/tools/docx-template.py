#!/usr/bin/env python3
"""A site template as a .docx, written from scratch, in one of a few
professional designs: the styles of a long document (body, headings with
a rule or an accent, quote bar, shaded code), a running header, a
"Page N of M" footer, a Letter page with one-inch margins and a cover
that the header and footer leave alone. Every face named is one the
Writer ships on every platform (Carlito, Caladea, Liberation, Libre
Franklin, Work Sans, Poppins), so the page looks the same in the browser
and in the PDF. The Writer opens it as any Word file: a site names it in
site.json as `template` and every new page starts from it; it opens in
Word too, for anyone who wants to restyle it there.

    build/tools/docx-template.py OUT.docx [--design editorial|technical|modern]
        [--title T] [--subtitle S] [--header H] [--byline B]
        [--heading-font F] [--body-font F] [--primary HEX] [--accent HEX] [--cover band|rule|plain]

The design sets the fonts, colours and cover; the other flags override it.
"""
import argparse, zipfile

DESIGNS = {
    # Navy band on the cover, Libre Franklin headings, Carlito text: the
    # look of a vendor's technical manual.
    'technical': dict(heading_font='Libre Franklin', body_font='Carlito', body_size=11, primary='1B2B4B', accent='2F5496',
                      ink='1F2328', muted='6B7280', cover='band'),
    # A serif text face (Caladea, Cambria's metrics) under sans headings in
    # deep teal; the cover a large title over an accent rule.
    'editorial': dict(heading_font='Libre Franklin', body_font='Caladea', body_size=11.5, primary='0F3D4C', accent='C8102E',
                      ink='222222', muted='6B6B6B', cover='rule'),
    # Poppins headings and Work Sans text in blue and near-black, lots of
    # air: the look of a software product's documentation.
    'modern': dict(heading_font='Poppins SemiBold', body_font='Work Sans', body_size=10.5, primary='111827', accent='2563EB',
                   ink='111827', muted='6B7280', cover='plain'),
}

ap = argparse.ArgumentParser()
ap.add_argument('out'); ap.add_argument('--design', default='editorial', choices=sorted(DESIGNS))
ap.add_argument('--title', default='Starling Site'); ap.add_argument('--subtitle', default='A publication')
ap.add_argument('--header', default=None); ap.add_argument('--byline', default='')
for k in ['heading-font', 'body-font', 'primary', 'accent', 'cover']: ap.add_argument('--' + k, default=None)
a = ap.parse_args()
D = dict(DESIGNS[a.design])
for k in ['heading_font', 'body_font', 'primary', 'accent', 'cover']:
    v = getattr(a, k)
    if v: D[k] = v
HEADER = a.header or (a.title + '  ·  ' + a.subtitle)
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'

def esc(t): return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
def run(text, rpr=''):
    return f'<w:r>{f"<w:rPr>{rpr}</w:rPr>" if rpr else ""}<w:t xml:space="preserve">{esc(text)}</w:t></w:r>'
def para(style, *runs, ppr=''):
    return f'<w:p><w:pPr><w:pStyle w:val="{style}"/>{ppr}</w:pPr>{"".join(runs)}</w:p>'
def style(id, name, kind='paragraph', ppr='', rpr='', based='Normal', next='Normal'):
    b = f'<w:basedOn w:val="{based}"/>' if based and id != 'Normal' else ''
    n = f'<w:next w:val="{next}"/>' if next and kind == 'paragraph' else ''
    return f'<w:style w:type="{kind}" w:styleId="{id}"><w:name w:val="{name}"/>{b}{n}<w:qFormat/><w:pPr>{ppr}</w:pPr><w:rPr>{rpr}</w:rPr></w:style>'
font = lambda f: f'<w:rFonts w:ascii="{f}" w:hAnsi="{f}" w:cs="{f}"/>'
sz = lambda pt: f'<w:sz w:val="{int(round(pt*2))}"/><w:szCs w:val="{int(round(pt*2))}"/>'
color = lambda c: f'<w:color w:val="{c}"/>'
rule = lambda c, pts, space=4: f'<w:pBdr><w:bottom w:val="single" w:sz="{int(pts*8)}" w:space="{space}" w:color="{c}"/></w:pBdr>'
shade = lambda c: f'<w:shd w:val="clear" w:color="auto" w:fill="{c}"/>'
HF, BF = font(D['heading_font']), font(D['body_font'])
P, A, INK, MUTED = D['primary'], D['accent'], D['ink'], D['muted']
cover = D['cover']
body = D['body_size']

# The cover: a band (white text on the primary colour), a rule (the title
# over a thick accent rule), or plain (the title in the accent colour).
if cover == 'band':
    title_p = f'<w:spacing w:before="1800" w:after="0"/><w:ind w:left="360" w:right="360"/>{shade(P)}<w:contextualSpacing/>'
    title_r = f'{HF}{sz(36)}{color("FFFFFF")}<w:b/>'
    sub_p = f'<w:spacing w:before="0" w:after="1200"/><w:ind w:left="360" w:right="360"/>{shade(P)}'
    sub_r = f'{HF}{sz(15)}{color("DCE3F0")}'
elif cover == 'rule':
    title_p = f'<w:spacing w:before="2600" w:after="160"/>{rule(A, 3, 10)}'
    title_r = f'{HF}{sz(40)}{color(P)}<w:b/>'
    sub_p = '<w:spacing w:before="200" w:after="600"/>'
    sub_r = f'{BF}{sz(18)}{color(MUTED)}<w:i/>'
else:
    title_p = '<w:spacing w:before="2800" w:after="80"/>'
    title_r = f'{HF}{sz(40)}{color(A)}'
    sub_p = '<w:spacing w:before="0" w:after="600"/>'
    sub_r = f'{BF}{sz(17)}{color(MUTED)}'

h1_rule = rule(A, 1.5, 6) if cover != 'plain' else ''
styles = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles {W}>
<w:docDefaults><w:rPrDefault><w:rPr>{BF}{sz(body)}{color(INK)}<w:lang w:val="en-US"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="{int(body*14)}" w:line="{int(round(body*2*1.22*10))}" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
{style("Normal", "Normal", based=None, next=None)}
{style("Title", "Title", ppr=title_p, rpr=title_r)}
{style("Subtitle", "Subtitle", ppr=sub_p, rpr=sub_r)}
{style("Heading1", "heading 1", ppr=f'<w:keepNext/><w:keepLines/><w:spacing w:before="560" w:after="200"/>{h1_rule}<w:outlineLvl w:val="0"/>', rpr=f'{HF}{sz(21)}{color(P)}<w:b/>')}
{style("Heading2", "heading 2", ppr='<w:keepNext/><w:keepLines/><w:spacing w:before="400" w:after="120"/><w:outlineLvl w:val="1"/>', rpr=f'{HF}{sz(14)}{color(P)}<w:b/>')}
{style("Heading3", "heading 3", ppr='<w:keepNext/><w:keepLines/><w:spacing w:before="280" w:after="80"/><w:outlineLvl w:val="2"/>', rpr=f'{HF}{sz(11.5)}{color(INK)}<w:b/>')}
{style("Quote", "Quote", ppr=f'<w:ind w:left="600" w:right="600"/><w:spacing w:before="160" w:after="200"/><w:pBdr><w:left w:val="single" w:sz="24" w:space="14" w:color="{A}"/></w:pBdr>', rpr=f'{color("444444")}<w:i/>')}
{style("Caption", "caption", ppr='<w:spacing w:after="220"/>', rpr=f'{sz(9)}{color(MUTED)}<w:i/>')}
{style("Code", "Code", ppr=f'<w:spacing w:after="0" w:line="252" w:lineRule="auto"/>{shade("F3F4F6")}<w:ind w:left="200" w:right="200"/>', rpr=f'{font("Liberation Mono")}{sz(9.5)}{color("1F2328")}')}
{style("ListParagraph", "List Paragraph", ppr='<w:ind w:left="720"/><w:contextualSpacing/>')}
{style("Header", "header", ppr=f'<w:jc w:val="right"/><w:spacing w:after="0"/>{rule("D0D7E2", 0.5)}', rpr=f'{HF}{sz(8.5)}{color(MUTED)}')}
{style("Footer", "footer", ppr='<w:jc w:val="center"/><w:spacing w:after="0"/>', rpr=f'{HF}{sz(8.5)}{color(MUTED)}')}
{style("Hyperlink", "Hyperlink", kind="character", based=None, next=None, rpr=f'{color(A)}<w:u w:val="single"/>')}
</w:styles>'''
header = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr {W}>{para("Header", run(HEADER))}</w:hdr>'''
footer = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr {W}><w:p><w:pPr><w:pStyle w:val="Footer"/></w:pPr>{run("Page ")}<w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r></w:fldSimple>{run(" of ")}<w:fldSimple w:instr=" NUMPAGES "><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>'''
byline = para("Normal", run(a.byline, f'{HF}{sz(10)}{color(MUTED)}'), ppr='<w:spacing w:before="0"/>') if a.byline else ''
document = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document {W}><w:body>
{para("Title", run(a.title))}
{para("Subtitle", run(a.subtitle))}
{byline}
{para("Normal")}
<w:sectPr><w:headerReference w:type="default" r:id="rId3"/><w:footerReference w:type="default" r:id="rId4"/>
<w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1296" w:left="1440" w:header="720" w:footer="576" w:gutter="0"/>
<w:titlePg/><w:docGrid w:linePitch="360"/></w:sectPr>
</w:body></w:document>'''
settings = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings {W}><w:defaultTabStop w:val="720"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>'''
rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''
docrels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
</Relationships>'''
ct = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
</Types>'''
with zipfile.ZipFile(a.out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', rels)
    z.writestr('word/document.xml', document); z.writestr('word/_rels/document.xml.rels', docrels)
    z.writestr('word/styles.xml', styles); z.writestr('word/settings.xml', settings)
    z.writestr('word/header1.xml', header); z.writestr('word/footer1.xml', footer)
print("wrote", a.out, "design", a.design)
