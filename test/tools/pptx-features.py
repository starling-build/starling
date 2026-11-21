#!/usr/bin/env python3
"""pptx-features: the feature fingerprint (docs/plans/slides-corpus.md section 1) of every deck in a folder.

  pptx-features.py DIR [DIR ...] [-o decks.tsv] [-j 16] [--recursive]
  pptx-features.py --new NEW.tsv --old OLD.tsv      # what the new decks add: tokens by decks, old vs new

One TSV row per .pptx: id (file stem), sha256 (first 16), slides, hidden, masters, layouts, tokens
(space-separated; a token counts only where a SLIDE uses it, see below), scripts, langs, sizes
(font sizes in points, distinct), faces (theme fonts resolved, as named in the deck), error.
A deck that does not open as a zip is a row with the error and nothing else.

Token families (prefix:name): ph: placeholder type (and ph-own:/ph-inh: position overridden or inherited),
fit: normAutofit/spAutoFit/none (fit-scale:90/80/70/lt70, fit-lnspc:...), bullet:char/auto-<scheme>/pic, lvl3 bullets,
lnspc:pct/pts, spc:bef/aft, tabs, cols, vert:<kind>, rtl, anchor:<v>, anchorctr, inset, wrap-none, tbl (+merge, +style,
+cellmar), chart:<type> (+labels, +secondary), smartart:<family> (+drawing), pic (+crop, +stretch, +tile, +svg, +alpha),
wordart:<prst>, group, connector, custgeom, geom:<prst>, fill:<solid|grad|patt|pic>, shadow, glow, 3d, ole, media,
equation, field:<type>, hidden-slide, masters>=2, lang:<xx>, script:<name>.
Layer C (rules reached) is not here: it comes from a traced sweep.

Only the Python standard library is used. Slides are read from the slide parts in presentation order
via the rels; layouts and masters are read only for the counts and the theme fonts.
"""
import argparse, collections, hashlib, multiprocessing, os, re, sys, zipfile
import xml.etree.ElementTree as ET

A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
P = "{http://schemas.openxmlformats.org/presentationml/2006/main}"
C = "{http://schemas.openxmlformats.org/drawingml/2006/chart}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"

SCRIPTS = [("hangul", 0xAC00, 0xD7A3), ("hangul", 0x1100, 0x11FF), ("kana", 0x3040, 0x30FF), ("han", 0x4E00, 0x9FFF),
           ("han", 0x3400, 0x4DBF), ("arabic", 0x0600, 0x06FF), ("arabic", 0x0750, 0x077F), ("hebrew", 0x0590, 0x05FF),
           ("thai", 0x0E00, 0x0E7F), ("devanagari", 0x0900, 0x097F), ("bengali", 0x0980, 0x09FF),
           ("cyrillic", 0x0400, 0x04FF), ("greek", 0x0370, 0x03FF), ("lao", 0x0E80, 0x0EFF), ("khmer", 0x1780, 0x17FF)]
LATIN_DIACRITICS = set("áéíóúñãõçêôàâüäöß¿¡ąćęłńśźżčšžřěů")


def scripts_of(text):
    s = set()
    for ch in text:
        o = ord(ch)
        if o < 0x80:
            continue
        for name, lo, hi in SCRIPTS:
            if lo <= o <= hi:
                s.add(name)
                break
        else:
            if ch.lower() in LATIN_DIACRITICS:
                s.add("latin-diacritics")
    return s


def bucket_scale(v):
    # fontScale / lnSpcReduction are in 1/1000 percent
    p = v / 1000.0
    return "90" if p >= 90 else "80" if p >= 80 else "70" if p >= 70 else "lt70"


def read_xml(z, name):
    try:
        return ET.fromstring(z.read(name))
    except Exception:
        return None


