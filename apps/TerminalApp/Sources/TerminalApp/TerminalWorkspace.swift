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
    func start(onRestore: @escaping @Sendable (PaneLayout?) -> Void) {
        link.onRestore = { blob in
            // Off the link's thread before any of this reaches the tree.
            DispatchQueue.main.async { onRestore(PaneLayout.decode(blob)) }
        }
        link.start()
    }

    /// Give a pane a session: the one the blob named, or a new one when
    /// `session` is nil or 0.
    func attach(_ pane: TerminalPane, session: UInt32?) {
        // No size is passed: the view resizes the session on mount and the
        // link turns that into a RESIZE frame, so the far end is told the
        // pane's real size rather than the one it was guessed at here.
        let remote = RemoteTerminal(session: pane.session,
                                    host: spec.host,
                                    attach: (session ?? 0) == 0 ? nil : session)
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

    /// Record the tab's arrangement. Cheap to call — RemoteWorkspace holds it
    /// and writes the last one after a pause.
    func record(_ tab: TerminalTab) {
        let panes = tab.root.panes
        let active = panes.firstIndex { $0.id == tab.activePaneId } ?? 0
        let layout = PaneLayout(
            root: tab.root.layoutNode { [weak self] in self?.sessionId($0) ?? 0 },
            activeLeaf: active)
        link.setLayout(layout.encoded())
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
