// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The child process a termd client talks through, and nothing else.
//
// `ssh host starling-termd --stdio` is one pipe pair to a child, on every
// platform; what differs is only how the child is started. RemoteTerminal
// owned this privately while it was the only client, but a workspace
// (docs/plans/remote-workspace.md) needs a SECOND connection — one that
// carries the WS_* frames and no session at all — and two copies of a fork
// site is how two transports drift.
//
// `read` returns a positive count, `0` for "nothing within the timeout" (the
// caller uses that tick for ACK and heartbeat), or `-1` for end of stream.

#if os(Linux) || os(macOS) || os(Windows)

import Foundation
#if os(Linux)
import Glibc
#elseif os(Windows)
import CStarlingConPTY
import WinSDK
#else
import Darwin
#endif
// Only for `starling_close_extra_fds`, and only on the fork path. Guarded by
// canImport rather than by platform so this file also compiles standalone —
// test/workspace/workspace-test.swift builds it with swiftc against a real
// daemon, the same shape as the layout codec's test, and a test binary has no
// app plumbing to keep out of the child.
#if canImport(CTerminalCore)
import CTerminalCore
#endif

#if !os(Windows)
// The class below has methods called `read`, `write` and `close`, which win
// the overload against the C functions of those names. Naming the module is
// the fix, and the module's name is the one thing that differs by platform.
@inline(__always)
private func _sysRead(_ fd: Int32, _ buf: UnsafeMutableRawPointer?, _ n: Int) -> Int {
    #if os(Linux)
    return Glibc.read(fd, buf, n)
    #else
    return Darwin.read(fd, buf, n)
    #endif
}
@inline(__always)
private func _sysWrite(_ fd: Int32, _ buf: UnsafeRawPointer?, _ n: Int) -> Int {
    #if os(Linux)
    return Glibc.write(fd, buf, n)
    #else
    return Darwin.write(fd, buf, n)
    #endif
}
@inline(__always)
private func _sysClose(_ fd: Int32) {
    #if os(Linux)
    _ = Glibc.close(fd)
    #else
    _ = Darwin.close(fd)
    #endif
}
#endif

/// How a client reaches a daemon: `ssh host starling-termd --stdio`, or the
/// daemon directly when the host is local.
///
/// Only "local" (and the empty string) skips ssh. `localhost` is a real ssh
/// destination and must go through it — quietly short-circuiting the
/// transport for the one host most likely to be used for testing it would
/// hide exactly the bugs that testing is for.
func termdArgv(host: String, sshPath: String, serverPath: String) -> [String] {
    if host.isEmpty || host == "local" {
        return [serverPath, "--stdio"]
    }
    // -T: no tty on the ssh channel. The stream must be the session's bytes
    // and nothing else — a pty in the middle would mangle them.
    return [sshPath, "-T", "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=15", host, serverPath, "--stdio"]
}

/// The environment a termd client is reached through, defaults included.
struct TermdPaths {
    let ssh: String
    let server: String

    /// Overridable because not every site reaches its machines with the stock
    /// `ssh` (a wrapper, a jump script, a different binary), and because a
    /// test needs to drive the transport without an sshd.
    init(ssh: String? = nil, server: String? = nil) {
        let env = ProcessInfo.processInfo.environment
        self.ssh = ssh ?? env["STARLING_SSH"] ?? "ssh"
        self.server = server ?? env["STARLING_TERMD"] ?? "starling-termd"
    }
}

/// The `ssh` child and its two pipes — the only part of a termd transport
/// that is platform-specific at all. Everything above it (framing, byte
/// offsets, reconnect, the protocol itself) is the same code everywhere,
/// which is the point of isolating it here rather than sprinkling `#if`
/// through a read loop.
final class ChildLink {
#if os(Linux) || os(macOS)
    private var pid: pid_t
    private let toChild: Int32
    private let fromChild: Int32

    private init(pid: pid_t, toChild: Int32, fromChild: Int32) {
        self.pid = pid
        self.toChild = toChild
        self.fromChild = fromChild
    }

