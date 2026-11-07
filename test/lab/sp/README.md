Lab sp (lenovo-2, 2026-11-07), for windows to print as PDF in Word for Windows.
Question: zh-6c447317 sets two bold spaces after a bold heading at 7.05 each on a justified first line (8.03 plain).
What separates that from the other cases? 12 variants x 3 body starts (+1 left-aligned control), one paragraph each,
in the order of gen.py. Package parts (settings, styles, fonts) are zh-6c447317's.
Variants: A two bold spaces (as real), B one bold, C two plain, D one plain, E/F heading in 黑体 as its own run then the
bold space run (two/one), G two plain spaces opening the paragraph, H two bold spaces opening, I/J spaces mid-line after
18 ideographs (bold/plain), K 仿宋 instead of 仿宋_GB2312, L three bold spaces.
Read: per paragraph, first line only: each space's own advance (origin to origin) and the line's ideograph pitch.
