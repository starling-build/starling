// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import PDFKit
// test/pdf-text.swift A.pdf — every line of text in the PDF as
// "p<page> <y> <x> <text>" (points, rounded, y up from the page's top so
// negative; spaces dropped from the
// text). Two of Word's prints through this and `diff -a` name the first
// line that moved, broke elsewhere or changed page — where pdf-diff.swift
// only says how much of a page differs.
//   swiftc -O -o /tmp/pdf-text test/pdf-text.swift
//   diff -a <(/tmp/pdf-text orig.pdf) <(/tmp/pdf-text ours.pdf) | head
guard CommandLine.arguments.count > 1, let d = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else {
    FileHandle.standardError.write(Data("usage: pdf-text FILE.pdf\n".utf8)); exit(2)
}
for i in 0 ..< d.pageCount {
    guard let p = d.page(at: i), let s = p.selection(for: p.bounds(for: .mediaBox)) else { continue }
    for l in s.selectionsByLine() {
        let b = l.bounds(for: p)
        // (Up from the page's TOP, as a negative: Word's print of a page
        // not quite A4 or Letter comes out on that paper — zh-8f9b19f4's
        // 835pt pages on A4's 842 — and its lines, measured from the foot,
        // stood 7pt off ours that are where Word's are from the top.)
        let top = p.bounds(for: .mediaBox).height
        print("p\(i + 1)\t\(Int((b.minY - top).rounded()))\t\(Int(b.minX.rounded()))\t\((l.string ?? "").replacingOccurrences(of: " ", with: ""))")
    }
}
