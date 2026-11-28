// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// W-FD-2: a table of contents made from the headings, and brought up to date. The field's instruction rides on the first
/// entry paragraph (`contentsStart`) and its end on the empty paragraph after the last entry (`contentsEnd`), the shape
/// Word writes.
public struct ContentsOptions: Equatable, Sendable {
    public var levels: Int = 3
    public var tabLeader: String? = "dot"   // nil: no leader
    public var rightAlignNumbers = true
    public var hyperlinks = true
    public var showPageNumbers = true
    /// W-FD-3: a table of figures lists the captions of this label (`\c "Figure"`) in place of the headings.
    public var caption: String? = nil
    public init() {}

    /// Word's instruction for these options.
    public var instruction: String {
        if let caption {
            var s = hyperlinks ? "TOC \\h \\z \\c \"\(caption)\"" : "TOC \\c \"\(caption)\""
            if !showPageNumbers { s += " \\n" }
            return s
        }
        var s = "TOC \\o \"1-\(levels)\""
        s += hyperlinks ? " \\h \\z \\u" : " \\u"
        if !showPageNumbers { s += " \\n" }
        return s
    }

    /// The options an existing instruction stands for.
    public init(instruction: String) {
        let parts = instruction.split(separator: " ").map(String.init)
        if let i = parts.firstIndex(of: "\\o"), i + 1 < parts.count {
            let range = parts[i + 1].filter { $0 != "\"" }.split(separator: "-")
            if let last = range.last, let n = Int(last) { levels = max(1, min(9, n)) }
        }
        if let i = parts.firstIndex(where: { $0.lowercased() == "\\c" }), i + 1 < parts.count {
            caption = parts[i + 1].filter { $0 != "\"" }
        }
        hyperlinks = parts.contains("\\h")
        showPageNumbers = !parts.contains("\\n")
    }
}

extension RichDocumentController {
    /// The paragraphs a table of contents spans, from the one holding its instruction to the one that closes it.
    public func contentsRange(containing paragraph: Int? = nil) -> Range<Int>? {
        let ps = document.paragraphs
        var k = 0
        while k < ps.count {
            if ps[k].style.contentsStart != nil {
                var e = k
                while e < ps.count, !ps[e].style.contentsEnd { e += 1 }
                let range = k ..< min(e + 1, ps.count)
                if paragraph == nil || range.contains(paragraph!) { return range }
                k = range.upperBound
            } else { k += 1 }
        }
        return nil
    }

    /// The entry paragraphs for the document's headings (outside any existing contents). `pageOf` gives the page label
    /// of a paragraph; `width` is the text width in points, where the page numbers sit.
    private func _contentsEntries(_ options: ContentsOptions, width: Double, pageOf: (Int) -> String?,
                                  skipping skip: Range<Int>?, marks: inout [Int: String]) -> [RichParagraph] {
        var taken = Set(document.paragraphs.flatMap { $0.bookmarks })
        var out: [RichParagraph] = []
        for (i, p) in document.paragraphs.enumerated() {
            if let skip, skip.contains(i) { continue }
            // (Level 0: a caption of the table of figures' label, Word's "table of figures" style.)
            let level: Int
            if let label = options.caption?.lowercased() {
                guard !p.text.isEmpty, p.runs.contains(where: { $0.style.preservedField.flatMap(Self.sequenceName)?.lowercased() == label }) else { continue }
                level = 0
            } else {
                guard let h = p.style.heading, h <= options.levels, !p.text.isEmpty else { continue }
                level = h
            }
            var name = p.bookmarks.first { $0.hasPrefix("_Toc") }
            if name == nil {
                var n = 100_000 + i
                while taken.contains("_Toc\(n)") { n += 1 }
                name = "_Toc\(n)"
                taken.insert(name!)
                marks[i] = name!
            }
            var heading = CharStyle.plain
            if options.hyperlinks { heading.link = "#" + name! }
            var text = p.text.replacingAll("\t", with: " ")
            var runs = [Run(length: text.utf16.count, style: heading)]
            if options.showPageNumbers {
                var tabStyle = CharStyle.plain
                if options.hyperlinks { tabStyle.link = "#" + name! }
                var pageStyle = tabStyle
                pageStyle.field = "PAGEREF \(name!) \\h"
                let page = pageOf(i) ?? "1"
                text += "\t" + page
                runs.append(Run(length: 1, style: tabStyle))
                runs.append(Run(length: page.utf16.count, style: pageStyle))
            }
            var style = RichParagraphStyle()
            style.named = _contentsStyle(level).id
            if options.showPageNumbers {
                var tab = TabStop(position: width, alignment: options.rightAlignNumbers ? .right : .left)
                tab.leader = options.tabLeader
                style.tabStops = [tab]
            }
            out.append(RichParagraph(text: text, runs: runs, style: style))
        }
        return out
    }

