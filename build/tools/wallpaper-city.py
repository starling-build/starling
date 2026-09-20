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
spec = importlib.util.spec_from_file_location('wallpaper_architecture', HERE/'wallpaper-architecture.py')
architecture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(architecture)
spec = importlib.util.spec_from_file_location('wallpaper_waterfront', HERE/'wallpaper-waterfront.py')
waterfront = importlib.util.module_from_spec(spec)
spec.loader.exec_module(waterfront)
spec = importlib.util.spec_from_file_location('wallpaper_distance', HERE/'wallpaper-distance.py')
distance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distance)


def ground(z):
    return max(-2., 32 + (.36*z - .0009*z*z if z<0 else 2.16*(1-np.exp(-z/6))))


def build(seed=12):
    rng = np.random.default_rng(seed)
    props = []
    terrain = []
    houses = []
    def box(t,x,y,z,xx,yy,zz):
        props.append(('box',t,x,y,z,xx,yy,zz))
    def beam(t,a,b,w):
        props.append(('beam',t,a,b,w))
    def tree(x,z,y,s=1):
        # Separate crowns and exposed branching preserve gaps in the silhouette.
        # Union the crowns on one voxel grid so overlapping limbs add no faces.
        beam('log',(x,y,z),(x+.12*s,y+3.6*s,z),.25*s)
        crowns=[(-.70,3.15,.12,.85),(.66,3.35,-.35,.88),
                (.30,3.65,.68,.78),(-.12,4.35,-.10,.94)]
        for dx,dy,dz,radius in crowns:
            beam('log',(x,y+1.8*s,z),(x+dx*s,y+dy*s,z+dz*s),.13*s)
        step=.32 if s>1.5 else .28
        for dx in np.arange(-1.65*s,1.65*s,step):
            for dy in np.arange(2.1*s,5.4*s,step):
                for dz in np.arange(-1.4*s,1.6*s,step):
                    shape=min(((dx/s-cx)/r)**2+((dy/s-cy)/(r*.86))**2+
                              ((dz/s-cz)/r)**2 for cx,cy,cz,r in crowns)
                    if shape>1+rng.uniform(-.12,.12) or shape<.48: continue
                    if rng.random()<.08: continue
                    r=step*.52
                    box(rng.choice(['leaves','leaves_dark','leaves_light']),
                        x+dx-r,y+dy-r,z+dz-r,x+dx+r,y+dy+r,z+dz+r)
    def lantern(x,z,y):
        # Slender cast-metal post, framed glass, stepped cap and finial.
        box('bronze',x-.19,y,z-.19,x+.19,y+.16,z+.19)
        box('bronze',x-.11,y+.16,z-.11,x+.11,y+.65,z+.11)
        beam('bronze',(x,y+.3,z),(x,y+2.65,z),.085)
        for yy,r,h in ((2.48,.15,.08),(2.62,.23,.07),(3.19,.30,.09)):
            box('bronze',x-r,y+yy,z-r,x+r,y+yy+h,z+r)
        box('lamp',x-.18,y+2.70,z-.18,x+.18,y+3.19,z+.18)
        for dx in (-.20,.20):
            for dz in (-.20,.20):
                beam('bronze',(x+dx,y+2.68,z+dz),(x+dx*1.3,y+3.22,z+dz*1.3),.045)
        for i in range(4):
            r=.28-i*.06
            box('bronze',x-r,y+3.28+i*.05,z-r,x+r,y+3.33+i*.05,z+r)
        beam('bronze',(x,y+3.43,z),(x,y+3.62,z),.055)
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
            # The right-hand row bends away downhill, opening the basin view.
            x=-20 if side<0 else 13+row*5
            h=(10-row*.35) if side<0 else (6.5-row*.2)
            front_color=colors[row%5] if side<0 else (
                'plaster_cream','plaster_rose','plaster_cream','plaster_sage','plaster_blue')[row%5]
            if row<5:
                houses.append(architecture.victorian(v,x,z,7,h,front_color,side,ground,
                                                     variant=row+(0 if side<0 else 1)))
            else:
                house(x,z,7,h,colors[row%5])
            tree(side*11.6,z-5,ground(z-5),1.15 if row<3 else .9)
            lantern(side*9.3,z+2,ground(z+2))
            for col in range(1,4):
                house(x+side*col*8.5,z-2,7,h+rng.uniform(-2,2),colors[(row+col)%5])
    tree(-15,-2,ground(-2),2.25)
    tree(16,-12,ground(-12),1.8)
    # Waterfront neighbourhoods: small, tightly packed blocks beyond the hill.
    for z in (-92,-105,-119):
        for x in np.arange(-65,70,9):
            if x>10 and z==-119: continue
            if x>=28 and z in (-92,-105): continue
            waterfront.district_block(props,x,z,7,rng.uniform(4.4,8.5),
                                      rng.choice(colors),int((x+65)/9)+int(-z))
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
            box('interior_warm',x+dx,-.8,-136.96,x+dx+.1,arch,-136.9)
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
    # Open belfry and lantern stages, rather than solid stacked roof blocks.
    for y,w in ((17.8,2.5),(20.9,1.9),(23.4,1.2)):
        box('limestone',tx-w,y,-135-w,tx+w,y+.35,-135+w)
    for bottom,top,radius,column in ((18.15,20.9,1.55,.22),(21.25,23.4,.85,.16)):
        beam('bronze',(tx,top,-135),(tx,(bottom+top)/2,-135),.06)
        props.append(('ellipsoid','bronze' if bottom<20 else 'lamp',
                      (tx,(bottom+top)/2,-135),
                      (radius*.4,(top-bottom)*.3,radius*.4),5))
        for dx in (-radius,radius-column):
            for dz in (-radius,radius-column):
                box('limestone',tx+dx,bottom,-135+dz,tx+dx+column,top,-135+dz+column)
    props.append(('ellipsoid','copper',(tx,24.65,-135),(.55,1.05,.55),5))
    beam('bronze',(tx,25,-135),(tx,28,-135),.09)
    # Clock face and hands are geometry, visible without shell overlays.
    props.append(('ellipsoid','lamp',(tx,15.8,-132.94),(1.02,1.02,.055),8))
    for angle in np.arange(12)*np.pi/6:
        beam('bronze',(tx+.78*np.sin(angle),15.8+.78*np.cos(angle),-132.86),
             (tx+.91*np.sin(angle),15.8+.91*np.cos(angle),-132.86),.045)
    beam('dark',(tx,15.8,-132.86),(tx,16.5,-132.86),.09)
    beam('dark',(tx,15.8,-132.85),(tx+.5,15.5,-132.85),.09)
    waterfront.quay(props)
    # Sea, warm reflections and island.
    # One sea surface beneath the land also covers oblique camera views.
    box('water',-5000,-3,-5000,5000,-2.5,5000)
    for _ in range(15000):
        z=rng.uniform(-420,-90); x=rng.uniform(-190,250)
        if z>-142 and not 12<x<70: continue
        props.append(('ripple','reflection_amber' if abs(x-(18-z)*.56)<24 else 'water_glint',x,-2.47,z,rng.uniform(.3,1.8),rng.uniform(.035,.13)))
    distance.island(props,tree)
    house(-61,-337,33,4.5,'plaster_cream',base=6)
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
        return 3+65*np.exp(-((x+170)/115)**2)+22*np.exp(-((x-280)/80)**2)
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
    distance.neighborhoods(props,terrain_height)
    radio_base=terrain_height(-160,-452)+.2
    radio_top=radio_base+60
    for y in np.arange(radio_base,radio_top,5):
        half=(radio_top-y)*.06
        for side in (-1,1):
            beam('bronze',(-160+side*half,y,-452),
                 (-160+side*max(0,half-.3),y+5,-452),.2)
        beam('bridge_red',(-160-half,y,-452),(-160+half,y,-452),.2)
    p,n,u,indices=v.mesh_blocks(np.zeros((1,1,1),np.uint8),(0,0),props)
    tp=[]; tn=[]; tu=[]
    for tile,points,normals in terrain:
        tp.extend(points); tn.extend(normals)
        u0,v0,u1,v1=v.tile_uv(v.T[tile])
        tu.extend(((u0,v0),(u0,v1),(u1,v1),(u1,v0)))
    base=np.arange(len(terrain),dtype=np.uint32)[:,None]*4+len(p)
    ti=(base+np.array([0,1,2,0,2,3],np.uint32)).reshape(-1)
    combined=[np.concatenate((p,np.asarray(tp,np.float32))),
              np.concatenate((n,np.asarray(tn,np.float32))),
              np.concatenate((u,np.asarray(tu,np.float32))),np.concatenate((indices,ti))]
    for hp,hn,hu,hi in houses:
        offset=len(combined[0])
        combined=[np.concatenate((combined[0],hp)),np.concatenate((combined[1],hn)),
                  np.concatenate((combined[2],hu)),np.concatenate((combined[3],hi+offset))]
    return tuple(combined)



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
DETAIL_CAMERA = {'position':[-5,34,1], 'yaw':-40, 'pitch':-5, 'size':[1400,1000]}
WATERFRONT_CAMERA = {'position':[90,16,-107], 'yaw':-64, 'pitch':7, 'size':[1400,1000]}
LIGHTING = {'ROOMTEST_SUN':'0.56,0.025,-1', 'ROOMTEST_SUN_COLOUR':'1,0.72,0.45',
            'ROOMTEST_SUN_LUX':'22000', 'ROOMTEST_IBL_LUX':'5000',
            'ROOMTEST_EXPOSURE':'8,0.0166667,100',
            'ROOMTEST_FOG':'0.003,160,0,0.07,0.42,0.65,0.75,0.9',
            'ROOMTEST_TIME':'0', 'ROOMTEST_REFLECTIONS':'0'}


