#!/usr/bin/env python3
"""Structural check of a .pptx: what PowerPoint refuses or "repairs".

    test/pptx-check.py file.pptx [...]

Every XML part parses; every internal relationship target exists; every
part has a content type (an Override, or a Default for its extension);
[Content_Types].xml is the first entry; slide ids are unique and >= 256;
shape ids (cNvPr) are unique within each slide; every slide names a
layout, every layout a master. Exit 1 on the first file with problems.
"""
import posixpath, sys, zipfile
import xml.etree.ElementTree as ET

R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
P = "{http://schemas.openxmlformats.org/presentationml/2006/main}"
PR = "{http://schemas.openxmlformats.org/package/2006/relationships}"
CTN = "{http://schemas.openxmlformats.org/package/2006/content-types}"

def rels_path(part):
    d, n = posixpath.split(part)
    return posixpath.join(d, "_rels", n + ".rels") if part else "_rels/.rels"

def check(path):
    problems = []
    z = zipfile.ZipFile(path)
    names = z.namelist()
    if names[0] != "[Content_Types].xml":
        problems.append("[Content_Types].xml is not the first entry")
    trees = {}
    for n in names:
        if n.endswith(".xml") or n.endswith(".rels"):
            try:
                trees[n] = ET.fromstring(z.read(n))
            except ET.ParseError as e:
                problems.append(f"{n}: not well-formed: {e}")
    ct = trees.get("[Content_Types].xml")
    defaults = {d.get("Extension").lower(): d.get("ContentType") for d in ct.iter(CTN + "Default")} if ct is not None else {}
    overrides = {o.get("PartName").lstrip("/"): o.get("ContentType") for o in ct.iter(CTN + "Override")} if ct is not None else {}
    for n in names:
        if n == "[Content_Types].xml" or n.endswith("/"):
            continue
        ext = n.rsplit(".", 1)[-1].lower()
        if n not in overrides and ext not in defaults:
            problems.append(f"{n}: no content type")
    for o in overrides:
        if o not in names:
            problems.append(f"content type for missing part {o}")
    rels_of = {}
    for n in names:
        if not n.endswith(".rels"):
            continue
        d = posixpath.dirname(posixpath.dirname(n))
        owner = posixpath.join(d, posixpath.basename(n)[:-5]) if posixpath.basename(n) != ".rels" else ""
        rels_of[owner] = []
        ids = set()
        for r in trees[n].iter(PR + "Relationship"):
            if r.get("Id") in ids:
                problems.append(f"{n}: duplicate Id {r.get('Id')}")
            ids.add(r.get("Id"))
            rels_of[owner].append(r)
            if r.get("TargetMode") == "External":
                continue
            t = r.get("Target")
            target = t.lstrip("/") if t.startswith("/") else posixpath.normpath(posixpath.join(posixpath.dirname(owner), t))
            if target not in names:
                problems.append(f"{n}: {r.get('Id')} -> missing {target}")
    pres = next((n for n in names if n.endswith("presentation.xml") and "ppt/" in n), None)
    if pres:
        sld_ids = [int(s.get("id")) for s in trees[pres].iter(P + "sldId")]
        if len(sld_ids) != len(set(sld_ids)) or any(i < 256 for i in sld_ids):
            problems.append("slide ids not unique or below 256")
        rid_ok = {r.get("Id") for r in rels_of.get(pres, [])}
        for el in trees[pres].iter():
            v = el.get(R + "id")
            if v and v not in rid_ok:
                problems.append(f"{pres}: r:id {v} has no relationship")
    for n, t in trees.items():
        if not n.startswith("ppt/slides/slide") or not n.endswith(".xml"):
            continue
        ids = [c.get("id") for c in t.iter(P + "cNvPr")]
        dup = {i for i in ids if ids.count(i) > 1}
        if dup:
            problems.append(f"{n}: duplicate shape ids {sorted(dup)}")
        kinds = [r.get("Type").rsplit("/", 1)[-1] for r in rels_of.get(n, [])]
        if "slideLayout" not in kinds:
            problems.append(f"{n}: no layout")
        rid_ok = {r.get("Id") for r in rels_of.get(n, [])}
        for el in t.iter():
            for k, v in el.attrib.items():
                if k.startswith(R) and v not in rid_ok:
                    problems.append(f"{n}: {k[len(R):]}={v} has no relationship")
    for n in names:
        if n.startswith("ppt/slideLayouts/") and n.endswith(".xml"):
            kinds = [r.get("Type").rsplit("/", 1)[-1] for r in rels_of.get(n, [])]
            if "slideMaster" not in kinds:
                problems.append(f"{n}: no master")
    return problems

bad = False
for f in sys.argv[1:]:
    p = check(f)
    print(f"{f}: {'ok' if not p else f'{len(p)} problem(s)'}")
    for x in p[:30]:
        print("   ", x)
    bad |= bool(p)
sys.exit(1 if bad else 0)
