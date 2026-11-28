// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// U-FR-1: the shared Find and Replace dialog, driven headless with recording hooks.
final class FindReplaceDialogTests: XCTestCase {
    private var log: [String] = []
    private var closed = 0

    private func dialog(scopes: [String] = [], entireCell: Bool = false, goTo: Bool = true) -> WidgetTester {
        log = []; closed = 0
        var hooks = FindHooks(
            findNext: { [unowned self] p, scope, back in log.append("next \(back ? "back" : "fwd") scope \(scope.scope) matchCase \(p.options.matchCase) whole \(p.options.wholeWord) cell \(p.options.entireCell)"); return "found" },
            replace: { [unowned self] _, t, _ in log.append("replace \(t)"); return "replaced" },
            replaceAll: { [unowned self] _, t, _ in log.append("all \(t)"); return "Replaced 3" })
        hooks.scopes = scopes
        hooks.wholeIsEntireCell = entireCell
        hooks.wholeLabel = entireCell ? "Match entire cell contents" : "Find whole words only"
        if goTo { hooks.goTo = { [unowned self] t in log.append("goto \(t)"); return t == "7" ? nil : "No such place" } }
        return WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: FindReplaceDialog(
            initialQuery: "cat", hooks: hooks, onClose: { [unowned self] in closed += 1 }), title: "T"), size: Size(1280, 800))
    }

    func testEnterFindsNextWithTheTypedQuery() {
        let ui = dialog()
        ui.press(.enter); ui.pump()
        XCTAssertEqual(log, ["next fwd scope 0 matchCase false whole false cell false"])
        XCTAssertTrue(ui.has(text: "found"))
    }

    func testOptionsReachThePattern() {
        let ui = dialog()
        ui.tap(text: "Match case"); ui.tap(text: "Find whole words only")
        ui.tap(text: "Find Previous")
        XCTAssertEqual(log, ["next back scope 0 matchCase true whole true cell false"])
    }

    func testSheetsStyleOptionMeansTheWholeCell() {
        let ui = dialog(entireCell: true)
        ui.tap(text: "Match entire cell contents")
        ui.tap(text: "Find Previous")
        XCTAssertEqual(log, ["next back scope 0 matchCase false whole false cell true"])
    }

    func testReplaceAndReplaceAllPassTheReplacement() {
        let ui = dialog()
        ui.tap(text: "Replace"); ui.tap(text: "Replace All")
        XCTAssertEqual(log, ["replace ", "all "])
        XCTAssertTrue(ui.has(text: "Replaced 3"))
    }

    func testScopeChoiceOnlyWhenTheAppOffersOne() {
        XCTAssertFalse(dialog().has(text: "Search in"))
        XCTAssertTrue(dialog(scopes: ["Sheet", "Workbook"]).has(text: "Search in"))
    }

    func testGoToClosesOnSuccessAndExplainsAFailure() {
        let ui = dialog()
        ui.tap(id: "fr-goto"); ui.type("9"); ui.tap(text: "Go")
        XCTAssertEqual(closed, 0)
        XCTAssertTrue(ui.has(text: "No such place"))
    }

    func testNoGoToRowWhenTheAppHasNone() {
        XCTAssertFalse(dialog(goTo: false).has(id: "fr-goto"))
    }

    func testCloseAndEscape() {
        let ui = dialog()
        ui.tap(text: "Close"); ui.press(.escape)
        XCTAssertEqual(closed, 2)
    }
}
