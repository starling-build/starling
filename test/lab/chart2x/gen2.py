# Round 2: windows' print showed the plot stands 2.1 pt further left only while the second value axis is shown.
# Hypothesis: Word keeps room at the right for that axis's labels; where the file leaves less, it moves the plot left.
# Variants set the inner width so the room at the right (frame 399.05 pt) is 12..32 pt, x unchanged (0.0815687).
import zipfile,re,sys
src=sys.argv[1]; W=399.05; X=0.0815687257235935
def mod(name,fn):
    zi=zipfile.ZipFile(src); zo=zipfile.ZipFile(f"docs/c2-{name}.docx","w",zipfile.ZIP_DEFLATED)
    for i in zi.infolist():
        d=zi.read(i.filename)
        if i.filename=="word/charts/chart2.xml": d=fn(d.decode()).encode()
        zo.writestr(i,d)
def room(r): return lambda s: s.replace('<c:w val="0.865680992356847"/>','<c:w val="%.6f"/>'%((W-r)/W-X),1)
for r in (8,14,18,22,26,32): mod("room%d"%r,room(r))
mod("room26-wide",lambda s: room(26)(s).replace('<c:min val="-5"/>','<c:min val="-500"/>').replace('<c:max val="10"/>','<c:max val="1000"/>'))
