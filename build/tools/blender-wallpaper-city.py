#!/usr/bin/env python3
"""Editable Blender study. Run: blender -b --python this.py -- --out DIR.
Blender is the source asset editor; this script reproduces the initial study.
Coordinates are metres, Z up, +Y downhill. No wallpaper projection geometry.
"""
import bpy, math, random, argparse, sys
from pathlib import Path
from mathutils import Vector, Matrix
rng=random.Random(51)
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--samples',type=int,default=32);p.add_argument('--width',type=int,default=1200)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);a.out.mkdir(parents=True,exist_ok=True)
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name!='Collection': bpy.data.collections.remove(c)
base=bpy.data.collections.get('Collection');base.name='00 • Cameras and lighting'
collections={}
def group(name):
    if name not in collections:
        c=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(c);collections[name]=c
    return collections[name]
def move(obj,coll):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    group(coll).objects.link(obj)
def material(name,color,rough=.65,metal=0,emission=0):
    # Palette values are sRGB swatches; shader inputs are scene-linear.
    swatch=color
    color=tuple(v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in color)
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    s=m.node_tree.nodes.get('Principled BSDF');s.inputs['Base Color'].default_value=(*color,1);s.inputs['Roughness'].default_value=rough;s.inputs['Metallic'].default_value=metal
    if emission:s.inputs['Emission Color'].default_value=(*swatch,1);s.inputs['Emission Strength'].default_value=emission
    if not emission and not metal:
        nodes=m.node_tree.nodes;links=m.node_tree.links
        noise=nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=3;noise.inputs['Detail'].default_value=2
        bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.16;bump.inputs['Distance'].default_value=.045
        links.new(noise.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],s.inputs['Normal'])
    return m
stone=material('Warm limestone',(0.49,.43,.34));trim=material('Ivory painted timber',(.78,.70,.56));dark=material('Cast iron',(.055,.065,.065),.35,.6)
roof=material('Slate roofs',(.095,.115,.13));glass=material('Amber window interiors',(.55,.25,.065),.35,emission=.65)
facades=[material('Facade • '+n,c) for n,c in [('sage',(.32,.39,.31)),('terracotta',(.55,.28,.19)),('sand',(.63,.49,.33)),('blue grey',(.31,.40,.43)),('cream',(.70,.62,.47))]]
leaves=[material('Foliage '+str(i),c) for i,c in enumerate([(.12,.19,.07),(.20,.27,.095),(.29,.33,.12)])]
wood=material('Tree bark',(.22,.12,.065));red=material('Cable car oxblood',(.34,.055,.035),.38);brass=material('Old brass',(.58,.34,.10),.27,.65)
bridge=material('Bridge vermilion',(.40,.13,.09),.55);land=material('Distant hillside',(.20,.27,.24));lamp=material('Lantern glow',(1,.57,.19),.3,emission=4)
cobbles=[material('Cobble '+str(i),(.27+i*.021,.25+i*.019,.23+i*.018),.5) for i in range(7)]
window_moods=[
    material('Window • dusk blue',(.18,.25,.30),.22,emission=.035),
    material('Window • dim interior',(.38,.25,.13),.3,emission=.16),
    material('Window • warm room',(.70,.37,.12),.3,emission=.6),
    glass,
]
# Each architectural component is a mesh batch, editable independently in Blender.
class Batch:
    def __init__(self,name,coll):self.name=name;self.coll=coll;self.v=[];self.f=[];self.mi=[];self.m=[]
    def box(self,c,s,m):
        x,y,z=c;u,v,w=[q/2 for q in s];n=len(self.v)
        self.v += [(x+dx*u,y+dy*v,z+dz*w) for dx,dy,dz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        self.f += [tuple(n+i for i in f) for f in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]]
        if m not in self.m:self.m.append(m)
        self.mi += [self.m.index(m)]*6
    def finish(self,bevel=0):
        mesh=bpy.data.meshes.new(self.name);mesh.from_pydata(self.v,[],self.f);mesh.update()
        obj=bpy.data.objects.new(self.name,mesh);group(self.coll).objects.link(obj)
        for m in self.m:mesh.materials.append(m)
        for poly,i in zip(mesh.polygons,self.mi):poly.material_index=i
        if bevel:
            mod=obj.modifiers.new('Small edge highlights','BEVEL');mod.width=bevel;mod.segments=2
        return obj

def box(name,c,s,m,coll,bevel=0):
    b=Batch(name,coll);b.box(c,s,m);return b.finish(bevel)
def beam(name,start,end,r,m,coll):
    d=Vector(end)-Vector(start);bpy.ops.mesh.primitive_cylinder_add(vertices=8,radius=r,depth=d.length,location=(Vector(start)+Vector(end))/2)
    o=bpy.context.object;o.name=name;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();o.data.materials.append(m);move(o,coll);return o

def ground(y):return max(0,24-.23*y-.00065*y*y)
road=Batch('Individual cobbles • downhill street','01 • Street and retaining walls')
for j in range(216):
    y=-57+j*.68
    for i in range(22):
        x=(i-10.5)*.80+(j%2)*.4
        road.box((x,y,ground(y)+rng.uniform(-.013,.013)),(.77,.64,.15),rng.choice(cobbles))
