// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// pdf-diff A.pdf B.pdf OUTDIR [scale] — renders both PDFs page by page with
// CoreGraphics and prints, per page, the share of pixels that differ and the
// mean difference (0..255), then one summary line; a page whose share is
// above 0.5% also gets a side-by-side PNG in OUTDIR (A | B | difference).
// Compiled on the fly by test/docx-word-render.sh; no dependencies beyond
// the system frameworks, so it runs where Pillow does not.

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 4,
      let a = CGPDFDocument(URL(fileURLWithPath: args[1]) as CFURL),
      let b = CGPDFDocument(URL(fileURLWithPath: args[2]) as CFURL)
else { print("usage: pdf-diff A.pdf B.pdf OUTDIR [scale]"); exit(2) }
let outDir = args[3]
let scale = CGFloat(args.count > 4 ? Double(args[4]) ?? 1 : 1)
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ page: CGPDFPage, width: Int, height: Int) -> [UInt8] {
    var data = [UInt8](repeating: 255, count: width * height * 4)
    let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor.white); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let box = page.getBoxRect(.mediaBox)
    ctx.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
    ctx.translateBy(x: -box.minX, y: -box.minY)
    ctx.drawPDFPage(page)
    return data
}

let pages = max(a.numberOfPages, b.numberOfPages)
var worst = 0.0, total = 0.0
for n in 1...max(pages, 1) {
    guard let pa = a.page(at: n), let pb = b.page(at: n) else {
        print(String(format: "page %2d  missing in %@", n, a.page(at: n) == nil ? "A" : "B"))
        worst = 100; total += 100
        continue
    }
    let box = pa.getBoxRect(.mediaBox)
    let w = Int(box.width * scale), h = Int(box.height * scale)
    let ia = render(pa, width: w, height: h), ib = render(pb, width: w, height: h)
    var differing = 0, sum = 0
    var diff = [UInt8](repeating: 255, count: w * h * 4)
    for i in stride(from: 0, to: w * h * 4, by: 4) {
        let d = max(abs(Int(ia[i]) - Int(ib[i])), abs(Int(ia[i + 1]) - Int(ib[i + 1])), abs(Int(ia[i + 2]) - Int(ib[i + 2])))
        if d > 32 { differing += 1; diff[i] = 255; diff[i + 1] = 0; diff[i + 2] = 0 }
        sum += d
    }
    let share = 100.0 * Double(differing) / Double(w * h)
    let mean = Double(sum) / Double(w * h)
    worst = max(worst, share); total += share
    print(String(format: "page %2d  %6.2f%% pixels differ  mean %5.2f", n, share, mean))
    if share > 0.5 {
        let pair = CGContext(data: nil, width: w * 3 + 20, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        pair.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); pair.fill(CGRect(x: 0, y: 0, width: w * 3 + 20, height: h))
        for (k, bytes) in [ia, ib, diff].enumerated() {
            var copy = bytes
            let img = CGContext(data: &copy, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
            pair.draw(img, in: CGRect(x: k * (w + 10), y: 0, width: w, height: h))
        }
        let out = pair.makeImage()!
        let rep = NSBitmapImageRep(cgImage: out)
        let name = String(format: "%@/pair-%05.2f-%@-p%d.png", outDir, share,
                          (args[2] as NSString).lastPathComponent.replacingOccurrences(of: ".pdf", with: ""), n)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
    }
}
print(String(format: "summary pages=%d worst=%.2f%% mean=%.2f%%", pages, worst, pages > 0 ? total / Double(pages) : 0))
