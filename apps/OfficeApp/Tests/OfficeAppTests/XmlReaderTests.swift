// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// This app's own XML reader against the system's: Slides reads every
/// part through it (XNode.parse), and the browser build has no other.
final class XmlReaderTests: XCTestCase {
    private func same(_ xml: String, file: StaticString = #filePath, line: UInt = #line) {
        let data = Data(xml.utf8)
        guard let system = XNode.parseSystem(data), let own = MiniXML.parse([UInt8](data)) else {
            return XCTFail("did not parse", file: file, line: line)
        }
        XCTAssertEqual(PptxXML.serialize(own), PptxXML.serialize(system), file: file, line: line)
        XCTAssertEqual(_texts(own), _texts(system), file: file, line: line)
    }

    /// Every element's own text, in document order (serialize drops the
    /// white space between children; this does not).
    private func _texts(_ n: XNode) -> [String] { [n.text] + n.children.flatMap(_texts) }

    func testALineEndIsOneLineFeedHoweverTheFileWroteIt() {
        // lo-n828390_2: "Linux \r\nStandard Platform" in an a:t kept its
        // carriage return, and drew as a second break.
        same("<a><t>one\r\ntwo\rthree\nfour</t></a>")
        let own = MiniXML.parse(Array("<a><t>one\r\ntwo\rthree</t></a>".utf8))
        XCTAssertEqual(own?.first("t")?.text, "one\ntwo\nthree")
    }

    func testACarriageReturnTheFileAskedForIsKept() {
        same("<a><t>one&#13;two&#xD;&#10;three</t></a>")
        XCTAssertEqual(MiniXML.parse(Array("<a><t>x&#13;y</t></a>".utf8))?.first("t")?.text, "x\ry")
    }

    func testWhiteSpaceInAnAttributeValueIsSpaces() {
        same("<a v=\"one\ttwo\nthree\r\nfour\rfive\" w='a&#10;b&#9;c'/>")
        XCTAssertEqual(MiniXML.parse(Array("<a v=\"1\r\n2\t3\"/>".utf8))?["v"], "1 2 3")
    }

    func testCDataEntitiesCommentsAndInstructions() {
        // (A line end inside CDATA: the Mac's parser hands the section over
        // as it stands, CR and all, and so does this app's; libxml2, which
        // is the system's parser off a Mac, has made it a line feed by
        // then. The two are compared where they can agree.)
        #if canImport(FoundationXML)
        let lineEnd = "\n"
        #else
        let lineEnd = "\r\n"
        #endif
        same("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<!-- c --><a x:y=\"&lt;&amp;&quot;&#233;\">t&gt;<![CDATA[<raw>&amp;\(lineEnd)]]><?pi x?><b/> tail<c> </c></a>")
    }

    func testAPartThatIsNotUtf8GoesToTheSystemsParser() {
        // UTF-16 with its byte order mark, as some exporters write a part.
        var utf16 = Data([0xFF, 0xFE])
        for u in "<?xml version=\"1.0\" encoding=\"UTF-16\"?><a v=\"é\"><t>日本</t></a>".utf16 {
            utf16.append(UInt8(u & 0xFF)); utf16.append(UInt8(u >> 8))
        }
        let root = XNode.parse(utf16)
        XCTAssertEqual(root?["v"], "é")
        XCTAssertEqual(root?.first("t")?.text, "日本")
        // And a declared single-byte encoding.
        var latin = Data("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><a v=\"".utf8)
        latin.append(0xE9)
        latin.append(contentsOf: Data("\"/>".utf8))
        XCTAssertEqual(XNode.parse(latin)?["v"], "é")
    }

    func testAPartWithADocumentTypeGoesToTheSystemsParser() {
        // An entity the part defines is the system's business — it drops
        // the reference, where this app's reader would leave "&who;" in
        // the text — so such a part reads as it always did.
        let data = Data("<?xml version=\"1.0\"?>\n<!DOCTYPE a [ <!ENTITY who \"world\"> ]>\n<a><t>hello &who;</t></a>".utf8)
        XCTAssertEqual(XNode.parse(data)?.first("t")?.text, XNode.parseSystem(data)?.first("t")?.text)
        XCTAssertNotEqual(MiniXML.parse([UInt8](data))?.first("t")?.text, XNode.parseSystem(data)?.first("t")?.text)
    }

