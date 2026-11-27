// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Files in a tab: there is no filesystem, there is the browser's picker and
// its downloads. Open is asynchronous (the user chooses); save is a
// download the browser names and places.

import CSkwasm
import Foundation

public enum WebFiles {
    /// Documents supplied by the page before the app mounts (presentation embeds).
    public nonisolated(unsafe) static var startupFiles: [String: Data] = [:]

    /// An open file's name and bytes.
    public struct Picked {
        public let name: String
        public let data: Data
    }

    nonisolated(unsafe) private static var pending: ((Picked?) -> Void)?

    /// Shows the browser's file picker for the given extensions. The
    /// completion runs when a file is chosen; a cancelled pick is never
    /// reported (the browser does not reliably say), and a second open
    /// supersedes the first, whose completion then gets nil.
    public static func open(extensions: [String], _ completion: @escaping (Picked?) -> Void) {
        pending?(nil)
        pending = completion
        var accept = extensions.joined(separator: ",")
        accept.withUTF8 { starling_host_open_file($0.baseAddress, UInt32($0.count)) }
    }

    /// Hands the browser a file to download.
    public static func download(_ data: Data, as name: String) {
        var name = name
        name.withUTF8 { nameBytes in
            data.withUnsafeBytes { bytes in
                starling_host_download(
                    nameBytes.baseAddress, UInt32(nameBytes.count),
                    bytes.baseAddress, UInt32(bytes.count))
            }
        }
    }

    /// Hands the browser a PDF to print: its print dialog opens on it.
    public static func print(_ data: Data, as name: String) {
        var name = name
        name.withUTF8 { nameBytes in
            data.withUnsafeBytes { bytes in
                starling_host_print_pdf(
                    nameBytes.baseAddress, UInt32(nameBytes.count),
                    bytes.baseAddress, UInt32(bytes.count))
            }
        }
    }

    /// A recovery copy a closed tab left: offered by the page before the app starts.
    public struct RecoveryRow {
        public let id: String
        public let kind: String
        public let name: String
        public let data: Data
    }

    /// The rows offered at start-up, newest first, not yet taken.
    public nonisolated(unsafe) static var recoveryOffers: [RecoveryRow] = []

    /// Writes this tab's recovery copy (replacing the last one).
    public static func keepRecovery(kind: String, name: String, data: Data) {
        var meta = kind + "\n" + name
        meta.withUTF8 { metaBytes in
            data.withUnsafeBytes { bytes in
                starling_host_recovery_keep(
                    metaBytes.baseAddress, UInt32(metaBytes.count),
                    bytes.baseAddress, UInt32(bytes.count))
            }
        }
    }

    /// Recent files: the names the page keeps, newest first (handed over before the app starts, then kept in
    /// step with `keepRecent`, so the list is there without a round trip).
    public nonisolated(unsafe) static var recentNames: [String] = []
    nonisolated(unsafe) static var recentPending: [String: [(Data?) -> Void]] = [:]

    /// The page keeps `data` under `name`, at the top of Recent (newest 20).
    public static func keepRecent(_ name: String, _ data: Data) {
        recentNames.removeAll { $0 == name }
        recentNames.insert(name, at: 0)
        if recentNames.count > 20 { recentNames.removeLast(recentNames.count - 20) }
        var name = name
        name.withUTF8 { nameBytes in
            data.withUnsafeBytes { bytes in
                starling_host_recent_keep(nameBytes.baseAddress, UInt32(nameBytes.count),
                                          bytes.baseAddress, UInt32(bytes.count))
            }
        }
    }

    /// Deletes this tab's recovery copy.
    public static func discardRecovery() { starling_host_recovery_discard() }

    /// The newest offered copy of this kind, made this tab's own.
    public static func takeRecovery(kind: String) -> RecoveryRow? {
        guard let i = recoveryOffers.firstIndex(where: { $0.kind == kind }) else { return nil }
        let row = recoveryOffers.remove(at: i)
        var id = row.id
        id.withUTF8 { starling_host_recovery_adopt($0.baseAddress, UInt32($0.count)) }
        return row
    }

    /// The kept copy of `name`, read back from the page's storage; nil (and gone from the list) when it is not
    /// there any more.
    public static func openRecent(_ name: String, _ done: @escaping (Data?) -> Void) {
        recentPending[name, default: []].append(done)
        var name = name
        name.withUTF8 { starling_host_recent_open($0.baseAddress, UInt32($0.count)) }
    }

    static func recentOpened(_ name: String, _ data: Data?) {
        if data == nil { recentNames.removeAll { $0 == name } }
        let waiting = recentPending.removeValue(forKey: name) ?? []
        for done in waiting { done(data) }
    }

    static func opened(_ picked: Picked?) {
        let completion = pending
        pending = nil
        completion?(picked)
    }
}
