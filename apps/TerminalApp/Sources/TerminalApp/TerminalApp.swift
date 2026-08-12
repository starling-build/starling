// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Terminal app is the sdk's TerminalView with a shell session — the
// twenty-line consumer the widget plan promised (docs/plans/
// terminal-widget.md). Everything terminal-shaped — the C emulator core,
// the PTY, the painter, input translation, fonts — lives in the framework
// now; this file owns only the session's lifecycle. It stays the perf and
// conformance testbed: the bench harness drives this binary.

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
        session.startShell()
    }

    override func dispose() {
        session.terminate()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        return TerminalView(session: session)
    }
}
