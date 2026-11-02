import sys; sys.path.insert(0,'.')
from meas import lines
A=[t for _,t in lines('run/hyB-z0-orig.pdf')]
for z in ('z360','z720','z1440'):
    print(z, A==[t for _,t in lines('run/hyB-%s-orig.pdf'%z)])
print('j0==j720',[t for _,t in lines('run/hyB-j0-orig.pdf')]==[t for _,t in lines('run/hyB-j720-orig.pdf')])
print('--caps1');[print(' ',t) for _,t in lines('run/hyD-caps1-orig.pdf')[:12]]
print('--caps0');[print(' ',t) for _,t in lines('run/hyD-caps0-orig.pdf')[:12]]
print('--leftz0');[print(' ',t) for _,t in lines('run/hyB-z0-orig.pdf')[:8]]