road.finish(.022)
# Rails follow the slope instead of floating as straight bars.
for x in [-6.9,-5.1]:
    for j in range(107):
        y=-57+j*1.4
        beam('Tram rail',(x,y,ground(y)+.10),(x,y+1.4,ground(y+1.4)+.10),.045,brass,'01 • Street and retaining walls')
for side in [-1,1]:
    paving=Batch('Sidewalk '+str(side),'01 • Street and retaining walls')
    for j in range(152):
        y=-54+j*.95;paving.box((side*10.4,y,ground(y)+.16),(3.0,.93,.22),trim)
    paving.finish(.035)
    for row,y in enumerate([0,13,26,39,52,65,78]):
        x=side*(16.0+max(0,row-2)*(2.5 if side>0 else 1.3));w=7.8;depth=10.;z=ground(y);h=12.0-row*.5
        coll='02 • Victorian street';name=f'{"West" if side<0 else "East"} house {row+1}'
        b=Batch(name+' / masonry',coll);b.box((x,y,z+h/2),(w,depth,h),facades[(row+(side>0))%5]);b.box((x,y,z+.35),(w+.5,depth+.4,.7),stone)
        for k in range(4):b.box((x,y,z+h+k*.15),(w+.15+k*.16,depth+.15+k*.16,.14),trim)
        b.box((x,y,z+h+.62),(w-.3,depth-.3,.13),roof);b.box((x+2,y+2,z+h+1.2),(.6,.7,1.4),stone)
        for level in range(1,3):b.box((x,y,z+level*3.6),(w+.18,depth+.18,.17),trim)
        b.finish(.035)
        front=y-depth/2;windows=Batch(name+' / bay windows and sash',coll)
        for floor in range(3 if h >= 11 else 2):
            zz=z+2.2+floor*3.65
            for wi,xx in enumerate([x-2.35,x,x+2.35]):
                pane=window_moods[(row*3+floor+wi+(side>0))%4]
                # Projecting bay gives the facade depth and an articulated silhouette.
                bay=.65 if abs(xx-x)<.1 else .18
                windows.box((xx,front-bay/2,zz),(1.65,bay,2.65),trim)
                windows.box((xx,front-bay-.025,zz),(1.32,.07,2.26),pane)
                for dx in [-.71,0,.71]:windows.box((xx+dx,front-bay-.09,zz),(.085,.10,2.48),trim)
                windows.box((xx,front-bay-.09,zz+.02),(1.5,.1,.09),trim)
                windows.box((xx,front-bay-.04,zz-1.27),(1.9,.42,.14),trim)
            # Street-facing side windows make walking views useful too.
            sx=x-side*(w/2+.035)
            for wi,yy in enumerate([y-2.6,y,y+2.6]):
                pane=window_moods[(row+floor*2+wi+(side>0))%4]
                # Deep street-facing bays, stacked through the three storeys.
                windows.box((sx-side*.45,yy,zz),(.9,1.95,2.6),trim)
                windows.box((sx-side*.94,yy,zz),(.06,1.54,2.22),pane)
                for dy in [-.87,0,.87]:windows.box((sx-side*1.02,yy+dy,zz),(.13,.10,2.5),trim)
                windows.box((sx-side*1.02,yy,zz),(.13,1.85,.10),trim)
                for dz in [-1.3,1.3]:windows.box((sx-side*.52,yy,zz+dz),(1.2,2.2,.16),trim)
                windows.box((sx,yy,zz),(.12,1.38,2.22),glass)
                for dy in [-.77,0,.77]:windows.box((sx-side*.10,yy+dy,zz),(.24,.095,2.46),trim)
                windows.box((sx-side*.10,yy,zz),(.24,1.6,.09),trim)
                windows.box((sx-side*.25,yy,zz-1.28),(.55,1.84,.14),trim)
                for dz in [-1.2,1.2]:windows.box((sx-side*.07,yy,zz+dz),(.22,1.64,.12),trim)
        # Dentil cornice and recessed entry break up the repeated facade.
        for xx in range(12):windows.box((x-w/2+xx*w/11,front-.2,z+h-.15),(.22,.3,.25),trim)
        windows.box((x,front-.09,z+1.1),(1.2,.22,2.1),wood)
        # Colored apron panels, occasional shutters and fine siding break up
        # the continuous ivory window strips without changing walkable space.
        siding=Batch(name+' / siding and apron panels',coll)
        facade=facades[(row+(side>0))%5]
        for k in range(1,int(h/.32)):
            siding.box((x,front-.018,z+k*.32),(w,.035,.023),stone)
            siding.box((x-side*(w/2+.018),y,z+k*.32),(.035,depth,.023),stone)
        for floor in range(1,3 if h>=11 else 2):
            zz=z+2.2+floor*3.65
            for yy in [y-2.6,y,y+2.6]:
                siding.box((sx-side*.96,yy,zz-1.67),(.08,1.6,.48),facade)
                siding.box((sx-side*1.015,yy,zz-1.67),(.035,1.28,.27),stone)
        if row%3==1:
            for yy in [y-2.6,y,y+2.6]:
                for dy in [-1.1,1.1]:
                    siding.box((sx-side*.98,yy+dy,z+2.2),(.10,.30,2.3),facades[0])
                    for k in range(7):siding.box((sx-side*1.05,yy+dy,z+1.3+k*.28),(.08,.31,.06),trim)
        siding.finish(.008)
        if row%3==1:
            # A hipped roof with a short ridge, distinct from neighboring flat roofs.
            rz=z+h+.65;rw=w/2+.1;rd=depth/2+.1
            verts=[(x-rw,y-rd,rz),(x+rw,y-rd,rz),(x+rw,y+rd,rz),(x-rw,y+rd,rz),(x,y-2,rz+1.8),(x,y+2,rz+1.8)]
            mesh=bpy.data.meshes.new(name+' roof');mesh.from_pydata(verts,[],[(0,1,4),(1,2,5,4),(2,3,5),(3,0,4,5)]);mesh.materials.append(roof)
            obj=bpy.data.objects.new(name+' / hipped roof',mesh);group(coll).objects.link(obj)
        elif row%3==2:
            for k in range(9):windows.box((x-w/2+k*w/8,front,z+h+1),(.10,.14,.8),dark)
            windows.box((x,front,z+h+1.4),(w,.17,.10),dark)
        windows.finish(.018)
        # Terraces step naturally between houses.
        wall=Batch(name+' / terrace', '01 • Street and retaining walls')
        for k in range(8):
            yy=y-5+k*.65;zz=ground(yy)
            wall.box((side*12.1,yy,zz+.45),(.38,.64,.9),stone)
        wall.finish(.03)
        garden=Batch(name+' / entry stairs and planters','01 • Street and retaining walls')
        for step in range(6):
            garden.box((side*(11.3+step*.30),y-3,ground(y-3)+step*.12),(.32,1.5,.20+step*.12),stone)
        for yy in [y-4,y+3]:
            garden.box((side*12.3,yy,ground(yy)+.62),(1.1,1.3,.8),stone)
            for k in range(9):garden.box((side*12.3+rng.uniform(-.4,.4),yy+rng.uniform(-.5,.5),ground(yy)+1.12+rng.random()*.25),(.23,.24,.23),rng.choice(leaves))
        garden.finish(.03)

