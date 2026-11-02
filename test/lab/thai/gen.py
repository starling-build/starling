#!/usr/bin/env python3
"""Lab thai (Windows 01QbbApP, for amd-3): does Word for Windows break Thai only at spaces?
gen.py OUT writes: thai-1-nospace (justified, no spaces), thai-2-space (same text, space between phrases),
thai-3-bidith (no spaces, w:lang w:bidi="th-TH"), thai-4-nolang (no spaces, no lang), thai-5-bidith-space,
thai-6-nospace-tahoma (no spaces, Tahoma).  TH Sarabun New 16pt on w:cs runs (w:rFonts cs + w:szCs 32 + w:cs), A4 default margins 1440, compat 15."""
import sys, os, zipfile
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
PH = ["การประชุมคณะกรรมการบริหารได้ข้อสรุป", "เกี่ยวกับแผนงานพัฒนาระบบสารสนเทศ", "ของหน่วยงานภาครัฐและเอกชน", "ที่ร่วมมือกันดำเนินโครงการ",
      "เพื่อยกระดับคุณภาพชีวิตของประชาชน", "ในพื้นที่ชนบทห่างไกลทั่วประเทศ", "โดยมีเป้าหมายให้เด็กและเยาวชน", "สามารถเข้าถึงการศึกษาได้อย่างเท่าเทียม",
      "ตลอดจนส่งเสริมการเรียนรู้ตลอดชีวิต", "และการสร้างงานสร้างอาชีพให้แก่คนในชุมชน", "ทั้งนี้ที่ประชุมได้มอบหมายให้", "ฝ่ายเลขานุการรวบรวมข้อเสนอแนะ",
      "จากทุกภาคส่วนเพื่อนำเสนอในการประชุมครั้งถัดไป"]


def pkg(path, text, lang, font):
    rf = '<w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s"/>' % (font, font, font)
    ln = '<w:lang w:bidi="th-TH"/>' if lang else ''
    run = '<w:r><w:rPr>%s<w:sz w:val="32"/><w:szCs w:val="32"/><w:cs/>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (rf, ln, text)
    body = '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="both"/></w:pPr>%s</w:p>' % run
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr>%s<w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, rf))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % W_)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/styles.xml", sty), ("word/settings.xml", st), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    nosp, sp = "".join(PH), " ".join(PH)
    S = "TH Sarabun New"
    for name, t, lang, font in (("1-nospace", nosp, False, S), ("2-space", sp, False, S), ("3-bidith", nosp, True, S), ("4-nolang", nosp, False, S),
                                ("5-bidith-space", sp, True, S), ("6-nospace-tahoma", nosp, False, "Tahoma")):
        pkg(os.path.join(out, "thai-%s.docx" % name), t, lang, font)
        print(name)