def water_normal(path, size=1024):
    """Periodic analytic wave slopes, converted to a tangent-space normal map."""
    z,x=np.mgrid[0:size,0:size].astype(float)*2*np.pi/size
    dx=np.zeros_like(x); dz=np.zeros_like(z)
    rng=np.random.default_rng(91)
    for _ in range(96):
        kx=int(rng.integers(-64,65)); kz=int(rng.integers(16,160))
        amplitude=rng.uniform(.015,.035)/np.hypot(kx,kz)
        wave=amplitude*np.cos(kx*x+kz*z+rng.uniform(0,2*np.pi))
        dx+=kx*wave; dz+=kz*wave
    n=np.stack((-dx,-dz,np.ones_like(x)),axis=-1)
    n/=np.linalg.norm(n,axis=-1,keepdims=True)
    Image.fromarray(np.rint((n*.5+.5)*255).astype(np.uint8)).save(path)


def sky_samples(source, size=(4096,2048)):
    """Map the source panorama to continuous, pole-safe spherical samples."""
    # Decode sRGB before baking lighting. The source contains no sun; an
    # analytic disc aligns the environment with the directional light.
    # The illustrated cloud belt covers too many degrees for the reference
    # camera. Remap latitude when baking the spherical environment.
    source=source.convert("RGB").resize(size,Image.Resampling.LANCZOS)
    pixels=np.asarray(source,dtype=np.float32)/255
    # Enforce a periodic sampling boundary before the longitude warp. Small
    # generated edge errors otherwise become a meridian on the cubemap.
    edge=(pixels[:,0]+pixels[:,-1])*.5
    band=max(2,round(pixels.shape[1]*.06))
    t=np.linspace(1,0,band,dtype=np.float32)
    weight=(t*t*(3-2*t))[None,:,None]
    pixels[:,:band]=pixels[:,:band]*(1-weight)+edge[:,None,:]*weight
    pixels[:,-band:]=pixels[:,-band:]*(1-weight[:,::-1])+edge[:,None,:]*weight[:,::-1]
    # Spread more of the source cloud panorama across the reference view.
    # A periodic angular warp stays continuous around the sphere and places
    # the source golden bank near the analytic sun, without duplicating it.
    w=pixels.shape[1]
    longitude=(np.arange(w)+.5)/w
    source_x=((.605+np.arctan(3.5*np.tan(np.pi*longitude))/np.pi)%1)*w-.5
    left=np.floor(source_x).astype(int); blend=(source_x-left)[None,:,None]
    pixels=pixels[:,left%w]*(1-blend)+pixels[:,(left+1)%w]*blend
    h=pixels.shape[0]
    latitude=(np.arange(h)+.5)/h-.5
    source_y=np.clip((.5+latitude*4.0)*h-.5,0,h-1)
    lower=np.floor(source_y).astype(int); upper=np.minimum(lower+1,h-1)
    fraction=(source_y-lower)[:,None,None]
    pixels=pixels[lower]*(1-fraction)+pixels[upper]*fraction
    linear=np.where(pixels<=.04045,pixels/12.92,((pixels+.055)/1.055)**2.4)
    # All longitudes meet at each pole. Fade to each latitude's average above
    # 35 degrees, reaching a uniform cap at 65 degrees; the reference view is
    # below this region. Do this in linear light for irradiance consistency.
    cap=np.clip((np.abs(latitude)*180-35)/30,0,1)
    cap=(cap*cap*(3-2*cap))[:,None,None]
    linear=linear*(1-cap)+linear.mean(axis=1,keepdims=True)*cap
    return linear


