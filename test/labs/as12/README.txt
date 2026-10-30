Lab as12 — the automatic space between digits and an ideograph, and "（一）", in Word for Windows. NOT for office.
Question (starling-bd, for zh-12db188f p3): Word's print of its cell paragraph sets the automatic spaces at 7.0 (half an em at 14pt)
and keeps "（一）" whole; ours sets 3.5 and halves （ and ）. zh-8415d258 (15pt 仿宋_GB2312 digits, mode 12, same balance flag) is a quarter,
3.75. Which of the compatibility mode, balance flag, face of the digits and of the ideographs, cell or body, decides?
1. python build.py REPO OUT          (REPO = a checkout with test/corpus/docx/docs) -> 18 as-<mode>-<on|off>-<a|b|c>.docx
   mode 12/14/15; balanceSingleByteDoubleByteWidth on/off; face a = TNR digits + 標楷體 (the original), b = TNR + 宋体, c = 標楷體 both.
   Each has six blocks: A1/A2 wide body (short text, with/without "（一）"; nothing wraps), B1/B2 the same long text at the cell's
   width in the body (right indent), C1/C2 the long text in a one-cell table (cell 4320, margins 28: the original's situation).
2. Print each in a FRESH Word for Windows (quit between, none open), PDF named like the docx.
3. python meas.py OUT/as-*.pdf       -> per line: its right end and text; for the line holding "第8…" the pitch of each character from
   "字" to the ideograph after the digits: 第's pitch is 14.0 + the first space, the last digit's is 7.0 + the second space.
Read-out wanted: (1) the two space widths in A1/A2 (wide: nothing squeezes), in B and C (narrow) — with and without the brackets, per
mode/balance/face; (2) the brackets' pitch (14.0 whole, 7.0 halved) in each; (3) where the long text's first three lines end in B and C.
Control: as-15-on-a C1 should print what Word printed for zh-12db188f: line 2 "社（一）字第89067628 號函", brackets 14.04, gaps 7.0.
