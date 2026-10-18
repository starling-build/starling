import XCTest
import WikiModel

/// A toy document the tests apply ops to: paragraphs of plain text. If two
/// clients' concurrent edits converge here, the positions are right; the
/// payloads the real model carries ride along untouched.
struct Toy: Equatable {
    var paragraphs: [String]

    mutating func apply(_ op: PageOp) {
        func idx(_ s: String, _ o: Int) -> String.Index { String.Index(utf16Offset: min(o, s.utf16.count), in: s) }
        switch op {
        case .insertText(let p, let o, let t, _):
            paragraphs[p].insert(contentsOf: t, at: idx(paragraphs[p], o))
        case .deleteText(let p, let o, let l, _):
            let s = paragraphs[p]
            paragraphs[p].removeSubrange(idx(s, o) ..< idx(s, o + l))
        case .splitParagraph(let p, let o, _):
            let s = paragraphs[p]
            let tail = String(s[idx(s, o)...])
            paragraphs[p] = String(s[..<idx(s, o)])
            paragraphs.insert(tail, at: p + 1)
        case .mergeParagraph(let p, _, _):
            let tail = paragraphs.remove(at: p + 1)
            paragraphs[p] += tail
        case .insertParagraphs(let at, let n, let payload):
            paragraphs.insert(contentsOf: Array(repeating: payload.json, count: n), at: at)
        case .removeParagraphs(let at, let n, _):
            paragraphs.removeSubrange(at ..< at + n)
        case .setParagraph, .setDocument:
            break
        }
    }

    mutating func apply(_ ops: [PageOp]) { for op in ops { apply(op) } }
}

let P = Opaque(json: "\"new\"")

final class TransformTests: XCTestCase {
    /// Two clients edit the same base concurrently; the server lands A then
    /// B; both clients and the server must end on the same document.
    func converge(_ base: [String], a: [PageOp], b: [PageOp], file: StaticString = #filePath, line: UInt = #line) -> Toy {
        var server = PageSequencer()
        var sDoc = Toy(paragraphs: base)
        let (a1, _) = try! server.land(a, clientRevision: 0)
        let (b1, _) = try! server.land(b, clientRevision: 0)
        sDoc.apply(a1); sDoc.apply(b1)

        // Client A: applied its own ops, then receives B's as the server
        // transformed them (it had nothing pending by then).
        var aDoc = Toy(paragraphs: base); aDoc.apply(a); aDoc.apply(b1)
        // Client B: applied its own ops locally, then A's land first; B's
        // pending ops must be rebased, and A's moved past them.
        var bDoc = Toy(paragraphs: base); bDoc.apply(b)
        var pending = PendingOps(); pending.sent(b)
        for op in a1 { bDoc.apply(pending.incoming(op)) }
        // B's rebased pending ops are what the server landed for B.
        XCTAssertEqual(pending.pending, b1, "client rebase matches server transform", file: file, line: line)

        XCTAssertEqual(aDoc, sDoc, "A converges", file: file, line: line)
        XCTAssertEqual(bDoc, sDoc, "B converges", file: file, line: line)
        return sDoc
    }

    func testInsertsInOneParagraph() {
        let d = converge(["hello world"],
                         a: [.insertText(para: 0, offset: 5, text: ",", runs: nil)],
                         b: [.insertText(para: 0, offset: 11, text: "!", runs: nil)])
        XCTAssertEqual(d.paragraphs, ["hello, world!"])
    }

    func testInsertAtSamePointKeepsServerOrder() {
        let d = converge(["ab"],
                         a: [.insertText(para: 0, offset: 1, text: "X", runs: nil)],
                         b: [.insertText(para: 0, offset: 1, text: "Y", runs: nil)])
        XCTAssertEqual(d.paragraphs, ["aXYb"])
    }

    func testDeleteAndInsertOverlap() {
        let d = converge(["abcdef"],
                         a: [.deleteText(para: 0, offset: 1, length: 3, removed: nil)],   // "aef"
                         b: [.insertText(para: 0, offset: 2, text: "Z", runs: nil)])      // inside the deleted span
        // The deletion landed first and the insertion was inside it: Z
        // appears where the span was.
        XCTAssertEqual(d.paragraphs, ["aZef"])
    }

    func testOverlappingDeletes() {
        let d = converge(["abcdefgh"],
                         a: [.deleteText(para: 0, offset: 1, length: 4, removed: nil)],   // bcde
                         b: [.deleteText(para: 0, offset: 3, length: 4, removed: nil)])   // defg
        XCTAssertEqual(d.paragraphs, ["ah"])
    }

