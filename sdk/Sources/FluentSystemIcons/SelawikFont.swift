// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Fluent style's TEXT, as opposed to its icons.
//
// Windows 11 sets everything in Segoe UI Variable, and typeface is most of
// what a desktop's "feel" is — the same layout in the wrong face still reads
// as the wrong desktop. Segoe is a Windows system font and cannot ship with
// us, so this is **Selawik**: Microsoft's own metric-compatible substitute
// for Segoe UI, released under the SIL Open Font License precisely so that
// software which cannot license Segoe can still lay out as though it had.
// Metric-compatible means every glyph has Segoe's advance width, so text
// occupies the same space to the pixel — the layout the Windows shell was
// tuned against transfers unchanged.
//
// Two weights, which is all Windows 11's chrome uses: Regular for body and
// Semibold for the few things that are emphasised. Roughly 44 KB each.
//
// The bundle search below is `CupertinoIcons.fontData()`'s, for the same
// reasons — see the long note there before changing it.

import Flutter
import FlutterSwiftBridge
import Foundation

/// Selawik, registered under its own family names so a caller asks for it
/// explicitly and nothing else on the desktop changes shape.
public enum SelawikFont {

    /// Ask for this in a `TextStyle(fontFamily:)`.
    public static let family = "Selawik"
    /// The semibold cut is a SEPARATE family rather than a weight of the
    /// first: the engine picks a face by family name here, and registering
    /// two faces under one name is what once left only the last one loaded.
    public static let semibold = "Selawik Semibold"

    private nonisolated(unsafe) static var _registered = false

    /// Registers both cuts with the engine. Safe to call more than once.
    @discardableResult
    public static func registerFont() -> Bool {
        guard !_registered else { return true }
        let ok = load("Selawik-Regular", as: family)
            && load("Selawik-Semibold", as: semibold)
        if ok { _registered = true }
        return ok
    }

    private static func load(_ resource: String, as familyName: String) -> Bool {
        let data = fontData(resource)
        guard !data.isEmpty else { return false }
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            return flutter.swift_bridge.LoadFontFromList(ptr, data.count, familyName)
        }
    }

    /// See `CupertinoIcons.fontData()`: deliberately not `Bundle.module`,
    /// and both the `.bundle` and `.resources` suffixes have to be searched
    /// or the font silently loads as nothing.
    public static func fontData(_ resource: String) -> Data {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(exe)
        }
        for root in roots {
            for suffix in ["bundle", "resources"] {
                let candidate = root
                    .appendingPathComponent("FlutterSwift_FluentSystemIcons.\(suffix)")
                if let bundle = Bundle(url: candidate),
                   let url = bundle.url(forResource: resource, withExtension: "ttf"),
                   let data = try? Data(contentsOf: url) {
                    return data
                }
            }
        }
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        for dir in [execDir, "\(execDir)/.."] {
            for suffix in ["bundle", "resources"] {
                let path = "\(dir)/FlutterSwift_FluentSystemIcons.\(suffix)/\(resource).ttf"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    return data
                }
            }
        }
        return Data()
    }
}
