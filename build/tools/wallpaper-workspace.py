#!/usr/bin/env python3
"""Render labeled workspace placement fixtures, not live application windows."""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('city',HERE/'wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


def fixture(path, name, accent):
    im=Image.new('RGB',(960,600),'#242932'); d=ImageDraw.Draw(im)
    font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    title=ImageFont.truetype(font,28); body=ImageFont.truetype(font,20)
    d.rectangle((0,0,960,48),fill='#e7cfac')
    d.text((20,7),name,fill='#352d29',font=title)
    for x in (860,900,940): d.ellipse((x-7,18,x+7,32),fill='#8f7966')
    d.text((28,75),'PLACEMENT FIXTURE · NOT A LIVE APP',fill='#e7cfac',font=body)
    d.rectangle((28,125,932,525),fill=accent)
    d.text((52,150),name,fill='white',font=ImageFont.truetype(font,48))
    for row in range(5):
        d.rounded_rectangle((52,235+row*48,620+(row%2)*160,251+row*48),radius=5,fill='#d0d8dc')
    d.text((28,550),'Starling · wallpaper world layout audit',fill='#e7cfac',font=body)
    im.save(path)


def layout(camera, mode, nav):
    x,y,z,yaw,pitch=camera
    result=[]
    for i in range(4):
        if mode=='switcher':
            # Match Desktop3D.swift's current switcher (selected index 1).
            angle=yaw+(i-1)*30
            radius=2.8 if i==1 else 3.8
            width=1.7; height=width*600/960
            px=x+math.sin(math.radians(angle))*radius
            pz=z-math.cos(math.radians(angle))*radius
            floor=nav.floor(px,pz)
            py=max(y,(floor if floor is not None else -1.9)+height/2+.05)
            facing=-angle
        else:
            # Existing workspace rail spacing, anchored 17 m downhill.
            offset=(i-1.5)*4
            px=x+offset; pz=z-17+.04*offset*offset
            py=y+2; width=3.6; height=width*600/960; facing=0
        result.append([px,py,pz,facing,width,height,int(i==1)])
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--world',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    args=p.parse_args(); args.out.mkdir(parents=True,exist_ok=True)
    nav=city.navigation.Navigation(json.loads((args.world/'navigation.json').read_text()))
    textures=[]
    for name,accent in [('Chrome','#3b647b'),('Video player','#6f4865'),
                        ('Files','#5c735c'),('Terminal','#374657')]:
        path=args.out/(name.lower().replace(' ','-')+'.ppm')
        fixture(path,name,accent); textures.append(path.resolve())
    cameras={'hillside':[0,nav.floor(0,1)+1.7,1,0,5],
             'quay':[34,nav.floor(34,-130)+1.7,-130,0,0]}
    for name,camera in cameras.items():
        for mode in ('switcher','rail'):
            if name=='quay' and mode=='rail': continue
            label=f'{name}-{mode}'; csv=args.out/(label+'.csv')
            rows=layout(camera,mode,nav)
            csv.write_text(''.join(','.join(map(str,row))+','+str(texture)+'\n'
                                   for row,texture in zip(rows,textures)))
            ppm=args.out/(label+'.ppm')
            with (args.out/(label+'.log')).open('w') as log:
                subprocess.run([str(city.ROOT/'.build-shared/roomtest'),str(args.world/'room.glb'),
                    str(args.world/'room_ibl.ktx'),str(args.world/'room_skybox.ktx'),
                    str(ppm),'1440','900',*map(str,camera)],
                    env={**os.environ,**city.LIGHTING,'ROOMTEST_PANES':str(csv.resolve())},
                    stdout=log,stderr=log,check=True)
            with Image.open(ppm) as image: image.save(args.out/(label+'.png'))
    (args.out/'placement.json').write_text(json.dumps({
        'status':'placement study; fixture textures, not live applications',
        'cameras':cameras,
        'workspaceRail':[{'x':0,'y':cameras['hillside'][1]+2,'z':-16,
                          'width':3.8,'height':2.375}],
    },indent=2)+'\n')
    cards=''.join(f'<figure><img src="{name}.png"><figcaption>{title}</figcaption></figure>'
        for name,title in [('hillside-rail','Four-window rail above the street'),
                           ('hillside-switcher','Switcher at the hillside workspace'),
                           ('quay-switcher','Switcher at the quay')])
    (args.out/'index.html').write_text('<!doctype html><meta charset="utf-8">'
        '<title>Wallpaper workspace placement</title><style>'
        'body{background:#262932;color:#f1d8b9;font:18px system-ui;margin:30px}'
        'img{width:100%;max-width:1440px}figure{margin:30px 0}figcaption{padding:8px 0}'
        '</style><h1>Workspace placement study</h1>'
        '<p>Labeled fixtures for Chrome, Video player, Files and Terminal. These are not live applications.</p>'+cards)
    print(args.out)


if __name__=='__main__': main()
