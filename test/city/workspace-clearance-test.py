"""Compare rail interiors against a geometry-free control at the same camera.

Run wallpaper-workspace.py first to create the placement audit in --audit.
"""
import argparse
import importlib.util
import math
import os
from pathlib import Path
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--world',required=True,type=Path)
p.add_argument('--audit',required=True,type=Path)
args=p.parse_args()
nav=city.navigation.Navigation(city.navigation.description(city.ground,city.waterfront))
y=nav.floor(0,1)+1.7
control=args.audit/'rail-control.ppm'
with (args.audit/'rail-control.log').open('w') as log:
    subprocess.run([str(ROOT/'.build-shared/roomtest'),'',str(args.world/'room_ibl.ktx'),
        str(args.world/'room_skybox.ktx'),str(control),'1440','900','0',str(y),'1','0','5'],
        env={**os.environ,**city.LIGHTING,'ROOMTEST_PANES':str((args.audit/'hillside-rail.csv').resolve())},
        stdout=log,stderr=log,check=True)
with Image.open(control) as image: expected=np.asarray(image,dtype=float)
with Image.open(args.audit/'hillside-rail.png') as image: actual=np.asarray(image,dtype=float)
focal=720/.7002; angle=math.radians(5)
def project(x,yy,z):
    dy,dz=yy-y,z-1
    vy=math.cos(angle)*dy-math.sin(angle)*dz
    vz=math.sin(angle)*dy+math.cos(angle)*dz
    return 720+focal*x/-vz,450-focal*vy/-vz
for i,row in enumerate((args.audit/'hillside-rail.csv').read_text().splitlines()):
    x,yy,z,yaw,width,height=map(float,row.split(',')[:6])
    assert yaw==0
    corners=[project(x+dx,yy+dy,z) for dx,dy in
             [(-width/2,-height/2),(width/2,-height/2),(width/2,height/2),(-width/2,height/2)]]
    assert all(0<px<1440 and 0<py<900 for px,py in corners), 'rail pane outside viewport'
    mask=Image.new('L',(1440,900)); ImageDraw.Draw(mask).polygon(corners,fill=255)
    inside=np.asarray(mask.filter(ImageFilter.MinFilter(17)))>0
    errors=np.abs(expected[inside]-actual[inside]).mean(axis=1)
    blocked=(errors>12).mean()
    assert blocked<.01, f'pane {i}: {blocked:.1%} of interior differs from unobstructed control'
    print(f'Pane {i}: {blocked:.2%} obstructed interior; mean difference {errors.mean():.3f}/255')
