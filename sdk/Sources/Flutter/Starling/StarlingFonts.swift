// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The faces the SDK ships, loaded on demand by family name.
//
// Three modules used to carry their own copy of the same bundle search and
// their own "registered" flag (`CupertinoIcons`, `FluentSystemIcons`,
// `SelawikFont`), and every app had to remember to call each one it used
// before its first frame. Forgetting is silent: the engine has no face for
// the family, falls back, and draws a tofu box per icon — which is how a
// Fluent page came up with two hollow rectangles where its pane icons
// should have been. So the loader lives here, in the module the `Icon`
// widget and `StarlingApp` are in, and both ask for a family the moment
// they are about to draw with it. The icon modules' `registerFont()` calls
// are still there and still work; they are now this, by another name.
//
// Registration is per process and per family, once. The engine must be up
// (`LoadFontFromList` is a call into it), which is why this is done from a
// widget's build and not from a module initialiser.

import FlutterSwiftBridge
import Foundation

public enum StarlingFonts {
    /// Where each bundled family lives: the SwiftPM resource bundle that
    /// carries it, and the file inside. The bundle name is the package's
    /// `<package>_<target>`; the suffix differs by platform and is searched
    /// below.
    private static let bundled: [String: (bundle: String, resource: String)] = [
        "CupertinoIcons":    ("FlutterSwift_CupertinoIcons",    "CupertinoIcons"),
        "FluentSystemIcons": ("FlutterSwift_FluentSystemIcons", "FluentSystemIcons-Regular"),
        "Selawik":           ("FlutterSwift_FluentSystemIcons", "Selawik-Regular"),
        "Selawik Semibold":  ("FlutterSwift_FluentSystemIcons", "Selawik-Semibold"),
    ]

    private nonisolated(unsafe) static var _registered: Set<String> = []
    /// Families that could not be found or loaded. Remembered so a build
    /// that draws a hundred icons does not repeat a hundred bundle searches
    /// a frame; the outcome does not change while the process runs.
    private nonisolated(unsafe) static var _failed: Set<String> = []

    /// Loads `family` into the engine if it is one of ours and not yet
    /// loaded. Families the SDK does not ship (a system face, nil, "") are
    /// left to the engine's own fallback and return false.
    @discardableResult
    public static func ensure(_ family: String?) -> Bool {
        guard let family, !family.isEmpty else { return false }
        if _registered.contains(family) { return true }
        if _failed.contains(family) { return false }
        guard let entry = bundled[family] else { return false }
        let data = resourceData(bundle: entry.bundle, resource: entry.resource, ext: "ttf")
        guard !data.isEmpty, load(data, as: family) else {
            _failed.insert(family)
            return false
        }
        _registered.insert(family)
        return true
    }

    /// Whether `family` has been loaded by this loader.
    public static func isRegistered(_ family: String) -> Bool {
        _registered.contains(family)
    }

    /// Hands font bytes to the engine under `family`. For a face that is not
    /// in the table above — an app's own bundled font.
    @discardableResult
    public static func load(_ data: Data, as family: String) -> Bool {
        guard !data.isEmpty else { return false }
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            return flutter.swift_bridge.LoadFontFromList(ptr, data.count, family)
        }
    }

    /// A file out of a SwiftPM resource bundle, found the way a shipped app
    /// finds it.
    ///
    /// **`Bundle.module` is deliberately not used.** SwiftPM's generated
    /// accessor is a `static let` that calls `fatalError` when neither of
    /// its two candidates resolves, so merely REACHING it crashes — any
    /// search underneath it never runs. Its second candidate is an absolute
    /// path into the build directory that produced the binary, so it
    /// resolves on the machine that built the app and nowhere else.
    ///
    /// `.bundle` is the Darwin name and `.resources` the name SwiftPM uses
    /// on Linux and Windows; searching one suffix silently yields nothing.
    /// The last resort is straight off disk beside the executable and one
    /// directory up — the staged desktop keeps apps in `lib/apps/` and the
    /// bundles in `lib/`.
    public static func resourceData(bundle: String, resource: String, ext: String) -> Data {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(exe)
            roots.append(exe.deletingLastPathComponent())
        }
        for root in roots {
            for suffix in ["bundle", "resources"] {
                let candidate = root.appendingPathComponent("\(bundle).\(suffix)")
                if let b = Bundle(url: candidate),
                   let url = b.url(forResource: resource, withExtension: ext),
                   let data = try? Data(contentsOf: url) {
                    return data
                }
            }
        }
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        for dir in [execDir, "\(execDir)/.."] {
            for suffix in ["bundle", "resources"] {
                let path = "\(dir)/\(bundle).\(suffix)/\(resource).\(ext)"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    return data
                }
            }
        }
        return Data()
    }
}
