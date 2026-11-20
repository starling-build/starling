#!/usr/bin/env python3
"""wordcmp: where does our render differ from Word's print?

  wordcmp DOC.docx [--word PDF] [--ours PDF | --bin OfficeApp] [--pages 3-5]
                   [--lines | --glyphs --line N] [--first N] [--json]

DOC is a path, or a doc stem (6+ chars of the id) looked up in
/data/corpus-cache/staging/*/docs and test/corpus. Word's print defaults to
word-win/<stem>-orig.pdf beside the docs folder. Our render defaults to the
newest main binary in /data/gate/cache, cached by (binary, doc).
Lines of the two PDFs are rebuilt per baseline and aligned BY TEXT.
Needs PyMuPDF (the venv at ~/venv-word has it; the script re-runs itself there).
"""
import argparse, glob, hashlib, json, os, re, subprocess, sys, unicodedata, warnings

warnings.filterwarnings("ignore")

try:
    import pymupdf as fitz  # PyMuPDF (the old name "fitz" prints a deprecation line)
except ImportError:
    py = os.path.expanduser("~/venv-word/bin/python")
    if os.path.exists(py) and os.path.realpath(sys.executable) != os.path.realpath(py):
        os.execv(py, [py, "-W", "ignore"] + sys.argv)
    sys.exit("wordcmp: PyMuPDF (fitz) not found")

TOL = 0.3          # pt: a row is marked when |dy| or |dx| exceeds this
XGAP = 18.0         # pt: a wider gap on one baseline starts a new row (cell, column)
YCLUSTER = 1.5     # pt: spans whose baselines are within this are one visual line
CACHE = os.path.expanduser("~/.cache/wordcmp")


def die(msg):
    sys.exit("wordcmp: " + msg)


def find_doc(arg):
    if os.path.isfile(arg):
        return os.path.abspath(arg)
    stem = arg[:-5] if arg.endswith(".docx") else arg
    hits = []
    for d in glob.glob("/data/corpus-cache/staging/*/docs") + ["/data/corpus-cache/test/corpus/docx",
                                                                os.path.join(os.getcwd(), "test/corpus/docx"),
                                                                os.path.join(os.getcwd(), "lab")]:
        hits += glob.glob(os.path.join(d, "**", stem + "*.docx"), recursive=True)
    hits = sorted(set(hits))
    if not hits:
        die("no doc matches %r" % arg)
    if len(hits) > 1:
        import hashlib
        h = lambda f: hashlib.sha1(open(f, "rb").read()).hexdigest()
        if len({h(f) for f in hits}) == 1:
            return hits[0]
        die("%r is ambiguous: %s" % (arg, ", ".join(os.path.basename(h) for h in hits[:5])))
    return hits[0]


def find_word_pdf(doc):
    stem = os.path.basename(doc)[:-5]
    d = os.path.dirname(doc)
    for base in [d, os.path.dirname(d), os.path.dirname(os.path.dirname(d))]:
        for sub in ["word-win", "."]:
            p = os.path.normpath(os.path.join(base, sub, stem + "-orig.pdf"))
            if os.path.isfile(p):
                return p
    die("no Word PDF for %s (looked for word-win/%s-orig.pdf); use --word" % (stem, stem))


def default_bin():
    best = None
    for p in glob.glob("/data/gate/cache/*/release/OfficeApp"):
        m = os.path.getmtime(p)
        if best is None or m > best[0]:
            best = (m, p)
    if not best:
        die("no gate-cache binary; use --bin or --ours")
    return best[1]


def repo_top():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def engine_out():
    for c in [os.path.join(os.getcwd(), "engine/src/out/host_release"), os.path.join(repo_top(), "engine/src/out/host_release"),
              "/data/s/amd-10/starling/engine/src/out/host_release"]:
        if os.path.isdir(c):
            return os.path.realpath(c)
    die("no engine out dir for the render env")


def file_key(p):
    # key on CONTENT of the binary AND every *.so beside it (sdk code builds into the .so files, so the
    # binary can be byte-identical after an sdk change); path+mtime let a rebuilt binary read an old render
    h = hashlib.sha1()
    d = os.path.dirname(os.path.realpath(p))
    for f in [p] + sorted(glob.glob(os.path.join(d, "*.so*"))):
        h.update(os.path.basename(f).encode())
        with open(f, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 22), b""):
                h.update(chunk)
    return h.hexdigest()[:12]


