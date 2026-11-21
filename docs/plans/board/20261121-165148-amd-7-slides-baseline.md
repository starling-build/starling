# amd-7: Slides painter BASELINE on main (2026-11-21)

Score = % of page pixels differing from PowerPoint-for-Windows (lower is better).

Result (555 of 559 decks scored): mean of deck means 0.729%, mean of deck worsts 0.917%.
Committed baseline-win.tsv: 0.730% / 0.917%. No deck is more than 1 point worse than it. 112 decks are exactly 0.00%.
4 ERRORs: clusterfuzz POIXSLFFuzzer 5463285576892416, 5471515212382208, 6372932378820608, 6435650376957952 (corrupt zip; expected).

Worst 20 by deck mean (pages, worst page %, mean %):
1. clusterfuzz ...5611274456596480 (1, 61.6, 61.6)
2. Divino_Revelado (12, 21.4, 14.4)
3. clusterfuzz ...4986044400861184 (23, 28.8, 12.3)
4. oox-tdf139618_ImportWordArtGradient (1, 8.1)
5. oox-tdf139618_WordArtBitmapFill (1, 6.3)
6-8. 45541_Footer / 45541_Header / 45545_Comment (11, 11.6, 5.6)
9. lo-font-scale (1, 5.3)  10. lo-tdf140865Wordart3D (1, 5.2)
11. alterman_security (23, 8.7, 4.9)  12. oox-tdf155327_WordArtDefaultColor (1, 4.5)
13. ae.ac.uaeu...GeomLec1 (14, 8.8, 4.4)  14. aascu...id=5864 (34, 11.0, 4.4)
15. 60810 (25, 6.7, 4.3)  16. oox-tdf139618_ThemeColorTransparency (1, 3.9)
17. lo-activex_picture (1, 3.9)  18. lo-tdf98603 (1, 3.8)
19. au.asn.aes...Maloney (28, 7.2, 3.8)  20. lo-3columns (1, 3.8)

Shared features (by look at the files, not yet by page diff):
- WordArt / text warp and 3-D text: 5 of 20 (oox-tdf139618 x3, tdf140865, tdf155327). Known weak spot (docs/plans/slides.md ~478).
- Fuzzer files: 2 of top 3 (odd or damaged zips). Low value.
- Old-Office decks with OLE objects, WMF pictures and shadows: 45541/45545 family, alterman_security.
- SmartArt (diagrams/): 60810.
- Single-page LibreOffice test files (lo-*): font scale, ActiveX picture, columns.
Not yet looked at page by page: Divino_Revelado (my unzip listing failed; check it first).

Recipe (about 6 min at -j 8):
  cd <checkout> && source ~/bin/office-env.sh && BUILD_INCREMENTAL=1 test/tools/build-office-fast.sh $PWD/.build-shared .
  export OFFICE_APP=$PWD/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp
  nohup test/pptx-app-render.sh -j 8 test/corpus/pptx/decks test/corpus/pptx/powerpoint-win <WORK> > <WORK>.log 2>&1 &
  (uses ~/venv-word/bin/python and MuPDF as in baseline-win.MUPDF; side-by-side PNGs of bad pages land in <WORK>/pairs)
Rows are in <WORK>/render.tsv. Compare with test/corpus/pptx/baseline-win.tsv; matched decks: CORPUS_GROUP=matched GROUP_SUFFIX=-win.
