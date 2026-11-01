#!/usr/bin/env python3
"""Lab pie4: what lab pie3 could not tell (all its labels were one size, perspective 30, no explosion).
Three families of documents, each chart a 3-D pie of two slices (the labelled one, share s %, and 'rest'), no title/legend,
frame 400.6 x 216pt, rAngAx 0, only the first slice labelled with its category name, no leader lines, no fill.
  A  label SIZE      (pie4-A-<pos>.docx, pos = inEnd, outEnd, bestFit): rotX 30, perspective 30; share 21 and 45; rotY 0/90/180/270;
                     label text of 5 sizes: 'Qnnnn' + filler to 5, 7, 10, 16 characters, and a 3-line label (words).
  B  PERSPECTIVE     (pie4-B-persp.docx): dLblPos ctr; perspective 0, 30, 60, 90, 150; rotX 30; share 21 and 45; rotY 0/90/180/270.
  C  EXPLOSION       (pie4-C-expl.docx): dLblPos ctr; explosion 0, 25, 50 on the labelled slice only, and the same on both; perspective 30,
                     rotX 30; share 21 and 45; rotY 0/90/180/270.
Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table  (send the TSV, or just the PDFs).
usage: build.py OUTDIR"""
import sys, os, zipfile
NS = ('xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
ROTYS = (0, 90, 180, 270)
SHARES = (21, 45)
FILL = {5: "", 7: "WW", 10: "WWWWW", 16: "WWWWWWWWWWW"}   # id 'Qnnnn' is 5 chars; filler makes 5, 7, 10, 16
LONG = " alpha beta gamma delta epsilon zeta eta theta iota kappa"   # wraps to three lines

def label_text(code, size):
    if size == "long": return f"Q{code}{LONG}"
    return f"Q{code}{FILL[size]}"

def chart_xml(text, share, rotx, roty, pos, persp, expl0, expl1):
    dpts = ''
    if expl0: dpts += f'<c:dPt><c:idx val="0"/><c:bubble3D val="0"/><c:explosion val="{expl0}"/></c:dPt>'
    if expl1: dpts += f'<c:dPt><c:idx val="1"/><c:bubble3D val="0"/><c:explosion val="{expl1}"/></c:dPt>'
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace {NS}><c:date1904 val="0"/><c:roundedCorners val="0"/>'
            f'<c:chart><c:autoTitleDeleted val="1"/><c:view3D><c:rotX val="{rotx}"/><c:rotY val="{roty}"/><c:rAngAx val="0"/><c:perspective val="{persp}"/></c:view3D>'
            '<c:floor><c:thickness val="0"/></c:floor><c:sideWall><c:thickness val="0"/></c:sideWall><c:backWall><c:thickness val="0"/></c:backWall>'
            '<c:plotArea><c:layout/><c:pie3DChart><c:varyColors val="1"/><c:ser><c:idx val="0"/><c:order val="0"/>' + dpts +
            f'<c:dLbls><c:dLbl><c:idx val="1"/><c:delete val="1"/></c:dLbl><c:spPr><a:noFill/></c:spPr>'
            f'<c:dLblPos val="{pos}"/><c:showLegendKey val="0"/><c:showVal val="0"/><c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/></c:dLbls>'
            f'<c:cat><c:strLit><c:ptCount val="2"/><c:pt idx="0"><c:v>{text}</c:v></c:pt><c:pt idx="1"><c:v>rest</c:v></c:pt></c:strLit></c:cat>'
            f'<c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="2"/><c:pt idx="0"><c:v>{share}</c:v></c:pt><c:pt idx="1"><c:v>{100-share}</c:v></c:pt></c:numLit></c:val>'
            '</c:ser></c:pie3DChart></c:plotArea><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>')

def inline(rid, n):
    return ('<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5088255" cy="2743200"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
            f'<wp:docPr id="{n}" name="Chart {n}"/><wp:cNvGraphicFramePr/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
            f'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="{rid}"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')

def write_doc(path, charts):
    """charts: list of (head, xml)"""
    body = ''; parts = {}; rels = ''
    for i, (head, xml) in enumerate(charts, 1):
        parts[f"word/charts/chart{i}.xml"] = xml
        rels += f'<Relationship Id="rId{i+10}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/chart{i}.xml"/>'
        pb = '<w:pageBreakBefore/>' if i > 1 and i % 2 == 1 else ''
        body += (f'<w:p><w:pPr>{pb}<w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="18"/></w:rPr>'
                 f'<w:t>{head}</w:t></w:r></w:p>')
        body += f'<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>{inline(f"rId{i+10}", i)}</w:p>'
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="992" w:gutter="0"/></w:sectPr>'
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
                'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>' + body + sect + '</w:body></w:document>')
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          + ''.join(f'<Override PartName="/word/charts/chart{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' for i in range(1, len(charts) + 1))
          + '</Types>')
    root = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + rels + '</Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ct); z.writestr("_rels/.rels", root)
        z.writestr("word/document.xml", document); z.writestr("word/_rels/document.xml.rels", drels)
        for k, v in parts.items(): z.writestr(k, v)

def head(code, fam, share, rotx, roty, pos, persp, expl, size):
    return f"Q{code} fam={fam} share={share} rotX={rotx} rotY={roty} pos={pos} persp={persp} expl={expl} size={size}"

def main(out):
    os.makedirs(out, exist_ok=True)
    n = 0
    # A: label size
    for pos in ("inEnd", "outEnd", "bestFit"):
        charts = []
        for size in (5, 7, 10, 16, "long"):
            for share in SHARES:
                for roty in ROTYS:
                    n += 1; code = f"{n:04d}"
                    charts.append((head(code, "A", share, 30, roty, pos, 30, "0", size),
                                   chart_xml(label_text(code, size), share, 30, roty, pos, 30, 0, 0)))
        write_doc(os.path.join(out, f"pie4-A-{pos}.docx"), charts); print(f"pie4-A-{pos}.docx", len(charts))
    # B: perspective
    charts = []
    for persp in (0, 30, 60, 90, 150):
        for share in SHARES:
            for roty in ROTYS:
                n += 1; code = f"{n:04d}"
                charts.append((head(code, "B", share, 30, roty, "ctr", persp, "0", 5), chart_xml(label_text(code, 5), share, 30, roty, "ctr", persp, 0, 0)))
    write_doc(os.path.join(out, "pie4-B-persp.docx"), charts); print("pie4-B-persp.docx", len(charts))
    # C: explosion
    charts = []
    for both in (False, True):
        for expl in (0, 25, 50):
            for share in SHARES:
                for roty in ROTYS:
                    n += 1; code = f"{n:04d}"
                    tag = f"{expl}{'+both' if both else ''}"
                    charts.append((head(code, "C", share, 30, roty, "ctr", 30, tag, 5),
                                   chart_xml(label_text(code, 5), share, 30, roty, "ctr", 30, expl, expl if both else 0)))
    write_doc(os.path.join(out, "pie4-C-expl.docx"), charts); print("pie4-C-expl.docx", len(charts))

if __name__ == "__main__":
    main(sys.argv[1])