def tree(x,y,z,size=1):
    coll='03 • Trees and lanterns';beam('Branching tree trunk',(x,y,z),(x+.15,y,z+4*size),.22*size,wood,coll)
    for dx,dy,dz,r in [(-.9,0,3.7,1.25),(.8,.15,4.0,1.3),(0,-.7,4.7,1.35),(.15,.7,4.5,1.1)]:
        c=(x+dx*size,y+dy*size,z+dz*size);beam('Branch',(x,y,z+2*size),c,.10*size,wood,coll)
        foliage=Batch('Layered foliage cluster',coll)
        step=.38*size
        for ix in range(-3,4):
            for iy in range(-3,4):
                for iz in range(-3,4):
                    q=(ix*step,iy*step,iz*step)
                    if sum(v*v for v in q)>(r*size)**2*rng.uniform(.78,1.08):continue
                    if abs(ix)<2 and abs(iy)<2 and abs(iz)<2:continue
                    foliage.box((c[0]+q[0],c[1]+q[1],c[2]+q[2]),(step*1.04,)*3,rng.choice(leaves))
        foliage.finish(.025*size)

for side in [-1,1]:
    for y in [1,18,34,50,67,81]:
        tree(side*11.7,y,ground(y)+.25,1.1 if y<20 else .9)
        x=side*9.5;yy=y+4;z=ground(yy);coll='03 • Trees and lanterns'
        beam('Cast iron lantern post',(x,yy,z),(x,yy,z+3.2),.075,dark,coll)
        box('Lantern glass',(x,yy,z+3.35),(.34,.34,.58),lamp,coll,.025)
        box('Lantern cap',(x,yy,z+3.69),(.52,.52,.13),dark,coll,.03)
        for dx in [-.19,.19]:
            for dy in [-.19,.19]:beam('Lantern frame',(x+dx,yy+dy,z+3.03),(x+dx,yy+dy,z+3.65),.025,dark,coll)
b=Batch('Lower street connection','01 • Street and retaining walls')
for j in range(38):
    yy=88+j
    b.box((0,yy,ground(yy)-.12),(19,1.02,.24),stone)
b.finish()
# Low blocks near the waterfront preserve the middle-distance street view.
for row,y in enumerate([94,107]):
    for x in [-35,-23,-12,12,23,35,47]:
        z=ground(y);h=rng.uniform(5,8);b=Batch(f'Waterfront block {row} {x}','04 • Waterfront')
        b.box((x,y,z+h/2),(9,9,h),rng.choice(facades));b.box((x,y,z+h),(9.5,9.5,.28),trim)
        for xx in [-3,-1,1,3]:
            for zz in [2,4.5]:b.box((x+xx,y-4.55,z+zz),(.85,.08,1.5),glass)
        b.finish(.025)
