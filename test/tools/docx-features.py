#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/tools/docx-features.py [--out FILE] [--docs DIR] [KEY ...] — what each
corpus document is made of, one row a document.

A layout fix touches some documents and not others: a rule for paragraphs
opened by a page break can only move a document that has one. Sweeping all
756 to find out costs 25-50 minutes; this reads the packages instead (about
ten seconds) and writes a row of features per document, so that
test/tools/docx-select.py can say which documents a change could reach.

    test/tools/docx-features.py                 # JSON rows to stdout
    test/tools/docx-features.py --out f.json    # … or to a file
    test/tools/docx-features.py zh-7773163d     # one document, pretty

Rows are keyed by the document's file name without ".docx" (the key the
sweeps, the Word prints and the line matcher use). Numbers are counts of
the element in the body, headers, footers, footnotes and text boxes; a
flag is true when it is not zero. Nothing here is read by the layout: it
is a cheap description of the file, from its XML, with regular
expressions where a parser would be slower and no stricter.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DOCS = os.path.join(ROOT, "test", "corpus", "docx", "docs")
WORD_WIN = os.path.join(ROOT, "test", "corpus", "docx", "word-win")


class Package:
    """A .docx's parts. Read with zipfile; a package whose directory zipfile
    rejects (zh-b0401810's is malformed) is read by unzip instead."""

    def __init__(self, path):
        self.path = path
        self.names = None
        self._zip = None
        try:
            self._zip = zipfile.ZipFile(path)
            self.names = self._zip.namelist()
        except Exception:
            out = subprocess.run(["unzip", "-Z1", path], capture_output=True, text=True).stdout
            self.names = out.splitlines()

    def text(self, name):
        if name not in self.names:
            return ""
        try:
            if self._zip is not None:
                return self._zip.read(name).decode("utf-8", "replace")
        except Exception:
            pass
        return subprocess.run(["unzip", "-p", self.path, name], capture_output=True).stdout.decode("utf-8", "replace")

    def parts(self, prefix):
        return [n for n in self.names if n.startswith(prefix) and n.endswith(".xml")]


def attrs(tag):
    return dict(re.findall(r'([\w:]+)="([^"]*)"', tag))


def on(tag):
    """A toggle element's value: absent w:val is true."""
    v = attrs(tag).get("w:val")
    return v not in ("0", "false", "off")


PARA = re.compile(r"<w:p(?: [^>]*)?>.*?</w:p>", re.S)
PPR = re.compile(r"<w:pPr>.*?</w:pPr>", re.S)
RUN = re.compile(r"<w:r(?: [^>]*)?>(.*?)</w:r>", re.S)


def space_before(spacing):
    """Whether a `w:spacing` tag asks for room above (twips or lines)."""
    a = attrs(spacing)
    return any(int(a.get(k, "0") or 0) > 0 for k in ("w:before", "w:beforeLines")) or a.get("w:beforeAutospacing") == "1"


def style_space_before(styles):
    """styleId -> whether the style, or one it is based on, puts room above
    its paragraphs. (A paragraph's own spacing overrides it, and the
    defaults sit under all.)"""
    own, based = {}, {}
    for m in re.finditer(r'<w:style\b[^>]*w:styleId="([^"]*)"[^>]*>(.*?)</w:style>', styles, re.S):
        sid, body = m.group(1), m.group(2)
        ppr = PPR.search(body)
        sp = re.search(r"<w:spacing\b[^>]*>", ppr.group(0)) if ppr else None
        own[sid] = None if not sp or not re.search(r"w:(?:before|beforeLines|beforeAutospacing)=", sp.group(0)) else space_before(sp.group(0))
        b = re.search(r'<w:basedOn w:val="([^"]*)"', body)
        based[sid] = b.group(1) if b else None
    dd = re.search(r"<w:pPrDefault>.*?</w:pPrDefault>", styles, re.S)
    dsp = re.search(r"<w:spacing\b[^>]*>", dd.group(0)) if dd else None
    default = space_before(dsp.group(0)) if dsp else False
    default_style = re.search(r'<w:style\b[^>]*w:type="paragraph"[^>]*w:default="1"[^>]*w:styleId="([^"]*)"|<w:style\b[^>]*w:default="1"[^>]*w:styleId="([^"]*)"', styles)
    out = {}
    for sid in own:
        seen, cur, val = set(), sid, None
        while cur is not None and cur in own and cur not in seen:
            seen.add(cur)
            if own[cur] is not None:
                val = own[cur]
                break
            cur = based[cur]
        out[sid] = default if val is None else val
    out[None] = out.get((default_style.group(1) or default_style.group(2)) if default_style else None, default)
    return out


