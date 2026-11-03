#!/usr/bin/env python3
"""Lab ctitle (for windows: Excel for Windows prints): where a column chart's plot starts under its title, and what
a legend at the top or right does to it. One chart per sheet (page), anchored at A1+7 rows, exact size 480 x 288 pt, one
series of four columns (10/40/25/30), a value axis, no gridline colour or text properties given (Excel's own look).
One thing varied at a time from the base: title 18 pt one line, no overlay, legend right.
gen.py OUT.xlsx -> a workbook of the sheets in combos(); print each sheet to PDF (one page a sheet, in order)."""
import sys, zipfile, importlib.util, os

HERE = os.path.dirname(os.path.abspath(__file__))
# The doughnut lab's workbook writer, widened from three series to five.
_src = open(os.path.join(HERE, '..', 'doughnut', 'gen.py')).read()
_src = _src.replace("'BCD'", "'BCDEF'").replace("vals = [[20, 1, 1, 12], [5, 8, 3, 9], [7, 2, 6, 4]]",
                                              "vals = [[20, 1, 1, 12], [5, 8, 3, 9], [7, 2, 6, 4], [3, 9, 5, 6], [11, 4, 8, 2]]")
base = type(sys)('doughnut_gen')
exec(compile(_src, 'doughnut/gen.py', 'exec'), base.__dict__)
CNS = base.CNS


def combos():
    b = dict(title='Chart title', tsz=18, lines=1, overlay=0, legend='r', w=480, h=288, series=1, lsz=None, kind='col')
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
    # round 2 (legend row pitch): the legend's own text size, its entry count, and a line chart's keys against a column's.
    for sz in (8, 10, 14, 18):
        out.append(('leg-sz%d-s2' % sz, dict(lsz=sz, series=2)))
        out.append(('leg-sz%d-s5' % sz, dict(lsz=sz, series=5)))
    out.append(('leg-s5-default', dict(series=5)))
    out.append(('leg-line-s2', dict(kind='line', series=2)))
    out.append(('leg-line-s5', dict(kind='line', series=5)))
    out.append(('leg-line-sz14-s5', dict(kind='line', series=5, lsz=14)))
    out.append(('leg-b-sz14-s5', dict(series=5, lsz=14, legend='b')))
    return [(n, {**b, **d}) for n, d in out]


def chart_xml(p, sheet):
    cats = ['Category 1', 'Category 2', 'Category 3', 'Category 4']
    vals = [[20, 1, 1, 12], [5, 8, 3, 9], [7, 2, 6, 4], [3, 9, 5, 6], [11, 4, 8, 2]]
    sers = ''
    for s in range(p['series']):
        col = 'BCDEF'[s]
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
    ltx = ('<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="%d"/></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr>' % (p['lsz'] * 100)) if p['lsz'] else ''
    legend = '<c:legend><c:legendPos val="%s"/><c:overlay val="0"/>%s</c:legend>' % (p['legend'], ltx) if p['legend'] else ''
    line = p['kind'] == 'line'
    plot = ('<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>%s<c:marker val="1"/><c:axId val="111"/><c:axId val="222"/></c:lineChart>' % sers) if line else (
        '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/><c:varyColors val="0"/>%s<c:gapWidth val="150"/><c:axId val="111"/><c:axId val="222"/></c:barChart>' % sers)
    xml = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:roundedCorners val="0"/><c:chart>%s'
           '<c:autoTitleDeleted val="%d"/><c:plotArea><c:layout/>%s'
           '<c:catAx><c:axId val="111"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/>'
           '<c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
           '<c:crossAx val="222"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>'
           '<c:valAx><c:axId val="222"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/>'
           '<c:majorGridlines/><c:numFmt formatCode="General" sourceLinked="0"/><c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
           '<c:crossAx val="111"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx></c:plotArea>%s<c:plotVisOnly val="1"/>'
           '<c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>') % (CNS, title, 0 if p['title'] else 1, plot, legend)
    return xml.replace('@@S@@', "'%s'" % sheet)


if __name__ == '__main__':
    # Reuse the doughnut lab's workbook writer with this lab's combos, chart and sheet data.
    base.combos = combos
    base.chart_xml = chart_xml
    src = open(os.path.join(HERE, '..', 'doughnut', 'gen.py')).read()
    base.main(sys.argv[1])
