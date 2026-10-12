// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// test/pdf-lines.swift A.pdf B.pdf [page] — the text lines of one page of two
// PDFs (PDFKit), printing only the lines whose box differs by more than a
// twentieth of a point: where a Word print of our copy first leaves the
// print of the original. swiftc -O -o pdf-lines test/pdf-lines.swift
import PDFKit
let a = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!, b = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[2]))!
let pn = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! - 1 : 0
func lines(_ d: PDFDocument) -> [(String, CGRect)] {
    guard let p = d.page(at: pn), let sel = p.selection(for: p.bounds(for: .mediaBox)) else { return [] }
    return sel.selectionsByLine().map { (String(($0.string ?? "").prefix(28)), $0.bounds(for: p)) }
}
let la = lines(a), lb = lines(b)
print("lines", la.count, lb.count)
for i in 0 ..< max(la.count, lb.count) {
    let x = i < la.count ? la[i] : ("-", .zero), y = i < lb.count ? lb[i] : ("-", .zero)
    let same = abs(x.1.minY - y.1.minY) < 0.05 && abs(x.1.minX - y.1.minX) < 0.05 && abs(x.1.width - y.1.width) < 0.05
    if !same { print(String(format: "%3d  %-28@ x%.2f y%.2f w%.2f | %-28@ x%.2f y%.2f w%.2f", i, x.0 as NSString, x.1.minX, x.1.minY, x.1.width, y.0 as NSString, y.1.minX, y.1.minY, y.1.width)) }
}
