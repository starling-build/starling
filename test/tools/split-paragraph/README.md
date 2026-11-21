# Splitting `_layoutParagraphBody` (RichLayout+Paragraph.swift)

The body is generated into `RichLayout+Paragraph+{Frame,Funcs,Body0..7}.swift` by `gen.py`: locals become fields of `_ParaFrame`,
local funcs and top-level chunks become methods. To regenerate on a newer tip (only needed if the body is ever re-merged):
1. `git show origin/main:<Paragraph.swift> > orig.swift`; dump.sh / dump2.sh are the build's own swift-frontend commands
   (from the build log) with `-dump-ast` on Paragraph.swift (ast.out) and `-dump-ast -experimental-skip-all-function-bodies` on all RichLayout files (ast2.out).
2. `python3 astfwd.py ast2.out names.txt > fwd.txt` (forwarders to RichLayout members; add `typealias _HeaderFooter = RichLayout._HeaderFooter`).
3. `FWD=fwd.txt python3 gen.py ast.out <checkout>`; then mktc.py builds a type-check command, and autoself.py inserts `self.` where the compiler asks.
4. `test/tools/split-audit.py [ref]` checks every original line is present in the split files.
Paths inside dump.sh/mktc.py are absolute to the author's checkout; adjust them.
