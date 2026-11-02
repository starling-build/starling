import sys,os,importlib.util
spec=importlib.util.spec_from_file_location('g','gen.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
out=sys.argv[1];os.makedirs(out,exist_ok=True)
for tw in (0,360,596,720,840,960):
    ind='<w:ind w:left="%d" w:firstLine="0"/>'%tw
    b=lambda: g.blank().replace('<w:ind w:left="0" w:firstLine="0"/>',ind)
    t=g.text("TEXTLINE").replace('w:lineRule="auto"/>','w:lineRule="auto"/>'+ind,1)
    g.pkg(os.path.join(out,'ft3-i%d.docx'%tw),g.tbl(335)+b()+b()+t)
    print(tw)