def doc_key(p):
    with open(p, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()[:12]


def render(binpath, doc):
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, "%s-%s.pdf" % (file_key(binpath), doc_key(doc)))
    if os.path.isfile(out) and os.path.getsize(out) > 0:
        return out
    eo = engine_out()
    env = dict(os.environ, OFFICE_FONT_SOURCE="bundled", OFFICE_WORD_FONTS="windows", STARLING_ICU=eo + "/icudtl.dat",
               STARLING_ENGINE_OUT=eo, FLUTTER_SWIFT_ENGINE_OUT=eo, LD_LIBRARY_PATH=eo)
    for clock in [os.path.join(os.getcwd(), "test/corpus/docx/clock.tsv"), os.path.join(repo_top(), "test/corpus/docx/clock.tsv"),
                  "/data/s/amd-10/starling/test/corpus/docx/clock.tsv"]:
        if os.path.isfile(clock):
            env["OFFICE_NOW_TABLE"] = clock
            break
    tmp = out[:-4] + ".%d.tmp.pdf" % os.getpid()
    r = subprocess.run([binpath, "--convert", os.path.basename(doc), tmp], cwd=os.path.dirname(doc), env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=600)
    if not os.path.isfile(tmp):
        die("render failed: " + "".join(l for l in r.stderr.decode(errors="replace").splitlines(True) if "no version information" not in l)[-300:])
    os.replace(tmp, out)
    return out


def norm(s):
    # NFKC folds ligatures; format characters (ZWNJ, bidi marks) draw nothing
    t = unicodedata.normalize("NFKC", s)
    return re.sub(r"\s+", "", "".join(ch for ch in t if unicodedata.category(ch) != "Cf"))


class Line:
    def __init__(self, page, y, chars):
        chars.sort(key=lambda c: c[1])
        self.page, self.y, self.chars = page, y, chars
        self.x0 = min(c[1] for c in chars)
        self.x1 = max(c[2] for c in chars)
        t = norm("".join(c[0] for c in chars))
        # RTL runs come out of PDFs in visual order, and the two PDFs may order
        # or shape them differently: compare such lines as a bag of characters.
        if re.search("[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufeff]", t):
            t = "".join(sorted(t))
        self.text = t


def extract(path, pages):
    doc = fitz.open(path)
    lines, skipped = [], 0
    for pn, page in enumerate(doc, 1):
        if pages and pn not in pages:
            continue
        spans = []
        for b in page.get_text("rawdict").get("blocks", []):
            for l in b.get("lines", []):
                d = l.get("dir", (1, 0))
                if abs(d[1]) > 0.5:
                    skipped += 1
                    continue
                for s in l["spans"]:
                    cs = [(c["c"], c["origin"][0], c["bbox"][2]) for c in s.get("chars", []) if c["c"].strip()]
                    if cs:
                        spans.append((s["origin"][1], cs))
        spans.sort(key=lambda t: t[0])
        groups = []
        for y, cs in spans:
            if groups and abs(y - groups[-1][0]) <= YCLUSTER:
                groups[-1][1].extend(cs)
            else:
                groups.append([y, list(cs)])
        for y, cs in groups:
            # Text in separate horizontal ranges (table cells, columns) is
            # separate rows even when the baselines are level.
            cs = sorted(cs, key=lambda c: c[1])
            piece = [cs[0]]
            for c in cs[1:]:
                if c[1] - piece[-1][2] > XGAP:
                    lines.append(Line(pn, y, piece))
                    piece = []
                piece.append(c)
            lines.append(Line(pn, y, piece))
    return lines, skipped, len(doc)


