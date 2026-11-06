#!/usr/bin/env python3
"""Lab sect563 (from lo-563123f3 p1): Word puts a heading after a continuous section break 2.0 pt lower than we do.
Each doc stacks 4 blocks: text line, a paragraph that carries a continuous sectPr, then a heading whose
spacing-before is 0/120/240/480. 'brk' docs have the break, 'ctl' docs the same without it. Compat 14 and 15.
Measure the baseline gap between the line before the break and the heading. usage: build.py OUTDIR"""
import sys, os, zipfile, re
src=open('/data/s/lenovo-5/starling/test/labs/sect563/../nest51/build.py').read() if False else None
import importlib.util
here=os.path.dirname(os.path.abspath(__file__))
spec=importlib.util.spec_from_file_location("n51",os.path.join(here,"..","nest51","build.py"))
n=importlib.util.module_from_spec(spec); spec.loader.exec_module(n)
W=n.W
PG='<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>'
def para(t,before=0,after=0,sz=20,brk=False,bold=False):
    sp=f'<w:spacing w:before="{before}" w:after="{after}" w:line="240" w:lineRule="auto"/>'
    sect=f'<w:sectPr><w:type w:val="continuous"/>{PG}</w:sectPr>' if brk else ''
    b='<w:b/>' if bold else ''
    mark=f'<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="{sz}"/></w:rPr>'
    return f'<w:p><w:pPr>{sp}{sect}{mark}</w:pPr>{run}</w:p>'
BEF=[0,120,240,480]
def build(out):
    os.makedirs(out,exist_ok=True)
    for mode in (14,15):
        for kind in ("brk","ctl","brkE","ctlE"):
            body=""
            for b in BEF:
                body+=para(f"{kind} m{mode} before-text {b}",after=0)
                # the break paragraph is an empty-ish line that ends section 1 (kept 1pt so it has a height)
                body+=(para("",sz=22,brk=(kind=="brkE")) if kind.endswith("E") else para("x",sz=2,brk=(kind=="brk")))
                body+=para(f"HEAD before={b}",before=b,sz=32,bold=True)
                body+=para("body line after heading",sz=20)
                body+=para("filler",sz=20)
            body+=f'<w:sectPr>{PG}</w:sectPr>'
            doc=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}</w:body></w:document>'
            path=os.path.join(out,f"sect563-{kind}{mode}.docx")
            with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED) as z:
                z.writestr("[Content_Types].xml",n.CT);z.writestr("_rels/.rels",n.RELS)
                z.writestr("word/_rels/document.xml.rels",n.DRELS);z.writestr("word/document.xml",doc)
                z.writestr("word/settings.xml",n.SETT.replace("{M}",str(mode)))
            print(path)
if __name__=="__main__": build(sys.argv[1])
