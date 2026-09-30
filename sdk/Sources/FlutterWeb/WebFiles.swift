// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Files in a tab: there is no filesystem, there is the browser's picker and
// its downloads. Open is asynchronous (the user chooses); save is a
// download the browser names and places.

import CSkwasm
import Foundation

public enum WebFiles {
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

    static func opened(_ picked: Picked?) {
        let completion = pending
        pending = nil
        completion?(picked)
    }
}