def bake_sky(out, cmgen):
    with Image.open(ASSETS/'sunset-sky-v4.png') as source:
        linear=sky_samples(source)
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


def render_preview(out, sky_audit=False):
    renderer=ROOT/'.build-shared/roomtest'
    if not renderer.is_file():
        raise FileNotFoundError(f'{renderer}: build with build/build-room.sh --test first')
    shots=[('view',CAMERA,0),('architecture',DETAIL_CAMERA,0),('waterfront',WATERFRONT_CAMERA,0)]
    shots.extend((f'motion-{seconds}',CAMERA,seconds) for seconds in (20,40,60))
    if sky_audit:
        for name,yaw,pitch in (('front',0,-15),('right',90,-15),('back',180,-15),
                               ('left',270,-15),('up',0,-85),('down',0,85)):
            shots.append(('sky-'+name,{'position':[0,40,-210], 'yaw':yaw,
                                      'pitch':pitch, 'size':[836,470]},0))
    for name,camera,seconds in shots:
        subprocess.run([str(renderer),str(out/'room.glb'),str(out/'room_ibl.ktx'),
                        str(out/'room_skybox.ktx'),str(out/(name+'.ppm')),
                        *map(str,camera['size']),*map(str,camera['position']),
                        str(camera['yaw']),str(camera['pitch'])],
                       env={**os.environ,**LIGHTING,'ROOMTEST_TIME':str(seconds)},check=True)
        with Image.open(out/(name+'.ppm')) as screenshot:
            screenshot.save(out/(name+'.png'))
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
<figure><img src="view.png" alt="Rendered 3D reconstruction"><figcaption>3D reconstruction</figcaption></figure></main>
<h2>Street architecture</h2><figure style="max-width:1400px"><img src="architecture.png" alt="Close view of modeled bay windows, doors and stairs"><figcaption>Second camera view of the same 3D scene</figcaption></figure>
<h2>Waterfront</h2><figure style="max-width:1400px"><img src="waterfront.png" alt="Ferry terminal and quay"><figcaption>Terminal, channel and piers from a closer camera</figcaption></figure>
<h2>Motion checkpoints</h2><p>Actual renders at four points in the animation; these are still frames.</p>
<label>Scene time: <output id="motion-time">0 seconds</output>
<input type="range" min="0" max="3" step="1" value="0" aria-label="Animation checkpoint"
 oninput="const t=Number(this.value)*20;document.getElementById('motion-time').textContent=t+' seconds';document.getElementById('motion-view').src=t?'motion-'+t+'.png':'view.png'"></label>