def rels_of(z, part):
    d, f = os.path.split(part)
    rn = f"{d}/_rels/{f}.rels"
    out = {}
    try:
        for r in ET.fromstring(z.read(rn)):
            tgt = r.get("Target", "")
            if r.get("TargetMode") == "External":
                out[r.get("Id")] = (r.get("Type", ""), tgt)
                continue
            path = os.path.normpath(os.path.join(d, tgt)) if not tgt.startswith("/") else tgt.lstrip("/")
            out[r.get("Id")] = (r.get("Type", ""), path)
    except Exception:
        pass
    return out


def slide_order(z):
    names = set(z.namelist())
    pres = read_xml(z, "ppt/presentation.xml")
    rels = rels_of(z, "ppt/presentation.xml")
    order = []
    if pres is not None:
        for sid in pres.iter(P + "sldId"):
            t = rels.get(sid.get(R + "id"))
            if t and t[1] in names:
                order.append(t[1])
    if not order:
        order = sorted((n for n in names if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)),
                       key=lambda n: int(re.findall(r"\d+", n)[-1]))
    return order


def theme_faces(z):
    faces = set()
    for n in z.namelist():
        if re.fullmatch(r"ppt/theme/theme\d+\.xml", n):
            t = read_xml(z, n)
            if t is None:
                continue
            fs = t.find(f".//{A}fontScheme")
            if fs is None:
                continue
            for kind in ("majorFont", "minorFont"):
                f = fs.find(A + kind)
                if f is None:
                    continue
                for tag in ("latin", "ea", "cs"):
                    e = f.find(A + tag)
                    if e is not None and e.get("typeface"):
                        faces.add(f"{kind[:3]}-{tag}:{e.get('typeface')}")
    return faces


