// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// test/pdf-fonts.swift FILE.pdf ... — the fonts and sizes on page one of each
// PDF and its first line boxes: what Word actually set a file in (how the
// no-styles defaults were read off its print).
// swiftc -O -o pdf-fonts test/pdf-fonts.swift
import PDFKit
for path in CommandLine.arguments.dropFirst() {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)), let page = doc.page(at: 0), let s = page.attributedString else { continue }
    var seen = Set<String>()
    s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { v, r, _ in
        if let f = v as? NSFont { let k = "\(f.fontName) \(f.pointSize)"; if seen.insert(k).inserted { print(path.split(separator: "/").last!, k, (s.string as NSString).substring(with: r).prefix(20)) } }
    }
    if let sel = page.selection(for: page.bounds(for: .mediaBox)) { for l in sel.selectionsByLine().prefix(4) { print("  line", l.bounds(for: page)) } }
}