# Ferry terminal and promenade: a long horizontal anchor beneath the clock.
# Arched glazing and segmented stone surrounds are real editable mesh geometry.
def arch_panel(batch,c,width,height,depth,mat):
    x,y,z=c;r=width/2;spring=height-r
    outline=[(-r,0),(r,0)]+[(r*math.cos(i*math.pi/12),spring+r*math.sin(i*math.pi/12)) for i in range(13)]
    base=len(batch.v);count=len(outline)
    batch.v += [(x+u,y+dy,z+v) for dy in [-depth/2,depth/2] for u,v in outline]
    faces=[tuple(base+i for i in reversed(range(count))),tuple(base+count+i for i in range(count))]
    faces += [(base+i,base+(i+1)%count,base+(i+1)%count+count,base+i+count) for i in range(count)]
    # Outline runs counterclockwise in X/Z; reverse the extrusion for outward normals.
    faces=[tuple(reversed(f)) for f in faces]
    batch.f+=faces
    if mat not in batch.m:batch.m.append(mat)
    batch.mi += [batch.m.index(mat)]*len(faces)
b=Batch('Ferry Building colonnade','04 • Waterfront')
b.box((25,128,-.2),(86,19,1.4),stone)
b.box((27,133,4.3),(65,10,8.6),facades[4])
for zz in [.7,4.7,8.55,8.85]:b.box((27,133,zz),(66,10.7,.23),trim)
b.box((27,133,9),(65,10,.16),roof)
for index,x in enumerate(range(-4,61,3)):
    for zz,w,h in [(1,1.7,3.3),(5.3,1.4,2.45)]:
        arch_panel(b,(x,127.78,zz),w+.36,h+.18,.35,trim)
        arch_panel(b,(x,127.54,zz+.12),w,h-.06,.12,window_moods[1 if index%4==0 else 2])
        b.box((x,127.43,zz+h*.42),(.075,.13,h*.78),dark)
        b.box((x,127.43,zz+h-w/2),(w,.13,.085),dark)
        b.box((x,127.40,zz+.03),(w+.4,.5,.17),stone)
    b.box((x-1.32,127.55,4.5),(.28,.6,7.6),trim)
    b.box((x-1.32,127.38,8.1),(.46,.75,.25),trim)
    b.box((x,128,9.45),(2.5,.25,.7),stone)
    b.box((x,127.82,9.45),(2.15,.10,.4),roof)
    if index%3==0:
        b.box((x-1.2,127.12,3.2),(.18,.24,.35),lamp)
b.box((27,128,9.87),(66,.55,.22),trim)
b.finish(.025)
x,y=25,131;b=Batch('Clock tower masonry','04 • Waterfront')
for z,w,d,h in [(9,6,6,7),(14,5,5,3),(17.5,4,4,4),(20.5,3,3,2),(22.3,1.8,1.8,1.6)]:
    b.box((x,y,z),(w,d,h),trim);b.box((x,y,z+h/2),(w+.4,d+.4,.20),stone)
b.finish(.04)
bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=1.12,depth=.10,location=(x,y-2.58,14),rotation=(math.pi/2,0,0));o=bpy.context.object;o.name='Illuminated clock dial';o.data.materials.append(lamp);move(o,'04 • Waterfront')
beam('Clock minute hand',(x,y-2.66,14),(x,y-2.66,14.88),.045,dark,'04 • Waterfront');beam('Clock hour hand',(x,y-2.67,14),(x-.57,y-2.67,14.28),.06,dark,'04 • Waterfront')
# Clock details and open belfry replace the blank upper masonry faces.
b=Batch('Clock tower pilasters and belfry','04 • Waterfront')
for side in [-1,1]:
    b.box((25+side*2.15,128.4,10),( .35,.4,6.4),stone)
    b.box((25+side*1.05,128.96,17.6),(.55,.12,2.4),roof)
for i in range(12):
    ang=i*math.tau/12
    b.box((25+math.sin(ang)*.94,128.29,14+math.cos(ang)*.94),(.065,.035,.10),dark)
for xx in [-1,1]:b.box((25+xx*2.35,131,16),( .18,5.1,.65),stone)
b.finish(.025)
bpy.ops.mesh.primitive_cone_add(vertices=4,radius1=2.4,radius2=0,depth=2.8,rotation=(0,0,math.pi/4),location=(25,131,24))
o=bpy.context.object;o.name='Clock tower pyramidal copper roof';o.data.materials.append(roof);move(o,'04 • Waterfront')
beam('Tower finial',(25,131,25.4),(25,131,26.5),.07,brass,'04 • Waterfront')
# Quay coping, seawall courses and bollards connect the terminal to the bay.
b=Batch('Quay edge and moorings','04 • Waterfront')
for xx in range(-17,69,2):
    b.box((xx,138,-.15),(1.95,1.1,1.5),stone)
    b.box((xx,138,.65),(2,.95,.20),trim)
    if xx%6==1:b.box((xx,137.8,1.05),(.32,.32,.6),dark)
