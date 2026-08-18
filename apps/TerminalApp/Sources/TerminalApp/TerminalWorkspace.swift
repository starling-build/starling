// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A tab whose panes live on another machine — milestone 3 of
// docs/plans/remote-workspace.md, and the one where a tmux user gets their
// workflow back.
//
// Everything hard is already built and this file is the seam between the two
// halves. The framework has the parts that talk: RemoteTerminal is one pane's
// byte stream, RemoteWorkspace is the connection that stores the arrangement.
// The app has the parts that draw: the pane tree in TerminalPanes.swift, the
// blob's format in PaneLayout.swift. What is left is the mapping between
// them, which is exactly three things:
//
//   attach   the blob's leaves become panes, each one attached to the session
//            id it names, focus where the blob says
//   record   any change to the tree becomes a blob and goes back (debounced
//            inside RemoteWorkspace — a seam drag is one write, not a hundred)
//   join     a pane that opened a NEW session tells the workspace about it,
//            so the next attach finds it
//
// The daemon never learns what any of that means. It holds a name, a set of
// sessions and some bytes.
//
// What closing a remote pane does NOT do is kill the shell behind it — the
// protocol has no frame for that, and detaching is what the design promises
// everywhere else. The session keeps running and drops out of the layout;
// `starling-termd --list` on the far machine still finds it. A frame that
// ends a session belongs with milestone 5, beside detaching a whole
// workspace at once.

import Flutter
import Foundation

#if !os(iOS)

/// Where a workspace lives, as a person types it: `remote:host/ws:dev`.
///
/// The `ws:` is what distinguishes a workspace from the plain
/// `remote:host/name` a single session already uses (the launcher in
/// sdk/Examples/TerminalTiling), so the two can share one field the day this
/// grows a launcher of its own.
struct WorkspaceSpec: Equatable {
    /// "local" runs the daemon here rather than over ssh — a persistent
    /// workspace on this machine, which is the same feature without a network.
    let host: String
    let name: String

    init?(_ text: String) {
        var rest = text.trimmingCharacters(in: .whitespaces)
        if rest.lowercased().hasPrefix("remote:") {
            rest = String(rest.dropFirst("remote:".count))
        }
        var host = "local"
        // The FIRST slash: a hostname cannot contain one, and everything after
        // it is the workspace part.
        if let slash = rest.firstIndex(of: "/") {
            host = String(rest[..<slash]).trimmingCharacters(in: .whitespaces)
            rest = String(rest[rest.index(after: slash)...])
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard rest.lowercased().hasPrefix("ws:") else { return nil }
        let name = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !host.isEmpty else { return nil }
        self.host = host
        self.name = name
    }

    /// The workspace this launch was asked for, if any.
    ///
    /// `--workspace remote:host/ws:dev`, or `STARLING_WORKSPACE` for a shell
    /// that cannot pass argv (the desktop's app records, a `.desktop` Exec
    /// line someone would rather not edit). This is the entry point the plan
    /// asks for; it is not yet the launcher the plan pictures, and the day one
    /// exists it calls the same `_openWorkspace`.
    static func fromLaunch() -> WorkspaceSpec? {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--workspace"), i + 1 < args.count,
           let spec = WorkspaceSpec(args[i + 1]) {
            return spec
        }
        if let text = ProcessInfo.processInfo.environment["STARLING_WORKSPACE"],
           let spec = WorkspaceSpec(text) {
            return spec
        }
        return nil
    }
}

/// The far side of one tab: the control link, and a link per pane.
///
/// Every method here is called on the UI thread, and every callback out of
/// the framework hops back onto it before touching anything — `remotes` is
/// read while building a frame, so it cannot be edited from a link's thread.
/// That hop is what the `@unchecked` stands for: there is no lock in here and
/// there must not be one, because everything this touches is UI state.
final class TerminalWorkspace: @unchecked Sendable {
    let spec: WorkspaceSpec
    let link: RemoteWorkspace

    /// One connection per pane, by pane id. A pane with no entry is one whose
    /// session has not been asked for yet.
    private var remotes: [Int: RemoteTerminal] = [:]

    /// Backlog a pane asks for on its first attach. 256 KB is several screens
    /// of a wide terminal — enough that scrolling up a little still finds
    /// something — against 8 MB of ring per pane if this is left off.
    static let paneReplayBytes: UInt32 = 256 * 1024