def slide_tokens(root, tok, text, sizes, faces, langs):
    for el in root.iter():
        tag = el.tag
        if not isinstance(tag, str):
            continue
        if tag == P + "ph":
            t = el.get("type") or "body"
            tok.add("ph:" + t)
        elif tag == P + "sp":
            ph = el.find(f"{P}nvSpPr/{P}nvPr/{P}ph")
            if ph is not None:
                own = el.find(f"{P}spPr/{A}xfrm") is not None
                tok.add(("ph-own:" if own else "ph-inh:") + (ph.get("type") or "body"))
            geom = el.find(f"{P}spPr/{A}prstGeom")
            if geom is not None and geom.get("prst") not in (None, "rect"):
                tok.add("geom:" + geom.get("prst"))
            if el.find(f"{P}spPr/{A}custGeom") is not None:
                tok.add("custgeom")
            if el.get("useBgFill"):
                tok.add("fill:bg")
        elif tag == P + "grpSp":
            tok.add("group")
        elif tag == P + "cxnSp":
            tok.add("connector")
        elif tag == P + "pic":
            tok.add("pic")
            bf = el.find(f"{P}blipFill")
            if bf is not None:
                sr = bf.find(A + "srcRect")
                if sr is not None and any(sr.get(k) not in (None, "0") for k in "lrtb"):
                    tok.add("pic:crop")
                if bf.find(A + "stretch") is not None:
                    tok.add("pic:stretch")
                if bf.find(A + "tile") is not None:
                    tok.add("pic:tile")
        elif tag == A + "alphaModFix":
            tok.add("pic:alpha")
        elif tag.endswith("}svgBlip"):
            tok.add("pic:svg")
        elif tag == P + "oleObj":
            tok.add("ole")
        elif tag == A + "videoFile" or tag == A + "audioFile" or tag.endswith("}media"):
            tok.add("media")
        elif tag == A + "tbl":
            tok.add("tbl")
            pr = el.find(A + "tblPr")
            if pr is not None and pr.find(A + "tableStyleId") is not None:
                tok.add("tbl:style")
        elif tag == A + "tc":
            if el.get("gridSpan") or el.get("rowSpan") or el.get("hMerge") or el.get("vMerge"):
                tok.add("tbl:merge")
            tcp = el.find(A + "tcPr")
            if tcp is not None and any(tcp.get(k) for k in ("marL", "marR", "marT", "marB")):
                tok.add("tbl:cellmar")
        elif tag == A + "graphicData":
            uri = el.get("uri", "")
            if uri.endswith("/chart"):
                tok.add("chart")
            elif "diagram" in uri:
                tok.add("smartart")
            elif uri.endswith("/table"):
                pass
        elif tag == A + "normAutofit":
            tok.add("fit:norm")
            fs = el.get("fontScale")
            if fs:
                tok.add("fit-scale:" + bucket_scale(float(fs)))
            lr = el.get("lnSpcReduction")
            if lr:
                tok.add("fit-lnspc:" + bucket_scale(100000 - float(lr)))
        elif tag == A + "spAutoFit":
            tok.add("fit:sp")
        elif tag == A + "noAutofit":
            tok.add("fit:none")
        elif tag == A + "bodyPr":
            v = el.get("vert")
            if v and v != "horz":
                tok.add("vert:" + v)
            if el.get("rtlCol") == "1":
                tok.add("rtl")
            if el.get("numCol") and el.get("numCol") != "1":
                tok.add("cols")
            if el.get("anchor"):
                tok.add("anchor:" + el.get("anchor"))
            if el.get("anchorCtr") == "1":
                tok.add("anchorctr")
            if any(el.get(k) for k in ("lIns", "rIns", "tIns", "bIns")):
                tok.add("inset")
            if el.get("wrap") == "none":
                tok.add("wrap-none")
        elif tag == A + "prstTxWarp":
            if el.get("prst") != "textNoShape":
                tok.add("wordart:" + (el.get("prst") or "?"))
        elif tag == A + "pPr":
            if el.get("rtl") == "1":
                tok.add("rtl")
            try:
                if int(el.get("lvl") or 0) >= 2 and (el.find(A + "buChar") is not None or el.find(A + "buAutoNum") is not None):
                    tok.add("bullet:lvl3")
            except ValueError:
                pass
        elif tag == A + "buChar":
            tok.add("bullet:char")
        elif tag == A + "buAutoNum":
            tok.add("bullet:auto-" + (el.get("type") or "?"))
        elif tag == A + "buBlip":
            tok.add("bullet:pic")
        elif tag == A + "lnSpc":
            tok.add("lnspc:pts" if el.find(A + "spcPts") is not None else "lnspc:pct")
        elif tag == A + "spcBef":
            tok.add("spc:bef")
        elif tag == A + "spcAft":
            tok.add("spc:aft")
        elif tag == A + "tabLst":
            if len(el):
                tok.add("tabs")
        elif tag in (A + "gradFill", A + "pattFill", A + "blipFill"):
            tok.add({A + "gradFill": "fill:grad", A + "pattFill": "fill:patt", A + "blipFill": "fill:pic"}[tag])
        elif tag == A + "outerShdw" or tag == A + "innerShdw":
            tok.add("shadow")
        elif tag == A + "glow":
            tok.add("glow")
        elif tag in (A + "scene3d", A + "sp3d"):
            if len(el):
                tok.add("3d")
        elif tag == A + "fld":
            tok.add("field:" + (el.get("type") or "?"))
        elif tag.endswith("}oMath") or tag.endswith("}oMathPara"):
            tok.add("equation")
        elif tag == A + "t":
            if el.text:
                text.append(el.text)
        elif tag in (A + "rPr", A + "endParaRPr", A + "defRPr"):
            if el.get("sz"):
                try:
                    sizes.add(int(el.get("sz")) / 100.0)
                except ValueError:
                    pass
            if el.get("lang"):
                langs.add(el.get("lang"))
            for f in ("latin", "ea", "cs", "sym"):
                e = el.find(A + f)
                if e is not None and e.get("typeface"):
                    faces.add(e.get("typeface"))
    # solid fills on shapes (not run colour): count a shape's own solidFill
    for sp in root.iter(P + "spPr"):
        if sp.find(A + "solidFill") is not None:
            tok.add("fill:solid")


