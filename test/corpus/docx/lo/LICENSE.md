# LibreOffice's Writer test documents

The 200 documents in `docs/` are copied unchanged from the LibreOffice core
repository, `sw/qa/**/*.docx`, at commit `c0ade982f09c8fcc1d0b484cab0051c6db8b0110`
(<https://git.libreoffice.org/core>, mirrored at
<https://github.com/LibreOffice/core>). None of them is ours: each stays under
the licence and copyright it came with.

## Licence

LibreOffice states that "this product is made available subject to the terms
of the Mozilla Public License, v. 2.0" (`readlicense_oo/license/license.xml`
in that repository; the text is `COPYING.MPL` there and at
<https://www.mozilla.org/MPL/2.0/>). Copyright (c) 2000-2026 LibreOffice
contributors; portions copyright Oracle and/or its affiliates (OpenOffice.org
code). The repository does not give its test documents a licence of their own.
We take them under the project's, MPL-2.0, and record their origin here.

Many were written for bug reports by people outside the project, and
`docProps` inside some of them names an author or an application (most were
saved by Microsoft Word). We have not changed any file. If you hold rights in
one of these documents and want it out of this repository, say so and it will
be removed.

## What is here

- `docs/lo-<id>.docx` where `<id>` is the first 16 hex digits of the file's SHA-256.
- `manifest.tsv`: for each, the id, its path in LibreOffice core, the commit, and
  the bug id read from the file name (`tdf`, `fdo`, `bnc` ...), where it has one.
- `SHA256SUMS` of `docs/`.

They are a separate set from the 756 documents of `test/corpus/docx/docs`: scores
for them are reported on their own and are not part of the official mean.

## How they were chosen

All 2,163 `sw/qa/**/*.docx` of that commit were fetched into
`~/.cache/starling/docx-lo` (a shallow, blobless, sparse clone); 2,121 are unique by
content, and none is byte-identical to a document in `test/corpus/docx/docs`.
Then, with `random.seed(20261030)` and in this order: every `sw/qa/extras/layout`
document, then seeded draws from `extras/ooxmlimport` and `core`, then
`extras/ooxmlexport` for any left to fill (none were needed). Left out first:
files whose content duplicates another, files that do not open as a zip,
`/fail/` folders, files with embedded fonts, and anything over 300 KB.

## Original paths

| id | path in LibreOffice core (commit c0ade982f09c) | bug |
|---|---|---|
| `lo-b7c1b8df1d85ac9c` | `sw/qa/core/data/ooxml/pass/fdo63164-1.docx` | fdo63164 |
| `lo-e8e5db45b18c26d3` | `sw/qa/core/data/ooxml/pass/fdo78885.docx` | fdo78885 |
| `lo-5afd43f95bc8c30e` | `sw/qa/core/data/ooxml/pass/liststyle-gridbefore.docx` | - |
| `lo-7c394e05fb457361` | `sw/qa/core/data/ooxml/pass/tdf96749.docx` | tdf96749 |
| `lo-15c5d6cd73194ea7` | `sw/qa/core/doc/data/bad-heading-indent.docx` | - |
| `lo-662686b2a0fc83d4` | `sw/qa/core/doc/data/del-then-format-own.docx` | - |
| `lo-73312d3df49b7adc` | `sw/qa/core/doc/data/edit-list-autofmt.docx` | - |
| `lo-c8c597fadbf024cf` | `sw/qa/core/doc/data/fmt-twice.docx` | - |
| `lo-9aa6b2d9cb938996` | `sw/qa/core/doc/data/ins-then-format-self.docx` | - |
| `lo-b3c44892eb2ed109` | `sw/qa/core/docnode/data/tdf150086.docx` | tdf150086 |
| `lo-6f698ba267fcad6b` | `sw/qa/core/draw/data/textbox-undo-ordnum.docx` | - |
| `lo-f83b3d39650b0275` | `sw/qa/core/fields/data/styleref-flags.docx` | - |
| `lo-33cd23d8d7f3872f` | `sw/qa/core/fields/data/tdf86790.docx` | tdf86790 |
| `lo-4dd08ddc036ffd90` | `sw/qa/core/header_footer/data/SimpleFirst.docx` | - |
| `lo-6886db4a2c87ad41` | `sw/qa/core/header_footer/data/bnc875718.docx` | bnc875718 |
| `lo-e13de6d762385ae8` | `sw/qa/core/header_footer/data/fdo65655.docx` | fdo65655 |
| `lo-f6ecbe857d75230f` | `sw/qa/core/header_footer/data/n750935.docx` | n750935 |
| `lo-1a09ce5277813d9f` | `sw/qa/core/header_footer/data/tdf135216_evenOddFooter.docx` | tdf135216 |
| `lo-01d7b0e5bb4e9c90` | `sw/qa/core/header_footer/data/tdf69635.docx` | tdf69635 |
| `lo-5897b12e808dd487` | `sw/qa/core/layout/data/double-border-horizontal.docx` | - |
| `lo-544bbcb9d9a5ccb6` | `sw/qa/core/layout/data/floattable-anchor-keep-with-next.docx` | - |
| `lo-00253c627e5adbdf` | `sw/qa/core/layout/data/floattable-compat14.docx` | - |
| `lo-015dbec5c738261f` | `sw/qa/core/layout/data/floattable-del-empty.docx` | - |
| `lo-931c88e9c1b4d0eb` | `sw/qa/core/layout/data/floattable-footer-2rows.docx` | - |
| `lo-a48482e7b65814c7` | `sw/qa/core/layout/data/floattable-in-text-section.docx` | - |
| `lo-db7394160ea7b5d3` | `sw/qa/core/layout/data/floattable-model-position-for-view-point-correction.docx` | - |
| `lo-7fd81082dbbfc2e1` | `sw/qa/core/layout/data/floattable-negative-height.docx` | - |
| `lo-3b33e2957c31ac84` | `sw/qa/core/layout/data/floattable-next-leaf-in-section.docx` | - |
| `lo-c83735dc8ae55b32` | `sw/qa/core/layout/data/floattable-rowsplit.docx` | - |
| `lo-c8e4ecd86afc61bb` | `sw/qa/core/layout/data/floattable-table-row-keep.docx` | - |
| `lo-c98d1eaf98c6215d` | `sw/qa/core/layout/data/floattable-widow.docx` | - |
| `lo-5c28b8d5b2bb5777` | `sw/qa/core/layout/data/header-textbox.docx` | - |
| `lo-d11a272c48132fb9` | `sw/qa/core/layout/data/ignore-top-margin.docx` | - |
| `lo-bf8f329792bd885c` | `sw/qa/core/layout/data/rtl-table.docx` | - |
| `lo-a2845c6a21857ea9` | `sw/qa/core/layout/data/tdf128195.docx` | tdf128195 |
| `lo-42fdd5481f31224e` | `sw/qa/core/layout/data/vmerge-cell-border.docx` | - |
| `lo-1fd6c41b42627478` | `sw/qa/core/objectpositioning/data/bottom-margin-with-footer.docx` | - |
| `lo-8cdeaea8d69a43b8` | `sw/qa/core/objectpositioning/data/do-not-capture-draw-objs-draw-obj-no-capture.docx` | - |
| `lo-e07d5e6dd138f16d` | `sw/qa/core/text/data/floattable-bad-fly-pos.docx` | - |
| `lo-d63aee2d95ce9e92` | `sw/qa/core/text/data/floattable-leftover-para-portion.docx` | - |
| `lo-55c89a76860d37c6` | `sw/qa/core/text/data/floattable-overlap.docx` | - |
| `lo-cf2ad77e4308cf76` | `sw/qa/core/text/data/floattable-wrap-empty-para.docx` | - |
| `lo-fc75bd78d5cbd5e5` | `sw/qa/core/text/data/redline-image-inline.docx` | - |
| `lo-9cce40f917a7cae1` | `sw/qa/core/text/data/tdf43100_tdf120715_cursorOnSpacesOverMargin.docx` | tdf43100 |
| `lo-8bd99b19c746d5e3` | `sw/qa/core/undo/data/textbox-cut-save.docx` | - |
| `lo-e1104febe4508f96` | `sw/qa/core/unocore/data/floattable-split.docx` | - |
| `lo-f2ca6bfa11e6819b` | `sw/qa/core/unocore/data/format-char-style-change.docx` | - |
| `lo-0770373f9fd08d76` | `sw/qa/extras/layout/data/CT-formatted-deletion.docx` | - |
| `lo-e643d1ee983d40a7` | `sw/qa/extras/layout/data/Cool15691_headerTextWrapsAroundImage.docx` | - |
| `lo-9181670262a2714c` | `sw/qa/extras/layout/data/Cool15691_headerTextWrapsAroundImageLargest.docx` | - |
| `lo-133254f02eb8a8a9` | `sw/qa/extras/layout/data/Cool15942_tableSplitRowReformat.docx` | - |
| `lo-43795e41325cdd0b` | `sw/qa/extras/layout/data/Cool16066_addRowsUnderOmittedHeading.docx` | - |
| `lo-eb12e7d4ce90ffa6` | `sw/qa/extras/layout/data/fdo43573-2-min.docx` | fdo43573 |
| `lo-158005c960c26f00` | `sw/qa/extras/layout/data/fdo48718-1.docx` | fdo48718 |
| `lo-cf2d6d4a0d91557e` | `sw/qa/extras/layout/data/fld-in-tbl.docx` | - |
| `lo-5e49366b936f8112` | `sw/qa/extras/layout/data/floattable-center-inline-overlap.docx` | - |
| `lo-d97ebfb1db12029c` | `sw/qa/extras/layout/data/floattable-center-shift-down.docx` | - |
| `lo-9f8da60b69cc6d61` | `sw/qa/extras/layout/data/floattable-footer-object-nofit.docx` | - |
| `lo-2d0cbd065a6578a0` | `sw/qa/extras/layout/data/floattable-footer-object.docx` | - |
| `lo-baa979feef0a9c26` | `sw/qa/extras/layout/data/footer-nowrap-object.docx` | - |
| `lo-795d4603e8eaa5cc` | `sw/qa/extras/layout/data/hidden-para-separator.docx` | - |
| `lo-ffef711a9531d47d` | `sw/qa/extras/layout/data/inline-textbox-position.docx` | - |
| `lo-a14e916b96437b8e` | `sw/qa/extras/layout/data/legend-itemorder-min.docx` | - |
| `lo-488c442dafc62944` | `sw/qa/extras/layout/data/long_legendentry.docx` | - |
| `lo-ec231ad7c5f06e26` | `sw/qa/extras/layout/data/merge_hidden_redline.docx` | - |
| `lo-f391267c751309b6` | `sw/qa/extras/layout/data/outside_long_data_label.docx` | - |
| `lo-f1cc2329dc3ab533` | `sw/qa/extras/layout/data/sdt+framePr.docx` | - |
| `lo-ff3b52d1090fe293` | `sw/qa/extras/layout/data/shape-anchored-in-follow.docx` | - |
| `lo-686a8dc91f44bd72` | `sw/qa/extras/layout/data/table-style-contextual-spacing-rows-before.docx` | - |
| `lo-82511cfe795743b3` | `sw/qa/extras/layout/data/table-style-contextual-spacing-rows.docx` | - |
| `lo-2eb00a7323ad38ca` | `sw/qa/extras/layout/data/tdf104797.docx` | tdf104797 |
| `lo-08b61fb0c5d16c56` | `sw/qa/extras/layout/data/tdf106153.docx` | tdf106153 |
| `lo-af63e15520c69cdd` | `sw/qa/extras/layout/data/tdf109077.docx` | tdf109077 |
| `lo-dcf44597d5537f5f` | `sw/qa/extras/layout/data/tdf109137.docx` | tdf109137 |
| `lo-c72c161741e48adb` | `sw/qa/extras/layout/data/tdf112290.docx` | tdf112290 |
| `lo-2c49220535df2f3c` | `sw/qa/extras/layout/data/tdf115094.docx` | tdf115094 |
| `lo-452c2f0f81d5c4ac` | `sw/qa/extras/layout/data/tdf115630.docx` | tdf115630 |
| `lo-9864ba48bc94c73a` | `sw/qa/extras/layout/data/tdf116256.docx` | tdf116256 |
| `lo-df32fb8074901671` | `sw/qa/extras/layout/data/tdf116486.docx` | tdf116486 |
| `lo-2ce807533a6650bb` | `sw/qa/extras/layout/data/tdf116925.docx` | tdf116925 |
| `lo-92110660239e9570` | `sw/qa/extras/layout/data/tdf117028.docx` | tdf117028 |
| `lo-32545a25c2a04e6c` | `sw/qa/extras/layout/data/tdf117188.docx` | tdf117188 |
| `lo-112dd44acc68e5c9` | `sw/qa/extras/layout/data/tdf117923.docx` | tdf117923 |
| `lo-c6cd222fb0e62252` | `sw/qa/extras/layout/data/tdf117982.docx` | tdf117982 |
| `lo-a594fa6b751ec5bb` | `sw/qa/extras/layout/data/tdf119908_smart_hyphenation.docx` | tdf119908 |
| `lo-0df0276da963593e` | `sw/qa/extras/layout/data/tdf122014.docx` | tdf122014 |
| `lo-83f286ac303f77e2` | `sw/qa/extras/layout/data/tdf122225.docx` | tdf122225 |
| `lo-a0aac2492a3897cb` | `sw/qa/extras/layout/data/tdf122878.docx` | tdf122878 |
| `lo-d88152cce1e2574c` | `sw/qa/extras/layout/data/tdf123163-1.docx` | tdf123163 |
| `lo-3a0ca937b73d8486` | `sw/qa/extras/layout/data/tdf123651.docx` | tdf123651 |
| `lo-ddcb14156e457418` | `sw/qa/extras/layout/data/tdf124261.docx` | tdf124261 |
| `lo-35ae94b3462d7d47` | `sw/qa/extras/layout/data/tdf124423.docx` | tdf124423 |
| `lo-db00fd9f4baaecb1` | `sw/qa/extras/layout/data/tdf124600.docx` | tdf124600 |
| `lo-0725bffd5ff3b783` | `sw/qa/extras/layout/data/tdf125300.docx` | tdf125300 |
| `lo-97bce3f6742b28e2` | `sw/qa/extras/layout/data/tdf125893.docx` | tdf125893 |
| `lo-a994ad5cb89686b4` | `sw/qa/extras/layout/data/tdf126244.docx` | tdf126244 |
| `lo-075bce95a4e8fd4c` | `sw/qa/extras/layout/data/tdf127118.docx` | tdf127118 |
| `lo-406a95f2f0155da8` | `sw/qa/extras/layout/data/tdf128198-1.docx` | tdf128198 |
| `lo-9851fe4d31660681` | `sw/qa/extras/layout/data/tdf128399.docx` | tdf128399 |
| `lo-8ab44df57b3960fe` | `sw/qa/extras/layout/data/tdf128959.docx` | tdf128959 |
| `lo-bb46946d1eb8e6d2` | `sw/qa/extras/layout/data/tdf128996.docx` | tdf128996 |
| `lo-fc0b25c54dbc0357` | `sw/qa/extras/layout/data/tdf129054.docx` | tdf129054 |
| `lo-3682890592f43f57` | `sw/qa/extras/layout/data/tdf129095.docx` | tdf129095 |
| `lo-e5a02eb47a3b76ed` | `sw/qa/extras/layout/data/tdf130031.docx` | tdf130031 |
| `lo-1daff8198548c536` | `sw/qa/extras/layout/data/tdf130088.docx` | tdf130088 |
| `lo-60124a3f72f51c85` | `sw/qa/extras/layout/data/tdf130380.docx` | tdf130380 |
| `lo-28bd89305cbe1f1b` | `sw/qa/extras/layout/data/tdf130969.docx` | tdf130969 |
| `lo-1e8fa600080a965c` | `sw/qa/extras/layout/data/tdf132956.docx` | tdf132956 |
| `lo-6b6ece9ced040abd` | `sw/qa/extras/layout/data/tdf134146.docx` | tdf134146 |
| `lo-413892fe7e9149b2` | `sw/qa/extras/layout/data/tdf134235.docx` | tdf134235 |
| `lo-2adcf9660f1d164d` | `sw/qa/extras/layout/data/tdf134277.docx` | tdf134277 |
| `lo-fd73bf5635f4e2b4` | `sw/qa/extras/layout/data/tdf134463.docx` | tdf134463 |
| `lo-c7a83a5aaff1a7b6` | `sw/qa/extras/layout/data/tdf134659.docx` | tdf134659 |
| `lo-948cd424ae59cb4e` | `sw/qa/extras/layout/data/tdf134676.docx` | tdf134676 |
| `lo-e85b5b42ae84c1db` | `sw/qa/extras/layout/data/tdf134685.docx` | tdf134685 |
| `lo-73f1dccc52f265e1` | `sw/qa/extras/layout/data/tdf134866.docx` | tdf134866 |
| `lo-f860132614b4f586` | `sw/qa/extras/layout/data/tdf135035.docx` | tdf135035 |
| `lo-9e88222d00168d79` | `sw/qa/extras/layout/data/tdf136061.docx` | tdf136061 |
| `lo-58cba335306cd1f2` | `sw/qa/extras/layout/data/tdf136588.docx` | tdf136588 |
| `lo-130300dfcaef4ee9` | `sw/qa/extras/layout/data/tdf136613.docx` | tdf136613 |
| `lo-0a475ed1d03af9c8` | `sw/qa/extras/layout/data/tdf137025.docx` | tdf137025 |
| `lo-f9b9a8fc47c97aa6` | `sw/qa/extras/layout/data/tdf137116.docx` | tdf137116 |
| `lo-b9d70b44da707ecb` | `sw/qa/extras/layout/data/tdf137154.docx` | tdf137154 |
| `lo-36398db3d4b267fe` | `sw/qa/extras/layout/data/tdf138018.docx` | tdf138018 |
| `lo-00895ac5d8819010` | `sw/qa/extras/layout/data/tdf138465min.docx` | tdf138465 |
| `lo-1e6077df6cdf94ee` | `sw/qa/extras/layout/data/tdf138773.docx` | tdf138773 |
| `lo-697c23759d8d885f` | `sw/qa/extras/layout/data/tdf138782.docx` | tdf138782 |
| `lo-9749f2b54199da9c` | `sw/qa/extras/layout/data/tdf139336_ColumnsWithFootnoteDoNotOccupyEntirePage.docx` | tdf139336 |
| `lo-3cf1f018c80b79dd` | `sw/qa/extras/layout/data/tdf141220.docx` | tdf141220 |
| `lo-e8c1ae371214f133` | `sw/qa/extras/layout/data/tdf147485-forcepoint.docx` | tdf147485 |
| `lo-be40d67a5e6f7109` | `sw/qa/extras/layout/data/tdf149711.docx` | tdf149711 |
| `lo-e6dce9d6fbaa479a` | `sw/qa/extras/layout/data/tdf150200.docx` | tdf150200 |
| `lo-1c56bb13b7320218` | `sw/qa/extras/layout/data/tdf150438.docx` | tdf150438 |
| `lo-20ac0c45f4edb6d8` | `sw/qa/extras/layout/data/tdf151954.docx` | tdf151954 |
| `lo-415c239851604a5b` | `sw/qa/extras/layout/data/tdf152298.docx` | tdf152298 |
| `lo-27918bf0c3edb5ae` | `sw/qa/extras/layout/data/tdf152983-1-min.docx` | tdf152983 |
| `lo-11ad5a950bc534cc` | `sw/qa/extras/layout/data/tdf153136.docx` | tdf153136 |
| `lo-5b86b731b5cf66b3` | `sw/qa/extras/layout/data/tdf155229_row_height_at_least.docx` | tdf155229 |
| `lo-ee07437e238f2a79` | `sw/qa/extras/layout/data/tdf157596_paragraph_numbering.docx` | tdf157596 |
| `lo-4ef2ff3c10c1d468` | `sw/qa/extras/layout/data/tdf157628.docx` | tdf157628 |
| `lo-4dc8da496a8b5ec3` | `sw/qa/extras/layout/data/tdf161718.docx` | tdf161718 |
| `lo-93d26fdd06b50f85` | `sw/qa/extras/layout/data/tdf163149.docx` | tdf163149 |
| `lo-27446c663903fb83` | `sw/qa/extras/layout/data/tdf164499.docx` | tdf164499 |
| `lo-12ec4f1914cb562b` | `sw/qa/extras/layout/data/tdf164903.docx` | tdf164903 |
| `lo-9c6cc479ac7525b8` | `sw/qa/extras/layout/data/tdf164905.docx` | tdf164905 |
| `lo-fe125fc7d87daace` | `sw/qa/extras/layout/data/tdf164907_rowHeightAtLeast.docx` | tdf164907 |
| `lo-396f5587c99de02a` | `sw/qa/extras/layout/data/tdf167202_footnote.docx` | tdf167202 |
| `lo-b41a6e917e2bfc95` | `sw/qa/extras/layout/data/tdf167526.docx` | tdf167526 |
| `lo-7cba90194d9b9eab` | `sw/qa/extras/layout/data/tdf167540.docx` | tdf167540 |
| `lo-e23d74c93f95f26a` | `sw/qa/extras/layout/data/tdf168777-blank-before-fly.docx` | tdf168777 |
| `lo-148591d55e08ca3c` | `sw/qa/extras/layout/data/tdf170381-split-float-table-in-float-table.docx` | tdf170381 |
| `lo-1e0077c34b69d826` | `sw/qa/extras/layout/data/tdf170381-split-float-table-in-normal-table.docx` | tdf170381 |
| `lo-496593e53af2b979` | `sw/qa/extras/layout/data/tdf170477.docx` | tdf170477 |
| `lo-a593374f19283b06` | `sw/qa/extras/layout/data/tdf170620.docx` | tdf170620 |
| `lo-e30957810e467cc8` | `sw/qa/extras/layout/data/tdf170630.docx` | tdf170630 |
| `lo-972bbdc062ee51dd` | `sw/qa/extras/layout/data/tdf170846_1.docx` | tdf170846 |
| `lo-011c6ecd8b48cc5f` | `sw/qa/extras/layout/data/tdf170846_2.docx` | tdf170846 |
| `lo-a9a1991c0217da35` | `sw/qa/extras/layout/data/tdf171708.docx` | tdf171708 |
| `lo-47598455d65caba8` | `sw/qa/extras/layout/data/tdf172156.docx` | tdf172156 |
| `lo-aa886326eaa90766` | `sw/qa/extras/layout/data/tdf64222.docx` | tdf64222 |
| `lo-52da6bc61ec7ff55` | `sw/qa/extras/layout/data/tdf69647_text.docx` | tdf69647 |
| `lo-b8d932d65599c8f4` | `sw/qa/extras/layout/data/tdf69648.docx` | tdf69648 |
| `lo-088e2078aa185701` | `sw/qa/extras/layout/data/tdf75659.docx` | tdf75659 |
| `lo-28f9b88606c18b24` | `sw/qa/extras/layout/data/tdf88496.docx` | tdf88496 |
| `lo-90484c011468a21e` | `sw/qa/extras/layout/data/testAreaChartNumberFormat.docx` | - |
| `lo-94db95acddd53f94` | `sw/qa/extras/layout/data/testHeaderImageAlignment.docx` | - |
| `lo-a1b8e9ce8ef4d1b5` | `sw/qa/extras/layout/data/writer-image-no-capture.docx` | - |
| `lo-817b02d41c5ce84c` | `sw/qa/extras/layout/data/xaxis-labelbreak.docx` | - |
| `lo-796c371e29f0b36d` | `sw/qa/extras/ooxmlimport/data/bnc779620.docx` | bnc779620 |
| `lo-520b5689a4f7e895` | `sw/qa/extras/ooxmlimport/data/btlr-frame-vml.docx` | - |
| `lo-b1f7ac3bd0b54135` | `sw/qa/extras/ooxmlimport/data/fdo75722-vml.docx` | fdo75722 |
| `lo-12baa2d971ff2e2f` | `sw/qa/extras/ooxmlimport/data/groupshape-line.docx` | - |
| `lo-83c47ec672afd0bc` | `sw/qa/extras/ooxmlimport/data/groupshape-sdt.docx` | - |
| `lo-e7d811ebad124268` | `sw/qa/extras/ooxmlimport/data/line-wps-only.docx` | - |
| `lo-57486ea9a770dc81` | `sw/qa/extras/ooxmlimport/data/n757890.docx` | n757890 |
| `lo-0b6eee77d629f43e` | `sw/qa/extras/ooxmlimport/data/n775899.docx` | n775899 |
| `lo-5f9638365a804490` | `sw/qa/extras/ooxmlimport/data/n779627.docx` | n779627 |
| `lo-38c4ff8a4cfc4129` | `sw/qa/extras/ooxmlimport/data/n820788.docx` | n820788 |
| `lo-4c748aab78206fcf` | `sw/qa/extras/ooxmlimport/data/table_width.docx` | - |
| `lo-74bd0b2f63a1ad3e` | `sw/qa/extras/ooxmlimport/data/tdf103931.docx` | tdf103931 |
| `lo-ef81aa22d9f26cbf` | `sw/qa/extras/ooxmlimport/data/tdf105975.docx` | tdf105975 |
| `lo-cf00dab763639817` | `sw/qa/extras/ooxmlimport/data/tdf119039_bad_embedded_compound.docx` | tdf119039 |
| `lo-f225432f2cbdbc6b` | `sw/qa/extras/ooxmlimport/data/tdf119200.docx` | tdf119200 |
| `lo-31b823c964f5b99b` | `sw/qa/extras/ooxmlimport/data/tdf120548.docx` | tdf120548 |
| `lo-9d2d78c160d28ea5` | `sw/qa/extras/ooxmlimport/data/tdf121440.docx` | tdf121440 |
| `lo-40949e852ad9c2fe` | `sw/qa/extras/ooxmlimport/data/tdf124398.docx` | tdf124398 |
| `lo-7e277da186a9d993` | `sw/qa/extras/ooxmlimport/data/tdf124670.docx` | tdf124670 |
| `lo-43ffd8cbb3d8763b` | `sw/qa/extras/ooxmlimport/data/tdf125038.docx` | tdf125038 |
| `lo-6a9976757ed67b69` | `sw/qa/extras/ooxmlimport/data/tdf126426.docx` | tdf126426 |
| `lo-12398162af15bed3` | `sw/qa/extras/ooxmlimport/data/tdf128076.docx` | tdf128076 |
| `lo-ccca8bf3eae9ede4` | `sw/qa/extras/ooxmlimport/data/tdf129659.docx` | tdf129659 |
| `lo-24edac1633bccd6d` | `sw/qa/extras/ooxmlimport/data/tdf159897_broken_link.docx` | tdf159897 |
| `lo-7e788bd74ab138af` | `sw/qa/extras/ooxmlimport/data/tdf169843.docx` | tdf169843 |
| `lo-d04a7466a1145dd8` | `sw/qa/extras/ooxmlimport/data/tdf170236.docx` | tdf170236 |
| `lo-5c8f35c7427d653a` | `sw/qa/extras/ooxmlimport/data/tdf43017.docx` | tdf43017 |
| `lo-896eea1d8f4d6bd1` | `sw/qa/extras/ooxmlimport/data/tdf95755.docx` | tdf95755 |
| `lo-93dbabf897db0eaa` | `sw/qa/extras/ooxmlimport/data/text-copy.docx` | - |
| `lo-4729718d131f088e` | `sw/qa/extras/ooxmlimport/data/textbox-wps-only.docx` | - |
| `lo-a07c5feb2f28fb6a` | `sw/qa/extras/ooxmlimport/data/unbalanced-columns-compat.docx` | - |
| `lo-cef1adeff9c7d79b` | `sw/qa/extras/ooxmlimport/data/xml_space.docx` | - |
