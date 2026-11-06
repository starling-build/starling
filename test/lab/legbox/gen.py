#!/usr/bin/env python3
"""lab legbox: variants of aascu 5864 slide 11 (chart5, bar+line, legend at the right in a manual box 0.4186 x 0.0907 of the
frame, 12 pt, two entries "2005" and "1995" laid in a row). Print page 11 of each deck only."""
import zipfile,sys,os
SRC="test/corpus/pptx/decks/aascu.org_workarea_downloadasset.aspx_id=5864.pptx"
W0='<c:w val="0.41859601730215767"/><c:h val="9.0728640966557889E-2"/>'
def w(v): return lambda x:x.replace('<c:w val="0.41859601730215767"/>',f'<c:w val="{v}"/>',1)
def h(v): return lambda x:x.replace('<c:h val="9.0728640966557889E-2"/></c:manualLayout></c:layout><c:txPr>',f'<c:h val="{v}"/></c:manualLayout></c:layout><c:txPr>',1)
def sz(v): return lambda x:x.replace('<a:defRPr sz="1200"><a:solidFill><a:schemeClr val="bg1"><a:lumMod val="10000"/>',f'<a:defRPr sz="{v}"><a:solidFill><a:schemeClr val="bg1"><a:lumMod val="10000"/>',1)
def pos(v): return lambda x:x.replace('<c:legendPos val="r"/>',f'<c:legendPos val="{v}"/>',1)
def names(x): return x.replace('<c:v>2005</c:v>','<c:v>2005 graduates</c:v>').replace('<c:v>1995</c:v>','<c:v>1995 graduates</c:v>')
V={"orig":lambda x:x,"w25":w(0.25),"w30":w(0.30),"w60":w(0.6),"w90":w(0.9),"s8":sz(800),"s16":sz(1600),"long":names,"h20":h(0.2),"t":pos("t"),"b":pos("b")}
os.makedirs("test/lab/legbox/decks",exist_ok=True)
for k,f in V.items():
    zi=zipfile.ZipFile(SRC)
    with zipfile.ZipFile(f"test/lab/legbox/decks/legbox-{k}.pptx","w",zipfile.ZIP_DEFLATED) as zo:
        for it in zi.infolist():
            b=zi.read(it.filename)
            if it.filename=="ppt/charts/chart5.xml":
                t=b.decode(); n=f(t)
                if k!="orig" and n==t: sys.exit("no change "+k)
                b=n.encode()
            zo.writestr(it,b)