    // MARK: A part read as a tree and a list

    private let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="m" xmlns:x="m"><dimension ref="A1:B3"/><cols><col min="1" max="1" width="9"/></cols>
        <sheetData note="a > b"><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><f>A1&amp;"x"</f><v>1</v></c></row>
        <row r="2"/><stray><row r="nested"/></stray> <x:row r="3" ht="20"><c r="A3"><is><t>a&lt;b\r\nc</t></is></c></x:row>
        <!-- <row r="in a comment"/> --></sheetData><mergeCells><mergeCell ref="A1:B1"/></mergeCells>
        <sheetData><row r="second list"/></sheetData><autoFilter ref="A1:B3"/></worksheet>
        """

    func testAListPartIsTheTreeWithoutItsListAndTheItemsInOrder() throws {
        let data = Data(sheet.utf8)
        let whole = try XCTUnwrap(XNode.parseSystem(data))
        let wanted = whole.child("sheetData")!.kids("row").map(PptxXML.serialize)
        XCTAssertEqual(wanted.count, 3)
        for mode in ["own", "system"] {
            let part: XNode.ListPart
            if mode == "own" {
                let root = try XCTUnwrap(MiniXML.parse([UInt8](data), emptying: "sheetData"))
                part = XNode.ListPart(root: root) { each in
                    MiniXML.children(named: "row", ofRootChild: "sheetData", in: [UInt8](data), each)
                }
            } else {
                // What `parse(_:listUnder:of:)` does when the part is the system's to read.
                var latin = Data("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>".utf8)
                latin.append(Data(sheet.utf8.drop { $0 != UInt8(ascii: "\n") }))
                part = try XCTUnwrap(XNode.parse(latin, listUnder: "sheetData", of: "row"))
            }
            var rows: [String] = []
            part.forEach { rows.append(PptxXML.serialize($0)) }
            XCTAssertEqual(rows, wanted, mode)
            // The rest of the tree is all there, the first list empty.
            let emptied = try XCTUnwrap(XNode.parseSystem(data))
            emptied.child("sheetData")!.children = []
            XCTAssertEqual(PptxXML.serialize(part.root), PptxXML.serialize(emptied), mode)
            XCTAssertEqual(part.root.child("sheetData")?["note"], "a > b", mode)
        }
    }

    func testAListPartThroughTheUsualDoor() throws {
        let part = try XCTUnwrap(XNode.parse(Data(sheet.utf8), listUnder: "sheetData", of: "row"))
        var n = 0
        part.forEach { _ in n += 1 }
        XCTAssertEqual(n, 3)
        XCTAssertNil(part.root.child("sheetData")?.child("row"))
        // No list at all, and an empty one.
        for xml in ["<worksheet><cols/></worksheet>", "<worksheet><sheetData/><cols/></worksheet>"] {
            let p = try XCTUnwrap(XNode.parse(Data(xml.utf8), listUnder: "sheetData", of: "row"))
            p.forEach { _ in XCTFail("no rows in \(xml)") }
            XCTAssertNotNil(p.root.child("cols"))
        }
    }

    func testSerializingIsWhatItWas() {
        let xml = "<p:sp xmlns:p=\"u\" b=\"2\" a=\"1 &amp; &quot;q&quot; &lt;\"><p:t>a &lt; b &amp; c &gt; d \"q\"</p:t>\n  <p:e/><p:f> </p:f></p:sp>"
        let node = XNode.parse(Data(xml.utf8))!
        XCTAssertEqual(PptxXML.serialize(node),
                       "<p:sp a=\"1 &amp; &quot;q&quot; &lt;\" b=\"2\" xmlns:p=\"u\"><p:t>a &lt; b &amp; c &gt; d \"q\"</p:t><p:e/><p:f> </p:f></p:sp>")
    }
}
