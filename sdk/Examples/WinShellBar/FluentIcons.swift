// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Windows' own icon language, from Windows' own font.
//
// Segoe Fluent Icons is what Explorer, the taskbar and every inbox surface
// draw their chrome with -- the arrows, the caption buttons, the command
// glyphs. Using it is not imitation, it is the same font: registered
// straight from C:\Windows\Fonts, so the glyphs are pixel-identical to the
// Explorer sitting beside this window, and they move with the OS when
// Microsoft redraws them. Windows 10 ships the same codepoints as Segoe
// MDL2 Assets, which is the fallback.
//
// The names here are the ROLES the shell uses them for, not the font's
// catalogue names -- the mapping to codepoints is the part worth reading.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import Foundation

enum FluentIcons {
    static let family = "Segoe Fluent Icons"

    nonisolated(unsafe) private static var registered = false

    /// Registers the SYSTEM's icon font with the engine. Call at startup,
    /// like CupertinoIcons.registerFont.
    @discardableResult
    static func registerFont() -> Bool {
        guard !registered else { return true }
        // Win11's Segoe Fluent Icons; Win10's MDL2 shares the codepoints.
        let candidates = ["C:\\Windows\\Fonts\\SegoeIcons.ttf",
                          "C:\\Windows\\Fonts\\segmdl2.ttf"]
        guard let path = candidates.first(
                  where: { FileManager.default.fileExists(atPath: $0) }),
              let data = FileManager.default.contents(atPath: path),
              !data.isEmpty else {
            return false
        }
        let ok = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            return flutter.swift_bridge.LoadFontFromList(ptr, data.count, family)
        }
        registered = ok
        return ok
    }

    // Navigation.
    static let back = IconData(0xE72B, fontFamily: family)
    static let forward = IconData(0xE72A, fontFamily: family)
    static let up = IconData(0xE74A, fontFamily: family)
    static let refresh = IconData(0xE72C, fontFamily: family)
    static let search = IconData(0xE721, fontFamily: family)

    // Chevrons.
    static let chevronDown = IconData(0xE70D, fontFamily: family)
    static let chevronUp = IconData(0xE70E, fontFamily: family)
    static let chevronRight = IconData(0xE76C, fontFamily: family)

    // The command bar and the menu's verbs.
    static let add = IconData(0xE710, fontFamily: family)
    static let cut = IconData(0xE8C6, fontFamily: family)
    static let copy = IconData(0xE8C8, fontFamily: family)
    static let paste = IconData(0xE77F, fontFamily: family)
    static let rename = IconData(0xE8AC, fontFamily: family)
    static let share = IconData(0xE72D, fontFamily: family)
    static let delete = IconData(0xE74D, fontFamily: family)
    static let sort = IconData(0xE8CB, fontFamily: family)
    static let viewAll = IconData(0xE8A9, fontFamily: family)
    static let more = IconData(0xE712, fontFamily: family)
    static let openExternal = IconData(0xE8A7, fontFamily: family)
    static let info = IconData(0xE946, fontFamily: family)
    static let link = IconData(0xE71B, fontFamily: family)
    static let print = IconData(0xE749, fontFamily: family)
    static let admin = IconData(0xEA18, fontFamily: family)
    static let history = IconData(0xE81C, fontFamily: family)
    static let favorite = IconData(0xE734, fontFamily: family)
    static let pin = IconData(0xE718, fontFamily: family)
    static let zip = IconData(0xE7B8, fontFamily: family)

    // Places.
    static let home = IconData(0xEA8A, fontFamily: family)
    static let desktop = IconData(0xE7F4, fontFamily: family)
    static let download = IconData(0xE896, fontFamily: family)
    static let document = IconData(0xE8A5, fontFamily: family)
    static let pictures = IconData(0xE8B9, fontFamily: family)
    static let music = IconData(0xE8D6, fontFamily: family)
    static let video = IconData(0xE714, fontFamily: family)
    static let thisPC = IconData(0xE977, fontFamily: family)
    static let drive = IconData(0xEDA2, fontFamily: family)
    static let folderFill = IconData(0xE8D5, fontFamily: family)
    static let folderOpen = IconData(0xE838, fontFamily: family)
    static let page = IconData(0xE7C3, fontFamily: family)

    // The caption trio and the tab's close -- the EXACT glyphs the system
    // titlebar draws (ChromeMinimize/Maximize/Restore/Close).
    static let chromeMinimize = IconData(0xE921, fontFamily: family)
    static let chromeMaximize = IconData(0xE922, fontFamily: family)
    static let chromeRestore = IconData(0xE923, fontFamily: family)
    static let chromeClose = IconData(0xE8BB, fontFamily: family)
    static let close = IconData(0xE711, fontFamily: family)
}
#endif
