// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// How to reach a particular host — `~/.config/starling-terminal/hosts`.
//
// `~/.ssh/config` is still the right place for most of this, and nothing here
// replaces it: a key, a user, a port and a jump host all belong there, the
// switcher already reads its `Host` entries, and ssh applies them with no help
// from us. This file exists for the one thing ssh_config cannot express —
// **which program to run** — and for the one thing an environment variable
// cannot survive: being launched from Finder or a dock, where the app inherits
// no shell and `STARLING_SSH` is simply not there.
//
//     # ~/.config/starling-terminal/hosts
//     # <host>    <command that reaches it>
//     prod-1      ssh -i ~/.ssh/id_prod -o IdentitiesOnly=yes
//     lab         /usr/local/bin/ssh-through-jump
//
// The command must accept ssh's flags, because the client appends its own
// (`-T -o BatchMode=yes …`) plus the host and the remote command. A front end
// that does not take them wants a wrapper script that swallows them.
//
// The host is matched EXACTLY, and against what was typed rather than what ssh
// resolves it to. Patterns are ssh_config's job and doing them again here
// would be a second, worse implementation of a thing that already works.

import Flutter
import Foundation


enum HostConfig {
    static var path: String {
        realUserHomeDirectory() + "/.config/starling-terminal/hosts"
    }

    /// The command that reaches `host`, or nil to use the default.
    ///
    /// Read on every call rather than cached: this is consulted when a link is
    /// built, which is rare, and a person editing the file to fix a broken
    /// destination should not have to restart the terminal to find out whether
    /// the fix worked.
    static func ssh(for host: String) -> String? {
        guard !host.isEmpty, host != "local",
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }

        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            // Host, then the rest of the line verbatim — the command keeps its
            // own spacing and quoting, which termdSplitCommand parses.
            guard let cut = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" })
            else { continue }
            let name = String(trimmed[..<cut])
            let command = String(trimmed[cut...]).trimmingCharacters(in: .whitespaces)
            if name == host, !command.isEmpty { return command }
        }
        return nil
    }
}

