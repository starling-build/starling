#!/usr/bin/env python3
"""Structural check of an OOXML package (.docx, .pptx, .xlsx), format-agnostic.

    test/ooxml-check.py FILE...

What any consumer needs before it reads a single part: a sound zip, every part
with a content type, every relationship target present, every r:id/r:embed/
r:link in a part naming a relationship of that part, and well-formed XML.
Exit 1 when any file has a problem. The format-specific checks (duplicate
shape ids, a layout for every slide...) stay in test/pptx-check.py.
"""
import posixpath
import re
import sys
import zipfile
from xml.etree import ElementTree as ET

REF = re.compile(r'\br:(?:id|embed|link|pict|dm|lo|qs|cs|href)="([^"]*)"')


def check(path):
    problems = []
    try:
        z = zipfile.ZipFile(path)
        bad = z.testzip()
        if bad:
            problems.append(f"zip: bad entry {bad}")
    except zipfile.BadZipFile as e:
        return [f"zip: {e}"]
    names = set(z.namelist())
    if "[Content_Types].xml" not in names:
        return ["no [Content_Types].xml"]
    ct = ET.fromstring(z.read("[Content_Types].xml"))
    defaults = {e.get("Extension").lower() for e in ct if e.tag.endswith("Default")}
    overrides = {e.get("PartName") for e in ct if e.tag.endswith("Override")}
    for n in sorted(names):
        if n.endswith("/") or n == "[Content_Types].xml":
            continue
        ext = n.rsplit(".", 1)[-1].lower() if "." in n else ""
        if "/" + n not in overrides and ext not in defaults:
            problems.append(f"no content type: {n}")
    for o in sorted(overrides):
        if o[1:] not in names:
            problems.append(f"override for missing part: {o}")
    for n in sorted(names):
        if n.endswith(".xml") or n.endswith(".rels"):
            try:
                ET.fromstring(z.read(n))
            except ET.ParseError as e:
                problems.append(f"{n}: not well-formed: {e}")
    for n in sorted(names):
        if not n.endswith(".rels"):
            continue
        d = posixpath.dirname(posixpath.dirname(n))
        base = posixpath.basename(n)
        src = "" if base == ".rels" else posixpath.join(d, base[:-5])
        try:
            rels = ET.fromstring(z.read(n))
        except ET.ParseError:
            continue
        ids = set()
        for r in rels:
            ids.add(r.get("Id"))
            if r.get("TargetMode") == "External":
                continue
            t = r.get("Target") or ""
            t = t[1:] if t.startswith("/") else posixpath.normpath(posixpath.join(d, t))
            if t not in names:
                problems.append(f"{n}: {r.get('Id')} -> missing {t}")
        if src and src in names and src.endswith(".xml"):
            xml = z.read(src).decode("utf-8", "replace")
            for ref in set(REF.findall(xml)):
                # Office itself writes r:id="" on a media poster frame's action.
                if ref and ref not in ids:
                    problems.append(f"{src}: r:id {ref} has no relationship")
    return problems


def main():
    bad = 0
    for path in sys.argv[1:]:
        problems = check(path)
        print(f"{path}: {'ok' if not problems else str(len(problems)) + ' problem(s)'}")
        for p in problems[:30]:
            print("   ", p)
        bad += bool(problems)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
