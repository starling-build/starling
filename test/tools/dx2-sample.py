#!/usr/bin/env python3
# dx2 sampler: stratified docxcorp.us picks. usage: dx2.py LANGS... (default: all in probe.txt)
import sys, os, re, random, hashlib, subprocess, zipfile, glob, json, importlib.util, urllib.request
W = '/data/s/amd-7/dx2'; REPO = '/data/s/amd-7/starling'
DOCS = '/data/corpus-cache/staging/dx2/docs'; TMP = W + '/tmp'
BIN = REPO + '/.build-shared/release/OfficeApp'
TYPES = 'legal forms educational administrative policies correspondence reports reference technical creative'.split()
UA = 'starling-corpus-research/1.0'
os.makedirs(TMP, exist_ok=True)
import fitz
spec = importlib.util.spec_from_file_location('docx_features', REPO + '/test/tools/docx-features.py')
df = importlib.util.module_from_spec(spec); sys.modules['docx_features'] = df; spec.loader.exec_module(df)

have = set()
for f in glob.glob(REPO + '/test/corpus/docx/*/manifest.tsv') + glob.glob('/data/corpus-cache/staging/*/manifest.tsv') + [W + '/manifest.tsv']:
    try: have |= set(re.findall(r'\b[0-9a-f]{64}\b', open(f, errors='replace').read()))
    except Exception: pass
try:
    for f in subprocess.run(['git', '-C', REPO, 'show', 'origin/wip/corpus-docxcorp:test/corpus/docx/docxcorp/manifest.tsv'], capture_output=True, text=True).stdout.split('\n'):
        have |= set(re.findall(r'\b[0-9a-f]{64}\b', f))
except Exception: pass

def get(url, timeout=60):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    return urllib.request.urlopen(req, timeout=timeout).read()

EMAIL = re.compile(r'[\w.+-]+@[\w-]+\.[\w.-]+')
PHONE = re.compile(r'(?<!\d)(\+?\d{1,3}[ .-]?)?\(?\d{2,4}\)?[ .-]\d{3,4}[ .-]\d{3,4}(?!\d)')
CV = re.compile(r'curriculum vitae|résumé|resume\b|\bCV\b|currículum|lebenslauf|резюме|履歴書|简历|簡歷|date of birth|geburtsdatum|дата рождения', re.I)
def personal(path):
    try:
        z = zipfile.ZipFile(path); t = ''
        for n in z.namelist():
            if n.startswith('word/') and n.endswith('.xml') and ('document' in n or 'header' in n or 'footer' in n or 'footnotes' in n):
                t += re.sub(r'<[^>]+>', ' ', z.read(n).decode('utf8', 'replace'))
        if EMAIL.search(t): return 'email'
        if PHONE.search(t): return 'phone'
        if CV.search(t[:6000]): return 'cv'
    except Exception as e: return 'badzip'
    return ''

def render(path, key):
    out = f'{TMP}/{key}.pdf'
    env = dict(os.environ, OFFICE_FONT_SOURCE='bundled', OFFICE_WORD_FONTS='windows', STARLING_ICU=os.environ['STARLING_ICU'])
    env.pop('LD_LIBRARY_PATH', None)
    try:
        r = subprocess.run([BIN, '--convert', path, out], env=env, capture_output=True, timeout=120)
    except subprocess.TimeoutExpired:
        return 'timeout', 0, 0
    if r.returncode != 0 or not os.path.exists(out): return 'crash', 0, 0
    try:
        d = fitz.open(out); n = len(d); blank = 0
        for p in d:
            if not p.get_text().strip() and not p.get_images() and not p.get_drawings(): blank += 1
        d.close()
    except Exception: return 'crash', 0, 0
    finally:
        try: os.remove(out)
        except OSError: pass
    return ('blank' if blank else 'ok'), n, blank

def feats(path):
    try:
        f = df.features(path)
        return ','.join(k for k, v in f.items() if v is True or (isinstance(v, int) and not isinstance(v, bool) and v > 0 and not k.startswith(('size', 'page', 'bytes'))))[:200]
    except Exception: return ''

def process(lang, url, typ):
    did = url.rsplit('/', 1)[1][:-5]
    if did in have: return None
    p = f'{TMP}/{did}.docx'
    try:
        b = get(url)
    except Exception: return None
    if len(b) > 6_000_000 or len(b) < 2000: return None
    sha = hashlib.sha256(b).hexdigest()
    if sha in have: return None
    open(p, 'wb').write(b)
    why = personal(p)
    if why: os.remove(p); return ('reject', why)
    st, n, blank = render(p, did)
    if st == 'ok' or st == 'blank':
        if n > 40: os.remove(p); return ('reject', 'pages')
        if n == 0: os.remove(p); return ('reject', 'zero')
    have.add(sha); have.add(did)
    os.replace(p, f'{DOCS}/{did}.docx')
    return ('keep', [did, sha, lang, typ, url, str(n), feats(f'{DOCS}/{did}.docx'), st, str(len(b))])

def main():
    langs = sys.argv[1:] or [x.split(':')[0] for x in open(W + '/probe.txt').read().split() if int(x.split(':')[1]) > 0]
    mf = W + '/manifest.tsv'
    if not os.path.exists(mf): open(mf, 'w').write('doc_id\tfile_sha256\tlanguage\ttype\tsource_url\tpages_ours\tfeatures\trender\tbytes\n')
    for lang in langs:
        rnd = random.Random(lang); got = []; pools = {}; rej = {}
        for t in TYPES:
            try: urls = get(f'https://api.docxcorp.us/manifest?lang={lang}&type={t}&min_confidence=0.6').decode().split()
            except Exception: urls = []
            urls = [u for u in urls if u.endswith('.docx')]; rnd.shuffle(urls); pools[t] = urls
        quota = 30
        for rnd_i, per in enumerate((3, 30)):
            for t in TYPES:
                mine = sum(1 for g in got if g[3] == t); tries = 0
                while pools[t] and len(got) < quota and (mine < per if rnd_i == 0 else True) and tries < 40:
                    if rnd_i == 1 and mine >= 6: break
                    u = pools[t].pop(); tries += 1
                    r = process(lang, u, t)
                    if r is None: continue
                    if r[0] == 'reject': rej[r[1]] = rej.get(r[1], 0) + 1; continue
                    got.append(r[1]); mine += 1
        with open(mf, 'a') as f:
            for g in got: f.write('\t'.join(g) + '\n')
        bad = {s: [g[0][:12] for g in got if g[7] == s] for s in ('crash', 'timeout', 'blank')}
        print(f'{lang}: {len(got)} docs, {sum(int(g[5]) for g in got)} pages, {sum(int(g[8]) for g in got)//1024} KB, rejects {rej}, bad {json.dumps(bad)}', flush=True)
main()
