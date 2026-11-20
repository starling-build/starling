"""configs.py: every Word print as one configuration for a placement simulator (lenovo-2).
Each config: dict(doc, R (true, pt), cx_phase (px, pie centre x minus the nearest integer... kept as the fractional W/2 px),
slices=[(start_deg, span_deg)], labels={k: (w_pt, h_fitz_pt)} for the labels that EXIST (kept), order = sorted k,
obs={k: (text_left_px, word_top_px, inside)} relative to the pie centre, leaders=set(k)).
Sources: lab pie1/pie2/pieanchor/piezone TSVs (meas2 or meas.py) + the docx geometry. R: the on-curve fit where available
(pieanchor F.tsv, piezone apex R), else the wedge-box R divided by the Bezier factor is NOT attempted - pie1/pie2 docs at ang 0
have R_box = R_true; other angles carry up to +3.5% (note in 'Rnote')."""
import os, re, glob, zipfile, math, collections
S = os.environ.get('LAB', '/tmp/claude-1000/-data-s-lenovo-2-starling/2f276615-7e16-4172-8b79-6ec68f60bc88/scratchpad/lab')
def chart_geom(docx):
    z = zipfile.ZipFile(docx); c = z.read('word/charts/chart1.xml').decode(); d = z.read('word/document.xml').decode()
    vals = [float(x) for x in re.findall(r'<c:v>([\d.]+)</c:v>', re.search(r'<c:val>.*?</c:val>', c, re.S).group(0))]
    ang = int(re.search(r'firstSliceAng val="(\d+)"', c).group(1)); tot = sum(vals)
    slices = []; a = ang
    for v in vals: slices.append((a % 360, 360 * v / tot)); a += 360 * v / tot
    deleted = {int(i) + 1 for i in re.findall(r'<c:dLbl><c:idx val="(\d+)"/><c:delete val="1"/>', c)}
    fw = int(re.search(r'<wp:extent cx="(\d+)"', d).group(1)) / 12700
    return dict(slices=slices, kept=[k for k in range(1, len(vals) + 1) if k not in deleted], fw=fw, n=len(vals))
def load():
    out = collections.OrderedDict()
    for tsv in glob.glob(S + '/*/test/lab/*/*-WORD*.tsv'):
        lab = tsv.split('/test/lab/')[1].split('/')[0]
        if 'LEADERS' in tsv: continue
        docs = glob.glob(os.path.dirname(tsv) + '/docs/*.docx'); dmap = {os.path.basename(x)[:-5]: x for x in docs}
        for ln in open(tsv):
            p = ln.rstrip('\n').split('\t')
            if ln.startswith('#') or len(p) < 14: continue
            multi = p[2] == 'LEADER' or (len(p) >= 16 and p[1].isdigit() and len(p[1]) == 1 and p[2].isdigit())
            if p[2] == 'LEADER':
                key = (p[0], int(p[1])); out.setdefault(key, {}).setdefault('leaders', set()).add('?'); continue
            if multi: doc, ch, k, cx, cy, dx, dy, w, h, pcx, pcy, R, io = p[0], int(p[1]), int(p[2]), *map(float, p[3:7]), float(p[8]), float(p[9]), float(p[10]), float(p[11]), float(p[12]), p[14]
            else: doc, ch, k, cx, cy, dx, dy, w, h, pcx, pcy, R, io = p[0], 1, int(p[1]), *map(float, p[2:6]), float(p[7]), float(p[8]), float(p[9]), float(p[10]), float(p[11]), p[13]
            key = (doc, ch); e = out.setdefault(key, {})
            if 'slices' not in e:
                if doc not in dmap: continue
                e.update(chart_geom(dmap[doc])); e['doc'] = doc; e['lab'] = lab; e['R'] = R; e['pcx'] = pcx; e['pcy'] = pcy
                e['Rnote'] = 'apex' if lab in ('piezone', 'piezone2') else 'box'
                e['labels'] = {}; e['obs'] = {}
            e['labels'][k] = (w, h); e['obs'][k] = ((dx - w / 2) / 0.75, (dy - h / 2 - 1.8) / 0.75, io != 'OUT')
    return out
if __name__ == '__main__':
    C = load(); print(len(C), 'configurations from', collections.Counter(v['lab'] for v in C.values()))
    k = ('pl5-w360', 1); v = C[k]; print(k, v['R'], v['slices'][:2], v['kept'], {i: tuple(round(x, 1) if isinstance(x, float) else x for x in o) for i, o in v['obs'].items()})
