// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The switcher: where you are going, and what is already there.
//
// Milestone 5 of docs/plans/remote-workspace.md. An arrangement that survives
// is worth nothing if the only way back to it is remembering its name and
// typing it on the command line — which is what milestone 3 shipped, and it
// is the wrong shape for the case the whole feature exists for: sitting down
// at a different machine.
//
// So: one chord (⌘O, Ctrl+Shift+O), one line to type a destination, and under
// it the workspaces that host actually has, asked for over the same protocol
// everything else uses (TermdDirectory). Enter on a row opens it; Enter on
// something you typed creates it, because a named workspace is
// attach-or-create on the daemon and the picker should not need a second verb
// for "new".
//
// The keyboard here is borrowed, not owned. A terminal claims nearly every
// key, so the switcher lives inside `keyFilter` — the app's first refusal on
// the pane's keys — rather than taking focus away from a shell that is
// probably mid-command. That is also why every key is swallowed while it is
// open: half-typed input reaching a shell is worse than a key doing nothing.

import Flutter
import FlutterSwiftBridge
import Foundation

#if !os(iOS)

/// One row: a place to go, and what is there.
struct SwitcherRow {
    let spec: WorkspaceSpec
    let title: String
    let detail: String
}

/// Everything the switcher knows while it is open.
final class SwitcherState {
    var open = false
    /// What has been typed: `name`, or `host/name`.
    var text = ""
    /// 0 is the typed line itself; 1... are `rows`.
    var index = 0
    var rows: [SwitcherRow] = []
    /// The host `rows` describe, so typing a different one re-asks and typing
    /// the same one does not.
    var listedHost: String?
    var busy = false
    /// Set when a host could not be reached — the difference between "nothing
    /// there" and "could not ask", which a blank list would hide.
    var unreachable: String?

    /// The host part of what is typed. Everything before the first slash; the
    /// machine you are already on when there is none.
    var host: String {
        guard let slash = text.firstIndex(of: "/") else { return "local" }
        let h = String(text[..<slash]).trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? "local" : h
    }

    /// The workspace name part: everything after the first slash.
    var name: String {
        guard let slash = text.firstIndex(of: "/") else {
            return text.trimmingCharacters(in: .whitespaces)
        }
        return String(text[text.index(after: slash)...])
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Where the client remembers what it was doing, so the next launch does not
/// have to be told again.
///
/// A file rather than UserDefaults because this is a desktop app that also
/// runs on Linux, where the same path is where the tiling example already
/// keeps its command history. One destination per line, newest last, deduped
/// on read — an append-only log is atomic enough for a list of names and
/// survives two clients writing at once, which a rewritten file does not.
enum WorkspaceMemory {
    private static var path: String {
        realUserHomeDirectory() + "/.local/state/starling-terminal-workspaces"
    }

    /// Destinations opened before, most recent first.
    static func recent() -> [WorkspaceSpec] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return [] }
        var seen = Set<String>()
        return text.split(separator: "\n").reversed().compactMap { line in
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, seen.insert(s).inserted else { return nil }
            return WorkspaceSpec(s)
        }
    }

    /// The one to reopen when the app is launched with nothing to go on.
    static func last() -> WorkspaceSpec? { recent().first }

    static func remember(_ spec: WorkspaceSpec) {
        let line = "remote:\(spec.host)/ws:\(spec.name)"
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// `Host` entries from ~/.ssh/config, minus the patterns — a `Host *`
    /// block configures every connection, it is not a machine to reach. The
    /// hostname is the part nobody remembers, so it is worth offering.
    static func sshHosts() -> [String] {
        let file = realUserHomeDirectory() + "/.ssh/config"
        guard let text = try? String(contentsOfFile: file, encoding: .utf8)
        else { return [] }
        var hosts: [String] = []
        for line in text.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[0].lowercased() == "host" else { continue }
            for host in parts.dropFirst()
            where !host.contains("*") && !host.contains("?") {
                hosts.append(String(host))
            }
        }
        return hosts
    }
}

/// The switcher's own palette. Quieter than the terminal it sits over, and
/// opaque: this is a surface to read, not a glass one.
private enum SwitcherChrome {
    static let scrim: Int = 0x99_000000
    static let panel: Int = 0xF2_1E2127
    static let edge: Int = 0xFF_3A4152
    static let input: Int = 0xFF_E8E8E8
    static let hint: Int = 0xFF_8A9099
    static let item: Int = 0xFF_C8CDD4
    static let pick: Int = 0xFF_66AAFF
    static let pickBg: Int = 0x33_66AAFF
    static let row: Double = 26
}

