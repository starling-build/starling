#!/usr/bin/env python3
"""fmap.py ROOT OUT.tsv : requested font NAME -> face Word for Windows drew, over test/corpus/docx (756) and docx/lo.
Per document: every character of the document's runs is attributed to the font NAME its run resolves to (run rFonts, character
style, paragraph style chain, docDefaults; ascii/hAnsi for non-East-Asian characters, eastAsia for CJK; theme fonts resolved from
theme1.xml). A character attributed to exactly one name counts for that name; the PDF face(s) that drew that character (word-win
reference, embedded font name minus its subset prefix) are credited to (name, face). Counts: docs = documents, chars = distinct
characters credited."""
import sys, os, re, zipfile, collections, glob
import xml.etree.ElementTree as ET
import pymupdf
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
root, out = sys.argv[1], sys.argv[2]


def isea(c):
    o = ord(c)
    return (0x2E80 <= o <= 0x9FFF or 0xF900 <= o <= 0xFAFF or 0xFF00 <= o <= 0xFFEF or 0x3000 <= o <= 0x303F or 0x20000 <= o <= 0x2FFFF
            or 0xAC00 <= o <= 0xD7AF or 0x1100 <= o <= 0x11FF or 0x2018 <= o <= 0x201F and False)


def theme_fonts(z):
    t = {}
    try:
        x = ET.fromstring(z.read('word/theme/theme1.xml'))
    except Exception:
        return t
    for kind in ('major', 'minor'):
        f = x.find(f'.//{A}{kind}Font')
        if f is None:
            continue
        t[kind + 'Latin'] = (f.find(f'{A}latin').get('typeface') if f.find(f'{A}latin') is not None else '')
        t[kind + 'EastAsia'] = (f.find(f'{A}ea').get('typeface') if f.find(f'{A}ea') is not None else '')
        t[kind + 'Bidi'] = (f.find(f'{A}cs').get('typeface') if f.find(f'{A}cs') is not None else '')
        for s in f.findall(f'{A}font'):
            t[kind + '/' + s.get('script')] = s.get('typeface')
    return t


def rfonts(el, th, lang_ea):
    """el = w:rFonts -> dict ascii/ea names (None if not given)"""
    if el is None:
        return {}
    r = {}
    def th_name(v):
        kind = 'major' if v.startswith('major') else 'minor'
        if 'EastAsia' in v:
            n = th.get(kind + 'EastAsia') or ''
            if not n:
                script = {'zh-CN': 'Hans', 'zh-TW': 'Hant', 'ja-JP': 'Jpan', 'ko-KR': 'Hang'}.get(lang_ea or '', 'Hans')
                n = th.get(kind + '/' + script, '')
            return n
        if 'Bidi' in v:
            return th.get(kind + 'Bidi') or ''
        return th.get(kind + 'Latin') or ''
    for key, tk in (('ascii', 'asciiTheme'), ('hAnsi', 'hAnsiTheme'), ('eastAsia', 'eastAsiaTheme')):
        v = el.get(W + tk)
        if v:
            r[key] = th_name(v)
        elif el.get(W + key):
            r[key] = el.get(W + key)
    return r


def load_styles(z, th):
    st = {}
    dd = {}
    try:
        x = ET.fromstring(z.read('word/styles.xml'))
    except Exception:
        return st, dd, None
    lang_ea = None
    d = x.find(f'{W}docDefaults/{W}rPrDefault/{W}rPr')
    if d is not None:
        l = d.find(f'{W}lang')
        lang_ea = l.get(W + 'eastAsia') if l is not None else None
        dd = rfonts(d.find(f'{W}rFonts'), th, lang_ea)
    for s in x.findall(f'{W}style'):
        sid = s.get(W + 'styleId')
        b = s.find(f'{W}basedOn')
        rp = s.find(f'{W}rPr')
        st[sid] = (b.get(W + 'val') if b is not None else None, rfonts(rp.find(f'{W}rFonts'), th, lang_ea) if rp is not None else {}, s.get(W + 'default') == '1' and s.get(W + 'type') == 'paragraph')
    return st, dd, lang_ea


