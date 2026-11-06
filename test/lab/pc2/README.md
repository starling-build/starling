# pc2 — 《 and “ in lines that squeeze (lenovo-2, 2026-11-06)

Two documents (SimSun 10.5 pt, FangSong 16 pt), compat 15 with settings.xml and styles.xml (zh-cd8987db's package).
Each document has 8 kinds x 11 paragraphs; the paragraph's right indent grows by 1/10 of a character per step (0 .. 1 character),
so one kind runs from "line full" to "one character short". Label = kind letter + step.
Kinds: V1 one 《 at char 20; V2 one “ at 20; V3 《 at 12 and 》 at 17; V4 “ 12 and ” 17; V5 《 12 + hanging-position 、 at 44;
V6 “ 12 + 、 44; V7 《 12, 》 17, 、 44; V8 、 at 44 alone (control).
Print: for every line, the x of every character (as PC-WORD.tsv of lab pc: doc, page, baseline, x0, x1, text, char_x).
Question: how much do 《 and “ give (Word keeps them 1.0 em where ours squeezes to ~0.9 on some lines), alone and beside a 、 that ends the line.
