#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""Checks that sheets-sweep.py finds a named book in every set (xlsx, xlsx2, r3), with or without its extension."""
import importlib.util, os, sys, tempfile
here = os.path.dirname(os.path.abspath(__file__))
with tempfile.TemporaryDirectory() as t:
    os.environ["CORPUS_CACHE"] = t
    for d, f in (("xlsx/books", "a.xlsx"), ("xlsx2/books", "b.xlsx"), ("xlsx-cjk-r3/ko", "c.xls"), ("xlsx-cjk-r3/zh", "d.xlsx")):
        os.makedirs(f"{t}/test/corpus/{d}", exist_ok=True); open(f"{t}/test/corpus/{d}/{f}", "w").close()
    sp = importlib.util.spec_from_file_location("s", here + "/tools/sheets-sweep.py"); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
    c = m.CC3
    want = {"a.xlsx": m.BOOKS, "a": m.BOOKS, "b": m.BOOKS2, "c.xls": c + "/ko", "c": c + "/ko", "d": c + "/zh"}
    bad = 0
    for n, bk in want.items():
        r = m.locate(n)
        if not r or r[1] != bk: print("FAIL", n, r); bad += 1
    if m.locate("nope") is not None: print("FAIL nope found"); bad += 1
    r = m.locate("d")
    if not r or r[2] != c + "/zh/excel-win": print("FAIL prints folder"); bad += 1
    print("sheets-sweep-test:", "FAIL" if bad else "ok"); sys.exit(1 if bad else 0)