def paragraph_features(xml, styles_before=None):
    """Counts over the paragraphs of one part."""
    styles_before = styles_before or {None: False}
    f = dict(paragraphs=0, pagebreak_before=0, pagebreak_first=0, pagebreak_first_before=0, pagebreak_mid=0, empty_paragraphs=0)
    for m in PARA.finditer(xml):
        p = m.group(0)
        f["paragraphs"] += 1
        ppr = PPR.search(p)
        head = ppr.group(0) if ppr else ""
        for t in re.findall(r"<w:pageBreakBefore\b[^>]*/?>", head):
            if on(t):
                f["pagebreak_before"] += 1
        body = p[ppr.end():] if ppr else p
        breaks = [mm.start() for mm in re.finditer(r'<w:br\b[^>]*w:type="page"', body)]
        if breaks:
            # (Opened by it: nothing that draws comes before the first break.)
            first = breaks[0]
            if not re.search(r"<w:t[ >]|<w:drawing|<w:pict|<w:tab/>|<w:sym ", body[:first]):
                f["pagebreak_first"] += 1
                sp = re.search(r"<w:spacing\b[^>]*>", head)
                if sp and re.search(r"w:(?:before|beforeLines|beforeAutospacing)=", sp.group(0)):
                    above = space_before(sp.group(0))
                else:
                    ps = re.search(r'<w:pStyle w:val="([^"]*)"', head)
                    above = styles_before.get(ps.group(1) if ps else None, styles_before.get(None, False))
                if above:
                    f["pagebreak_first_before"] += 1
                f["pagebreak_mid"] += len(breaks) - 1
            else:
                f["pagebreak_mid"] += len(breaks)
        if not re.search(r"<w:t[ >]|<w:drawing|<w:pict|<w:object", body):
            f["empty_paragraphs"] += 1
    return f


def table_depth(xml):
    depth = best = 0
    for m in re.finditer(r"<w:tbl>|</w:tbl>", xml):
        if m.group(0) == "<w:tbl>":
            depth += 1
            best = max(best, depth)
        else:
            depth -= 1
    return best


