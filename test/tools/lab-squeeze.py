#!/usr/bin/env python3
"""lab-squeeze.py BIN WORKDIR [wsf|hcg|kq ...] — run the line-end squeeze labs through BIN and compare with Word for Windows.

BIN is an OfficeApp beside its libFlutterShared.so and *.resources. Run from the repo root (it reads the labs from git):

  wsf  wip/lab-wsf ed7175cee  test/labs/wsf  word spaces: 4 or 8, between ideographs or inside Latin words, commas 0/1/3, balance, face
  hcg  wip/lab-hcg bbd21e4ac  test/labs/hcg  a hung comma or semicolon against an unhung tail, with automatic spaces
  kq   wip/lab-kq  a028f49ef  test/labs/kq   a closing mark as a piece of its own under w:kinsoku 0, modes 12 and 15
  (wip/lab-kq2 68cb29f70: kq again with useFELayout, modes 12, 14, 15, in cells too: same body numbers, not run here.)

For each lab and variant it prints the first width that takes the character: Word's / ours, as points short of (wsf, hcg) or
past (kq) the natural width. The lab files name no w:useFELayout, which ours reads as "no East Asian layout", so this adds it;
kq2 shows Word prints the same with it. wsf, 2026-11-02: 48 of 60 equal, 8 more agree that it is never taken (ours "-"),
and 4 are half a point out."""
import collections, glob, json, os, subprocess, sys, tarfile, io, zipfile
import pymupdf

LABS = {"wsf": ("ed7175cee", "test/labs/wsf"), "hcg": ("bbd21e4ac", "test/labs/hcg"), "kq": ("a028f49ef", "test/labs/kq")}
BIN, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
WHICH = sys.argv[3:] or list(LABS)
EO = os.path.realpath("engine") + "/src/out/host_release"
ENV = dict(os.environ, OFFICE_FONT_SOURCE="bundled", OFFICE_WORD_FONTS="windows", STARLING_ICU=EO + "/icudtl.dat", LD_LIBRARY_PATH=EO,
           STARLING_ENGINE_OUT=EO, FLUTTER_SWIFT_ENGINE_OUT=EO)
SKIP = str.maketrans("", "", " ​⁠")


def fetch(lab):
    rev, path = LABS[lab]
    root = f"{WORK}/{lab}"
    if not os.path.isdir(root + "/" + path):
        os.makedirs(root, exist_ok=True)
        tar = subprocess.run(["git", "archive", rev, path], capture_output=True, check=True).stdout
        tarfile.open(fileobj=io.BytesIO(tar)).extractall(root, filter="data")
    lab_dir = f"{root}/{path}"
    run = f"{root}/run"
    if not os.path.isdir(run):
        subprocess.run([sys.executable, "-I", f"{lab_dir}/spec/gen.py", "test", run, f"{lab_dir}/widths.json"], check=True, stdout=subprocess.DEVNULL)
        for d in glob.glob(run + "/*.docx"):
            z = zipfile.ZipFile(d); items = {n: z.read(n) for n in z.namelist()}; z.close()
            s = items["word/settings.xml"].decode()
            if "useFELayout" not in s: items["word/settings.xml"] = s.replace("<w:compat>", "<w:compat><w:useFELayout/>", 1).encode()
            with zipfile.ZipFile(d, "w", zipfile.ZIP_DEFLATED) as o:
                for n, v in items.items(): o.writestr(n, v)
    return lab_dir, run


