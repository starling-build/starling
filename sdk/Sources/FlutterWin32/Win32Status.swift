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

    public var isConnected: Bool { kind != .none }

    public init(kind: Win32NetworkKind, signal: Int, ssid: String) {
        self.kind = kind
        self.signal = signal
        self.ssid = ssid
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

    public static func network() -> Win32Network {
        var kind: Int32 = 0, signal: Int32 = 0
        var buffer = [CChar](repeating: 0, count: 128)
        _ = buffer.withUnsafeMutableBufferPointer {
            flwin32_network_status(&kind, &signal, $0.baseAddress, 128)
        }
        let which: Win32NetworkKind = kind == 2 ? .wifi : kind == 1 ? .ethernet : .none
        return Win32Network(kind: which, signal: Int(signal),
                            ssid: String(cString: buffer))
    }

    public static func volume() -> Win32Volume? {
        var percent: Int32 = 0, muted: Int32 = 0
        guard flwin32_volume_status(&percent, &muted) != 0 else { return nil }
        return Win32Volume(percent: Int(percent), isMuted: muted != 0)
    }
}

/// Changing what `Win32Status` reads — the control centre's half.
///
/// Deliberately a separate type. A status bar reads; a control centre writes;
/// and a status widget that can reach a setter by autocomplete is how a
/// readout ends up changing the thing it is meant to be reporting.
public enum Win32Control {

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
}
#endif
