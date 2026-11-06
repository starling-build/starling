#!/usr/bin/env python3
"""Lab sect563 (lo-563123f3 p1): Word puts a heading after a continuous section break 2.0 pt lower than we do.
4 blocks per doc: text line, break paragraph, heading with space-before 0/120/240/480, two body lines.
brk/ctl = tiny 1pt 'x' break paragraph with / without the continuous sectPr; brkE/ctlE = EMPTY break paragraph at 11 pt
(as in the real doc). Compat 14 and 15. Needs ../nest51/build.py (branch history). usage: build.py OUTDIR"""
import sys, os, zipfile, importlib.util
here=os.path.dirname(os.path.abspath(__file__))
spec=importlib.util.spec_from_file_location("n51",os.path.join(here,"..","nest51","build.py"))
n=importlib.util.module_from_spec(spec); spec.loader.exec_module(n)
PG='<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>'
def para(t,before=0,sz=20,brk=False,bold=False):
    sp=f'<w:spacing w:before="{before}" w:after="0" w:line="240" w:lineRule="auto"/>'
    sect=f'<w:sectPr><w:type w:val="continuous"/>{PG}</w:sectPr>' if brk else ''
    rpr=f'<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>{"<w:b/>" if bold else ""}<w:sz w:val="{sz}"/></w:rPr>'
    run=f'<w:r>{rpr}<w:t xml:space="preserve">{t}</w:t></w:r>' if t else ''
    return f'<w:p><w:pPr>{sp}{sect}{rpr}</w:pPr>{run}</w:p>'
def build(out):
    os.makedirs(out,exist_ok=True)
    for mode in (14,15):
        for kind in ("brk","ctl","brkE","ctlE"):
            body=""
            for b in (0,120,240,480):
                body+=para(f"{kind} m{mode} before-text {b}")
                body+=para("",sz=22,brk=(kind=="brkE")) if kind.endswith("E") else para("x",sz=2,brk=(kind=="brk"))
                body+=para(f"HEAD before={b}",before=b,sz=32,bold=True)+para("body line after heading")+para("filler")
            body+=f'<w:sectPr>{PG}</w:sectPr>'
            doc=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {n.W}><w:body>{body}</w:body></w:document>'
            path=os.path.join(out,f"sect563-{kind}{mode}.docx")
            with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED) as z:
                z.writestr("[Content_Types].xml",n.CT);z.writestr("_rels/.rels",n.RELS)
                z.writestr("word/_rels/document.xml.rels",n.DRELS);z.writestr("word/document.xml",doc)
                z.writestr("word/settings.xml",n.SETT.replace("{M}",str(mode)))
            print(path)
if __name__=="__main__": build(sys.argv[1])
