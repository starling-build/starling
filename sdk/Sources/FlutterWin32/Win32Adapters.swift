// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Every network adapter, in the detail a settings page shows.
//
// Distinct from `Win32Status.network()`, which answers the status bar's
// question — "am I online, and how strong is the signal" — from the first
// interface that is up. This is the whole list, with addresses.
//
// Reads only. Changing an address, the DNS servers or an adapter's state
// needs administrator rights, and a page whose switches raise a UAC prompt or
// silently fail is worse than one that reads honestly and hands the rest to
// Windows. `openWindowsSettings()` is that handoff.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

public struct Win32Adapter: Sendable, Equatable, Identifiable {
    public enum Kind: Int32, Sendable {
        case other = 0
        case ethernet = 1
        case wifi = 2
    }

    public let name: String
    public let description: String
    public let kind: Kind
    public let isUp: Bool
    /// Bits per second, as the driver reports the current link — 0 when down.
    public let speed: Int64
    public let ipv4: String
    public let gateway: String
    public let dns: String
    public let mac: String
    public let usesDHCP: Bool

    public var id: String { name + mac }

    /// "1.0 Gbps", "100 Mbps", or empty when the link is down and the figure
    /// would be a leftover.
    public var speedText: String {
        guard isUp, speed > 0 else { return "" }
        if speed >= 1_000_000_000 {
            return String(format: "%.1f Gbps", Double(speed) / 1_000_000_000)
        }
        return "\(speed / 1_000_000) Mbps"
    }
}

public enum Win32Adapters {

    /// Wired first, then the rest — the page is about the cable, and a
    /// machine with six virtual adapters should not bury it.
    public static func all() -> [Win32Adapter] {
        let count = Int(flwin32_adapter_count())
        guard count > 0 else { return [] }

        var adapters: [Win32Adapter] = []
        for index in 0..<count {
            var name = [CChar](repeating: 0, count: 256)
            var description = [CChar](repeating: 0, count: 256)
            var ipv4 = [CChar](repeating: 0, count: 64)
            var gateway = [CChar](repeating: 0, count: 64)
            var dns = [CChar](repeating: 0, count: 160)
            var mac = [CChar](repeating: 0, count: 64)
            var kind: Int32 = 0, up: Int32 = 0, dhcp: Int32 = 0
            var speed: Int64 = 0

            let ok = name.withUnsafeMutableBufferPointer { n in
                description.withUnsafeMutableBufferPointer { d in
                    ipv4.withUnsafeMutableBufferPointer { i in
                        gateway.withUnsafeMutableBufferPointer { g in
                            dns.withUnsafeMutableBufferPointer { s in
                                mac.withUnsafeMutableBufferPointer { m in
                                    flwin32_adapter_info(
                                        Int32(index),
                                        n.baseAddress, 256, d.baseAddress, 256,
                                        i.baseAddress, 64, g.baseAddress, 64,
                                        s.baseAddress, 160, m.baseAddress, 64,
                                        &kind, &up, &speed, &dhcp)
                                }
                            }
                        }
                    }
                }
            }
            guard ok != 0 else { continue }
            adapters.append(Win32Adapter(
                name: String(cString: name),
                description: String(cString: description),
                kind: Win32Adapter.Kind(rawValue: kind) ?? .other,
                isUp: up != 0,
                speed: speed,
                ipv4: String(cString: ipv4),
                gateway: String(cString: gateway),
                dns: String(cString: dns),
                mac: String(cString: mac),
                usesDHCP: dhcp != 0))
        }

        // Wired, then wireless, then everything else; connected before
        // disconnected within each. A page that opens on a disconnected
        // second port is answering the wrong question.
        func rank(_ a: Win32Adapter) -> Int {
            switch a.kind {
            case .ethernet: return a.isUp ? 0 : 1
            case .wifi: return a.isUp ? 2 : 3
            case .other: return a.isUp ? 4 : 5
            }
        }
        return adapters.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : $0.name < $1.name
        }
    }

    /// Windows' own Ethernet page, for everything that needs elevation.
    @discardableResult
    public static func openWindowsSettings() -> Bool {
        flwin32_open_network_settings() != 0
    }
}
#endif
