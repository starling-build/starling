#!/usr/bin/env python3
"""Render a 1080p narrated comparison film from the frozen PDFs.

PDF excerpts retain their aspect ratio. Captions are timed to individual
speech files. Transitions reveal the next real comparison, with no fake UI.
Requires Pillow, PyMuPDF, NumPy and ffmpeg. Run narrate.py and prepare.py first.
"""
import json
import math
import re
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont
import pymupdf

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts/office-compatibility'
ASSETS = OUT / 'assets'
FRAMES = OUT / 'frames'
FRAMES.mkdir(exist_ok=True)
W, H, FPS = 1920, 1080, 24
BG, INK, MUTED, BLUE = '#f5f7fc', '#16243c', '#64718a', '#2849df'
GREEN, ORANGE = '#11775e', '#a65c27'
FONT = Path('/System/Library/Fonts/Supplemental')

def font(size, bold=False):
    return ImageFont.truetype(str(FONT / ('Arial Bold.ttf' if bold else 'Arial.ttf')), size)

def label(im, xy, text, size=28, fill=INK, bold=False):
    ImageDraw.Draw(im).text(xy, text, font=font(size, bold), fill=fill)

def wrapped(im, xy, text, width, size=28, fill=INK, bold=False, gap=10):
    x, y = xy
    f = font(size, bold)
    words, lines, line = text.split(), [], ''
    for word in words:
        candidate = (line + ' ' + word).strip()
        if f.getlength(candidate) > width and line:
            lines.append(line); line = word
        else:
            line = candidate
    if line: lines.append(line)
    for line in lines:
        label(im, (x,y), line, size, fill, bold); y += size + gap
    return y

def card(im, box, fill='white', outline='#dce2ef'):
    ImageDraw.Draw(im).rounded_rectangle(box, radius=18, fill=fill, outline=outline, width=2)

def pdf_image(name, page=0, crop=None, scale=2):
    with pymupdf.open(ASSETS / (name+'.pdf')) as doc:
        pg = doc[page]
        clip = pymupdf.Rect(crop) if crop else pg.rect
        pix = pg.get_pixmap(matrix=pymupdf.Matrix(scale,scale), clip=clip, alpha=False)
        return Image.frombytes('RGB',(pix.width,pix.height),pix.samples)

def fit(im, pic, box):
    x,y,x2,y2=box
    pic=pic.copy(); pic.thumbnail((int(x2-x),int(y2-y)),Image.Resampling.LANCZOS)
    im.paste(pic,(round(x+(x2-x-pic.width)/2),round(y+(y2-y-pic.height)/2)))

def panel(im, name, title, box, page=0, crop=None, color=BLUE):
    x,y,x2,y2=box
    card(im,box)
    ImageDraw.Draw(im).rounded_rectangle((x+20,y+18,x+28,y+52),radius=4,fill=color)
    label(im,(x+42,y+17),title,26,color,True)
    fit(im,pdf_image(name,page,crop),(x+20,y+72,x2-20,y2-18))

def base(scene):
    im=Image.new('RGB',(W,H),BG)
    label(im,(70,37),'STARLING OFFICE',25,BLUE,True)
    label(im,(1440,39),'COMPATIBILITY DIARY',21,MUTED)
    ImageDraw.Draw(im).line((70,85,1850,85),fill='#dce2ef',width=2)
    label(im,(70,116),scene['eyebrow'],22,BLUE,True)
    label(im,(70,155),scene['title'],52,INK,True)
    label(im,(72,225),scene['subtitle'],25,MUTED)
    label(im,(70,903),'DEVELOPMENT SNAPSHOT · 16 OCT 2026',18,MUTED)
    label(im,(1480,903),'starling-build / starling',18,MUTED)
    return im

def diff_pane(comparison, page, pane, crop=None):
    """Extract an original pane from pdf-diff.py, without recomputing the mask."""
    paths = list((OUT / 'diffs' / comparison).glob(f'pair-*-p{page+1}.png'))
    assert len(paths) == 1, paths
    with Image.open(paths[0]) as combined:
        width = (combined.width - 20) // 3
        pic = combined.crop((pane*(width+10), 0, pane*(width+10)+width, combined.height))
    if crop:
        pic = pic.crop(tuple(round(v*2) for v in crop))
    return pic