b.finish(.04)
# Cable car with framed cabin, curved roof, running boards and wheelsets.
coll='05 • Cable car';y=29;x=-6;z=ground(y);b=Batch('Cable car body',coll)
b.box((x,y,z+1.7),(2.8,5.3,3),red)
for xx in [-.87,0,.87]:
    b.box((x+xx,y-2.68,z+2.3),(.70,.07,1.36),window_moods[2])
    for dx in [-.40,.40]:b.box((x+xx+dx,y-2.77,z+2.3),(.09,.12,1.64),brass)
    for zz in [1.53,2.4,3.08]:b.box((x+xx,y-2.77,z+zz),(.83,.12,.075),brass)
    b.box((x+xx,y-2.72,z+.84),(.70,.12,.67),wood)
    b.box((x+xx,y-2.80,z+.84),(.55,.05,.50),red)
for yy in [-1.8,-.6,.6,1.8]:
    for side in [-1,1]:
        b.box((x+side*1.42,y+yy,z+2.3),(.08,.9,1.45),window_moods[2 if yy<0 else 1])
        for dy in [-.52,.52]:b.box((x+side*1.5,y+yy+dy,z+2.3),(.15,.09,1.7),brass)
        b.box((x+side*1.52,y+yy,z+2.55),(.12,1.05,.07),brass)
for side in [-1,1]:
    b.box((x+side*1.52,y,z+.40),(.45,5.7,.15),wood)
    b.box((x+side*1.53,y,z+1.18),(.12,5.5,.14),brass)
    b.box((x+side*1.53,y,z+3.15),(.14,5.5,.18),brass)
b.box((x,y-2.98,z+.3),(3.2,.6,.20),dark)
b.box((x,y-2.84,z+1.16),(2.9,.3,.16),brass)
b.box((x,y-2.91,z+3.33),(2.5,.16,.30),dark)
b.finish(.018)
def car_roof(name,width,length,base,rise,mat):
    verts=[];faces=[];steps=16
    for yy in [y-length/2,y+length/2]:
        for i in range(steps+1):
            u=2*i/steps-1;verts.append((x+u*width/2,yy,z+base+rise*(1-u*u)))
    for i in range(steps):faces.append((i,i+1,steps+2+i,steps+1+i))
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.materials.append(mat)
    o=bpy.data.objects.new(name,me);group(coll).objects.link(o)
    mod=o.modifiers.new('Roof thickness','SOLIDIFY');mod.thickness=.12
car_roof('Cable car curved main roof',3.6,6,3.45,.23,roof)
b=Batch('Cable car clerestory',coll);b.box((x,y,z+3.83),(2.1,4.8,.36),red)
for side in [-1,1]:
    for yy in [-1.8,-.9,0,.9,1.8]:b.box((x+side*1.06,y+yy,z+3.84),(.07,.62,.22),glass)
b.finish(.02)
car_roof('Cable car clerestory cap',2.5,5.2,4.02,.13,roof)
for side in [-1,1]:
    for yy in [-1.8,1.8]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=.43,depth=.18,location=(x+side*1.3,y+yy,z+.30),rotation=(0,math.pi/2,0))
        o=bpy.context.object;o.name='Cable car wheel';o.data.materials.append(dark);move(o,coll)
    beam('Front platform handrail',(x+side*1.45,y-3.1,z+.45),(x+side*1.45,y-3.1,z+1.55),.035,brass,coll)
bpy.ops.object.text_add(location=(x,y-3.01,z+3.26),rotation=(math.pi/2,0,0))
o=bpy.context.object;o.name='Cable car destination';o.data.body='BAY & MARKET';o.data.align_x='CENTER';o.data.size=.20;o.data.extrude=.002;o.data.materials.append(trim);move(o,coll);bpy.ops.object.convert(target='MESH')
bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.22,location=(x,y-2.96,z+.95));o=bpy.context.object;o.name='Cable car headlamp';o.data.materials.append(lamp);move(o,coll)
# Scale the landmark and pitch its complete assembly to the local street grade.
grade=Matrix.Rotation(math.atan(-.23-.0013*y),4,'X')
for o in group('05 • Cable car').objects:
    if o.type=='MESH':
        anchor=Vector((x,y,z))
        for v in o.data.vertices:
            world=o.matrix_world @ v.co
            v.co=o.matrix_world.inverted() @ (anchor+Vector((0,0,.25))+grade @ ((world-anchor)*1.45))
# Continuous terrain, rather than a cloud of disconnected distant cubes.
def island(name,x,y,rx,ry,height):
    vertices=[(x,y,height)];faces=[];rings=16;steps=64
    for k in range(1,rings+1):
        t=k/rings
        for i in range(steps):
            ang=i*math.tau/steps;r=t*(1+.05*math.sin(ang*5)+.03*math.cos(ang*9))
            vertices.append((x+rx*r*math.cos(ang),y+ry*r*math.sin(ang),height*max(0,1-t*t)**1.6+math.sin(ang*4)*t*(1-t)*height*.12-.5))
    for i in range(steps):faces.append((0,1+i,1+(i+1)%steps))
    for k in range(rings-1):
        for i in range(steps):q=1+k*steps+i;n=1+k*steps+(i+1)%steps;faces.append((q,q+steps,n+steps,n))
    me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces);me.materials.append(land);o=bpy.data.objects.new(name,me);group('06 • Bay and distant landscape').objects.link(o)
    for f in me.polygons:f.use_smooth=True
