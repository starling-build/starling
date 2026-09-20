"""Navigation data shared by the wallpaper generator and walking preview."""
import math


def street_rows(ground):
    return [(-84+i*.65, float(ground(-84+i*.65))) for i in range(168)]


def description(ground, waterfront):
    surfaces = []
    # Match the generated road strips, including their overlapping .01 m edges.
    for z,y in street_rows(ground):
        surfaces += [[-40, 40, z, z+.66, y], [9, 11, z, z+.66, y+.16]]
    props = []
    waterfront.quay(props)
    for p in props:
        if p[0] == 'box' and p[1] in ('sidewalk', 'limestone', 'stone') and p[6] < 0:
            surfaces.append([p[2], p[5], p[4], p[7], p[6]])
    return dict(
        version=1,
        areas=[[-1,10.35,-2,4], [9.76,10.35,-82,8], [8,10.35,-84.5,-81],
               [8,9.25,-128.8,-83.5], [8,74,-132,-129], [8,9.25,-132,-128]],
        obstacles=[[9.3,z+2,.45] for z in (-5,-17,-29,-41,-53,-65,-77)]
                  + [[x,-131,.45] for x in range(10,77,7)],
        surfaces=surfaces,
        spawn=[0,1,0,5], eye_height=1.7)


class Navigation:
    def __init__(self, data): self.data = data

    def allowed(self, x, z):
        return (any(a<=x<=b and c<=z<=d for a,b,c,d in self.data['areas'])
                and all(math.hypot(x-a,z-b)>=r for a,b,r in self.data['obstacles'])
                and self.floor(x,z) is not None)

    def floor(self, x, z):
        return max((y for a,b,c,d,y in self.data['surfaces'] if a<=x<=b and c<=z<=d),default=None)

    def move(self, x, z, dx, dz):
        if not all(math.isfinite(v) for v in (x,z,dx,dz)): return x,z
        length=math.hypot(dx,dz)
        if length>1: dx/=length; dz/=length; length=1
        for _ in range(steps:=max(1,math.ceil(length/.04))):
            if self.allowed(x+dx/steps,z): x+=dx/steps
            if self.allowed(x,z+dz/steps): z+=dz/steps
        return x,z
