#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/tools/docx-census.py OUTDIR — the Word corpus census and dedupe report
(docs/plans/word-corpus-curation.md, steps 1-2). Removes nothing.

  1. FINGERPRINT every scored document (756 set + LO set) as a set of tokens:
       A  structure: test/tools/docx-features.py rows, plus extra XML presence
          tokens (fields, kashida, bidi, line numbers, ...);
       B  text: punctuation/symbol/space code points, scripts, font sizes, and
          the faces used AFTER the Word-for-Windows font map (word-win-font-map.tsv);
       C  rules reached: --trace TRACE.tsv (docx-sweep.sh -t output, "doc<TAB>rule").
          Optional; the report says plainly when it was not given.
  2. DEDUPE: sort by tokens (most first), pages, score-file history, key; keep a
     document unless one already kept has every token of it. Then
       - protections (below 100, visual-scored, board entries that are not
         DONE/LANDED, roundtrip/clock/unit-test documents, moved in history
         without its keeper) are pinned in the gate first;
       - a witness floor keeps every token at 2 witnesses (or all it has);
       - the HISTORY REPLAY runs the committed score files and pins any dropped
         document that moved while its keeper did not, unless the move was a fix
         aimed at it; repeat until nothing changes.
  Writes OUTDIR/dedupe.tsv, OUTDIR/census.json and OUTDIR/report.md.

    python3 test/tools/docx-census.py /tmp/census [--trace T.tsv] [--no-history]
