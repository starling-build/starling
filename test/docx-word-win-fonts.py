# Which faces the corpus asks for that this Windows box does not have, and
# what Word for Windows printed instead -- read from the reprints in
# test/corpus/docx/word-win (test/docx-word-win-reprint.py).
#
#   python -I test/docx-word-win-fonts.py [> word-win/fonts.txt]
#
# A face counts as present when any name in an installed font's name table
# (family, full, typographic family, in every language -- 宋体 is SimSun's
# Chinese name) matches it, or the document embeds it. For each missing face
# it lists the documents that ask for it and the PDF fonts those prints use
# that no document face accounts for: the substitutes.
import os, re, sys, zipfile, collections
import pymupdf
from fontTools.ttLib import TTFont, TTCollection

sys.stdout.reconfigure(encoding='utf-8')
HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, 'corpus', 'docx', 'docs')
WIN = os.path.join(HERE, 'corpus', 'docx', 'word-win')

def norm(s): return re.sub(r'[\s\-_]', '', s).lower()

installed, ps_of = set(), {}
for d in (os.path.join(os.environ.get('WINDIR', r'C:\Windows'), 'Fonts'),
          os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Microsoft', 'Windows', 'Fonts'),
          # Office's cloud fonts (Aptos, …), fetched on first use and Word's alone
          os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Microsoft', 'FontCache', '4', 'CloudFonts')):
    if not os.path.isdir(d): continue
    for f in (os.path.relpath(os.path.join(r, x), d) for r, _, xs in os.walk(d) for x in xs):
        if not f.lower().endswith(('.ttf', '.otf', '.ttc', '.otc')): continue
        try:
            fonts = TTCollection(os.path.join(d, f)).fonts if f.lower().endswith(('c',)) else [TTFont(os.path.join(d, f), lazy=True)]
        except Exception: continue
        for t in fonts:
            try: names = t['name'].names
            except Exception: continue
            fam = set()
            for n in names:
                if n.nameID in (1, 4, 6, 16):
                    try: fam.add(n.toUnicode())
                    except Exception: pass
            for n in fam:
                installed.add(norm(n))
                ps_of.setdefault(norm(n), set()).update(norm(m) for m in fam)

RFONTS = re.compile(r'<w:rFonts\s[^>]*>')
ATTR = re.compile(r'w:(?:ascii|hAnsi|eastAsia|cs)="([^"]+)"')
def requested(z):
    faces = set()
    for n in z.namelist():
        if re.match(r'word/(document|styles|numbering|header\d*|footer\d*|footnotes|endnotes)\.xml$', n):
            for r in RFONTS.findall(z.read(n).decode('utf-8', 'replace')):
                faces.update(ATTR.findall(r))
        elif re.match(r'word/theme/theme\d*\.xml$', n):
            x = z.read(n).decode('utf-8', 'replace')
            for blk in re.findall(r'<a:(?:major|minor)Font>.*?</a:(?:major|minor)Font>', x, re.S):
                faces.update(t for t in re.findall(r'<a:(?:latin|ea|cs)\s[^>]*typeface="([^"]+)"', blk) if t)
                faces.update(re.findall(r'<a:font script="(?:Hans|Hant|Jpan|Hang)" typeface="([^"]+)"', blk))
    embedded = set()
    if 'word/fontTable.xml' in z.namelist():
        x = z.read('word/fontTable.xml').decode('utf-8', 'replace')
        for name, body in re.findall(r'<w:font w:name="([^"]+)"[^>]*>(.*?)</w:font>', x, re.S):
            if '<w:embed' in body: embedded.add(name)
    return {f for f in faces if not f.startswith('+')}, embedded

missing_docs = collections.defaultdict(list)
subs = collections.defaultdict(collections.Counter)
n = 0
for f in sorted(os.listdir(WIN)):
    if not f.endswith('-orig.pdf'): continue
    key = f[:-len('-orig.pdf')]
    try: faces, embedded = requested(zipfile.ZipFile(os.path.join(DOCS, key + '.docx')))
    except Exception: continue
    n += 1
    miss = {x for x in faces if norm(x) not in installed and x not in embedded}
    if not miss: continue
    used = set()
    for p in pymupdf.open(os.path.join(WIN, f)):
        for ft in p.get_fonts(full=False):
            used.add(re.sub(r'^[A-Z]{6}\+', '', ft[3]).split(',')[0])
    # a PDF font no requested-and-present face accounts for
    present = set()
    for x in faces:
        present |= ps_of.get(norm(x), set())
    extra = {u for u in used if norm(u) not in present and not any(norm(u).startswith(norm(e)) for e in embedded)}
    for x in miss:
        missing_docs[x].append(key)
        subs[x].update(extra)
print(f'{n} reprints read; {len(missing_docs)} faces asked for and missing on this box')
for x, keys in sorted(missing_docs.items(), key=lambda kv: -len(kv[1])):
    top = ', '.join(f'{u} ({c})' for u, c in subs[x].most_common(4)) or '-'
    print(f'{x}\t{len(keys)} docs\tprinted in: {top}')
