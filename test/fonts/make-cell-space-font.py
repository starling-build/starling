#!/usr/bin/env python3
"""Regenerate the six-glyph cell-space fixture from Noto Sans SC (FontTools required)."""
import argparse
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, help='NotoSansSC-VariableFont_wght.ttf')
args = parser.parse_args()
font = TTFont(args.source, recalcTimestamp=False)
font = instantiateVariableFont(font, {'wght': 400}, inplace=True)
options = subset.Options()
options.name_IDs = ['*']
options.name_legacy = True
options.name_languages = ['*']
subsetter = subset.Subsetter(options=options)
subsetter.populate(text='甲（）、 A')
subsetter.subset(font)
for entry in font['name'].names:
    if entry.nameID in (1, 4, 6, 16, 17):
        name = ('Regular' if entry.nameID == 17 else
                'StarlingCellSpaceCJKTest' if entry.nameID == 6 else 'Starling Cell Space CJK Test')
        entry.string = name.encode(entry.getEncoding())
font.save(Path(__file__).with_name('StarlingCellSpaceTest.ttf'))
