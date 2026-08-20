// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What the Settings app reports, and the two things it changes that are not
// already in `Win32Control`.
//
// Split from `Win32Status` because they answer different questions on
// different clocks: the status bar asks "what is the volume right now" once a
// second, and this asks "what machine is this" once, when a pane is opened.
// Everything here is slow enough to matter — registry reads, adapter
// enumeration, a mode change that restarts the display pipeline — so it is
// all called from a bloc's `Task.detached`, never from the thread that draws.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

/// One display mode the adapter offers.
public struct Win32DisplayMode: Sendable, Equatable, Identifiable {
    public let width: Int
    public let height: Int
    public let refresh: Int
    public var id: String { "\(width)x\(height)@\(refresh)" }
    public var label: String { "\(width) × \(height)" }
}

/// One fixed drive.
public struct Win32Drive: Sendable, Equatable, Identifiable {
    public let letter: String
    public let total: Int64
    public let free: Int64
    public var id: String { letter }
    public var used: Int64 { max(0, total - free) }
    public var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

/// Everything the About pane shows, gathered in one pass.
public struct Win32MachineInfo: Sendable, Equatable {
    public var osName = ""
    public var osBuild = ""
    public var deviceName = ""
    public var cpuName = ""
    public var cpuCores = 0
    public var totalRam: Int64 = 0
    public var availableRam: Int64 = 0
    public var gpuName = ""
    public var powerScheme = ""
}

/// The shell's own dialogs.
public enum Win32Dialog {
    /// Asks the user for an image. **Blocks** until they answer, so it belongs
    /// on a background task — and returns nil if they cancel.
    public static func openImage() -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_pick_image($0.baseAddress, 1024)
        }
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }
}

public enum Win32SystemInfo {

    /// Whether the user's APPS theme is light -- the value Explorer's own
    /// chrome follows (AppsUseLightTheme), not the taskbar's separate
    /// SystemUsesLightTheme. Read it once at startup; Windows apps restyle
    /// on WM_SETTINGCHANGE, which nothing here listens for yet.
    public static func appsUseLightTheme() -> Bool {
        flwin32_apps_use_light_theme() != 0
    }

    /// One pass over everything the About pane needs. **Slow** — several
    /// registry reads and an adapter enumeration.
    public static func machine() -> Win32MachineInfo {
        var info = Win32MachineInfo()
        info.osName = string { flwin32_os_name($0, $1) }
        info.osBuild = string { flwin32_os_build($0, $1) }
        info.deviceName = string { flwin32_device_name($0, $1) }
        // The registry's brand string is padded to a fixed width — "AMD Ryzen
        // 7 8845HS w/ Radeon 780M Graphics     " — and those spaces reach the
        // UI as a ragged right edge nobody can explain.
        info.cpuName = string { flwin32_cpu_name($0, $1) }
            .trimmingCharacters(in: .whitespaces)
        info.cpuCores = Int(flwin32_cpu_cores())
        info.totalRam = Int64(flwin32_total_ram())
        info.availableRam = Int64(flwin32_available_ram())
        info.gpuName = string { flwin32_gpu_name($0, $1) }
        info.powerScheme = string { flwin32_power_scheme($0, $1) }
        return info
    }

    public static func displayModes() -> [Win32DisplayMode] {
        var buffer = [Int32](repeating: 0, count: 64 * 3)
        let count = buffer.withUnsafeMutableBufferPointer {
            flwin32_display_modes($0.baseAddress, 64)
        }
        guard count > 0 else { return [] }
        let modes = (0..<Int(count)).map { i in
            Win32DisplayMode(width: Int(buffer[i * 3]),
                             height: Int(buffer[i * 3 + 1]),
                             refresh: Int(buffer[i * 3 + 2]))
        }
        // BIGGEST FIRST. The adapter enumerates ascending, so a list taken
        // from the front is a list of resolutions nobody wants — 1024x768 at
        // the top and the panel's native mode off the end of it. A display
        // pane opens on the mode the screen is actually in.
        return modes.sorted {
            ($0.width * $0.height, $0.refresh) > ($1.width * $1.height, $1.refresh)
        }
    }

    public static func currentDisplayMode() -> Win32DisplayMode? {
        var width: Int32 = 0, height: Int32 = 0, refresh: Int32 = 0
        guard flwin32_display_current(&width, &height, &refresh) != 0 else {
            return nil
        }
        return Win32DisplayMode(width: Int(width), height: Int(height),
                                refresh: Int(refresh))
    }

    /// Changes the mode and remembers it. **Restarts the display pipeline** —
    /// the screen goes black for a moment and every window is relaid out, so
    /// this is not something to call speculatively.
    @discardableResult
    public static func setDisplayMode(_ mode: Win32DisplayMode) -> Bool {
        flwin32_display_set(Int32(mode.width), Int32(mode.height),
                            Int32(mode.refresh)) != 0
    }

    public static func drives() -> [Win32Drive] {
        var letters = [CChar](repeating: 0, count: 64)
        var totals = [Int64](repeating: 0, count: 26)
        var frees = [Int64](repeating: 0, count: 26)
        let count = letters.withUnsafeMutableBufferPointer { l in
            totals.withUnsafeMutableBufferPointer { t in
                frees.withUnsafeMutableBufferPointer { f in
                    flwin32_drives(l.baseAddress, 64, t.baseAddress,
                                   f.baseAddress, 26)
                }
            }
        }
        guard count > 0 else { return [] }
        return (0..<Int(count)).map { i in
            Win32Drive(letter: String(cString: Array(letters[(i * 2)...])),
                       total: totals[i], free: frees[i])
        }
    }

    public static func wallpaper() -> String {
        string { flwin32_get_wallpaper($0, $1) }
    }

    @discardableResult
    public static func setWallpaper(_ path: String) -> Bool {
        flwin32_set_wallpaper(path) != 0
    }

    // MARK: - Private

    private static func string(
        _ read: (UnsafeMutablePointer<CChar>?, Int32) -> Int32
    ) -> String {
        var buffer = [CChar](repeating: 0, count: 512)
        let n = buffer.withUnsafeMutableBufferPointer { read($0.baseAddress, 512) }
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }
}
#endif
