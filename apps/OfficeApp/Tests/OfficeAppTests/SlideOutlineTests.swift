import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
import OfficeText

final class SlideOutlineTests: XCTestCase {
    private func deckWith(_ rows: [(String, [String])]) -> DeckController {
        let deck = DeckController()
        while deck.slides.count < rows.count { _ = deck.addSlide() }
        for (i, row) in rows.enumerated() {
            let slide = deck.slides[i]
            let title = slide.shapes.first { $0.role == .title || $0.role == .ctrTitle }!
            title.text!.insertText(row.0)
            if let body = slide.shapes.first(where: { $0.role == .body || $0.role == .subTitle }) {
                body.text!.insertText(row.1.joined(separator: "\n"))
            }
        }
        return deck
    }

    func testEntriesListTitleAndBody() {
        let deck = deckWith([("One", ["a", "b"]), ("Two", [])])
        let e = deck.outlineEntries
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].title, "One")
        XCTAssertEqual(e[0].body.map(\.text), ["a", "b"])
        XCTAssertEqual(e[0].body.map(\.level), [1, 1])
    }

    func testDocumentRoundTrip() {
        let entries = [OutlineEntry(title: "One", body: [OutlineLine(level: 1, text: "a"), OutlineLine(level: 2, text: "deep")]),
                       OutlineEntry(title: "Two")]
        XCTAssertEqual(Outline.entries(from: Outline.document(entries)), entries)
    }

    func testEditingOneTitleKeepsTheOtherSlides() {
        let deck = deckWith([("One", ["a"]), ("Two", ["b"]), ("Three", ["c"])])
        let ids = deck.slides.map(\.id)
        var e = deck.outlineEntries
        e[1].title = "Two!"
        deck.applyOutline(e)
        XCTAssertEqual(deck.slides.map(\.id), ids)
        XCTAssertEqual(deck.outlineEntries[1].title, "Two!")
    }

    func testANewTitleLineMakesANewSlideAndDeletingOneRemovesIt() {
        let deck = deckWith([("One", ["a"]), ("Two", ["b"])])
        let ids = deck.slides.map(\.id)
        var e = deck.outlineEntries
        e.insert(OutlineEntry(title: "Between", body: [OutlineLine(level: 1, text: "x")]), at: 1)
        deck.applyOutline(e)
        XCTAssertEqual(deck.slides.count, 3)
        XCTAssertEqual(deck.slides[0].id, ids[0]); XCTAssertEqual(deck.slides[2].id, ids[1])
        XCTAssertEqual(deck.outlineEntries[1].title, "Between")
        XCTAssertNotNil(deck.outlineEntries[1].slideId)
        e = deck.outlineEntries
        e.remove(at: 0)
        deck.applyOutline(e)
        XCTAssertEqual(deck.slides.map(\.id).last, ids[1])
        XCTAssertEqual(deck.slides.count, 2)
    }

    func testSlidesWithTheSameTitleAreToldApartByTheirIds() {
        let deck = deckWith([("Title", ["first"]), ("Title", ["second"]), ("Title", ["third"]), ("End", [])])
        let ids = deck.slides.map(\.id)
        // Edit the middle "Title" (through the outline document, as typing does) and move the third before the first.
        var doc = Outline.document(deck.outlineEntries)
        XCTAssertEqual(Outline.entries(from: doc).map(\.slideId), ids.map { Optional($0) })
        var e = Outline.entries(from: doc)
        e[1].body[0].text = "second, edited"
        e.insert(e.remove(at: 2), at: 0)
        doc = Outline.document(e)
        deck.applyOutline(Outline.entries(from: doc))
        XCTAssertEqual(deck.slides.map(\.id), [ids[2], ids[0], ids[1], ids[3]])
        XCTAssertEqual(deck.outlineEntries.map { $0.body.first?.text ?? "" }, ["third", "first", "second, edited", ""])
    }

    func testEnterCopiesATagButOnlyOneRowKeepsIt() {
        let deck = deckWith([("One", ["a"]), ("Two", ["b"])])
        let ids = deck.slides.map(\.id)
        var e = deck.outlineEntries
        // Enter after "One": a second row with the same tag and no text.
        e.insert(OutlineEntry(title: "", body: [], slideId: ids[0]), at: 1)
        deck.applyOutline(e)
        XCTAssertEqual(deck.slides.count, 3)
        XCTAssertEqual(deck.slides[0].id, ids[0])
        XCTAssertEqual(deck.slides[2].id, ids[1])
    }

    func testBodyLevelsReachTheSlideAndOneUndoStepRestores() {
        let deck = deckWith([("One", ["a", "b"])])
        var e = deck.outlineEntries
        e[0].body[1].level = 2
        deck.applyOutline(e)
        e[0].body[1].text = "bb"
        deck.applyOutline(e)   // more typing: the same undo step
        XCTAssertEqual(deck.outlineEntries[0].body.map(\.level), [1, 2])
        deck.undo()
        XCTAssertEqual(deck.outlineEntries[0].body.map(\.text), ["a", "b"])
        XCTAssertEqual(deck.outlineEntries[0].body.map(\.level), [1, 1])
    }

    func testOutlineViewReplacesTheThumbnailRailAndShowsTheTitles() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let session = try XCTUnwrap(ui.state(SlidesShellState.self)?.session)
        let deck = try XCTUnwrap(session.deck)
        XCTAssertFalse(ui.has(id: "outline.pane"))
        _ = Outline.entries(from: Outline.document(deck.outlineEntries))
        session.onSlidesOutline?(); ui.pump()
        XCTAssertTrue(ui.has(id: "outline.pane"))
        XCTAssertTrue(session.slidesOutline)
        session.onSlidesOutline?(); ui.pump()
        XCTAssertFalse(ui.has(id: "outline.pane"))
    }

    /// STARLING_OUTLINE_OUT: a real deck edited the way the Outline view edits it, saved for PowerPoint.
    func testSaveOutlineEditedDeck() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_OUTLINE_OUT"] else { throw XCTSkip("no output path") }
        let dir = "/data/corpus-cache/test/corpus/pptx/decks"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { throw XCTSkip("no corpus cache") }
        let deck = DeckController()
        var picked = ""
        for n in names.sorted() where n.hasSuffix(".pptx") {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: dir + "/" + n)), data.count < 1_500_000,
                  let (state, theme, pkg) = try? Pptx.read(data) else { continue }
            let d = DeckController()
            d.load(state, theme: theme, package: pkg)
            let en = d.outlineEntries
            let titled = en.filter { !$0.title.isEmpty }.count
            let bodied = en.filter { $0.body.count >= 2 }.count
            if en.count >= 5, en.count <= 12, titled >= en.count - 1, titled >= 5, bodied >= 3,
               !(en[1].body.isEmpty || en[2].body.isEmpty || en[3].body.isEmpty), !en[0].title.isEmpty, !en[en.count - 1].title.isEmpty {
                deck.load(state, theme: theme, package: pkg); picked = n; break
            }
        }
        guard !picked.isEmpty else { throw XCTSkip("no suitable deck") }
        var e = Outline.entries(from: Outline.document(deck.outlineEntries))
        func show(_ e: [OutlineEntry]) -> String {
            // (one step at a time: the whole chain in one expression is too much for the type checker on macOS)
            var out = ""
            for (i, x) in e.enumerated() {
                out += "\(i + 1). \(x.title)\n"
                for line in x.body {
                    let indent = String(repeating: "  ", count: line.level - 1)
                    out += "     " + indent + "- " + line.text + "\n"
                }
            }
            return out
        }
        var log = "DECK \(picked)\n\nBEFORE\n" + show(e)
        precondition(e.count >= 4)
        // 1. Enter on slide 1's title: a new slide 2 titled "Added in outline" with one body line.
        e.insert(OutlineEntry(title: "Added in outline", body: [OutlineLine(level: 1, text: "First point of the new slide")]), at: 1)
        // 2. Tab on a body line: demote the first body line of the (old) slide 2 one level.
        if let k = e[2].body.indices.first { e[2].body[k].level += 1 }
        // 3. Shift+Tab on a body line of the old slide 3: promote its first line to a title (a new slide).
        if let first = e[3].body.first {
            let rest = Array(e[3].body.dropFirst())
            e[3].body = []
            e.insert(OutlineEntry(title: first.text, body: rest), at: 4)
        }
        // 4. Delete the last title (its slide goes).
        let removed = e.removeLast().title
        // 5. Type into another title.
        e[0].title += " (edited in outline)"
        deck.applyOutline(e)
        deck.endOutlineEdit()
        log += "\nEDITS\n1. Enter after slide 1's title: new slide 2 'Added in outline'\n2. Tab: first body line of old slide 2 demoted\n3. Shift+Tab: first body line of old slide 3 promoted to its own slide\n4. Deleted the last title: '\(removed)'\n5. Typed ' (edited in outline)' into slide 1's title\n"
        log += "\nAFTER\n" + show(deck.outlineEntries)
        try Pptx.write(deck).write(to: URL(fileURLWithPath: out))
        try log.write(toFile: out + ".txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(deck.outlineEntries.map { [$0.title] + $0.body.map(\.text) }, e.map { [$0.title] + $0.body.map(\.text) })
    }

    /// Demote one line of a slide with nine levels, save, reopen: every level is where it was, the layout is unchanged,
    /// and a slide inserted in front does not take over the neighbour's place.
    func testDemoteOneLineKeepsLevelsAndLayoutThroughASave() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/layouts.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let (state, theme, pkg) = try Pptx.read(try Data(contentsOf: URL(fileURLWithPath: path)))
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        var e = deck.outlineEntries
        let at = try XCTUnwrap(e.firstIndex { $0.body.count == 9 })
        let layoutBefore = deck.slides[at].layout
        let levelsBefore = e[at].body.map(\.level)
        e.insert(OutlineEntry(title: "Added", body: [OutlineLine(level: 1, text: "x")]), at: 1)
        e[at + 1].body[0].level += 1
        deck.applyOutline(e)
        let (back, _, _) = try Pptx.read(try Pptx.write(deck))
        let again = DeckController()
        again.load(back, theme: theme, package: nil)
        let got = again.outlineEntries
        XCTAssertEqual(got.count, e.count)
        XCTAssertEqual(got[at + 1].body.map(\.level), [levelsBefore[0] + 1] + levelsBefore.dropFirst())
        XCTAssertEqual(got[at + 1].title, e[at + 1].title)
        XCTAssertEqual(deck.slides[at + 1].layout, layoutBefore)
        XCTAssertEqual(got[1].title, "Added")
    }
}
