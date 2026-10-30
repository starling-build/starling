#!/usr/bin/env python3
# test/labs/frame/build.py — lab "frame": where Word stands an inline drawing held by a page-anchored frame.
# Source: lo tdf147485-forcepoint (lo-e8c1ae371214f133): one paragraph, framePr w=9851 h=1669 hRule=exact x=1418 y=996 vAnchor/hAnchor page,
# holding a wp:inline group 136.45 x 88.45pt (effectExtent l=r=9pt), top margin 540 twips (27pt), left margin 1800. Word's print puts the group's
# ink box at x 70.8, y 22.8 (page coordinates); the frame says x 70.9, y 49.8. Ours: x 79.9, y 49.8.
# Each variant changes ONE thing from the original (v00), plus controls without the frame. Output: docx/*.docx.
import re, sys, zipfile, os
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "../../corpus/docx/lo/docs/lo-e8c1ae371214f133.docx")

def make(name, fn):
    zin = zipfile.ZipFile(SRC)
    out = os.path.join(HERE, "docx", name + ".docx")
    zout = zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED)
    for it in zin.infolist():
        d = zin.read(it.filename)
        if it.filename == "word/document.xml":
            d = fn(d.decode("utf8")).encode("utf8")
        zout.writestr(it, d)
    zout.close()

def frame(h=None, y=None, rule=None, x=None):
    def f(s):
        if h is not None: s = s.replace('w:h="1669"', 'w:h="%d"' % h)
        if y is not None: s = s.replace('w:y="996"', 'w:y="%d"' % y)
        if x is not None: s = s.replace('w:x="1418"', 'w:x="%d"' % x)
        if rule is not None: s = s.replace('w:hRule="exact"', 'w:hRule="%s"' % rule)
        return s
    return f

def margin_top(t): return lambda s: re.sub(r'(<w:pgMar[^>]*w:top=")\d+', r'\g<1>%d' % t, s)
def effect(l): return lambda s: re.sub(r'<wp:effectExtent [^>]*/>', '<wp:effectExtent l="%d" t="0" r="%d" b="0"/>' % (l, l), s)
def scale_h(k):
    # the drawing's height times k: wp:extent cy and the group's a:ext cy (its chExt keeps the content's scale)
    def f(s):
        s = re.sub(r'(<wp:extent cx="\d+" cy=")(\d+)', lambda m: m.group(1) + str(int(int(m.group(2)) * k)), s)
        s = re.sub(r'(<wpg:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\d+" cy=")(\d+)', lambda m: m.group(1) + str(int(int(m.group(2)) * k)), s)
        return s
    return f
def noframe(s): return re.sub(r'<w:framePr [^>]*/>', '', s)
def compose(*fs):
    def f(s):
        for g in fs: s = g(s)
        return s
    return f

V = [
 ("v00-original",        lambda s: s),
 # frame height (twips): the drawing is 1769 twips (88.45pt) tall
 ("v01-h1000-exact",     frame(h=1000)),
 ("v02-h2400-exact",     frame(h=2400)),
 ("v03-h1669-atLeast",   frame(rule="atLeast")),
 ("v04-h1000-atLeast",   frame(h=1000, rule="atLeast")),
 # frame y (twips): 996 = 49.8pt
 ("v05-y1500",           frame(y=1500)),
 ("v06-y2400",           frame(y=2400)),
 ("v07-y400",            frame(y=400)),
 # top margin (twips): 540 = 27pt
 ("v08-top1440",         margin_top(1440)),
 ("v09-top0",            margin_top(0)),
 ("v10-top1440-y2400",   compose(margin_top(1440), frame(y=2400))),
 # the drawing's height: x0.5 (44pt), x1.6 (141pt)
 ("v11-draw-half",       scale_h(0.5)),
 ("v12-draw-x1.6",       scale_h(1.6)),
 ("v13-draw-half-h1000", compose(scale_h(0.5), frame(h=1000))),
 # the 9pt on x: effectExtent l=r (EMU)
 ("v14-effect0",         effect(0)),
 ("v15-effect228600",    effect(228600)),
 ("v16-x2000",           frame(x=2000)),
 # controls: no frame — the paragraph in the flow (the group's own place from the top margin and the left margin)
 ("c1-noframe",          noframe),
 ("c2-noframe-top1440",  compose(noframe, margin_top(1440))),
 ("c3-noframe-effect0",  compose(noframe, effect(0))),
]
if __name__ == "__main__":
    os.makedirs(os.path.join(HERE, "docx"), exist_ok=True)
    for name, fn in V: make(name, fn)
    print(len(V), "documents")