"""
import argparse
import collections
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import unicodedata
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CORP = os.path.join(ROOT, "test", "corpus", "docx")
SETS = {"756": os.path.join(CORP, "docs"), "lo": os.path.join(CORP, "lo", "docs")}
SCORES = os.path.join(CORP, "scores", "linux")
BOARD = os.path.join(ROOT, "docs", "plans", "word-gaps-tasks.md")


def nk(k):
    """One key form: zh-/lo- keys by their first 11 characters (what the board, commits and
    LAND_ACCEPT_DROP use); POI names whole."""
    return k[:11] if re.match(r"(zh|lo)-[0-9a-f]{8}", k) else k


# ---------------------------------------------------------------- scores
LINE = re.compile(r"\s*(-?[\d.]+)%\s+lines (\d+)/(\d+)\s+pages (\d+)/(\d+)\s+(\S+)")


def parse_scores(txt):
    o = {}
    for l in txt.splitlines():
        m = LINE.match(l)
        if m:
            o[nk(re.sub(r"\.docx$", "", m[6]))] = (float(m[1]), int(m[2]), int(m[3]), int(m[4]), int(m[5]))
    return o


def universe():
    """key -> dict(set, score, visual, pages) from the committed combined score files."""
    u = {}
    for s, fn in (("756", "756.combined"), ("lo", "lo.combined")):
        for k, (sc, la, lb, pa, pb) in parse_scores(open(os.path.join(SCORES, fn)).read()).items():
            if k in u:
                sys.exit(f"key collision {k}")
            u[k] = dict(set=s, score=sc, visual=(lb == 0), pages=max(pa, pb))
    return u


# ---------------------------------------------------------------- features
def load_extra(cache, name, d):
    """Feature rows of a staged folder of candidate documents (not scored yet): key = file name."""
    fp = os.path.join(cache, "features-%s.json" % name)
    if os.path.exists(fp):
        return json.load(open(fp))
    spec = importlib.util.spec_from_file_location("docx_features", os.path.join(HERE, "docx-features.py"))
    mod = importlib.util.module_from_spec(spec)
    sys.modules["docx_features"] = mod
    spec.loader.exec_module(mod)
    rows = {k: dict(r, _file=os.path.join(d, k + ".docx")) for k, r in
            ((re.sub(r"\.docx$", "", k), r) for k, r in mod.rows_for(d, jobs=1).items())}
    json.dump(rows, open(fp, "w"))
    return rows


def load_features(cache):
    fp = os.path.join(cache, "features.json")
    if os.path.exists(fp):
        return json.load(open(fp))
    spec = importlib.util.spec_from_file_location("docx_features", os.path.join(HERE, "docx-features.py"))
    mod = importlib.util.module_from_spec(spec)
    sys.modules["docx_features"] = mod
    spec.loader.exec_module(mod)
    rows = {}
    for s, d in SETS.items():
        for k, r in mod.rows_for(d, jobs=1).items():
            rows[nk(k)] = dict(r, _file=os.path.join(d, re.sub(r"\.docx$", "", k) + ".docx"))
    json.dump(rows, open(fp, "w"))
    return rows


# Extra structure tokens (the plan's layer A additions), over every word/*.xml part.
XP = {
    "toc": r'instrText[^>]*>\s*TOC\b', "date": r'instrText[^>]*>\s*(DATE|TIME|PRINTDATE|CREATEDATE|SAVEDATE)\b',
    "if": r'instrText[^>]*>\s*IF\b', "seq": r'instrText[^>]*>\s*SEQ\b', "ref": r'instrText[^>]*>\s*(REF|PAGEREF|NOTEREF)\b',
    "mergefield": r"MERGEFIELD", "formfield": r"w:ffData", "eq": r'instrText[^>]*>\s*EQ\b', "contentctl": r"<w:sdt\b",
    "kashida": r'w:jc w:val="(lowKashida|mediumKashida|highKashida)"', "thaiDist": r'w:jc w:val="thaiDistribute"',
    "bidi": r'<w:bidi/>|<w:bidi w:val="(1|true|on)"', "bidiVisual": r"bidiVisual", "lnNum": r"w:lnNumType", "pgBorders": r"w:pgBorders",
    "fitText": r"w:fitText", "eaLayout": r"w:eastAsianLayout", "emphasis": r'<w:em w:val="(?!none)', "tblFixed": r'w:tblLayout w:val="fixed"',
    "cantSplit": r"w:cantSplit", "tblHeader": r"w:tblHeader", "vMerge": r"w:vMerge", "gridSpan": r"w:gridSpan", "ptab": r"w:ptab",
    "altChunk": r"w:altChunk", "ole": r"<w:object", "mirrorMargins": r"mirrorMargins", "gutter": r'w:gutter="[1-9]',
    "hyphen": r"autoHyphenation", "widowOff": r'<w:widowControl w:val="(0|false)', "contSect": r'w:type w:val="continuous"',
    "colSep": r'w:cols [^>]*w:sep="(1|true)', "textDirTb": r'w:textDirection w:val="(tbRl|tbRlV|btLr|tbLrV)"',
    "tabRight": r'w:tab w:val="right"', "tabCenter": r'w:tab w:val="center"', "tabDecimal": r'w:tab w:val="decimal"',
    "tabBar": r'w:tab w:val="bar"', "tabLeader": r'w:leader="(dot|hyphen|underscore|middleDot)"',
    "dropcap": r'w:dropCap="(drop|margin)"', "wrapTight": r"wp:wrapTight|wp:wrapThrough", "behindDoc": r'behindDoc="1"',
    "caps": r"<w:(smallCaps|caps)/>", "kern": r"<w:kern ", "position": r"<w:position ", "highlight": r"w:highlight",
    "ruby": r"<w:ruby>", "footnoteRefs": r"w:footnoteReference", "endnoteRefs": r"w:endnoteReference", "commentRefs": r"w:commentReference",
    "revisions": r"<w:(ins|del) ", "omml": r"<m:oMath", "smartart": r"dgm:relIds", "wps": r"<wps:wsp",
}
XC = {k: re.compile(v) for k, v in XP.items()}
SCRIPTS = {
    "hangul": (0xAC00, 0xD7AF), "hangul-jamo": (0x1100, 0x11FF), "kana": (0x3040, 0x30FF), "hebrew": (0x0590, 0x05FF),
    "arabic": (0x0600, 0x06FF), "devanagari": (0x0900, 0x097F), "greek": (0x0370, 0x03FF), "cyrillic": (0x0400, 0x04FF),
    "thai": (0x0E00, 0x0E7F), "latin-ext": (0x0100, 0x024F), "han": (0x4E00, 0x9FFF), "han-ext": (0x3400, 0x4DBF),
}
SPACES = {0x3000, 0xA0, 0x2002, 0x2003, 0x2009, 0x200B, 0x202F}
TEXT_PARTS = re.compile(r"word/(document|header\d*|footer\d*|footnotes|endnotes|comments)\.xml$")


def read_parts(path):
    try:
        z = zipfile.ZipFile(path)
        return {n: z.read(n).decode("utf-8", "replace") for n in z.namelist() if n.startswith("word/") and n.endswith(".xml")}
    except Exception:
        out = subprocess.run(["unzip", "-Z1", path], capture_output=True, text=True).stdout.split()
        return {n: subprocess.run(["unzip", "-p", path, n], capture_output=True).stdout.decode("utf-8", "replace")
                for n in out if n.startswith("word/") and n.endswith(".xml")}


def xml_tokens(path):
    parts = read_parts(path)
    allx = "".join(parts.values())
    t = {"x:" + k for k, c in XC.items() if c.search(allx)}
    txt = ""
    sizes = set()
    for n, x in parts.items():
        if TEXT_PARTS.search(n):
            txt += "".join(re.findall(r"<w:t(?:\s[^>]*)?>([^<]*)</w:t>", x))
            sizes.update(int(v) for v in re.findall(r'<w:sz w:val="(\d+)"', x))
    for ch in set(txt):
        o = ord(ch)
        cat = unicodedata.category(ch)
        if cat[0] in "PS" or o in SPACES:
            t.add("ch:%04x" % o)
        elif 0xFF00 <= o <= 0xFFEF:
            t.add("fullwidth-form")
        for name, (a, b) in SCRIPTS.items():
            if a <= o <= b:
                t.add("script:" + name)
    t.update("sz:%d" % s for s in sizes)
    return t


# ---------------------------------------------------------------- fonts through the Windows map
def font_map():
    best = {}
    for l in open(os.path.join(CORP, "word-win-font-map.tsv"), encoding="utf-8"):
        if l.startswith("#") or not l.strip():
            continue
        c = l.rstrip("\n").split("\t")
        if len(c) < 5:
            continue
        try:
            share = float(c[4])
        except ValueError:
            continue
        name, face = c[0], c[1]
        if name not in best or share > best[name][1]:
            best[name] = (face, share)
    return best


def family(face):
    f = re.sub(r"-.*$", "", face)
    return re.sub(r"(PSMT|PS|MT)$", "", f) or face


def face_tokens(fonts, fmap, stat):
    out = set()
    for n in fonts:
        n = n.strip()
        row = fmap.get(n)
        if row is None or row[0].startswith("___WRD_EMBED"):
            out.add("face:" + n)
            stat["authored"] += 1
        else:
            out.add("face:" + family(row[0]))
            stat["mapped"] += 1
    return out


SKIP = {"bytes", "paragraphs", "styles", "page_w", "size_pt_min", "size_pt_max", "grid_line", "empty_paragraphs", "fonts",
        "fonts_embedded", "compat", "list_formats", "list_levels", "langs", "grids", "footer_types", "header_types", "font_parts",
        "lang_stated", "header_parts", "footer_parts", "_file"}


def struct_tokens(row):
    t = set()
    for n, v in row.items():
        if n in SKIP:
            continue
        if isinstance(v, bool):
            if v:
                t.add(n)
        elif isinstance(v, (int, float)):
            if n == "mode":
                t.add("mode=%d" % v)
            elif n in ("columns", "sections", "table_depth"):
                if v >= 2:
                    t.add("%s>=2" % n)
                if v >= 3:
                    t.add("%s>=3" % n)
            elif v > 0:
                t.add(n)
        elif isinstance(v, str):
            if v:
                t.add("%s=%s" % (n, v))
        elif isinstance(v, list):
            t.update("%s:%s" % (n, x) for x in v)
    t.update("hdr:" + str(x) for x in (row.get("header_types") or []))
    t.update("ftr:" + str(x) for x in (row.get("footer_types") or []))
    if row.get("fonts_embedded"):
        t.add("fonts_embedded")
    for x in (row.get("compat") or []):
        t.add("compat:" + str(x))
    return t


def fingerprints(rows, u, trace, stat):
    fm = font_map()
    T = {}
    for k in u:
        r = rows.get(k)
        if r is None:
            continue
        t = struct_tokens(r) | xml_tokens(r["_file"]) | face_tokens(r.get("fonts") or [], fm, stat)
        t |= {"rule:" + x for x in trace.get(k, ())}
        T[k] = frozenset(t)
    return T


# ---------------------------------------------------------------- the board
ACTIVE = ("CLAIMED", "OPEN", "PARKED", "RELEASED", "UNFIXABLE", "BLOCKED")
DONEW = ("DONE", "LANDED")
STATUS = re.compile(r"\b(" + "|".join(ACTIVE + DONEW) + r")\b")
DOCRE = re.compile(r"\b((?:zh|lo)-[0-9a-f]{8})")


def poi_regexes(keys):
    return {k: re.compile(r"(?<![\w.-])" + re.escape(k) + r"(?![\w-])")
            for k in keys if not k.startswith(("zh-", "lo-")) and len(k) >= 5 and not k.isdigit()}


def read_board(keys):
    """doc -> list of (reason, line number, tier). tier 'header' = named in the header of an entry
    that is not DONE/LANDED (or in an ASSIGNMENTS bullet); 'body' = named only in its body.
    Also returns the unmarked headers (no status word) and the documents they name."""
    lines = open(BOARD, encoding="utf-8").read().split("\n")
    pois = poi_regexes(keys)
    prot = collections.defaultdict(list)
    unmarked = []
    unmarked_docs = set()

    def names(s):
        n = set(DOCRE.findall(s))
        n.update(k for k, rx in pois.items() if rx.search(s))
        return n

    heads = [i for i, l in enumerate(lines) if l.startswith("### ") or l.startswith("## ")]
    heads.append(len(lines))
    for hi, start in enumerate(heads[:-1]):
        h = lines[start]
        body = lines[start + 1: heads[hi + 1]]
        if h.startswith("## "):
            if "ASSIGNMENTS" in h:
                for j, l in enumerate(body):
                    if l.startswith("- ") and not l.startswith("- DONE:"):
                        for d in names(l):
                            prot[d].append(("ASSIGNMENTS bullet (not DONE)", start + 2 + j, "header"))
            continue
        stat = STATUS.findall(h)
        if not stat:
            unmarked.append(start + 1)
            unmarked_docs |= names(h)
            continue
        has_active = any(s in ACTIVE for s in stat)
        has_done = any(s in DONEW for s in stat)

        def status_after(end):
            m = STATUS.search(h, end)
            return m.group(1) if m else stat[-1]

        for m in DOCRE.finditer(h):
            if status_after(m.end()) in ACTIVE:
                prot[m.group(1)].append(("header " + status_after(m.end()), start + 1, "header"))
        for d, rx in pois.items():
            m = rx.search(h)
            if m and status_after(m.end()) in ACTIVE:
                prot[d].append(("header " + status_after(m.end()), start + 1, "header"))
        if has_active and not has_done:
            for j, l in enumerate(body):
                for d in names(l):
                    prot[d].append(("body of a %s entry" % stat[0], start + 2 + j, "body"))
    for j, l in enumerate(lines):
        if "LAND_ACCEPT_DROP" in l or re.search(r"cancelling[- ]error|SCORER ARTEFACT", l):
            for d in names(l):
                prot[d].append(("accepted drop / scorer artefact line", j + 1, "line"))
    return prot, unmarked, unmarked_docs


# ---------------------------------------------------------------- other protections
def read_tsv_keys(fn, keys):
    out = set()
    ks = set(keys)
    for l in open(fn, encoding="utf-8"):
        c = re.sub(r"\.docx$", "", l.split("\t")[0].strip())
        if not c or c.startswith("#"):
            continue
        n = nk(c)
        if n in ks:
            out.add(n)
    return out


def test_docs(keys):
    txt = ""
    for dp, _, fs in os.walk(os.path.join(ROOT, "apps", "OfficeApp", "Tests")):
        for f in fs:
            if f.endswith(".swift"):
                txt += open(os.path.join(dp, f), encoding="utf-8", errors="replace").read()
    pois = poi_regexes(keys)
    out = set()
    for k in keys:
        if k.startswith(("zh-", "lo-")):
            if k in txt or k[3:] in txt:
                out.add(k)
        elif k in pois and pois[k].search(txt):
            out.add(k)
    return out


# ---------------------------------------------------------------- history
def git(*a):
    return subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True).stdout


def nonboard_msgs(rng):
    """Commit messages in the range, board-only commits left out: a board note naming a document is not a fix aimed at it."""
    out = git("log", "--format=%s%x00%B%x01", rng)
    return "\n".join(e.split("\x00", 1)[1] for e in out.split("\x01") if "\x00" in e and not e.strip().startswith("board:"))


def history():
    """events: dict(file, rev, subject, moved={key:(old,new)}, rebase, msgs). appear: revisions per key."""
    events = []
    appear = collections.Counter()
    for f in ("756.v2", "lo.v2"):
        p = "test/corpus/docx/scores/linux/" + f
        revs = git("log", "--format=%H", "--", p).split()[::-1]
        prev = prevrev = None
        for rv in revs:
            cur = {k: v[0] for k, v in parse_scores(git("show", f"{rv}:{p}")).items()}
            for k in cur:
                appear[k] += 1
            if prev is not None:
                mv = {k: (prev[k], cur[k]) for k in cur if k in prev and abs(cur[k] - prev[k]) >= 0.05}
                if mv:
                    rng = f"{prevrev}..{rv}"
                    files = git("log", "--name-only", "--format=", rng)
                    events.append(dict(file=f, rev=rv[:9], subject=git("log", "-1", "--format=%s", rv).strip()[:100],
                                       moved=mv, msgs=nonboard_msgs(rng),
                                       rebase=bool(re.search(r"word-win/|test/docx-line-match\.py", files))))
            prev, prevrev = cur, rv
    return events, appear


def aimed(k, msgs):
    if k.startswith(("zh-", "lo-")):
        return k in msgs or k[3:] in msgs
    return bool(re.search(r"(?<![\w.-])" + re.escape(k) + r"(?![\w-])", msgs))


# ---------------------------------------------------------------- the dedupe
def dedupe(keys, T, u, appear, pinned):
    order = sorted(keys, key=lambda k: (-len(T[k]), -u[k]["pages"], -appear.get(k, 0), k))
    kept = [k for k in order if k in pinned]
    keptset = set(kept)
    keeper = {}
    for k in order:
        if k in keptset:
            continue
        sup = next((j for j in kept if T[k] <= T[j]), None)
        if sup is None:
            kept.append(k)
            keptset.add(k)
        else:
            keeper[k] = sup
    floor = set()
    total = collections.Counter(t for k in keys for t in T[k])
    while True:
        cnt = collections.Counter(t for k in keptset for t in T[k])
        need = {t for t in total if cnt[t] < min(2, total[t])}
        if not need:
            break
        for k in order:
            if k in keeper and (T[k] & need):
                keptset.add(k)
                floor.add(k)
                del keeper[k]
                break
        else:
            break
    return keptset, keeper, floor


def run_plan(keys, T, u, appear, base_pins, events, replay):
    pins = dict(base_pins)
    rounds = 0
    while True:
        rounds += 1
        kept, keeper, floor = dedupe(keys, T, u, appear, set(pins))
        if not replay:
            break
        new = {}
        for ev in events:
            if ev["rebase"]:
                continue
            for k, (a, b) in ev["moved"].items():
                if k in keeper and k not in pins and k not in new:
                    if keeper[k] in ev["moved"] or aimed(k, ev["msgs"]):
                        continue
                    new[k] = [("history: moved %.1f->%.1f in %s (%s) while its keeper %s did not; no commit in the range names it"
                               % (a, b, ev["rev"], ev["file"], keeper[k]), 0, "history")]
        if not new:
            break
        pins.update(new)
    return pins, kept, keeper, floor, rounds


def replay_stats(events, kept, keeper):
    blind, aimed_unseen, side = [], [], []
    for ev in events:
        if ev["rebase"]:
            continue
        if not any(k in kept for k in ev["moved"]):
            blind.append(ev)
        for k in ev["moved"]:
            if k in keeper and keeper[k] not in ev["moved"]:
                (aimed_unseen if aimed(k, ev["msgs"]) else side).append((k, ev))
    return blind, aimed_unseen, side


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("out")
    ap.add_argument("--trace", help="docx-sweep.sh -t trace.tsv (document<TAB>rule); layer C")
    ap.add_argument("--stage", action="append", default=[], metavar="NAME=DIR",
                    help="candidate documents (a folder of .docx not yet in the gate): list those that add nothing "
                         "beyond the kept set plus the other candidates (repeatable; batches are judged together)")
    ap.add_argument("--no-history", action="store_true", help="skip the history replay")
    ap.add_argument("--body-protect", choices=("all", "none"), default="all",
                    help="protect documents named only in the body of an active entry (default all)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    u = universe()
    rows = load_features(a.out)
    trace = collections.defaultdict(set)
    if a.trace:
        for l in open(a.trace):
            c = l.rstrip("\n").split("\t")
            if len(c) >= 2:
                trace[nk(re.sub(r"\.docx$", "", c[0]))].add(c[1])
    stat = collections.Counter()
    T = fingerprints(rows, u, trace, stat)
    keys = [k for k in u if k in T]
    missing = sorted(set(u) - set(T))
    unscored = sorted(set(rows) - set(u))
    events, appear = ([], {}) if a.no_history else history()

    pins = collections.defaultdict(list)
    for k in keys:
        if u[k]["score"] < 100:
            pins[k].append(("below 100 combined", 0, "score"))
        if u[k]["visual"]:
            pins[k].append(("visual-scored (no text lines; the replay cannot see it)", 0, "visual"))
    prot, unmarked, unmarked_docs = read_board(keys)
    for k, v in prot.items():
        if k in T:
            for r in v:
                if a.body_protect == "all" or r[2] != "body":
                    pins[k].append(r)
    for fn, why in (("roundtrip.tsv", "used by roundtrip.tsv"), ("clock.tsv", "used by clock.tsv")):
        for k in read_tsv_keys(os.path.join(CORP, fn), keys):
            pins[k].append((why, 0, "file"))
    for k in test_docs(keys):
        pins[k].append(("named in apps/OfficeApp/Tests", 0, "test"))
    pins, kept, keeper, floor, rounds = run_plan(keys, T, u, appear, dict(pins), events, not a.no_history)
    blind, aimed_unseen, side = replay_stats(events, kept, keeper)

    sha = collections.defaultdict(list)
    for k in keys:
        sha[hashlib.sha256(open(rows[k]["_file"], "rb").read()).hexdigest()].append(k)
    bytedup = [v for v in sha.values() if len(v) > 1]

    allcnt = collections.Counter(t for k in keys for t in T[k])
    keptcnt = collections.Counter(t for k in kept for t in T[k])
    with open(os.path.join(a.out, "dedupe.tsv"), "w") as fh:
        fh.write("key\tset\tpages\tscore\taction\tkeeper\treason\tkeeper_adds\n")
        for k in sorted(keys, key=lambda k: (u[k]["set"], k)):
            if k in keeper:
                kp = keeper[k]
                row = ("drop", kp, "every token is in the keeper", " ".join(sorted(T[kp] - T[k]))[:200])
            else:
                if k in pins:
                    why = "; ".join(sorted({r[0] for r in pins[k]}))[:200]
                elif k in floor:
                    why = "witness floor"
                else:
                    why = "carries tokens no kept document has"
                row = ("keep", "", why, "")
            fh.write("\t".join([k, u[k]["set"], str(u[k]["pages"]), "%.1f" % u[k]["score"], *row]) + "\n")
    json.dump(dict(keep=sorted(kept), drop=keeper, floor=sorted(floor), pins={k: [r[0] for r in v] for k, v in pins.items()},
                   tokens={k: sorted(T[k]) for k in keys}), open(os.path.join(a.out, "census.json"), "w"))
    write_report(a.out, u, keys, T, kept, keeper, floor, pins, prot, unmarked, unmarked_docs, events, blind, aimed_unseen,
                 side, rounds, stat, unscored, missing, bytedup, allcnt, keptcnt, bool(a.trace), a.no_history)
    if a.stage:
        stage_report(a, T, kept, u, stat)
    print(f"{len(keys)} documents, {len(set(T.values()))} distinct fingerprints; drop {len(keeper)}; kept {len(kept)}; "
          f"protected {len(pins)}; rounds {rounds} -> {a.out}/report.md")
    return 0


def app_pages(path):
    """Page count the producer wrote in docProps/app.xml (0 when absent); candidates are not printed yet."""
    try:
        m = re.search(r"<Pages>(\d+)</Pages>", zipfile.ZipFile(path).read("docProps/app.xml").decode("utf-8", "replace"))
        return int(m[1]) if m else 0
    except Exception:
        return 0


def read_manifest(d):
    """name -> dict(pages, lang, kind, idx) from the batch's manifest.tsv (beside the docs folder)."""
    import csv
    fn = os.path.join(os.path.dirname(d.rstrip("/")), "manifest.tsv")
    out = {}
    if os.path.exists(fn):
        for i, r in enumerate(csv.DictReader(open(fn, encoding="utf-8"), delimiter="\t")):
            nm = re.sub(r"\.docx$", "", r.get("file") or r.get("name") or "")
            pg = r.get("pages_ours") or r.get("pages_est") or "0"
            out[nm] = dict(pages=int(float(pg or 0)), lang=LANG3.get(l2 := (r.get("language") or "").split("-")[0].split("_")[0].lower(), l2),
                           kind=r.get("kind", ""), idx=i)
    return out


