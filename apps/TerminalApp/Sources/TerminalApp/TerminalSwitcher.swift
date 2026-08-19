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
    let target: SwitcherTarget
    let title: String
    let detail: String

    /// This row written the way a person would type it — what a copy puts on
    /// the clipboard, so it can be pasted back into a switcher on another
    /// machine, or into a message, and still mean this place.
    ///
    /// nil for a loose session, which is not a destination anyone can type:
    /// choosing one adopts it, and which workspace it lands in depends on what
    /// is already on screen (see `_goTo`).
    var typed: String? {
        guard case .workspace(let spec) = target else { return nil }
        return spec.host == "local" ? spec.name : "\(spec.host)/ws:\(spec.name)"
    }
}

/// What choosing a row does.
enum SwitcherTarget {
    /// Open that workspace, or create it if the name is new.
    case workspace(WorkspaceSpec)
    /// Take a session that belongs to no workspace and put it in one — the
    /// one on screen if there is one, otherwise a workspace of its own.
    ///
    /// A session is not a thing this app can open on its own: what it draws is
    /// always a workspace, because that is what an arrangement is stored
    /// against. Someone who ran `starling-termd build` on the far machine
    /// should still be able to reach it, and this is what "reaching it" has to
    /// mean here — adoption, not a second kind of tab.
    case session(host: String, id: UInt32, name: String)
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
    /// Where the destination ends and the workspace name begins.
    ///
    /// Normally the first slash — `prod-1/dev` — because a hostname cannot
    /// contain one. But a destination may be a whole ssh command, typed as it
    /// would be in a shell (`ssh -i ~/.ssh/id_prod deploy@box`), and those are
    /// full of slashes. So when the text carries an explicit `/ws:` marker,
    /// that wins and the last one is used: the command may contain anything,
    /// and only the marker says where it stops.
    private var cut: (host: String, name: String)? {
        if let marker = text.range(of: "/ws:", options: .backwards) {
            return (String(text[..<marker.lowerBound])
                        .trimmingCharacters(in: .whitespaces),
                    String(text[marker.upperBound...])
                        .trimmingCharacters(in: .whitespaces))
        }
        guard let slash = text.firstIndex(of: "/") else { return nil }
        return (String(text[..<slash]).trimmingCharacters(in: .whitespaces),
                String(text[text.index(after: slash)...])
                    .trimmingCharacters(in: .whitespaces))
    }

    var host: String {
        guard let h = cut?.host else { return "local" }
        return h.isEmpty ? "local" : h
    }

    /// The workspace name part.
    var name: String {
        cut?.name ?? text.trimmingCharacters(in: .whitespaces)
    }

    /// The longest a typed line may get. Paste obeys the same ceiling typing
    /// does, rather than being the one way to overflow the field.
    static let limit = 128

    /// What a paste contributes to the line: one line of printable text, cut
    /// to whatever room is left.
    ///
    /// A destination is a single line, and the clipboard rarely is — the
    /// hostname someone copied came out of a terminal, a config file or a
    /// browser, and arrives with a newline on the end at best. So the first
    /// line with anything on it wins and the rest is dropped: joining the
    /// lines of a shell transcript would produce something that is not a
    /// destination in any spelling, and pasting a stray `\n` into a field
    /// whose Enter *opens a workspace* would be worse than either.
    ///
    /// C0 goes the same way. Nothing unprintable belongs in a hostname, a key
    /// path or an ssh flag, and a tab or an escape landing mid-prompt would
    /// draw as a hole nobody could account for.
    static func pasteable(_ text: String, room: Int) -> String {
        guard room > 0 else { return "" }
        let line = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let printable = String(String.UnicodeScalarView(
            line.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }))
        return String(printable.trimmingCharacters(in: .whitespaces).prefix(room))
    }
}

/// The type size, remembered between launches.
///
/// A file rather than UserDefaults for the same reason `WorkspaceMemory` below
/// is one: this app runs on Linux too, where UserDefaults has no home worth
/// relying on. One line, one number — small enough that a person can read it,
/// change it, or delete it to get the default back, which is the cheapest
/// settings UI there is until there is a real one.
enum TerminalFontMemory {
    static let standard: Double = 13

    private static var path: String {
        realUserHomeDirectory() + "/.local/state/starling-terminal-font"
    }

    static func load() -> Double {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let size = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              size >= 6, size <= 40
        else { return standard }
        return size
    }

    static func save(_ size: Double) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        try? String(format: "%g\n", size)
            .write(toFile: path, atomically: true, encoding: .utf8)
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

