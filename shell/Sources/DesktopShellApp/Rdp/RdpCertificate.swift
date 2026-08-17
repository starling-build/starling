// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation

/// TLS material for both RDP modes. There is no unencrypted path, so a
/// session that cannot produce a certificate does not listen at all.
///
/// Note what this does NOT give you: TLS without NLA authenticates the
/// server to the client and nothing in the other direction, so reaching the
/// port is the only credential. Both modes are LAN/dev only until NLA lands.
enum RdpCertificate {

    /// Configured paths if given, else a self-signed pair generated once
    /// into the session's config dir. Returns nil if neither is possible.
    static func resolve(env: [String: String]) -> (cert: String, key: String)? {
        if let c = env["STARLING_RDP_CERT"], let k = env["STARLING_RDP_KEY"],
           !c.isEmpty, !k.isEmpty {
            return (c, k)
        }
        let dir = "\(LoginUser.configDir)/rdp"
        let cert = "\(dir)/server.crt"
        let key = "\(dir)/server.key"
        let fm = FileManager.default
        if fm.fileExists(atPath: cert), fm.fileExists(atPath: key) {
            return (cert, key)
        }

        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            warn("cannot create \(dir): \(error)")
            return nil
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes",
                       "-days", "3650", "-subj", "/CN=starling",
                       "-keyout", key, "-out", cert]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            warn("openssl failed: \(error)")
            return nil
        }
        guard p.terminationStatus == 0 else {
            warn("openssl exited \(p.terminationStatus)")
            return nil
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key)
        // The dev shell runs as root; the packaged session does not. Without
        // this the generated pair is unreadable to the very session that
        // ships, and the failure reads as "RDP works on my box".
        if getuid() == 0 {
            let uid = LoginUser.uid
            let gid = getpwuid(uid)?.pointee.pw_gid ?? uid
            for path in [dir, cert, key] {
                try? fm.setAttributes([.ownerAccountID: uid,
                                       .groupOwnerAccountID: gid],
                                      ofItemAtPath: path)
            }
        }
        warn("generated self-signed certificate in \(dir)")
        return (cert, key)
    }

    private static func warn(_ msg: String) {
        FileHandle.standardError.write(Data("[Rdp] \(msg)\n".utf8))
    }
}
#endif
