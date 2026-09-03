// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The three readings a status bar exists to show: network, power, volume.
//
// Read from the system, not drawn as decoration — a bar with a fixed wifi
// glyph and a fixed battery glyph is a picture of a status bar. The awkward
// parts are in the C (flwin32_status.c); this is the shape the UI wants.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

public struct Win32Power: Sendable, Equatable {
    /// False on a desktop — which is not the same as "0%", and a bar should
    /// draw nothing at all rather than an empty battery.
    public let hasBattery: Bool
    /// 0-100, or nil when Windows will not say.
    public let percent: Int?
    /// On mains. True for a full battery still plugged in, which is what a
    /// bar should show.
    public let isCharging: Bool

    public init(hasBattery: Bool, percent: Int?, isCharging: Bool) {
        self.hasBattery = hasBattery
        self.percent = percent
        self.isCharging = isCharging
    }
}

public enum Win32NetworkKind: Sendable, Equatable {
    case none
    case ethernet
    case wifi
}

public struct Win32Network: Sendable, Equatable {
    public let kind: Win32NetworkKind
    /// 0-100. Only meaningful for wifi; ethernet reports 100.
    public let signal: Int
    /// May be empty even on wifi — an SSID is raw bytes, not required to be
    /// text, and a hidden network has none to give.
    public let ssid: String

    /// Whether this machine has a Wi-Fi interface at all — not whether it is
    /// using one. A desktop has none and should be shown no signal meter; a
    /// laptop with the radio off has one, and an empty meter is the truth.
    public let hasWifiAdapter: Bool

    public var isConnected: Bool { kind != .none }

    public init(kind: Win32NetworkKind, signal: Int, ssid: String,
                hasWifiAdapter: Bool = false) {
        self.kind = kind
        self.signal = signal
        self.ssid = ssid
        self.hasWifiAdapter = hasWifiAdapter
    }
}

public struct Win32Volume: Sendable, Equatable {
    public let percent: Int
    public let isMuted: Bool

    public init(percent: Int, isMuted: Bool) {
        self.percent = percent
        self.isMuted = isMuted
    }
}

public enum Win32Status {

    /// Reads all three. Cheap enough for a once-a-second poll — the volume
    /// call is the expensive one at a few hundred microseconds, and none of
    /// them belongs on a frame.
    ///
    /// Polling rather than subscribing on purpose: each of the three has its
    /// own notification mechanism (a WLAN notification callback,
    /// WM_POWERBROADCAST, an IAudioEndpointVolumeCallback COM object), they
    /// deliver on three different threads, and a status bar that updates a
    /// second late is indistinguishable from one that does not.
    public static func power() -> Win32Power {
        var present: Int32 = 0, percent: Int32 = -1, charging: Int32 = 0
        guard flwin32_power_status(&present, &percent, &charging) != 0 else {
            return Win32Power(hasBattery: false, percent: nil, isCharging: true)
        }
        return Win32Power(hasBattery: present != 0,
                          percent: percent >= 0 ? Int(percent) : nil,
                          isCharging: charging != 0)
    }

    /// The primary monitor's backlight, 0-100, or nil when no monitor
    /// answers DDC/CI — which is common, and means the control should not be
    /// offered at all.
    ///
    /// **Slow.** An I2C round trip to the monitor's firmware, tens to
    /// hundreds of milliseconds. Read it once and after a change, never on a
    /// tick, and never on the thread that draws.
    public static func brightness() -> Int? {
        var percent: Int32 = 0
        guard flwin32_brightness_get(&percent) != 0 else { return nil }
        return Int(percent)
    }

    public static func network() -> Win32Network {
        var kind: Int32 = 0, signal: Int32 = 0, hasWifi: Int32 = 0
        var buffer = [CChar](repeating: 0, count: 128)
        _ = buffer.withUnsafeMutableBufferPointer {
            flwin32_network_status(&kind, &signal, $0.baseAddress, 128, &hasWifi)
        }
        let which: Win32NetworkKind = kind == 2 ? .wifi : kind == 1 ? .ethernet : .none
        return Win32Network(kind: which, signal: Int(signal),
                            ssid: String(cString: buffer),
                            hasWifiAdapter: hasWifi != 0)
    }

    public static func volume() -> Win32Volume? {
        var percent: Int32 = 0, muted: Int32 = 0
        guard flwin32_volume_status(&percent, &muted) != 0 else { return nil }
        return Win32Volume(percent: Int(percent), isMuted: muted != 0)
    }
}

/// What moved. See `Win32Status.watch`.
public enum Win32StatusChange: Sendable {
    /// Power, network or theme — anything `Win32Status`'s readers cover.
    case status
    /// The tray's promoted/hidden split, edited in Windows' own Settings.
    case tray
    /// Explorer put its taskbar back on screen.
    case taskbar
    /// A taskbar preference under Explorer\Advanced — the icon alignment.
    /// Windows tells EXPLORER when Settings writes one of these; a shell that
    /// has replaced explorer hears nothing, so the key is watched directly.
    case prefs
}

