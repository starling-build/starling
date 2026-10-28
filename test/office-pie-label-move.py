#!/usr/bin/env python3
"""Word's manual label move starts from the frame-constrained flat-pie default.

Four self-contained charts pair a zero move with a 14.25pt move at two slice
angles. Word prints moves of 14.40/14.16pt (its PDF quantization); the old
renderer loses part of the first move by constraining only afterwards.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

NS='http://schemas.openxmlformats.org/'
def fixture(path):
 def chart(share,move):
  return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<c:chartSpace xmlns:c="{NS}drawingml/2006/chart" xmlns:a="{NS}drawingml/2006/main">
<c:lang val="en-US"/>
<c:chart>
<c:plotArea>
<c:layout>
<c:manualLayout>
<c:layoutTarget val="inner"/>
<c:xMode val="edge"/>
<c:yMode val="edge"/>
<c:x val="0.0595238095238095"/>
<c:y val="0.092257217847769"/>
<c:w val="0.628204571019532"/>
<c:h val="0.907742782152231"/>
</c:manualLayout>
</c:layout>
<c:pieChart>
<c:varyColors val="1"/>
<c:ser>
<c:idx val="0"/>
<c:order val="0"/>
<c:cat>
<c:strLit>
<c:ptCount val="2"/>
<c:pt idx="0">
<c:v>Small</c:v>
</c:pt>
<c:pt idx="1">
<c:v>Large</c:v>
</c:pt>
</c:strLit>
</c:cat>
<c:val>
<c:numLit>
<c:formatCode>General</c:formatCode>
<c:ptCount val="2"/>
<c:pt idx="0">
<c:v>{share}</c:v>
</c:pt>
<c:pt idx="1">
<c:v>{1000-share}</c:v>
</c:pt>
</c:numLit>
</c:val>
<c:dLbls>
<c:dLbl>
<c:idx val="0"/>
<c:layout>
<c:manualLayout>
<c:x val="0"/>
<c:y val="{move}"/>
</c:manualLayout>
</c:layout>
<c:tx>
<c:rich>
<a:bodyPr/>
<a:lstStyle/>
<a:p>
<a:r>
<a:rPr lang="en-US"/>
<a:t>10964, 15.8%</a:t>
</a:r>
</a:p>
</c:rich>
</c:tx>
<c:dLblPos val="bestFit"/>
<c:showVal val="1"/>
<c:showPercent val="1"/>
</c:dLbl>
<c:dLbl>
<c:idx val="1"/>
<c:tx>
<c:rich>
<a:bodyPr/>
<a:lstStyle/>
<a:p>
<a:r>
<a:rPr lang="en-US"/>
<a:t>58205, 84.2%</a:t>
</a:r>
</a:p>
</c:rich>
</c:tx>
<c:dLblPos val="bestFit"/>
<c:showVal val="1"/>
<c:showPercent val="1"/>
</c:dLbl>
<c:txPr>
<a:bodyPr lIns="38100" rIns="38100" tIns="19050" bIns="19050" anchor="ctr"/>
<a:lstStyle/>
<a:p>
<a:pPr>
<a:defRPr sz="1000">
<a:latin typeface="Arial"/>
</a:defRPr>
</a:pPr>
</a:p>
</c:txPr>
<c:dLblPos val="bestFit"/>
<c:showPercent val="1"/>
<c:showLeaderLines val="1"/>
</c:dLbls>
</c:ser>
<c:firstSliceAng val="0"/>
</c:pieChart>
</c:plotArea>
<c:plotVisOnly val="1"/>
</c:chart>
<c:txPr>
<a:bodyPr/>
<a:lstStyle/>
<a:p>
<a:pPr>
<a:defRPr sz="1000">
<a:latin typeface="Arial"/>
</a:defRPr>
</a:pPr>
</a:p>
</c:txPr>
</c:chartSpace>'''
 parts={'_rels/.rels':f'<Relationships xmlns="{NS}package/2006/relationships"><Relationship Id="rId1" Type="{NS}officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'}
 body=[];rels=[];overrides=[]
 for i,(share,move) in enumerate([(158.5,0),(158.5,.116421568627451),(350,0),(350,.116421568627451)],1):
  parts[f'word/charts/chart{i}.xml']=chart(share,move)
  rels.append(f'<Relationship Id="rId{i}" Type="{NS}officeDocument/2006/relationships/chart" Target="charts/chart{i}.xml"/>')
  overrides.append(f'<Override PartName="/word/charts/chart{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>')
  body.append(f'''<w:p><w:pPr>{'<w:pageBreakBefore/>' if i>1 else ''}<w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:drawing><wp:inline><wp:extent cx="2598420" cy="1554480"/><wp:docPr id="{i}" name="Chart {i}"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="{NS}drawingml/2006/chart"><c:chart r:id="rId{i}"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>''')
 parts['word/document.xml']=f'''<w:document xmlns:w="{NS}wordprocessingml/2006/main" xmlns:r="{NS}officeDocument/2006/relationships" xmlns:wp="{NS}drawingml/2006/wordprocessingDrawing" xmlns:a="{NS}drawingml/2006/main" xmlns:c="{NS}drawingml/2006/chart"><w:body>{''.join(body)}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr></w:body></w:document>'''
 parts['word/_rels/document.xml.rels']=f'<Relationships xmlns="{NS}package/2006/relationships">'+''.join(rels)+'</Relationships>'
 parts['[Content_Types].xml']=f'<Types xmlns="{NS}package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'+''.join(overrides)+'</Types>'
 with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:
  for n,s in parts.items():z.writestr(n,s)

def check(path):
    import pymupdf
    with pymupdf.open(path) as pdf:
        assert len(pdf) == 4, f"expected four chart pages, got {len(pdf)}"
        pages = []
        for page in pdf:
            spans = [span for block in page.get_text('dict')['blocks']
                     for line in block.get('lines', []) for span in line['spans']]
            labels = {}
            for text in ['10964,', '15.8%', '58205,', '84.2%']:
                found = [span for span in spans if span['text'].strip() == text]
                assert len(found) == 1, f"expected one {text!r}, got {len(found)}"
                labels[text] = found[0]['bbox']
            pages.append(labels)
        for first in [0, 2]:
            for text in ['10964,', '15.8%']:
                before, after = pages[first][text], pages[first + 1][text]
                dx, dy = after[0] - before[0], after[1] - before[1]
                assert abs(dx) < 0.25 and abs(dy - 14.25) < 0.25, (
                    f"page pair {first+1}/{first+2}: {text} moved ({dx:.3f}, {dy:.3f}), "
                    "expected (0, 14.25) within Word's 0.25pt print quantization")
            for text in ['58205,', '84.2%']:
                assert all(abs(a-b) < 0.01 for a,b in zip(pages[first][text], pages[first+1][text])), (
                    f"unmoved label {text} changed in pair {first+1}/{first+2}")
    print('  ✔ flat-pie label moves: four Word frame-boundary controls pass')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--fixture', type=Path)
    group.add_argument('--pdf', type=Path)
    group.add_argument('--binary', type=Path)
    args = parser.parse_args()
    if args.fixture:
        fixture(args.fixture)
    elif args.pdf:
        check(args.pdf)
    else:
        with tempfile.TemporaryDirectory(prefix='office-pie-move-') as directory:
            doc = Path(directory) / 'pie-move.docx'
            fixture(doc)
            for mode in ['windows', 'mac']:
                pdf = Path(directory) / (mode + '.pdf')
                env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': mode}
                subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)],
                               env=env, check=True)
                check(pdf)


if __name__ == '__main__':
    main()
