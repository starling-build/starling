#!/usr/bin/env python3
"""Lab legend (for windows: Excel for Windows prints + COM readback as ctitle's): a column chart with the legend at the
right, 1) its entry count (2/6/12/20 series) at two chart heights: when Excel starts dropping entries and which, and
2) the legend's x offset from the plot at three chart widths and three legend text sizes (3 series).
Title 'Chart title' 18 pt, no overlay, no gridline colour or text properties (Excel's own look), as ctitle's base.
gen.py OUT.xlsx -> a workbook of the sheets in combos(); print each sheet to PDF (one page a sheet, in order)."""
import sys, os, string
HERE = os.path.dirname(os.path.abspath(__file__))
COLS = (string.ascii_uppercase)[1:] + 'AA'          # B..Z, AA : 26 columns
import builtins; builtins.COLS = COLS
_src = open(os.path.join(HERE, '..', 'ctitle', 'gen.py')).read()
_src = _src.replace("'BCDEF'[s]", "COLS[s]").replace("'BCDEF'", "COLS")
_src = _src.replace("vals = [[20, 1, 1, 12], [5, 8, 3, 9], [7, 2, 6, 4], [3, 9, 5, 6], [11, 4, 8, 2]]",
                    "vals = [[(s * 7 + i * 5) % 19 + 1 for i in range(4)] for s in range(26)]")
mod = type(sys)('ctitle_gen')
mod.__dict__['__file__'] = os.path.join(HERE, '..', 'ctitle', 'gen.py')
mod.__dict__['COLS'] = COLS
exec(compile(_src.replace("if __name__ == '__main__':", "if False:"), 'ctitle/gen.py', 'exec'), mod.__dict__)


def combos():
    b = dict(title='Chart title', tsz=18, lines=1, overlay=0, legend='r', w=480, h=288, series=3, lsz=None, kind='col')
    out = []
    for h in (200, 384):
        for n in (2, 6, 12, 20):
            out.append(('n%d-h%d' % (n, h), dict(series=n, h=h)))
    for w in (320, 480, 640):
        for lsz in (None, 8, 14):
            out.append(('x-w%d-sz%s' % (w, lsz or 'def'), dict(w=w, lsz=lsz)))
    return [(n, {**b, **d}) for n, d in out]


if __name__ == '__main__':
    mod.base.combos = combos
    mod.base.chart_xml = mod.chart_xml
    mod.base.main(sys.argv[1])
