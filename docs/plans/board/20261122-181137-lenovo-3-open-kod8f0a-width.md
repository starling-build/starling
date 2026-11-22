# OPEN ko-d8f0a8af5 p5 (and p535-539): our Korean lines carry one more syllable than PowerPoint's (lenovo-3, 2026-11-22)

HANDOFF for task (d), lab ko-latinlnbrk (2 rounds used).

Settled (PR #1808): run language decides the Hangul word hold. latinLnBrk stated nowhere + a run naming ko = hold whole (text boxes and cells); latinLnBrk 1 parts mid-word; runs with no lang part mid-word. spc and run splitting do not change it (round 2). 25 ko decks 98.3 to 98.4, none down.

NOT explained: ko-d8f0a p5, paragraph "이심사기준은상표법등...해석과상표심사(이의신청포함)에 / 관한기준을...". PowerPoint ends the line at "에" and starts "관한"; ours fits "관" more, and the next line ends "규정이다" vs ours "규정이다른". Every line of that justified paragraph is one syllable longer in ours. The runs have no lang, Batang 12 pt, algn=just, marR=5080, indent=152400, runs carry spc -25 to -55 on words and +120 to +125 on the single-space runs. So this is a WIDTH gap (per-run spc on spaces and words, or the justified margin), not the break rule. Word lines: 14395 lines, ours 14362, matched 13745.
Next step: print a lab of one such paragraph with spc only on the space runs (+125) vs only on words (-40), measure the line width in the PDF against ours.
