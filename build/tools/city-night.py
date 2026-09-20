"""Wallpaper-inspired waterfront composition, authored as real geometry.

Coordinates are metres, looking north (-Z) from the level interaction terrace.
The street descends beyond the app rail; no wallpaper is projected onto meshes.
"""
import numpy as np


def ground(z):
    return max(-2.2, 5.0 + min(0.0, z + 8.0) * .19)


def house_x(side, row, column, z):
    """Keep the east panorama clear through the adjacent display's lens."""
    distance = 14+column*8.0+row*1.4
    if side > 0:
        distance = max(distance, (13-z)*1.32+8+column*8)
    return side*distance


def build(v, size, seed):
    rng = np.random.default_rng(seed)
    props = []
    c = size // 2
    def box(tile, x, y, z, xx, yy, zz):
        v.detail_box(props, tile, x + c, y, z + c, xx + c, yy, zz + c)
    def beam(tile, a, b, width):
        props.append(("beam", tile, (a[0]+c, a[1], a[2]+c),
                      (b[0]+c, b[1], b[2]+c), width))
    def lamp(x, z, y=None):
        y = ground(z) if y is None else y
        props.append(("lamp", x+c, y, z+c, 3))
        # Small warm stone landing beneath each lantern.
        box("limestone", x-.65, y, z-.65, x+.65, y+.04, z+.65)
    def tree(x, z, y, scale=1):
        def crown(tile,dx,dy,dz,rx,ry,rz,segments=4):
            props.append(("ellipsoid",tile,(x+c+dx*scale,y+dy*scale,z+c+dz*scale),
                          (rx*scale,ry*scale,rz*scale),segments))
        crown("log",0,1.65,0,.16,1.7,.16)
        for dx,dz in ((-.65,.12),(.55,-.3),(.25,.55)):
            beam("log",(x,y+1.6*scale,z),
                 (x+dx*scale,y+3.1*scale,z+dz*scale),.12*scale)
        # A dark core and small overlapping leaf clusters. A golden-angle
        # distribution breaks up the outline without rows of identical balls.
        crown("leaves_dark",0,3.85,0,1.05,1.35,.95)
        phase = x*.73+z*.31
        for k in range(36):
            height = 1-2*(k+.5)/36
            angle = k*2.399963+phase
            ring = np.sqrt(1-height*height)
            dx,dz = 1.15*ring*np.cos(angle),ring*np.sin(angle)
            dy = 3.9+1.4*height
            radius = .38+.12*(.5+.5*np.sin(k*3.7+phase))
            tile = ("leaves","leaves_light","leaves_dark")[k%3]
            crown(tile,dx,dy,dz,radius,radius*.85,radius,3)

    # Level central terrace preserves the existing app ring and walking origin.
    # Fine terracing beyond it forms the downhill street visible in the image.
    for z in np.arange(-45, size/2, .5):
        y = ground(z)
        box("asphalt", -size/2, y-.6, z, size, y, z+.5)
        for x in (-size/2, 9):
            xx = -9 if x < 0 else size
            box("sidewalk", x, y, z, xx, y+.13, z+.5)
        for x in (-9.2, 9):
            box("limestone", x, y+.05, z, x+.2, y+.23, z+.5)
    # Rail and modest overlook furniture remain clear of the app panes.
    for x in np.arange(-8, 8, .25):
        beam("bronze", (x,6.05,-4+.04*x*x),
             (x+.25,6.05,-4+.04*(x+.25)**2), .16)
    for x in (-8,-4,0,4,8):
        z = -4+.04*x*x
        box("limestone", x-.13,5,z-.13,x+.13,5.98,z+.13)
    # Broad, staggered paving joints give the foreground a human scale.
    # A thin stone cap covers the road only on the level overlook. The street
    # beyond the rail remains asphalt; walking heights and app anchors stay put.
    box("plaza",-8.8,4.99,-8,9,5.001,17)
    for iz,z in enumerate(np.arange(-8,17,1.2)):
        for x in np.arange(-8.8,9,1.8):
            xx = x + (iz%2)*.9
            box("paving_border",xx,5.002,z,min(xx+1.72,9.5),5.006,z+.018)
            box("paving_border",xx,5.002,z,xx+.018,5.006,z+1.12)

    # A low, open eastern overlook rather than a wall of nearby houses.
    # It belongs to the same terrain and camera as the main app terrace.
    for x in np.arange(10,39,1.8):
        box("paving_border",x,5.135,-7,x+.035,5.145,7)
    beam("bronze",(10,6.05,-8),(40,6.05,-8),.10)
    for x in range(10,41,5):
        box("limestone",x-.10,ground(-8),-8.1,x+.10,6,-7.9)
    for x in (18,32):
        for z in (3,3.25,3.5):
            box("planks",x-1.5,5.65,z,x+1.5,5.77,z+.18)
        for dx in (-1.2,1.2):
            box("bronze",x+dx,5.13,3,x+dx+.10,5.65,3.7)
        box("planks",x-1.5,5.95,3.65,x+1.5,6.25,3.8)

    # Architectural houses are smaller, more detailed units than the old grid.
    # Their fronts face the viewer, with bay windows on the street-facing side.
    palette = ("plaster_sage", "plaster_rose", "plaster_cream", "plaster_blue", "plaster_terra")
    for side in (-1, 1):
        for row, z in enumerate((2, -10, -22, -34)):
            for column in range(3):
                x = house_x(side,row,column,z)
                y = ground(z)+.15
                h = (10.4, 11.5, 10.0)[(row+column)%3]
                wall = palette[(row+column+(side==1))%len(palette)]
                box("stone", x-3.3,y-.4,z-3.8,x+3.3,y+.6,z+3.8)
                box(wall,x-3,y+.6,z-3.4,x+3,y+h,z+3.4)
                for yy in (y+.6,y+3.5,y+6.6,y+h):
                    box("limestone",x-3.15,yy,z-3.55,x+3.15,yy+.19,z+3.55)
                box("roof",x-2.9,y+h+.19,z-3.3,x+2.9,y+h+.45,z+3.3)
                # Layered cornice, dentils, parapet and chimney silhouettes.
                for dh,over in ((.20,.16),(.34,.27),(.50,.38)):
                    box("limestone",x-3-over,y+h+dh,z-3.4-over,
                        x+3+over,y+h+dh+.12,z+3.4+over)
                for dz in (-3.25,3.05):
                    box(wall,x-2.9,y+h+.62,z+dz,x+2.9,y+h+1,z+dz+.2)
                box("brick",x+1.5,y+h+.5,z-1.8,x+2.25,y+h+2,z-1)
                box("limestone",x+1.4,y+h+1.9,z-1.9,x+2.35,y+h+2.1,z-.9)
                for dz in np.arange(-3.1,3.2,.55):
                    for xx in (x-3.22,x+3.08):
                        box("limestone",xx,y+h-.16,z+dz,xx+.14,y+h+.2,z+dz+.18)
                for xx in (x-3,x+2.8):
                    box("limestone",xx,y+.6,z+3.4,xx+.2,y+h,z+3.6)
                # Deep projecting bay, three glazed faces, slender trim and mullions.
                bx = x-side*.95
                for floor in range(3):
                    yy = y+1+floor*3.05
                    box(wall,bx-1.15,yy,z+3.35,bx+1.15,yy+2.8,z+4.05)
                    tile = "lamp" if rng.random()<.70 else "glass"
                    box(tile,bx-.93,yy+.25,z+4.06,bx+.93,yy+2.35,z+4.08)
                    for xx in (bx-1.16,bx+1.14):
                        box(tile,xx,yy+.25,z+3.5,xx+.02,yy+2.35,z+3.96)
                    for xx in (bx-1.08,bx-.035,bx+1.01):
                        box("limestone",xx,yy+.12,z+4.09,xx+.07,yy+2.5,z+4.16)
                    for hh in (0,2.5):
                        box("limestone",bx-1.25,yy+hh,z+3.3,bx+1.25,yy+hh+.16,z+4.2)
                    # Windows on both side elevations make walking views complete.
                    for xx in (x-3.02,x+3):
                        for zz in (z-2,z+.2):
                            box("window_lit" if rng.random()<.55 else "window",
                                xx,yy+.3,zz,xx+.02,yy+2.3,zz+1.3)
                # The inward elevations dominate the home camera: articulate
                # those too, with deep two-storey bays and real window frames.
                face = x-side*3
                def sidebox(tile,depth0,ya,za,depth1,yb,zb):
                    a,b = sorted((face-side*depth0,face-side*depth1))
                    box(tile,a,ya,za,b,yb,zb)
                for floor in range(3):
                    yy = y+.9+floor*3.05
                    sidebox(wall,0,yy,z-.9,.72,yy+2.8,z+1.5)
                    for zz in (z-.7,z+.45):
                        sidebox("lamp" if rng.random()<.65 else "glass",
                                .725,yy+.35,zz,.74,yy+2.35,zz+.92)
                    for zz in (z-.87,z+.30,z+1.40):
                        sidebox("limestone",.74,yy+.15,zz,.83,yy+2.5,zz+.09)
                    for dh in (.08,2.5):
                        sidebox("limestone",-.05,yy+dh,z-1.05,.95,yy+dh+.16,z+1.65)
                    # Fine horizontal transoms and a planted window box.
                    sidebox("limestone",.75,yy+1.7,z-.8,.80,yy+1.77,z+1.45)
                    if floor == 0:
                        sidebox("bronze",.8,yy-.12,z-.85,1.12,yy+.13,z+1.45)
                        sidebox("leaves",.8,yy+.13,z-.8,1.10,yy+.34,z+1.4)
                sidebox("copper",-.1,y+10,z-1.1,1,y+10.28,z+1.7)
                # Window reveals read as depth from the home viewpoint:
                # dark inner jambs behind projecting pale stone surrounds.
                for floor in range(3):
                    yy = y+.9+floor*3.05
                    for zz in (z-.7,z+.45):
                        for jamb in (zz-.045,zz+.92):
                            sidebox("bronze",.74,yy+.29,jamb,.79,yy+2.4,jamb+.045)
                        sidebox("limestone",.74,yy+.22,zz-.10,.93,yy+.32,zz+1.02)
                        sidebox("limestone",.74,yy+2.38,zz-.10,.90,yy+2.49,zz+1.02)
                box("copper",bx-1.3,y+h+.2,z+3.2,bx+1.3,y+h+.55,z+4.3)
                dx = x+side*1.8
                box("door_bottom",dx-.45,y+.6,z+3.41,dx+.45,y+1.65,z+3.45)
                box("door_top",dx-.45,y+1.65,z+3.41,dx+.45,y+2.7,z+3.45)
                for step in range(3):
                    box("stone",dx-.7,y+step*.2,z+3.45,dx+.7,y+(step+1)*.2,z+4.5-step*.3)
            # Leave the east outlook's distant sightline open as well.
            edge = side*10.3 if side < 0 else house_x(side,row,0,z)-4
            tree(edge,z-2,ground(z-2)+.13,.8)
            lamp(side*8.3 if side < 0 else edge-1.5,z)
            # Iron garden railings and stone planters break up the street edge.
            py = ground(z-2)+.13
            px = edge
            box("stone",px-.65,py,z-3,px+.65,py+.45,z-1)
            box("leaves",px-.52,py+.45,z-2.9,px+.52,py+.75,z-1.1)
            for zz in np.arange(z-4,z+3,.45):
                box("bronze",px-.035,py,zz,px+.035,py+1.05,zz+.045)
            beam("bronze",(px,py+1.05,z-4),(px,py+1.05,z+3),.055)

    # Long Ferry Building, arcade and stepped clock tower at the waterfront.
    tx,tz,y = 10,-49,-2.2
    box("stone",-36,y-.5,-55,40,y,-44.8)
    # Shorter terminal wings leave open water on both sides of the tower.
    box("limestone",2,y,-53,24,y+5,-47)
    box("copper",1.6,y+5,-53.4,24.4,y+5.4,-46.6)
    for x in np.arange(3,23,2.8):
        box("dark",x,y+.15,-46.98,x+1.65,y+2.75,-46.92)
        box("lamp",x+.22,y+.5,-46.9,x+1.43,y+2.2,-46.88)
        box("limestone",x-.18,y,-46.85,x+.1,y+4.8,-46.5)
        box("window_lit",x,y+3.15,-46.98,x+1.65,y+4.5,-46.94)
        # Stone voussoirs turn square glowing slots into a waterfront arcade.
        for a in np.linspace(0,np.pi,11)[:-1]:
            b = a+np.pi/10
            beam("limestone",(x+.825+.88*np.cos(a),y+1.95+.88*np.sin(a),-46.64),
                 (x+.825+.88*np.cos(b),y+1.95+.88*np.sin(b),-46.64),.23)
        for xx in (x-.13,x+1.64):
            box("limestone",xx,y,-46.75,xx+.16,y+2,-46.5)
        box("bronze",x+.79,y+.5,-46.85,x+.85,y+2.2,-46.82)
    box("sandstone",tx-1.5,y,tz-1.5,tx+1.5,14.5,tz+1.5)
    for yy,half in ((5,1.7),(9.5,1.7),(13,1.8),(14.5,1.9)):
        box("limestone",tx-half,yy,tz-half,tx+half,yy+.24,tz+half)
    for xx in (tx-1.48,tx+1.3):
        box("limestone",xx,y,tz+1.51,xx+.18,10,tz+1.7)
    for yy in (6,8):
        box("lamp",tx-.35,yy,tz+1.51,tx+.35,yy+1,tz+1.53)
    for step in range(4):
        r = 1.65-step*.32
        box("copper",tx-r,14.74+step*.6,tz-r,tx+r,15.34+step*.6,tz+r)
    beam("bronze",(tx,17,tz),(tx,20,tz),.07)
    box("bridge_red",tx,19,tz,tx+1.3,19.6,tz+.04)
    for x in range(-30,39,7):
        lamp(x,-45,-2.2)

    # Bay: broad dark water with sparse directional glints, not a tiled carpet.
    box("water",-600,-3.0,-600,600,-2.45,-55)
    for _ in range(400):
        x,z = rng.uniform(-140,140),rng.uniform(-200,-56)
        box("water_glint",x,-2.44,z,x+rng.uniform(.4,2.8),-2.435,z+.07)
    # Broken reflection trails: sparse, low-luminance geometry on the water.
    # Their foreshortening changes correctly as the viewer walks.
    for center in (-33,10,43):
        for _ in range(70):
            z = rng.uniform(-130,-56)
            x = center+rng.normal(0,1.0+(z+130)*.015)
            box("reflection_amber",x,-2.433,z,x+rng.uniform(.15,1.2),-2.431,z+.055)
    # Bridge portal towers, catenary-like cables and tiny navigation lights.
    bz,deck = -136,3
    box("asphalt",-72,deck,bz-2,82,deck+.4,bz+2)
    for x in (-33,43):
        for z in (bz-2.4,bz+1.7):
            box("bridge_red",x-.65,-2.5,z,x+.65,31,z+.7)
        for yy in (7,15,23,30):
            box("bridge_red",x-.65,yy,bz-2.4,x+.65,yy+.7,bz+2.4)
        box("lamp",x-.12,31,bz+2,x+.12,31.2,bz+2.2)
    def cable(x):
        return 12+18*((x-5)/38)**2 if -33<=x<=43 else 30-(abs(x-5)-38)*.5
    for x in np.arange(-71,81,1):
        for z in (bz-2.2,bz+2.2):
            beam("bridge_red",(x,cable(x),z),(x+1,cable(x+1),z),.13)
            if int(x)%3==0:
                beam("bridge_red",(x,deck+.4,z),(x,cable(x),z),.055)
                box("lamp",x-.07,deck+.55,z-.07,x+.07,deck+.69,z+.07)
    # Layered headlands and scattered hillside windows beyond the bridge.
    for layer,z in enumerate((-182,-222)):
        for x in range(-540,541,3):
            h = 4+15*(.5+.5*np.sin(x*.024+layer*1.6))+1.2*np.sin(x*.11)
            box("hill_far" if layer else "hill",x,-3,z,x+3,h,z+18)
            for _ in range(int(rng.integers(1,4))):
                yy = rng.uniform(1,max(2,h-1))
                xx = x+rng.uniform(.2,2.7)
                box("reflection_amber",xx,yy,z+18.01,xx+.20,yy+.16,z+18.03)
    # Trolley rails descend along the street, away from the foreground app rail.
    for z in np.arange(-40,-9,.5):
        for x in (-4.6,-3.4):
            beam("bronze",(x,ground(z)+.04,z),(x,ground(z+.5)+.04,z+.5),.055)
    return np.zeros((size,1,size),np.uint8), props