island('Continuous wooded island',-55,300,60,34,14)
island('Marin ridge',-190,560,230,95,48);island('Eastern headland',380,690,170,110,65)
b=Batch('Island buildings','06 • Bay and distant landscape');b.box((-58,301,14),(27,8,5),facades[4]);b.box((-58,301,16.6),(28,9,.3),roof)
for xx in range(-69,-45,3):b.box((xx,296.9,14.5),(1.2,.12,1.8),glass)
b.box((-40,300,20),(2.5,2.5,14),trim);b.finish()
# Small grouped buildings and tree crowns articulate the continuous hills.
b=Batch('Distant settlement lights','06 • Bay and distant landscape')
for i in range(160):
    while True:
        xx=rng.uniform(-380,-20);yy=rng.uniform(490,615)
        nx=(xx+190)/230;ny=(yy-560)/95;ang=math.atan2(ny,nx)
        t=math.hypot(nx,ny)/(1+.05*math.sin(ang*5)+.03*math.cos(ang*9))
        if t < .94:break
    zz=48*max(0,1-t*t)**1.6+math.sin(ang*4)*t*(1-t)*48*.12-.5
    b.box((xx,yy,zz+1),(2.5,2,2),rng.choice(facades))
    b.box((xx,yy-1.05,zz+1),(.7,.05,.65),glass)
b.finish()
# Dense, stepped canopy clusters follow the same terrain surface as the mesh.
for name,cx,cy,rx,ry,h,count in [('Island woodland',-55,300,60,34,14,360),('Marin woodland',-190,560,230,95,48,1800),('Eastern woodland',380,690,170,110,65,650)]:
    b=Batch(name,'06 • Bay and distant landscape')
    for i in range(count):
        ang=rng.uniform(0,math.tau);t=math.sqrt(rng.uniform(.03,.90))
        r=t*(1+.05*math.sin(ang*5)+.03*math.cos(ang*9))
        xx=cx+rx*r*math.cos(ang);yy=cy+ry*r*math.sin(ang)
        if name=='Island woodland' and -75<xx<-36 and 294<yy<309:continue
        zz=h*max(0,1-t*t)**1.6+math.sin(ang*4)*t*(1-t)*h*.12-.5
        size=rng.uniform(1.2,2.5) if count==360 else rng.uniform(2,4)
        for level in range(3):
            w=size*(1-level*.22)
            b.box((xx,yy,zz+size*.35+level*size*.4),(w,w,size*.65),rng.choice(leaves))
    b.finish()
# Uneven stone revetment gives the island a readable edge against the water.
b=Batch('Island shoreline rocks','06 • Bay and distant landscape')
for i in range(180):
    ang=i*math.tau/180;r=1+.05*math.sin(ang*5)+.03*math.cos(ang*9)
    b.box((-55+60*r*math.cos(ang),300+34*r*math.sin(ang),-.55),(rng.uniform(.8,2),rng.uniform(.8,1.8),rng.uniform(.4,1.1)),stone)
b.finish(.08)
# Suspension bridge: deck, two connected towers, parabolic main cable, hangers.
coll='07 • Suspension bridge';b=Batch('Bridge towers and deck',coll)
b.box((125,555,33),(380,8,2),bridge)
for tx in [35,215]:
    for yy in [552,558]:
        for dx in [-3.1,3.1]:b.box((tx+dx,yy,40),(1.8,1.8,80),bridge)
        for zz in [28,49,68,78]:b.box((tx,yy,zz),(8,1.9,1.5),bridge)
b.finish(.10)
for yy in [552,558]:
    def cable(xx):
        if xx<35:return 36+43*((xx+65)/100)**2
        if xx>215:return 36+43*((315-xx)/100)**2
        return 38+41*((xx-125)/90)**2
    for xx in range(-65,315,5):
        beam('Main suspension cable',(xx,yy,cable(xx)),(xx+5,yy,cable(xx+5)),.22,bridge,coll)
        beam('Suspension hanger',(xx,yy,34),(xx,yy,cable(xx)),.06,bridge,coll)
