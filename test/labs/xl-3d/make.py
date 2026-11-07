# Lab: Excel's angled (rAngAx=0) 3-D column box by chart width, series count, rotX, rotY.
# One workbook, one sheet per case, chart at D2; sheet name w<width>_s<series>_x<rotX>_y<rotY>. Chart height 320 px.
# Run: /tmp/a5-venv/bin/python make.py  (xlsxwriter has no 3-D charts: the chart parts are rewritten)
import xlsxwriter, zipfile, os, re
A=[2667.6,1768.41,3182.4,4013.1,9579.5,4836.0,1196.0,6087.9]
cases=[]
base=(480,2,15,20)
for w in (240,360,480,640): cases.append((w,2,15,20))
for s in (1,3,4): cases.append((480,s,15,20))
for x,y in ((0,0),(15,0),(15,40),(30,20),(30,40),(45,20),(15,60)): cases.append((480,2,x,y))
cases=list(dict.fromkeys(cases))
wb=xlsxwriter.Workbook('xl-3d.xlsx')
view={}
for (w,s,x,y) in cases:
    nm=f'w{w}_s{s}_x{x}_y{y}'
    ws=wb.add_worksheet(nm)
    ws.write_column('A1',[f'c{i+1}' for i in range(8)])
    for j in range(s): ws.write_column(0,1+j,[v*(1-0.18*j) for v in A])
    ch=wb.add_chart({'type':'column'})
    for j in range(s):
        col=chr(ord('B')+j)
        ch.add_series({'categories':f"='{nm}'!$A$1:$A$8",'values':f"='{nm}'!${col}$1:${col}$8"})
    ch.set_legend({'none':True}); ch.set_title({'none':True})
    ch.set_size({'width':w,'height':320})
    ws.insert_chart('D2',ch)
    view[nm]=(x,y)
wb.close()
tmp='xl-3d.tmp'
zi=zipfile.ZipFile('xl-3d.xlsx'); zo=zipfile.ZipFile(tmp,'w',zipfile.ZIP_DEFLATED)
names=[n for n in zi.namelist() if n.startswith('xl/charts/chart')]
order=list(view)   # chartN follows sheet order
for it in zi.infolist():
    d=zi.read(it.filename)
    if it.filename.startswith('xl/charts/chart'):
        i=int(re.search(r'chart(\d+)',it.filename).group(1))-1
        x,y=view[order[i]]
        s=d.decode().replace('<c:barChart>','<c:bar3DChart>').replace('</c:barChart>','</c:bar3DChart>')
        s=re.sub(r'<c:overlap[^>]*/>','',s)
        if '<c:gapWidth' not in s: s=s.replace('<c:axId val="','<c:gapWidth val="150"/><c:axId val="',1)
        s=s.replace('<c:plotArea>',f'<c:view3D><c:rotX val="{x}"/><c:rotY val="{y}"/><c:rAngAx val="0"/><c:perspective val="30"/></c:view3D><c:plotArea>',1)
        d=s.encode()
    zo.writestr(it,d)
zo.close(); os.replace(tmp,'xl-3d.xlsx')
print(len(cases),'sheets')
