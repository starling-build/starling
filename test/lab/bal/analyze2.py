import sys, glob, os, pymupdf
# for each line: non-space glyphs with x0 and the origin-based advance; gaps between a Latin/digit glyph and a CJK glyph (both directions), measured origin-to-origin minus the Latin glyph's natural advance (from its own run on the line is unknown), so report origin x of every glyph
for f in sorted(glob.glob(sys.argv[1] + '/*-orig.pdf')):
    d = pymupdf.open(f); print('##', os.path.basename(f))
    for b in d[0].get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
            if not cs: continue
            sz = l['spans'][0]['size']; x = [c['origin'][0] for c in cs]
            print(f"{sz:.1f}\t" + ' '.join(f"{c['c']}@{x[i]-x[0]:.2f}" for i, c in enumerate(cs)))
