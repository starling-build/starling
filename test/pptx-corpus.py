#!/usr/bin/env python3
"""Round-trip a corpus of real PowerPoint decks through Slides.

    test/pptx-corpus.py [--render] [--dir DIR] [FILE.pptx ...]

Downloads Apache POI's .pptx test files (real decks from bug reports, and
fuzzer cases), LibreOffice's sd/qa pptx regression decks (as lo-*) and its
oox/qa decks (as oox-*) into DIR (default ~/.cache/starling/pptx-corpus/in)
once — never into the repo — then for each: read (`OfficeApp --deck`), save and
re-read (`--deck-roundtrip`), and `test/pptx-check.py` on the saved copy.
With --render (macOS, needs Pillow) it also has Quick Look draw slide 1
and the middle slide of the original and of the saved copy and reports
the mean pixel difference (0–255); pairs over 2 are kept side by side in
DIR/../vis to look at. Expected: every healthy deck "ok"; the
clusterfuzz-* files are deliberately broken (refused cleanly or
salvaged); Divino_Revelado is truncated (salvaged); bug62513's duplicate
ids are the original's own. Baseline 2026-10-01: 86 ok, 18 of 118
renders over 2.
"""
import argparse, json, os, re, subprocess, sys, time, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.environ.get("OFFICE_APP") or os.path.join(ROOT, "apps/OfficeApp/.build/debug/OfficeApp")
CHECK = os.path.join(ROOT, "test/pptx-check.py")
# (prefix, GitHub directory listing). The prefix keeps the sources apart in
# one directory and tells the reports which corpus a deck came from.
SOURCES = [
    ("", "https://api.github.com/repos/apache/poi/contents/test-data/slideshow"),
    ("lo-", "https://api.github.com/repos/LibreOffice/core/contents/sd/qa/unit/data/pptx"),
    ("oox-", "https://api.github.com/repos/LibreOffice/core/contents/oox/qa/unit/data"),
]


def fetch(dest):
    os.makedirs(dest, exist_ok=True)
    total = 0
    for prefix, url in SOURCES:
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                entries = [e for e in json.load(r) if e["name"].lower().endswith(".pptx")]
        except (urllib.error.URLError, OSError) as e:
            # Offline, or GitHub reset the connection: the cache is the corpus.
            cached = [f for f in os.listdir(dest) if f.lower().endswith(".pptx")]
            if not cached:
                raise
            print(f"corpus: listing unavailable ({e}); using the {len(cached)} cached decks")
            return len(cached)
        for e in entries:
            path = os.path.join(dest, prefix + e["name"])
            if os.path.exists(path) and os.path.getsize(path) == e["size"]:
                continue
            with urllib.request.urlopen(e["download_url"], timeout=120) as r, open(path, "wb") as f:
                f.write(r.read())
        total += len(entries)
    return total


def run(args, timeout=60):
    t = time.time()
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr, time.time() - t
    except subprocess.TimeoutExpired:
        return "timeout", "", time.time() - t


def last(text):
    lines = text.strip().splitlines()
    return lines[-1][:160] if lines else ""


def one_slide(src, n, dst):
    """A copy of `src` showing only slide n (Quick Look draws slide 1)."""
    z = zipfile.ZipFile(src)
    pres = z.read("ppt/presentation.xml").decode("utf-8", "replace")
    rels = z.read("ppt/_rels/presentation.xml.rels").decode("utf-8", "replace")
    target = f"slides/slide{n}.xml"
    m = re.search(r'Id="([^"]+)"[^>]*Target="[^"]*%s"' % re.escape(target), rels) \
        or re.search(r'Target="[^"]*%s"[^>]*Id="([^"]+)"' % re.escape(target), rels)
    if not m:
        return False
    rid = m.group(1)
    pres = re.sub(r"<p:sldIdLst>.*?</p:sldIdLst>", lambda x: "<p:sldIdLst>" + "".join(
        s for s in re.findall(r"<p:sldId [^>]*/>", x.group(0)) if f'r:id="{rid}"' in s) + "</p:sldIdLst>", pres, flags=re.S)
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as o:
        for i in z.infolist():
            o.writestr(i, pres.encode() if i.filename == "ppt/presentation.xml" else z.read(i.filename))
    return True


