import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-AR-5: View > Gridlines, Guides and Grid Settings, kept in viewProps.xml as PowerPoint keeps them.
final class SlideGridTests: XCTestCase {
    /// A slide view as PowerPoint writes it, with a notes view that has guides of its own.
    static let powerPointViewProps = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/></p:normalViewPr><p:slideViewPr><p:cSldViewPr snapToGrid="0" showGuides="1"><p:cViewPr varScale="1"><p:scale><a:sx n="83" d="100"/><a:sy n="83" d="100"/></p:scale><p:origin x="114" y="378"/></p:cViewPr><p:guideLst><p:guide orient="horz" pos="2160"/><p:guide pos="2880"/></p:guideLst></p:cSldViewPr></p:slideViewPr><p:notesTextViewPr><p:cViewPr><p:scale><a:sx n="1" d="1"/><a:sy n="1" d="1"/></p:scale><p:origin x="0" y="0"/></p:cViewPr></p:notesTextViewPr><p:notesViewPr><p:cSldViewPr snapToGrid="0"><p:cViewPr varScale="1"><p:scale><a:sx n="60" d="100"/><a:sy n="60" d="100"/></p:scale><p:origin x="0" y="0"/></p:cViewPr><p:guideLst><p:guide orient="horz" pos="3120"/></p:guideLst></p:cSldViewPr></p:notesViewPr><p:gridSpacing cx="76200" cy="76200"/></p:viewPr>
    """

    func testReadsPowerPointsSlideView() throws {
        let g = SlideGridSettings.read(XNode.parse(Data(Self.powerPointViewProps.utf8)))
        XCTAssertFalse(g.snapToGrid)
        XCTAssertFalse(g.snapToObjects)
        XCTAssertTrue(g.showGuides)
        XCTAssertEqual(g.guides, [DrawingGuide(vertical: false, at: 270), DrawingGuide(vertical: true, at: 360)])
        XCTAssertEqual(g.spacing, 6, accuracy: 1e-9)
    }

    func testApplyKeepsTheZoomAndTheNotesView() throws {
        var g = SlideGridSettings.read(XNode.parse(Data(Self.powerPointViewProps.utf8)))
        g.snapToGrid = true
        g.snapToObjects = true
        g.guides = [DrawingGuide(vertical: true, at: 100)]
        g.spacing = 9
        let out = g.apply(to: Self.powerPointViewProps)
        XCTAssertNotNil(out.rangeOfSubstring("<p:cSldViewPr snapToObjects=\"1\" showGuides=\"1\"><p:cViewPr varScale=\"1\"><p:scale><a:sx n=\"83\""))
        XCTAssertNotNil(out.rangeOfSubstring("<p:guideLst><p:guide pos=\"800\"/></p:guideLst>"))
        // The notes view's own list and attribute are left alone.
        XCTAssertNotNil(out.rangeOfSubstring("<p:notesViewPr><p:cSldViewPr snapToGrid=\"0\">"))
        XCTAssertNotNil(out.rangeOfSubstring("<p:guide orient=\"horz\" pos=\"3120\"/>"))
        XCTAssertNotNil(out.rangeOfSubstring("<p:gridSpacing cx=\"114300\" cy=\"114300\"/></p:viewPr>"))
        XCTAssertEqual(SlideGridSettings.read(XNode.parse(Data(out.utf8))), g)
    }

    func testANewDeckGetsASlideViewOnlyWhenNeeded() throws {
        XCTAssertNil(SlideGridSettings().apply(to: PptxTemplates.viewProps).rangeOfSubstring("slideViewPr"))
        var g = SlideGridSettings()
        g.showGuides = true
        g.addCentreGuidesIfNone(Size(960, 540))
        let out = g.apply(to: PptxTemplates.viewProps)
        // Order: normalViewPr, slideViewPr, …, gridSpacing.
        let n = try XCTUnwrap(out.rangeOfSubstring("</p:normalViewPr>")), s = try XCTUnwrap(out.rangeOfSubstring("<p:slideViewPr>"))
        let gs = try XCTUnwrap(out.rangeOfSubstring("<p:gridSpacing"))
        XCTAssertTrue(n.upperBound <= s.lowerBound && s.upperBound < gs.lowerBound)
        XCTAssertNotNil(out.rangeOfSubstring("<p:guide orient=\"horz\" pos=\"2160\"/><p:guide pos=\"3840\"/>"))
        XCTAssertEqual(SlideGridSettings.read(XNode.parse(Data(out.utf8))), g)
    }

    func testGuidesSurviveSavingAndAreOneUndoStep() throws {
        let deck = DeckController()
        XCTAssertFalse(deck.grid.showGuides)
        deck.setShowGuides(true)
        XCTAssertEqual(deck.grid.guides.count, 2)
        var g = deck.grid
        g.snapToGrid = false
        g.spacing = 18
        deck.setGrid(g)
        let (state, theme, pkg) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(state.grid, g)
        // A saved deck's grid read back and saved through its package keeps it, and a change is written over it.
        var again = state
        again.grid.guides.removeFirst()
        let (back, _, _) = try Pptx.read(try PptxWriter.write(again, theme: theme, package: pkg))
        XCTAssertEqual(back.grid, again.grid)
        deck.undo()
        XCTAssertTrue(deck.grid.snapToGrid)
        XCTAssertTrue(deck.grid.showGuides)
        deck.undo()
        XCTAssertEqual(deck.grid, SlideGridSettings())
    }

    func testSnappedAndTheDialogsSpacing() {
        var g = SlideGridSettings()
        XCTAssertEqual(g.snapped(10), 12)
        XCTAssertEqual(g.snapped(14.9), 12)
        g.spacing = 18
        XCTAssertEqual(g.snapped(10), 18)
        XCTAssertEqual(GridGuidesDialogState.parse("1/12"), 6)
        XCTAssertEqual(GridGuidesDialogState.parse("0.5\""), 36)
        XCTAssertNil(GridGuidesDialogState.parse("3"))
        XCTAssertEqual(GridGuidesDialogState.inches(6), "0.08\"")
        XCTAssertEqual(GridGuidesDialogState.inches(72), "1\"")
    }
}
