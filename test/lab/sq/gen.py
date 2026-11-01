#!/usr/bin/env python3
"""Lab sq (Windows 01QbbApP, for amd-1): how far may CJK-Latin autospace / Latin word space shrink on a justified line so Word takes one more character?
usage:
  gen.py cal OUTDIR            one doc per (csc, compat): every line T left-aligned, natural (the width W of T is measured from the print)
  gen.py test OUTDIR WIDTHS    docs per (container, csc, compat): T followed by filler U, justified, measure M = W - delta (delta 1.0/1.6/2.2/3.0)
Line T = ideograph run ending in the ideograph 經 (U starts with 後); kinds: L letters between ideographs (k letters = 2k autospaces),
S Latin words with k word spaces inside a CJK context, B letters with spaces ("A B", "A B C", "A B C D"), D digit runs "65" between ideographs, P pure Latin (ends in a word).
Sizes 10 and 16 pt, 標楷體 eastAsia / Times New Roman Latin, lang zh-TW. Containers: body (right indent), cell (cell width M), box (inline text box width M)."""
import sys, os, json, zipfile
POOL = "各等級全體訓練單位之招募兼具豐富政府機關辦理考核成績優良人員獎勵措施"
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
NS = (W_ + ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
SIZES = {10: 26, 16: 17}      # pt -> number of ideographs in the base run
DELTAS = (1.0, 1.6, 2.2, 3.0)
KINDS = [("L", 1), ("L", 2), ("L", 3), ("S", 1), ("S", 2), ("S", 3), ("B", 1), ("B", 2), ("B", 3), ("D", 1), ("D", 2), ("D", 3), ("P", 0)]


def line_text(kind, k, n):
    base = [POOL[i % len(POOL)] for i in range(n)]
    base = base[:-1] + ["經"]
    ins = {"L": ["A", "B", "C"], "D": ["65", "72", "83"], "S": ["Ab cd ef gh"], "B": ["A B C D"]}
    if kind == "P":
        return "The quick brown fox jumps over the lazy dogs again today"
    if kind == "S":
        words = ["Ab", "cd", "ef", "gh"][:k + 1]
        blk = " ".join(words)
        pos = [n // 2]
        out = base[:pos[0]] + [blk] + base[pos[0]:]
        return "".join(out)
    if kind == "B":
        blk = " ".join(["A", "B", "C", "D"][:k + 1])
        pos = n // 2
        return "".join(base[:pos] + [blk] + base[pos:])
    # L / D: k insertions spread
    items = ins[kind][:k]
    step = n // (k + 1)
    out = []
    j = 0
    for i, c in enumerate(base):
        out.append(c)
        if j < k and i + 1 == step * (j + 1):
            out.append(items[j]); j += 1
    return "".join(out)


def lines():
    out = []
    for sz, n in SIZES.items():
        for kind, k in KINDS:
            out.append((f"{kind}{k}-s{sz}", sz, line_text(kind, k, n if kind != "P" else 0), kind))
    return out


def run(text, sz):
    h = sz * 2
    return (f'<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="標楷體"/><w:sz w:val="{h}"/><w:szCs w:val="{h}"/><w:lang w:eastAsia="zh-TW"/></w:rPr>'
            f'<w:t xml:space="preserve">{text}</w:t></w:r>')


def para(text, sz, jc="left", rind=0, ppr_extra=""):
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="0" w:right="{rind}"/><w:jc w:val="{jc}"/>{ppr_extra}</w:pPr>{run(text, sz)}</w:p>')


def filler(kind):
    return " and then more words follow here to fill the rest of this paragraph" if kind == "P" else "後續文字繼續排版使用國家政府機關辦理考核成績優良人員獎勵措施之規定事項"


def package(path, body, csc, compat):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
    styles = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W_}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="標楷體" w:cs="Times New Roman"/>'
              '<w:sz w:val="20"/><w:szCs w:val="20"/><w:lang w:val="en-US" w:eastAsia="zh-TW"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {W_}><w:characterSpacingControl w:val="{csc}"/><w:compat>'
                f'<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{compat}"/></w:compat></w:settings>')
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    drels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
             '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
             '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", document), ("word/styles.xml", styles), ("word/settings.xml", settings), ("word/_rels/document.xml.rels", drels)):
            z.writestr(n, v)


def cell_wrap(inner, mtw):
    return (f'<w:tbl><w:tblPr><w:tblW w:w="{mtw}" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            f'<w:tblGrid><w:gridCol w:w="{mtw}"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="{mtw}" w:type="dxa"/></w:tcPr>{inner}</w:tc></w:tr></w:tbl><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>')


def box_wrap(inner, mtw, n):
    emu = int(mtw * 635)
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{emu}" cy="1270000"/>'
            f'<wp:docPr id="{n}" name="Box {n}"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp><wps:cNvSpPr txBox="1"/>'
            f'<wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{emu}" cy="1270000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr>'
            f'<wps:txbx><w:txbxContent>{inner}</w:txbxContent></wps:txbx><wps:bodyPr lIns="0" tIns="0" rIns="0" bIns="0" wrap="square"><a:noAutofit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')


if __name__ == "__main__":
    mode, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    L = lines()
    if mode == "cal":
        json.dump([(k, sz, t) for k, sz, t, _ in L], open(os.path.join(out, "lines.json"), "w", encoding="utf8"), ensure_ascii=False)
        for csc in ("compressPunctuation", "doNotCompress"):
            for compat in (14, 15):
                body = ''.join(para(t, sz) for _, sz, t, _ in L)
                package(os.path.join(out, f"cal-{csc[:3]}-m{compat}.docx"), body, csc, compat)
                print(f"cal-{csc[:3]}-m{compat}")
    else:
        widths = json.load(open(sys.argv[3]))   # {"com-m14": {"L1-s10": W, ...}, ...}
        for cont in ("body", "cell", "box"):
            for csc in ("compressPunctuation", "doNotCompress"):
                for compat in (14, 15):
                    if cont == "box" and compat == 14:
                        continue
                    tag = f"{csc[:3]}-m{compat}"
                    W = widths[tag]
                    body = ''
                    n = 0
                    for key, sz, t, kind in L:
                        for d in DELTAS:
                            n += 1
                            M = W[key] - d
                            mtw = round(M * 20)
                            txt = t + filler(kind)
                            if cont == "body":
                                body += para(txt, sz, "both", 9026 - mtw)
                            elif cont == "cell":
                                body += cell_wrap(para(txt, sz, "both"), mtw)
                            else:
                                body += box_wrap(para(txt, sz, "both"), mtw, n)
                    package(os.path.join(out, f"sq-{cont}-{tag}.docx"), body, csc, compat)
                    print(f"sq-{cont}-{tag}")