# Water uses a subtle anisotropic bump; geometry and base PBR export separately.
water=material('Bay water • Blender procedural study',(.32,.44,.54),.16,.1)
n=water.node_tree.nodes;l=water.node_tree.links;s=n.get('Principled BSDF');tex=n.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=.7;tex.inputs['Detail'].default_value=3
coord=n.new('ShaderNodeTexCoord');mapping=n.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=(.65,4,1);l.new(coord.outputs['Object'],mapping.inputs[0]);l.new(mapping.outputs[0],tex.inputs['Vector'])
bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.5;bump.inputs['Distance'].default_value=.3;l.new(tex.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs['Normal'],s.inputs['Normal'])
geo=n.new('ShaderNodeNewGeometry');l.new(geo.outputs['Position'],mapping.inputs[0])
mapping.inputs[1].default_value=(.22,1.6,1)
tex.inputs['Scale'].default_value=1.4
bump.inputs['Distance'].default_value=.35
bump.inputs['Strength'].default_value=.8
box('Bay water',(0,900,-1.3),(2500,1560,.15),water,'06 • Bay and distant landscape')
# Ferry placed in open water above the terminal, with a tapered bow and wake.
coll='08 • Ferry';fx,fy=70,250
b=Batch('Ferry decks and fittings',coll)
for zz,w,d,h,m in [(-.15,9,20,1.5,dark),(1.0,8,18,1.3,trim),(2.4,6.8,14,1.3,trim),(3.5,5,8,.65,trim)]:b.box((fx,fy,zz),(w,d,h),m)
for zz,w,d in [(1.1,8.1,18),(2.5,6.9,14)]:
    for xx in [-2.6,-1.3,0,1.3,2.6]:b.box((fx+xx,fy-d/2-.04,zz),(.9,.10,.65),roof)
    for side in [-1,1]:
        for yy in range(-5,6,2):b.box((fx+side*w/2,fy+yy,zz),(.10,1.3,.65),roof)
for side in [-1,1]:
    for yy in range(-8,9,2):b.box((fx+side*3.9,fy+yy,2),(.09,.09,.8),trim)
    b.box((fx+side*3.9,fy,2.4),(.10,17,.10),trim)
b.box((fx+1.2,fy+2,4.4),(1.2,1.6,1.8),red);b.box((fx+1.2,fy+2,5.35),(1.3,1.7,.18),dark)
b.box((fx,fy-2,5),(.10,.10,2),brass);b.finish(.06)
# Tapered bow continues the hull beneath the front deck.
me=bpy.data.meshes.new('Ferry bow');me.from_pydata([(fx-4.5,fy-10,-.9),(fx+4.5,fy-10,-.9),(fx,fy-14,-.7),(fx-4.5,fy-10,.6),(fx+4.5,fy-10,.6),(fx,fy-14,.4)],[],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]);me.materials.append(dark);o=bpy.data.objects.new('Tapered ferry bow',me);group(coll).objects.link(o)
foam=material('Soft wake foam',(.44,.56,.57),.45)
b=Batch('Broken ferry wake',coll)
for side in [-1,1]:
    for i in range(40):
        b.box((fx+side*(4.5+i*.23)+rng.uniform(-.25,.25),fy+8+i*.85,-1.19),(rng.uniform(.3,1),rng.uniform(.4,1.4),.025),foam)
b.finish()
# Present the ferry broadside; keep the wake in the same local frame.
from mathutils import Matrix
turn=Matrix.Rotation(math.radians(65),4,'Z');anchor=Vector((fx,fy,-1.2))
for o in group('08 • Ferry').objects:
    for v in o.data.vertices:v.co=anchor+(turn @ (v.co-anchor))*1.35
# Composition pass: retain three-dimensional geometry while matching the
# reference's smaller distant landmarks and lower eastern street frontage.
def reshape(objects,transform):
    for ob in objects:
        if ob.type!='MESH':continue
        inverse=ob.matrix_world.inverted()
        for vertex in ob.data.vertices:
            vertex.co=inverse @ Vector(transform(ob.matrix_world @ vertex.co))
reshape(group('07 • Suspension bridge').objects,
        lambda p:(125+(p.x-125)*.70,p.y,-1.225+(p.z+1.225)*.62))
landscape=group('06 • Bay and distant landscape')
island_names={'Continuous wooded island','Island buildings','Island woodland','Island shoreline rocks'}
reshape([ob for ob in landscape.objects if ob.name in island_names],
        lambda p:(-10+(p.x+55)*.88,410+(p.y-300)*.88,-1.225+(p.z+1.225)*.88))
reshape([ob for ob in landscape.objects if ob.name in {'Marin ridge','Marin woodland','Distant settlement lights'}],
        lambda p:(p.x,p.y,-1.225+(p.z+1.225)*.75))
reshape([ob for ob in landscape.objects if ob.name in {'Eastern headland','Eastern woodland'}],
        lambda p:(p.x,p.y-90,-1.225+(p.z+1.225)*.72))
for row,house_y in enumerate([0,13,26,39,52,65,78]):
    base_z=ground(house_y)
    reshape([ob for ob in group('02 • Victorian street').objects if ob.name.startswith(f'East house {row+1} /')],
            lambda p:(p.x,p.y,base_z+(p.z-base_z)*.78))