    /// The arrangement changed in a way that must be recorded, or a pane
    /// learned its session id. Set by the tabs state; called on the UI thread.
    var onChange: (() -> Void)?

    init(spec: WorkspaceSpec) {
        self.spec = spec
        self.link = RemoteWorkspace(name: spec.name, host: spec.host)
    }

    /// Connect, and hand back what the far side was holding. `nil` means a
    /// workspace nobody has arranged yet — a first launch, or a name typed
    /// for the first time — and the caller opens a single pane instead.
    func start(onRestore: @escaping @Sendable (PaneLayout?) -> Void,
               onRearranged: @escaping @Sendable (PaneLayout) -> Void) {
        link.onRestore = { blob in
            // Off the link's thread before any of this reaches the tree.
            DispatchQueue.main.async { onRestore(PaneLayout.decode(blob)) }
        }
        link.onLayoutChanged = { blob in
            guard let layout = PaneLayout.decode(blob) else { return }
            DispatchQueue.main.async { onRearranged(layout) }
        }
        link.start()
    }

    /// True while another client's arrangement is being applied, so the
    /// changes that causes are not written straight back as if they were ours.
    /// The daemon would forward that to the other client, which would apply it
    /// and write back, and two clients would trade the same tree forever.
    private(set) var adopting = false

    func adopt(_ body: () -> Void) {
        adopting = true
        body()
        adopting = false
    }

    /// Give a pane a session: the one the blob named, or a new one when
    /// `session` is nil or 0.
    ///
    /// `cwd` is where the blob says that pane's shell was. It is used only
    /// when a session has to be OPENed — restoring the arrangement after the
    /// daemon itself restarted, which is the case where the panes come back
    /// but their shells do not. An attach that finds its session ignores it,
    /// because that shell has its own idea of where it is and is right.
    func attach(_ pane: TerminalPane, session: UInt32?, cwd: String? = nil) {
        // No size is passed: the view resizes the session on mount and the
        // link turns that into a RESIZE frame, so the far end is told the
        // pane's real size rather than the one it was guessed at here.
        let remote = RemoteTerminal(session: pane.session,
                                    host: spec.host,
                                    attach: (session ?? 0) == 0 ? nil : session,
                                    command: reopenCommand(in: cwd))
        // The blob's directory is right for the FIRST open — the pane has no
        // screen of its own yet, so there is nothing better to know. From then
        // on the pane's own emulator is the better answer, and it is asked at
        // the moment an OPEN is sent rather than remembered here: a session
        // vanishing is exactly the case where "where was I" changed since.
        remote.commandForOpen = { [weak self, weak pane] in
            guard let self = self, let pane = pane else { return nil }
            return self.reopenCommand(in: Self.paneCwd(pane) ?? cwd)
        }
        // Enough to rebuild the screen and a few scrollbacks of context, and
        // not the whole ring: N panes attach at once here, and 8 MB each is
        // minutes of nothing on the link this feature exists for.
        remote.maxReplayBytes = Self.paneReplayBytes
        // The blob's ids come from a daemon that may have restarted since it
        // wrote them. Restoring the arrangement is the promise; a pane that
        // refuses to come back because its shell is gone keeps none of it.
        remote.reopenIfSessionGone = true
        remote.onLink = { state in
            guard case .live(let id) = state else { return }
            // The capture list belongs on the closure that HOPS: a `self`
            // captured before the hop is one the compiler has to assume is
            // still being used on the link's thread.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Idempotent on both sides — every reconnect says this again.
                self.link.add(session: id)
                // The id may be NEW (a fresh session, or one reopened after
                // the old one vanished), and the blob is what carries it to
                // the next attach.
                self.onChange?()
            }
        }
        remotes[pane.id] = remote
        remote.start()
    }

