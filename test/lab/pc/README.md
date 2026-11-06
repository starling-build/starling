# lab pc — punctuation compression in a full line (Word for Windows)

Question: when does Word squeeze full-width commas (and 、。 closing brackets) in a justified full line, by how much, and how does that decide how many characters the line holds? (zh-cd8987db, zh-27083953, zh-c2f6d17a, zh-3fe252ff: compat 15, compressPunctuation, one character different at a line end.)

Two docs (package of zh-cd8987db: real settings.xml compat 15, characterSpacingControl compressPunctuation, styles.xml): `pc-105-simsun` (宋体 10.5 pt) and `pc-16-fangsong` (仿宋 16 pt). Page A4, margins 1134, justified, exact line 1.6 x size, no grid snap.

77 paragraphs each = 7 types x 11 right-indent steps (0 .. 1 character in tenths: w:ind right = step x size/10 pt). Label = 3 characters (type 甲..壬, step 甲..癸 then 甲丑 = step 10). Text after the label: 64 distinct characters (千字文) with punctuation inserted:
- T0 (甲) none; T1 (乙) one ，after char 20; T2 (丙) ，after 8, 20, 32; T3 (丁) ，after every 4th char (to 44); T4 (戊) ，、。 rotating every 4th; T5 (己) ，and ）alternating every 4th; T6 (庚) （ before and ， after, every 4th.

Please print both to PDF in Word for Windows and send per line: page, baseline, x0 of every glyph (first lines matter most; the rest of each paragraph is filler). Compare per paragraph: characters on the first line, and the advance of each ，、。）（.