def chart_tokens(z, part, tok):
    root = read_xml(z, part)
    if root is None:
        return
    kinds = {"barChart": "bar", "bar3DChart": "bar3d", "lineChart": "line", "line3DChart": "line3d", "pieChart": "pie",
             "pie3DChart": "pie3d", "doughnutChart": "doughnut", "areaChart": "area", "area3DChart": "area3d",
             "scatterChart": "scatter", "bubbleChart": "bubble", "radarChart": "radar", "stockChart": "stock",
             "surfaceChart": "surface", "ofPieChart": "ofpie"}
    found = [kinds[e.tag.rpartition("}")[2]] for e in root.iter() if isinstance(e.tag, str) and e.tag.rpartition("}")[2] in kinds]
    for k in set(found):
        tok.add("chart:" + k)
    if len(set(found)) > 1:
        tok.add("chart:combo")
    if root.find(f".//{C}dLbls") is not None and any(e.get("val") == "1" for e in root.iter(C + "showVal")):
        tok.add("chart:labels")
    if len(list(root.iter(C + "valAx"))) > 1:
        tok.add("chart:secondary")


def analyse(path):
    row = {"id": os.path.splitext(os.path.basename(path))[0], "sha": "", "slides": 0, "hidden": 0, "masters": 0, "layouts": 0,
           "tokens": "", "scripts": "", "langs": "", "sizes": "", "faces": "", "error": ""}
    try:
        with open(path, "rb") as f:
            row["sha"] = hashlib.sha256(f.read()).hexdigest()[:16]
        z = zipfile.ZipFile(path)
        names = z.namelist()
    except Exception as e:
        row["error"] = "not-a-zip:" + str(e)[:40].replace("\t", " ")
        return row
    tok, text, sizes, faces, langs = set(), [], set(), set(), set()
    try:
        order = slide_order(z)
        row["slides"] = len(order)
        masters = [n for n in names if re.fullmatch(r"ppt/slideMasters/slideMaster\d+\.xml", n)]
        row["masters"] = len(masters)
        row["layouts"] = len([n for n in names if re.fullmatch(r"ppt/slideLayouts/slideLayout\d+\.xml", n)])
        if len(masters) >= 2:
            tok.add("masters>=2")
        used_layouts = set()
        for n in order:
            root = read_xml(z, n)
            if root is None:
                tok.add("bad-xml")
                continue
            if root.get("show") == "0":
                row["hidden"] += 1
                tok.add("hidden-slide")
            slide_tokens(root, tok, text, sizes, faces, langs)
            rels = rels_of(z, n)
            for typ, tgt in rels.values():
                tl = typ.rpartition("/")[2]
                if tl == "slideLayout":
                    lay = read_xml(z, tgt) if tgt in names else None
                    if lay is not None:
                        used_layouts.add(lay.get("type") or "cust")
                elif tl == "chart" and tgt in names:
                    chart_tokens(z, tgt, tok)
                elif tl == "diagramLayout":
                    lay = read_xml(z, tgt) if tgt in names else None
                    base = ((lay.get("uniqueId") if lay is not None else "") or tgt).rpartition("/")[2].lower()
                    fam = ("list" if "list" in base else "process" if "process" in base else "cycle" if "cycle" in base
                           else "hierarchy" if ("hierarchy" in base or "orgchart" in base) else "other")
                    tok.add("smartart:" + fam)
                elif tl in ("diagramData", "diagramDrawing") and tgt in names:
                    dx = read_xml(z, tgt)  # the words a SmartArt shows, for the scripts and sizes
                    if dx is not None:
                        slide_tokens(dx, set(), text, sizes, faces, langs)
                elif tl == "diagramDrawing":
                    tok.add("smartart:drawing")
                elif tl == "image" and tgt.lower().endswith(".svg"):
                    tok.add("pic:svg")
        for l in used_layouts:
            tok.add("layout:" + l)
        faces |= theme_faces(z)
    except Exception as e:  # keep what we have
        row["error"] = "partial:" + type(e).__name__
    joined = "".join(text)
    for s in scripts_of(joined):
        tok.add("script:" + s)
    for l in langs:
        tok.add("lang:" + l.split("-")[0].lower())
    row["scripts"] = " ".join(sorted(s for s in (t[7:] for t in tok if t.startswith("script:"))))
    row["langs"] = " ".join(sorted(langs))
    row["sizes"] = " ".join(f"{s:g}" for s in sorted(sizes))
    row["faces"] = "|".join(sorted(faces))
    row["tokens"] = " ".join(sorted(tok))
    return row


