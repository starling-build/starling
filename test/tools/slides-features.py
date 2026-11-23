#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""slides-features.py PER_PAGE.tsv — add (or refresh) a `features` column to a round per-page file (amd-8, 2026-11-22).
Per deck and page, read from the slide's own XML (page N = Nth slide of presentation.xml) and its chart parts, comma-separated:
chart chartex table smartart picture emf vertical rtl equation 3d ("-" when none). So one grep ranks a kind of page:
  awk -F'\t' '$7 ~ /chart/ && $6<100' per-page.tsv | sort -t$'\t' -k6 -n | head
Decks are found by file name under the corpus cache (pptx/decks, pptx-full/decks, pptx-pilot/decks)."""
import glob, os, re, sys, zipfile

CC = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus"


def index():
    ix = {}
    for pat in ("pptx/decks/**/*.pptx", "pptx-full/decks/**/*.pptx", "pptx-pilot/decks/**/*.pptx", "pptx-zh/decks/**/*.pptx", "pptx-cjk-r1/decks/**/*.pptx", "pptx-cjk-r3/*/*.pptx"):
        for f in glob.glob(CC + "/" + pat, recursive=True):
            ix.setdefault(os.path.basename(f)[:-5], f)
            if "/pptx-zh/" in f: ix.setdefault("zh-" + os.path.basename(f)[:-5], f)   # round ids of the zh set
    return ix


def rels(z, part):
    d, b = os.path.split(part)
    name = (d + "/_rels/" + b + ".rels") if d else ("_rels/" + b + ".rels")
    try:
        x = z.read(name).decode("utf8", "replace")
    except KeyError:
        return {}
    out = {}
    for m in re.finditer(r"<Relationship\b[^>]*>", x):
        t = m.group(0)
        i = re.search(r'\bId="([^"]*)"', t); g = re.search(r'\bTarget="([^"]*)"', t); ty = re.search(r'\bType="([^"]*)"', t)
        if i and g:
            tg = g.group(1)
            if not tg.startswith("/"):
                tg = os.path.normpath(os.path.join(d, tg))
            out[i.group(1)] = (tg.lstrip("/"), ty.group(1) if ty else "")
    return out


def slides(z):
    try:
        p = z.read("ppt/presentation.xml").decode("utf8", "replace"); r = rels(z, "ppt/presentation.xml")
    except KeyError:
        return []
    return [r[i][0] for i in re.findall(r'<p:sldId\b[^>]*\br:id="([^"]*)"', p) if i in r]


def features(z, part):
    try:
        x = z.read(part).decode("utf8", "replace")
    except KeyError:
        return "-"
    r = rels(z, part); f = set()
    if "drawingml/2006/chart\"" in x or "<c:chart " in x or "<c:chart>" in x: f.add("chart")
    if "chartex" in x: f.add("chartex")
    if "<a:tbl>" in x or "<a:tbl " in x: f.add("table")
    if "drawingml/2006/diagram" in x or "<dgm:" in x: f.add("smartart")
    if "<p:pic>" in x or "<p:pic " in x or "<a:blip " in x: f.add("picture")
    if re.search(r'\bvert="(?!horz")[a-zA-Z0-9]+"', x) and re.search(r"<a:bodyPr\b[^>]*\bvert=\"(vert|vert270|eaVert|wordArtVert|wordArtVertRtl|mongolianVert)\"", x): f.add("vertical")
    if re.search(r'<a:pPr\b[^>]*\brtl="1"', x): f.add("rtl")
    if "<m:oMath" in x or "<a14:m>" in x or "<a14:m " in x: f.add("equation")
    if "<a:sp3d" in x or "<a:scene3d" in x and re.search(r"<a:scene3d>.*?<a:camera prst=\"(?!orthographicFront)", x, re.S) or "model3d" in x: f.add("3d")
    for tg, ty in r.values():
        t = tg.lower()
        if ty.endswith("/image") and (t.endswith(".emf") or t.endswith(".wmf")): f.add("emf"); f.add("picture")
        if ty.endswith("/chart"):
            try:
                c = z.read(tg).decode("utf8", "replace")
                if re.search(r"<c:view3D>|3DChart>", c): f.add("3d")
            except KeyError:
                pass
    return ",".join(sorted(f)) or "-"


def main(path):
    ix = index(); cache = {}
    rows = [l.rstrip("\n").split("\t") for l in open(path)]
    out = []
    for r in rows:
        if r[0].startswith("#"):
            out.append(r); continue
        if r[0] == "deck":
            out.append(r[:6] + ["features"]); continue
        deck, page = r[0], int(r[1])
        if deck not in cache:
            f = ix.get(deck); cache[deck] = None
            if f:
                try:
                    z = zipfile.ZipFile(f); cache[deck] = (z, slides(z))
                except Exception:
                    pass
        c = cache[deck]; ft = "?"
        if c and page <= len(c[1]):
            ft = features(c[0], c[1][page - 1])
        out.append(r[:6] + [ft])
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w") as o:
        for r in out: o.write("\t".join(r) + "\n")
    os.replace(tmp, path)


if __name__ == "__main__":
    main(sys.argv[1])
