// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The session slot -- shell-replacement Phase 5.
//
// `WinShellBar.exe --session` is what Winlogon's Shell= points at: it brings
// up the two surfaces a session cannot be without (the dock, which parks the
// launcher/notifications/banners/run overlays itself, and the desktop),
// replays the startup sources in explorer's order, and then does the only
// two jobs a supervisor should have -- restart a crashed child, and give the
// machine back to explorer when restarting stops helping. It deliberately
// never boots the engine: a supervisor that shares the children's failure
// modes supervises nothing.
//
// The crash-loop rule, from the plan's own words: a shell that dies twice
// in a minute writes the Shell registration back and lets the machine live.
// Concretely: any critical child exiting twice within 60 seconds ends the
// session -- delete our HKCU Winlogon\Shell value (the machine default,
// explorer, returns at next logon), start explorer.exe NOW so the user has
// a desktop, and exit.
//
// Startup replay follows explorer's documented order: HKLM RunOnce, HKLM
// Run (both registry views), HKCU Run, the common Startup folder, the
// user's Startup folder, HKCU RunOnce. RunOnce values are deleted BEFORE
// running (a "!" prefix defers the delete until after a successful
// spawn); an HKLM RunOnce value
// we cannot delete is NOT run, or it would run again every logon. Startup
// runs only when explorer is absent -- in trial mode (explorer present)
// the items have already run this logon, so replaying them would double
// every autostart app.

#if os(Windows)
import Foundation
import FlutterWin32
import FlutterWin32Bridge
import WinSDK

enum SessionSlot {

    // MARK: - Startup sources

    struct StartupItem {
        var source: String
        var name: String
        /// A command line for registry sources; a full path for folder items.
        var command: String
        /// 0 HKLM RunOnce, 5 HKCU RunOnce, -1 everything else.
        var runOnceKey: Int32
        var deleteAfter: Bool
    }

    /// Every startup entry, in the order explorer replays them.
    static func startupItems() -> [StartupItem] {
        var items: [StartupItem] = []
        for (which, source) in [(Int32(0), "HKLM\\RunOnce"),
                                (Int32(1), "HKLM\\Run"),
                                (Int32(2), "HKCU\\Run")] {
            items += registryItems(which, source: source)
        }
        items += folderItems(3, source: "Startup (all users)")
        items += folderItems(2, source: "Startup")
        items += registryItems(5, source: "HKCU\\RunOnce")
        return items
    }

    private static func registryItems(_ which: Int32,
                                      source: String) -> [StartupItem] {
        var buffer = [CChar](repeating: 0, count: 65536)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_sessionslot_startup_list(which, $0.baseAddress, 65536)
        }
        guard n > 0 else { return [] }
        let runOnce = which == 0 || which == 5
        return String(cString: buffer).split(separator: "\n").compactMap {
            line in
            let parts = line.split(separator: "\t", maxSplits: 1,
                                   omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[1].isEmpty else { return nil }
            let name = String(parts[0])
            // "!" defers the delete until the entry has actually run. The
            // raw value name (prefixes included) is kept throughout -- the
            // registry delete addresses the value by exactly that name.
            let deleteAfter = runOnce && name.hasPrefix("!")
            return StartupItem(source: source, name: name,
                               command: String(parts[1]),
                               runOnceKey: runOnce ? which : -1,
                               deleteAfter: deleteAfter)
        }
    }