def render_diff(src, dst, n, work):
    from PIL import Image, ImageChops, ImageStat
    pngs = []
    for tag, path in (("a", src), ("b", dst)):
        one = os.path.join(work, f"{tag}.pptx")
        if not one_slide(path, n, one):
            return None
        subprocess.run(["qlmanage", "-t", "-s", "800", "-o", work, one], capture_output=True, timeout=60)
        if not os.path.exists(one + ".png"):
            return None
        pngs.append(one + ".png")
    a, b = (Image.open(p).convert("RGB") for p in pngs)
    if a.size != b.size:
        b = b.resize(a.size)
    score = sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3
    if score > 2:
        pair = Image.new("RGB", (a.width * 2 + 10, a.height), "red")
        pair.paste(a, (0, 0)); pair.paste(b, (a.width + 10, 0))
        pair.save(os.path.join(work, f"pair-{score:06.2f}-{os.path.basename(src)}-{n}.png"))
    for p in pngs:
        os.remove(p)
    return score


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.expanduser("~/.cache/starling/pptx-corpus/in"))
    ap.add_argument("--render", action="store_true")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    if not os.path.exists(APP):
        sys.exit("build the app first: swift build --package-path apps/OfficeApp")
    if not a.files:
        print("corpus:", fetch(a.dir), "decks in", a.dir)
    out = os.path.join(os.path.dirname(a.dir), "out")
    vis = os.path.join(os.path.dirname(a.dir), "vis")
    os.makedirs(out, exist_ok=True)
    os.makedirs(vis, exist_ok=True)
    # PowerPoint leaves `~$name.pptx` lock files beside decks it has open
    # (test/pptx-powerpoint-render.sh opens the originals): not decks.
    names = a.files or sorted(f for f in os.listdir(a.dir) if f.lower().endswith(".pptx") and not f.startswith("~$"))
    counts, scores = {}, []
    for name in names:
        src, dst = os.path.join(a.dir, name), os.path.join(out, name)
        code, text, _ = run([APP, "--deck", src])
        if code != 0:
            status, note = "READ-FAIL", last(text)
        else:
            code, text, _ = run([APP, "--deck-roundtrip", src, dst])
            note = last(text)
            status = "ROUNDTRIP-FAIL" if code != 0 else "ok"
            if status == "ok":
                _, ctext, _ = run(["python3", CHECK, dst])
                if not last(ctext).endswith(": ok"):
                    status, note = "CHECK-FAIL", ctext.strip().splitlines()[-1][:160]
        counts[status] = counts.get(status, 0) + 1
        if status != "ok":
            print(f"{status:15} {name}  {note}")
        if a.render and status in ("ok", "CHECK-FAIL"):
            try:
                count = len(re.findall(r"<p:sldId ", zipfile.ZipFile(dst).read("ppt/presentation.xml").decode("utf-8", "replace")))
            except Exception:
                continue
            for n in sorted({1, max(1, (count + 1) // 2)}):
                try:
                    s = render_diff(src, dst, n, vis)
                except (zipfile.BadZipFile, KeyError, OSError):
                    s = None  # a salvaged original Python's zipfile cannot open
                if s is not None:
                    scores.append((s, name, n))
    print(counts)
    if scores:
        print(f"{len(scores)} renders: {sum(s <= 0.5 for s, _, _ in scores)} ≤0.5, "
              f"{sum(0.5 < s <= 2 for s, _, _ in scores)} ≤2, {sum(s > 2 for s, _, _ in scores)} >2 (pairs in {vis})")
        for s, name, n in sorted(scores, reverse=True)[:10]:
            print(f"  {s:6.2f}  {name} slide {n}")


if __name__ == "__main__":
    main()