    /// What a reopened pane runs, so it comes back where it was.
    ///
    /// `OPEN` already carries a command and the daemon runs it with the
    /// shell's `-c`, so this needs no protocol change: step into the
    /// directory, then BECOME the shell, which leaves a pane indistinguishable
    /// from one opened normally — same process, no wrapper, and `exit` still
    /// ends the session. `$STARLING_SHELL` is exported by the daemon beside
    /// the pty precisely so this names the same shell a plain OPEN would have
    /// run, rather than guessing from `$SHELL` (which the daemon may itself
    /// have overridden).
    ///
    /// `&&`, not `;`: a directory that no longer exists on the far machine
    /// should not silently hand back a shell in `$HOME` pretending to be the
    /// pane you left. The session ends, visibly, and the next OPEN has no cwd.
    private func reopenCommand(in cwd: String?) -> String? {
        // Composed only for a daemon that says it runs commands through a
        // POSIX shell (HELLO_OK's caps byte). A Windows daemon, or one too old
        // to say, gets no command at all and its pane opens where it always
        // did — a pane in the wrong directory beats a pane that exits.
        guard link.serverUsesPosixShell else { return nil }
        guard let cwd = cwd, cwd.hasPrefix("/") else { return nil }
        // POSIX single-quoting: everything is literal inside quotes except a
        // quote itself, which has to leave and come back.
        let quoted = cwd.replacingOccurrences(of: "'", with: "'\\''")
        return "cd '\(quoted)' && exec \"$STARLING_SHELL\""
    }

    /// Drop a pane's link. The session on the far side keeps running — see
    /// the header.
    func detach(_ pane: TerminalPane) {
        remotes.removeValue(forKey: pane.id)?.stop()
    }

    /// The far-side session behind a pane, or 0 for one that has not landed
    /// yet. A leaf encodes as 0 in that case and is rewritten the moment its
    /// ATTACHED arrives.
    func sessionId(_ pane: TerminalPane) -> UInt32 {
        remotes[pane.id]?.remoteId ?? 0
    }

    /// Tell the far side this pane's size again.
    ///
    /// A pty has one size and two clients can be attached, so somebody has to
    /// lose: the daemon takes the last RESIZE it is given and that is the
    /// policy. What makes it the RIGHT policy is this — the client someone is
    /// actually using re-asserts when they engage with a pane, so "last
    /// writer" means "the machine in your hands" rather than "whichever
    /// happened to attach most recently".
    ///
    /// Between engagements the other client draws at a size the shell does not
    /// know about: its grid is its own, the text inside it was wrapped for
    /// somebody else's. That is the cost of one pty and no server-side
    /// rendering, it is visible rather than corrupting, and one click fixes it.
    /// Every pane in the tab, not just the one that was clicked: the person
    /// engaged with this WINDOW, and a window whose focused pane is sized for
    /// it while the pane beside it is still sized for another machine is a
    /// worse answer than either client winning outright.
    func assertSizes(_ tab: TerminalTab) {
        for pane in tab.root.panes {
            guard remotes[pane.id] != nil else { continue }
            pane.session.lock.lock()
            let (cols, rows) = (pane.session.emulator.cols,
                                pane.session.emulator.rows)
            pane.session.lock.unlock()
            pane.session.resizeProcess(cols: cols, rows: rows)
        }
    }

    /// Record the tab's arrangement. Cheap to call — RemoteWorkspace holds it
    /// and writes the last one after a pause.
    func record(_ tab: TerminalTab) {
        guard !adopting else { return }
        let panes = tab.root.panes
        let active = panes.firstIndex { $0.id == tab.activePaneId } ?? 0
        let layout = PaneLayout(
            root: tab.root.layoutNode { [weak self] pane in
                LeafInfo(session: self?.sessionId(pane) ?? 0,
                         cwd: Self.paneCwd(pane))
            },
            activeLeaf: active)
        link.setLayout(layout.encoded())
    }

    /// Where a pane's shell last said it was.
    ///
    /// Read from OUR emulator, which is the only one in the system: the bytes
    /// that told it are the same bytes the far side wrote, so this is the
    /// remote machine's directory even though nothing asked the remote machine
    /// anything. Shells that emit no OSC 7 report nil and their panes reopen
    /// in the default directory, as they always did.
    private static func paneCwd(_ pane: TerminalPane) -> String? {
        pane.session.lock.lock()
        defer { pane.session.lock.unlock() }
        return pane.session.emulator.cwd
    }

    /// Close the whole workspace: every pane's link, then the control link,
    /// which flushes a pending layout on its way down.
    func close() {
        for remote in remotes.values { remote.stop() }
        remotes.removeAll()
        link.stop()
    }
}

#endif  // !os(iOS)
