import sys, os, re, json, zipfile, importlib.util
spec = importlib.util.spec_from_file_location('hcgen', os.path.expanduser('~/starling-doc-check/lab/hc/spec/gen.py')); hc = importlib.util.module_from_spec(spec); spec.loader.exec_module(hc)
FLAGS = {"f1": ("<w:doNotWrapTextWithPunct/>", ""), "f2": ("<w:doNotUseEastAsianBreakRules/>", ""), "f3": ("<w:doNotWrapTextWithPunct/><w:doNotUseEastAsianBreakRules/><w:useFELayout/>", ""),
         "f4": ("", '<w:adjustRightInd w:val="0"/>'), "f5": ("", '<w:kinsoku/><w:wordWrap/><w:overflowPunct/><w:topLinePunct w:val="0"/>'), "f6": ("", '<w:snapToGrid/>')}
ws = list(range(350, 382))
for k, (cflag, pflag) in FLAGS.items():
    body = ''.join(hc.para(hc.A_ + hc.FILL, 9026 - round(w * 20), "both").replace('<w:jc ', pflag + '<w:jc ', 1) for w in ws)
    path = os.path.join(sys.argv[1], f"hf-{k}.docx"); hc.pkg(path, body, "compressPunctuation")
    zi = zipfile.ZipFile(path); items = {n: zi.read(n) for n in zi.namelist()}; zi.close()
    items['word/settings.xml'] = items['word/settings.xml'].decode().replace('<w:compat>', '<w:compat>' + cflag).encode('utf8')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as o:
        for n, v in items.items(): o.writestr(n, v)
    json.dump(ws, open(path[:-5] + '.ws', 'w')); print(k)
