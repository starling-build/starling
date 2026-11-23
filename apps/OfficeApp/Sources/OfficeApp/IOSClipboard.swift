// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The iPad's system clipboard for `Clipboard`: UIPasteboard, so Cut/Copy/Paste
// in the editors reaches other apps (Notes, Mail, Pages) and not just this
// process, which is all the no-provider fallback gives. The counterpart of the
// Mac's CocoaClipboardProvider.

#if os(iOS)

import Flutter
import UIKit

final class IOSClipboardProvider: ClipboardProvider {
    private static let text = "public.utf8-plain-text"
    private static let rtf = "public.rtf"
    private static let html = "public.html"
    private static let png = "public.png"

    func setText(_ text: String) {
        UIPasteboard.general.string = text
    }

    func getText(_ completion: @escaping (String?) -> Void) {
        let text = UIPasteboard.general.string
        if Thread.isMainThread { completion(text) } else { DispatchQueue.main.async { completion(text) } }
    }

    /// Every flavour the data carries, under the type other apps look for.
    func setData(_ data: ClipboardData) {
        var item: [String: Any] = [:]
        if let rtf = data.rtf { item[Self.rtf] = Data(rtf.utf8) }
        if let html = data.html { item[Self.html] = Data(html.utf8) }
        if let png = data.png { item[Self.png] = png }
        // A picture alone publishes no string, or a text field would paste "".
        if let text = data.text, !(text.isEmpty && data.png != nil) { item[Self.text] = text }
        guard !item.isEmpty else { return }
        UIPasteboard.general.setItems([item], options: [:])
    }

    func getData(_ completion: @escaping (ClipboardData?) -> Void) {
        let pb = UIPasteboard.general
        let text = pb.string
        let rtf = pb.data(forPasteboardType: Self.rtf).map { String(decoding: $0, as: UTF8.self) }
        let html = pb.data(forPasteboardType: Self.html).map { String(decoding: $0, as: UTF8.self) }
        // A photo or screenshot arrives as PNG, JPEG or HEIC; readers see PNG.
        var png = pb.data(forPasteboardType: Self.png)
        if png == nil, pb.hasImages, let image = pb.image { png = image.pngData() }
        let data = ClipboardData(text: text, rtf: rtf, html: html, png: png)
        let result: ClipboardData? = data.isEmpty ? nil : data
        if Thread.isMainThread { completion(result) } else { DispatchQueue.main.async { completion(result) } }
    }
}

#endif
