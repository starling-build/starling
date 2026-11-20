#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/tools/docx-select.py 'EXPRESSION' [options] — the corpus documents a
change can reach, as a key list a sweep reads.

The expression is Python over the features of test/tools/docx-features.py,
true for the documents selected:

    docx-select.py 'mode >= 15 and pagebreak_para'
    docx-select.py "'zh-TW' in langs_ea and kinsoku_off > 0"
    docx-select.py 'tables_floating and not textboxes' --show tables,mode
    docx-select.py --list                   # every feature, with its kind and a sample

Values are numbers, strings, booleans, or lists (use `in`). Only the
feature names, `len`, `any`, `all`, `min`, `max`, `sum` and `sorted` exist
there: nothing else can run.

Options:
  --scored      only documents with a Word for Windows print (the ones a
                sweep scores; this is the default),
  --all         every document in docs/,
  --keyfile F   write the keys to F as well (one per line, no ".docx"),
  --show A,B    print those features beside each key,
  --count       just the number,
  --union FILE  add the keys of FILE (witnesses, a trace) to the answer,
  --canaries    add the fixed canary set (test/corpus/docx/canaries.txt),
  --make-canaries
                (re)build that set: for each of about 25 classes of
                documents the smallest scored one (two, where a class is under a
                hundred) with 30 paragraphs or more, so a cheap pair still has
                a document of every kind to fall on.

