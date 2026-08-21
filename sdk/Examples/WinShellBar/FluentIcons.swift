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

    // The flyouts' tile roles — Quick Settings and the notification centre.
    static let settings = IconData(0xE713, fontFamily: family)
    static let accessibility = IconData(0xE776, fontFamily: family)
    static let cc = IconData(0xE7F0, fontFamily: family)
    static let project = IconData(0xE7F4, fontFamily: family)
    static let calendar = IconData(0xE787, fontFamily: family)
    static let ringer = IconData(0xEA8F, fontFamily: family)

    // Chevrons.
    static let chevronDown = IconData(0xE70D, fontFamily: family)
    static let chevronUp = IconData(0xE70E, fontFamily: family)
    static let chevronRight = IconData(0xE76C, fontFamily: family)
    static let chevronLeft = IconData(0xE76B, fontFamily: family)

    // The dock's tiles and Start's controls. Verified against the font's
    // own cmap and drawn to be looked at before being trusted -- several of
    // these (SignOut F3B1, the wifi-error EB5E) are not on the Fluent page.
    static let brightness = IconData(0xE706, fontFamily: family)
    static let volume = IconData(0xE767, fontFamily: family)
    static let mute = IconData(0xE74F, fontFamily: family)
    static let wifi = IconData(0xE701, fontFamily: family)
    static let wifiOff = IconData(0xEB5E, fontFamily: family)
    static let ethernet = IconData(0xE839, fontFamily: family)
    /// The antenna with radio waves (InternetSharing) -- the generic
    /// "network" glyph, where the adapter's kind is not the point.
    static let network = IconData(0xE704, fontFamily: family)
    static let bolt = IconData(0xE945, fontFamily: family)
    static let moon = IconData(0xE708, fontFamily: family)
    static let power = IconData(0xE7E8, fontFamily: family)
    static let restart = IconData(0xE777, fontFamily: family)
    static let signOut = IconData(0xF3B1, fontFamily: family)
    static let lock = IconData(0xE72E, fontFamily: family)
    static let edit = IconData(0xE70F, fontFamily: family)
    static let allApps = IconData(0xE71D, fontFamily: family)
    /// The system's own generic-app placeholder (AppIconDefault).
    static let appDefault = IconData(0xECAA, fontFamily: family)
    static let addTo = IconData(0xECC8, fontFamily: family)
    static let removeFrom = IconData(0xECC9, fontFamily: family)
    static let pinned = IconData(0xE842, fontFamily: family)

    // Settings' rows and radios.
    static let system = IconData(0xE770, fontFamily: family)
    static let personalize = IconData(0xE771, fontFamily: family)
    static let radioOn = IconData(0xECCB, fontFamily: family)
    static let radioOff = IconData(0xECCA, fontFamily: family)

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
    static let check = IconData(0xE73E, fontFamily: family)
    static let folder = IconData(0xE8B7, fontFamily: family)

    // Places.
    static let home = IconData(0xEA8A, fontFamily: family)
    static let desktop = IconData(0xE7F4, fontFamily: family)
    static let download = IconData(0xE896, fontFamily: family)
    static let document = IconData(0xE8A5, fontFamily: family)
    static let pictures = IconData(0xE8B9, fontFamily: family)
    static let music = IconData(0xE8D6, fontFamily: family)
    static let video = IconData(0xE714, fontFamily: family)
    static let thisPC = IconData(0xE977, fontFamily: family)
    static let cloud = IconData(0xE753, fontFamily: family)
    /// The sidebar's Network place (the MDL2 "Network" glyph) -- distinct
    /// from `network`, the antenna the status surfaces use.
    static let networkPlaces = IconData(0xE968, fontFamily: family)
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