# Never cut (thin groups); cut only from OVER (the plan's over-target groups: European Latin, Arabic+Persian).
LANG3 = {"ar": "ara", "fa": "fas", "de": "deu", "fr": "fra", "es": "spa", "it": "ita", "pt": "por", "pl": "pol", "nl": "nld",
         "cs": "ces", "hu": "hun", "ja": "jpn", "ko": "kor", "he": "heb", "hi": "hin", "el": "ell", "ru": "rus", "uk": "ukr",
         "bg": "bul", "sv": "swe", "da": "dan", "nb": "nor", "no": "nor", "fi": "fin", "ro": "ron", "bn": "ben", "ta": "tam",
         "mr": "mar", "ur": "urd", "th": "tha", "en": "eng", "zh": "zho", "tr": "tur", "cy": "cym", "bs": "bos"}
NEVER = {"jpn", "kor", "heb", "hin", "ben", "tam", "mar", "urd", "ell", "tha"}
OVER = {"ara", "fas", "fra", "ces", "spa", "ita", "por", "pol", "nld", "deu", "hun", "dan", "swe", "nor", "fin", "ron"}
AR_FA_TARGET = 40
BUDGET_PAGES = 4000   # docs/plans/word-corpus-curation.md
PRINTED_B = 241       # windows printed the first 241 batch B rows (7bd947233 + earlier); the rest wait for this list


