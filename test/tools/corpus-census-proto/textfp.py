import zipfile,re,json,sys,os,unicodedata
out={}
for D in ("test/corpus/docx/docs","test/corpus/docx/lo/docs"):
  for n in os.listdir(D):
    if not n.endswith(".docx"): continue
    k=n[:-5]
    try:
        z=zipfile.ZipFile(os.path.join(D,n)); x=z.read("word/document.xml").decode("utf8","replace")
    except Exception: continue
    t="".join(re.findall(r"<w:t(?:\s[^>]*)?>([^<]*)</w:t>",x))
    toks=set()
    for ch in set(t):
        o=ord(ch)
        cat=unicodedata.category(ch)
        if cat[0] in "PS" or o in (0x3000,0xa0,0x2002,0x2003): toks.add(f"ch:{o:04x}")
        elif 0xff00<=o<=0xffef: toks.add("fullwidth-form")
    sz=set(int(v) for v in re.findall(r'<w:sz w:val="(\d+)"',x))
    for s in sz: toks.add(f"sz:{s}")
    toks.add("len:%d"%min(5,len(t).bit_length()//3))
    out[k]=sorted(toks)
json.dump(out,open(sys.argv[1],"w"))
print(len(out))
