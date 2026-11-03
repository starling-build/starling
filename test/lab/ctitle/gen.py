#!/usr/bin/env python3
"""Lab ctitle (for windows: Excel for Windows prints): where a column chart's plot starts under its title, and what
a legend at the top or right does to it. One chart per sheet (page), anchored at A1+7 rows, exact size 480 x 288 pt, one
series of four columns (10/40/25/30), a value axis, no gridline colour or text properties given (Excel's own look).
One thing varied at a time from the base: title 18 pt one line, no overlay, legend right.
gen.py OUT.xlsx -> a workbook of the sheets in combos(); print each sheet to PDF (one page a sheet, in order)."""
import sys, zipfile, importlib.util, os

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('doughnut_gen', os.path.join(HERE, '..', 'doughnut', 'gen.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
CNS = base.CNS


def combos():
    b = dict(title='Chart title', tsz=18, lines=1, overlay=0, legend='r', w=480, h=288, series=1)
    out = [('base', {}), ('notitle', dict(title=None))]
    for sz in (10, 14, 24, 32):
        out.append(('tsz%d' % sz, dict(tsz=sz)))
    out.append(('two-lines', dict(lines=2)))
    out.append(('two-lines-tsz10', dict(lines=2, tsz=10)))
    out.append(('overlay', dict(overlay=1)))
    out.append(('overlay-tsz24', dict(overlay=1, tsz=24)))
    for lg in (None, 't', 'b', 'l'):
        out.append(('legend-%s' % (lg or 'none'), dict(legend=lg)))
    out.append(('legend-t-notitle', dict(legend='t', title=None)))
    out.append(('legend-t-tsz24', dict(legend='t', tsz=24)))
    out.append(('legend-t-two-lines', dict(legend='t', lines=2)))
    out.append(('series2', dict(series=2)))
    for w, h in ((320, 200), (640, 384)):
        out.append(('size%dx%d' % (w, h), dict(w=w, h=h)))
    return [(n, {**b, **d}) for n, d in out]


def chart_xml(p, sheet):
    cats = ['Category 1', 'Category 2', 'Category 3', 'Category 4']
    vals = [[20, 1, 1, 12], [5, 8, 3, 9]]
    sers = ''
    for s in range(p['series']):
        col = 'BCD'[s]
        cat = '<c:cat><c:strRef><c:f>@@S@@!$A$2:$A$5</c:f><c:strCache><c:ptCount val="4"/>%s</c:strCache></c:strRef></c:cat>' % ''.join(
            '<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, v) for i, v in enumerate(cats))
        val = '<c:val><c:numRef><c:f>@@S@@!$%s$2:$%s$5</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="4"/>%s</c:numCache></c:numRef></c:val>' % (
            col, col, ''.join('<c:pt idx="%d"><c:v>%s</c:v></c:pt>' % (i, v) for i, v in enumerate(vals[s])))
        sers += ('<c:ser><c:idx val="%d"/><c:order val="%d"/><c:tx><c:strRef><c:f>@@S@@!$%s$1</c:f><c:strCache><c:ptCount val="1"/>'
                 '<c:pt idx="0"><c:v>Series %d</c:v></c:pt></c:strCache></c:strRef></c:tx>%s%s</c:ser>') % (s, s, col, s + 1, cat, val)
    title = ''
    if p['title']:
        paras = ''.join('<a:p><a:pPr><a:defRPr sz="%d" b="0"/></a:pPr><a:r><a:rPr lang="en-US" sz="%d" b="0"/><a:t>%s</a:t></a:r></a:p>' % (
            p['tsz'] * 100, p['tsz'] * 100, t) for t in ([p['title']] if p['lines'] == 1 else [p['title'], 'second line']))
        title = '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/>%s</c:rich></c:tx><c:overlay val="%d"/></c:title>' % (paras, p['overlay'])
    legend = '<c:legend><c:legendPos val="%s"/><c:overlay val="0"/></c:legend>' % p['legend'] if p['legend'] else ''
    xml = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:roundedCorners val="0"/><c:chart>%s'
           '<c:autoTitleDeleted val="%d"/><c:plotArea><c:layout/><c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>'
           '<c:varyColors val="0"/>%s<c:gapWidth val="150"/><c:axId val="111"/><c:axId val="222"/></c:barChart>'
           '<c:catAx><c:axId val="111"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>'
           '<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
           '<c:crossAx val="222"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
           '<c:valAx><c:axId val="222"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/>'
           '<c:majorGridlines/><c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
           '<c:crossAx val="111"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx></c:plotArea>%s<c:plotVisOnly val="1"/>'
           '<c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>') % (CNS, title, 0 if p['title'] else 1, sers, legend)
    return xml.replace('@@S@@', "'%s'" % sheet)


if __name__ == '__main__':
    # Reuse the doughnut lab's workbook writer with this lab's combos, chart and sheet data.
    base.combos = combos
    base.chart_xml = chart_xml
    src = open(os.path.join(HERE, '..', 'doughnut', 'gen.py')).read()
    base.main(sys.argv[1])
