// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The document faces Office ships: Liberation Sans/Serif/Mono, metric
/// clones of Arial/Times/Courier, so a `.docx` written in those reflows the
/// same here. Registered by path (mmap, shared, evictable), each family's
/// four files under one name — the font manager picks weight and slant.
///
/// Found by searching for the SwiftPM resource bundle, never through
/// `Bundle.module`: that accessor bakes the BUILD directory's absolute path
/// into the binary, so a shipped .app would find its fonts only on the
/// machine that built it (`TerminalView.swift` learned this the hard way).
enum OfficeFonts {
    static let sans = "Liberation Sans"
    static let serif = "Liberation Serif"
    static let mono = "Liberation Mono"

    /// Families the font menu offers. On macOS CoreText resolves any
    /// installed family by name, so a few system faces join the list.
    static var families: [String] {
        var list = [sans, serif, mono]
        #if os(macOS)
        list += ["Helvetica Neue", "Times New Roman", "Georgia", "Menlo", "Avenir Next"]
        #endif
        return list
    }

    nonisolated(unsafe) private static var _registered = false

    private static func _bundle(_ name: String) -> Bundle? {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() { roots.append(exe) }
        for root in roots {
            for suffix in ["bundle", "resources"] {
                if let b = Bundle(url: root.appendingPathComponent("\(name).\(suffix)")) { return b }
            }
        }
        return nil
    }

    @discardableResult
    static func register() -> Bool {
        if _registered { return true }
        _registered = true
        #if os(WASI)
        // The page fetched every face in Resources/fonts and registered it
        // under the family name inside the file, which is the family name
        // above (build/web-app.sh writes fonts/manifest.json).
        return true
        #endif
        // The ribbon's glyphs: the Fluent System Icons face ships in the SDK
        // and is registered by whoever draws it (the shell does the same).
        _ = FluentSystemIcons.registerFont()
        guard let bundle = _bundle("OfficeApp_OfficeApp") else {
            FileHandle.standardError.write("[Office] font bundle not found; documents use the engine's default face\n".data(using: .utf8)!)
            return false
        }
        var ok = true
        for (file, family) in [("LiberationSans", sans), ("LiberationSerif", serif), ("LiberationMono", mono)] {
            for variant in ["Regular", "Bold", "Italic", "BoldItalic"] {
                let path = bundle.bundleURL.appendingPathComponent("fonts/\(file)-\(variant).ttf").path
                if !flutter.swift_bridge.LoadFontFromFile(path, family) {
                    ok = false
                    FileHandle.standardError.write("[Office] could not load \(path)\n".data(using: .utf8)!)
                }
            }
        }
        return ok
    }
}
