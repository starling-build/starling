#!/usr/bin/env python3
"""Lab balloon: how Word for Windows stacks the margin balloons of a link item that wraps.

Built from test/corpus/docx/delins.docx (its styles, numbering, page). delins' item "Advanced Indexing Techniques with Apache
Lucene - Michael Busch. March 25th @ 14:00" wraps one word ("14:00") onto a second line; there Word prints that second line's
three balloons as Field Code Changed, Formatted, Formatted where every other item (including Apache Droids, same markup, also
wrapped) prints Formatted, Formatted, Field Code Changed. This lab varies one thing at a time. Each item is a bullet, inside one
tracked insertion, holding a HYPERLINK field whose code and result were reformatted, then plain text; the code run and the
result carry a format change.

  w1    short item, the wrapping item (delins' own), short item
  n1    the same three, the middle one shortened so it does not wrap
  w1s   the wrapping item alone
  w2c1  w1 with a comment on "March" (line 1 of the wrapping item)
  w2c2  w1 with a comment on "14:00" (line 2)
  n2c   n1 with a comment on "March"
  w3    the wrapping item twice in a row, then a short one
  w4    the wrapping item with one more word so line 2 holds two words ("March 25th @ 14:00 sharp"), alone
  ov1   14 short items: a column of 42 balloons, pushed far below its anchors
  ov2   14 items, every third wrapping
  ov3   delins' own run of nine items (its paragraphs 13-21), the wrapping one in the same place
  ov4   four short items, then ov3's nine

Print each to PDF in Word for Windows; compare the order of the Formatted / Field Code Changed / Commented balloons in the
margin column and the x where each balloon's leader meets the text.
Usage: gen.py OUTDIR
"""
import re, sys, zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[2] / "corpus/docx/docs/delins.docx"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
D = 'w:author="lab" w:date="2009-03-01T10:00:00Z"'
n = [100]


def nid():
    n[0] += 1
    return n[0]


FONTS = '<w:rFonts w:ascii="Times New Roman" w:eastAsia="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'


def run(t, changed=False, link=False):
    """delins' run: Times New Roman 12; a reformatted one says w:lang en-US where it was unset (Word: "Formatted: English (United States)")."""
    color, under = ('<w:color w:val="0000FF"/>', '<w:u w:val="single"/>') if link else ("", "")
    body = lambda lang: f'{FONTS}{color}<w:sz w:val="24"/><w:szCs w:val="24"/>{under}{lang}'
    new = body('<w:lang w:val="en-US" w:eastAsia="ru-RU"/>')
    if not changed:
        return f'<w:r><w:rPr>{new}</w:rPr>{t}</w:r>'
    old = body('<w:lang w:eastAsia="ru-RU"/>')
    return f'<w:r><w:rPr>{new}<w:rPrChange w:id="{nid()}" {D}><w:rPr>{old}</w:rPr></w:rPrChange></w:rPr>{t}</w:r>'


def text(s):
    return f'<w:t xml:space="preserve">{s}</w:t>'


def item(link, tail, comment=None):
    """comment: a word of the tail to comment on, or None."""
    cid = nid()
    parts = [run('<w:fldChar w:fldCharType="begin"/>'),
             run(f'<w:instrText xml:space="preserve"> HYPERLINK "http://example.org/{cid}" </w:instrText>', changed=True),
             run('<w:fldChar w:fldCharType="separate"/>'),
             run(text(link), changed=True, link=True),
             run('<w:fldChar w:fldCharType="end"/>')]
    first, *rest = tail
    parts.append(run(text(first), changed=True))
    for piece in rest:
        if comment and piece.strip() == comment:
            parts.append(f'<w:commentRangeStart w:id="{cid}"/>' + run(text(piece)) + f'<w:commentRangeEnd w:id="{cid}"/>'
                         + f'<w:r><w:rPr><w:rStyle w:val="CommentReference"/></w:rPr><w:commentReference w:id="{cid}"/></w:r>')
        else:
            parts.append(run(text(piece)))
    ppr = (f'<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="3"/></w:numPr>'
           f'<w:spacing w:before="100" w:beforeAutospacing="1" w:after="100" w:afterAutospacing="1" w:line="240" w:lineRule="auto"/>'
           f'<w:rPr><w:ins w:id="{nid()}" {D}/><w:sz w:val="24"/></w:rPr></w:pPr>')
    return f'<w:p>{ppr}<w:ins w:id="{nid()}" {D}>{"".join(parts)}</w:ins></w:p>', cid


