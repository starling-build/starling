// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Terminal app is the sdk's TerminalView with a shell session — the
// twenty-line consumer the widget plan promised (docs/plans/
// terminal-widget.md). Everything terminal-shaped — the C emulator core,
// the PTY, the painter, input translation, fonts — lives in the framework
// now; this file owns only the session's lifecycle. It stays the perf and
// conformance testbed: the bench harness drives this binary.
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
    private let session = TerminalSession()

    override func initState() {
        super.initState()
        #if !os(iOS)
        session.startShell()
        #endif
    }

    override func dispose() {
        #if os(iOS)
        ssh?.disconnect()
        #endif
        session.terminate()
        super.dispose()
    }

    #if os(iOS)
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

    override func build(_ context: any BuildContext) -> Widget {
        if !connected {
            return SSHConnectView(onConnect: { [weak self] target in
                self?.connect(target)
            })
        }
        return TerminalView(session: session)
    }
    #else
    override func build(_ context: any BuildContext) -> Widget {
        return TerminalView(session: session)
    }
    #endif
}