    static func spawn(_ argv: [String]) -> ChildLink? {
        var inPipe: [Int32] = [-1, -1]
        var outPipe: [Int32] = [-1, -1]
        guard pipe(&inPipe) == 0, pipe(&outPipe) == 0 else { return nil }

        var cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cargs.append(nil)
        defer { cargs.forEach { free($0) } }

        #if os(Linux)
        let pid = fork()
        if pid < 0 { return nil }
        if pid == 0 {
            dup2(inPipe[0], 0)
            dup2(outPipe[1], 1)
            _sysClose(inPipe[0]); _sysClose(inPipe[1])
            _sysClose(outPipe[0]); _sysClose(outPipe[1])
            // ssh needs 0/1/2 and nothing this process was holding.
            #if canImport(CTerminalCore)
            starling_close_extra_fds()
            #endif
            if let program = cargs[0] { execvp(program, &cargs) }
            _exit(127)
        }
        #else
        // Darwin: Swift's overlay marks `fork()` unavailable outright, so the
        // child is described rather than run. POSIX_SPAWN_CLOEXEC_DEFAULT is
        // this platform's `starling_close_extra_fds` — everything not named in
        // a file action is closed across the exec — which is why stderr has to
        // be named too, or ssh's diagnostics would go to a closed descriptor.
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, 2, 2)
        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        var envp: [UnsafeMutablePointer<CChar>?] =
            ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { envp.forEach { free($0) } }

        var pid: pid_t = -1
        let rc = posix_spawnp(&pid, cargs[0], &actions, &attrs, &cargs, &envp)
        if rc != 0 || pid < 0 {
            _sysClose(inPipe[0]); _sysClose(inPipe[1])
            _sysClose(outPipe[0]); _sysClose(outPipe[1])
            return nil
        }
        #endif

        _sysClose(inPipe[0])
        _sysClose(outPipe[1])
        return ChildLink(pid: pid, toChild: inPipe[1], fromChild: outPipe[0])
    }

    func read(into buf: inout [UInt8], timeoutMs: Int32) -> Int {
        var pfd = pollfd(fd: fromChild, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pfd, 1, timeoutMs)
        if ready < 0 { return errno == EINTR ? 0 : -1 }
        if ready == 0 { return 0 }
        if (pfd.revents & Int16(POLLIN)) != 0 {
            let n = _sysRead(fromChild, &buf, buf.count)
            return n <= 0 ? -1 : n
        }
        if (pfd.revents & Int16(POLLHUP | POLLERR)) != 0 { return -1 }
        return 0
    }

    func write(_ frame: [UInt8]) {
        var off = 0
        frame.withUnsafeBufferPointer { buf in
            while off < buf.count {
                let n = _sysWrite(toChild, buf.baseAddress! + off, buf.count - off)
                if n > 0 { off += n; continue }
                if errno == EINTR { continue }
                break
            }
        }
    }

    func close() {
        if toChild >= 0 { _sysClose(toChild) }
        if fromChild >= 0 { _sysClose(fromChild) }
        if pid > 0 {
            kill(pid, SIGTERM)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            pid = -1
        }
    }
