#!/usr/bin/env python3
"""fit-decisions.py SWEEPDIR OUT.pkl [SET] (sweep with STARLING_FIT_LOG=1, stderr into SWEEPDIR/err/<doc>.txt) — join FIT* records in SWEEPDIR/err/*.txt with Word's lines: each over-the-margin decision on our path, and Word's.
Row dict: doc, text, a, last, s(line start offset), took(ours), word (1 took,0 refused,None unknown) + the Q and S fields."""
import os, sys, glob, pickle, unicodedata, re
import pymupdf
from concurrent.futures import ProcessPoolExecutor
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sd, out = sys.argv[1], sys.argv[2]; S = sys.argv[3] if len(sys.argv) > 3 else "756"
C = ROOT + "/test/corpus/docx" + ("/lo" if S == "lo" else "")
SKIP = str.maketrans("", "", " 　\xa0​⁠­\t\x1f")
def norm(s): return unicodedata.normalize("NFKC", s).translate(SKIP)
def wordlines(f):
    out = []
    d = pymupdf.open(f)
    for p in d:
        for b in p.get_text("rawdict")["blocks"]:
            for l in b.get("lines", []):
                cs = [c for sp in l["spans"] for c in sp["chars"]]
                seg = []; prev = None
                for c in cs:
                    sz = max(c["bbox"][3] - c["bbox"][1], 8)
                    if prev is not None and c["bbox"][0] - prev["bbox"][2] > 0.8 * sz: seg.append([])
                    if not seg: seg.append([])
                    seg[-1].append(c); prev = c
                for sg in seg:
                    t = norm("".join(c["c"] for c in sg))
                    if t: out.append(t)
    return out
QF = "over hung hang need room markRoom nall ngiven gapSum nws wsSum stretch lead set before em finalGive takenFirst taken modern legacy wide lineOther wordSpaced squeezedFirst paragraphEnd latinWord oneLatin gridCapped kept commaRefused".split()
OF = "line a last x w width after nmarks nown lineWide lineEms lineOtherO".split()
SF = "sneed sroom sautoRoom sautos snws swsSum sS shalf sshares".split()
def num(v):
    try: return float(v)
    except: return v
def one(ef):
    k = os.path.basename(ef)[:-4]; wf = f"{C}/word-win/{k}-orig.pdf"
    if not os.path.exists(wf): return []
    rows = []; paras = {}; cur = None; seen = set(); ls = {}
    for l in open(ef, errors="replace"):
        if not l.startswith("FIT"): continue
        f = l.rstrip("\n").split("\t")
        if f[0] == "FITP":
            paras[f[1]] = dict(i=f[1], base=float(f[2]), mode=int(f[3]), csc=f[4], cell=int(f[5]), just=int(f[6]), kin0=int(f[7]), halfh=int(f[8]), centred=int(f[9]), bal=int(f[10]), grid=int(f[11]), box=int(f[12]), text=f[13] if len(f) > 13 else "")
        elif f[0] == "FITO":
            cur = dict(zip(OF, map(num, f[2:]))); cur["i"] = f[1]
        elif f[0] == "FITQ" and cur is not None:
            cur.update(zip(QF, map(num, f[3:])))
        elif f[0] == "FITS" and cur is not None:
            cur.update(zip(SF, map(num, f[3:])))
        elif f[0] == "FITR" and cur is not None:
            cur["took"] = int(f[3]); rows.append(cur); cur = None
    if not rows: return []
    wl = wordlines(wf); J = "\n" + "\n".join(wl) + "\n"
    res = []
    prevEnd = {}
    # our line start for each decision: walk rows in order per paragraph: a line starts after the last refused piece or the next piece after a taken (fits) one
    start = {}
    for r in rows:
        p = paras.get(r["i"])
        if not p: continue
        key = (p["text"], r["width"], r["a"], r["last"])
        if key in seen: continue
        seen.add(key)
        T = p["text"]; a = int(r["a"]); last = int(r["last"])
        s = start.get((p["text"], r["width"]), 0)
        pre = norm(T[s:a]); cand = norm(T[a:last])
        word = None
        if len(pre) >= 4 and cand:
            anc = "" if r["line"] == 0 else "\n"
            tk = (anc + pre + cand) in J; rf = (anc + pre + "\n") in J
            if tk and not rf: word = 1
            elif rf and not tk: word = 0
        r2 = dict(p); r2.update(r); r2.update(doc=k[:11], s=s, word=word, pre=pre[-14:], cand=cand)
        res.append(r2)
        # next line start in OUR path
        if r["took"]:
            nx = last
            while nx < len(T) and T[nx] in " 　\t\x1f": nx += 1
            start[(p["text"], r["width"])] = nx
        else:
            start[(p["text"], r["width"])] = a
    return res
if __name__ == "__main__":
    fs = sorted(glob.glob(sd + "/err/*.txt"))
    with ProcessPoolExecutor(32) as ex:
        allr = [r for rows in ex.map(one, fs) for r in rows]
    pickle.dump(allr, open(out, "wb"))
    import collections
    c = collections.Counter((r["took"], r["word"]) for r in allr)
    print(len(allr), c)