def convert(run, prefix):
    docs = sorted(glob.glob(f"{run}/{prefix}-*.docx"))
    ps = [subprocess.Popen([BIN, "--convert", d, d[:-5] + ".pdf"], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for d in docs]
    for p in ps: p.wait()
    return docs


def lines(pdf):
    out = []
    for p in pymupdf.open(pdf):
        for b in p.get_text("rawdict")["blocks"]:
            for l in b.get("lines", []):
                t = "".join(c["c"] for s in l["spans"] for c in s["chars"]).translate(SKIP)
                if t: out.append(t)
    return out


def word_rows(path):
    return [l.rstrip("\n").split("\t") for l in open(path, encoding="utf8") if l.strip() and not l.startswith("#")]


def compare(name, results):
    same = sum(1 for _, w, o in results if o is not None and w is not None and abs(w - o) < 0.01)
    print(f"{name}: {same} of {len(results)} equal")
    for key, w, o in results:
        if o is None or w is None or abs(w - o) >= 0.01:
            print(f"  {key}: Word {w if w is None else round(w, 2)} ours {'-' if o is None else round(o, 2)}")


def wsf():
    d, run = fetch("wsf")
    word = collections.defaultdict(dict)
    for f in word_rows(d + "/wsf-WORD.tsv"): word[(f[0], int(f[1]))][float(f[2])] = "工" in f[3]
    nat = json.load(open(d + "/widths.json"))
    res = []
    for doc in convert(run, "wsf"):
        n = os.path.basename(doc)[:-5]; meta = json.load(open(doc[:-5] + ".meta"))
        st = [x for x in lines(doc[:-5] + ".pdf") if x.startswith("政府機")]
        if len(st) != len(meta): print("#", n, len(st), len(meta)); continue
        per = collections.defaultdict(dict)
        for (k, w), x in zip(meta, st): per[k][w] = "移工" in x
        _, bf, pl = n.split("-")
        for k in sorted(per):
            N = nat[bf][f"{pl}-{k}"]
            o = next((w for w in sorted(per[k]) if per[k][w]), None)
            w = next((w for w in sorted(word[(n, k)]) if word[(n, k)][w]), None)
            res.append((f"{n} k{k}", None if w is None else N - w, None if o is None else N - o))
    compare("wsf (points short)", res)


def kq():
    d, run = fetch("kq")
    word = collections.defaultdict(dict)
    for f in word_rows(d + "/kq-WORD.tsv"): word[(f[0], int(f[1]))][float(f[2])] = f[3].startswith("on line")
    mark = {"c": "，", "d": "、", "q": "”", "r": "”"}
    res = []
    for doc in convert(run, "kq"):
        n = os.path.basename(doc)[:-5]; meta = json.load(open(doc[:-5] + ".meta"))
        st = [x for x in lines(doc[:-5] + ".pdf") if x.startswith("各等級")]
        if len(st) != len(meta): print("#", n, len(st), len(meta)); continue
        per = collections.defaultdict(dict)
        for (k, w), x in zip(meta, st): per[k][w] = x.endswith(mark[n[-1]])
        for k in sorted(per):
            base = min(per[k])
            o = next((w for w in sorted(per[k]) if per[k][w]), None)
            w = next((w for w in sorted(word[(n, k)]) if word[(n, k)][w]), None)
            res.append((f"{n} k{k}", None if w is None else w - base, None if o is None else o - base))
    compare("kq (points past natural)", res)


def hcg():
    d, run = fetch("hcg")
    word = collections.defaultdict(dict)
    for f in word_rows(d + "/hcg-WORD.tsv"): word[(f[0], f[1])][float(f[2])] = "工" in f[3]
    res = []
    for doc in convert(run, "hcg"):
        n = os.path.basename(doc)[:-5]; meta = json.load(open(doc[:-5] + ".meta"))
        st = [x for x in lines(doc[:-5] + ".pdf") if x.startswith("COVID")]
        if len(st) != len(meta): print("#", n, len(st), len(meta)); continue
        per = collections.defaultdict(dict)
        for (t, w), x in zip(meta, st): per[t][w] = "移工" in x
        for t in sorted(per):
            o = next((w for w in sorted(per[t]) if per[t][w]), None)
            w = next((w for w in sorted(word[(n, t)]) if word[(n, t)][w]), None)
            res.append((f"{n} {t}", w, o))
    compare("hcg (first width taken)", res)


for lab in WHICH: {"wsf": wsf, "kq": kq, "hcg": hcg}[lab]()