LONG = ("Advanced Indexing Techniques with Apache Lucene", [" - Michael Busch. ", "March", " 25th @ ", "14:00"])
SHORTW = ("Advanced Indexing", [" - Michael Busch. ", "March", " 25th @ ", "14:00"])
OTHER1 = ("Lucene/Solr Case Studies", [" - Erik Hatcher. ", "March", " 25th @ ", "13:00"])
OTHER2 = ("Apache Droids - an intelligent standalone robot framework", [" - Thorsten Scherler. ", "March", " 26th @ ", "15:00"])
LONG2 = (LONG[0], LONG[1][:-1] + ["14:00 sharp"])

def short(i):
    return (f"Session number {i}", [f" - Speaker {i}. ", "March", f" 25th @ {10 + i % 8}:00"])


# delins' own run of items (its paragraphs 13-21), where Word prints C, F, F for the group of "Apache Solr - A Case Study"
DELINS = [("Lucene will be extremely well represented", [" - Many speakers. ", "March", " 24th @ 10:00"]),
          ("Lucene Boot Camp - A two day training session", [" - Grant Ingersoll. ", "March", " 23rd @ 09:00"]),
          ("Solr Boot Camp - A one day training session", [" - Erik Hatcher. ", "March", " 24th @ 09:00"]),
          ("Introducing Apache Mahout", [" - Grant Ingersoll. ", "March", " 25th @ 10:00"]),
          OTHER1,
          LONG,
          ("Apache Solr - A Case Study", [" - Uri Boness. ", "March", " 26th @ 17:30"]),
          ("Best of breed - httpd, forrest, solr and lucene", [" - Many speakers. ", "March", " 26th @ 14:00"]),
          OTHER2]

def cut(items, commented):
    return [(a, b, "March") if k < commented else (a, b) for k, (a, b) in enumerate(short(i) for i in range(items))]


# N balloons = 3 per item (Formatted, Formatted, Field Code Changed) + 1 per item with a comment
DOCS = {f"cut{3 * k + j}": cut(k, j) for k, j in ((9, 0), (9, 1), (9, 2), (10, 0), (10, 1), (10, 2), (11, 0), (12, 0))}


def build(name, items, out):
    n[0] = 100
    body, comments = [], []
    for it in items:
        link, tail = it[0], it[1]
        c = it[2] if len(it) > 2 else None
        xml, cid = item(link, tail, c)
        body.append(xml)
        if c:
            comments.append(cid)
    zin = zipfile.ZipFile(BASE)
    doc = zin.read("word/document.xml").decode("utf8")
    head = doc[:doc.index("<w:body>") + 8]
    sect = doc[doc.rindex("<w:sectPr"):]
    new = head + "".join(body) + sect
    ct = zin.read("[Content_Types].xml").decode("utf8")
    rels = zin.read("word/_rels/document.xml.rels").decode("utf8")
    files = {}
    if comments:
        cx = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:comments xmlns:w="{W}">'
              + "".join(f'<w:comment w:id="{c}" w:author="lab" w:date="2009-03-01T10:00:00Z" w:initials="L"><w:p><w:r><w:t>note</w:t></w:r></w:p></w:comment>'
                        for c in comments) + '</w:comments>')
        files["word/comments.xml"] = cx
        ct = ct.replace("</Types>", '<Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/></Types>')
        rels = rels.replace("</Relationships>", '<Relationship Id="rIdLab1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/></Relationships>')
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename == "word/document.xml": data = new.encode("utf8")
            elif info.filename == "[Content_Types].xml": data = ct.encode("utf8")
            elif info.filename == "word/_rels/document.xml.rels": data = rels.encode("utf8")
            z.writestr(info.filename, data)
        for k, v in files.items():
            z.writestr(k, v)


if __name__ == "__main__":
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    for name, items in DOCS.items():
        build(name, items, out / f"balloon-{name}.docx")
    print(f"wrote {len(DOCS)} documents to {out}")