def features(path):
    z = Package(path)
    body = z.text("word/document.xml")
    styles = z.text("word/styles.xml")
    settings = z.text("word/settings.xml")
    numbering = z.text("word/numbering.xml")
    fonts = z.text("word/fontTable.xml")
    heads = [n for n in z.parts("word/header")]
    foots = [n for n in z.parts("word/footer")]
    side = "".join(z.text(n) for n in heads + foots)
    notes = z.text("word/footnotes.xml") + z.text("word/endnotes.xml")
    everything = body + side + notes
    f = {}

    # --- the file's mode and compatibility switches
    m = re.search(r'<w:compatSetting [^>]*w:name="compatibilityMode"[^>]*>', settings)
    f["mode"] = int(attrs(m.group(0)).get("w:val", "12") or 12) if m else 12
    f["legacy_mode"] = m is None
    compat = re.search(r"<w:compat>(.*?)</w:compat>", settings, re.S)
    f["compat"] = sorted(set(re.findall(r"<w:(\w+)\b", compat.group(1)))) if compat else []
    f["breakrules_off"] = "<w:doNotUseEastAsianBreakRules" in settings
    m = re.search(r"<w:characterSpacingControl\b[^>]*>", settings)
    f["char_spacing"] = attrs(m.group(0)).get("w:val", "") if m else ""
    f["fe_layout"] = "<w:useFELayout" in settings
    f["no_punct_kerning"] = "<w:noPunctuationKerning" in settings

    # --- the grid, by section (the last is the body's)
    grids = [attrs(t) for t in re.findall(r"<w:docGrid\b[^>]*>", body)]
    g = grids[-1] if grids else {}
    f["grid"] = g.get("w:type", "none")
    f["grid_chars"] = int(g.get("w:charSpace", "0") or 0)
    f["grid_line"] = int(g.get("w:linePitch", "0") or 0)
    f["grids"] = sorted({x.get("w:type", "none") for x in grids})

    # --- the East Asian line rules, paragraph by paragraph
    def count_off(name):
        return sum(1 for t in re.findall(r"<w:%s\b[^>]*/?>" % name, body + styles) if not on(t))
    def count_on(name):
        return sum(1 for t in re.findall(r"<w:%s\b[^>]*/?>" % name, body + styles) if on(t))
    f["kinsoku_off"] = count_off("kinsoku")
    f["kinsoku_on"] = count_on("kinsoku")
    f["overflow_off"] = count_off("overflowPunct")
    f["overflow_on"] = count_on("overflowPunct")
    f["topline_on"] = count_on("topLinePunct")
    f["topline_off"] = count_off("topLinePunct")
    f["autospace_de_off"] = count_off("autoSpaceDE")
    f["autospace_dn_off"] = count_off("autoSpaceDN")
    f["snap_off"] = count_off("snapToGrid")
    f["wordwrap_off"] = count_off("wordWrap")
    f["jc_distribute"] = len(re.findall(r'<w:jc w:val="distribute"', everything))
    f["jc_both"] = len(re.findall(r'<w:jc w:val="(?:both|thaiDistribute)"', everything))

    # --- languages
    langs_val, langs_ea = set(), set()
    for t in re.findall(r"<w:lang\b[^>]*>", body + styles + side + notes + numbering):
        a = attrs(t)
        if a.get("w:val"):
            langs_val.add(a["w:val"])
        if a.get("w:eastAsia"):
            langs_ea.add(a["w:eastAsia"])
    f["langs"] = sorted(langs_val | langs_ea)
    f["langs_ea"] = sorted(langs_ea)
    dd = re.search(r"<w:docDefaults>.*?</w:docDefaults>", styles, re.S)
    lm = re.search(r"<w:lang\b[^>]*>", dd.group(0)) if dd else None
    f["lang_default_ea"] = attrs(lm.group(0)).get("w:eastAsia", "") if lm else ""
    f["lang_stated"] = bool(langs_ea or langs_val)
    scripts = []
    text = re.sub(r"<[^>]+>", "", body)
    for name, pat in (("han", r"[一-鿿]"), ("kana", r"[぀-ヿ]"), ("hangul", r"[가-힯]"),
                      ("thai", r"[฀-๿]"), ("arabic", r"[؀-ۿ]"), ("hebrew", r"[֐-׿]"),
                      ("cyrillic", r"[Ѐ-ӿ]"), ("latin", r"[A-Za-z]")):
        if re.search(pat, text):
            scripts.append(name)
    f["scripts"] = scripts
    f["rtl"] = any(on(t) for t in re.findall(r"<w:(?:bidi|rtl)\b[^>]*>", everything))
    f["ruby"] = "<w:ruby>" in body
    f["vertical_text"] = bool(re.search(r"<w:textDirection\b|<w:vert\b|w:eastAsianLayout[^>]*w:vert", everything))

    # --- fonts
    named = set()
    for t in re.findall(r"<w:rFonts\b[^>]*>", body + styles + side + notes + numbering):
        for k, v in attrs(t).items():
            if k in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs") and v:
                named.add(v)
    f["fonts"] = sorted(named)
    embedded = set()
    for fm in re.finditer(r'<w:font w:name="([^"]*)"[^>]*>(.*?)</w:font>', fonts, re.S):
        if re.search(r"<w:embed(?:Regular|Bold|Italic|BoldItalic)\b", fm.group(2)):
            embedded.add(fm.group(1))
    f["fonts_embedded"] = sorted(embedded)
    f["font_parts"] = sum(1 for n in z.names if n.startswith("word/fonts/"))

    # --- structure
    f["tables"] = body.count("<w:tbl>")
    f["table_depth"] = table_depth(body)
    f["tables_merged"] = len(re.findall(r'<w:gridSpan w:val="(?:[2-9]|\d\d)"|<w:vMerge\b|<w:hMerge\b', body))
    f["tables_floating"] = body.count("<w:tblpPr")
    f["rows_exact"] = len(re.findall(r'<w:trHeight [^>]*w:hRule="exact"', body))
    f["rows_atleast"] = len(re.findall(r'<w:trHeight (?![^>]*w:hRule="(?:exact|auto)")[^>]*>', body))
    f["table_header_rows"] = body.count("<w:tblHeader")
    f["sections"] = body.count("<w:sectPr")
    f["columns"] = max([1] + [int(attrs(t).get("w:num", "1") or 1) for t in re.findall(r"<w:cols\b[^>]*>", body)])
    f["textboxes"] = everything.count("<w:txbxContent")
    f["vml"] = len(re.findall(r"<v:(?:shape|rect|roundrect|oval|line|group|polyline|curve|imagedata)\b", everything))
    f["picts"] = everything.count("<w:pict")
    f["wordart"] = len(re.findall(r"<v:textpath\b|<a:prstTxWarp\b|prst=\"text(?!Box)", everything))
    f["drawings_inline"] = everything.count("<wp:inline")
    f["drawings_anchor"] = everything.count("<wp:anchor")
    f["wps_shapes"] = everything.count("<wps:wsp")
    f["charts"] = len([n for n in z.names if n.startswith("word/charts/") and n.endswith(".xml") and "/_rels/" not in n])
    f["smartart"] = len([n for n in z.names if n.startswith("word/diagrams/") and "data" in n and n.endswith(".xml")])
    f["equations"] = everything.count("<m:oMath>") + everything.count("<m:oMath ")
    f["images"] = len([n for n in z.names if n.startswith("word/media/")])
    f["footnotes"] = len(re.findall(r"<w:footnote ", z.text("word/footnotes.xml"))) - 2
    f["footnotes"] = max(0, f["footnotes"])
    f["endnotes"] = max(0, len(re.findall(r"<w:endnote ", z.text("word/endnotes.xml"))) - 2)
    f["comments"] = len(re.findall(r"<w:comment ", z.text("word/comments.xml")))
    f["tracked"] = len(re.findall(r"<w:(?:ins|del)\b ", body))
    f["frames"] = body.count("<w:framePr")
    f["dropcaps"] = len(re.findall(r'<w:framePr [^>]*w:dropCap=', body))
    f["sdt"] = body.count("<w:sdt>")
    f["fields"] = len(re.findall(r"<w:fldChar\b[^>]*w:fldCharType=\"begin\"|<w:fldSimple\b", body))
    f["hyperlinks"] = body.count("<w:hyperlink")
    f["tabs"] = len(re.findall(r"<w:tab/>", body))
    f["tab_stops"] = len(re.findall(r"<w:tab w:val=", body))
    f["symbols"] = body.count("<w:sym ")
    f["nobreak_hyphen_or_nbsp"] = len(re.findall(r" |<w:noBreakHyphen", body))

    # --- headers and footers
    def hf_types(tag):
        return sorted({attrs(t).get("w:type", "default") for t in re.findall(r"<w:%sReference\b[^>]*>" % tag, body)})
    f["header_parts"] = len(heads)
    f["footer_parts"] = len(foots)
    f["header_types"] = hf_types("header")
    f["footer_types"] = hf_types("footer")
    f["title_page"] = "<w:titlePg" in body
    f["even_odd"] = "<w:evenAndOddHeaders" in settings
    f["hf_page_field"] = bool(re.search(r"instrText[^>]*>\s*PAGE\b|w:instr=\"\s*PAGE\b", side))
    f["hf_numpages_field"] = bool(re.search(r"instrText[^>]*>\s*NUMPAGES\b|w:instr=\"\s*NUMPAGES\b", side))
    f["hf_frames"] = side.count("<w:framePr")
    f["hf_textboxes"] = side.count("<w:txbxContent") + len(re.findall(r"<v:shape\b|<wps:wsp", side))

    # --- paragraphs
    f.update(paragraph_features(body, style_space_before(styles)))
    f["pagebreak_para"] = (f["pagebreak_before"] + f["pagebreak_first"]) > 0
    f["page_breaks"] = len(re.findall(r'<w:br\b[^>]*w:type="page"', body)) + f["pagebreak_before"]
    f["column_breaks"] = len(re.findall(r'<w:br\b[^>]*w:type="column"', body))
    sp = [attrs(t) for t in re.findall(r"<w:spacing\b[^>]*>", body + styles)]
    f["line_exact"] = sum(1 for a in sp if a.get("w:lineRule") == "exact")
    f["line_atleast"] = sum(1 for a in sp if a.get("w:lineRule") == "atLeast")
    f["line_auto"] = sum(1 for a in sp if "w:line" in a and a.get("w:lineRule", "auto") == "auto")
    f["spacing_lines"] = sum(1 for a in sp if "w:beforeLines" in a or "w:afterLines" in a)
    f["indent_chars"] = len(re.findall(r"<w:ind\b[^>]*(?:Chars|hangingChars|firstLineChars)=", body + styles))
    f["lists"] = body.count("<w:numPr>")
    f["list_formats"] = sorted(set(re.findall(r'<w:numFmt w:val="(\w+)"', numbering)))
    f["list_levels"] = 1 + max([0] + [int(x) for x in re.findall(r'<w:ilvl w:val="(\d)"', body)])
    f["styles"] = len(re.findall(r"<w:style ", styles))
    f["char_scale"] = len(re.findall(r'<w:w w:val="(?!100")', body + styles))
    f["char_spacing_runs"] = len(re.findall(r"<w:spacing w:val=", body))
    f["snap_grid_runs"] = len(re.findall(r"<w:snapToGrid", body))
    f["size_pt_max"] = max([0] + [int(x) for x in re.findall(r'<w:sz w:val="(\d+)"', body)]) / 2
    f["size_pt_min"] = min([999] + [int(x) for x in re.findall(r'<w:sz w:val="(\d+)"', body)]) / 2
    f["page_w"] = int(attrs(re.search(r"<w:pgSz\b[^>]*>", body).group(0)).get("w:w", "0") or 0) if "<w:pgSz" in body else 0
    f["landscape"] = bool(re.search(r'<w:pgSz\b[^>]*w:orient="landscape"', body))
    f["bytes"] = os.path.getsize(path)
    return f


