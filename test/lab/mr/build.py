#!/usr/bin/env python3
"""Lab mr (Windows 01QbbApP, for amd-3): first baseline of a paragraph whose first line mixes two run sizes.
Package = zh-202582e2 (styles/settings/sectPr kept); body = a plain 15pt FangSong paragraph + the item-3 paragraph whose first two runs ("3", ".消防设施按设计") are S pt, the rest 15pt.
usage: build.py SRC.docx OUTDIR"""
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
d = z.read('word/document.xml').decode()
ps = re.findall(r'<w:p>.*?</w:p>', d, flags=re.S)
item3 = next(p for p in ps if 'w:line="322"' in p and 'w:before="46"' in p)
head = d[:d.index('<w:body>') + 8]
sect = re.search(r'<w:sectPr.*?</w:sectPr>', d, flags=re.S).group(0)
above = item3.replace('w:val="31"', 'w:val="30"')
for S in (15, 15.5, 16, 17, 18, 20):
    sz = str(int(S * 2))
    parts = item3.split('<w:r>')
    # parts[1], parts[2] are the "3" and ".消防设施按设计" runs
    for k in (1, 2):
        parts[k] = parts[k].replace('w:val="31"', f'w:val="{sz}"')
    p = '<w:r>'.join(parts)
    body = above + p + '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr></w:p>' + sect
    doc = head + body + '</w:body></w:document>'
    name = f'mr-{str(S).replace(".", "_")}'
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for it in z.infolist():
            if it.is_dir(): continue
            o.writestr(it.filename, doc if it.filename == 'word/document.xml' else z.read(it.filename))
    print(name)
