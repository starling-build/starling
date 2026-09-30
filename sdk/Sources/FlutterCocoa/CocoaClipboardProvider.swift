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
        pb.declareTypes(types, owner: nil)
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
        let data = ClipboardData(text: text, rtf: rtf, html: html, png: png)
        let result: ClipboardData? = data.isEmpty ? nil : data
        if Thread.isMainThread {
            completion(result)
        } else {
            DispatchQueue.main.async { completion(result) }
        }
    }
}

#endif
