import re,zipfile,random
src=open('/data/s/amd-6/starling/apps/OfficeApp/Sources/OfficeApp/Sheets/HintedAdvances.swift',encoding='utf8').read()
tab={m.group(1):[ord(c)-48 for c in m.group(2)] for m in re.finditer(r'"([^"]+\|[^"]+)": "([^"]*)"',src)}
cs='abcdefghijklmnopqrstuvwxyz0123456789'
def word(face,size,target):
    w=tab[f'{face}|{size}|0|0']; adv=lambda c:w[ord(c)-0x20]
    for seed in range(5000):
        random.seed(seed*1000+target); s='';t=0
        while t<target:
            c=random.choice(cs)
            if t+adv(c)<=target: s+=c;t+=adv(c)
            else:
                cand=[x for x in cs if t+adv(x)==target]
                if cand: s+=cand[0];t=target
                else: break
        if t==target and len(s)>2: return s
    raise SystemExit(f'no word {face} {target}')
def col(i): return chr(64+i)
for face,size,nm in (('calibri','11','Calibri'),('arial','10','Arial')):
    sz=size; Ps=[49,56,63,70,77,84]; rows=[]
    cols=''.join(f'<col min="{i}" max="{i}" width="{P/7:.10f}" customWidth="1"/>' for i,P in enumerate(Ps,1))
    body=''
    for k,d in enumerate(range(-6,3)):
        cells=''
        for i,P in enumerate(Ps,1):
            w=word(face,size,P+d)
            cells+=f'<c r="{col(i)}{2+k}" s="1" t="inlineStr"><is><t>{w}</t></is></c>'
        body+=f'<row r="{2+k}">{cells}</row>'
    hdr='<row r="1">'+''.join(f'<c r="{col(i)}1" t="inlineStr"><is><t>P={P}</t></is></c>' for i,P in enumerate(Ps,1))+'</row>'
    sheet=f'<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetFormatPr defaultRowHeight="15"/><cols>{cols}</cols><sheetData>{hdr}{body}</sheetData><pageSetup orientation="landscape"/></worksheet>'
    styles=f'<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="{sz}"/><name val="{nm}"/><family val="2"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
    z=zipfile.ZipFile(f'lab-{face}.xlsx','w',zipfile.ZIP_DEFLATED)
    z.writestr('[Content_Types].xml','<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>')
    z.writestr('_rels/.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    z.writestr('xl/workbook.xml','<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Lab" sheetId="1" r:id="rId1"/></sheets></workbook>')
    z.writestr('xl/_rels/workbook.xml.rels','<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>')
    z.writestr('xl/styles.xml',styles); z.writestr('xl/worksheets/sheet1.xml',sheet); z.close()
print('ok')
