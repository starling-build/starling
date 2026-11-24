// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsPartsKeptTests: XCTestCase {
    func testSaveKeepsDocPropsAndCustomXml() throws {
        let url = URL(fileURLWithPath: "/data/corpus-cache/test/corpus/xlsx-cjk-r3/ko-xlsx-r3b-dev/ko-c5f2fb8384.xlsx")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path))
        var orig = try Zip.read(try Data(contentsOf: url))
        // Add a customXml item the way Office writes one: a part, its props, and a workbook relationship to it.
        orig.append(ZipEntry(name: "customXml/item1.xml", data: Data("<root xmlns=\"urn:x\"><a>1</a></root>".utf8)))
        orig.append(ZipEntry(name: "customXml/itemProps1.xml", data: Data("<ds:datastoreItem xmlns:ds=\"http://schemas.openxmlformats.org/officeDocument/2006/customXml\" ds:itemID=\"{00000000-0000-0000-0000-000000000001}\"/>".utf8)))
        orig.append(ZipEntry(name: "customXml/_rels/item1.xml.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXmlProps\" Target=\"itemProps1.xml\"/></Relationships>".utf8)))
        let ri = try XCTUnwrap(orig.firstIndex { $0.name == "xl/_rels/workbook.xml.rels" })
        var rels = String(decoding: orig[ri].data, as: UTF8.self)
        rels = rels.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"rIdCx1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml\" Target=\"../customXml/item1.xml\"/></Relationships>")
        orig[ri] = ZipEntry(name: orig[ri].name, data: Data(rels.utf8))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Zip.write(orig)))
        c.setInput("edited", at: CellAddress(row: 0, col: 0))
        let out = Set(try Zip.read(try Xlsx.write(c.book)).map(\.name))
        let lost = orig.map(\.name).filter { !out.contains($0) }
        XCTAssertEqual(lost, [], "parts dropped by a save")
        let saved = try Zip.read(try Xlsx.write(c.book))
        let relsOut = String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/_rels/workbook.xml.rels" }).data, as: UTF8.self)
        XCTAssertTrue(relsOut.containsSubstring("customXml/item1.xml"), "the workbook still points at its customXml")
    }
}
