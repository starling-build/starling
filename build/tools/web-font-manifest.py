#!/usr/bin/env python3
"""Manifest entries for the script fonts, from Resources/fonts/fonts.tsv.

    web-font-manifest.py FONTS_DIR [--gzip]   -> JSON array on stdout

One entry per FILE (a collection is one download), lazy, in fallback order:
  {"url", "bytes", "sha256", "lazy": true, "weight": 400|700,
   "faces": [{"index", "family"}...]   index -1: a plain file,
   "scripts": [...], "fallback": true, "order": N}
`order` is the smallest fallback_order of the file's rows (0: registered but
not in the glyph-fallback chain). With --gzip the page fetches url + ".gz"
(GitHub Pages sends no Content-Encoding for fonts) and inflates it itself.
"""
import csv, json, sys, os

def entries(fonts_dir, gzip=False):
    by_file = {}
    with open(os.path.join(fonts_dir, 'fonts.tsv'), newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f, delimiter='\t'):
            e = by_file.setdefault(row['file'], {
                'url': 'fonts/' + row['file'], 'bytes': int(row['bytes']), 'sha256': row['sha256'],
                'lazy': True, 'weight': 700 if row['weight'] == 'Bold' else 400,
                'faces': [], 'scripts': [], 'fallback': False, 'order': 0, '_orders': []})
            e['faces'].append({'index': int(row['face_index']), 'family': row['family']})
            if row['script'] not in e['scripts']: e['scripts'].append(row['script'])
            if row['role'] == 'fallback' and int(row['fallback_order']) > 0:
                e['fallback'] = True
                e['_orders'].append(int(row['fallback_order']))
    out = []
    for e in by_file.values():
        e['order'] = min(e.pop('_orders'), default=0)
        if gzip: e['gzip'] = True
        out.append(e)
    return out

if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    json.dump(entries(args[0], '--gzip' in sys.argv), sys.stdout, indent=1, ensure_ascii=False)
    print()
