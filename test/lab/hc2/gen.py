#!/usr/bin/env python3
"""Lab hc2 (Windows 01QbbApP, for amd-5): hung end comma with inner commas present, in other setups.
Variant 1a: zh-2af9ab1b's own pPr/rPr (仿宋_GB2312 16pt, kinsoku, jc both, exact 30pt, docGrid lines 312, compat 15, compressPunctuation), first line = the Word line
 "《山东省突发公共卫生事件应急办法》等有关法律法规，结合" + "本市实际，制定本办法。..." ; 1b: shortened "等有关法律法规，结合本市实际" + "，制定..." (X=际 then a comma).
Variant 2: hc's own line (標楷體, A_ text) at 16pt in a document with docGrid lines 312.   Variant 3: hc's own line at 14pt, no grid, but 仿宋_GB2312 font.
usage: gen.py cal OUT | gen.py test OUT widths.json"""
import sys, os, re, json, zipfile
SRC = os.path.expanduser('~/starling-doc-check/lab/hc2/src/s.docx')
z = zipfile.ZipFile(SRC)
D = z.read('word/document.xml').decode()
P = next(p for p in re.findall(r'<w:p[ >].*?</w:p>', D, flags=re.S) if '山东省突发公共卫生事件应急办法' in re.sub(r'<[^>]+>', '', p))
PPR = re.search(r'<w:pPr>.*?</w:pPr>', P, flags=re.S).group(0)
PPR = re.sub(r'<w:ind [^>]*/>', '', PPR)          # indents are ours
RPR = re.findall(r'<w:rPr>.*?</w:rPr>', P, flags=re.S)[2]   # the 仿宋_GB2312 body run's rPr (index 0 = pPr's own)
SECT = re.search(r'<w:sectPr.*?</w:sectPr>', D, flags=re.S).group(0)
TEXTW = 11906 - 1701 * 2
L1 = "《山东省突发公共卫生事件应急办法》等有关法律法规，结合"
L2 = "等有关法律法规，结合本市实际"
A_ = "COVID-19疫苗者，得免除PCR檢驗，未完整接種疫苗之移"
FILL1 = "本市实际，制定本办法。为了有效应对突发公共卫生事件，保障公众身体健康与生命安全，维护正常的社会秩序。"
FILL2 = "，制定本办法。为了有效应对突发公共卫生事件，保障公众身体健康与生命安全，维护正常的社会秩序。"
FILL3 = "工，并应配合辦理相關事項之規定以維護公共衛生安全及保障全體民眾健康"
# name: (L, X-chars-after-L list for calibration probes, fill, grid, font, size)
VARS = {
 "1a": (L1, "本", FILL1, None),
 "1b": (L2, "，", FILL2, None),     # L2 ends at 际; probe adds the comma
 "2": (A_, "工，", FILL3, "g"),
 "3": (A_, "工，", FILL3, "f"),
}
def para(var, text, rind=0, jc="both"):
    if var in ("1a", "1b"):
        return '<w:p>' + PPR_I(rind, jc) + '<w:r>' + RPR + '<w:t xml:space="preserve">' + text + '</w:t></w:r></w:p>'
    sz, font = (32, "標楷體") if var == "2" else (28, "仿宋_GB2312")
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="680" w:lineRule="exact"/><w:ind w:left="0" w:right="{rind}"/><w:jc w:val="{jc}"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:eastAsia="{font}"/>'
            f'<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/><w:lang w:eastAsia="zh-TW"/></w:rPr><w:t xml:space="preserve">{text}</w:t></w:r></w:p>')
def PPR_I(rind, jc):
    x = re.sub(r'<w:jc w:val="[a-z]+"/>', f'<w:ind w:left="0" w:right="{rind}"/><w:jc w:val="{jc}"/>', PPR)
    return x
def build(path, var, body):
    if var in ("1a", "1b"):
        zi = zipfile.ZipFile(SRC)
        doc = D[:D.index('<w:body>') + 8] + body + SECT + '</w:body></w:document>'
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as o:
            for it in zi.infolist():
                if it.is_dir(): continue
                o.writestr(it.filename, doc if it.filename == 'word/document.xml' else zi.read(it.filename))
        return
    import importlib.util
    spec = importlib.util.spec_from_file_location('hcgen', os.path.expanduser('~/starling-doc-check/lab/hc/spec/gen.py')); hc = importlib.util.module_from_spec(spec); spec.loader.exec_module(hc)
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>' + ('<w:docGrid w:type="lines" w:linePitch="312"/>' if VARS[var][3] == "g" else '') + '</w:sectPr>'
    old = hc.pkg
    # reuse hc.pkg but with our sectPr: write by hand
    import types
    src = open(os.path.expanduser('~/starling-doc-check/lab/hc/spec/gen.py'), encoding='utf8').read()
    hc.pkg(path, body, "compressPunctuation")
    zi = zipfile.ZipFile(path); items = {n: zi.read(n) for n in zi.namelist()}; zi.close()
    d = items['word/document.xml'].decode(); d = re.sub(r'<w:sectPr>.*?</w:sectPr>', sect, d, flags=re.S); items['word/document.xml'] = d.encode('utf8')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as o:
        for n, v in items.items(): o.writestr(n, v)
if __name__ == "__main__":
    mode, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
    if mode == "cal":
        for v, (L, X, fill, g) in VARS.items():
            tp = (lambda t: para(v, t, 0, "left"))
            probes = [L, L + X, L + X + ("，" if v == "1a" else "")] if v != "1b" else [L2[:-1] + "", L2, L2 + "，"]
            build(os.path.join(out, f"cal-{v}.docx"), v, ''.join(tp(t) for t in probes)); print("cal-" + v)
    else:
        W = json.load(open(sys.argv[3]))
        for v, (L, X, fill, g) in VARS.items():
            lo, hi = W[v]
            hi = min(hi + 3, TEXTW / 20 - 0.5 if v in ("1a", "1b") else 9000)
            ws = []; w = int(lo) - 3
            while w <= hi: ws.append(w); w += 1
            basetxt = L + fill if v != "1b" else L2 + fill
            tw = TEXTW if v in ("1a", "1b") else 9026
            body = ''.join(para(v, basetxt, tw - round(w * 20), "both") for w in ws)
            build(os.path.join(out, f"hc2-{v}.docx"), v, body); json.dump(ws, open(os.path.join(out, f"hc2-{v}.ws"), "w")); print("hc2-" + v, len(ws))
