"""load.py: every Word lab print's pie labels (lenovo-2, from amd-1's TSVs). LAB = dir holding <name>/test/lab/<name>/*.tsv.
rows(): list of dict(doc,k,th,dx,dy,w,h,R,cx,cy,leg,inside,fw,fh,n,ang,leader). dx,dy = fitz box centre minus pie centre (pt).
Word's own label box (hhea line box, Calibri 0.952/0.269 em, no insets) is the fitz box (typo 0.75/0.25) with top 1.82 pt higher
and bottom 0.17 lower at 9 pt: wtop = fitz_top - 0.2022*sz, wbot = fitz_bot + 0.0190*sz."""
import glob, re, zipfile, collections, os
LAB = os.environ.get('LAB', '/tmp/claude-1000/-data-s-lenovo-2-starling/2f276615-7e16-4172-8b79-6ec68f60bc88/scratchpad/lab')
def docs():
    D = {}
    for f in glob.glob(LAB + '/*/test/lab/*/docs/*.docx'):
        z = zipfile.ZipFile(f); d = z.read('word/document.xml').decode(); c = z.read('word/charts/chart1.xml').decode()
        m = re.search(r'<wp:extent cx="(\d+)" cy="(\d+)"', d)
        v = [float(x) for x in re.findall(r'<c:v>([\d.]+)</c:v>', re.search(r'<c:val>.*?</c:val>', c, re.S).group(0))]
        D[f.split('/')[-1][:-5]] = dict(fw=int(m.group(1)) / 12700, fh=int(m.group(2)) / 12700, vals=v,
                                        ang=int(re.search(r'firstSliceAng val="(\d+)"', c).group(1)))
    return D
def rows():
    D = docs(); out = []; lead = collections.defaultdict(set)
    for f in glob.glob(LAB + '/*/test/lab/*/LEADERS*-WORD*.tsv'):
        for ln in open(f):
            p = ln.rstrip('\n').split('\t')
            if ln.startswith('#') or len(p) < 2 or p[1] in ('-', '?'): continue
            lead[p[0]].add(int(p[1]))
    seen = set()
    for f in sorted(glob.glob(LAB + '/*/test/lab/*/*-WORD.tsv')):
        if 'LEADERS' in f: continue
        for ln in open(f):
            if ln.startswith('#'): continue
            p = ln.rstrip('\n').split('\t')
            if len(p) < 14: continue
            d, k = p[0], int(p[1])
            if (d, k) in seen: continue
            seen.add((d, k)); m = D[d]; v = m['vals']; t = sum(v); cum = sum(v[:k - 1])
            out.append(dict(doc=d, k=k, th=(m['ang'] + 360 * (cum + v[k - 1] / 2) / t) % 360, dx=float(p[4]), dy=float(p[5]),
                            w=float(p[7]), h=float(p[8]), cx=float(p[9]), cy=float(p[10]), R=float(p[11]), leg=float(p[12]),
                            inside=p[13] != 'OUT', fw=m['fw'], fh=m['fh'], n=len(v), ang=m['ang'], leader=k in lead[d]))
    return out
