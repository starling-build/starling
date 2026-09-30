// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// The home directory to show the person using the desktop.
///
/// Normally that is just `NSHomeDirectory()`. The exception is dev mode, where
/// the shell is started with `sudo` to get DRM master, so it and every app it
/// spawns inherit `HOME=/root` — and a file picker or terminal opening in
/// `/root` is never what the user meant. `sudo` records who invoked it in
/// `SUDO_USER`, so resolve that account's home through the passwd database
/// rather than guessing at a path.
///
/// In the shipped desktop this never triggers: GDM starts the session as the
/// user, so `NSHomeDirectory()` is already correct.
public func realUserHomeDirectory() -> String {
    #if os(WASI)
    return "/"  // no users, no homes
    #else
    let home = NSHomeDirectory()
    #if os(Linux)
    guard home == "/root" else { return home }
    let env = ProcessInfo.processInfo.environment
    guard let name = env["SUDO_USER"], !name.isEmpty,
          let pw = getpwnam(name), let dir = pw.pointee.pw_dir else { return home }
    let resolved = String(cString: dir)
    return resolved.isEmpty ? home : resolved
    #else
    return home
    #endif
    #endif
}
