// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlideSectionTests: XCTestCase {
    private func _deck(_ n: Int = 6) -> DeckController {
        let deck = SlidesSample.make()
        while deck.slides.count > n { deck.deleteSlide(deck.slides.count - 1) }
        while deck.slides.count < n { deck.addSlide() }
        return deck
    }

    private func _names(_ d: DeckController) -> [String] {
        d.sections.indices.map { "\(d.sections[$0].name):\(d.slides(inSection: $0).map { $0 + 1 }.map(String.init).joined(separator: ","))" }
    }

    func testAddRenameRemoveMove() {
        let d = _deck(6)
        d.addSection(at: 2, name: "B")
        XCTAssertEqual(_names(d), ["Default Section:1,2", "B:3,4,5,6"])
        d.addSection(at: 4, name: "C")
        XCTAssertEqual(_names(d), ["Default Section:1,2", "B:3,4", "C:5,6"])
        d.renameSection(1, to: "Middle")
        d.moveSection(2, by: -1)
        XCTAssertEqual(_names(d), ["Default Section:1,2", "C:3,4", "Middle:5,6"])
        d.removeSection(1)  // C's slides join the section before
        XCTAssertEqual(_names(d), ["Default Section:1,2,3,4", "Middle:5,6"])
        d.undo()
        XCTAssertEqual(d.sections.count, 3)
        d.removeSectionAndSlides(2)
        XCTAssertEqual(d.slides.count, 4)
        d.removeAllSections()
        XCTAssertTrue(d.sections.isEmpty)
        XCTAssertTrue(d.slides.allSatisfy { $0.section == nil })
    }

    func testNewSlidesAndMovesJoinTheirNeighbours() {
        let d = _deck(4)
        d.addSection(at: 2, name: "B")
        d.select(1); d.addSlide()   // after slide 2: still in the first section
        XCTAssertEqual(_names(d), ["Default Section:1,2,3", "B:4,5"])
        d.select(3); d.duplicateSlide(3)
        XCTAssertEqual(_names(d), ["Default Section:1,2,3", "B:4,5,6"])
        d.moveSlide(0, to: 4)       // the first slide dragged into section B
        XCTAssertEqual(_names(d), ["Default Section:1,2", "B:3,4,5,6"])
    }

    func testCollapseSurvivesUndoAndSelectExpands() {
        let d = _deck(4)
        d.addSection(at: 2, name: "B")
        d.setSectionCollapsed(1, true)
        XCTAssertTrue(d.sections[1].collapsed)
        d.select(3)
        XCTAssertFalse(d.sections[1].collapsed)
    }

    func testRoundTripThroughTheFile() throws {
        let d = _deck(5)
        d.addSection(at: 1, name: "Intro & <more>")
        d.addSection(at: 3, name: "End")
        d.moveSection(2, by: -1)
        let want = _names(d)
        let data = try Pptx.write(d)
        let (state, theme, pkg) = try Pptx.read(data)
        let d2 = DeckController()
        d2.load(state, theme: theme, package: pkg)
        XCTAssertEqual(_names(d2), want)
        // Write it through (a loaded package), after one more edit.
        d2.addSection(at: 0, name: "Zero")
        let (s3, t3, p3) = try Pptx.read(Pptx.write(d2))
        let d3 = DeckController()
        d3.load(s3, theme: t3, package: p3)
        XCTAssertEqual(d3.sections.map(\.name), d2.sections.map(\.name))
        XCTAssertEqual(d3.slides.map(\.section), d2.slides.map(\.section))
        let xml = String(decoding: try XCTUnwrap(p3.parts["ppt/presentation.xml"]), as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<p14:sectionLst").count, 2)
        XCTAssertTrue(xml.contains("{521415D9-36F7-43E2-AB2F-B90AF26B5E84}"))
    }

    /// Writes the PowerPoint check deck when STARLING_SECTION_OUT names a path.
    func testWriteCheckDeck() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_SECTION_OUT"] else { return }
        let d = _deck(6)
        d.addSection(at: 2, name: "Middle & <end>")
        d.addSection(at: 4, name: "Last")
        d.moveSection(2, by: -1)   // Last before Middle: slides 3,4 are Last, 5,6 Middle
        try Pptx.write(d).write(to: URL(fileURLWithPath: out))
    }
}
