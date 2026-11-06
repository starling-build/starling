#!/usr/bin/env python3
"""Lab hdr264 (zh-264d7516 p21): body starts 2.2 pt lower in Word than in ours when the header ends in an EMPTY paragraph.
Header = one 16 pt line + an empty paragraph whose mark size varies (1/9/18/40 pt), under docGrid none / lines 315 pt-twips,
paragraph snapToGrid 0 or 1, font Arial or SimSun. Top margin is small so the header pushes the body down.
Measure the baseline of the body line "BODY". usage: build.py OUTDIR   (needs ../nest51/build.py from branch history)"""
import sys, os, zipfile, importlib.util
here=os.path.dirname(os.path.abspath(__file__))
spec=importlib.util.spec_from_file_location("n51",os.path.join(here,"..","nest51","build.py"))
n=importlib.util.module_from_spec(spec); spec.loader.exec_module(n)
NS=n.W
CT=n.CT.replace('</Types>','<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/></Types>')
DR=n.DRELS.replace('</Relationships>','<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/></Relationships>')
def build(out):
    os.makedirs(out,exist_ok=True)
    for font in ("Arial","SimSun"):
        for grid in ("none","g315"):
            for snap in (0,1):
                for sz in (2,9,18,40):
                    if font=="SimSun" and sz in (2,40): continue
                    code=f"{font}-{grid}-s{snap}-z{sz}"
                    rf=f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:eastAsia="{font}"/>'
                    sn=f'<w:snapToGrid w:val="{snap}"/>'
                    hdr=(f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr {NS}>'
                         f'<w:p><w:pPr>{sn}</w:pPr><w:r><w:rPr>{rf}<w:sz w:val="32"/></w:rPr><w:t>HEADER</w:t></w:r></w:p>'
                         f'<w:p><w:pPr>{sn}<w:rPr>{rf}<w:sz w:val="{sz*2}"/></w:rPr></w:pPr></w:p></w:hdr>')
                    dg='' if grid=="none" else '<w:docGrid w:type="lines" w:linePitch="315"/>'
                    body=(f'<w:p><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/></w:rPr><w:t>BODY {code}</w:t></w:r></w:p>'
                          f'<w:sectPr><w:headerReference w:type="default" r:id="rId9"/><w:pgSz w:w="11906" w:h="16838"/>'
                          f'<w:pgMar w:top="1000" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="708" w:gutter="0"/>{dg}</w:sectPr>')
                    doc=f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS} xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>{body}</w:body></w:document>'
                    hdr=hdr
                    path=os.path.join(out,f"hdr264-{code}.docx")
                    with zipfile.ZipFile(path,"w",zipfile.ZIP_DEFLATED) as z:
                        z.writestr("[Content_Types].xml",CT);z.writestr("_rels/.rels",n.RELS)
                        z.writestr("word/_rels/document.xml.rels",DR);z.writestr("word/document.xml",doc)
                        z.writestr("word/header1.xml",hdr);z.writestr("word/settings.xml",n.SETT.replace("{M}","15"))
                    print(path)
if __name__=="__main__": build(sys.argv[1])
