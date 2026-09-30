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
        #if os(WASI)
        return true  // the page registered both faces (fonts/manifest.json)
        #endif
        guard !_registered else { return true }
        // The semibold cut goes in under both names: its own, for a style
        // that asks for it by name, and the regular's, so that weight 600
        // inside "Selawik" is this cut rather than a synthesized bold.
        #if os(iOS)
        // Regular only on iOS, and the weight-600 styles synthesized from
        // it (FluentTheme passes no strong family there). Measured on the
        // simulator, engine c2eba62: with both cuts loaded — in one family
        // or two, the semibold once or twice — every run that landed on
        // the Semibold face was shaped with one set of advances and drawn
        // with another ("Document 1" came out "Do cument 1" with its m
        // over its e), and the same bytes registered under two names made
        // even a Regular placeholder draw as accented capitals. Carlito's
        // four cuts in one family are perfect on the same build. The
        // difference is Selawik-Semibold's name table — family "Selawik
        // Semibold", subfamily "Regular", typographic family "Selawik" —
        // which CoreText resolves back to the Regular face when it makes
        // the sized CTFont Impeller draws with, while the tables the shaper
        // read were the Semibold's. Skia on macOS and skwasm do not go
        // through CoreText for the drawing font and are fine. Renaming the
        // cut inside the file would fix it and needs the OFL's reserved-name
        // question answered first; until then, one face.
        let ok = load("Selawik-Regular", as: family)
        #else
        let ok = load("Selawik-Regular", as: family)
            && load("Selawik-Semibold", as: semibold)
            && load("Selawik-Semibold", as: family)
        #endif
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
        #if os(WASI)
        return Data()  // no files; and Bundle is the legacy Foundation layer
        #else
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
        #endif
    }
}
