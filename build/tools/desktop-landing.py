#!/usr/bin/env python3
"""Build editable Desktop PPTX decks using the Office deck's package skeleton."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from xml.sax.saxutils import escape
import re
root=Path(__file__).resolve().parents[2]
slides=[
 ('STARLING DESKTOP / OPEN SOURCE','One desktop.\nMany possibilities.','A fast, native home for your apps.\nBuilt-in tools. Agent workspaces.\nRoom to explore.', ['NATIVE','APPS','WORKSPACES']),
 ('01 / A SHARED FOUNDATION','One program.\nEvery window.','Dock, menus and windows in one widget tree.\nCompiled Swift. GPU rendering.\nA desktop built on the Starling SDK.', ['WINDOWS','MENUS','DOCK']),
 ('02 / YOUR EVERYDAY TOOLS','Real apps.\nReal work.','Native Wayland and X11 support.\nChrome, VS Code and your Linux apps.\nFiles, Terminal, Settings and an App Store.', ['FILES','TERMINAL','APP STORE']),
 ('03 / AGENT WORKSPACES','Watch it work.\nStep in anytime.','Give an agent a dedicated workspace.\nThe apps it opens stay beside its terminal.\nWatch the work. Take over when you need to.', ['WORKSPACE','AGENT','LIVE APPS']),
 ('04 / MORE WAYS TO WORK','Your desktop.\nYour perspective.','Start with the familiar 2D desktop.\nExplore a living 3D city.\nTwo views are part of a much bigger desktop.', ['2D DESKTOP','3D CITY','YOUR APPS']),
 ('05 / GET STARLING DESKTOP','Built in the open.\nYours to explore.','An early preview for Ubuntu.\nWindows through WSL2.\nFree to use. Open source. Apache 2.0.', ['USE IT','STUDY IT','BUILD ON IT']),
]
colors=['165B46','F1F7F3','FBF1E5','EDF2FF','F4F0FA','165B46']
for tall in [False,True]:
 name='tall' if tall else 'wide'; w=450 if tall else 1280; m=32 if tall else 72
 with ZipFile(root/f'ui/openoffice/slides/landing-{name}.pptx') as source, ZipFile(root/f'ui/desktop/slides/landing-{name}.pptx','w',ZIP_DEFLATED) as dest:
  for info in source.infolist():
   data=source.read(info.filename)
   match=re.fullmatch(r'ppt/slides/slide([1-6])\.xml',info.filename)
   if match:
    n=int(match[1])-1; dark=n in [0,5]; ink='FFFFFF' if dark else '183A2D';muted='CCE4D9' if dark else '52685F'; bg=colors[n]; parts=[]; sid=2
    def box(text,x,y,width,height,size=20,color=ink,fill=None,bold=False):
     global sid
     sid+=1
     geom=f'<a:solidFill><a:srgbClr val="{fill}"/></a:solidFill>' if fill else '<a:noFill/>'
     paragraphs=''
     for line in text.split('\n'):
      paragraphs+=f'<a:p><a:pPr><a:lnSpc><a:spcPct val="100000"/></a:lnSpc></a:pPr><a:r><a:rPr sz="{size*100}" b="{int(bold)}"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>{escape(line)}</a:t></a:r></a:p>'
     parts.append(f'<p:sp><p:nvSpPr><p:cNvPr id="{sid}" name="Desktop {sid}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{int(x*12700)}" y="{int(y*12700)}"/><a:ext cx="{int(width*12700)}" cy="{int(height*12700)}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>{geom}<a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr lIns="0" tIns="0" rIns="0" bIns="0"/><a:lstStyle/>{paragraphs}</p:txBody></p:sp>')
    eyebrow,title,body,labels=slides[n]
    box(eyebrow,m,40,w-2*m,30,12 if tall else 16,bold=True)
    box(title,m,110,386 if tall else 760,220,46 if tall else 82,bold=True)
    box(body,m,280 if tall else 370,386 if tall else 710,150,21 if tall else 27,color=muted)
    for j,label in enumerate(labels):
     x=m if tall else 890; y=(450+j*64) if tall else (165+j*138); width=386 if tall else 318; height=52 if tall else 112
     box('',x,y,width,height,fill='244F3F' if dark else 'FFFFFF')
     box(label,x+20,y+(14 if tall else 36),width-40,40,18 if tall else 25,bold=True)
    box('STARLING / A SOFTWARE FACTORY',m,670,w-2*m,25,12 if tall else 16,color=muted)
    xml=source.read(info.filename).decode(); xml=re.sub(r'<p:bg>.*?</p:bg>',f'<p:bg><p:bgPr><a:solidFill><a:srgbClr val="{bg}"/></a:solidFill></p:bgPr></p:bg>',xml)
    xml=re.sub(r'<p:sp>.*?</p:sp>','',xml);xml=xml.replace('</p:spTree>',''.join(parts)+'</p:spTree>');data=xml.encode()
   dest.writestr(info.filename,data)
