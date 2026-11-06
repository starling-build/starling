#!/usr/bin/env python3
"""lab b3dlabels: variants of aascu 5864 slide 5 (a 3-D column chart, value labels 14 pt bold) — label size,
gapDepth, depthPercent, rotX/rotY, label position — to find where PowerPoint stands a 3-D column's value labels.
Print the deck, read page 5 only."""
import zipfile,re,sys,os
SRC="test/corpus/pptx/decks/aascu.org_workarea_downloadasset.aspx_id=5864.pptx"
V={
 "orig":lambda x:x,
 "s8":lambda x:x.replace('sz="1400" b="1"/></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr><c:showVal','sz="800" b="1"/></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr><c:showVal',1),
 "s20":lambda x:x.replace('sz="1400" b="1"/></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr><c:showVal','sz="2000" b="1"/></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr><c:showVal',1),
 "g50":lambda x:x.replace('<c:shape val="box"/>','<c:gapDepth val="50"/><c:shape val="box"/>',1),
 "g300":lambda x:x.replace('<c:shape val="box"/>','<c:gapDepth val="300"/><c:shape val="box"/>',1),
 "d300":lambda x:x.replace('<c:view3D>','<c:view3D><c:depthPercent val="300"/>',1) if False else x.replace('</c:view3D>','<c:depthPercent val="300"/></c:view3D>',1),
 "rx30":lambda x:x.replace('<c:view3D>','<c:view3D><c:rotX val="30"/>',1),
 "rx5":lambda x:x.replace('<c:view3D>','<c:view3D><c:rotX val="5"/>',1),
 "ry40":lambda x:x.replace('<c:view3D>','<c:view3D><c:rotY val="40"/>',1),
}
os.makedirs("test/lab/b3dlabels/decks",exist_ok=True)
for k,f in V.items():
    zi=zipfile.ZipFile(SRC); out=f"test/lab/b3dlabels/decks/b3d-{k}.pptx"
    with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as zo:
        for it in zi.infolist():
            b=zi.read(it.filename)
            if it.filename=="ppt/charts/chart1.xml":
                t=b.decode(); n=f(t); 
                b=n.encode()
            zo.writestr(it,b)
