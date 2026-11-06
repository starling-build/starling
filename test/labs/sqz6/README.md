Lab sqz6 (for `windows`, Word for Windows). Does Word take a line-end symbol (□ ■ ○, against the ideograph 工) past the line's room, and how far?
Run `python3 -I test/labs/sqz6/spec/gen.py test OUT`, open the 32 files in OUT in Word, print to PDF (same page setup as lab sqz3 / wsf), send the PDFs or the first-W read-out.
Each file has 37 paragraphs, W stepped 1 pt over the 36 pt below natural; read-out per variant: the first W at which the last character (X) stays on line 1.
Variants: X = 工 □ ■ ○; before it 止 (ideograph) or ； (closing mark); 0 or 9 spaces mid-line; compat 14 or 15.
Why: zh-e0ca7252 p20 "...之日止；□" (justified, 9 spaces): Word keeps the □; our log needs 19.9 pt of squeeze against room 14. sqz3 showed Word never took a lone 工 below natural.
Also covers 27083953, 9e020c95, 7b125a21 over a wider range (36 pt) than sqz3's 21.
