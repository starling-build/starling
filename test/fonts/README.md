# Opener boundary test font

`StarlingOpenerCJKTest.ttf` is a static weight-400 subset of
[Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc),
renamed for this test. It contains only `甲乙，（「）` and the required font
infrastructure (4,124 bytes). Copyright and the SIL Open Font License 1.1
are preserved in the font and `StarlingOpenerCJKTest-LICENSE.txt`.

`test/office-opener-fit.py` embeds it in its generated DOCX so native and
browser checks do not depend on installed CJK fonts or a network font
service. This is a test asset, not an application font.

Regenerate with FontTools:

```sh
python3 test/fonts/make-opener-font.py /path/to/NotoSansSC-VariableFont_wght.ttf
```

Original source SHA256: `2e68d43ae2c504f4e302a9cf522ecc3f06ef66d724cade58bbe13a3a4af70512`.
Created with FontTools 4.67.0; regenerated container metadata
may differ with the tool version. The test verifies line breaks and complete
text against Word-printed controls, not the font file's binary identity.

# Cell word boundary test font

`StarlingCellSpaceTest.ttf` is another static weight-400 subset of the same
Noto Sans SC source, renamed **Starling Cell Space CJK Test**. It contains
`甲（）、 A` (six glyphs, including space). The matching
`StarlingCellSpaceTest-LICENSE.txt` preserves the SIL Open Font License 1.1.
`test/office-cell-word-fit.py` embeds it to test legacy cell word fitting
without installed CJK fonts; Arial supplies its ordinary spaces and letters.
The PDF check also asserts that the embedded CJK font was used. Regenerate with:

```sh
python3 test/fonts/make-cell-space-font.py /path/to/NotoSansSC-VariableFont_wght.ttf
```
