// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What this module takes for granted that WASI does not supply. The Flutter
// module has its own copy of the same stand-in (internal there, so it did not
// travel with the layout stack out of sdk/).

#if os(WASI)
import Foundation
import WASILibc

/// Only the two standard streams; there is no file to open. Shadows
/// Foundation's `FileHandle`, whose class does not link on the web.
final class FileHandle: Sendable {
    static let standardError = FileHandle(descriptor: 2)
    static let standardOutput = FileHandle(descriptor: 1)
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }

    func write(_ data: Data) {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = WASILibc.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if n <= 0 { break }
                offset += n
            }
        }
    }
}
#endif