    /// The most recent destination — what the switcher prefills its line with.
    /// A launch does NOT reopen it: starting the terminal gives a local shell
    /// and reaching a workspace is something a person asks for (see
    /// `initState` in TerminalTabs.swift).
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
    static let scrim: Int = 0x99_06070B
    /// Lifted a step ABOVE a pane rather than matched to it, which is what
    /// makes it read as a sheet over the terminal instead of another panel
    /// beside it. Still near-opaque: this is a surface to read.
    static let panel: Int = 0xF2_1E212B
    static let edge: Int = 0xFF_333947
    static let input: Int = 0xFF_E9EBF0
    static let hint: Int = 0xFF_858B99
    static let item: Int = 0xFF_C3C8D3
    static let pick: Int = 0xFF_8AA0FF
    static let pickBg: Int = 0x33_8AA0FF
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
        // The same command the workspace itself will be reached by. Listing a
        // host with the stock `ssh` and then opening it with the configured
        // one would make the picker lie: it would show nothing for a host that
        // works perfectly.
        TermdDirectory.list(host: host,
                            sshPath: HostConfig.ssh(for: host)) { [weak self] listing in
            DispatchQueue.main.async {
                guard let self = self, self._switcher.open,
                      self._switcher.host == host
                else { return }
                self.setState {
                    self._switcher.busy = false
                    self._switcher.unreachable = listing == nil ? host : nil
                    var rows = (listing?.workspaces ?? [])
                        .sorted { $0.name.lowercased() < $1.name.lowercased() }
                        .map { ws -> SwitcherRow in
                            let panes = ws.sessions.count
                            let spec = WorkspaceSpec("remote:\(host)/ws:\(ws.name)")
                                ?? WorkspaceSpec("ws:\(ws.name)")!
                            return SwitcherRow(
                                target: .workspace(spec),
                                title: ws.name,
                                detail: panes == 1 ? "1 session"
                                                   : "\(panes) sessions")
                        }
                    // Then what is running on that machine outside any
                    // workspace: a `starling-termd build` someone started over
                    // ssh, or what is left of a workspace that stopped
                    // mentioning it. Below the workspaces, because the
                    // workspace is the thing you usually want.
                    rows += (listing?.loose ?? [])
                        .sorted { $0.id < $1.id }
                        .map { session in
                            SwitcherRow(
                                target: .session(host: host, id: session.id,
                                                 name: session.name),
                                title: session.name.isEmpty
                                    ? "session \(session.id)" : session.name,
                                detail: session.alive ? "loose · \(session.cols)×\(session.rows)"
                                                      : "loose · ended")
                        }
                    self._switcher.rows = rows
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
            let chosen: SwitcherTarget? =
                _switcher.index > 0 && _switcher.index <= matches.count
                    ? matches[_switcher.index - 1].target
                    : WorkspaceSpec("remote:\(_switcher.host)/ws:\(_switcher.name)")
                        .map { SwitcherTarget.workspace($0) }
            _closeSwitcher()
            if let chosen = chosen { _goTo(chosen) }
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

        // Paste and copy, in the same chords the grid underneath uses — to the
        // hand holding them this is still the terminal, and a sheet that took
        // the keyboard should not also take away the one chord everybody
        // reaches for when a hostname is already on the clipboard.
        //
        // They are matched BEFORE the character fallback below, which is what
        // used to happen to them: ⌘V arrived carrying the character "v" and
        // was typed into the destination, so the field filled with letters
        // while nothing pasted.
        var clipboardChord = _ctrlDown && _shiftDown
        #if os(macOS)
        clipboardChord = clipboardChord || (_metaDown && !_ctrlDown)
        #endif
        if clipboardChord {
            if keyData.logical == 0x56 || keyData.logical == 0x76 {   // V/v
                _switcherPaste()
                return true
            }
            if keyData.logical == 0x43 || keyData.logical == 0x63 {   // C/c
                _switcherCopy()
                return true
            }
        }

        // A chord that reached here is one this sheet does not bind, and its
        // letter is not text the person meant to type: without the modifier
        // test, ⌘T put a "t" in the middle of a hostname.
        if !_ctrlDown && !_metaDown,
           let character = keyData.character,
           let scalar = character.unicodeScalars.first,
           scalar.value >= 0x20, scalar.value != 0x7F,
           _switcher.text.count < SwitcherState.limit {
            setState {
                _switcher.text += character
                _switcher.index = 0
            }
            _switcherRefresh()
            return true
        }
        return true
    }

    // MARK: - The clipboard

    /// Paste onto the end of the line.
    ///
    /// Asynchronous, because the clipboard may be owned by another process
    /// that has to be asked for it — the same reason `TerminalView._paste` is.
    /// The completion lands on the UI thread, but by then the sheet may be
    /// gone, so it re-checks before touching anything.
    private func _switcherPaste() {
        Clipboard.getData(Clipboard.kTextPlain) { [weak self] data in
            guard let self = self, self._switcher.open,
                  let text = data?.text else { return }
            let add = SwitcherState.pasteable(
                text, room: SwitcherState.limit - self._switcher.text.count)
            guard !add.isEmpty else { return }
            self.setState {
                self._switcher.text += add
                self._switcher.index = 0
            }
            // The host part may have just changed — pasting a whole
            // `box/ws:dev` over an empty line is the ordinary case.
            self._switcherRefresh()
        }
    }

    /// Copy the destination being pointed at: the highlighted row, or the
    /// typed line when the typed line *is* the choice (index 0, and Enter
    /// there creates what was typed).
    private func _switcherCopy() {
        let matches = _switcherMatches
        let row = _switcher.index > 0 && _switcher.index <= matches.count
            ? matches[_switcher.index - 1] : nil
        let text = row?.typed ?? _switcher.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Clipboard.setData(ClipboardData(text: text))
    }

    /// Act on a chosen row.
    func _goTo(_ target: SwitcherTarget) {
        switch target {
        case .workspace(let spec):
            _open(spec)
        case .session(let host, let id, let name):
            // Into the workspace on screen, when it is one on the same
            // machine: "bring that session in here" is what someone looking at
            // a workspace means. Otherwise the session gets a workspace of its
            // own, named after it, which is also how it stops being loose.
            let current = tabs.indices.contains(active) ? tabs[active] : nil
            if let tab = current, let workspace = tab.workspace,
               workspace.spec.host == host {
                _adoptSession(tab, session: id)
                return
            }
            let label = name.isEmpty ? "session-\(id)" : name
            guard let spec = WorkspaceSpec("remote:\(host)/ws:\(label)") else { return }
            _open(spec, adopting: id)
        }
    }

    /// Open a workspace, and remember it as the one to come back to.
    private func _open(_ spec: WorkspaceSpec, adopting session: UInt32? = nil) {
        WorkspaceMemory.remember(spec)
        // Already open? Show it rather than attaching a second client to the
        // same sessions — which works (milestone 6 says who wins) but is not
        // what someone picking it from a list is asking for.
        if let existing = tabs.firstIndex(where: { $0.workspace?.spec == spec }) {
            setState { active = existing }
            if let session = session { _adoptSession(tabs[existing], session: session) }
            return
        }
        setState { _openWorkspace(spec, adopting: session) }
    }

    // MARK: - Drawing

    func _switcherOverlay(_ body: Size) -> Widget {
        let matches = _switcherMatches
        let width = min(560, max(280, body.width - 80))

        var children: [Widget] = [
            SizedBox(width: width, height: 14),
            _line("  go to", SwitcherChrome.hint, 11),
            SizedBox(width: width, height: 4),
            _line("  ❯ " + _switcher.text + "▏", SwitcherChrome.input, 15),
            SizedBox(width: width, height: 10),
        ]

        if let unreachable = _switcher.unreachable {
            // Name the likely cause. "did not answer" alone reads as "this
            // feature is broken" when the answer is almost always that the
            // daemon is not installed on that machine — which is a thing the
            // person can go and fix, and could not guess from silence.
            children.append(_line("    \(unreachable) did not answer — "
                                  + "is starling-termd there?",
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
        // The syntax, while there is nothing typed to obscure. A destination
        // can be a whole ssh command, and nobody would guess that from a
        // prompt that has only ever been shown hostnames.
        if _switcher.text.isEmpty {
            children.append(_line("    host/name · or  ssh -i ~/key box/ws:name",
                                  SwitcherChrome.hint, 11))
            children.append(SizedBox(width: width, height: 4))
        }
        // The clipboard chord is on this line rather than in the help sheet
        // (⌘/) because it is only true *here*: paste is a thing the terminal
        // does everywhere, and that it also fills this field is the part
        // nobody would think to try.
        #if os(macOS)
        let pasteChord = "⌘V"
        #else
        let pasteChord = "Ctrl+Shift+V"
        #endif
        children.append(_line("    ↑↓ choose · ⏎ open · \(pasteChord) paste · esc cancel",
                              SwitcherChrome.hint, 11))
        // The bottom margin, matching the 14 at the top. It used to be the
        // slack left over in a fixed height; sizing to the content means it
        // has to be said.
        children.append(SizedBox(width: width, height: 14))

        // Height comes from the content, not from a formula. It used to be
        // `96 + rows × 26`, which is the same number until the typed line
        // wraps — and paste is what makes that ordinary, since a destination
        // worth pasting is usually a whole ssh command. Past the formula's
        // guess the hint and the footer were drawn below the panel, on the
        // bare scrim. The help sheet next door has always sized this way.
        let panel = SizedBox(
            width: width,
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
                _goTo(row.target)
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
