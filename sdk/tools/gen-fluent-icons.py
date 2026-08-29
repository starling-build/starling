#!/usr/bin/env python3
"""Regenerate FluentSystemIcons.swift from the upstream codepoint map.

    sdk/tools/gen-fluent-icons.py [path/to/FluentSystemIcons-Regular.json]

with no argument, downloads the map from microsoft/fluentui-system-icons.

WHY A CURATED LIST AND NOT ALL OF THEM

The upstream map has 9,708 entries -- every icon at every size. CupertinoIcons
ships all 1,322 of its own because that is the whole font; doing the same here
would be a 9,708-line Swift file to give the shell the sixty glyphs it draws.
So ROLES is the source of truth: it names what the chrome needs, and this
script only looks up the codepoints. The names on the left are the parts the
glyphs play in a Windows shell -- deliberately the same vocabulary as
`sdk/Examples/WinShellBar/FluentIcons.swift`, which does this against Segoe
Fluent Icons on Windows, so the two shells read alike.

A name that upstream has renamed or dropped is a hard error rather than a
silently missing glyph: a role that resolves to nothing draws as nothing, and
"the icon is invisible" is a much worse bug to chase than "the generator
failed".
"""

import json
import os
import sys
import urllib.request

MAP_URL = ("https://raw.githubusercontent.com/microsoft/fluentui-system-icons"
           "/main/fonts/FluentSystemIcons-Regular.json")

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "Sources", "FluentSystemIcons", "FluentSystemIcons.swift")

# role -> upstream name (without the `ic_fluent_` prefix and the size suffix).
# Sizes are tried in PREFERENCE ORDER below; 24 is the chrome's working size.
ROLES = [
    ("— Navigation", None),
    ("back",            "arrow_left"),
    ("forward",         "arrow_right"),
    ("up",              "arrow_up"),
    ("refresh",         "arrow_clockwise"),
    ("search",          "search"),

    ("— Caption buttons: the trio every window title bar draws", None),
    ("chromeMinimize",  "subtract"),
    ("chromeMaximize",  "maximize"),
    # Two overlapping squares, which is what Windows draws for Restore.
    ("chromeRestore",   "square_multiple"),
    ("chromeClose",     "dismiss"),

    ("— Chevrons", None),
    ("chevronUp",       "chevron_up"),
    ("chevronDown",     "chevron_down"),
    ("chevronLeft",     "chevron_left"),
    ("chevronRight",    "chevron_right"),

    ("— The taskbar's status readout", None),
    # Upstream numbers these by BARS REMAINING, not by strength: wifi_1 is
    # full and wifi_4 is a single dot. Naming them by strength here is the
    # whole point -- `wifi4` read as "four bars" and shipped a dot.
    ("wifiFull",        "wifi_1"),
    ("wifiGood",        "wifi_2"),
    ("wifiFair",        "wifi_3"),
    ("wifiWeak",        "wifi_4"),
    ("wifiOff",         "wifi_off"),
    ("wifiWarning",     "wifi_warning"),
    ("ethernet",        "plug_connected"),
    ("network",         "globe"),
    ("bluetooth",       "bluetooth"),
    ("airplane",        "airplane"),
    ("volume",          "speaker_2"),
    ("volumeLow",       "speaker_1"),
    ("mute",            "speaker_off"),
    ("brightness",      "brightness_high"),
    ("battery",         "battery_10"),
    ("batteryHalf",     "battery_5"),
    ("batteryEmpty",    "battery_0"),
    ("batteryCharging", "battery_charge"),
    ("clock",           "clock"),
    ("bell",            "alert"),
    ("bellOff",         "alert_off"),
    ("calendar",        "calendar_ltr"),
    ("accessibility",   "accessibility"),
    ("keyboard",        "keyboard"),

    ("— Start, and the session it can end", None),
    ("allApps",         "apps_list"),
    ("apps",            "apps"),
    ("appDefault",      "app_generic"),
    ("person",          "person"),
    ("power",           "power"),
    ("restart",         "arrow_sync"),
    ("signOut",         "sign_out"),
    ("lock",            "lock_closed"),
    ("moon",            "weather_moon"),
    ("sun",             "weather_sunny"),
    ("bolt",            "flash"),
    ("settings",        "settings"),
    ("personalize",     "paint_brush"),
    ("system",          "desktop"),
    ("pin",             "pin"),
    ("pinOff",          "pin_off"),

    ("— Menus and command bars", None),
    ("add",             "add"),
    ("cut",             "cut"),
    ("copy",            "copy"),
    ("paste",           "clipboard_paste"),
    ("rename",          "rename"),
    ("share",           "share"),
    ("delete",          "delete"),
    ("sort",            "arrow_sort"),
    ("more",            "more_horizontal"),
    ("openExternal",    "open"),
    ("info",            "info"),
    ("link",            "link"),
    ("print",           "print"),
    ("history",         "history"),
    ("favorite",        "star"),
    ("check",           "checkmark"),
    ("close",           "dismiss"),
    ("edit",            "edit"),
    ("grid",            "grid"),
    ("window",          "window"),

    ("— Places", None),
    ("folder",          "folder"),
    ("folderOpen",      "folder_open"),
    ("zip",             "folder_zip"),
    ("home",            "home"),
    ("desktop",         "desktop"),
    ("download",        "arrow_download"),
    ("document",        "document"),
    ("pictures",        "image"),
    ("music",           "music_note_2"),
    ("video",           "video"),
    ("laptop",          "laptop"),
    ("cloud",           "cloud"),
    ("drive",           "hard_drive"),
]

