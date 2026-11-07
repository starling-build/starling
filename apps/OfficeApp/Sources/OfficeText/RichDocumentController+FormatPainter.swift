// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// Format Painter, kept in the controller so desktop, Mac and web share it.

/// What the painter picked up: the character style at the selection and,
/// when the source included a paragraph mark (or was a bare caret), the
/// paragraph's own formatting.
public struct FormatSample: Equatable {
    public var char: CharStyle
    public var paragraph: RichParagraphStyle?
}

extension RichDocumentController {
    /// Pick up the formatting at the selection (or caret).
    public func copyFormat() -> FormatSample {
        var char = currentCharStyle
        char.link = nil
        char.note = nil; char.inlineImage = nil; char.revision = nil; char.formatChange = nil
        let a = document.clamped(selection.start), b = document.clamped(selection.end)
        let wholeParagraph = selection.isCollapsed
            || (a.paragraph != b.paragraph)
            || (a.offset == 0 && b.offset == document.paragraphs[b.paragraph].length)
        return FormatSample(char: char, paragraph: wholeParagraph ? document.paragraphs[a.paragraph].style : nil)
    }

    /// Lay `sample` over the selection. Formatting travels; hyperlinks,
    /// note marks, pictures and tracked-change marks on the target stay.
    public func pasteFormat(_ sample: FormatSample) {
        let painted = sample.char
        applyCharStyle { style in
            let (link, note, image, rev, change) = (style.link, style.note, style.inlineImage, style.revision, style.formatChange)
            style = painted
            style.link = link; style.note = note; style.inlineImage = image
            style.revision = rev; style.formatChange = change
        }
        guard let src = sample.paragraph, !selection.isCollapsed else { return }
        let a = document.clamped(selection.start), b = document.clamped(selection.end)
        let reachesMark = a.paragraph != b.paragraph || b.offset == document.paragraphs[b.paragraph].length
        guard reachesMark else { return }
        applyParagraphStyle { p in
            p.alignment = src.alignment
            p.indentLeft = src.indentLeft; p.indentRight = src.indentRight
            p.firstLineIndent = src.firstLineIndent
            p.spaceBefore = src.spaceBefore; p.spaceAfter = src.spaceAfter
            p.lineSpacing = src.lineSpacing
            p.lineHeightPoints = src.lineHeightPoints
            p.lineHeightIsMinimum = src.lineHeightIsMinimum
        }
    }

    /// A click without a drag, while painting, paints the word under it.
    public func selectWordForPainting() {
        guard selection.isCollapsed else { return }
        selectWord(at: selection.focus)
    }
}
