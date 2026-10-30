#!/usr/bin/env python3
"""Fixed DrawingML text frames: fresh Word's indent and clipping controls.

Requires PyMuPDF and a native OfficeApp. Runs both Word font modes.
  python office-fixed-text-box.py --binary /path/to/OfficeApp
  python office-fixed-text-box.py --fixture /tmp/fixed-box.docx
  python office-fixed-text-box.py --pdf /tmp/fixed-box-word-or-browser.pdf
"""
import argparse
import io
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

import pymupdf


def fixture():
    blocks = []
    for align in ["both", "left"]:
        for text, indent, turned in [("A", 0, False), ("A", 9, False), ("A", 24, False), ("30", 15, True)]:
            number = len(blocks) + 1
            width, height = (254000, 99060) if turned else (298450, 318770)
            insets = 'lIns="0" tIns="0" rIns="0" bIns="0"' if turned else 'lIns="91440" tIns="45720" rIns="91440" bIns="45720"'
            before = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>' if blocks else ""
            # The first four inherit justified alignment, as the original
            # document does; the other four explicitly choose left alignment.
            alignment = '<w:jc w:val="left"/>' if align == "left" else ""
            blocks.append(f'''{before}<w:p><w:r><w:t>Control {number}</w:t></w:r></w:p>
<w:p><w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="1" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">
<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="page"><wp:posOffset>1270000</wp:posOffset></wp:positionH>
<wp:positionV relativeFrom="page"><wp:posOffset>2540000</wp:posOffset></wp:positionV>
<wp:extent cx="{width}" cy="{height}"/><wp:wrapNone/><wp:docPr id="{number}" name="Frame {number}"/>
<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp>
<wps:cNvSpPr txBox="1"/><wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{width}" cy="{height}"/></a:xfrm><a:prstGeom prst="rect"/><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr>
<wps:txbx><w:txbxContent><w:p><w:pPr><w:ind w:firstLine="{indent * 20}"/>{alignment}<w:spacing w:before="0" w:after="0"/></w:pPr>
<w:r><w:rPr><w:rFonts w:ascii="Carlito" w:hAnsi="Carlito"/><w:sz w:val="{15 if turned else 24}"/></w:rPr><w:t>{text}</w:t></w:r>
</w:p></w:txbxContent></wps:txbx><wps:bodyPr vert="{'vert270' if turned else 'horz'}" wrap="square" {insets}><a:noAutofit/></wps:bodyPr>
</wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>''')
    # A tight second line must keep all its ink when the first line moves.
    # White first glyphs isolate B: overflow on the left, an explicit break
    # on the right. Both must paint the same black B, including its top.
    for first, size, pitch in [("g", 12, 8), ("A", 24, 8), ("g", 12, 18)]:
        number = len(blocks) + 1
        frames = []
        for x, overflow in [(100, True), (300, False)]:
            frames.append(f'''<w:p><w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="1" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">
<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="page"><wp:posOffset>{x * 12700}</wp:posOffset></wp:positionH>
<wp:positionV relativeFrom="page"><wp:posOffset>2540000</wp:posOffset></wp:positionV>
<wp:extent cx="254000" cy="1016000"/><wp:wrapNone/><wp:docPr id="{number * 2 + int(overflow)}" name="Overlap {number} {x}"/>
<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp>
<wps:cNvSpPr txBox="1"/><wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="254000" cy="1016000"/></a:xfrm><a:prstGeom prst="rect"/><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr>
<wps:txbx><w:txbxContent><w:p><w:pPr><w:ind w:firstLine="{600 if overflow else 0}"/><w:jc w:val="left"/><w:spacing w:before="0" w:after="0" w:line="{pitch * 20}" w:lineRule="exact"/></w:pPr>
<w:r><w:rPr><w:rFonts w:ascii="Carlito" w:hAnsi="Carlito"/><w:sz w:val="{size * 2}"/><w:color w:val="FFFFFF"/></w:rPr><w:t>{first}</w:t>{'' if overflow else '<w:br/>'}</w:r>
<w:r><w:rPr><w:rFonts w:ascii="Carlito" w:hAnsi="Carlito"/><w:sz w:val="24"/><w:color w:val="000000"/></w:rPr><w:t>B</w:t></w:r>
</w:p></w:txbxContent></wps:txbx><wps:bodyPr vert="horz" wrap="square" lIns="0" tIns="0" rIns="0" bIns="0"><a:noAutofit/></wps:bodyPr>
</wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>''')
        blocks.append(f'<w:p><w:r><w:br w:type="page"/></w:r></w:p><w:p><w:r><w:t>Control {number}</w:t></w:r></w:p>' + ''.join(frames))
    w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    contents = {
        "[Content_Types].xml": '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>''',
        "_rels/.rels": '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''',
        "word/_rels/document.xml.rels": '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''',
        "word/styles.xml": f'''<w:styles xmlns:w="{w}"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:pPr><w:jc w:val="both"/><w:spacing w:before="0" w:after="0"/></w:pPr><w:rPr><w:rFonts w:ascii="Carlito" w:hAnsi="Carlito"/><w:sz w:val="24"/></w:rPr></w:style></w:styles>''',
        "word/document.xml": f'''<w:document xmlns:w="{w}" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><w:body>{''.join(blocks)}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="0" w:footer="0"/></w:sectPr></w:body></w:document>''',
    }
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w", zipfile.ZIP_DEFLATED) as package:
        for name, xml in contents.items():
            package.writestr(name, xml)
    return data.getvalue()