SIZE_PREFERENCE = (24, 20, 28, 32, 16)

HEADER = '''// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// GENERATED by sdk/tools/gen-fluent-icons.py -- edit the ROLES table there,
// not this file.
//
// Fluent UI System Icons: Microsoft's own icon language, from Microsoft's own
// font, under the MIT licence -- so unlike Segoe Fluent Icons (which the
// Windows shell reads straight out of C:\\Windows\\Fonts and which cannot be
// redistributed) this one ships with us.
//
// The names are the ROLES the shell draws them in, not the font's catalogue
// names; the mapping to catalogue names is in the generator, and the mapping
// to codepoints is below. Everything is the 24pt cut unless the font has no
// 24 -- the chrome's working size.

import Flutter
import FlutterSwiftBridge
import Foundation

private let _kFontFamily = "FluentSystemIcons"

/// Icons from Microsoft's Fluent UI System Icons font.
///
/// Call `FluentSystemIcons.registerFont()` at startup before using any icon,
/// exactly like `CupertinoIcons`. Both fonts can be registered in the same
/// process; they carry different family names.
public enum FluentSystemIcons {

    /// The font family every icon below is drawn from.
    public static let iconFont = _kFontFamily

    private nonisolated(unsafe) static var _registered = false

    /// Returns the raw font data for loading into the engine.
    ///
    /// **`Bundle.module` is deliberately not used.** SwiftPM's generated
    /// accessor is a `static let` that calls `fatalError` when neither of its
    /// two candidates resolves, so merely REACHING it crashes -- any search
    /// underneath it never runs. Its second candidate is an absolute path into
    /// the build directory that produced the binary, so it resolves on the
    /// machine that built the app and nowhere else. This is a copy of
    /// `CupertinoIcons.fontData()`; keep the two in step.
    public static func fontData() -> Data {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(exe)
        }
        // `.bundle` is the Darwin name and `.resources` the name SwiftPM uses
        // on Linux and Windows. Searching one suffix silently yields an empty
        // Data() here, which is every icon in the shell drawn as nothing.
        for root in roots {
            for suffix in ["bundle", "resources"] {
                let candidate = root
                    .appendingPathComponent("FlutterSwift_FluentSystemIcons.\\(suffix)")
                if let bundle = Bundle(url: candidate),
                   let url = bundle.url(forResource: "FluentSystemIcons-Regular",
                                        withExtension: "ttf"),
                   let data = try? Data(contentsOf: url) {
                    return data
                }
            }
        }
        // Last resort: straight off disk beside the executable, for a layout
        // Bundle() refuses to open at all.
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        var searchPaths: [String] = []
        for dir in [execDir, "\\(execDir)/.."] {
            for suffix in ["bundle", "resources"] {
                searchPaths.append(
                    "\\(dir)/FlutterSwift_FluentSystemIcons.\\(suffix)"
                    + "/FluentSystemIcons-Regular.ttf")
            }
        }
        for path in searchPaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return data
            }
        }
        return Data()
    }

    /// Registers the font with the Flutter engine. Synchronous; safe to call
    /// more than once.
    @discardableResult
    public static func registerFont() -> Bool {
        guard !_registered else { return true }
        let data = fontData()
        guard !data.isEmpty else { return false }
        let success = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            return flutter.swift_bridge.LoadFontFromList(ptr, data.count, _kFontFamily)
        }
        if success { _registered = true }
        return success
    }
'''


def main() -> int:
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as fh:
            table = json.load(fh)
    else:
        with urllib.request.urlopen(MAP_URL, timeout=60) as resp:
            table = json.load(resp)

    lines = [HEADER]
    missing = []
    for role, name in ROLES:
        if name is None:
            lines.append(f"\n    // {role[2:]}")
            continue
        for size in SIZE_PREFERENCE:
            key = f"ic_fluent_{name}_{size}_regular"
            if key in table:
                lines.append(
                    f"    public static let {role} = "
                    f"IconData(0x{table[key]:04x}, fontFamily: _kFontFamily)"
                    + ("" if size == 24 else f"  // {name}, {size}pt cut"))
                break
        else:
            missing.append((role, name))

    if missing:
        for role, name in missing:
            print(f"error: no glyph for role {role!r} (looked for {name!r})",
                  file=sys.stderr)
        print("upstream renamed or dropped these -- fix ROLES and re-run.",
              file=sys.stderr)
        return 1

    lines.append("}\n")
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print(f"wrote {os.path.normpath(OUT)} "
          f"({len([r for r, n in ROLES if n])} roles)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