def image_panel(im, pic, title, box, color=BLUE):
    x,y,x2,y2 = box
    card(im, box)
    label(im, (x+24,y+20), title, 25, color, True)
    fit(im, pic, (x+20,y+75,x2-20,y2-20))

def diff_score(comparison, page):
    output = (OUT/'diffs'/comparison/'output.txt').read_text()
    return re.search(rf'page\s+{page+1}\s+([\d.]+)%', output).group(1)

def draw_scene(scene):
    im=base(scene);kind=scene['kind']; d=ImageDraw.Draw(im)
    if kind=='problem':
        panel(im,'slides-reference','MICROSOFT POWERPOINT',(70,305,945,825),crop=(95,100,820,430))
        panel(im,'slides-before','STARLING · EARLIER OUTPUT',(975,305,1850,825),crop=(95,100,820,430),color=ORANGE)
        label(im,(90,848),'Same source file. Different colors, title, labels and legend.',29,INK,True)
    elif kind=='corpus':
        for i,(name,title,items,page) in enumerate([
            ('writer-reference','DOCUMENTS','Tables / wrapping / line heights',3),
            ('slides-reference','PRESENTATIONS','Themes / charts / text layout',0),
            ('sheets-reference','SPREADSHEETS','Labels / print areas / page breaks',0)]):
            x=70+600*i
            panel(im,name,title,(x,300,x+580,760),page=page)
            wrapped(im,(x+20,790),items,540,27,INK,True)
    elif kind=='workflow':
        card(im,(70,435,470,665),BLUE,BLUE)
        label(im,(100,475),'ONE INPUT FILE',32,'white',True)
        label(im,(100,540),'DOCX / PPTX / XLSX',28,'white')
        for y,title,detail in [(310,'MICROSOFT OFFICE','Word / PowerPoint / Excel'),(625,'STARLING OFFICE','Writer / Slides / Sheets')]:
            card(im,(565,y,1105,y+200))
            label(im,(595,y+28),title,32,BLUE,True)
            label(im,(595,y+90),detail,27,MUTED)
            d.line((470,550,515,550,515,y+100,565,y+100),fill=BLUE,width=4)
            d.line((1105,y+100,1190,y+100),fill=BLUE,width=4)
            card(im,(1190,y,1850,y+200))
            label(im,(1220,y+28),'REFERENCE PDF' if y==310 else 'STARLING PDF',34,INK,True)
            label(im,(1220,y+93),'Saved visual source of truth' if y==310 else 'Compare against the reference',28,MUTED)
        label(im,(620,545),'Preserve reference settings and fonts.',27,MUTED)
    elif kind=='exports':
        card(im,(70,305,945,860));card(im,(975,305,1850,860))
        label(im,(100,335),'MICROSOFT REFERENCE AUTOMATION',25,BLUE,True)
        for i,(app,script,detail) in enumerate([
            ('PowerPoint','pptx-powerpoint-pdf.applescript','Save as PDF'),
            ('Word','docx-word-pdf.applescript','Print dialog → Save as PDF'),
            ('Excel','xlsx-excel-pdf.ps1','Windows COM → ExportAsFixedFormat')]):
            y=405+145*i
            label(im,(100,y),app,31,INK,True)
            label(im,(100,y+43),'test/'+script,25,BLUE)
            label(im,(100,y+78),detail,24,MUTED)
        label(im,(1005,335),'STARLING COMMAND-LINE EXPORTS',25,BLUE,True)
        for i,(app,flag,ext) in enumerate([('Slides','--deck-pdf','pptx'),('Writer','--convert','docx'),('Sheets','--sheet-pdf','xlsx')]):
            y=405+145*i
            label(im,(1005,y),app,31,INK,True)
            label(im,(1005,y+47),f'OfficeApp {flag} input.{ext} output.pdf',26,BLUE)
        label(im,(1005,819),'Input/output names abbreviated for readability.',22,MUTED)
    elif kind=='diff-method':
        card(im,(70,305,1850,705),'#15233b','#15233b')
        lines=[('$ cd artifacts/office-compatibility', '#b9c8f6'),
               ('$ python ../../test/pdf-diff.py \\', 'white'),
               ('    assets/slides-reference.pdf assets/slides-before.pdf \\', 'white'),
               ('    diffs/slides-before 2', 'white')]
        output=(OUT/'diffs/slides-before/output.txt').read_text().strip().splitlines()
        lines += [(s,'#a9e6cd') for s in output]
        for i,(line,color) in enumerate(lines):
            label(im,(105,332+i*55),line,29,color)
        for i,(title,detail) in enumerate([('144 dpi','Rasterize both pages'),('RGB difference > 32','Mark changed pixels red'),('3-panel PNG','Reference / Starling / mask')]):
            x=70+i*600;card(im,(x,740,x+580,865))
            label(im,(x+22,758),title,31,BLUE,True)
            label(im,(x+22,810),detail,25,MUTED)
    elif kind=='diff':
        key=scene['comparison'];page=scene['page'];crop=scene.get('crop')
        if key.startswith('slides'):crop=(95,100,820,430)
        for i,title in enumerate(['MICROSOFT REFERENCE','STARLING OUTPUT','ACTUAL DIFFERENCE MASK']):
            x=70+600*i
            image_panel(im,diff_pane(key,page,i,crop),title,(x,310,x+580,760),ORANGE if i==2 else BLUE)
        card(im,(70,790,1850,875))
        label(im,(95,808),f'{diff_score(key,page)}% of page {page+1} differs',36,BLUE,True)
        label(im,(840,819),'Matching crops shown; score uses the complete page.',25,MUTED)
    elif kind=='writer-diffs':
        for i,(key,title) in enumerate([('writer-before','BEFORE · 7.50% OF PAGE 4'),('writer-after','AFTER · 3.81% OF PAGE 4')]):
            image_panel(im,diff_pane(key,3,2,(62,60,545,345)),title,(70+905*i,300,945+905*i,820),ORANGE if i==0 else GREEN)
        label(im,(90,848),'Red masks from the comparator · 5 pages before → 4 pages after, matching Word',28,INK,True)
    elif kind in ('slides-before','slides-after'):
        panel(im,'slides-reference','MICROSOFT POWERPOINT',(70,295,945,855),crop=(95,100,820,430))
        after=kind.endswith('after')
        panel(im,'slides-current' if after else 'slides-before','STARLING · CURRENT' if after else 'STARLING · EARLIER',(975,295,1850,855),crop=(95,100,820,430),color=GREEN if after else ORANGE)
    elif kind in ('writer-before','writer-after'):
        panel(im,'writer-reference','MICROSOFT WORD · PAGE 4',(70,295,945,855),page=3,crop=(62,60,545,345))
        after=kind.endswith('after')
        panel(im,'writer-after' if after else 'writer-before','STARLING · AFTER FIX' if after else 'STARLING · BEFORE FIX',(975,295,1850,855),page=3,crop=(62,60,545,345),color=GREEN if after else ORANGE)
        label(im,(90,865),'Same crop and scale on both sides. Compare the heading and the first table row.',20,MUTED)
    elif kind in ('sheets-before','sheets-after'):
        after=kind.endswith('after')
        panel(im,'sheets-reference','MICROSOFT EXCEL',(70,295,945,855),crop=(85,80,535,440))
        panel(im,'sheets-current' if after else 'sheets-before','STARLING · CURRENT' if after else 'STARLING · EARLIER',(975,295,1850,855),crop=(85,65,535,425) if after else (35,45,485,405),color=GREEN if after else ORANGE)
        label(im,(90,865),'Still open: some label text and percentages differ.' if after else 'Chart excerpts enlarged for readability; page layout is not scored in this view.',20,MUTED)
    elif kind in ('opening','closing'):
        if kind=='opening':
            panel(im,'slides-before','EARLIER',(70,310,945,825),crop=(95,100,820,430),color=ORANGE)
            panel(im,'slides-current','CURRENT',(975,310,1850,825),crop=(95,100,820,430),color=GREEN)
            label(im,(72,850),'Real test documents. Actual exports. Changes you can inspect.',26,INK,True)
        else:
            items=[('writer-current','WRITER',3,(62,60,545,345)),('slides-current','SLIDES',0,(95,100,820,430)),('sheets-current','SHEETS',0,(85,65,535,425))]
            for i,(name,title,page,crop) in enumerate(items):
                panel(im,name,title,(70+600*i,315,650+600*i,680),page,crop)
            card(im,(70,720,1850,865),BLUE,BLUE)
            label(im,(100,744),'Try a sample. Report a mismatch. Help improve the next build.',37,'white',True)
            label(im,(100,800),'Test excerpts: Apache POI and LibreOffice collections; source details in the companion notes.',23,'#e1e8ff')
    elif kind=='checks':
        cards=[('01','READ','Can we interpret the file?','Content, structure and relationships.'),('02','RENDER','Does the layout agree?','Fonts, wrapping, charts and pagination.'),('03','SAVE BACK','Does Office reopen it?','Preserve content; investigate repair warnings.')]
        for i,(n,title,q,detail) in enumerate(cards):
            x=70+600*i;card(im,(x,330,x+580,810))
            label(im,(x+36,365),n,80,BLUE,True);label(im,(x+36,480),title,40,INK,True)
            wrapped(im,(x+36,555),q,490,32,INK,True)
            wrapped(im,(x+36,665),detail,490,27,MUTED)
    elif kind=='reference':
        panel(im,'slides-reference','MICROSOFT EXPORT',(70,310,740,830),crop=(95,100,820,430))
        panel(im,'slides-current','STARLING EXPORT',(1180,310,1850,830),crop=(95,100,820,430))
        label(im,(815,415),'SAME FILE',34,BLUE,True)
        wrapped(im,(805,490),'Compare pages',300,36,INK,True)
        wrapped(im,(805,595),'Find the first meaningful difference.',290,28,MUTED)
        d.line((785,550,1135,550),fill=BLUE,width=4)
    elif kind=='chart-steps':
        panel(im,'slides-current','CURRENT STARLING EXPORT',(660,310,1850,850),crop=(95,100,820,430))
        steps=[('515f4659','Chart theme'),('7bdd9f8e','Title formatting'),('70c6bd7a','Axis labels'),('730f2328','Labels from cells'),('51852676','Legend and plot width')]
        for i,(sha,title) in enumerate(steps):
            y=320+i*105;card(im,(70,y,620,y+90));label(im,(95,y+13),title,29,INK,True);label(im,(95,y+51),sha,21,MUTED)
    elif kind=='timeline':
        dates=[('12 OCT','Sheets printing','87b3cc2c'),('13 OCT','Chart formatting','515f4659'),('14 OCT','Floating pictures','e9ad2983'),('15 OCT','Blank-line height','f4cc1940'),('16 OCT','Pie chart labels','d96594ce')]
        d.line((180,405,1740,405),fill='#b9c8f6',width=6)
        for i,(date,title,sha) in enumerate(dates):
            x=70+i*360;d.ellipse((x+108,390,x+138,420),fill=BLUE)
            label(im,(x+20,325),date,37,BLUE,True);card(im,(x,465,x+340,730))
            wrapped(im,(x+22,502),title,295,34,INK,True);label(im,(x+22,660),sha,24,MUTED)
        label(im,(72,790),'Each change starts from a specific file and an observed behavior.',32,INK,True)
    elif kind=='regressions':
        card(im,(70,320,945,735));card(im,(975,320,1850,735))
        label(im,(105,360),'THE TARGET WORKBOOK',26,BLUE,True)
        label(im,(105,425),'29.6% → 6.0%',72,GREEN,True)
        wrapped(im,(105,550),'A proposed print-area rule improved this comparison.',785,34,INK)
        label(im,(1010,360),'ANOTHER WORKBOOK',26,BLUE,True)
        label(im,(1010,425),'+11 unwanted pages',64,ORANGE,True)
        wrapped(im,(1010,550),'The wider check exposed a regression. The change was reverted.',785,34,INK)
        card(im,(70,770,1850,860),BLUE,BLUE)
        label(im,(100,791),'Kept in the engineering notes: what failed, and what remains unexplained.',30,'white',True)
    elif kind=='metrics':
        card(im,(70,315,1160,865));card(im,(1190,315,1850,865))
        label(im,(105,350),'SHEETS · 751 SCORED WORKBOOKS',28,BLUE,True)
        for i,(date,value) in enumerate([('12 OCT · SWEEP 4',1.93),('16 OCT · SWEEP 14',1.43)]):
            y=435+i*180;label(im,(105,y),date,25,MUTED)
            d.rounded_rectangle((105,y+49,105+value*390,y+117),radius=8,fill=BLUE if i==0 else GREEN)
            label(im,(125+value*390,y+53),f'{value:.2f}%',43,INK,True)
        wrapped(im,(1225,365),'A rendering metric.',570,45,INK,True)
        wrapped(im,(1225,465),'Specific files. Fixed references. Consistent comparison method.',565,32,MUTED)
        wrapped(im,(1225,640),'Not a feature-support percentage or a guarantee for every file.',565,32,INK,True)
    else:
        raise ValueError(kind)
    return im

