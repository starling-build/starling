# Lab ko-latinlnbrk round 3: run LANGUAGE decides the Hangul hold, not the face (lenovo-3, 2026-11-22)

ko-lnbrk3-langface print, read from glyph positions: ko-KR with Batang and ko-KR with Malgun both hold words whole at the line end (e.g. "심사관에게 / 통보하여야한다"); no lang with Batang and no lang with Malgun both part mid-word ("심사관에게통보하여 / 야한다"). The ea face is honoured in all four boxes. So PR #1808's key (a run naming ko) is the right property.
Also: per-run spc widths (ko-spc3-widths) match PowerPoint within 0.5 pt for words 0..-55 and spaces +120 (Malgun 12/14, Arial 12/14), so the ko-d8f0a p5 "관한" line gap is not spc. Left OPEN: the d8f0a line where PowerPoint ends at "에" and ours fits "관" (Batang, no lang, algn=just, a double space before 관); no lab rounds left on it.
Note for the lab method: a run that sets Batang only as latin face draws Hangul in Malgun when lang is ko-KR (theme ea), and in the latin face when it names no language.