extension Win32Status {
    /// Be told when a readout might have changed, rather than asking on a
    /// timer.
    ///
    /// Every source behind these values has a notification — a power
    /// broadcast, WLAN and IP-interface callbacks, a settings broadcast, a
    /// registry change — and the bridge subscribes to all of them on one
    /// thread. The handler runs on the MAIN queue and says only what class of
    /// thing moved: re-reading that class costs microseconds, and it was
    /// asking for it every few seconds that showed up as idle CPU.
    ///
    /// One watcher per process; the second call replaces the handler. False if
    /// the watcher could not start, in which case the caller needs its poll.
    @discardableResult
    public static func watch(_ handler: @escaping (Win32StatusChange) -> Void) -> Bool {
        changeHandler = handler
        return flwin32_status_watch({ _, kind in
            let change: Win32StatusChange
            switch kind {
            case Int32(FLWIN32_STATUS_KIND_TRAY): change = .tray
            case Int32(FLWIN32_STATUS_KIND_TASKBAR): change = .taskbar
            case Int32(FLWIN32_STATUS_KIND_PREFS): change = .prefs
            default: change = .status
            }
            DispatchQueue.main.async { Win32Status.changeHandler?(change) }
        }, nil) != 0
    }

    /// Where the taskbar gathers its icons, from Windows' own setting —
    /// Personalization > Taskbar > "Taskbar alignment".
    ///
    /// True (centred) is what a profile that has never touched it reads as,
    /// because Windows does not write the value until it is changed. A shell
    /// standing in for explorer has to read this itself: nothing tells it.
    public static var taskbarIconsCentred: Bool {
        flwin32_taskbar_alignment() != 0
    }

    /// Whether Windows holds a value at all, which is not the same as what it
    /// says: a profile that has never touched the setting has none, and reads
    /// as centred. For anything folding an older setting into this one.
    public static var taskbarAlignmentIsSet: Bool {
        flwin32_taskbar_alignment_is_set() != 0
    }

    nonisolated(unsafe) fileprivate static var changeHandler:
        ((Win32StatusChange) -> Void)?
}

/// Changing what `Win32Status` reads — the control centre's half.
///
/// Deliberately a separate type. A status bar reads; a control centre writes;
/// and a status widget that can reach a setter by autocomplete is how a
/// readout ends up changing the thing it is meant to be reporting.
public enum Win32Control {

    /// Moves the taskbar's icons, by writing the setting Windows itself
    /// keeps — so Settings shows the change, and explorer's taskbar follows
    /// it on the machines where that is showing.
    ///
    /// One setting, not two. A shell that kept its own copy would disagree
    /// with the Settings page the moment either was touched, and the user
    /// would have two places to set one thing and no way to know which won.
    @discardableResult
    public static func setTaskbarIconsCentred(_ centred: Bool) -> Bool {
        flwin32_set_taskbar_alignment(centred ? 1 : 0) != 0
    }

    /// Sets the primary monitor's backlight. **Slow** — an I2C round trip to
    /// the monitor's firmware; see `Win32Status.brightness()`.
    @discardableResult
    public static func setBrightness(_ percent: Int) -> Bool {
        flwin32_brightness_set(Int32(percent)) != 0
    }

    /// 0–100, on the same scalar scale the reader reports, so a slider set to
    /// what the readout said does not move the volume.
    @discardableResult
    public static func setVolume(_ percent: Int) -> Bool {
        flwin32_volume_set(Int32(percent)) != 0
    }

    @discardableResult
    public static func setMuted(_ muted: Bool) -> Bool {
        flwin32_volume_set_muted(muted ? 1 : 0) != 0
    }

    /// The Wi-Fi radio — the softer of the two switches behind "turn the
    /// network off", and the only one an unelevated shell owns. Disabling the
    /// adapter is an administrator action, and a shell that raises a UAC
    /// prompt to turn Wi-Fi off is not one anybody wants.
    ///
    /// Returns false on a machine with no Wi-Fi at all, which is how the
    /// control centre knows to draw the tile as unavailable rather than as
    /// off.
    @discardableResult
    public static func setWifiRadio(_ on: Bool) -> Bool {
        flwin32_wifi_set_radio(on ? 1 : 0) != 0
    }

    /// Windows' own light/dark setting, which running apps pick up
    /// immediately — it is a real system toggle, not a repaint of our own
    /// chrome.
    public static var isDarkMode: Bool { flwin32_dark_mode() != 0 }

    @discardableResult
    public static func setDarkMode(_ dark: Bool) -> Bool {
        flwin32_set_dark_mode(dark ? 1 : 0) != 0
    }

    /// Night light — Windows' blue-light filter, the same state the native
    /// Quick Settings tile flips. `nil` when this machine has no night-light
    /// state at all, which is how the tile knows to draw as unavailable.
    public static var nightLight: Bool? {
        switch flwin32_night_light() {
        case 1: return true
        case 0: return false
        default: return nil
        }
    }

    @discardableResult
    public static func setNightLight(_ on: Bool) -> Bool {
        flwin32_set_night_light(on ? 1 : 0) != 0
    }

    /// Energy saver, read-only: the OS owns the toggle, so the tile shows
    /// the true state and a press opens the Settings page instead of lying.
    public static var energySaver: Bool? {
        switch flwin32_energy_saver() {
        case 1: return true
        case 0: return false
        default: return nil
        }
    }
}
#endif