    private static func folderItems(_ which: Int32,
                                    source: String) -> [StartupItem] {
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_known_folder(which, $0.baseAddress, 1024)
        }
        guard n > 0 else { return [] }
        let dir = String(cString: buffer)
        let names = (try? FileManager.default
            .contentsOfDirectory(atPath: dir)) ?? []
        return names.sorted { $0.localizedCaseInsensitiveCompare($1)
                               == .orderedAscending }
            .filter { $0.lowercased() != "desktop.ini" }
            .map { name in
                StartupItem(source: source, name: name,
                            command: dir + "\\" + name,
                            runOnceKey: -1, deleteAfter: false)
            }
    }

    /// Replays the startup set. Returns log lines; `execute: false` is the
    /// `--print-startup` oracle, identical walk with nothing run.
    @discardableResult
    static func runStartup(execute: Bool) -> [String] {
        var lines: [String] = []
        for item in startupItems() {
            var verdict = execute ? "run" : "would run"
            if execute {
                if item.runOnceKey >= 0 && !item.deleteAfter {
                    // Delete BEFORE running. An HKLM value that will not
                    // delete does not run -- explorer's own restraint, or
                    // the entry repeats every logon.
                    if flwin32_sessionslot_runonce_delete(item.runOnceKey,
                                                      item.name) == 0 {
                        verdict = "SKIPPED (RunOnce delete failed)"
                        lines.append("[startup] \(item.source)  \(item.name)"
                                     + "  \(verdict)")
                        continue
                    }
                }
                let ok: Bool
                if item.runOnceKey >= 0 || item.source.hasPrefix("HK") {
                    ok = flwin32_sessionslot_exec_command(item.command) != 0
                } else {
                    // Folder items go through the shell: they are .lnk
                    // files and documents, not command lines.
                    ok = Win32AppCatalog.open(item.command)
                }
                if ok && item.deleteAfter {
                    _ = flwin32_sessionslot_runonce_delete(item.runOnceKey,
                                                       item.name)
                }
                if !ok { verdict = "FAILED" }
            }
            lines.append("[startup] \(item.source)  \(item.name)  "
                         + "\(verdict)  \(item.command)")
        }
        if lines.isEmpty { lines.append("[startup] nothing to run") }
        return lines
    }

    // MARK: - Registration

    static var ownCommandLine: String {
        "\"\(CommandLine.arguments[0])\" --session"
    }

    static func registeredShell() -> String? {
        var buffer = [CChar](repeating: 0, count: 2048)
        let n = buffer.withUnsafeMutableBufferPointer {
            flwin32_sessionslot_shell_get($0.baseAddress, 2048)
        }
        return n > 0 ? String(cString: buffer) : nil
    }

    /// Writes HKCU Winlogon\Shell for the NEXT logon of this user only.
    static func register() -> Bool {
        flwin32_sessionslot_shell_set(ownCommandLine) != 0
    }

    /// Deletes the per-user value -- the machine default (explorer) returns.
    static func unregister() -> Bool {
        flwin32_sessionslot_shell_set(nil) != 0
    }

    // MARK: - The supervisor

    private struct Child {
        var role: String
        var args: String
        var handle: UInt64 = 0
        /// Exit timestamps inside the crash-loop window.
        var exits: [Date] = []
    }

    private static func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[session] \(stamp) \(line)\n"
        FileHandle.standardError.write(Data(text.utf8))
        if let data = text.data(using: .utf8) {
            let dir = (ProcessInfo.processInfo.environment["LOCALAPPDATA"]
                       ?? NSTemporaryDirectory()) + "\\Starling"
            try? FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            let path = dir + "\\session.log"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }

    /// The `--session` entry. Never returns.
    static func supervise(trial: Bool) -> Never {
        // Started by Winlogon, a console-subsystem binary wears a fresh
        // console window over the session (the VM soak's first screenshot).
        // Hidden only when this process owns it -- from a dev terminal the
        // call does nothing.
        flwin32_sessionslot_hide_own_console()

        var children = [Child(role: "dock", args: ""),
                        Child(role: "desktop", args: "--desktop")]

        if trial {
            // Children inherit the environment; the desktop's own gate
            // refuses to run beside explorer without this.
            _ = SetEnvironmentVariableA("STARLING_DESKTOP_TRIAL", "1")
        }

        log("session start, trial=\(trial), shell=\(registeredShell() ?? "<machine default>")")

        for i in children.indices {
            children[i].handle =
                flwin32_sessionslot_spawn_self(children[i].args)
            log("spawned \(children[i].role) "
                + (children[i].handle != 0 ? "ok" : "FAILED"))
        }

        // Startup replays only when we are the real shell: beside explorer
        // (trial) every one of these already ran this logon.
        if trial {
            log("startup skipped (trial mode, explorer ran them)")
        } else {
            for line in runStartup(execute: true) { log(line) }
        }

        while true {
            let handles = children.map(\.handle)
            let index = handles.withUnsafeBufferPointer {
                flwin32_sessionslot_wait_any($0.baseAddress, Int32(handles.count),
                                         5000)
            }
            if index == -1 {
                // Quiet tick: re-park any small overlay that died. Idempotent
                // FindWindow checks, so this costs nothing when all is well.
                flwin32_shell_ensure_notification_center()
                flwin32_shell_ensure_banners()
                flwin32_shell_ensure_run()
                flwin32_shell_ensure_launcher()
                continue
            }
            guard index >= 0, Int(index) < children.count else {
                log("wait error \(index); exiting")
                exit(1)
            }
            let i = Int(index)
            flwin32_sessionslot_close_handle(children[i].handle)
            children[i].handle = 0
            let now = Date()
            children[i].exits = children[i].exits.filter {
                now.timeIntervalSince($0) < 60
            } + [now]
            log("\(children[i].role) exited "
                + "(\(children[i].exits.count) in the last minute)")

            if children[i].exits.count >= 2 {
                // Restarting stopped helping. Give the machine back: the
                // registration first (so the NEXT logon is explorer's), then
                // explorer NOW (so THIS session has a desktop), then out.
                log("crash loop: unregistering and starting explorer")
                // Reap the other children first: a desktop surface left
                // standing would sit OVER the returning explorer's own.
                // (The parked overlays the dock spawned are not ours to
                // hold handles on, and they self-suppress beside explorer.)
                for j in children.indices where children[j].handle != 0 {
                    flwin32_sessionslot_kill(children[j].handle)
                    flwin32_sessionslot_close_handle(children[j].handle)
                    log("reaped \(children[j].role)")
                }
                // Delete our per-user Shell value so the NEXT logon is
                // explorer's. Unregister when the value is ours OR when we
                // cannot read it back: early in a logon HKCU has been observed
                // to read empty from this process even though the value is set
                // (the same misread that logs shell=<machine default> at
                // start), and skipping the delete then leaves the loop armed to
                // crash again every boot. Deleting an absent value is harmless,
                // and only this shell ever writes the per-user Shell here — a
                // readable foreign value is the one case we leave alone.
                let current = registeredShell()
                if current == nil
                    || current!.lowercased().contains("winshellbar") {
                    _ = unregister()
                    log("unregistered shell (was: "
                        + "\(current ?? "<unreadable>"))")
                }
                _ = flwin32_sessionslot_start_explorer()
                // A force-killed dock never ran its atexit, so explorer's
                // taskbar comes back wearing the AUTOHIDE the dock set --
                // a PERSISTED user setting, so it survives reboots (the VM
                // soak came back taskbar-less twice). Wait for explorer to
                // stand, then put the state back.
                for _ in 0..<20 where flwin32_shell_explorer_present() == 0 {
                    Thread.sleep(forTimeInterval: 0.5)
                }
                Thread.sleep(forTimeInterval: 3)
                _ = flwin32_explorer_taskbar_show()
                log("explorer started, taskbar state restored")
                exit(1)
            }

            children[i].handle = flwin32_sessionslot_spawn_self(children[i].args)
            log("respawned \(children[i].role) "
                + (children[i].handle != 0 ? "ok" : "FAILED"))
        }
    }
}
#endif
