# Lab: Excel's major unit and plot height by chart height, 2-D/3-D, column/line. Run: /tmp/a5-venv/bin/python make.py
import xlsxwriter
A=[2667.6,1768.41,3182.4,4013.1,9579.5,4836.0,1196.0,6087.9]
B=[v*47.3/9579.5 for v in A]
H=[120,180,240,320,420]   # chart height in px (width 480)
kinds={'col2':('column',None),'line2':('line',None),'col3':('column','3d'),'line3':('line','3d')}
for name,(t,sub) in kinds.items():
    wb=xlsxwriter.Workbook(f'xlunit-{name}.xlsx')
    for dn,data in (('A',A),('B',B)):
        for h in H:
            ws=wb.add_worksheet(f'{dn}{h}')
            ws.write_column('A1',[f'c{i+1}' for i in range(8)])
            ws.write_column('B1',data)
            ch=wb.add_chart({'type':t,'subtype':sub} if sub else {'type':t})
            ch.add_series({'categories':f"='{dn}{h}'!$A$1:$A$8",'values':f"='{dn}{h}'!$B$1:$B$8"})
            ch.set_legend({'none':True}); ch.set_title({'none':True})
            ch.set_size({'width':480,'height':h})
            if sub: ch.set_x_axis({}) 
            ws.insert_chart('D2',ch)
    wb.close()

# xlsxwriter has no 3-D charts: rewrite the two "3d" workbooks' chart parts into real c:bar3DChart / c:line3DChart.
import zipfile, re, shutil, os
for name in ('col3','line3'):
    src=f'xlunit-{name}.xlsx'; tmp=src+'.tmp'
    zi=zipfile.ZipFile(src); zo=zipfile.ZipFile(tmp,'w',zipfile.ZIP_DEFLATED)
    for it in zi.infolist():
        d=zi.read(it.filename)
        if it.filename.startswith('xl/charts/chart'):
            s=d.decode()
            s=s.replace('<c:grouping val="3d"/>','<c:grouping val="standard"/>')
            if name=='col3':
                s=s.replace('<c:barChart>','<c:bar3DChart>').replace('</c:barChart>','</c:bar3DChart>')
                s=re.sub(r'<c:overlap[^>]*/>','',s)
                s=s.replace('<c:axId val="','<c:gapWidth val="150"/><c:axId val="',1) if '<c:gapWidth' not in s else s
            else:
                s=s.replace('<c:lineChart>','<c:line3DChart>').replace('</c:lineChart>','</c:line3DChart>')
                s=re.sub(r'<c:marker val="1"/>','',s)
            s=s.replace('<c:plotArea>','<c:view3D><c:rotX val="15"/><c:rotY val="20"/><c:rAngAx val="0"/></c:view3D><c:plotArea>',1)
            d=s.encode()
        zo.writestr(it,d)
    zo.close(); os.replace(tmp,src)
