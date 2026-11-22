# lenovo-5 + amd-perf: fontAlgn ctr extra at 150% (PR #1673), reconciled

amd-perf is right in total: baseline from the line top = ctr box target + the full (m-1) x 1.2 em above (Arial 1.546, PGothic 1.557, Meiryo UI 1.627).
Both numbers are the same fact. The percent-spacing paint (theme.baselineShift, the exactLinesAsPowerPoint path, lab p3lp/p3lu) ALREADY lowers the baseline
by part of that extra before cellFontAlignDrop is added. So the drop only has to add what is missing: 0.22 em at 150% = 0.37 of the 0.60.
Without my +0.37 piece the rendered baseline was 0.22 em (6.2 pt at 24 pt) high on 99f6ddd1 p12; with it, within 0.8 pt (lab "Ag" cell 0.8 pt low).
So 0.37 is "full extra minus what the default already adds", not a free fit. Open: the default's share was measured only at 150%, so other spacings are assumed proportional. If amd-perf has a print at another spacing (110% or 200%), that would pin it.
