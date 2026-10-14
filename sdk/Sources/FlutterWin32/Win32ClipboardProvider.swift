// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Windows)

import Flutter
import FlutterWin32Bridge
import Foundation

/// `Clipboard` for a Flutter-Swift app in a Win32 window, over the system
/// clipboard — so copy and paste reach the rest of Windows.
///
/// Installed by `Win32WindowedHost.install()`.
///
/// Note the shape difference from the other two backends: Win32 hands the data
/// over directly rather than asking the current owner to write it, so a read
/// cannot block on another process and the completion runs inline. The
/// callback signature is kept anyway, because `ClipboardProvider` is what the
/// asynchronous backends need and one protocol beats two.
public final class Win32ClipboardProvider: ClipboardProvider {
    public init() {}

    public func setText(_ text: String) {
        _ = text.withCString { flwin32_clipboard_set_text($0) }
    }

    public func getText(_ completion: @escaping (String?) -> Void) {
        // Grow rather than truncate: -1 means the buffer was too small, and a
        // silently clipped paste is worse than a slow one. The cap stops a
        // pathological clipboard from being copied forever.
        var capacity = 64 * 1024
        while capacity <= 64 * 1024 * 1024 {
            var buffer = [CChar](repeating: 0, count: capacity)
            let written = buffer.withUnsafeMutableBufferPointer { buf in
                flwin32_clipboard_get_text(buf.baseAddress, Int32(buf.count))
            }
            if written == -1 {
                capacity *= 4
                continue
            }
            if written <= 0 {
                completion(nil)       // no text on the clipboard
                return
            }
            completion(String(cString: buffer))
            return
        }
        completion(nil)
    }

    /// Every flavour the data carries, under the names Windows apps look
    /// for: "HTML Format" (Word, Outlook, Excel and browsers paste a table
    /// with its formatting from it), "Rich Text Format", "PNG", and the text.
    /// It was the text alone, so a copy from Sheets or Writer pasted into
    /// Word plain, and a picture not at all.
    public func setData(_ data: ClipboardData) {
        guard flwin32_clipboard_begin() != 0 else { return }
        defer { flwin32_clipboard_end() }
        func put(_ format: String?, _ bytes: [UInt8]) {
            _ = bytes.withUnsafeBufferPointer { buf in
                if let format {
                    return format.withCString { flwin32_clipboard_put($0, buf.baseAddress, Int32(buf.count)) }
                }
                return flwin32_clipboard_put(nil, buf.baseAddress, Int32(buf.count))
            }
        }
        // A picture alone publishes no text, or Notepad would paste "".
        if let text = data.text, !(text.isEmpty && data.png != nil) { put(nil, Array(text.utf8)) }
        if let rtf = data.rtf { put("Rich Text Format", Array(rtf.utf8)) }
        if let html = data.html { put("HTML Format", Self.cfHTML(html)) }
        if let png = data.png { put("PNG", [UInt8](png)) }
    }

    /// What is on the clipboard, in every flavour we read: Excel's and
    /// Word's HTML (header stripped), RTF, a PNG (as Office, browsers and
    /// the Snipping Tool put it), and the text.
    public func getData(_ completion: @escaping (ClipboardData?) -> Void) {
        var text: String? = nil
        getText { text = $0 }
        let html = Self._bytes("HTML Format").map { Self.htmlFromCF($0) }
        let rtf = Self._bytes("Rich Text Format").map { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let png = Self._bytes("PNG").map { Data($0) }
        let data = ClipboardData(text: text, rtf: rtf, html: html, png: png)
        completion(data.isEmpty ? nil : data)
    }

    private static func _bytes(_ format: String) -> [UInt8]? {
        var size = 64 * 1024
        for _ in 0 ..< 4 {
            var buffer = [UInt8](repeating: 0, count: size)
            let n = buffer.withUnsafeMutableBufferPointer { buf in
                format.withCString { flwin32_clipboard_get_format($0, buf.baseAddress, Int32(buf.count)) }
            }
            if n == 0 { return nil }
            if n > 0 { return Array(buffer.prefix(Int(n))) }
            size = Int(-n)
        }
        return nil
    }

    // MARK: CF_HTML

    private static let _startMark = Array("<!--StartFragment-->".utf8)
    private static let _endMark = Array("<!--EndFragment-->".utf8)

    private static func _find(_ needle: [UInt8], in hay: [UInt8], from: Int = 0, caseless: Bool = false, last: Bool = false) -> Int? {
        guard needle.count <= hay.count, from >= 0, from <= hay.count - needle.count else { return nil }
        func lower(_ b: UInt8) -> UInt8 { caseless && b >= 65 && b <= 90 ? b + 32 : b }
        let range = Array(from ... hay.count - needle.count)
        for i in last ? range.reversed() : range {
            var j = 0
            while j < needle.count, lower(hay[i + j]) == lower(needle[j]) { j += 1 }
            if j == needle.count { return i }
        }
        return nil
    }

    /// HTML as Windows' "HTML Format" carries it: a header giving the byte
    /// offsets of the document and of the fragment inside it, the fragment
    /// marked by comments. A full document's body is the fragment.
    static func cfHTML(_ html: String) -> [UInt8] {
        var doc = Array(html.utf8)
        if _find(_startMark, in: doc) == nil || _find(_endMark, in: doc) == nil {
            if let b = _find(Array("<body".utf8), in: doc, caseless: true),
               let gt = doc[b...].firstIndex(of: UInt8(ascii: ">")),
               let e = _find(Array("</body>".utf8), in: doc, caseless: true, last: true), e > gt {
                doc = Array(doc[...gt]) + _startMark + Array(doc[(gt + 1) ..< e]) + _endMark + Array(doc[e...])
            } else {
                doc = Array("<html><body>".utf8) + _startMark + doc + _endMark + Array("</body></html>".utf8)
            }
        }
        func pad(_ n: Int) -> String { let s = String(n); return String(repeating: "0", count: max(0, 10 - s.count)) + s }
        func header(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> [UInt8] {
            Array("Version:0.9\r\nStartHTML:\(pad(a))\r\nEndHTML:\(pad(b))\r\nStartFragment:\(pad(c))\r\nEndFragment:\(pad(d))\r\n".utf8)
        }
        let n = header(0, 0, 0, 0).count
        let start = n + (_find(_startMark, in: doc) ?? 0) + _startMark.count
        let end = n + (_find(_endMark, in: doc) ?? doc.count)
        return header(n, n + doc.count, start, end) + doc
    }

    /// The document inside "HTML Format" bytes: from StartHTML to EndHTML,
    /// or everything after the header when those are missing (-1 is legal).
    static func htmlFromCF(_ bytes: [UInt8]) -> String {
        let all = Array(bytes.prefix { $0 != 0 })
        let head = String(decoding: all.prefix(512), as: UTF8.self)
        func offset(_ key: String) -> Int? {
            guard let r = head.range(of: key + ":") else { return nil }
            return Int(head[r.upperBound...].prefix { $0.isNumber || $0 == "-" })
        }
        if let s = offset("StartHTML"), let e = offset("EndHTML"), s >= 0, s < e, e <= all.count {
            return String(decoding: all[s ..< e], as: UTF8.self)
        }
        if let s = offset("StartFragment"), let e = offset("EndFragment"), s >= 0, s < e, e <= all.count {
            return String(decoding: all[s ..< e], as: UTF8.self)
        }
        let lt = all.firstIndex(of: UInt8(ascii: "<")) ?? 0
        return String(decoding: all[lt...], as: UTF8.self)
    }
}

#endif
