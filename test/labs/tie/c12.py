"""tie variant c, mode 12 only, recalibrated in a mode-12 doc, wide sweep.  usage: c12.py cal OUT | c12.py test OUT CAL.json"""
import sys, os, json
import gen
gen.D = [-8.2, -8.4, -8.5, -8.6, -8.63, -8.7, -8.8, -9.0, -9.5]
kind, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
if kind == 'cal':
    gen.pkg(os.path.join(out, 'c12-cal.docx'), 'c', 12, gen.para('c', 0, 'left'), True)
else:
    cal = json.load(open(sys.argv[3]))
    nat = cal['c-m12']
    body = ''
    rs = []
    for d in gen.D:
        w = nat - d
        r = round((gen.TEXTW - w) * 20)
        ach = nat - (gen.TEXTW - r / 20)
        rs.append((d, r, round(ach, 3)))
        body += gen.para('c', r, 'both')
    gen.pkg(os.path.join(out, 'c12-test3.docx'), 'c', 12, body, False)
    json.dump(rs, open(os.path.join(out, 'c12-test3.json'), 'w'))
print('ok')
