// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import PDFKit
// test/pdf-text.swift A.pdf — every line of text in the PDF as
// "p<page> <y> <x> <text>" (points, rounded; spaces dropped from the
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
        print("p\(i + 1)\t\(Int(b.minY.rounded()))\t\(Int(b.minX.rounded()))\t\((l.string ?? "").replacingOccurrences(of: " ", with: ""))")
    }
}
