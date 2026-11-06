# Variants of zh-547fc43c's chart2 (page 6): Word puts its inner plot ~2.1 pt left of the file's x.
# Each variant changes one thing; compare the plot's left edge (file says x=0.0816*399.05 from the frame).
import zipfile,re,sys
src=sys.argv[1]
def mod(name,fn):
    zi=zipfile.ZipFile(src); zo=zipfile.ZipFile(f"docs/c2-{name}.docx","w",zipfile.ZIP_DEFLATED)
    for i in zi.infolist():
        d=zi.read(i.filename)
        if i.filename=="word/charts/chart2.xml": d=fn(d.decode()).encode()
        zo.writestr(i,d)
def secmin(s): return s.replace('<c:min val="-5"/>','<c:min val="0"/>')
def tickin(s): return s.replace('<c:majorTickMark val="out"/>','<c:majorTickMark val="in"/>').replace('<c:minorTickMark val="none"/>','<c:minorTickMark val="in"/>')
def notitlelay(s): return re.sub(r'(<c:title>.*?)<c:layout>.*?</c:layout>',r'\1<c:layout/>',s,count=1,flags=re.S)
def nolegendlay(s): return re.sub(r'(<c:legend>.*?)<c:layout>.*?</c:layout>',r'\1<c:layout/>',s,count=1,flags=re.S)
def nolayouts(s): return nolegendlay(notitlelay(s))
def secdel(s): return re.sub(r'<c:valAx><c:axId val="886426510"/>.*?</c:valAx>',lambda m: m.group(0).replace('<c:delete val="0"/>','<c:delete val="1"/>'),s,count=1,flags=re.S)
mod("base",lambda s:s)
for n,f in (("secmin0",secmin),("tickin",tickin),("notitlelay",notitlelay),("nolegendlay",nolegendlay),("nolayouts",nolayouts),("secdeleted",secdel)): mod(n,f)
