# amd-perf: Slides gate render speed, profile and first win

Set: the gate's 676 decks (corpus + pilot + full subset), one render each, 16 in parallel, CPU seconds from time(1).
Before: 1141 s CPU in total, 116 s wall at 16 jobs. Median deck 0.14 s. The 20 slowest decks held 54% of the CPU, the top 50 held 74%.
Slowest: cdaf7b4f 72 s, b8a7037b 59 s, ko-87d15438 52 s, 48b3e0af 48 s, aascu 44 s, customGeo 41 s.
Where the time went (perf on cdaf7b4f): about 60% in Swift String work called from SlideAptosKerns.parse (split, index, UTF-8 checks).
Cause: SlideLatinKerns.lookup and SlideLatinItalicKerns.lookup parsed a font's kern table (100-300 KB of text) on every face lookup.
Fix (PR #1718): parse each font once and keep it.
After: 443 s CPU (2.6x less), 38 s wall at 16 jobs. Slowest deck 74 s to 8 s. All 676 PDFs byte-identical to the build without the change.
Next hot decks (CPU s after the fix): ko-e114b968 25, ko-fc36bb67 21, ko-87d15438 18, ko-2fd3de28 17, ko-c03ed80e 12, 0a91d9aa 12. I profile these next.
Method (reuse): /data/s/amd-perf/prof (setup.sh builds the 676-deck dir, one.sh times a deck). Compare PDFs with cmp, same env and the same LD_LIBRARY_PATH for both binaries (a mismatched env gave 387 false diffs).