def stage_report(a, T, kept, u, stat):
    """Candidates (batch folders, judged together): sort like the dedupe (tokens, pages); a candidate that adds no token beyond
    the kept set plus the earlier admitted candidates is REDUNDANT. Then trim to the page budget by cutting redundant
    candidates of over-target groups only (never the thin groups, never long English):
      1. Arabic+Persian down to AR_FA_TARGET documents, cutting the unprinted ones first;
      2. the rest of the excess pages from the other over-target groups, largest first."""
    fm = font_map()
    C, meta = {}, {}
    for spec in a.stage:
        name, d = spec.split("=", 1)
        rows = load_extra(a.out, name, d)
        man = read_manifest(d)
        for k, r in rows.items():
            key = name + "/" + k
            m = man.get(k, dict(pages=app_pages(r["_file"]), lang=k.split("-")[0], kind="", idx=0))
            lang = LANG3.get(m["lang"], m["lang"])
            meta[key] = dict(m, batch=name, group=lang, unprinted=(name == "B" and m["idx"] >= PRINTED_B))
            C[key] = frozenset(struct_tokens(r) | xml_tokens(r["_file"]) | face_tokens(r.get("fonts") or [], fm, stat))
    pages = {k: meta[k]["pages"] for k in C}
    have = set()
    for k in kept:
        have |= T[k]
    order = sorted(C, key=lambda k: (-len(C[k]), -pages[k], k))
    admit, skip = [], {}
    for k in order:
        if C[k] - have:
            admit.append(k)
            have |= C[k]
        else:
            same = next((j for j in admit if C[k] <= C[j]), None)
            skip[k] = same or "(kept set + several admitted)"
    total = sum(pages.values())
    need = max(0, total - BUDGET_PAGES)
    cuttable = lambda k: k in skip and meta[k]["group"] in OVER and meta[k]["kind"] != "long"
    cut, saved = {}, 0
    arfa = [k for k in C if meta[k]["group"] in ("ara", "fas")]
    for k in sorted((k for k in arfa if cuttable(k)),
                    key=lambda k: (not meta[k]["unprinted"], skip[k].startswith("("), -pages[k], k)):
        if len(arfa) - len(cut) <= AR_FA_TARGET:
            break
        cut[k] = skip[k]
        saved += pages[k]
    for k in sorted((k for k in skip if cuttable(k) and k not in cut), key=lambda k: (-pages[k], k)):
        if saved >= need:
            break
        cut[k] = skip[k]
        saved += pages[k]
    with open(os.path.join(a.out, "stage.tsv"), "w") as fh:
        fh.write("doc\taction\tgroup\tpages\tprinted\tcovered_by\n")
        for k in order:
            act = "NOT ADMIT" if k in cut else ("redundant, kept (thin group or budget met)" if k in skip else "admit")
            fh.write(f"{k}\t{act}\t{meta[k]['group']}\t{pages[k]}\t{'no' if meta[k]['unprinted'] else 'yes'}\t{skip.get(k, '')}\n")
    json.dump(dict(admit=admit, skip=skip, cut=cut, pages=pages, need=need, saved=saved, total=total,
                   meta={k: dict(batch=v["batch"], group=v["group"], unprinted=v["unprinted"], kind=v["kind"]) for k, v in meta.items()}),
              open(os.path.join(a.out, "stage.json"), "w"))
    print(f"stage: {len(C)} candidates, {total} pages (budget {BUDGET_PAGES}, cut {need}); redundant {len(skip)}; "
          f"propose NOT to admit {len(cut)} documents, {saved} pages")