extension _TerminalTabsState {

    // MARK: - Opening and closing

    func _openSwitcher() {
        let last = WorkspaceMemory.last()
        setState {
            _switcher.open = true
            // Prefilled with the host you were last on, name empty: the common
            // case is another workspace on the same machine, and the rows
            // below are then already the right ones.
            _switcher.text = last.map { $0.host == "local" ? "" : "\($0.host)/" } ?? ""
            _switcher.index = 0
            _switcher.rows = []
            _switcher.listedHost = nil
            _switcher.unreachable = nil
        }
        _switcherRefresh()
    }

    func _closeSwitcher() {
        guard _switcher.open else { return }
        setState { _switcher.open = false }
    }

    /// Ask the typed host what it has, unless it is the host already listed.
    private func _switcherRefresh() {
        let host = _switcher.host
        guard host != _switcher.listedHost else { return }
        _switcher.listedHost = host
        _switcher.busy = true
        _switcher.unreachable = nil
        TermdDirectory.list(host: host) { [weak self] listing in
            DispatchQueue.main.async {
                guard let self = self, self._switcher.open,
                      self._switcher.host == host
                else { return }
                self.setState {
                    self._switcher.busy = false
                    self._switcher.unreachable = listing == nil ? host : nil
                    self._switcher.rows = (listing?.workspaces ?? [])
                        .sorted { $0.name.lowercased() < $1.name.lowercased() }
                        .map { ws in
                            let panes = ws.sessions.count
                            return SwitcherRow(
                                spec: WorkspaceSpec("remote:\(host)/ws:\(ws.name)")
                                    ?? WorkspaceSpec("ws:\(ws.name)")!,
                                title: ws.name,
                                detail: panes == 1 ? "1 session"
                                                   : "\(panes) sessions")
                        }
                    self._switcher.index = 0
                }
            }
        }
    }

    /// The rows actually shown: what the host has, narrowed by what is typed.
    private var _switcherMatches: [SwitcherRow] {
        let needle = _switcher.name.lowercased()
        guard !needle.isEmpty else { return _switcher.rows }
        return _switcher.rows.filter { $0.title.lowercased().contains(needle) }
    }

    // MARK: - Keys

    /// Every key while the switcher is open. Returns true always, so nothing
    /// half-typed reaches the shell underneath.
    func _switcherKey(_ keyData: KeyData) -> Bool {
        guard keyData.type == .down || keyData.type == .repeat else { return true }
        let matches = _switcherMatches

        // Two id schemes, as everywhere else in this app: X11 keysyms from the
        // DRM embedder, Flutter logical ids from the Cocoa/GTK/Win32 hosts.
        switch keyData.logical {
        case 0xFF1B, 0x1_0000_001B:                             // Escape
            _closeSwitcher()
            return true
        case 0xFF0D, 0xFF8D, 0x1_0000_000D, 0x1_0000_020D:      // Enter
            let chosen = _switcher.index > 0 && _switcher.index <= matches.count
                ? matches[_switcher.index - 1].spec
                : WorkspaceSpec("remote:\(_switcher.host)/ws:\(_switcher.name)")
            _closeSwitcher()
            if let spec = chosen { _goTo(spec) }
            return true
        case 0xFF08, 0x1_0000_0008:                             // Backspace
            if !_switcher.text.isEmpty {
                setState {
                    _switcher.text.removeLast()
                    _switcher.index = 0
                }
                _switcherRefresh()
            }
            return true
        case 0xFF52, 0x1_0000_0304:                             // Up
            setState { _switcher.index = max(0, _switcher.index - 1) }
            return true
        case 0xFF54, 0x1_0000_0301, 0xFF09, 0x1_0000_0009:      // Down / Tab
            setState { _switcher.index = min(matches.count, _switcher.index + 1) }
            return true
        default:
            break
        }

        if let character = keyData.character,
           let scalar = character.unicodeScalars.first,
           scalar.value >= 0x20, scalar.value != 0x7F,
           _switcher.text.count < 128 {
            setState {
                _switcher.text += character
                _switcher.index = 0
            }
            _switcherRefresh()
            return true
        }
        return true
    }