The feature rows are cached in ~/.cache/starling/docx-features.json
(rebuilt when the corpus or the extractor changes).
"""
import argparse
import ast
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CORPUS = os.path.join(ROOT, "test", "corpus", "docx")
DOCS = os.path.join(CORPUS, "docs")
CANARIES = os.path.join(CORPUS, "canaries.txt")
CACHE = os.path.expanduser("~/.cache/starling/docx-features.json")

spec = importlib.util.spec_from_file_location("docx_features", os.path.join(HERE, "docx-features.py"))
F = importlib.util.module_from_spec(spec)
sys.modules["docx_features"] = F  # (The worker processes find `one` by this name.)
spec.loader.exec_module(F)

# (Classes of document a canary stands for: a name and the expression that says it.)
CLASSES = [
    ("mode12", "mode == 12"), ("mode14", "mode == 14"), ("mode15", "mode >= 15"), ("legacy", "legacy_mode"),
    ("grid-lines", "grid == 'lines'"), ("grid-chars", "grid in ('linesAndChars', 'snapToChars')"),
    ("kinsoku-off", "kinsoku_off > 0"), ("breakrules-off", "breakrules_off"), ("compress", "char_spacing == 'compressPunctuation'"),
    ("zh-TW", "'zh-TW' in langs_ea"), ("zh-CN", "'zh-CN' in langs_ea"), ("rtl", "rtl"), ("thai", "'thai' in scripts"),
    ("tables-merged", "tables_merged > 0"), ("tables-floating", "tables_floating > 0"), ("rows-exact", "rows_exact > 0"),
    ("textboxes", "textboxes > 0"), ("vml", "vml > 0"), ("wordart", "wordart > 0"), ("charts", "charts > 0"),
    ("smartart", "smartart > 0"), ("equations", "equations > 0"), ("footnotes", "footnotes > 0"),
    ("hf-page-field", "hf_page_field"), ("title-page", "title_page"), ("columns", "columns > 1"),
    ("pagebreak-para", "pagebreak_para"), ("line-exact", "line_exact > 20"), ("line-atleast", "line_atleast > 5"),
    ("lists", "lists > 20"), ("distribute", "jc_distribute > 0"), ("embedded-fonts", "len(fonts_embedded) > 0"),
    ("images", "images > 3"), ("char-scale", "char_scale > 20"), ("landscape", "landscape"), ("sections", "sections > 5"),
]
SAFE_CALLS = {"len": len, "any": any, "all": all, "min": min, "max": max, "sum": sum, "sorted": sorted}


def rows():
    """The feature rows, from the cache where it is current."""
    stamp = [len(os.listdir(DOCS)), max(os.path.getmtime(os.path.join(DOCS, n)) for n in os.listdir(DOCS)),
             os.path.getmtime(os.path.join(HERE, "docx-features.py"))]
    try:
        with open(CACHE, encoding="utf-8") as fh:
            cached = json.load(fh)
        if cached.get("stamp") == stamp:
            return cached["rows"]
    except (OSError, ValueError, KeyError):
        pass
    r = F.rows_for(DOCS)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w", encoding="utf-8") as fh:
        json.dump({"stamp": stamp, "rows": r}, fh, ensure_ascii=False)
    return r


def compile_expression(text, names):
    tree = ast.parse(text, mode="eval")
    for node in ast.walk(tree):
        if isinstance(node, (ast.Attribute, ast.Lambda, ast.Await, ast.Yield, ast.NamedExpr)):
            raise SystemExit(f"not allowed in an expression: {ast.dump(node)[:40]}")
        if isinstance(node, ast.Call) and not (isinstance(node.func, ast.Name) and node.func.id in SAFE_CALLS):
            raise SystemExit("only len, any, all, min, max, sum and sorted can be called")
        if isinstance(node, ast.Name) and node.id not in names and node.id not in SAFE_CALLS:
            near = [n for n in sorted(names) if node.id[:3] in n][:8]
            raise SystemExit(f"no such feature: {node.id}" + (f" (near: {', '.join(near)})" if near else "") + "  (see --list)")
    return compile(tree, "<expression>", "eval")


def scored(keys):
    return [k for k in keys if os.path.exists(os.path.join(CORPUS, "word-win", k + "-orig.pdf"))]


def make_canaries(r):
    chosen = []
    for name, expr in CLASSES:
        code = compile_expression(expr, set(next(iter(r.values()))))
        pool = [k for k in scored(sorted(r)) if r[k]["paragraphs"] >= 30 and eval(code, {"__builtins__": {}}, {**SAFE_CALLS, **r[k]})]
        pool.sort(key=lambda k: (r[k]["bytes"], k))
        picks = [k for k in pool if k not in chosen][:1 if len(pool) > 100 else 2]
        chosen += picks
        print(f"{name:16} {len(pool):4} candidates -> {', '.join(k[:11] for k in picks)}", file=sys.stderr)
    with open(CANARIES, "w", encoding="utf-8") as fh:
        fh.write("# The canary set: documents of every kind, small ones, for a cheap pair to fall on\n"
                 "# (test/tools/docx-select.py --make-canaries; see its classes). One key a line.\n")
        for k in sorted(set(chosen)):
            fh.write(k + "\n")
    print(f"{len(set(chosen))} canaries -> {CANARIES}", file=sys.stderr)


def read_keys(path):
    with open(path, encoding="utf-8") as fh:
        return [l.split("\t")[0].strip().removesuffix(".docx") for l in fh if l.strip() and not l.startswith("#")]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("expression", nargs="?")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--scored", action="store_true")
    ap.add_argument("--keyfile")
    ap.add_argument("--show", default="")
    ap.add_argument("--count", action="store_true")
    ap.add_argument("--union", action="append", default=[])
    ap.add_argument("--canaries", action="store_true")
    ap.add_argument("--make-canaries", action="store_true")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    r = rows()
    names = set(next(iter(r.values())))
    if a.list:
        sample = r[sorted(r)[len(r) // 2]]
        for n in sorted(names):
            vals = {json.dumps(r[k][n], ensure_ascii=False) for k in r}
            print(f"{n:24} {type(sample[n]).__name__:6} {len(vals):4} values  e.g. {json.dumps(sample[n], ensure_ascii=False)[:50]}")
        return 0
    if a.make_canaries:
        make_canaries(r)
        return 0
    if not a.expression and not (a.canaries or a.union):
        ap.error("an expression, --canaries or --union is needed")
    keys = sorted(r) if a.all else scored(sorted(r))
    picked = []
    if a.expression:
        code = compile_expression(a.expression, names)
        picked = [k for k in keys if eval(code, {"__builtins__": {}}, {**SAFE_CALLS, **r[k]})]
    extra = []
    for f in a.union:
        extra += read_keys(f)
    if a.canaries:
        extra += read_keys(CANARIES)
    out = sorted(set(picked) | {k for k in extra if k in r or k.startswith("zh-")})
    # (A key given short, as the board writes it, is every document it starts.)
    full = []
    for k in out:
        full += [x for x in sorted(r) if x.startswith(k)] if k not in r else [k]
    out = sorted(set(full))
    if a.count:
        print(len(out))
        return 0
    show = [s for s in a.show.split(",") if s]
    for k in out:
        print(k + ("\t" + "\t".join(str(r[k][s]) for s in show) if show else ""))
    if a.keyfile:
        with open(a.keyfile, "w", encoding="utf-8") as fh:
            fh.write("\n".join(out) + "\n")
    print(f"{len(out)} documents", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
