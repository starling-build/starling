import sys, os, json, importlib.util
spec = importlib.util.spec_from_file_location('hcgen', os.path.expanduser('~/starling-doc-check/lab/hc/spec/gen.py')); hc = importlib.util.module_from_spec(spec); spec.loader.exec_module(hc)
V = {"a": "COVID-19疫苗者，得免除PCR檢驗未完整接種疫苗之移",       # one inner comma at 7
     "b": "COVID-19疫苗，者得免除PCR檢驗未完整接種疫苗之移",       # one inner comma early (after 疫苗)
     "c": "疫苗者，得免除，未完整接種移",                        # two commas at 4 and 8 of 14
     "d": "COVID-19疫苗者得免除PCR檢驗未完整接種疫苗之移"}         # none (= hc B)
mode, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
if mode == "cal":
    for k, L in V.items():
        hc.pkg(os.path.join(out, f"cal-{k}.docx"), hc.para(L) + hc.para(L + "工") + hc.para(L + "工，"), "compressPunctuation"); print("cal-" + k)
else:
    W = json.load(open(sys.argv[3]))
    for k, L in V.items():
        lo, hi = W[k]; ws = list(range(int(lo) - 3, int(hi) + 5))
        hc.pkg(os.path.join(out, f"h3-{k}.docx"), ''.join(hc.para(L + hc.FILL, 9026 - round(w * 20), "both") for w in ws), "compressPunctuation")
        json.dump(ws, open(os.path.join(out, f"h3-{k}.ws"), "w")); print("h3-" + k, len(ws))