<img id="motion-view" style="max-width:1672px" src="view.png" alt="Selected animation checkpoint">
</html>
""")
    if sky_audit:
        page=out/'comparison.html'
        section='<h2>Sky around the scene</h2><p>Four headings plus pole views from the bay.</p><main>'
        for name in ('front','right','back','left','up','down'):
            section+=f'<figure><img src="sky-{name}.png" alt="Sky {name}"><figcaption>{name.title()}</figcaption></figure>'
        page.write_text(page.read_text().replace('</html>',section+'</main></html>'))


def motion_tracks():
    times=np.linspace(0,80,161)
    z=np.interp(times,[0,6,36,44,74,80],[-5,-5,-30,-30,-5,-5])
    positions=np.column_stack((np.full_like(z,-4),[ground(zz)+.07 for zz in z],z))
    pitch=-np.arctan(.36-.0018*z)/2
    rotations=np.column_stack((np.sin(pitch),np.zeros_like(z),np.zeros_like(z),np.cos(pitch)))
    tracks={'plaza-cable-car':(times,positions,rotations)}
    times=np.linspace(0,150,301); a=times/150*2*np.pi
    positions=np.column_stack((84+32*np.sin(a),-2.25+.1*np.sin(24*a),-254+5*np.cos(a)))
    yaw=np.unwrap(np.arctan2(5*np.sin(a),32*np.cos(a)))/2
    rotations=np.column_stack((np.zeros_like(a),np.sin(yaw),np.zeros_like(a),np.cos(yaw)))
    tracks['bay-ferry']=(times,positions,rotations)
    return tracks


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--render',action='store_true',help='Render a PNG and local comparison page')
    parser.add_argument('--sky-audit',action='store_true',
                        help='Include all-around sky views when rendering')
    parser.add_argument('--reflections',action='store_true',
                        help='Opt into experimental screen-space reflections (higher GPU cost)')
    parser.add_argument('--cmgen',type=Path,default=Path.home()/'dev/filament/gles/bin/cmgen')
    parser.add_argument('--no-sky',action='store_true',help='Reuse an existing baked sky in --out')
    args=parser.parse_args(); out=args.out; out.mkdir(parents=True,exist_ok=True)
    LIGHTING['ROOMTEST_REFLECTIONS']='1' if args.reflections else '0'
    v.make_atlas(out/'atlas.png',out/'frame.png')
    tracks=motion_tracks()
    original=v.ambient_actors
    def actors():
        result=[]
        for name,mesh,times,positions in original():
            if name not in tracks: continue
            times,positions,_=tracks[name]
            if name=='bay-ferry':
                # Cream-painted hull, with red funnels retained above the deck.
                uv=mesh[2].copy()
                tile_ids=(np.floor(uv[:,1]*v.ATLAS)*v.ATLAS+np.floor(uv[:,0]*v.ATLAS)).astype(int)
                hull=(tile_ids==v.T['bridge_red']) & (mesh[0][:,1]<.91)
                row,col=divmod(v.T['plaster_cream'],v.ATLAS)
                uv[hull]=(np.mod(uv[hull]*v.ATLAS,1)+[col,row])/v.ATLAS
                mesh=(mesh[0]*1.8,mesh[1],uv,mesh[3])
            elif name=='plaza-cable-car':
                mesh=trolley_mesh()
            else: continue
            result.append((name,mesh,times,positions))
        return result
    mesh=build()
    assert all(np.isfinite(a).all() for a in mesh)
    assert np.allclose(np.linalg.norm(mesh[1],axis=1),1,atol=1e-5)
    assert mesh[3].max()<len(mesh[0])
    water_normal(out/'water-normal.png')
    v.write_glb(out/'room.glb',*mesh,out/'atlas.png',actors=actors(),actor_rotations={name:track[2] for name,track in tracks.items()},
                light_positions=[[side*9.3,ground(z+2)+2.95,z+2]
                                 for z in (-5,-17,-29,-41,-53) for side in (-1,1)]
                                + [[x,2,-134.5] for x in (20,34,48,62)],
                material_options={
                    'surface_overrides': {
                        'water': (None,(.035,.12,.19),.29,0.,144.),
                        'plaster_blue': ('lime-plaster.png',(.18,.30,.40),.88,0.,2.),
                        'plaster_sage': ('lime-plaster.png',(.25,.36,.25),.88,0.,2.),
                        'plaster_terra': ('lime-plaster.png',(.45,.19,.12),.88,0.,2.),
                        'limestone': ('limestone.png',(.78,.69,.54),.78,0.,2.),
                        'hill': (None,(.055,.075,.07),.95,0.,1.),
                        'hill_far': (None,(.09,.105,.13),.95,0.,1.),
                        'water_glint': (None,(.30,.38,.46),.38,.2,1.),
                        'reflection_amber': (None,(.65,.34,.14),.27,.25,1.),
                    },
                    'normal_maps': {'water': (out/'water-normal.png',1.4)},
                    'material_extras': {
                        'interior_warm': {'emissiveFactor':[.60,.21,.035]},
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
        'detail_camera':DETAIL_CAMERA,'waterfront_camera':WATERFRONT_CAMERA,'stage':'composition study; not a desktop world'},indent=2)+'\n')
    if args.render:
        render_preview(out, sky_audit=args.sky_audit)
    print(f'{out}: {len(mesh[3])//3:,} static triangles; finite geometry and unit normals verified')

if __name__=='__main__': main()
