// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// The cell scanner (MiniXML.scanCells) against the tree reader: the same book comes out of both, so
/// what is written back is identical, sheet part by sheet part.
final class SheetsScanTests: XCTestCase {
    /// The written sheet parts of `data`, read with the scanner `on` or off.
    func sheetParts(_ data: Data, scan: Bool) throws -> [String: Data] {
        Xlsx.scanCells = scan
        defer { Xlsx.scanCells = true }
        let written = try Zip.read(try Xlsx.write(try Xlsx.read(data)))
        var out: [String: Data] = [:]
        for e in written where e.name.hasPrefix("xl/worksheets/sheet") && e.name.hasSuffix(".xml") { out[e.name] = e.data }
        return out
    }

    func assertSame(_ data: Data, _ what: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let a = try sheetParts(data, scan: false), b = try sheetParts(data, scan: true)
        XCTAssertFalse(a.isEmpty, what, file: file, line: line)
        XCTAssertEqual(a.keys.sorted(), b.keys.sorted(), what, file: file, line: line)
        for (k, v) in a { XCTAssertEqual(v, b[k], "\(what) \(k)", file: file, line: line) }
    }

    /// The fixture with its first sheet's rows replaced by `rows`.
    func fixture(rows: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        var entries = try Zip.read(try Data(contentsOf: url))
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "xl/worksheets/sheet1.xml" })
        var s = String(decoding: entries[i].data, as: UTF8.self)
        let open = try XCTUnwrap(s.findRange(of: "<sheetData>")), close = try XCTUnwrap(s.findRange(of: "</sheetData>"))
        s.replaceSubrange(open.lowerBound ..< close.upperBound, with: "<sheetData>" + rows + "</sheetData>")
        entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
        return try Zip.write(entries)
    }

    func testOddHandWrittenCellsReadTheSame() throws {
        let rows = [
            // entities, a CR/LF in a value, an inline string, a missing r, an r out of order
            #"<row r="1"><c r="A1" t="inlineStr"><is><t>a &amp; b &lt;c&gt; &#65;</t></is></c><c r="B1" t="str"><f>A1&amp;"x"</f><v>a&#10;b</v></c><c t="n"><v>7</v></c><c r="A1"><v>9</v></c></row>"#,
            // cm / vm / ph, duplicate attribute (tree decides), an empty <v/>, extra <f> attributes
            #"<row r="2"><c r="A2" cm="1" vm="2" ph="1"><v>1.5</v></c><c r="B2" s="0" s="0"><v>2</v></c><c r="C2"><v/></c><c r="D2"><f ca="1" aca="1">SUM(A2:C2)</f><v>3.5</v></c></row>"#,
            // CDATA and a comment in the text, a prefixed attribute, an attribute on <v>
            #"<row r="3"><c r="A3" t="str"><v><![CDATA[x<y]]></v></c><c r="B3" t="str"><v>p<!-- c -->q</v></c><c r="C3" xml:space="preserve"><v>4</v></c><c r="D3" t="str"><v xml:space="preserve"> pad </v></c></row>"#,
            // shared formulas (master, then followers), an array formula, a bad type, error and bool cells
            #"<row r="4"><c r="A4"><f t="shared" ref="A4:A6" si="0">B4+1</f><v>2</v></c><c r="B4"><v>1</v></c><c r="C4" t="e"><v>#DIV/0!</v></c><c r="D4" t="b"><v>1</v></c><c r="E4" t="zz"><v>5</v></c></row>"#,
            #"<row r="5"><c r="A5"><f t="shared" si="0"/><v>3</v></c><c r="B5"><v>2</v></c><c r="C5"><f t="array" ref="C5:C5">SUM(B4:B5)</f><v>3</v></c></row>"#,
            // self-closing cells, a custom-format row, spans, an empty row, a stray element between cells
            #"<row r="6" spans="1:3"><c r="A6"/><c r="B6" s="0"/><c r="C6"><v>8</v></c></row>"#,
            #"<row r="7" customFormat="1" s="0"><c r="A7"><v>1</v></c><c r="B7"/></row>"#,
            #"<row r="8"/>"#,
            #"<row r="9"><c r="A9"><v>1</v></c><extLst/><c r="B9"><v>2</v></c></row>"#,
        ].joined()
        try assertSame(try fixture(rows: rows), "hand-written rows")
    }

    /// About 60 corpus books (every eighth), when the cache is there.
    func testCorpusBooksReadTheSame() throws {
        let dir = "/data/corpus-cache/test/corpus/xlsx2/books"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".xlsx") }.sorted()
        try XCTSkipIf(names.isEmpty, "corpus cache not present")
        for (n, name) in names.enumerated() where n % 8 == 0 {
            guard let data = FileManager.default.contents(atPath: dir + "/" + name), data.count < 1_000_000 else { continue }
            try assertSame(data, name)
        }
    }

    /// A1-style text read on bytes (CellRefText.parse) against the Character reading, on every shape and a few thousand mixes.
    func testCellRefTextBytesMatchCharacters() {
        var samples = ["A1", "$A$1", "A$1", "$A1", "$1", "$3:$5", "3:5", "A", "$A", "A$", "$$A1", "XFD1048576", "XFE1", "A1048577", "A0", "a1", "abcd1",
                       "A1:B2", "A1B", "A1.5", "Á1", "A\u{301}1", "A1\u{301}", "$\u{301}A1", "A1é", "É1", "A$1$", "1A", "12345678", "A12345678", "AAA1", "", "$", "é"]
        let alphabet = Array("Aa$1:Zz9 .é\u{301}_(")
        var seed: UInt64 = 12345
        for _ in 0 ..< 4000 {
            var t = ""
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            for k in 0 ..< Int(seed >> 60) % 7 + 1 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                t.append(alphabet[Int(seed >> 33) % alphabet.count]); _ = k
            }
            samples.append(t)
        }
        for t in samples {
            let a = CellRefText.parse(Substring(t)), b = CellRefText.parseCharacters(Substring(t))
            XCTAssertEqual(a?.row, b?.row, t); XCTAssertEqual(a?.col, b?.col, t)
            XCTAssertEqual(a?.rowAbs, b?.rowAbs, t); XCTAssertEqual(a?.colAbs, b?.colAbs, t)
            XCTAssertEqual(a.map { String($0.rest) }, b.map { String($0.rest) }, t)
        }
    }

    // MARK: Formula tokenizer: bytes against Characters

    private func tokens(_ f: (Substring) throws -> [Formula.Token], _ s: String) -> String {
        do { return "\(try f(Substring(s)))" } catch let e as FormulaError { return "error: \(e.message)" } catch { return "other" }
    }

    private func assertTokensMatch(_ s: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(tokens(Formula._tokenize, s), tokens(Formula._tokenizeCharacters, s), s, file: file, line: line)
    }

    func testFormulaTokenizerBytesMatchCharacters() throws {
        let odd = ["SUM(A1:B2)", "$A$1+B$2*$C3", "A1 B2", "A1:B2 C3:D4", "Sheet1!A1", "'My Sheet'!$A$1:$B$2", "'it''s'!A1",
                   "3:5", "$3:$5", "A:C", "$A:$C", "1.5e3+.5", "1e", "1e+", "2E-4", "#REF!", "#ref!", "#N/A", "#NAME?", "#bad",
                   "\"a\"\"b\"", "\"open", "{1,2;3,4}", "A1#", "Table1[Col]", "Table1[[#Data],[A 'b]]]", "[@Qty]*2", "[1]Sheet1!A1",
                   "[1]!A1", "[]", "[1", "TRUE", "false", "True(", "foo", "foo.bar", "IF(A1<=1,A1<>2,A1>=3)", "A1&\"x\"", "-A1^2%", "@A1",
                   "Hitab!Divisor", "Hitab!Divisor(", "x!", "1 2", "A1  (B1)", "SUM (A1)", "name (A1)", "A1\t B1", "\n", "A$", "$$1", "$1", "A0",
                   "XFE1", "XFD1048576", "XFD1048577", "AAAA1", "A1048577", "é1", "A1é", "\"é\"", "日本!A1", "A1\u{301}", "a\r\nb", "~", "'", "\\x",
                   "Sheet1!", "Sheet1!3:5", "Sheet1!A:A", "A1:B", "A:B2", "1:2:3", "R1C1", "LOG10(10)", "A1.5", "1..2", "."]
        for s in odd { assertTokensMatch(s) }
        let dir = "/data/corpus-cache/test/corpus/xlsx2/books"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".xlsx") }.sorted()
        try XCTSkipIf(names.isEmpty, "corpus cache not present")
        var count = 0
        for (n, name) in names.enumerated() where n % 20 == 0 {
            guard let data = FileManager.default.contents(atPath: dir + "/" + name), data.count < 1_500_000 else { continue }
            for (_, part) in try sheetParts(data, scan: true) {
                let xml = String(decoding: part, as: UTF8.self)
                var rest = xml[...]
                while let open = rest.range(of: "<f") {
                    rest = rest[open.upperBound...]
                    guard let gt = rest.firstIndex(of: ">"), gt == rest.startIndex || rest[rest.index(before: gt)] != "/",
                          let close = rest.range(of: "</f>") else { continue }
                    let text = rest[rest.index(after: gt) ..< close.lowerBound]
                        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
                        .replacingOccurrences(of: "&amp;", with: "&")
                    assertTokensMatch(text)
                    count += 1
                    if count > 200_000 { return }
                    rest = rest[close.upperBound...]
                }
            }
        }
        XCTAssertGreaterThan(count, 0)
    }
}
