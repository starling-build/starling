#!/usr/bin/env python3
"""Apply Office's deferred-font policy to new builds and existing web stages."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit


DEFERRED_FAMILIES = {
    'ArchivoBlack-Regular.ttf': 'Archivo Black',
    'StarlingFangSong-Regular.ttf': 'Starling FangSong',
}


def prepare_manifest(entries):
    """Keep UI/default faces eager; give optional faces names for lazy lookup.

    An empty families list registers a font using its internal name, but cannot
    be requested by the deferred loader. Retain explicit aliases if provided.
    """
    result = []
    for entry in entries:
        entry = dict(entry)
        family = DEFERRED_FAMILIES.get(Path(urlsplit(entry['url']).path).name)
        if family:
            entry['families'] = entry.get('families') or [family]
            entry['lazy'] = True
        result.append(entry)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    args.manifest.write_text(json.dumps(prepare_manifest(json.loads(args.manifest.read_text())), indent=2) + '\n')