def style_chain(st, sid):
    r = {}
    chain = []
    while sid and sid in st and len(chain) < 20:
        chain.append(sid)
        sid = st[sid][0]
    for s in reversed(chain):
        r.update(st[s][1])
    return r


def doc_attr(path):
    z = zipfile.ZipFile(path)
    th = theme_fonts(z)
    st, dd, lang_ea = load_styles(z, th)
    default_p = next((k for k, v in st.items() if v[2]), None)
    names = collections.defaultdict(set)   # char -> set(name)
    parts = [n for n in z.namelist() if re.match(r'word/(document|header\d*|footer\d*|footnotes|endnotes)\.xml$', n)]
    for part in parts:
        try:
            x = ET.fromstring(z.read(part))
        except Exception:
            continue
        def walk(el, pfont):
            for ch in el:
                if ch.tag == W + 'p':
                    ps = ch.find(f'{W}pPr/{W}pStyle')
                    pf = style_chain(st, ps.get(W + 'val') if ps is not None else default_p)
                    for r in ch.iter(W + 'r'):
                        rp = r.find(f'{W}rPr')
                        f = dict(dd); f.update(pf)
                        if rp is not None:
                            rs = rp.find(f'{W}rStyle')
                            if rs is not None:
                                f.update(style_chain(st, rs.get(W + 'val')))
                            f.update(rfonts(rp.find(f'{W}rFonts'), th, lang_ea))
                        for t in r.iter(W + 't'):
                            for c in (t.text or ''):
                                if c.isspace():
                                    continue
                                n = f.get('eastAsia') if isea(c) else (f.get('ascii') or f.get('hAnsi'))
                                if n:
                                    names[c].add(n)
                else:
                    walk(ch, pfont)
        walk(x, None)
    return names


def pdf_faces(path):
    faces = collections.defaultdict(set)
    d = pymupdf.open(path)
    for p in d:
        for b in p.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                for s in l['spans']:
                    f = re.sub(r'^[A-Z]{6}\+', '', s['font'])
                    for c in s['text']:
                        if not c.isspace():
                            faces[c].add(f)
    return faces


docs = collections.Counter(); chars = collections.Counter(); requested = collections.Counter(); unseen = collections.Counter()
sets = [('756', os.path.join(root, 'test/corpus/docx')), ('lo', os.path.join(root, 'test/corpus/docx/lo'))]
ndoc = 0
for tag, base in sets:
    for dp in sorted(glob.glob(base + '/docs/*.docx')):
        nm = os.path.basename(dp)[:-5]
        pp = os.path.join(base, 'word-win', nm + '-orig.pdf')
        if not os.path.exists(pp):
            continue
        try:
            names = doc_attr(dp)
            faces = pdf_faces(pp)
        except Exception as e:
            sys.stderr.write(f'{nm}: {e}\n')
            continue
        ndoc += 1
        seen = set()
        for c, ns in names.items():
            for n in ns:
                requested[n] += 0
            if len(ns) != 1:
                continue
            n = next(iter(ns))
            if c not in faces:
                continue
            for f in faces[c]:
                chars[(n, f)] += 1
                seen.add((n, f))
        for k in seen:
            docs[k] += 1
        for n in {next(iter(v)) for v in names.values() if len(v) == 1}:
            requested[n] += 1
with open(out, 'w', encoding='utf8') as o:
    o.write('# requested\tface\tdocs\tchars\n')
    for (n, f), k in sorted(docs.items(), key=lambda kv: (kv[0][0], -kv[1])):
        o.write(f'{n}\t{f}\t{k}\t{chars[(n, f)]}\n')
    o.write(f'# documents processed: {ndoc}\n')
    o.write('# requested name -> documents using it (chars attributed to it alone)\n')
    for n, k in requested.most_common():
        o.write(f'#REQ\t{n}\t{k}\n')
print(ndoc, 'docs', len(docs), 'pairs')
