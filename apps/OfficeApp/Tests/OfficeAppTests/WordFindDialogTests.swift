// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-ED-2: Writer's Find and Replace dialog (tabs, Special, Format) and Go To.
final class WordFindDialogTests: XCTestCase {
    private func shell(_ texts: [String]) -> (WidgetTester, OfficeShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 900))
        let st = ui.state(OfficeShellState.self)!
        let c = st.session.controller
        for (i, t) in texts.enumerated() {
            if i > 0 { c.insertParagraphBreak() }
            c.insertText(t)
        }
        return (ui, st)
    }

    /// Go To on paragraphs, sections, headings, tables and bookmarks: a number, +n/-n, Next and Previous.
    func testGoToTargets() throws {
        var doc = RichDocument(paragraphs: ["a", "b", "c", "d", "e"].map { RichParagraph(text: $0) })
        doc.paragraphs[1].style.sectionXML = "<w:sectPr/>"
        doc.paragraphs[3].style.sectionXML = "<w:sectPr/>"
        let c = RichDocumentController(document: doc)
        XCTAssertNil(c.goTo(.section, "3"))
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: 4, offset: 0))
        XCTAssertNil(c.goTo(.section, "-1"))
        XCTAssertEqual(c.selection.focus.paragraph, 2)
        XCTAssertNil(c.goTo(.section, "", step: -1))
        XCTAssertEqual(c.selection.focus.paragraph, 0)
        XCTAssertNotNil(c.goTo(.section, "", step: -1), "no previous section")
        XCTAssertNil(c.goTo(.section, "", step: 1))
        XCTAssertEqual(c.selection.focus.paragraph, 2)
        XCTAssertNil(c.goTo(.section, "9"), "past the end goes to the last, as Word")
        XCTAssertEqual(c.selection.focus.paragraph, 4)
        XCTAssertNotNil(c.goTo(.section, "x"))

        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 2, offset: 1), extend: true)
        XCTAssertTrue(c.addBookmark("Here"))
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertNil(c.goTo(.bookmark, "here"))
        XCTAssertEqual(c.selection.start, RichPosition(paragraph: 2, offset: 0))
        XCTAssertNotNil(c.goTo(.bookmark, "Nowhere"))
        XCTAssertNotNil(c.goTo(.heading, "1"), "no headings")

        // Page and Line come from the laid-out lines.
        let lines: [(page: Int, at: RichPosition)] = [(1, RichPosition(paragraph: 0, offset: 0)), (1, RichPosition(paragraph: 1, offset: 0)),
                                                      (2, RichPosition(paragraph: 2, offset: 0)), (2, RichPosition(paragraph: 3, offset: 0))]
        XCTAssertNil(c.goTo(.page, "2", lines: lines))
        XCTAssertEqual(c.selection.focus.paragraph, 2)
        XCTAssertNil(c.goTo(.line, "2", lines: lines))
        XCTAssertEqual(c.selection.focus.paragraph, 1)
        XCTAssertNil(c.goTo(.line, "+2", lines: lines))
        XCTAssertEqual(c.selection.focus.paragraph, 3)
    }

    /// The real layout's line starts: each paragraph's first line, all on page 1 for a short document.
    func testLineStartsFromTheLayout() throws {
        let (_, st) = shell(["one", "two", "three"])
        let s = st.session
        let lines = PdfExport.lineStarts(s.controller.document, pageSetup: s.pageSetup, theme: s.theme)
        XCTAssertEqual(lines.map(\.at.paragraph), [0, 1, 2])
        XCTAssertEqual(Set(lines.map(\.page)), [1])
    }

    /// F5's tab: Go To with Word's kinds; typing a number and Go To moves the caret, and the dialog stays.
    func testGoToTab() throws {
        let (ui, st) = shell(["a", "b", "c"])
        let c = st.session.controller
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        st._openFindDialog(tab: 2); ui.pump()
        let d = try XCTUnwrap(ui.state(FindReplaceDialogState.self))
        XCTAssertEqual(d.tab, 2)
        XCTAssertTrue(ui.has(id: "fr-goto-what"))
        XCTAssertTrue(ui.has(text: "Enter page number"))
        d.setGoToWhat(.line); ui.pump()
        XCTAssertTrue(ui.has(text: "Enter line number"))
        XCTAssertTrue(ui.tap(id: "fr-goto")); ui.type("3")
        XCTAssertTrue(ui.tap(id: "fr-goto-go")); ui.pump()
        XCTAssertEqual(c.selection.focus.paragraph, 2)
        XCTAssertTrue(ui.has(id: "fr-goto"), "Word keeps the dialog open")
        XCTAssertTrue(ui.tap(id: "fr-tab-find")); ui.pump()
        XCTAssertFalse(ui.has(id: "fr-replace"), "the Find tab has no Replace with")
        XCTAssertTrue(ui.has(id: "fr-prefix"))
        // Word keeps the dialog one size on its three tabs: the title does not move.
        let title = ui.centre(ofText: "Find and Replace")
        for t in [1, 2, 0] {
            d.setTab(t); ui.pump()
            XCTAssertEqual(ui.centre(ofText: "Find and Replace"), title, "tab \(t)")
        }
    }

    /// Special puts the code in the box last clicked; Format shows under its box and reaches the
    /// document: find bold "x", replace with italic "y".
    func testSpecialAndFormat() throws {
        let (ui, st) = shell(["x x"])
        let c = st.session.controller
        c.moveTo(RichPosition(paragraph: 0, offset: 2), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: true)
        c.toggleBold()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        st._openFindDialog(tab: 1); ui.pump()
        let d = try XCTUnwrap(ui.state(FindReplaceDialogState.self))
        let title = ui.centre(ofText: "Find and Replace")
        XCTAssertTrue(ui.tap(id: "fr-special")); ui.pump()
        XCTAssertTrue(ui.has(text: "Any Digit"), "Find what offers the search codes")
        XCTAssertEqual(ui.centre(ofText: "Find and Replace"), title, "the Special menu does not move the dialog")
        XCTAssertTrue(ui.tap(id: "fr-sp-^t")); ui.pump()
        XCTAssertTrue(ui.tap(id: "fr-replace")); ui.pump()
        XCTAssertEqual(d.target, 1)
        XCTAssertTrue(ui.tap(id: "fr-special")); ui.pump()
        XCTAssertFalse(ui.has(text: "Any Digit"), "Replace with does not")
        XCTAssertTrue(ui.has(text: "Find What Text"))
        XCTAssertTrue(ui.tap(id: "fr-sp-^&")); ui.pump()
        XCTAssertEqual(d.queryText, "^t")
        XCTAssertEqual(d.replacementText, "^&")

        // Now the real query: "x" bold, replaced with "y" italic.
        d.setTarget(0); d.setFormat(FindFormat(bold: true))
        d.setTarget(1); d.setFormat(FindFormat(bold: false, italic: true)); ui.pump()
        XCTAssertTrue(ui.has(id: "fr-format-find")); XCTAssertTrue(ui.has(id: "fr-format-replace"))
        XCTAssertTrue(ui.has(text: "Format: Font: Bold"))
        XCTAssertTrue(ui.tap(id: "fr-format")); ui.pump()
        XCTAssertTrue(ui.has(id: "fr-fmt-italic"))
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        d.queryText = "x"; d.replacementText = "y"
        d.replaceEvery(); ui.pump()
        XCTAssertEqual(c.document.paragraphs[0].text, "x y")
        XCTAssertEqual(c.document.paragraphs[0].style(at: 3).italic, true)
        XCTAssertEqual(c.document.paragraphs[0].style(at: 3).bold, false)
        XCTAssertTrue(ui.has(text: "Replaced 1"))
    }

    /// Replace with refuses a search-only code, as Word does.
    func testReplaceWithRefusesSearchCodes() throws {
        let (ui, st) = shell(["a"])
        st._openFindDialog(tab: 1); ui.pump()
        let d = try XCTUnwrap(ui.state(FindReplaceDialogState.self))
        d.queryText = "a"; d.replacementText = "^#"
        d.replaceEvery(); ui.pump()
        XCTAssertEqual(st.session.controller.document.paragraphs[0].text, "a")
        XCTAssertFalse(d.status.isEmpty)
    }

    /// Ctrl+G is Go To on Windows and Linux (Word for Windows); Cmd+G stays Find Next on the Mac (Mac Word).
    func testPrimaryGPerPlatform() throws {
        XCTAssertEqual(PrimaryG.of(mac: false, shift: false), .goTo)
        XCTAssertEqual(PrimaryG.of(mac: true, shift: false), .findNext)
        XCTAssertEqual(PrimaryG.of(mac: true, shift: true), .findPrevious)
        XCTAssertEqual(PrimaryG.of(mac: false, shift: true), .findPrevious)
        // This platform's own chord, through the shell.
        let (ui, st) = shell(["a", "b"])
        let key = KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0x67, character: nil, synthesized: false)
        XCTAssertTrue(st._shortcut(key, [.primary])); ui.pump()
        let d = ui.state(FindReplaceDialogState.self)
        if PrimaryG.platformIsMac {
            XCTAssertNil(d, "Cmd+G is Find Next")
        } else {
            XCTAssertEqual(d?.tab, 2, "Ctrl+G opens Go To")
        }
    }
}
