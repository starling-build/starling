#!/usr/bin/env python3
"""Lab fhang builder: where does Word put a framePr notBeside label that holds an inline picture on an exact-height line? usage: build.py OUTDIR"""
import sys, os, zipfile, zlib, struct
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
def png():
    raw = b''.join(b'\x00' + b'\x80\x80\x80' * 4 for _ in range(4))
    ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b'')
def pict(hpt, wpt=18):
    cx, cy = int(wpt * 12700), int(hpt * 12700)
    return (f'<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cx}" cy="{cy}"/><wp:docPr id="1" name="P"/><wp:cNvGraphicFramePr/>'
            f'<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name=""/><pic:cNvPicPr/></pic:nvPicPr>'
            f'<pic:blipFill><a:blip r:embed="rId9"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')
#  code: (frame?, exact line pt or 0 = auto, picture height pt or 0 = none, label text, in a one-cell table?)
V = [
 ("F15-P12",   True, 15, 12, "Note ", False),   # the corpus case: exact 15, 12pt picture, frame
 ("F15-P0",    True, 15, 0,  "Note ", False),   # same without the picture
 ("F15-P24",   True, 15, 24, "Note ", False),   # picture taller than the exact line
 ("F15-P6",    True, 15, 6,  "Note ", False),
 ("F20-P12",   True, 20, 12, "Note ", False),
 ("F12-P12",   True, 12, 12, "Note ", False),
 ("FAUTO-P12", True, 0,  12, "Note ", False),   # automatic line height
 ("N15-P12",   False, 15, 12, "Note ", False),  # no frame: ordinary paragraph, same line
 ("N15-P0",    False, 15, 0,  "Note ", False),
 ("F15-P12-T", True, 15, 12, "Note ", True),    # inside a one-cell table
 ("F15-P0-T",  True, 15, 0,  "Note ", True),
 ("F15-P12-I13", True, 15, 12, "Note ", False),  # intro paragraph on an exact 13pt line (the corpus list item's)
 ("N15-P12-I13", False, 15, 12, "Note ", False),
 ("F15-P12-I13-L", True, 15, 12, "Note ", False),  # intro 13pt exact, label indented 18pt (a label in a list)
]
INTRO13 = ("I13",)
def label(frame, ex, ph, txt):
    fp = '<w:framePr w:wrap="notBeside" w:vAnchor="text" w:hAnchor="text" w:y="1"/>' if frame else ''
    sp = f'<w:spacing w:before="120" w:after="0" w:line="{ex*20}" w:lineRule="exact"/>' if ex else '<w:spacing w:before="120" w:after="0"/>'
    return f'<w:p><w:pPr><w:keepNext/>{fp}{sp}</w:pPr>' + (pict(ph) if ph else '') + f'<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">{txt}</w:t></w:r></w:p>'
def plain(t, ex=0):
    sp = f'<w:spacing w:before="60" w:after="60" w:line="{ex*20 if ex else 280}" w:lineRule="exact"/>'
    return f'<w:p><w:pPr>{sp}<w:ind w:left="360" w:right="360"/></w:pPr><w:r><w:t>{t}</w:t></w:r></w:p>'
def doc(frame, ex, ph, txt, tbl, code=""):
    lab = label(frame, ex, ph, txt)
    if code.endswith("-L"): lab = lab.replace('<w:spacing', '<w:ind w:left="360"/><w:spacing', 1) if False else lab.replace('</w:pPr>', '<w:ind w:left="360"/></w:pPr>', 1)
    intro = plain('INTRO LINE before the label.', 13 if "-I13" in code else 0)
    after = plain('AFTER LINE one, the paragraph that follows the label and hangs below it.') + plain('AFTER LINE two.')
    if tbl:
        body = intro + '<w:tbl><w:tblPr><w:tblW w:w="8640" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/></w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="8640"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="8640" w:type="dxa"/></w:tcPr>' + lab + after + '</w:tc></w:tr></w:tbl><w:p/>'
    else:
        body = intro + lab + after
    sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1800" w:bottom="1440" w:left="1800" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
STYLES = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="20"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:before="60" w:after="60" w:line="280" w:lineRule="exact"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/p.png"/></Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    for n, (code, fr, ex, ph, txt, tb) in enumerate(V, 1):
        with zipfile.ZipFile(os.path.join(out, f"fhang-{n:02d}-{code}.docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", doc(fr, ex, ph, txt, tb, code)); z.writestr("word/styles.xml", STYLES)
            z.writestr("word/_rels/document.xml.rels", DRELS); z.writestr("word/media/p.png", png())
    print(len(V), "documents in", out)
if __name__ == "__main__": main(sys.argv[1])
