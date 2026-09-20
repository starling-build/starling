"""Waterfront blocks and working quay details for the wallpaper study."""
import numpy as np


def district_block(props,x,z,width,height,tile,variant):
    def box(t,*bounds): props.append(('box',t,*bounds))
    y=-2.; back=z-7; roof=y+height
    box('stone',x-.15,-3,back-.1,x+width+.15,y+.45,z+.15)
    box(tile,x,y+.45,back,x+width,roof,z)
    box('limestone',x-.18,y+2.7,back-.1,x+width+.18,y+2.9,z+.22)
    for xx in np.arange(x+.4,x+width-.8,1.5):
        box('painted_wood',xx,y+.55,z+.02,xx+1.0,y+2.5,z+.1)
        box('interior_warm' if (int(xx)+variant)%3 else 'glass',
            xx+.09,y+.68,z+.12,xx+.91,y+2.38,z+.15)
        box('limestone',xx+.46,y+.6,z+.16,xx+.51,y+2.45,z+.2)
        for yy in np.arange(y+3.4,roof-1,2.6):
            box('limestone',xx-.07,yy-.08,z+.03,xx+1.07,yy+1.55,z+.13)
            box('glass' if variant%4==0 else 'interior_warm',xx+.05,yy,z+.15,xx+.95,yy+1.42,z+.18)
            box('bronze',xx+.48,yy,z+.19,xx+.52,yy+1.42,z+.23)
            box('limestone',xx-.14,yy-.2,z-.02,xx+1.14,yy-.06,z+.3)
    # A shallow striped shop canopy and a blank sign panel above the door.
    if variant%3!=0:
        for k,xx in enumerate(np.arange(x+.15,x+width-.1,.35)):
            box('plaster_cream' if k%2 else ('awning_green' if variant%2 else 'awning_red'),
                xx,y+2.5,z+.1,min(xx+.35,x+width),y+2.67,z+.8)
        box('painted_wood',x+width*.3,y+2.95,z+.04,x+width*.7,y+3.22,z+.1)
    for yy,overhang in ((roof,.15),(roof+.2,.3)):
        box('limestone',x-overhang,yy,back-overhang,x+width+overhang,yy+.17,z+overhang)
    box('roof',x+.15,roof+.37,back+.15,x+width-.15,roof+.47,z-.15)
    # Parapets and roof equipment distinguish the blocks from the hillside houses.
    for xx in (x+.05,x+width-.22):
        box('stone',xx,roof+.35,back+.05,xx+.17,roof+.8,z-.05)
    box('stone',x+.2,roof+.35,back+.05,x+width-.2,roof+.8,back+.22)
    box('brick',x+.7,roof+.4,back+1,x+1.3,roof+1.7,back+1.7)
    if variant%3==0:
        box('copper',x+width*.45,roof+.45,back+2,x+width*.8,roof+1.1,back+4)
    else:
        box('vent',x+width*.55,roof+.45,back+2,x+width*.75,roof+.9,back+3)


def quay(props):
    def box(t,*bounds): props.append(('box',t,*bounds))
    def beam(t,a,b,width): props.append(('beam',t,a,b,width))
    # Land beneath the district, with an open water channel in front of the
    # terminal. The west end connects to the terminal quay at walking height.
    box('stone',-75,-4,-134,10,-2,-81)
    box('sidewalk',-75,-2,-134,10,-1.9,-81)
    box('stone',10,-4,-113,77,-2,-81)
    box('sidewalk',10,-2,-113,77,-1.9,-81)
    for x in np.arange(10,77,1.5):
        box('limestone',x,-2.1,-113.2,x+1.45,-1.75,-112.9)
    # Continuous stone waterfront connects the long terminal to the piers.
    box('stone',7,-3,-138,77,-.8,-128)
    box('sidewalk',7,-.8,-138,77,-.58,-128)
    for x in np.arange(7,77,1.5):
        box('limestone',x,-.7,-128.25,x+1.45,-.42,-127.9)
        box('stone',x,-2.2,-128.05,x+1.43,-1.45,-127.99)
    # Open railing allows a view of water between the vertical posts.
    beam('bronze',(8,.45,-128),(76,.45,-128),.065)
    for x in np.arange(8,77,2):
        box('bronze',x-.035,-.55,-128.04,x+.035,.48,-127.96)
    for x in np.arange(10,77,7):
        props.append(('lamp',x,-.58,-131,2.6))
        box('bronze',x+1,-.6,-128.5,x+1.35,-.15,-128.15)
        box('bronze',x+.93,-.23,-128.56,x+1.42,-.12,-128.09)
    # Two wooden finger piers extend into the near channel, on actual piles.
    for x,length in ((48,17),(69,12)):
        for z in np.arange(-128,-128+length,.42):
            box('planks',x,-1,z,x+2.8,-.79,z+.39)
        for z in np.arange(-127,-128+length,2.7):
            for xx in (x+.1,x+2.7):
                box('log',xx-.12,-4,z-.12,xx+.12,-.45,z+.12)
                box('limestone',xx-.15,-.55,z-.15,xx+.15,-.38,z+.15)
    for x in np.arange(16,72,12):
        box('copper',x,5.35,-143,x+3.8,5.6,-140)
        box('glass',x+.2,5.6,-142.8,x+3.6,6.25,-140.2)
        box('copper',x+.1,6.25,-142.9,x+3.7,6.4,-140.1)
    # Side wings, loading canopy, and a small rooftop flag at the terminal.
    for x in (7,73):
        box('plaster_cream',x,-1,-145,x+3,4,-136)
        box('limestone',x-.2,4,-145.2,x+3.2,4.3,-135.8)
    for x in np.arange(10,74,2.4):
        box('bronze',x-.025,-.55,-134,x+.025,2.4,-133.95)
    box('copper',9.5,2.4,-137,74.5,2.55,-133.9)
    box('bridge_red',34.05,26.2,-135.02,35.5,27,-134.98)
