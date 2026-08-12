// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The twenty-line terminal — the app the TerminalView plan promised
// (docs/plans/terminal-widget.md). A TerminalSession spawns the user's
// shell; TerminalView renders it. Everything else — the C emulator core
// that outruns ghostty and sweeps ucs-detect, wide characters and
// grapheme clusters, mouse reporting, scrollback, selection, the bundled
// fonts — comes with the widget.
//
//   swift run -c release TerminalDemo

#if os(Linux) || os(Windows)
import ExampleHost
import Flutter

let session = TerminalSession()
session.startShell()

runExampleApp(title: "Terminal", width: 940, height: 620) {
    TerminalView(session: session)
}

#else
fatalError("The example apps currently target Linux and Windows desktop sessions.")
#endif
