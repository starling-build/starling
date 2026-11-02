#!/usr/bin/env python3
"""Lab pf (Windows 01QbbApP, for amd-opus/starling-47): how many lines of an 8-line paragraph P Word leaves at the foot of a page.
Base = lo-000463df's own styles/settings/footer (two empty Normal paragraphs, body bottom ~778.9) and sectPr.
One page per start distance d (room from the end of the fillers to the body bottom), d = 14..120 step 2 (54 pages per doc).
Page = marker/filler paragraphs of exact 70pt lines (+ one tuning exact line), then P (Calibri 12, theme minorHAnsi).
Docs: pf-b{0,6,12}-l{100,115,150,200}-w{1,0}  (8 wrapped lines);  pf-br-b12-l150-w{1,0}  (3 wrapped + 5 w:br lines, as in the document).
gen.py ORIG.docx OUT"""
import sys, os, re, zipfile

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
parts = {n: z.read(n) for n in z.namelist()}
doc = parts['word/document.xml'].decode('utf8')
sect = re.search(r'<w:sectPr .*?</w:sectPr>', doc, re.S).group(0)
head = doc[:doc.index('<w:body>') + len('<w:body>')]
RPR = '<w:rPr><w:rFonts w:asciiTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi" w:cstheme="minorHAnsi"/></w:rPr>'
T1 = ('xxxxxxxxxxx Xxxxxxxxxxxx xxxx xxxxxxxxxxxxxxxxxxxxx Xxxxxxxxxxx xxx xxx Xxxx xxxxxxxxxxxxxxxx xxxxxxxxxxxx xxx x. x. Xxxxxxxxx xxxxx Xxxxxxxxxxxxxxxxxxx xx '
      'xxxxxxxxxxtigen. Xxx xxxxxx Xxxxxxxxxxxxx xxxxxx xxxx, xxxx xxx Xxxxxxxxxxxxxxxx xxxxxxxxxxxxx')
WRAP8 = 'Page 3 start ' + (T1 + ' ') * 3 + 'Xxxxxxxxxxxx xxxx xxxxx Xxxx xxxxx xxxxxxxx xx xxxxx.'
DS = list(range(14, 122, 2))
BODY = 841.9 - 70.85 - 56.7  # raw page body; the footer lifts the bottom to ~778.9 (708.05 tall)
HB = 778.9 - 70.85


def fill(first, mark, h):
    pb = '<w:pageBreakBefore/>' if first else ''
    r = '<w:r>%s<w:t>%s</w:t></w:r>' % (RPR, mark) if mark else ''
    return '<w:p><w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="%d" w:lineRule="exact"/></w:pPr>%s</w:p>' % (pb, round(h * 20), r)


def para(b, ls, widow, form):
    wc = '<w:widowControl/>' if widow else '<w:widowControl w:val="0"/>'
    if form == 'wrap':
        runs = '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % (RPR, WRAP8)
    else:
        runs = '<w:r>%s<w:t xml:space="preserve">Page 3 start %s</w:t>%s</w:r>' % (RPR, T1, ''.join('<w:br/><w:t>L%d</w:t>' % (45 + k) for k in range(5)))
    return '<w:p><w:pPr>%s<w:spacing w:before="%d" w:after="0" w:line="%d" w:lineRule="auto"/></w:pPr>%s</w:p>' % (wc, round(b * 20), ls * 12 // 5, runs)


def build(name, b, ls, widow, form):
    body = ''
    for i, d in enumerate(DS):
        room = HB - d
        n = int(room // 70)
        rem = room - 70 * n
        if rem < 1:
            n -= 1
            rem += 70
        body += fill(i > 0, 'P%d' % d, 70) + fill(False, '', 70) * (n - 1) + fill(False, '', rem) + para(b, ls, widow, form)
    d = head + body + sect + '</w:body></w:document>'
    p = dict(parts)
    p['word/document.xml'] = d.encode('utf8')
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for k, v in p.items():
            o.writestr(k, v)


if __name__ == '__main__':
    names = []
    for b in (0, 6, 12):
        for ls in (100, 115, 150, 200):
            for w in (1, 0):
                nm = 'pf-b%d-l%d-w%d' % (b, ls, w)
                build(nm, b, ls, w, 'wrap'); names.append(nm)
    for w in (1, 0):
        nm = 'pf-br-b12-l150-w%d' % w
        build(nm, 12, 150, w, 'br'); names.append(nm)
    open(os.path.join(out, 'names.txt'), 'w').write(' '.join(names))
    print(len(names))