    /// Put the bookmarks the entries point at on their headings (a range over the heading text, as Word's `_Toc` marks).
    private func _markHeadings(_ marks: [Int: String]) {
        for (k, name) in marks.sorted(by: { $0.key < $1.key }) where k < document.paragraphs.count {
            var p = document.paragraphs[k]
            let used = document.paragraphs.flatMap { $0.bookmarkMarkers.map(\.id) }.compactMap { Int($0) }
            let id = String(max(400_000, (used.max() ?? 0) + 1))
            p.bookmarks.append(name)
            p.bookmarkMarkers.append(RichBookmarkMarker(id: id, name: name, offset: 0))
            p.bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: p.length))
            perform(.restoreParagraphs(k, count: 1, [p]))
        }
    }

    /// Rewrite the PAGEREF page numbers of the table spanning `range` from `pageOf` (no undo step of its own: the caller's
    /// edit holds it). Returns whether any number changed.
    @discardableResult
    private func _refreshPages(_ range: Range<Int>, pageOf: (Int) -> String?) -> Bool {
        var homes: [String: Int] = [:]
        for (k, p) in document.paragraphs.enumerated() where !range.contains(k) {
            for name in p.bookmarks where homes[name.lowercased()] == nil { homes[name.lowercased()] = k }
        }
        var changed = false
        for k in range {
            var p = document.paragraphs[k]
            var text = "", runs: [Run] = [], at = p.text.utf16.startIndex, last: String? = nil, touched = false
            for run in p.runs {
                let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                var piece = String(p.text[at ..< end]); at = end
                if let f = run.style.field, f.uppercased().hasPrefix("PAGEREF "),
                   let target = f.split(separator: " ").dropFirst().first.map({ String($0).lowercased() }),
                   let home = homes[target], let label = pageOf(home) {
                    let shown = last == f ? "" : label
                    if shown != piece { touched = true }
                    piece = shown
                }
                last = run.style.field
                guard !piece.isEmpty else { continue }
                text += piece; runs.append(Run(length: piece.utf16.count, style: run.style))
            }
            guard touched else { continue }
            p.text = text; p.runs = runs
            perform(.restoreParagraphs(k, count: 1, [p]))
            changed = true
        }
        return changed
    }

    /// With the table in place the headings sit lower: lay the document out, fill the numbers, and again while they move.
    private func _settlePages(_ range: Range<Int>, layout: ((RichDocument) -> (Int) -> String?)?) {
        guard let layout else { return }
        for _ in 0 ..< 3 { if !_refreshPages(range, pageOf: layout(document)) { break } }
    }

    /// The paragraph style of TOC level `level` (Word's "toc N"): the document's own, else a new one to add.
    private func _contentsStyle(_ level: Int) -> (id: String, new: RichNamedStyle?) {
        if level == 0 {
            if let e = document.styles.styles.first(where: { $0.name.lowercased() == "table of figures" }) { return (e.id, nil) }
            return ("TableofFigures", RichNamedStyle(id: "TableofFigures", name: "table of figures", paragraph: RichParagraphStyle(spaceAfter: 0), next: RichNamedStyle.normalId))
        }
        if let e = document.styles.styles.first(where: { $0.name.lowercased() == "toc \(level)" }) { return (e.id, nil) }
        var p = RichParagraphStyle(spaceAfter: 5)
        p.indentLeft = Double(level - 1) * 11
        return ("TOC\(level)", RichNamedStyle(id: "TOC\(level)", name: "toc \(level)", paragraph: p, next: RichNamedStyle.normalId))
    }

    /// The styles the entries need that the document lacks.
    private func _missingContentsStyles(_ entries: [RichParagraph]) -> [RichNamedStyle] {
        var out: [RichNamedStyle] = []
        for p in entries {
            guard let n = p.style.named, let level = n == "TableofFigures" ? 0 : n.hasPrefix("TOC") ? Int(n.dropFirst(3)) : nil,
                  document.styles[n] == nil, !out.contains(where: { $0.id == n }) else { continue }
            if let new = _contentsStyle(level).new { out.append(new) }
        }
        return out
    }

    /// Insert a table of contents after the caret's paragraph (in its place when that paragraph is empty). One undo step.
    /// Returns false when there are no headings to list.
    @discardableResult
    public func insertTableOfContents(_ options: ContentsOptions, width: Double, pageOf: (Int) -> String?,
                                      layout: ((RichDocument) -> (Int) -> String?)? = nil) -> Bool {
        guard !readOnly else { return false }
        var marks: [Int: String] = [:]
        var entries = _contentsEntries(options, width: width, pageOf: pageOf, skipping: contentsRange(), marks: &marks)
        guard !entries.isEmpty else { return false }
        entries[0].style.contentsStart = options.instruction
        var closing = RichParagraph(text: "", runs: [Run(length: 0, style: .plain)])
        closing.style.contentsEnd = true
        let at = document.clamped(selection.end).paragraph
        let replace = document.paragraphs[at].text.isEmpty && document.paragraphs[at].image == nil
        let missing = _missingContentsStyles(entries)
        edit {
            for m in missing { perform(.addStyle(m)) }
            _markHeadings(marks)
            // (Headings keep their index: only bookmarks changed, no paragraphs moved.)
            let insertAt = replace ? at : at + 1
            if replace { perform(.restoreParagraphs(at, count: 1, entries + [closing])) }
            else { perform(.restoreParagraphs(insertAt, count: 0, entries + [closing])) }
            if let r = contentsRange(containing: insertAt) { _settlePages(r, layout: layout) }
            moveTo(RichPosition(paragraph: insertAt, offset: 0), extend: false)
        }
        return true
    }

    /// Bring the table of contents holding the caret (or the first) up to date: the page numbers only, or the whole table
    /// (new headings, renamed ones). Returns false when there is none.
    @discardableResult
    public func updateTableOfContents(pagesOnly: Bool, width: Double, pageOf: (Int) -> String?,
                                      layout: ((RichDocument) -> (Int) -> String?)? = nil) -> Bool {
        guard !readOnly, let range = contentsRange(containing: document.clamped(selection.end).paragraph) ?? contentsRange(),
              let instruction = document.paragraphs[range.lowerBound].style.contentsStart else { return false }
        if pagesOnly {
            edit { _refreshPages(range, pageOf: pageOf); _settlePages(range, layout: layout) }
            return true
        }
        var options = ContentsOptions(instruction: instruction)
        let old = document.paragraphs[range.lowerBound ..< range.upperBound]
        if let tab = old.compactMap({ $0.style.tabStops.first }).first {
            options.tabLeader = tab.leader; options.rightAlignNumbers = tab.alignment == .right
        }
        options.showPageNumbers = old.contains { $0.runs.contains { $0.style.field?.uppercased().hasPrefix("PAGEREF ") == true } }
        var marks: [Int: String] = [:]
        var entries = _contentsEntries(options, width: width, pageOf: pageOf, skipping: range, marks: &marks)
        var closing = RichParagraph(text: "", runs: [Run(length: 0, style: .plain)])
        closing.style.contentsEnd = true
        if entries.isEmpty { entries = [] }
        else { entries[0].style.contentsStart = instruction }
        let missing = _missingContentsStyles(entries)
        edit {
            for m in missing { perform(.addStyle(m)) }
            _markHeadings(marks)
            perform(.restoreParagraphs(range.lowerBound, count: range.count, entries.isEmpty ? [closing] : entries + [closing]))
            if let r = contentsRange(containing: range.lowerBound) { _settlePages(r, layout: layout) }
            moveTo(RichPosition(paragraph: range.lowerBound, offset: 0), extend: false)
        }
        return true
    }
}
