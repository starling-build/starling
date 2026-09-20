"""Irregular island shoreline and inhabited distant hills for the reference city."""
import numpy as np


def island(props, tree, seed=47):
    rng=np.random.default_rng(seed)
    def box(tile,*bounds): props.append(('box',tile,*bounds))
    # A rounded land mass reaches below the sea instead of exposing a slab edge.
    props.append(('ellipsoid','hill',(-40,-1,-345),(55,7,18),14))
    for angle in np.linspace(0,2*np.pi,100,endpoint=False):
        x=-40+np.cos(angle)*rng.uniform(52,56)
        z=-345+np.sin(angle)*rng.uniform(16,19)
        props.append(('ellipsoid','hill',(x,-.6,z),
                      (rng.uniform(1.2,3),rng.uniform(.9,1.8),rng.uniform(1,2.2)),3))
    box('stone',-63,3.7,-350,-23,6,-334)
    for _ in range(65):
        x=rng.uniform(-91,10); z=rng.uniform(-359,-328)
        radial=((x+40)/55)**2+((z+345)/18)**2
        if radial>.86 or (-65<x<-21 and -352<z<-332): continue
        y=-1+7*np.sqrt(1-radial)
        tree(x,z,y,rng.uniform(.4,.8))
    # Low landing, lighthouse lantern, and a small jetty facing the viewer.
    box('limestone',-17,3,-342,-9,5,-335)
    box('limestone',-14,5,-340,-12,16,-338)
    for y in (7,10,13): box('glass',-13.2,y,-337.98,-12.8,y+1,-337.94)
    box('limestone',-14.4,15.8,-340.4,-11.6,16.2,-337.6)
    box('lamp',-13.6,16.2,-339.6,-12.4,17.2,-338.4)
    box('copper',-14,17.2,-340,-12,17.45,-338)
    for z in np.arange(-331,-321,.5):
        box('planks',-19,-.6,z,-16,-.4,z+.46)
    for z in (-329,-326,-323):
        for x in (-18.8,-16.2): box('log',x-.1,-4,z-.1,x+.1,-.1,z+.1)


def neighborhoods(props,height,seed=59):
    rng=np.random.default_rng(seed)
    def box(tile,*bounds): props.append(('box',tile,*bounds))
    # Scattered footprints follow the hill surface, avoiding the old straight
    # rows of identical dots. A coarse occupancy grid prevents major overlaps.
    occupied=set()
    for _ in range(4200):
        x=rng.uniform(-340,370); z=rng.uniform(-543,-428)
        y=height(x,z)
        if y<2 or (-5<x<195): continue
        cell=(int(np.floor(x/4)),int(np.floor(z/4)))
        if cell in occupied: continue
        if rng.random() < (.22 if x<0 else .6): continue
        occupied.add(cell)
        w=rng.uniform(1.8,3.7); depth=rng.uniform(2,3.7); h=rng.uniform(1.5,4.1)
        base=min(height(xx,zz) for xx,zz in ((x,z),(x+w,z),(x,z-depth),(x+w,z-depth)))-.2
        tile='hill_far' if rng.random()<.55 else 'hill'
        box(tile,x,base,z-depth,x+w,y+h,z)
        box('hill_far',x-.12,y+h,z-depth-.12,x+w+.12,y+h+.25,z+.12)
        for xx in np.arange(x+.3,x+w-.25,.85):
            for yy in np.arange(y+.4,y+h-.2,1.15):
                if rng.random()<.35: continue
                box('interior_warm',xx,yy,z+.025,xx+.30,yy+.48,z+.055)
        # Small darker groves interleave with buildings and break up the skyline.
        if rng.random()<.35:
            box('hill',x+w+.3,y,z-1,x+w+1.2,y+rng.uniform(1.5,3),z-.1)

    for _ in range(100):
        x=rng.uniform(-330,370); z=rng.uniform(-540,-430); y=height(x,z)
        if y<3 or (-5<x<195): continue
        props.append(('ellipsoid','leaves_dark',(x,y+1,z),
                      (rng.uniform(2,4),rng.uniform(1,2),rng.uniform(2,4)),2))