def write_report(out, u, keys, T, kept, keeper, floor, pins, prot, unmarked, unmarked_docs, events, blind, aimed_unseen,
                 side, rounds, stat, unscored, missing, bytedup, allcnt, keptcnt, have_trace, no_hist):
    W = []
    w = W.append
    pg = lambda ks: sum(u[k]["pages"] for k in ks)
    w("## Counts")
    w("")
    w("| | 756 set | LO set | all |\n|---|---|---|---|")
    for lab, f in (("scored documents", lambda k: True), ("proposed to drop", lambda k: k in keeper), ("kept", lambda k: k not in keeper)):
        a = [k for k in keys if f(k) and u[k]["set"] == "756"]
        b = [k for k in keys if f(k) and u[k]["set"] == "lo"]
        w(f"| {lab} | {len(a)} ({pg(a)} pages) | {len(b)} ({pg(b)} pages) | {len(a)+len(b)} ({pg(a)+pg(b)} pages) |")
    w("")
    w(f"Layer C (rules reached) was {'included' if have_trace else 'NOT included: no trace file was given'}. "
      f"{len(set(T.values()))} distinct fingerprints among {len(keys)} documents. "
      f"Keepers added by the witness floor: {len(floor)}. Dedupe/replay rounds until stable: {rounds}.")
    w(f"Fonts: {stat['mapped']} used font names went through the Windows font map, {stat['authored']} stayed as authored "
      f"(no map row, or the face is an embedded stand-in).")
    if missing:
        w(f"Scored but with no feature row (left out of the dedupe, never dropped): {len(missing)}: {', '.join(missing[:10])}")
    if unscored:
        w(f"Files in the folders that no score file lists (left out): {len(unscored)}.")
    w("")
    w("## History replay")
    w("")
    if no_hist:
        w("Skipped (--no-history).")
    else:
        norb = [e for e in events if not e["rebase"]]
        w(f"The committed score files (756.v2 and lo.v2, every version) hold {len(events)} occasions when some documents moved by 0.05 or more; "
          f"{len(events)-len(norb)} of them are re-baselines or scorer changes (the range touches `word-win/` or `docx-line-match.py`) and are not judged. "
          f"Of the other {len(norb)}:")
        w(f"- the kept set would have seen {len(norb)-len(blind)}; it would have seen nothing in {len(blind)};")
        w(f"- moves of a dropped document whose keeper did not move, where a commit in the range names the document (a fix aimed at it): {len(aimed_unseen)};")
        w(f"- moves of a dropped document whose keeper did not move and nothing names it (side effects): {len(side)}. "
          f"**Acceptance rule: this must be 0.** Every such document was pinned, which is why the loop ran {rounds} rounds.")
        if blind:
            w("")
            w("Occasions the kept set would not have seen at all:")
            for e in blind:
                w(f"- {e['rev']} {e['file']}: " + ", ".join(f"{k} {x:.1f}->{y:.1f}" for k, (x, y) in list(e["moved"].items())[:4]) + f" | {e['subject']}")
    w("")
    w("## Protected (never dropped), by reason")
    w("")
    rc = collections.Counter()
    for k, v in pins.items():
        for r in {re.sub(r"[\d.]+", "#", x[0])[:60] for x in v}:
            rc[r] += 1
    for r, n in rc.most_common():
        w(f"- {n}: {r}")
    w("")
    w(f"Protected documents: {len(pins)} (a document can have several reasons). "
      f"Board entries with no status word (not guessed, not protecting): {len(unmarked)} headers naming {len(unmarked_docs)} documents.")
    w("")
    w("## Byte-identical documents (SHA-256)")
    w("")
    w(", ".join("/".join(v) for v in bytedup) if bytedup else "none")
    w("")
    w("## Features with too few witnesses")
    w("")
    w("Structure and script tokens with fewer than 3 witnesses in the whole corpus, and how many the proposed gate keeps.")
    w("")
    w("| token | all docs | proposed gate |\n|---|---|---|")
    for t, n in sorted(allcnt.items(), key=lambda x: (x[1], x[0])):
        if n < 3 and not t.startswith(("ch:", "sz:", "face:", "rule:")):
            w(f"| {t} | {n} | {keptcnt[t]} |")
    w("")
    sc = [t for t, n in allcnt.items() if t.startswith(("ch:", "sz:", "face:")) and n < 3]
    w(f"Plus {len(sc)} rare code points, sizes and faces with 1-2 witnesses (kept by the floor; list in census.json).")
    w("")
    w("## Proposed drops (each with its keeper)")
    w("")
    w("| document | set | pages | keeper | tokens the keeper adds (first 8) |\n|---|---|---|---|---|")
    for k in sorted(keeper, key=lambda k: (u[k]["set"], k)):
        adds = sorted(T[keeper[k]] - T[k])
        w(f"| {k} | {u[k]['set']} | {u[k]['pages']} | {keeper[k]} | {' '.join(adds[:8])}{' …(%d)' % len(adds) if len(adds) > 8 else ''} |")
    open(os.path.join(out, "report.md"), "w").write("\n".join(W) + "\n")


if __name__ == "__main__":
    sys.exit(main())