COLS = ["id", "sha", "slides", "hidden", "masters", "layouts", "tokens", "scripts", "langs", "sizes", "faces", "error"]


def find_decks(dirs, recursive):
    out = []
    for d in dirs:
        if os.path.isfile(d):
            out.append(d)
            continue
        if recursive:
            for root, _, files in os.walk(d):
                out += [os.path.join(root, f) for f in files if f.lower().endswith(".pptx")]
        else:
            out += [os.path.join(d, f) for f in os.listdir(d) if f.lower().endswith(".pptx")]
    return sorted(out)


def read_tsv(p):
    rows = []
    with open(p, encoding="utf8") as f:
        head = f.readline().rstrip("\n").split("\t")
        for line in f:
            v = line.rstrip("\n").split("\t")
            rows.append(dict(zip(head, v + [""] * (len(head) - len(v)))))
    return rows


def compare(new_p, old_p, out=sys.stdout):
    new, old = read_tsv(new_p), read_tsv(old_p)
    def count(rows):
        c = collections.Counter()
        for r in rows:
            for t in set(r["tokens"].split()):
                c[t] += 1
        return c
    cn, co = count(new), count(old)
    old_sha = {r["sha"] for r in old}
    dup = sum(1 for r in new if r["sha"] in old_sha)
    print(f"new decks {len(new)} (slides {sum(int(r['slides'] or 0) for r in new)}), old decks {len(old)} "
          f"(slides {sum(int(r['slides'] or 0) for r in old)}); new decks already in old by hash: {dup}", file=out)
    print(f"\ntokens NEW decks have and OLD has none ({sum(1 for t in cn if t not in co)}):", file=out)
    for t, n in sorted(((t, n) for t, n in cn.items() if t not in co), key=lambda x: -x[1]):
        print(f"  {t:36s} {n:4d}", file=out)
    print("\ntokens OLD has in fewer than 5 decks that NEW lifts to 5 or more:", file=out)
    for t, n in sorted(cn.items(), key=lambda x: -x[1]):
        if t in co and co[t] < 5 and co[t] + n >= 5:
            print(f"  {t:36s} old {co[t]:3d}  new {n:3d}", file=out)
    print("\nper decks (new / old), top 40 by new:", file=out)
    for t, n in cn.most_common(40):
        print(f"  {t:36s} {n:4d} / {co.get(t, 0):4d}", file=out)
    miss = [t for t, n in co.items() if n >= 5 and t not in cn]
    print(f"\ntokens in 5+ old decks and in no new deck: {' '.join(sorted(miss))}", file=out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="*")
    ap.add_argument("-o", "--out", default="-")
    ap.add_argument("-j", type=int, default=16)
    ap.add_argument("--recursive", action="store_true")
    ap.add_argument("--new")
    ap.add_argument("--old")
    a = ap.parse_args()
    if a.new or a.old:
        if not (a.new and a.old):
            ap.error("--new and --old go together")
        compare(a.new, a.old)
        return
    if not a.dirs:
        ap.error("give a folder")
    decks = find_decks(a.dirs, a.recursive)
    with multiprocessing.Pool(max(1, a.j)) as pool:
        rows = pool.map(analyse, decks, chunksize=4)
    out = sys.stdout if a.out == "-" else open(a.out, "w", encoding="utf8")
    out.write("\t".join(COLS) + "\n")
    for r in rows:
        out.write("\t".join(str(r[c]) for c in COLS) + "\n")
    if out is not sys.stdout:
        out.close()
    bad = sum(1 for r in rows if r["error"])
    print(f"pptx-features: {len(rows)} decks, {sum(r['slides'] for r in rows)} slides, {bad} with an error", file=sys.stderr)


if __name__ == "__main__":
    main()
