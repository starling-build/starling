#!/usr/bin/env python3
"""Word controls for a single grid line above a page-anchored floating table.

Ten full-width Arial controls measure vertical clearance, including empty,
mixed-size, grid-off and explicit-height paragraphs. Two multiline controls
only require that later glyphs stay clear of the table: their exact wrapping
is a separate, preexisting gap. No platform-installed CJK font is needed.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED


def fixture(path):
    spec = importlib.util.spec_from_file_location(
        "seed", Path(__file__).with_name("office-opener-fit.py")
    )
    seed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(seed)
    buf = io.BytesIO()
    seed.fixture(buf)
    with ZipFile(buf) as z:
        parts = {n: z.read(n) for n in z.namelist()}
    W = seed.W
    cases = [
        ("grid-under", 94, [("X", 12)], "grid"),
        ("grid-above", 98, [("X", 12)], "grid"),
        ("grid-clear", 110, [("X", 12)], "grid"),
        ("grid-empty", 98, [], "grid"),
        ("mixed-small-first", 98, [("X", 12), ("Y", 24)], "grid"),
        ("mixed-big-first", 98, [("X", 24), ("Y", 12)], "grid"),
        ("mixed-clear", 106, [("X", 12), ("Y", 24)], "grid"),
        ("grid-off", 94, [("X", 12)], "off"),
        ("exact-under", 98, [("X", 12)], "exact"),
        ("exact-clear", 110, [("X", 12)], "exact"),
        ("multiline", 98, [("X\nY", 12)], "grid"),
        ("multiline-larger-second", 98, [("X", 12), ("\nY", 24)], "grid"),
    ]
    sect = (
        '<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="12240" w:h="15840"/>'
        '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/>'
        '<w:docGrid w:type="lines" w:linePitch="720"/></w:sectPr>'
    )

    def run(text, size):
        content = text.replace("\n", "</w:t><w:br/><w:t>")
        return (
            f'<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
            f'<w:sz w:val="{size*2}"/></w:rPr><w:t>{content}</w:t></w:r>'
        )

    body = []
    for i, (name, y, runs, mode) in enumerate(cases):
        borders = "".join(
            f'<w:{s} w:val="single" w:sz="4"/>' for s in ["top", "left", "bottom", "right"]
        )
        body.append(
            f'<w:tbl><w:tblPr><w:tblpPr w:vertAnchor="page" w:horzAnchor="margin" w:tblpY="{y*20}"/>'
            f'<w:tblW w:type="dxa" w:w="9360"/><w:tblLayout w:type="fixed"/>'
            f'<w:tblBorders>{borders}</w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="9360"/></w:tblGrid>'
            f'<w:tr><w:trPr><w:trHeight w:val="2400" w:hRule="exact"/></w:trPr><w:tc><w:tcPr>'
            f'<w:tcW w:type="dxa" w:w="9360"/></w:tcPr><w:p><w:pPr><w:snapToGrid w:val="0"/>'
            f'</w:pPr>{run("TABLE",12)}</w:p></w:tc></w:tr></w:tbl>'
        )
        extra = (
            '<w:snapToGrid w:val="0"/>'
            if mode == "off"
            else '<w:spacing w:line="720" w:lineRule="exact"/>'
            if mode == "exact"
            else ""
        )
        body.append(
            "<w:p><w:pPr>" + extra + "</w:pPr>" + "".join(run(t, s) for t, s in runs) + "</w:p>"
        )
        body.append(
            '<w:p><w:pPr><w:snapToGrid w:val="0"/>'
            + (sect if i < len(cases) - 1 else "")
            + "</w:pPr>"
            + run("AFTER " + name, 12)
            + "</w:p>"
        )
    body.append(sect)
    parts["word/document.xml"] = (
        f'<w:document xmlns:w="{W}"><w:body>' + "".join(body) + "</w:body></w:document>"
    )
    parts[
        "word/styles.xml"
    ] = f'<w:styles xmlns:w="{W}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>'
    parts["word/fontTable.xml"] = f'<w:fonts xmlns:w="{W}"><w:font w:name="Arial"/></w:fonts>'
    for n in ["word/fonts/opener.odttf", "word/_rels/fontTable.xml.rels"]:
        parts.pop(n, None)
    with ZipFile(path, "w", ZIP_DEFLATED) as z:
        for n, b in parts.items():
            z.writestr(n, b)


def check(path):
    import pymupdf

    names = [
        "grid-under",
        "grid-above",
        "grid-clear",
        "grid-empty",
        "mixed-small-first",
        "mixed-big-first",
        "mixed-clear",
        "grid-off",
        "exact-under",
        "exact-clear",
        "multiline",
        "multiline-larger-second",
    ]
    # Baselines from a fresh Word print of the exact fixture package, in pt.
    anchors = [236.88, 94.32, 94.32, None, 245.28, 245.28, 98.88, 83.28, 247.20, 100.80]
    after = [261.84, 229.68, 241.68, 229.68, 265.68, 265.68, 237.84, 225.84, 265.68, 241.68]
    table = [
        105.84,
        109.68,
        121.68,
        109.68,
        109.68,
        109.68,
        117.84,
        105.84,
        109.68,
        121.68,
        109.68,
        109.68,
    ]
    with pymupdf.open(path) as pdf:
        assert len(pdf) == 12, f"{path}: expected 12 pages, got {len(pdf)}"
        for n, page in enumerate(pdf):
            lines = []
            for block in page.get_text("dict")["blocks"]:
                for line in block.get("lines", []):
                    text = "".join(span["text"] for span in line["spans"]).strip()
                    if text:
                        lines.append((text, line["spans"][0]["origin"]))
            anchor = (
                ["XY"] if n in (4, 5, 6) else [] if n == 3 else ["X", "Y"] if n >= 10 else ["X"]
            )
            wanted = ["TABLE", "AFTER " + names[n]] + anchor
            assert sorted(t for t, _ in lines) == sorted(
                wanted
            ), f"page {n+1}: unexpected text {lines}"
            positions = dict(lines)
            assert abs(positions["TABLE"][1] - table[n]) < 0.75, f"page {n+1}: table moved"
            if n < 10:
                expected = {"AFTER " + names[n]: after[n]}
                if anchor:
                    expected[anchor[0]] = anchors[n]
                for text, y in expected.items():
                    x, actual = positions[text]
                    assert (
                        abs(x - 72) < 0.75 and abs(actual - y) < 0.75
                    ), f"page {n+1} {text}: expected (72, {y}), got {(x, actual)}"
            else:
                # Word puts X above and Y below. Until multiline flow is
                # implemented, preserving both below is safe; Y over the
                # table (98..218pt) is a regression, even if X improves.
                assert positions["Y"][1] > 218, f"page {n+1}: later line overlaps the table"
    print("  ✔ Grid/table clearance: 10 Word controls and 2 later-line safeguards pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--fixture", type=Path)
    group.add_argument("--pdf", type=Path)
    group.add_argument("--binary", type=Path)
    args = parser.parse_args()
    if args.fixture:
        fixture(args.fixture)
    elif args.pdf:
        check(args.pdf)
    else:
        with tempfile.TemporaryDirectory(prefix="office-grid-band-") as directory:
            doc = Path(directory) / "grid-band.docx"
            fixture(doc)
            for mode in ["windows", "mac"]:
                pdf = Path(directory) / (mode + ".pdf")
                env = os.environ | {"OFFICE_FONT_SOURCE": "bundled", "OFFICE_WORD_FONTS": mode}
                subprocess.run(
                    [str(args.binary.resolve()), "--convert", str(doc), str(pdf)],
                    env=env,
                    check=True,
                )
                check(pdf)


if __name__ == "__main__":
    main()
