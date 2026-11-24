// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocHeaderPictureTests: XCTestCase {
    /// A header or footer with no drawn shapes can still hold an inline picture (a letterhead logo).
    /// The reader used to give that part no picture and no relationships. The fixture is a corpus
    /// .doc (kept out of git), so the test skips where the corpus cache is absent.
    func testAHeaderWithOnlyAnInlinePictureGetsItsRelationship() throws {
        let path = "/data/corpus-cache/staging/docx-new/es-doc-r1-dev/es-7289450bf2.doc"
        guard let data = FileManager.default.contents(atPath: path) else { throw XCTSkip("corpus doc not present") }
        let cf = try CompoundFile([UInt8](data))
        let parts = try XCTUnwrap(DocRead.parts(cf))
        let headerRels = parts.filter { $0.name.hasPrefix("word/_rels/header") }
        XCTAssertFalse(headerRels.isEmpty, "no header part has relationships: " + parts.map(\.name).joined(separator: ","))
        let xml = headerRels.map { String(decoding: $0.data, as: UTF8.self) }.joined()
        XCTAssertTrue(xml.contains("relationships/image"), xml)
    }
}
