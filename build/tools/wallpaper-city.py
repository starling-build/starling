#!/usr/bin/env python3
"""Independent reference-view study. Does not replace the installed city.

python3 build/tools/wallpaper-city.py --out /tmp/wallpaper-city
Render with roomtest at 0 40 18 0 7.5, 1672 x 941.
Geometry is authored from the wallpaper; no wallpaper projection is used.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from PIL import Image
import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('voxel', HERE / 'voxel-world.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def ground(z):
    return max(-2., 32 + (.36*z - .0009*z*z if z<0 else 2.16*(1-np.exp(-z/6))))


def build(seed=12):
    rng = np.random.default_rng(seed)
    props = []
    terrain = []
    def box(t,x,y,z,xx,yy,zz):
        props.append(('box',t,x,y,z,xx,yy,zz))
    def beam(t,a,b,w):
        props.append(('beam',t,a,b,w))
    def tree(x,z,y,s=1):
        # Fixed-size leaf voxels keep nearby trees detailed instead of scaling
        # a handful of enormous cubes with the tree's overall height.
        beam('log',(x,y,z),(x+.12*s,y+3.3*s,z),.28*s)
        for dx,dz in ((-.7,.1),(.6,-.4),(.3,.65)):
            beam('log',(x,y+1.9*s,z),(x+dx*s,y+3.3*s,z+dz*s),.12*s)
        step=.34 if s>1.5 else .28
        radius=1.3*s
        for dx in np.arange(-radius,radius+.01,step):
            for dy in np.arange(-1.5*s,1.5*s+.01,step):
                for dz in np.arange(-radius,radius+.01,step):
                    shape=(dx/radius)**2+(dy/(1.5*s))**2+(dz/radius)**2
                    if shape>1+rng.uniform(-.17,.17) or shape<.60: continue
                    if rng.random()<.13: continue
                    r=step*.55
                    box(rng.choice(['leaves','leaves_dark','leaves_light']),
                        x+dx-r,y+3.6*s+dy-r,z+dz-r,
                        x+dx+r,y+3.6*s+dy+r,z+dz+r)
    def window(x,y,z,w=1,h=1.8):
        box('limestone',x-.12,y-.12,z-.08,x+w+.12,y+h+.12,z+.13)
        box('interior_warm',x,y,z+.14,x+w,y+h,z+.16)
        box('bronze',x+w*.47,y,z+.17,x+w*.53,y+h,z+.21)
        box('limestone',x,y+h*.43,z+.17,x+w,y+h*.47,z+.21)
    def house(x,z,w,h,t,d=7,base=None):
        y=ground(z) if base is None else base
        box('stone',x-.25,y-2,z-d,x+w+.25,y+.7,z+.2)
        box(t,x,y+.7,z-d,x+w,y+h,z)
        for level in np.arange(1,h,3):
            box('limestone',x-.17,y+level,z-d-.1,x+w+.17,y+level+.22,z+.3)
        for dz,dy,thick in ((.35,h,.25),(.5,h+.3,.23),(.25,h+.6,.18)):
            box('limestone',x-dz,y+dy,z-d-dz,x+w+dz,y+dy+thick,z+dz)
        box('roof',x+.2,y+h+.2,z-d+.2,x+w-.2,y+h+.45,z-.2)
        box('stone',x+w*.7,y+h,z-d*.55,x+w*.7+.6,y+h+1.4,z-d*.55+.7)
        for wx in np.arange(x+.6,x+w-1,1.8):
            # Projecting bay windows, stacked over two floors.
            bay=.55 if h>8 and wx<x+w*.6 else .05
            for level in np.arange(1.5,h-1,3):
                box(t,wx-.15,y+level-.25,z,wx+1.25,y+level+2.2,z+bay)
                window(wx,y+level,z+bay)
                box('limestone',wx-.25,y+level+2.1,z,wx+1.35,y+level+2.28,z+bay+.2)
        # Bay windows on both side elevations, especially the street-facing wall.
        for sx,sign in ((x,-1),(x+w,1)):
            for wz in np.arange(z-d+.8,z-1,2):
                for level in np.arange(1.5,h-1,3):
                    lo,hi=sorted((sx,sx+sign*.55))
                    box('limestone',lo,y+level-.12,wz-.12,hi,y+level+2,wz+1.22)
                    face=sx+sign*.57
                    box('interior_warm',face-.015,y+level,wz,face+.015,y+level+1.8,wz+1.1)
                    box('bronze',face-.025,y+level,wz+.52,face+.025,y+level+1.8,wz+.58)
                    box('limestone',face-.04,y+level+.8,wz,face+.04,y+level+.88,wz+1.1)
        # Front stoop and garden wall, facing the reference camera.
        for step in range(5):
            box('limestone',x+w-1.7,y-.5+step*.22,z+1.8-step*.3,x+w-.2,y-.28+step*.22,z+2.1-step*.3)
        box('stone',x-.1,y-.5,z+1.8,x+w-2,y+.5,z+2.15)
        for k in range(int(w*2)):
            xx=x+rng.uniform(0,w-2)
            box('leaves',xx,y+.45,z+1.65,xx+.35,y+.8,z+2)
            if k%3==0: box('flower_rose',xx,y+.8,z+1.8,xx+.14,y+.95,z+1.95)
    # Descending cobblestone road, with individually laid stones and curbs.
    for z in np.arange(-84,25,.65):
        y=ground(z)
        box('stone',-40,y-1,z,40,y,z+.66)
        for x in np.arange(-9,9,1.05):
            xx=x+(.35 if int(z/.65)%2 else 0)
            box(rng.choice(['stone','sidewalk','plaza']),xx,y,z,xx+1,y+.045,z+.61)
        for side in (-1,1):
            x=side*10
            box('sidewalk',x-1,y,z,x+1,y+.16,z+.66)
    for x in (-5.5,-4.3,-2.2,-1):
        for z in np.arange(-78,25,2):
            beam('bronze',(x,ground(z)+.09,z),(x,ground(z+2)+.09,z+2),.085)
    for side in (-1,1):
        for z in np.arange(-56,4,1):
            y=ground(z)
            x=side*11.1
            if int(z)%12 in (0,1,2,3): continue
            box('stone',x-.3,y,z,x+.3,y+.9,z+.98)
            box('limestone',x-.36,y+.9,z,x+.36,y+1.03,z+.98)
            for k in range(3):
                xx=x+rng.uniform(-.2,.2); zz=z+rng.uniform(.1,.8)
                box('leaves',xx-.15,y+1,zz-.15,xx+.15,y+1.3,zz+.15)
                if k==0: box('flower_rose',xx-.06,y+1.3,zz-.06,xx+.06,y+1.44,zz+.06)
    colors=['plaster_blue','plaster_sage','plaster_terra','plaster_cream','plaster_rose']
    for side in (-1,1):
        for row,z in enumerate((-5,-17,-29,-41,-53,-65,-77)):
            x=-20 if side<0 else 13
            h=(10-row*.35) if side<0 else (6.5-row*.2)
            house(x,z,7,h,colors[row%5])
            tree(side*11.6,z-5,ground(z-5),1.15 if row<3 else .9)
            props.append(('lamp',side*9.3,ground(z+2),z+2,3.3))
            for col in range(1,4):
                house(x+side*col*8.5,z-2,7,h+rng.uniform(-2,2),colors[(row+col)%5])
    tree(-12.5,-2,ground(-2),2.6)
    tree(16,-12,ground(-12),1.8)
    # Waterfront neighbourhoods: small, tightly packed blocks beyond the hill.
    for z in (-92,-105,-119):
        for x in np.arange(-65,70,9):
            if x>10 and z==-119: continue
            house(x,z,7,rng.uniform(4,8),rng.choice(colors),base=-2)
    # Long Ferry Building and clock tower, right of the vanishing point.
    box('stone',8,-2.5,-146,75,-1,-135)
    box('plaster_cream',9,-1,-145,74,5,-137)
    for y,edge in ((1.9,.18),(5,.35),(5.35,.5)):
        box('limestone',9-edge,y,-145-edge,74+edge,y+.22,-137+edge)
    box('copper',9.4,5.2,-144.6,73.6,5.4,-137.4)
    for x in np.arange(10,74,3):
        window(x,3,-136.95,.8,1.4)
        box('limestone',x-1,-1,-136.8,x-.75,5,-136.6)
    for x in np.arange(11,73,3):
        # Narrow strips describe a rounded opening without transparent planes.
        for dx in np.arange(-.7,.71,.1):
            arch=2.1+np.sqrt(max(0,.7**2-dx**2))
            box('glass',x+dx,-.8,-136.96,x+dx+.1,arch,-136.9)
        for a in np.linspace(0,np.pi,13)[:-1]:
            b=a+np.pi/12
            beam('limestone',(x+.85*np.cos(a),2.1+.85*np.sin(a),-136.8),
                 (x+.85*np.cos(b),2.1+.85*np.sin(b),-136.8),.18)
        box('limestone',x-.94,-1,-136.9,x-.77,2.1,-136.7)
        box('limestone',x+.77,-1,-136.9,x+.94,2.1,-136.7)
    tx=34
    box('limestone',tx-2,5,-137,tx+2,18,-133)
    for x in (tx-1.95,tx+1.65):
        box('plaster_cream',x,5,-132.97,x+.3,18,-132.72)
    for y in (6,10,14,17.5):
        box('plaster_cream',tx-2.15,y,-137.15,tx+2.15,y+.25,-132.85)
    for y in (7,10.8):
        box('glass',tx-.2,y,-132.94,tx+.2,y+1.4,-132.91)
    for y,w in ((17.8,2.5),(19.8,1.8),(21.8,1.1),(23.8,.6)):
        box('limestone',tx-w,y,-135-w,tx+w,y+1.5,-135+w)
    beam('bronze',(tx,25,-135),(tx,28,-135),.09)
    # Clock face and hands are geometry, visible without shell overlays.
    props.append(('ellipsoid','lamp',(tx,15.8,-132.94),(1.02,1.02,.055),8))
    beam('dark',(tx,15.8,-132.86),(tx,16.5,-132.86),.09)
    beam('dark',(tx,15.8,-132.85),(tx+.5,15.5,-132.85),.09)
    # Sea, warm reflections and island.
    box('water',-5000,-3,-5000,5000,-2.5,-142)
    box('water',10,-3,-142,75,-2.5,-80)
    for _ in range(15000):
        z=rng.uniform(-420,-90); x=rng.uniform(-190,250)
        if z>-142 and not 12<x<70: continue
        props.append(('ripple','reflection_amber' if abs(x-(18-z)*.56)<24 else 'water_glint',x,-2.47,z,rng.uniform(.3,1.8),rng.uniform(.035,.13)))
    for x in np.arange(-92,12,2):
        h=1+5*np.sin(np.pi*(x+92)/104)
        front=-335+9*np.sin(np.pi*(x+92)/104)
        box('hill',x,-2.5,-357,x+2,h,front)
        if int(x)%6==0: tree(x,front-2,h,.75)
    for x in np.arange(-93,13,2.5):
        front=-335+9*np.sin(np.pi*(x+92)/104)
        props.append(('ellipsoid','hill',(x,0,front+1),(2.2,1.6,2.4),3))
        if int(x)%3==0: tree(x,front,1,.45)
    house(-61,-337,33,4.5,'plaster_cream',base=4)
    box('limestone',-13,4,-337,-11,17,-335)
    # Bridge spans the right half of the distant bay.
    bz=-365
    bridge_start=len(props)
    box('bridge_red',-2,13,bz-2,205,14,bz+2)
    for x in (50,155):
        for dx in (-2,2): box('bridge_red',x+dx-.7,-2.5,bz-1,x+dx+.7,52,bz+1)
        for y in (15,27,39,50): box('bridge_red',x-2.7,y,bz-.7,x+2.7,y+1,bz+.7)
    for a,b in ((-2,50),(50,155),(155,205)):
        for x in np.arange(a,b,2):
            def cable(xx):
                t=(xx-a)/(b-a)
                if a==50: return 17+35*(2*t-1)**2
                return 15+37*(t*t if b==50 else (1-t)**2)
            for dz in (-1.5,1.5):
                beam('bridge_red',(x,cable(x),bz+dz),(min(x+2,b),cable(min(x+2,b)),bz+dz),.14)
                beam('bronze',(x,14,bz+dz),(x,cable(x),bz+dz),.07)
    # Raise the whole distant bridge to match the reference skyline.
    for i in range(bridge_start,len(props)):
        p=props[i]
        if p[0]=='box': props[i]=(p[0],p[1],p[2],(p[3] if p[3]<0 else p[3]+20),p[4],p[5],p[6]+20,p[7])
        elif p[0]=='beam': props[i]=(p[0],p[1],(p[2][0],p[2][1]+20,p[2][2]),(p[3][0],p[3][1]+20,p[3][2]),p[4])
    # Overlapping ridges hide vertical sea cliffs; nearer toes taper into water.
    def hill(x):
        return 3+39*np.exp(-((x+170)/115)**2)+22*np.exp(-((x-280)/80)**2)
    def terrain_height(x,z):
        depth=np.sin(np.clip((-z-415)/135,0,1)*np.pi*.7)
        shore=max(np.clip(-x/65,0,1),np.clip((x-185)/70,0,1))
        return max(-2.5,hill(x)*depth*shore-2.5)
    for z in np.arange(-550,-414,5):
        for x in np.arange(-620,621,4):
            if 0<x<181: continue
            points=[]; normals=[]
            for xx,zz in ((x,z),(x,z+5),(x+4,z+5),(x+4,z)):
                yy=terrain_height(xx,zz)
                dx=(terrain_height(xx+.1,zz)-terrain_height(xx-.1,zz))/.2
                dz=(terrain_height(xx,zz+.1)-terrain_height(xx,zz-.1))/.2
                n=np.array([-dx,1,-dz]); n/=np.linalg.norm(n)
                points.append((xx,yy,zz)); normals.append(n)
            terrain.append(('hill_far' if z<-490 else 'hill',points,normals))
            h0=terrain_height(x,z)
            if z in (-505,-475,-445) and h0>3 and rng.random()<.62:
                by=h0-.5
                box('hill_far',x,by,z+3,x+2.5,by+2.4,z+6)
                for wx in (x+.4,x+1.4):
                    box('interior_warm',wx,by+.8,z+6.01,wx+.35,by+1.4,z+6.03)
    for y in np.arange(38,70,5):
        half=(70-y)*.09
        for side in (-1,1):
            beam('bronze',(-160+side*half,y,-452),(-160+side*max(0,half-.45),y+5,-452),.2)
        beam('bridge_red',(-160-half,y,-452),(-160+half,y,-452),.2)
    p,n,u,indices=v.mesh_blocks(np.zeros((1,1,1),np.uint8),(0,0),props)
    tp=[]; tn=[]; tu=[]
    for tile,points,normals in terrain:
        tp.extend(points); tn.extend(normals)
        u0,v0,u1,v1=v.tile_uv(v.T[tile])
        tu.extend(((u0,v0),(u0,v1),(u1,v1),(u1,v0)))
    base=np.arange(len(terrain),dtype=np.uint32)[:,None]*4+len(p)
    ti=(base+np.array([0,1,2,0,2,3],np.uint32)).reshape(-1)
    return (np.concatenate((p,np.asarray(tp,np.float32))),
            np.concatenate((n,np.asarray(tn,np.float32))),
            np.concatenate((u,np.asarray(tu,np.float32))),np.concatenate((indices,ti)))


def trolley_mesh():
    props=[]
    def box(t,*bounds): props.append(('box',t,*bounds))
    box('dark',-1.1,.1,-2.4,1.1,.4,2.4)
    box('bridge_red',-1.05,.4,-2.3,1.05,1.35,2.3)
    box('bronze',-1.08,1.25,-2.32,1.08,1.36,2.32)
    box('dark',-.95,1.35,-2.2,.95,2.65,2.2)
    for side in (-1,1):
        z=side*2.3
        for x in (-.95,-.32,.32,.89):
            box('plaster_cream',x,1.35,z-.045,x+.065,2.7,z+.045)
        for x in (-.86,-.23,.41):
            box('glass_lit',x,1.5,z-.035,x+.43,2.5,z+.035)
        box('bronze',-1.08,.52,z-.06,1.08,.59,z+.06)
        props.append(('ellipsoid','lamp',(0,.94,z+side*.06),(.18,.18,.055),5))
    for side in (-1,1):
        x=side*1.06
        for z in np.arange(-2.15,2.2,.65):
            box('plaster_cream',x-.045,1.35,z,x+.045,2.7,z+.06)
            box('glass_lit',x-.035,1.5,z+.12,x+.035,2.5,z+.52)
    box('bridge_red',-1.22,2.7,-2.55,1.22,2.88,2.55)
    box('dark',-.75,2.88,-1.7,.75,3.15,1.7)
    box('bridge_red',-.86,3.15,-1.85,.86,3.29,1.85)
    for z in (-1.7,1.7):
        for x in (-1.1,.9): box('dark',x,0,z-.25,x+.2,.55,z+.25)
    return v.mesh_blocks(np.zeros((1,1,1),np.uint8),(0,0),props)


ROOT = HERE.parents[1]
ASSETS = ROOT/'shell/Resources/Worlds/wallpaper-city/materials'
CAMERA = {'position':[0,40,18], 'yaw':0, 'pitch':7.5, 'size':[1672,941]}
LIGHTING = {'ROOMTEST_SUN':'0.56,0.025,-1', 'ROOMTEST_SUN_COLOUR':'1,0.72,0.45',
            'ROOMTEST_SUN_LUX':'12000', 'ROOMTEST_IBL_LUX':'6500',
            'ROOMTEST_EXPOSURE':'8,0.0166667,100'}


def water_normal(path, size=512):
    """Periodic analytic wave slopes, converted to a tangent-space normal map."""
    z,x=np.mgrid[0:size,0:size].astype(float)*2*np.pi/size
    dx=np.zeros_like(x); dz=np.zeros_like(z)
    rng=np.random.default_rng(91)
    for _ in range(24):
        kx=int(rng.integers(-25,26)); kz=int(rng.integers(8,75))
        amplitude=rng.uniform(.035,.10)/np.hypot(kx,kz)
        wave=amplitude*np.cos(kx*x+kz*z+rng.uniform(0,2*np.pi))
        dx+=kx*wave; dz+=kz*wave
    n=np.stack((-dx,-dz,np.ones_like(x)),axis=-1)
    n/=np.linalg.norm(n,axis=-1,keepdims=True)
    Image.fromarray(np.rint((n*.5+.5)*255).astype(np.uint8)).save(path)


def bake_sky(out, cmgen):
    # Decode sRGB before baking lighting. The source contains no sun; an
    # analytic disc aligns the environment with the directional light.
    source=Image.open(ASSETS/'sunset-sky-v2.png').convert('RGB')
    # The illustrated cloud belt covers too many degrees for the reference
    # camera. Remap latitude when baking the spherical environment.
    source=source.resize((4096,2048),Image.Resampling.LANCZOS)
    pixels=np.asarray(source,dtype=np.float32)/255
    pixels=np.roll(pixels,pixels.shape[1]//2,axis=1)
    h=pixels.shape[0]
    latitude=(np.arange(h)+.5)/h-.5
    source_y=np.clip((.5+latitude*2.8)*h-.5,0,h-1)
    lower=np.floor(source_y).astype(int); upper=np.minimum(lower+1,h-1)
    fraction=(source_y-lower)[:,None,None]
    pixels=pixels[lower]*(1-fraction)+pixels[upper]*fraction
    linear=np.where(pixels<=.04045,pixels/12.92,((pixels+.055)/1.055)**2.4)
    with tempfile.TemporaryDirectory(prefix='wallpaper-sky-',dir=out) as scratch:
        scratch=Path(scratch)
        h,w=linear.shape[:2]
        lat=(.5-(np.arange(h)+.5)/h)*np.pi
        phi=((np.arange(w)+.5)/w*2-1)*np.pi
        # cmgen's equirectangular longitude is mirrored relative to world X.
        direction=np.array([-.56,.025,-1.]); direction/=np.linalg.norm(direction)
        alignment=(np.cos(lat)[:,None]*np.sin(phi)[None,:]*direction[0]
                   +np.sin(lat)[:,None]*direction[1]
                   +np.cos(lat)[:,None]*np.cos(phi)[None,:]*direction[2])
        angle=np.arccos(np.clip(alignment,-1,1))
        sun=(angle<.008)[...,None]*np.array([2.5,1.9,1.1])
        sun+=np.exp(-(angle/.027)**2)[...,None]*np.array([.12,.065,.018])
        for name,size,gain in (('ibl',128,1.),('sky',1024,.5)):

            hdr=scratch/(name+'.hdr')
            v.write_hdr(hdr,(linear+sun)*gain*(np.array([1.8,1.3,.8]) if name=='ibl' else 1.))
            subprocess.run([str(cmgen),'--quiet','--format=ktx',f'--size={size}',
                            f'--deploy={scratch/name}',str(hdr)],check=True)
            suffix='ibl' if name=='ibl' else 'skybox'
            shutil.copy2(scratch/name/f'{name}_{suffix}.ktx',out/f'room_{suffix}.ktx')


def render_preview(out):
    renderer=ROOT/'.build-shared/roomtest'
    if not renderer.is_file():
        raise FileNotFoundError(f'{renderer}: build with build/build-room.sh --test first')
    subprocess.run([str(renderer),str(out/'room.glb'),str(out/'room_ibl.ktx'),
                    str(out/'room_skybox.ktx'),str(out/'view.ppm'),
                    *map(str,CAMERA['size']),*map(str,CAMERA['position']),
                    str(CAMERA['yaw']),str(CAMERA['pitch'])],
                   env={**os.environ,**LIGHTING},check=True)
    with Image.open(out/'view.ppm') as screenshot:
        screenshot.save(out/'view.png')
    shutil.copy2(ROOT/'shell/Resources/Wallpapers/city-sunset.png',out/'reference.png')
    (out/'comparison.html').write_text("""<!doctype html><html lang="en">
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wallpaper city reconstruction</title><style>
body{background:#191d26;color:#eee;font:16px system-ui;margin:24px}
main{display:grid;grid-template-columns:1fr 1fr;gap:16px}img{width:100%}
figure{margin:0}figcaption{padding:12px 0}button{padding:8px 16px;margin-bottom:16px}
main.stacked{grid-template-columns:1fr}@media(max-width:900px){main{grid-template-columns:1fr}}
</style><h1>Wallpaper city reconstruction</h1>
<p>Actual 3D render. Prototype: shoreline and architectural variety remain unfinished.</p>
<button onclick="document.querySelector('main').classList.toggle('stacked')">Toggle stacked / side by side</button>
<main><figure><img src="reference.png" alt="Sunset wallpaper"><figcaption>Reference wallpaper</figcaption></figure>
<figure><img src="view.png" alt="Rendered 3D reconstruction"><figcaption>3D reconstruction</figcaption></figure></main></html>
""")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--render',action='store_true',help='Render a PNG and local comparison page')
    parser.add_argument('--cmgen',type=Path,default=Path.home()/'dev/filament/gles/bin/cmgen')
    parser.add_argument('--no-sky',action='store_true',help='Reuse an existing baked sky in --out')
    args=parser.parse_args(); out=args.out; out.mkdir(parents=True,exist_ok=True)
    v.make_atlas(out/'atlas.png',out/'frame.png')
    original=v.ambient_actors
    def actors():
        result=[]
        for name,mesh,times,positions in original():
            positions=np.asarray(positions,dtype=float)
            if name=='bay-ferry':
                positions[:,0]+=76; positions[:,2]-=115
                mesh=(mesh[0]*1.4,mesh[1],mesh[2],mesh[3])
            elif name=='plaza-cable-car':
                positions[:,0]=-4
                positions[:,2]+=7
                mesh=trolley_mesh()
                positions[:,1]=[ground(z)+.1 for z in positions[:,2]]
            else: continue
            result.append((name,mesh,times,positions))
        return result
    mesh=build()
    assert all(np.isfinite(a).all() for a in mesh)
    assert np.allclose(np.linalg.norm(mesh[1],axis=1),1,atol=1e-5)
    assert mesh[3].max()<len(mesh[0])
    water_normal(out/'water-normal.png')
    v.write_glb(out/'room.glb',*mesh,out/'atlas.png',actors=actors(),trolley_slope=.45,
                light_positions=[[side*9.3+.5,ground(z+2)+3.2,z+2.5]
                                 for z in (-5,-17,-29) for side in (-1,1)],
                material_options={
                    'surface_overrides': {
                        'water': (None,(.035,.10,.16),.38,.15,13.),
                        'plaster_blue': ('lime-plaster.png',(.18,.30,.40),.88,0.,2.),
                        'plaster_sage': ('lime-plaster.png',(.25,.36,.25),.88,0.,2.),
                        'plaster_terra': ('lime-plaster.png',(.45,.19,.12),.88,0.,2.),
                        'limestone': ('limestone.png',(.66,.55,.40),.78,0.,2.),
                        'hill': (None,(.055,.075,.07),.95,0.,1.),
                        'hill_far': (None,(.09,.105,.13),.95,0.,1.),
                        'water_glint': (None,(.30,.38,.46),.38,.2,1.),
                        'reflection_amber': (None,(.65,.34,.14),.27,.25,1.),
                    },
                    'normal_maps': {'water': (out/'water-normal.png',1.15)},
                    'material_extras': {
                        'hill': {'emissiveFactor':[.006,.007,.009]},
                        'hill_far': {'emissiveFactor':[.012,.012,.016]},
                        'reflection_amber': {'emissiveFactor':[.32,.13,.04]},
                    },
                })
    if not args.no_sky:
        bake_sky(out,args.cmgen)
    elif not all((out/name).is_file() for name in ('room_ibl.ktx','room_skybox.ktx')):
        parser.error('--no-sky requires an existing sky bake in --out')
    (out/'reference-camera.json').write_text(json.dumps({**CAMERA,'lighting':LIGHTING,
        'stage':'composition study; not a desktop world'},indent=2)+'\n')
    if args.render:
        render_preview(out)
    print(f'{out}: {len(mesh[3])//3:,} static triangles; finite geometry and unit normals verified')

if __name__=='__main__': main()