# A broad low-frequency swell bends the fine wave normals.
swell=n.new('ShaderNodeTexNoise');swell.inputs['Scale'].default_value=.075;swell.inputs['Detail'].default_value=2
l.new(geo.outputs['Position'],swell.inputs['Vector'])
wide_bump=n.new('ShaderNodeBump');wide_bump.inputs['Strength'].default_value=.6;wide_bump.inputs['Distance'].default_value=.65
l.new(swell.outputs['Fac'],wide_bump.inputs['Height']);l.new(bump.outputs['Normal'],wide_bump.inputs['Normal']);l.new(wide_bump.outputs['Normal'],s.inputs['Normal'])
# Camera and lighting are saved with the source scene.
scene=bpy.context.scene
bpy.ops.object.camera_add(location=(2,-28,38));cam=bpy.context.object;cam.name='Wallpaper comparison camera';cam.rotation_euler=(Vector((3,225,4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=35;cam.data.clip_end=4000;scene.camera=cam
ref=bpy.data.images.load(str(ROOT/'shell/Resources/Wallpapers/city-sunset.png'));ref.pack();cam.data.show_background_images=True;bg=cam.data.background_images.new();bg.image=ref;bg.alpha=.35;bg.display_depth='FRONT'
world=bpy.data.worlds.new('Peach sunset environment');scene.world=world;world.use_nodes=True;n=world.node_tree.nodes;l=world.node_tree.links
sky=n.new('ShaderNodeTexEnvironment');sky.image=bpy.data.images.load(str(ROOT/'shell/Resources/Worlds/wallpaper-city/materials/sunset-sky-v4.png'));sky.image.pack();l.new(sky.outputs['Color'],n.get('Background').inputs['Color']);n.get('Background').inputs['Strength'].default_value=.65
coords=n.new('ShaderNodeTexCoord');stretch=n.new('ShaderNodeVectorMath');stretch.operation='MULTIPLY';stretch.inputs[1].default_value=(1,1,4)
l.new(coords.outputs['Generated'],stretch.inputs[0]);l.new(stretch.outputs[0],sky.inputs['Vector'])
# A local atmospheric volume softens distant shapes without fogging the street.
haze=bpy.data.materials.new('Bay atmosphere • render study');haze.use_nodes=True;hn=haze.node_tree.nodes;hn.clear();out=hn.new('ShaderNodeOutputMaterial');vol=hn.new('ShaderNodeVolumePrincipled');vol.inputs['Density'].default_value=.0006;vol.inputs['Color'].default_value=(.64,.60,.67,1);vol.inputs['Anisotropy'].default_value=.25;haze.node_tree.links.new(vol.outputs['Volume'],out.inputs['Volume'])
box('Distant bay haze',(0,650,75),(1800,1050,150),haze,'09 • Render atmosphere')
bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=14,location=(650,1500,80));o=bpy.context.object;o.name='Sun disc';o.data.materials.append(material('Sun disc emission',(1,.57,.18),emission=1));move(o,'09 • Render atmosphere')
bpy.ops.object.light_add(type='SUN',location=(100,240,70));sun=bpy.context.object;sun.name='Low warm sunset';sun.rotation_euler=Vector((-650,-1500,-80)).to_track_quat('-Z','Y').to_euler();sun.data.energy=2.3;sun.data.color=(1,.66,.39);sun.data.angle=math.radians(1)
# Warm sky patch creates a broad reflected sunset in the bay, with actual
# light transport rather than painted highlights on the water surface.
bpy.ops.object.light_add(type='AREA',location=(130,1000,100));bounce=bpy.context.object;bounce.name='Sunset cloud bounce over bay';bounce.rotation_euler=(Vector((35,280,-1))-bounce.location).to_track_quat('-Z','Y').to_euler();bounce.data.energy=450000;bounce.data.shape='DISK';bounce.data.size=300;bounce.data.color=(1,.43,.18)
# Broad sky fill retains detail on the shaded facades.
bpy.ops.object.light_add(type='AREA',location=(0,-10,65));fill=bpy.context.object;fill.name='Warm facade bounce';fill.data.energy=30000;fill.data.shape='DISK';fill.data.size=75;fill.data.color=(1,.78,.54)
scene.render.engine='CYCLES';scene.cycles.samples=a.samples;scene.cycles.use_denoising=True;scene.cycles.denoiser='OPENIMAGEDENOISE';scene.cycles.max_bounces=6;scene.cycles.volume_bounces=0
scene.render.threads_mode='FIXED';scene.render.threads=8
scene.render.resolution_x=a.width;scene.render.resolution_y=round(a.width*941/1672);scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.55
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(a.out/'camera-study.png')
# Open directly into the reference camera, with meaningful collection names.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.clip_end=4000
notes=bpy.data.texts.new('START HERE');notes.write('Wallpaper city • Blender composition study\nNative meshes, metre scale, Z up. Compare through the named camera.\nCamera background holds the packed wallpaper as an overlay (not rendered).\nProcedural water and Blender lighting require baking/matching before runtime integration.\nThis is a first composition study, not a finished replacement world.\n')
scene.render.use_compositing=True
for layer in scene.view_layers: layer.cycles.use_denoising=True
bpy.ops.wm.save_as_mainfile(filepath=str(a.out/'wallpaper-city.blend'))
bpy.ops.render.render(write_still=True)
print('BLENDER_STUDY_COMPLETE',a.out,flush=True)