def caption_frame(base_image,text,progress):
    im=base_image.copy();d=ImageDraw.Draw(im)
    d.rectangle((0,945,W,H),fill='#15233b')
    f=font(32)
    lines=[];line=''
    for word in text.split():
        candidate=(line+' '+word).strip()
        if f.getlength(candidate)>1740 and line:lines.append(line);line=word
        else:line=candidate
    if line:lines.append(line)
    assert len(lines)<=2,(text,lines)
    y=968 if len(lines)>1 else 991
    for line in lines:
        d.text(((W-f.getlength(line))/2,y),line,font=f,fill='white');y+=43
    d.rectangle((0,H-5,round(W*progress),H),fill='#8da9ff')
    return im

def render():
    timeline=json.loads((OUT/'timeline.json').read_text())
    duration=timeline[-1]['start']+timeline[-1]['duration']
    events=[]
    for scene in timeline:
        bg=draw_scene(scene);bg.save(FRAMES/(scene['id']+'.png'))
        for i,c in enumerate(scene['captions']):
            end=scene['captions'][i+1]['start'] if i+1<len(scene['captions']) else scene['start']+scene['duration']
            im=caption_frame(bg,c['text'],end/duration)
            events.append((c['start'],end,im,scene['id']))
    # ffconcat gives each real frame its exact narrated duration. At chapter
    # boundaries, a 12-frame dissolve replaces the start of the new scene.
    lines=['ffconcat version 1.0'];counter=0;last=None
    for start,end,im,scene_id in events:
        length=end-start
        if last is not None and scene_id!=last[1]:
            for j in range(12):
                frame=Image.blend(last[0],im,(j+1)/12)
                name=f'cut-{counter:04}.png';frame.save(FRAMES/name);counter+=1
                lines.extend([f"file 'frames/{name}'",f'duration {1/FPS:.9f}'])
            length-=12/FPS
        name=f'cut-{counter:04}.png';im.save(FRAMES/name);counter+=1
        lines.extend([f"file 'frames/{name}'",f'duration {length:.9f}'])
        last=(im,scene_id)
    lines.append(f"file 'frames/{name}'")
    (OUT/'film.ffconcat').write_text('\n'.join(lines)+'\n')
    chapters=[';FFMETADATA1', 'title=Starling Office: Compatibility, one document at a time']
    for scene in timeline:
        chapters.extend(['[CHAPTER]', 'TIMEBASE=1/1000',
                         f'START={round(scene["start"]*1000)}',
                         f'END={round((scene["start"]+scene["duration"])*1000)}',
                         'title='+scene['title']])
    (OUT/'chapters.ffmeta').write_text('\n'.join(chapters)+'\n')
    print(f'Encoding {duration:.1f}s from {counter} frames',flush=True)
    subprocess.run(['ffmpeg','-hide_banner','-y','-f','concat','-safe','0','-i',str(OUT/'film.ffconcat'),
                    '-i',str(OUT/'narration.wav'),'-i',str(OUT/'captions.srt'),
                    '-f','ffmetadata','-i',str(OUT/'chapters.ffmeta'),
                    '-map','0:v:0','-map','1:a:0','-map','2:s:0','-r',str(FPS),
                    '-map_metadata','3','-map_chapters','3',
                    '-vf',f'fps={FPS},tpad=stop_mode=clone:stop_duration=10',
                    '-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p',
                    '-af','loudnorm=I=-16:TP=-1.5:LRA=11','-c:a','aac','-b:a','192k',
                    '-c:s','mov_text','-metadata:s:s:0','language=eng',
                    '-metadata','title=Starling Office: Compatibility, one document at a time',
                    '-movflags','+faststart','-t',str(duration),str(OUT/'starling-office-compatibility.pending.mp4')],check=True)
    (OUT/'starling-office-compatibility.pending.mp4').replace(OUT/'starling-office-compatibility.mp4')
    thumbs=Image.new('RGB',(1280,math.ceil(len(timeline)/2)*360),'white')
    for i,s in enumerate(timeline):
        pic=Image.open(FRAMES/(s['id']+'.png'));pic.thumbnail((640,360))
        thumbs.paste(pic,((i%2)*640,(i//2)*360))
    thumbs.save(OUT/'storyboard.jpg',quality=90)

if __name__=='__main__':render()
