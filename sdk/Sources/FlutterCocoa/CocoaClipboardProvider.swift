// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(macOS)

import AppKit
import Flutter

/// `Clipboard` for an app in a Cocoa window, backed by NSPasteboard — so a
/// FlutterSwift app on macOS copies and pastes with the rest of the Mac, not
/// just with itself. The counterpart of `GtkClipboardProvider` and
/// `Win32ClipboardProvider`.
///
/// Installed by `CocoaHost`'s initializer rather than a host-boot hook,
/// because Cocoa surfaces reach that initializer down two roads —
/// `CocoaWindowedHost.install()` and the example hosts' direct `CocoaHost()`
/// — and the GTK precedent of installing at boot left the second road with
/// the process-local fallback clipboard.
///
/// NSPasteboard is synchronous, so `getText` answers immediately; the
/// completion still runs on the main thread exactly once, per the
/// `ClipboardProvider` contract.
public final class CocoaClipboardProvider: ClipboardProvider {
    public init() {}

    public func setText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public func getText(_ completion: @escaping (String?) -> Void) {
        let text = NSPasteboard.general.string(forType: .string)
        if Thread.isMainThread {
            completion(text)
        } else {
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// Every flavour the data carries, under the type each Mac app looks
    /// for: public.rtf, public.html, public.png, and the string.
    public func setData(_ data: ClipboardData) {
        let pb = NSPasteboard.general
        pb.clearContents()
        var types: [NSPasteboard.PasteboardType] = []
        if data.rtf != nil { types.append(.rtf) }
        if data.html != nil { types.append(.html) }
        if data.png != nil { types.append(.png) }
        let text = data.text.flatMap { $0.isEmpty && data.png != nil ? nil : $0 }
        if text != nil { types.append(.string) }
        // An app's private types go under a name of our own, which NSPasteboard keeps (it drops nothing it
        // was told to declare), so they reach another window of the app: Slides' shapes cross as shapes.
        let custom = data.custom.keys.sorted()
        types += custom.map(Self.pasteboardType)
        pb.declareTypes(types, owner: nil)
        for mime in custom { if let bytes = data.custom[mime] { pb.setData(bytes, forType: Self.pasteboardType(mime)) } }
        if let rtf = data.rtf { pb.setData(Data(rtf.utf8), forType: .rtf) }
        if let html = data.html { pb.setData(Data(html.utf8), forType: .html) }
        if let png = data.png { pb.setData(png, forType: .png) }
        // A picture alone publishes no string, or TextEdit would paste "".
        if let text { pb.setString(text, forType: .string) }
    }

    /// What is on the pasteboard, in every flavour we read. A picture
    /// pasted from Preview or a browser arrives as TIFF or PNG; TIFF is
    /// turned into PNG here so readers see one format.
    public func getData(_ completion: @escaping (ClipboardData?) -> Void) {
        let pb = NSPasteboard.general
        let text = pb.string(forType: .string)
        let rtf = pb.data(forType: .rtf).map { String(decoding: $0, as: UTF8.self) }
        let html = pb.data(forType: .html).map { String(decoding: $0, as: UTF8.self) }
        var png = pb.data(forType: .png)
        if png == nil, let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            png = rep.representation(using: .png, properties: [:])
        }
        var custom: [String: Data] = [:]
        for mime in Clipboard.readFormats { custom[mime] = pb.data(forType: Self.pasteboardType(mime)) }
        let data = ClipboardData(text: text, rtf: rtf, html: html, png: png, custom: custom)
        let result: ClipboardData? = data.isEmpty ? nil : data
        if Thread.isMainThread {
            completion(result)
        } else {
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// One private type's bytes (the standard flavours come through `getData`).
    public func getFormat(_ mime: String, _ completion: @escaping (Data?) -> Void) {
        let pb = NSPasteboard.general
        let bytes: Data?
        switch mime {
        case Clipboard.kTextPlain: bytes = pb.string(forType: .string).map { Data($0.utf8) }
        case ClipboardData.mimeHtml: bytes = pb.data(forType: .html)
        case ClipboardData.mimeRtf: bytes = pb.data(forType: .rtf)
        case ClipboardData.mimePng: bytes = pb.data(forType: .png)
        default: bytes = pb.data(forType: Self.pasteboardType(mime))
        }
        completion(bytes)
    }

    /// The MIME types on offer: the standard flavours and any private type of ours.
    public func availableFormats(_ completion: @escaping ([String]) -> Void) {
        let types = NSPasteboard.general.types ?? []
        var out: [String] = []
        if types.contains(.string) { out.append(Clipboard.kTextPlain) }
        if types.contains(.html) { out.append(ClipboardData.mimeHtml) }
        if types.contains(.rtf) { out.append(ClipboardData.mimeRtf) }
        if types.contains(.png) || types.contains(.tiff) { out.append(ClipboardData.mimePng) }
        for t in types where t.rawValue.hasPrefix(Self.privatePrefix) {
            if let mime = Self.mime(t) { out.append(mime) }
        }
        completion(out)
    }

    static let privatePrefix = "org.starling.clipboard."

    /// A private MIME type as a pasteboard type: a reverse-DNS name with the MIME type hex-coded after it,
    /// so any MIME string maps to a legal type name and back.
    static func pasteboardType(_ mime: String) -> NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(privatePrefix + mime.utf8.map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined())
    }

    static func mime(_ type: NSPasteboard.PasteboardType) -> String? {
        let hex = Array(type.rawValue.dropFirst(privatePrefix.count).utf8)
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var i = 0
        while i < hex.count {
            guard let b = UInt8(String(decoding: hex[i ..< i + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(b); i += 2
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

#endif