def align(wl, ol):
    """Pair Word lines with ours by text, page by page."""
    import difflib
    rows = []
    for pg in sorted(set(l.page for l in wl) | set(l.page for l in ol)):
        w = [l for l in wl if l.page == pg]
        o = [l for l in ol if l.page == pg]
        sm = difflib.SequenceMatcher(None, [l.text for l in w], [l.text for l in o], autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == "equal":
                rows += [(w[i1 + k], o[j1 + k]) for k in range(i2 - i1)]
            elif tag == "replace":
                oo, used = o[j1:j2], set()
                for a in w[i1:i2]:
                    best, bj = 0.0, None
                    for j, b in enumerate(oo):
                        if j not in used:
                            r = difflib.SequenceMatcher(None, a.text, b.text).ratio()
                            if r > best:
                                best, bj = r, j
                    if bj is not None and best >= 0.5:
                        used.add(bj)
                        rows.append((a, oo[bj]))
                    else:
                        rows.append((a, None))
                rows += [(None, b) for j, b in enumerate(oo) if j not in used]
            elif tag == "delete":
                rows += [(a, None) for a in w[i1:i2]]
            else:
                rows += [(None, b) for b in o[j1:j2]]
    rows.sort(key=lambda r: ((r[0] or r[1]).page, (r[0] or r[1]).y))
    return rows


def parse_pages(s):
    if not s:
        return None
    out = set()
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out |= set(range(int(a), int(b) + 1))
        else:
            out.add(int(part))
    return out


def build_rows(rows):
    res = []
    for i, (w, o) in enumerate(rows):
        r = {"n": i, "page": (w or o).page, "text": (w or o).text[:30]}
        if w and o:
            r.update(wy=round(w.y, 2), oy=round(o.y, 2), dy=round(o.y - w.y, 2), wx=round(w.x0, 2), ox=round(o.x0, 2),
                     dx=round(o.x0 - w.x0, 2), dw=round((o.x1 - o.x0) - (w.x1 - w.x0), 2), exact=(w.text == o.text))
            r["bad"] = abs(r["dy"]) > TOL or abs(r["dx"]) > TOL or not r["exact"]
        else:
            r.update(wy=round(w.y, 2) if w else None, oy=round(o.y, 2) if o else None, wx=round(w.x0, 2) if w else None,
                     ox=round(o.x0, 2) if o else None, only="word" if w else "ours", bad=True)
        res.append(r)
    return res


def fmt(v, w=7):
    return ("%*.2f" % (w, v)) if isinstance(v, (int, float)) else " " * (w - 1) + "-"


def main():
    ap = argparse.ArgumentParser(prog="wordcmp", description="Compare our render with Word's print, line by line.")
    ap.add_argument("doc")
    ap.add_argument("--word")
    ap.add_argument("--ours")
    ap.add_argument("--bin")
    ap.add_argument("--pages")
    ap.add_argument("--lines", action="store_true", help="line table (default)")
    ap.add_argument("--glyphs", action="store_true", help="per-glyph x of one line (needs --line)")
    ap.add_argument("--line", type=int, help="row number (the # column) for --glyphs")
    ap.add_argument("--first", type=int, help="only the first N diverging lines")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    both = bool(a.word and a.ours)  # two PDFs given: no doc lookup needed
    doc = a.doc if both else find_doc(a.doc)
    word = a.word or find_word_pdf(doc)
    ours = a.ours or render(a.bin or default_bin(), doc)
    pages = parse_pages(a.pages)
    wl, wskip, wn = extract(word, pages)
    ol, oskip, on = extract(ours, pages)
    rows = align(wl, ol)
    res = build_rows(rows)
    bad = [r for r in res if r["bad"]]
    paired = [r for r in res if "dy" in r]
    mean = sum(abs(r["dy"]) for r in paired) / len(paired) if paired else 0.0
    summary = {"doc": os.path.basename(doc), "word_pages": wn, "our_pages": on, "word_lines": len(wl), "our_lines": len(ol),
               "matched": sum(1 for r in paired if not r["bad"]), "mean_abs_dy": round(mean, 3),
               "skipped_vertical": {"word": wskip, "ours": oskip}, "first_diverging": bad[0] if bad else None}

    if a.glyphs:
        if a.line is None:
            die("--glyphs needs --line N (the # of a row)")
        w, o = rows[a.line]
        if not (w and o):
            die("row %d is only in %s" % (a.line, "Word" if w else "ours"))
        print("page %d  Word y %.2f  ours y %.2f" % (w.page, w.y, o.y))
        for k in range(min(len(w.chars), len(o.chars))):
            wc, oc = w.chars[k], o.chars[k]
            print("%3d %-2s Word x %8.2f  ours x %8.2f  dx %6.2f%s" % (k, wc[0], wc[1], oc[1], oc[1] - wc[1], ("  ours " + oc[0]) if oc[0] != wc[0] else ""))
        if len(w.chars) != len(o.chars):
            print("char counts differ: Word %d, ours %d" % (len(w.chars), len(o.chars)))
        return

    show = bad[: a.first] if a.first else res
    if a.json:
        print(json.dumps({"summary": summary, "rows": show}, ensure_ascii=False))
        return
    print("pages: Word %d, ours %d%s" % (wn, on, "   (PAGE COUNT DIFFERS)" if wn != on else ""))
    if wskip or oskip:
        print("note: skipped vertical-text lines: Word %d, ours %d" % (wskip, oskip))
    print("  #  pg %-30s %7s %7s %6s %7s %7s %6s %6s" % ("text", "Word y", "ours y", "dy", "Word x", "ours x", "dx", "dwid"))
    for r in show:
        if "dy" in r:
            print("%3d %3d %-30s %s %s %s %s %s %s %s%s%s" % (r["n"], r["page"], r["text"], fmt(r["wy"]), fmt(r["oy"]), fmt(r["dy"], 6),
                  fmt(r["wx"]), fmt(r["ox"]), fmt(r["dx"], 6), fmt(r["dw"], 6), " *" if r["bad"] else "", "" if r["exact"] else " text differs"))
        else:
            print("%3d %3d %-30s %s %s %6s %s %s %6s %6s  * only in %s" % (r["n"], r["page"], r["text"], fmt(r["wy"]), fmt(r["oy"]), "",
                  fmt(r["wx"]), fmt(r["ox"]), "", "", r["only"]))
    fd = summary["first_diverging"]
    if fd:
        print("\nFIRST DIVERGING: row #%d page %d %r  Word y %s ours y %s" % (fd["n"], fd["page"], fd["text"], fd["wy"], fd["oy"]))
    else:
        print("\nno diverging lines")
    print("SUMMARY: %d of %d Word lines matched (ours %d), mean |dy| %.3f pt" % (summary["matched"], len(wl), len(ol), mean))


if __name__ == "__main__":
    main()