    func testSplitAgainstInsert() {
        let d = converge(["hello world"],
                         a: [.splitParagraph(para: 0, offset: 5, tailStyle: nil)],
                         b: [.insertText(para: 0, offset: 7, text: "X", runs: nil)])
        XCTAssertEqual(d.paragraphs, ["hello", " wXorld"])
    }

    func testInsertAgainstSplit() {
        let d = converge(["hello world"],
                         a: [.insertText(para: 0, offset: 7, text: "X", runs: nil)],
                         b: [.splitParagraph(para: 0, offset: 5, tailStyle: nil)])
        XCTAssertEqual(d.paragraphs, ["hello", " wXorld"])
    }

    func testMergeAgainstEditInTail() {
        let d = converge(["ab", "cd", "ef"],
                         a: [.mergeParagraph(para: 0, headLength: 2, removedStyle: nil)],
                         b: [.insertText(para: 1, offset: 1, text: "X", runs: nil), .insertText(para: 2, offset: 0, text: "Y", runs: nil)])
        XCTAssertEqual(d.paragraphs, ["abcXd", "Yef"])
    }

    func testInsertParagraphsAgainstEdits() {
        let d = converge(["a", "b"],
                         a: [.insertParagraphs(at: 1, count: 2, paragraphs: P)],
                         b: [.insertText(para: 1, offset: 1, text: "!", runs: nil)])
        XCTAssertEqual(d.paragraphs, ["a", "\"new\"", "\"new\"", "b!"])
    }

    func testRemoveParagraphDropsEditsInIt() {
        let d = converge(["a", "b", "c"],
                         a: [.removeParagraphs(at: 1, count: 1, paragraphs: P)],
                         b: [.insertText(para: 1, offset: 0, text: "X", runs: nil), .insertText(para: 2, offset: 0, text: "Y", runs: nil)])
        XCTAssertEqual(d.paragraphs, ["a", "Yc"])
    }

    func testSplitThenMergeByOther() {
        let d = converge(["abcd", "e"],
                         a: [.splitParagraph(para: 0, offset: 2, tailStyle: nil)],
                         b: [.mergeParagraph(para: 0, headLength: 4, removedStyle: nil)])
        XCTAssertEqual(d.paragraphs, ["ab", "cde"])
    }

    func testSequencerRevisions() throws {
        var s = PageSequencer()
        try s.land([.insertText(para: 0, offset: 0, text: "a", runs: nil)], clientRevision: 0)
        XCTAssertEqual(s.revision, 1)
        XCTAssertEqual(s.ops(since: 0)?.count, 1)
        XCTAssertThrowsError(try s.land([], clientRevision: 5))
        let s2 = PageSequencer(revision: 10)
        XCTAssertNil(s2.ops(since: 3))
    }

    func testOpsSurviveJSON() throws {
        let ops: [PageOp] = [
            .insertText(para: 1, offset: 2, text: "héllo 中", runs: Opaque(json: #"[{"length":7,"style":{"bold":true}}]"#)),
            .setDocument(what: "header", payload: Opaque(json: #"{"old":"","new":"H \"q\" /x"}"#)),
            .removeParagraphs(at: 0, count: 2, paragraphs: Opaque(json: "[1,2.5,null,true]")),
        ]
        let data = try JSONEncoder().encode(ops)
        let back = try JSONDecoder().decode([PageOp].self, from: data)
        XCTAssertEqual(back, ops)
    }
}

final class TransformEdgeTests: XCTestCase {
    func testDeleteAcrossSplit() {
        let t = TransformTests()
        let d = t.converge(["abcdef"],
                           a: [.splitParagraph(para: 0, offset: 3, tailStyle: nil)],
                           b: [.deleteText(para: 0, offset: 1, length: 4, removed: nil)])   // bcde
        XCTAssertEqual(d.paragraphs, ["a", "f"])
    }

    func testInsertInsideConcurrentDeleteSurvivesBothWays() {
        let t = TransformTests()
        // The insertion lands first this time.
        let d = t.converge(["abcdef"],
                           a: [.insertText(para: 0, offset: 2, text: "Z", runs: nil)],
                           b: [.deleteText(para: 0, offset: 1, length: 3, removed: nil)])
        XCTAssertEqual(d.paragraphs, ["aZef"])
    }
}