def check(path):
    with pymupdf.open(path) as pdf:
        assert len(pdf) == 11, f"{path}: expected eleven control pages, got {len(pdf)}"
        labels = [[w for w in page.get_text("words") if 150 < w[1] < 300] for page in pdf]
        for first in [0, 4]:
            zero, indented, hidden, turned = labels[first:first + 4]
            assert [w[4] for w in zero] == ["A"], (first, zero)
            assert [w[4] for w in indented] == ["A"], (first + 1, indented)
            assert abs(indented[0][0] - zero[0][0] - 9) < 0.2, "first glyph lost its 9pt indent"
            assert abs(indented[0][1] - zero[0][1]) < 0.2, "the indent occupied a line by itself"
            assert not hidden, f"glyph past the fixed frame still drawn: {hidden}"
            assert [w[4] for w in turned] == ["0"], f"turned frame must retain only the second digit: {turned}"
        for page in list(pdf)[8:]:
            spans = [s for b in page.get_text("dict")["blocks"] for line in b.get("lines", [])
                     for s in line["spans"] if s["text"].strip() == "B" and s["color"] == 0]
            assert len(spans) == 2, f"second-line B split or duplicated: {spans}"
            assert abs(spans[0]["origin"][1] - spans[1]["origin"][1]) < 0.2, "second-line B moved vertically"
            pix = page.get_pixmap(matrix=pymupdf.Matrix(4, 4), alpha=False)
            raw = pix.samples
            ink = []
            for x in [100, 300]:
                points = set()
                for y in range(190 * 4, 270 * 4):
                    for dx in range(20 * 4):
                        offset = (y * pix.width + x * 4 + dx) * pix.n
                        if max(raw[offset:offset + 3]) < 150:
                            points.add((dx, y))
                assert points, "second-line B disappeared"
                ink.append(points)
            assert abs(min(y for _, y in ink[0]) - min(y for _, y in ink[1])) <= 1, "second-line B lost its top"
            assert len(ink[0] ^ ink[1]) <= max(8, len(ink[1]) * 0.05), "second-line B ink differs from explicit-break control"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default=os.environ.get("OFFICE_BIN"))
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--pdf", type=Path)
    args = parser.parse_args()
    if args.fixture:
        args.fixture.write_bytes(fixture())
        return
    if args.pdf:
        check(args.pdf)
        print(f"PASS fixed text frames: {args.pdf}")
        return
    if not args.binary:
        parser.error("set --binary or OFFICE_BIN")
    with tempfile.TemporaryDirectory(prefix="office-fixed-box-") as directory:
        docx = Path(directory) / "controls.docx"
        docx.write_bytes(fixture())
        for mode in ["windows", "mac"]:
            pdf = Path(directory) / f"{mode}.pdf"
            result = subprocess.run([args.binary, "--convert", str(docx), str(pdf)],
                                    env=os.environ | {"OFFICE_WORD_FONTS": mode, "OFFICE_FONT_SOURCE": "bundled"},
                                    capture_output=True, text=True)
            assert result.returncode == 0, result.stdout + result.stderr
            check(pdf)
            print(f"PASS fixed text frames: {mode}, 11 control pages")


if __name__ == "__main__":
    main()
