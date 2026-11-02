#!/usr/bin/env python3
"""Lab hy (Windows 01QbbApP, for amd-5): automatic hyphenation in Word for Windows.
gen.py OUT writes docs: A-{lang}  B-z{0,360,720,1440} (left), B-j720 (justified), B-j0,  C-c{1,2,3,u}, D-caps{0,1}, E-probes (zone 0), F-suppress.
Column 3402 twips (6 cm) = page 11906 with margins 4252.  Times New Roman 12pt, compat 15, w:autoHyphenation."""
import sys, os, zipfile
W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
EN = ("The international committee considered the administrative reorganization of the organization's communication infrastructure, "
      "emphasizing environmental responsibilities, extraordinary educational opportunities, and the unprecedented possibilities of "
      "technological development in contemporary society. Representatives demonstrated considerable enthusiasm regarding collaborative arrangements. ")
GB = EN.replace("reorganization", "reorganisation").replace("organization", "organisation").replace("emphasizing", "emphasising")
T = {
    "en-US": EN, "en-GB": GB,
    "nl-NL": ("De internationale commissie besprak de administratieve reorganisatie van de communicatie-infrastructuur van de organisatie, met nadruk op "
              "milieuverantwoordelijkheden, buitengewone onderwijsmogelijkheden en de ongekende mogelijkheden van technologische ontwikkeling in de "
              "hedendaagse samenleving. Vertegenwoordigers toonden aanzienlijk enthousiasme over samenwerkingsverbanden. "),
    "de-DE": ("Der internationale Ausschuss beriet über die administrative Neuorganisation der Kommunikationsinfrastruktur der Organisation und betonte dabei "
              "Umweltverantwortung, außergewöhnliche Bildungsmöglichkeiten sowie die beispiellosen Entwicklungsmöglichkeiten der Technologie in der "
              "zeitgenössischen Gesellschaft. Vertreter zeigten beträchtliche Begeisterung für Kooperationsvereinbarungen. "),
    "es-ES": ("El comité internacional consideró la reorganización administrativa de la infraestructura de comunicación de la organización, destacando las "
              "responsabilidades medioambientales, las extraordinarias oportunidades educativas y las posibilidades sin precedentes del desarrollo tecnológico "
              "en la sociedad contemporánea. Los representantes demostraron un entusiasmo considerable respecto a los acuerdos de colaboración. "),
    "fr-FR": ("Le comité international a examiné la réorganisation administrative de l'infrastructure de communication de l'organisation, en soulignant les "
              "responsabilités environnementales, les possibilités éducatives extraordinaires et les perspectives sans précédent du développement technologique "
              "dans la société contemporaine. Les représentants ont montré un enthousiasme considérable pour les accords de collaboration. "),
}


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;")


def para(text, lang="en-US", jc="left", supp=False):
    rp = '<w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:lang w:val="%s"/></w:rPr>' % lang
    pp = '<w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="%s"/></w:pPr>' % ('<w:suppressAutoHyphens/>' if supp else '', jc)
    return '<w:p>%s<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p>' % (pp, rp, esc(text))


def pkg(path, body, zone=None, consec=None, caps=None):
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="4252" w:bottom="1440" w:left="4252" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % W_)
    s = '<w:autoHyphenation/>'
    if consec is not None:
        s += '<w:consecutiveHyphenLimit w:val="%d"/>' % consec
    if zone is not None:
        s += '<w:hyphenationZone w:val="%d"/>' % zone
    if caps is not None:
        s += '<w:doNotHyphenateCaps/>' if caps else ''
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s>%s<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % (W_, s))
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, v in (("[Content_Types].xml", ct), ("_rels/.rels", root), ("word/document.xml", doc), ("word/styles.xml", sty), ("word/settings.xml", st), ("word/_rels/document.xml.rels", dr)):
            z.writestr(n, v)


CAPS = ("The INTERNATIONALIZATION of COMMUNICATIONS and ORGANIZATIONAL RESPONSIBILITIES required Constantinople, Massachusetts and Pennsylvania "
        "representatives to discuss INFRASTRUCTURE, ENVIRONMENTAL ARRANGEMENTS, Oppenheimer, Schwarzenegger and UNPRECEDENTED POSSIBILITIES. ")
PROBES = ["about", "only", "table", "radio", "under", "enough", "around", "also", "language", "elephant", "computer", "problem"]


def main(out):
    os.makedirs(out, exist_ok=True)
    for lg, t in T.items():
        pkg(os.path.join(out, "hyA-%s.docx" % lg), para(t * 4, lg, "both"), zone=360)
    prose = EN * 4
    for z in (0, 360, 720, 1440):
        pkg(os.path.join(out, "hyB-z%d.docx" % z), para(prose), zone=z)
    for z in (0, 720):
        pkg(os.path.join(out, "hyB-j%d.docx" % z), para(prose, jc="both"), zone=z)
    for c in (1, 2, 3, None):
        pkg(os.path.join(out, "hyC-c%s.docx" % ("u" if c is None else c)), para(prose), zone=0, consec=c)
    for k in (0, 1):
        pkg(os.path.join(out, "hyD-caps%d.docx" % k), para(CAPS * 6), zone=0, caps=bool(k))
    body = ""
    for p in PROBES:
        for k in range(30, 51):
            body += para("i" * k + " " + p)
    pkg(os.path.join(out, "hyE-probes.docx"), body, zone=0)
    body = para(prose) + para(prose, supp=True) + para(prose)
    pkg(os.path.join(out, "hyF-suppress.docx"), body, zone=0)
    print(sorted(os.listdir(out)))


if __name__ == "__main__":
    main(sys.argv[1])
