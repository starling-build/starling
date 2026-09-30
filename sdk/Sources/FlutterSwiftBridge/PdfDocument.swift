// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// PDF output through the engine: one recorded `Picture` per page, written
/// by Skia's PDF backend with the real fonts embedded. Lives beside the
/// picture types because the page pictures' bridge handles are internal to
/// this module.
public enum PdfDocument {
    public struct Page {
        public let picture: any Picture
        /// PDF points (1/72 in).
        public let width: Double
        public let height: Double

        public init(picture: any Picture, width: Double, height: Double) {
            self.picture = picture
            self.width = width
            self.height = height
        }
    }

    /// Writes `pages` to `path`. A picture is played back at 1 unit = 1 PDF
    /// point, so a caller that painted in logical pixels (96/in) scales its
    /// canvas by 72/96 before painting. Returns false when a page is not an
    /// engine picture or the file could not be written.
    @discardableResult
    public static func write(to path: String, pages: [Page], title: String? = nil,
                             author: String? = nil) -> Bool {
        guard !pages.isEmpty else { return false }
        var lists: [UnsafeRawPointer?] = []
        for page in pages {
            guard let native = page.picture as? NativePictureProvider else { return false }
            lists.append(native.displayListPtr)
        }
        let widths = pages.map(\.width)
        let heights = pages.map(\.height)
        return lists.withUnsafeBufferPointer { b in
            widths.withUnsafeBufferPointer { w in
                heights.withUnsafeBufferPointer { h in
                    flutter.swift_bridge.WritePdf(path, b.baseAddress, Int32(pages.count),
                                                  w.baseAddress, h.baseAddress, title, author)
                }
            }
        }
    }
}