    /// Open a destination, and remember it as the one to come back to.
    func _goTo(_ spec: WorkspaceSpec) {
        WorkspaceMemory.remember(spec)
        // Already open? Show it rather than attaching a second client to the
        // same sessions — which works, but means two panes fighting over one
        // pty's size until milestone 6 says who wins.
        if let existing = tabs.firstIndex(where: { $0.workspace?.spec == spec }) {
            setState { active = existing }
            return
        }
        setState { _openWorkspace(spec) }
    }

    // MARK: - Drawing

    func _switcherOverlay(_ body: Size) -> Widget {
        let matches = _switcherMatches
        let width = min(560, max(280, body.width - 80))
        let listed = min(matches.count, 8)
        let height = 96 + Double(listed) * SwitcherChrome.row
            + (matches.isEmpty ? 24 : 0)

        var children: [Widget] = [
            SizedBox(width: width, height: 14),
            _line("  go to", SwitcherChrome.hint, 11),
            SizedBox(width: width, height: 4),
            _line("  ❯ " + _switcher.text + "▏", SwitcherChrome.input, 15),
            SizedBox(width: width, height: 10),
        ]

        if let unreachable = _switcher.unreachable {
            children.append(_line("    \(unreachable) did not answer",
                                  SwitcherChrome.hint, 12))
        } else if _switcher.busy {
            children.append(_line("    looking…", SwitcherChrome.hint, 12))
        } else if matches.isEmpty {
            children.append(_line(_switcher.name.isEmpty
                                    ? "    no workspaces on \(_switcher.host) yet"
                                    : "    ⏎ makes “\(_switcher.name)” on \(_switcher.host)",
                                  SwitcherChrome.hint, 12))
        } else {
            for (i, row) in matches.prefix(8).enumerated() {
                children.append(_switcherRow(row, width: width,
                                             selected: _switcher.index == i + 1))
            }
        }
        children.append(SizedBox(width: width, height: 10))
        children.append(_line("    ↑↓ choose · ⏎ open · esc cancel",
                              SwitcherChrome.hint, 11))

        let panel = SizedBox(
            width: width, height: height,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Color(SwitcherChrome.panel),
                    border: Border.all(color: Color(SwitcherChrome.edge), width: 1)
                ),
                child: Column(crossAxisAlignment: .start, children: children)
            )
        )

        // The scrim absorbs the click that dismisses, and everything else: a
        // click landing in a pane behind an open switcher would move focus
        // under it.
        return Positioned(
            left: 0, top: 0, right: 0, bottom: 0,
            child: Listener(
                onPointerDown: { [self] _ in _closeSwitcher() },
                behavior: .opaque,
                child: SizedBox(
                    width: body.width, height: body.height,
                    child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(SwitcherChrome.scrim)),
                        child: Column(
                            mainAxisAlignment: .start,
                            crossAxisAlignment: .center,
                            children: [
                                SizedBox(width: body.width,
                                         height: min(120, body.height / 6)),
                                panel,
                            ]
                        )
                    )
                )
            )
        )
    }

    private func _switcherRow(_ row: SwitcherRow, width: Double,
                              selected: Bool) -> Widget {
        return Listener(
            onPointerDown: { [self] _ in
                _closeSwitcher()
                _goTo(row.spec)
            },
            behavior: .opaque,
            child: SizedBox(
                width: width, height: SwitcherChrome.row,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(selected ? SwitcherChrome.pickBg : 0x00_000000)
                    ),
                    child: Row(
                        crossAxisAlignment: .center,
                        children: [
                            SizedBox(width: 16, height: SwitcherChrome.row),
                            _line(selected ? "❯ " : "  ",
                                  selected ? SwitcherChrome.pick : SwitcherChrome.item,
                                  13),
                            _line(row.title,
                                  selected ? SwitcherChrome.pick : SwitcherChrome.item,
                                  13),
                            SizedBox(width: 12, height: SwitcherChrome.row),
                            _line(row.detail, SwitcherChrome.hint, 11),
                        ]
                    )
                )
            )
        )
    }

    private func _line(_ text: String, _ color: Int, _ size: Double) -> Widget {
        return Text(text, style: TextStyle(
            color: Color(color), fontSize: size,
            fontFamily: TerminalFontLoader.family,
            fontFamilyFallback: TerminalFontLoader.fallback))
    }
}

#endif  // !os(iOS)
