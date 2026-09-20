#!/usr/bin/env python3
"""Independent reference-view study. Does not replace the installed city.

python3 build/tools/wallpaper-city.py --out /tmp/wallpaper-city
Render with roomtest at 0 40 18 0 7.5, 1672 x 941.
Geometry is authored from the wallpaper; no wallpaper projection is used.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('voxel', HERE / 'voxel-world.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)


def ground(z):
    return max(-2., 32 + .45*min(z, 0))


def build(seed=12):
    rng = np.random.default_rng(seed)
    props = []
    def box(t,x,y,z,xx,yy,zz):
        props.append(('box',t,x,y,z,xx,yy,zz))
    def beam(t,a,b,w):
        props.append(('beam',t,a,b,w))
    def tree(x,z,y,s=1):
        box('log',x-.17*s,y,z-.17*s,x+.17*s,y+3*s,z+.17*s)
        for _ in range(44):
            p=rng.uniform(-1,1,3)
            if np.linalg.norm(p)>1.2: continue
            dx,dy,dz=p*np.array([1.45,1.65,1.35])*s
            r=rng.uniform(.27,.52)*s
            box(rng.choice(['leaves','leaves_dark','leaves_light']),x+dx-r,y+3.4*s+dy-r,z+dz-r,x+dx+r,y+3.4*s+dy+r,z+dz+r)
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
    tree(-13,-2,ground(-2),2.8)
    tree(14,-8,ground(-8),2.0)
    # Waterfront neighbourhoods: small, tightly packed blocks beyond the hill.
    for z in (-92,-105,-119):
        for x in np.arange(-65,70,9):
            if x>10 and z==-119: continue
            house(x,z,7,rng.uniform(4,8),rng.choice(colors),base=-2)
    # Long Ferry Building and clock tower, right of the vanishing point.
    house(9,-137,65,7,'plaster_cream',d=8,base=-2)
    tx=34
    box('limestone',tx-2,5,-137,tx+2,22,-133)
    for y,w in ((21,2.5),(23,1.8),(25,1.1),(27,.6)):
        box('limestone',tx-w,y,-135-w,tx+w,y+1.5,-135+w)
    beam('bronze',(tx,28,-135),(tx,31,-135),.09)
    # Clock face and hands are geometry, visible without shell overlays.
    props.append(('ellipsoid','lamp',(tx,18.8,-132.94),(1.02,1.02,.055),8))
    beam('dark',(tx,18.8,-132.86),(tx,19.5,-132.86),.09)
    beam('dark',(tx,18.8,-132.85),(tx+.5,18.5,-132.85),.09)
    # Sea, warm reflections and island.
    box('water',-5000,-3,-5000,5000,-2.5,-142)
    box('water',10,-3,-142,75,-2.5,-80)
    for _ in range(3300):
        z=rng.uniform(-420,-90); x=rng.uniform(-190,250)
        if z>-142 and not 12<x<70: continue
        props.append(('ripple','reflection_amber' if abs(x-110)<18 else 'water_glint',x,-2.47,z,rng.uniform(.25,2),.06))
    for x in np.arange(-75,-12,2):
        h=1+4*np.sin(np.pi*(x+75)/63)
        box('hill',x,-2.5,-230,x+2,h,-210)
        if int(x)%4==0: tree(x,-219,h,.6)
    house(-54,-219,24,3.5,'plaster_cream',base=3)
    box('limestone',-22,2,-220,-20,13,-218)
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
    # Inhabited headlands: blocked silhouettes and warm distant windows.
    for x in np.arange(-440,400,4):
        h=12+29*np.exp(-((x+170)/115)**2)+15*np.exp(-((x-280)/80)**2)
        box('hill_far',x,-3,-500,x+4,h,-460)
        if x<0 or x>205:
            for k in range(4):
                y=rng.uniform(2,h)
                box('hill',x,y,-458,x+3,y+2,-455)
                box('interior_warm',x+.5,y+.4,-454.9,x+1,y+.9,-454.8)
    for y in np.arange(38,70,5):
        half=(70-y)*.09
        for side in (-1,1):
            beam('bronze',(-160+side*half,y,-452),(-160+side*max(0,half-.45),y+5,-452),.2)
        beam('bridge_red',(-160-half,y,-452),(-160+half,y,-452),.2)
    # Broken cloud banks with small voxel lobes, placed beyond the hills.
    for cx,cy,cz,length in ((-210,145,-760,190),(20,135,-760,165),(245,112,-760,160),(-140,88,-700,110)):
        for _ in range(140):
            xx=cx+rng.uniform(-length/2,length/2)
            yy=cy+rng.normal(0,3)
            zz=cz+rng.uniform(-9,9)
            r=rng.uniform(1,3.5)
            box('cloud',xx-r,yy-r*.45,zz-r,xx+r,yy+r*.45,zz+r)
    return v.mesh_blocks(np.zeros((1,1,1),np.uint8),(0,0),props)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
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
                positions[:,1]=[ground(z)+.1 for z in positions[:,2]]
            else: continue
            result.append((name,mesh,times,positions))
        return result
    mesh=build()
    assert all(np.isfinite(a).all() for a in mesh)
    assert np.allclose(np.linalg.norm(mesh[1],axis=1),1,atol=1e-5)
    assert mesh[3].max()<len(mesh[0])
    v.write_glb(out/'room.glb',*mesh,out/'atlas.png',actors=actors(),trolley_slope=.45,
                light_positions=[[side*9.3+.5,ground(z+2)+3.2,z+2.5]
                                 for z in (-5,-17,-29) for side in (-1,1)])
    source=HERE.parents[1]/'shell/Resources/Worlds/city'
    for name in ('room_ibl.ktx','room_skybox.ktx'): shutil.copy2(source/name,out/name)
    (out/'reference-camera.json').write_text(json.dumps({'position':[0,40,18],'yaw':0,'pitch':7.5,'size':[1672,941],'stage':'composition study; not a desktop world'},indent=2)+'\n')
    print(f'{out}: {len(mesh[3])//3:,} static triangles; finite geometry and unit normals verified')

if __name__=='__main__': main()