def key_of(path):
    return os.path.basename(path)[: -len(".docx")]


def one(path):
    try:
        return key_of(path), features(path)
    except Exception as e:  # (A document that cannot be read has no row to select it by.)
        print(f"{path}: {e}", file=sys.stderr)
        return key_of(path), None


def rows_for(docs, keys=(), jobs=4):
    """The rows of every document in `docs` (or of those `keys` start), by key."""
    names = sorted(n for n in os.listdir(docs) if n.endswith(".docx"))
    if keys:
        names = [n for n in names if any(n.startswith(k) for k in keys)]
    paths = [os.path.join(docs, n) for n in names]
    if jobs > 1 and len(paths) > 8:
        from multiprocessing import Pool
        with Pool(jobs) as pool:
            done = pool.map(one, paths, chunksize=8)
    else:
        done = [one(p) for p in paths]
    return {k: r for k, r in done if r is not None}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("keys", nargs="*", help="documents (a key or a prefix of one); default all")
    ap.add_argument("--out", help="write the rows (JSON) here")
    ap.add_argument("--docs", default=DOCS)
    ap.add_argument("--jobs", type=int, default=4, help="processes (default 4)")
    a = ap.parse_args()
    rows = rows_for(a.docs, a.keys, a.jobs)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            json.dump(rows, fh, ensure_ascii=False, sort_keys=True)
        print(f"{len(rows)} documents -> {a.out}", file=sys.stderr)
    elif a.keys:
        for k, r in rows.items():
            print(k)
            for name in sorted(r):
                print(f"  {name:24} {r[name]}")
    else:
        json.dump(rows, sys.stdout, ensure_ascii=False, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
