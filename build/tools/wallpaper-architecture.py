"""Reference-view Victorian houses with modeled chamfered bays and street stoops.

Local U runs along the street facade, V points out toward the road, and Y is up.
The same details are mirrored onto either side of the street. Every surface is
real geometry, including recessed sash frames and the angled bay-window sides.
"""
import numpy as np


def victorian(v, x, z, width, height, tile, side, ground, variant=0, depth=7):
    out = {'pos': [], 'nrm': [], 'uv': [], 'count': 0}
    base = ground(z)
    facing = -side
    face_x = x + width if side < 0 else x
    # Mapping local (u,y,v) to (world x,y,z) is a reflection on the left.
    basis = np.array([[0, 0, facing], [0, 1, 0], [1, 0, 0]], dtype=float)
    mirrored = np.linalg.det(basis) < 0
    origin = np.array([face_x, base, z-depth])

    def append(local, angle=0, center=(0,0)):
        c,s = np.cos(angle),np.sin(angle)
        rotation = np.array([[c,0,-s],[0,1,0],[s,0,c]])
        transform = basis @ rotation
        translation = origin + basis @ np.array([center[0],0,center[1]])
        for p,n,uv in zip(local['pos'],local['nrm'],local['uv']):
            p = p @ transform.T + translation
            n = n @ transform.T
            if mirrored:
                p=p[[0,3,2,1]]; n=n[[0,3,2,1]]; uv=uv[[0,3,2,1]]
            out['pos'].append(p.astype(np.float32))
            out['nrm'].append(n.astype(np.float32)); out['uv'].append(uv)
        out['count'] += local['count']

    def block(t, u0, y0, v0, u1, y1, v1, angle=0, center=(0,0)):
        local = {'pos': [], 'nrm': [], 'uv': [], 'count': 0}
        v.box_quads(u0,y0,v0,u1,y1,v1,v.T[t],local)
        append(local,angle,center)

    def beam(t,a,b,width):
        local = {'pos': [], 'nrm': [], 'uv': [], 'count': 0}
        v.mesh_props([('beam',t,a,b,width)],(0,0),local)
        append(local)

    def pane(u,y,front,w=1.25,h=1.8,angle=0,lit=True):
        def b(t,a,yy,c,aa,yyy,cc):
            block(t,a,yy,c,aa,yyy,cc,angle,(u,front))
        # Dark reveal, recessed pane, side curtains, then slim projecting sash.
        b('painted_wood',-w/2-.09,y-.09,-.08,w/2+.09,y+h+.09,.045)
        b('interior_warm' if lit else 'glass',-w/2,y,0,w/2,y+h,.05)
        if lit:
            for sign in (-1,1):
                xx=sign*w*.38
                b('curtain',xx-w*.075,y+.02,.055,xx+w*.075,y+h-.02,.075)
        for xx in (-w/2-.045,w/2):
            b('limestone',xx,y-.06,.06,xx+.055,y+h+.06,.13)
        for yy in (y-.06,y+h*.48,y+h):
            b('limestone',-w/2-.06,yy,.065,w/2+.06,yy+.06,.135)
        b('bronze',-.025,y,.07,.025,y+h,.12)
        b('limestone',-w/2-.16,y-.21,-.04,w/2+.16,y-.09,.26)
        b('limestone',-w/2-.19,y+h+.08,-.06,w/2+.19,y+h+.23,.22)

    block('stone',-.15,-3,-width-.1,depth+.15,.85,.1)
    block(tile,0,.85,-width,depth,height,0)
    # Fine clapboard laps catch grazing sunset light on both visible elevations.
    for yy in np.arange(1.08,height-.3,.24):
        block(tile,0,yy,.003,depth,yy+.035,.035)
        block(tile,depth+.003,yy,-width,depth+.035,yy+.035,0)
    # Staggered masonry courses give the raised basement actual joints.
    for row,yy in enumerate(np.arange(-1.8,.8,.42)):
        for u in np.arange(-.1,depth,.82):
            start=max(-.14,u-(.41 if row%2 else 0))
            end=min(depth+.14,u+.78-(.41 if row%2 else 0))
            if end>start:
                block('stone',start,yy,.105,end,yy+.39,.145)
    for yy in np.arange(1,height,3):
        block('limestone',-.12,yy,-width-.1,depth+.12,yy+.16,.16)
    for u in (.05,depth-.22):
        block('limestone',u,.9,.015,u+.17,height-.25,.12)
    # Stacked three-sided projecting bay, with actual angled wall segments.
    bay_u=2.25 if variant%2==0 else 2.65
    block(tile,bay_u-.82,.9,0,bay_u+.82,height-.35,1.0)
    for sign in (-1,1):
        block(tile,-.46,.9,-.14,.46,height-.35,.14,
              -sign*np.pi/4,(bay_u+sign*1.09,.68))
    for floor,yy in enumerate(np.arange(1.45,height-1.3,3)):
        pane(bay_u,yy,1.025,1.35,1.95,lit=(floor+variant)%4!=3)
        for sign in (-1,1):
            pane(bay_u+sign*1.09,yy,.83,.58,1.95,-sign*np.pi/4,lit=True)
        block('limestone',bay_u-.97,yy+2.22,-.05,bay_u+.97,yy+2.4,1.25)
        for sign in (-1,1):
            block('limestone',-.55,yy+2.22,-.21,.55,yy+2.4,.21,
                  -sign*np.pi/4,(bay_u+sign*1.08,.68))
        # Small colored panels below each projecting bay.
        block('painted_wood',bay_u-.62,yy-.42,1.03,bay_u+.62,yy-.24,1.065)
    # Separate narrow upper windows over the entrance.
    door_u=5.5
    for floor,yy in enumerate(np.arange(4.45,height-1.3,3)):
        pane(door_u,yy,.035,.92,1.8,lit=(floor+variant)%3!=1)
    # Camera-facing end elevation, distinct from the road elevation.
    for k,front in enumerate((-width*.28,-width*.7)):
        # A second projecting bay faces uphill, where the reference camera
        # sees most of the nearest houses. Side panes complete its return walls.
        projection=.58 if k==0 else .10
        block(tile,-.88,.95,0,.88,height-.4,projection,
              -np.pi/2,(depth,front))
        for floor,yy in enumerate(np.arange(1.5,height-1.3,3)):
            pane(depth+projection+.025,yy,front,1.35,1.9,-np.pi/2,
                 lit=(k+floor+variant)%4!=3)
            block('limestone',-1.02,yy+2.14,-.02,1.02,yy+2.34,projection+.2,
                  -np.pi/2,(depth,front))
            if k==0:
                for sign in (-1,1):
                    pane(depth+.26,yy,front+sign*.89,.37,1.9,
                         0 if sign>0 else np.pi,lit=True)
    # Paneled door and transom, set above a real stair landing.
    block('limestone',door_u-.79,1.1,-.02,door_u+.79,3.95,.20)
    block('painted_wood',door_u-.65,1.2,.21,door_u+.65,3.6,.25)
    for xx in (door_u-.5,door_u+.08):
        for yy in (1.45,2.35):
            block('bronze',xx,yy,.26,xx+.42,yy+.64,.285)
            block('painted_wood',xx+.035,yy+.035,.29,xx+.385,yy+.605,.31)
    block('interior_warm',door_u-.58,3.66,.22,door_u+.58,3.88,.25)
    block('bronze',door_u+.45,2.23,.31,door_u+.51,2.32,.39)
    block('limestone',door_u-.88,3.99,-.05,door_u+.88,4.17,.38)
    door_z=z-depth+door_u
    low=ground(door_z)-base+.16
    steps=8
    for i in range(steps):
        top=low+(1.2-low)*(i+1)/steps
        front=2.8-i*.31
        block('limestone',door_u-.84,low-.15,front-.33,door_u+.84,top,front)
        for edge in (-.94,.94):
            block('bronze',door_u+edge-.025,top,front-.14,
                  door_u+edge+.025,top+.82,front-.09)
    for edge in (-.94,.94):
        beam('bronze',(door_u+edge,low+(1.2-low)/steps+.84,2.70),
             (door_u+edge,2.04,.53),.07)
    block('limestone',door_u-.85,1.03,-.04,door_u+.85,1.2,.47)
    # Cornice brackets and different roof silhouettes break the repeated boxes.
    for u in np.arange(.15,depth,.46):
        block('limestone',u,height-.38,.02,u+.16,height+.03,.36)
    for yy,overhang in ((height,.28),(height+.2,.42),(height+.4,.28)):
        block('limestone',-overhang,yy,-width-overhang,depth+overhang,yy+.17,overhang)
    if variant%3==0:
        for i in range(5):
            inset=i*.22
            block('copper',inset,height+.55+i*.20,-width+inset,
                  depth-inset,height+.75+i*.20,-inset)
        # Small front dormer.
        block(tile,bay_u-.64,height+.57,-.04,bay_u+.64,height+1.38,.22)
        pane(bay_u,height+.65,.24,.72,.62,lit=False)
    elif variant%3==1:
        block('roof',.2,height+.58,-width+.2,depth-.2,height+.68,-.2)
        for u in (.05,depth-.22):
            block('stone',u,height+.58,-width+.1,u+.17,height+1.05,-.1)
        for i in range(5):
            half=.9-i*.16
            block('limestone',bay_u-half,height+.58+i*.15,-.06,
                  bay_u+half,height+.73+i*.15,.26)
    else:
        block('copper',.2,height+.58,-width+.2,depth-.2,height+.8,-.2)
        for u in np.arange(.5,depth,.8):
            block('limestone',u,height+.58,.01,u+.22,height+.95,.25)
    chimney_u=1.1+variant%3
    block('brick',chimney_u,height+.7,-width+.8,chimney_u+.65,height+2.0,-width+1.5)
    block('stone',chimney_u-.08,height+1.9,-width+.72,chimney_u+.73,height+2.12,-width+1.58)
    # Small individual planters below the bay, with varied blossoms.
    for u in np.arange(bay_u-1.25,bay_u+1.3,.45):
        block('plaster_terra',u-.15,.9,1.25,u+.15,1.3,1.55)
        block('leaves',u-.19,1.25,1.2,u+.19,1.57,1.58)
        block('flower_rose' if variant%2 else 'flower_ochre',u-.05,1.56,1.34,u+.05,1.70,1.44)
    positions=np.concatenate(out['pos']); normals=np.concatenate(out['nrm'])
    uv=np.concatenate(out['uv']).astype(np.float32)
    base_indices=np.arange(out['count'],dtype=np.uint32)[:,None]*4
    indices=(base_indices+np.array([0,1,2,0,2,3],np.uint32)).reshape(-1)
    return positions,normals,uv,indices