#else
    private var handle: OpaquePointer?

    private init(handle: OpaquePointer) { self.handle = handle }

    static func spawn(_ argv: [String]) -> ChildLink? {
        guard let h = starling_child_spawn(commandLine(argv)) else { return nil }
        return ChildLink(handle: h)
    }

    /// argv -> one command line, by the rules CommandLineToArgvW undoes.
    /// Backslashes are literal except before a quote, where they must be
    /// doubled — the case that matters here, since every Windows path in an
    /// `-o` option or an ssh binary override ends up inside these quotes.
    private static func commandLine(_ argv: [String]) -> String {
        argv.map { arg -> String in
            if !arg.isEmpty && !arg.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" }) {
                return arg
            }
            var out = "\""
            var slashes = 0
            for ch in arg {
                if ch == "\\" {
                    slashes += 1
                } else if ch == "\"" {
                    out += String(repeating: "\\", count: slashes * 2 + 1) + "\""
                    slashes = 0
                } else {
                    out += String(repeating: "\\", count: slashes) + String(ch)
                    slashes = 0
                }
            }
            out += String(repeating: "\\", count: slashes * 2) + "\""
            return out
        }.joined(separator: " ")
    }

    /// No poll() on a Windows pipe: peek, and sleep in short slices so the
    /// caller's ACK/heartbeat tick still lands on time. A child that has
    /// exited with nothing queued is end of stream — without that check a
    /// dead ssh reads as an idle one and never triggers a reconnect.
    func read(into buf: inout [UInt8], timeoutMs: Int32) -> Int {
        guard let h = handle else { return -1 }
        let slice: UInt32 = 20
        var waited: Int32 = 0
        while true {
            if starling_child_avail(h) > 0 {
                let n = buf.withUnsafeMutableBufferPointer {
                    starling_child_read(h, $0.baseAddress, Int32($0.count))
                }
                return n <= 0 ? -1 : Int(n)
            }
            if starling_child_alive(h) == 0 { return -1 }
            if waited >= timeoutMs { return 0 }
            Sleep(slice)
            waited += Int32(slice)
        }
    }

    func write(_ frame: [UInt8]) {
        guard let h = handle else { return }
        var off = 0
        frame.withUnsafeBufferPointer { buf in
            while off < buf.count {
                let n = starling_child_write(h, buf.baseAddress! + off,
                                             Int32(buf.count - off))
                if n <= 0 { break }
                off += Int(n)
            }
        }
    }

    func close() {
        if let h = handle { starling_child_close(h) }
        handle = nil
    }
#endif
}

// MARK: - Wire format

/// Frame types, shared by every client of the protocol (termd/protocol.h).
enum TermdFrame: UInt8 {
    case hello = 1, helloOk = 2, list = 3, listReply = 4, open = 5
    case attach = 6, attached = 7, data = 8, input = 9, resize = 10
    case ack = 11, exit = 12, detach = 13, error = 14, ping = 15, pong = 16
    // Workspaces — docs/plans/remote-workspace.md.
    case wsCreate = 17, wsInfo = 18, wsList = 19, wsListReply = 20
    case wsAdd = 21, wsSetMeta = 22, wsGetMeta = 23, wsMeta = 24
}

/// Little-endian scalars, the format's only encoding rule.
enum TermdWire {
    /// 2 added session names (termd/protocol.h). The daemon refuses a version
    /// it does not speak, so an old server answers ERROR rather than
    /// misreading a named OPEN as a command.
    static let version = 2
    /// termd/protocol.h's TERMD_MAX_NAME, less the NUL the daemon adds.
    static let maxNameBytes = 63
    /// TERMD_MAX_BLOB: generous for a tree of pane ratios and mean about
    /// anything else, which is the point.
    static let maxBlobBytes = 16 * 1024

    static func u16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    static func u32(_ v: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((v >> (8 * $0)) & 0xff) }
    }
    static func u64(_ v: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) }
    }
    static func readU16(_ b: [UInt8], _ off: Int) -> UInt16 {
        UInt16(b[off]) | (UInt16(b[off + 1]) << 8)
    }
    static func readU32(_ b: [UInt8], _ off: Int) -> UInt32 {
        UInt32(b[off]) | (UInt32(b[off + 1]) << 8)
            | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 24)
    }
    static func readU64(_ b: [UInt8], _ off: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(b[off + i]) << (8 * UInt64(i)) }
        return v
    }

    /// One frame: `u8 type; u8 flags; u16 pad; u32 len; payload`.
    static func frame(_ type: TermdFrame, _ payload: [UInt8]) -> [UInt8] {
        var out = [UInt8]([type.rawValue, 0, 0, 0])
        out.append(contentsOf: u32(UInt32(payload.count)))
        out.append(contentsOf: payload)
        return out
    }
}

#endif  // os(Linux) || os(macOS) || os(Windows)
