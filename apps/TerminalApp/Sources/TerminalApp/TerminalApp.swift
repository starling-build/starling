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
#if os(iOS)
import FlutterUIKit
#endif

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
    /// Columns the grid is sized to, taken from the window the app actually
    /// got rather than from a constant.
    ///
    /// A phone gets 50. 80 was tried first, because that is the width the
    /// software world assumes (man pages, `ls -l`, every TUI's layout) — and
    /// it came out unreadable, ~8pt on an iPhone 15. Held in one hand,
    /// reading the text beats not wrapping it; pinch inward for the full 80
    /// when a TUI needs its layout over your eyesight.
    ///
    /// An iPad is not a big phone, and a flat 50 made that obvious the first
    /// time one ran it: a 45-character prompt spanned a 13-inch display, one
    /// glyph about 20pt. Above the phone's floor the rule is the desktop's
    /// own — a 13pt monospace advance is ~8.2pt, which is exactly why 13pt
    /// yields 49 columns in a 402pt window — so dividing the width by it
    /// keeps the font at the size both desktop hosts default to. A 13-inch
    /// iPad opens at ~125 columns, and a split pane still has room for real
    /// output instead of six words a line.
    ///
    /// `windowSize` is zero until the tree is mounted; this is read from
    /// `build`, so it is not, but the floor covers it if that ever changes.
    private static var defaultColumns: Int {
        let width = UIKitHost.windowSize.width
        guard width > 0 else { return 50 }
        return max(50, Int((width / 8.2).rounded()))
    }

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

    /// Connect, then hand the screen to the same tabbed workspace UI the
    /// desktop runs.
    ///
    /// The connection is opened `connectionOnly`: it authenticates and stops
    /// there, because every pane dials its own channel through the dialer set
    /// below. Anything this object opened for itself would be a second shell
    /// on the far machine that nothing draws.
    ///
    /// Order matters. The dialer and the launch spec are in place BEFORE
    /// `connected` flips, because that flip mounts `TerminalTabsView`, whose
    /// `initState` reads the spec and starts dialing immediately.
    private func connect(_ target: SSHTarget) {
        target.remember()
        let ssh = SSHTerminal(session: session)
        ssh.connectionOnly = true
        self.ssh = ssh
        TerminalWorkspace.dialer = ssh.termdDialer()
        WorkspaceSpec.connected = WorkspaceSpec(
            "\(target.host)/ws:\(WorkspaceSpec.defaultName)")
        ssh.connect(host: target.host, port: target.port,
                    user: target.user, password: target.password)
        setState { self.connected = true }
    }

    override func build(_ context: any BuildContext) -> Widget {
        if !connected {
            return SSHConnectView(onConnect: { [weak self] target in
                self?.connect(target)
            })
        }
        // The pad chrome, not the desktop's (docs/plans/ipad-ui.md). The
        // model underneath is the same class either way — TerminalPad.swift
        // overrides `build` and nothing else.
        return TerminalPadView()
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
