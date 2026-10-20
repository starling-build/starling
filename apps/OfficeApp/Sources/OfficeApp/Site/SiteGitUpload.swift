// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// One attempt owns one control. Cancellation never touches the saved files.
final class SitePublishControl {
    #if !os(WASI)
    private let lock = NSLock()
    private var requested = false
    func cancel() { lock.lock(); requested = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return requested }
    #else
    func cancel() {}
    var isCancelled: Bool { false }
    #endif
}

#if !os(WASI)
enum SiteGitUpload {
    enum StopReason { case cancelled, timedOut }
    struct Result {
        let status: Int32
        let output: String
        let stopped: StopReason?
    }
    static let defaultTimeout: TimeInterval = 300

    static func push(repo: String, revision: String, target: String, control: SitePublishControl) -> Result {
        run(arguments: ["/usr/bin/env", "git", "-C", repo, "push", "--", "origin", revision + ":" + target],
            environment: ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"]) { _, value in value },
            timeout: defaultTimeout, control: control)
    }

    /// Run off the UI thread. A dedicated process group lets Stop also reach
    /// Git's transport and credential-helper children. Capture is bounded;
    /// neither a full pipe nor an inherited open pipe can stall cancellation.
    static func run(arguments: [String], environment: [String: String], timeout: TimeInterval,
                    control: SitePublishControl) -> Result {
        func failure() -> Result { Result(status: 127, output: "Could not start the upload process.", stopped: nil) }
        if control.isCancelled { return Result(status: -1, output: "", stopped: .cancelled) }
        guard let program = arguments.first, program.hasPrefix("/"), timeout.isFinite, timeout > 0 else { return failure() }
        #if canImport(Darwin) || canImport(Glibc)
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { return failure() }
        let readFD = descriptors[0], writeFD = descriptors[1]
        var readClosed = false, writeClosed = false
        defer { if !readClosed { close(readFD) }; if !writeClosed { close(writeFD) } }
        guard fcntl(readFD, F_SETFL, O_NONBLOCK) != -1,
              fcntl(readFD, F_SETFD, FD_CLOEXEC) != -1,
              fcntl(writeFD, F_SETFD, FD_CLOEXEC) != -1 else { return failure() }
        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        #endif
        guard posix_spawn_file_actions_init(&actions) == 0 else { return failure() }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return failure() }
        defer { posix_spawnattr_destroy(&attributes) }
        var flags = Int16(POSIX_SPAWN_SETPGROUP)
        #if canImport(Darwin)
        flags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
        #endif
        guard posix_spawnattr_setflags(&attributes, flags) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, writeFD, 1) == 0,
              posix_spawn_file_actions_adddup2(&actions, writeFD, 2) == 0,
              posix_spawn_file_actions_addclose(&actions, readFD) == 0,
              posix_spawn_file_actions_addclose(&actions, writeFD) == 0 else { return failure() }
        var argv = arguments.map { strdup($0) } + [nil]
        var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = -1
        guard posix_spawn(&pid, program, &actions, &attributes, &argv, &envp) == 0, pid > 0 else { return failure() }
        close(writeFD); writeClosed = true

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        func drain() {
            guard !readClosed else { return }
            // Limit each turn so a noisy child cannot starve the stop/deadline check.
            for _ in 0..<16 {
                let count = read(readFD, &buffer, buffer.count)
                if count > 0 {
                    output.append(contentsOf: buffer.prefix(count))
                    if output.count > 65_536 { output.removeFirst(output.count - 65_536) }
                } else if count == 0 {
                    close(readFD); readClosed = true; return
                } else if errno != EINTR { return }
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var stopped: StopReason?
        var stoppingSince: TimeInterval = 0
        var status: Int32 = 0
        while true {
            drain()
            let now = ProcessInfo.processInfo.systemUptime
            if stopped == nil {
                let ended = waitpid(pid, &status, WNOHANG)
                if ended == pid {
                    drain()
                    let exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
                    return Result(status: exitCode, output: String(decoding: output, as: UTF8.self), stopped: nil)
                }
                if ended < 0 && errno != EINTR { return failure() }
                if control.isCancelled || now >= deadline {
                    stopped = control.isCancelled ? .cancelled : .timedOut
                    stoppingSince = now
                    kill(-pid, SIGTERM)
                }
            } else if now - stoppingSince >= 0.3 {
                // Do not reap during the grace period: keeping the child PID
                // reserved prevents a later signal from targeting a reused ID.
                kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
                drain()
                return Result(status: -1, output: String(decoding: output, as: UTF8.self), stopped: stopped)
            }
            if readClosed { Thread.sleep(forTimeInterval: 0.05) }
            else {
                var item = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
                _ = poll(&item, 1, 50)
            }
        }
        #else
        return failure()
        #endif
    }
}
#endif
