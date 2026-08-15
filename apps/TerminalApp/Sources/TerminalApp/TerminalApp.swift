// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Terminal app is the sdk's TerminalView with a shell session — the
// twenty-line consumer the widget plan promised (docs/plans/
// terminal-widget.md). Everything terminal-shaped — the C emulator core,
// the PTY, the painter, input translation, fonts — lives in the framework
// now; this file owns only which terminal is on screen. It stays the perf and
// conformance testbed: the bench harness drives this binary.
//
// On the desktop that is a list of them — see TerminalTabs.swift, which owns
// the sessions and their lifecycle.
//
// On iOS the session cannot be local — there is no fork and no exec there —
// so the app opens an ssh connection to another machine instead, and this
// file owns that too: a connect screen first, the same TerminalView after.

import Flutter
import Foundation

class TerminalApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TerminalAppState()
    }
}

class _TerminalAppState: State<StatefulWidget>, @unchecked Sendable {
    #if os(iOS)
    private let session = TerminalSession()
    #endif

    override func initState() {
        super.initState()
        #if os(iOS)
        // Connect straight away when the environment named a target — the
        // simulator dev loop, which cannot tap a button. See
        // SSHTarget.fromEnvironment.
        if let target = SSHTarget.fromEnvironment() {
            connect(target)
            // `STARLING_SSH_COMMAND`: typed into the session once the shell
            // has had a moment to come up — the dev loop's only way to reach
            // a TUI, since `simctl` cannot tap or type. Sent as keystrokes
            // rather than exec'd so what renders is exactly what a person
            // launching it would see. Simulator-only by the same gate as the
            // credentials above; the delay is crude by design, this is a
            // debugging hook and not a protocol.
            if let command = ProcessInfo.processInfo.environment["STARLING_SSH_COMMAND"],
               !command.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.session.write(command + "\r")
                }
            }
        }
        #endif
    }

    override func dispose() {
        #if os(iOS)
        ssh?.disconnect()
        session.terminate()
        #endif
        super.dispose()
    }

    #if os(iOS)
    /// Columns the grid is sized to. 50, which on a 393pt phone puts the
    /// font at ~13pt — the size the desktop terminal itself defaults to.
    /// 80 was tried first, because that is the width the software world
    /// assumes (man pages, `ls -l`, every TUI's layout) — and it came out
    /// unreadable, ~8pt on an iPhone 15. On a phone held in one hand,
    /// reading the text beats not wrapping it; pinch inward for the full
    /// 80 when a TUI needs its layout over your eyesight.
    private static let defaultColumns = 50

    private var columns: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "starling.term.columns")
            return stored > 0 ? stored : Self.defaultColumns
        }
        set { UserDefaults.standard.set(newValue, forKey: "starling.term.columns") }
    }

    private var ssh: SSHTerminal?
    /// nil until the user has connected once; the connect screen is what is
    /// on screen until then.
    private var connected = false

    private func connect(_ target: SSHTarget) {
        target.remember()
        let ssh = SSHTerminal(session: session)
        self.ssh = ssh
        ssh.connect(host: target.host, port: target.port,
                    user: target.user, password: target.password)
        setState { self.connected = true }
    }

    /// The terminal proper: a grid sized to a column count rather than to a
    /// font size, and a pinch that moves that count.
    private func terminal() -> Widget {
        return TerminalView(
            session: session,
            fitColumns: columns,
            onFitColumnsChanged: { [weak self] in self?.columns = $0 },
            pinchToZoom: true)
    }

    override func build(_ context: any BuildContext) -> Widget {
        if !connected {
            return SSHConnectView(onConnect: { [weak self] target in
                self?.connect(target)
            })
        }
        return terminal()
    }
    #else
    /// The desktop terminal is tabbed — several shells in one window, the bar
    /// hidden until there is a second one. The session lifecycle moves with
    /// it (TerminalTabs.swift): there is no one session here to own.
    override func build(_ context: any BuildContext) -> Widget {
        return TerminalTabsView()
    }
    #endif
}
