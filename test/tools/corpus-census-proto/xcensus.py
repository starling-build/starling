import zipfile,re,os,collections
P={"toc":r'instrText[^>]*>\s*TOC\b|w:instr="\s*TOC',"date":r'instrText[^>]*>\s*(DATE|TIME|PRINTDATE|CREATEDATE|SAVEDATE)\b',"if":r'instrText[^>]*>\s*IF\b',
"seq":r'instrText[^>]*>\s*SEQ\b',"ref":r'instrText[^>]*>\s*(REF|PAGEREF|NOTEREF)\b',"mergefield":r'MERGEFIELD',"formfield":r'w:ffData',"eq":r'instrText[^>]*>\s*EQ\b',
"hangul":r'[가-힣]',"kana":r'[぀-ヿ]',"hebrew":r'[֐-׿]',"arabic":r'[؀-ۿ]',"devanagari":r'[ऀ-ॿ]',"greek":r'[Ͱ-Ͽ]',"cyrillic":r'[Ѐ-ӿ]',"thai":r'[฀-๿]',
"kashida":r'w:jc w:val="(lowKashida|mediumKashida|highKashida)"',"thaiDist":r'w:jc w:val="thaiDistribute"',"bidi":r'<w:bidi/>|<w:bidi w:val="(1|true|on)"',"bidiVisual":r'bidiVisual',
"lnNum":r'w:lnNumType',"pgBorders":r'w:pgBorders',"fitText":r'w:fitText',"eaLayout":r'w:eastAsianLayout',"em":r'<w:em w:val="(?!none)',"tblFixed":r'w:tblLayout w:val="fixed"',
"cantSplit":r'w:cantSplit',"tblHeader":r'w:tblHeader',"vMerge":r'w:vMerge',"ptab":r'w:ptab',"altChunk":r'w:altChunk',"ole":r'<w:object',"mirrorMargins":r'mirrorMargins',"gutter":r'w:gutter="[1-9]',
"hyphen":r'autoHyphenation',"widowOff":r'<w:widowControl w:val="(0|false)',"contSect":r'w:type w:val="continuous"',"colSep":r'w:cols [^>]*w:sep="(1|true)',"textDirTb":r'w:textDirection w:val="(tbRl|tbRlV|btLr|tbLrV)"',
"tabRight":r'w:tab w:val="right"',"tabDecimal":r'w:tab w:val="decimal"',"tabLeader":r'w:leader="(dot|hyphen|underscore|middleDot)"',"dropcap":r'w:dropCap="(drop|margin)"',"wrapTight":r'wp:wrapTight|wp:wrapThrough',"behindDoc":r'behindDoc="1"',"glossary":r'glossary',"caps":r'<w:(smallCaps|caps)/>',"kern":r'<w:kern ',"position":r'<w:position ',"highlight":r'w:highlight'}
C={k:re.compile(v) for k,v in P.items()}
cnt={"756":collections.Counter(),"lo":collections.Counter()}
for s,D in (("756","test/corpus/docx/docs"),("lo","test/corpus/docx/lo/docs")):
  for n in os.listdir(D):
    try:
        z=zipfile.ZipFile(os.path.join(D,n)); x="".join(z.read(m).decode("utf8","replace") for m in z.namelist() if m.startswith("word/") and m.endswith(".xml") and "theme" not in m)
    except Exception: continue
    for k,c in C.items():
        if c.search(x): cnt[s][k]+=1
for k in P: print(f"{k}:{cnt['756'][k]}/{cnt['lo'][k]}",end="  ")
print()
