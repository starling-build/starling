// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The shell's own right-click verbs, without waiting for them.
//
// Everything a Windows context menu offers beyond the two or three things an
// app implements itself comes from the shell: the static verbs registered
// against the file type, and every installed IContextMenu handler. Assembling
// that set is what makes Explorer's menu take 370ms to appear -- it is
// synchronous, and it is done before a single row is drawn.
//
// So a session here is a THREAD PER TIER, and this type is the way to talk
// to them without thinking about that. `open` returns immediately; `items`
// calls back on the main thread whenever the shell is finished; the caller
// draws its own verbs in between, and a verb on the cheap tier can be
// invoked while the full query is still running. Every call into the C
// session is serialized onto one queue, which is what the ping-pong on the
// other side requires.
//
// The session owns real COM objects belonging to real third-party DLLs, so it
// has to be closed. `close()` is safe at any point, including while the query
// is still running -- a menu dismissed before the handlers answered is the
// ordinary case.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

/// Which of the session's two menus a row came from.
///
/// The cheap one is the same shell asked about fewer association classes --
/// the item's own ProgID and extension rather than `*` and
/// AllFilesystemObjects, where the expensive handlers live. Measured: 2ms for
/// a document against 48ms for the full set, and its rows are a strict subset
/// of the full menu's, so replacing one with the other only ever adds.
///
/// A row's tier travels with it because the two menus number their verbs
/// independently: id 3 means different things in each.
public enum Win32ShellMenuTier: Int32, Sendable {
    case fast = 0
    case full = 1
}

/// One row of the shell's menu.
public struct Win32ShellVerb: Sendable {
    /// What `invoke` takes. -1 for a separator or a submenu, neither of which
    /// is a command.
    public let id: Int32
    /// The token `expand` takes, or 0 when the row is not a submenu.
    public let submenu: Int32
    public let title: String
    /// The canonical verb -- "open", "copy", "delete", "properties" -- or "".
    /// Empty is the common case for a third-party handler and is not an
    /// error; it exists so a caller can recognise the verbs it already draws
    /// itself and drop the shell's duplicate.
    public let verb: String
    public let isSeparator: Bool
    public let isSubmenu: Bool
    public let isEnabled: Bool
    /// What a double-click would have done. Windows draws it bold.
    public let isDefault: Bool
}

public final class Win32ShellMenu {
    /// One queue for ALL sessions rather than one each. The C side is a
    /// ping-pong with no lock around its request slot, and two sessions in
    /// flight would still be two threads calling into the same shell -- which
    /// is the contention the icon cache already measured itself out of.
    private static let queue = DispatchQueue(label: "starling.shellmenu",
                                             qos: .userInitiated)

    private var handle: OpaquePointer?

    /// Starts asking the shell about `path`. Cheap: the work is on the
    /// session's own thread from here.
    ///
    /// `background` asks for the folder's menu -- what a right-click on empty
    /// space gets, and the only place New and Paste live. `extended` is
    /// Shift+right-click. `owner` is the window a verb's dialog is parented
    /// to; a properties sheet with no owner is a window the user can lose
    /// behind the one they asked it from.
    public init?(path: String, background: Bool = false, extended: Bool = false,
                 owner: UInt64) {
        guard let handle = flwin32_shellmenu_open(path, background ? 1 : 0,
                                                  extended ? 1 : 0, owner) else {
            return nil
        }
        self.handle = handle
    }

    /// The top-level rows, on the main thread, once the shell has answered.
    /// Empty when the menu could not be built at all -- an item that has gone
    /// away between the click and the query, most often.
    public func items(_ tier: Win32ShellMenuTier,
                      _ done: @escaping ([Win32ShellVerb]) -> Void) {
        deliver({ [weak self] in self?.itemsSync(tier) ?? [] }, done)
    }

    /// The rows inside a submenu. Work rather than a read: the handler has to
    /// be told to populate it first, which is why this is asynchronous too.
    public func expand(_ tier: Win32ShellMenuTier, _ token: Int32,
                       _ done: @escaping ([Win32ShellVerb]) -> Void) {
        deliver({ [weak self] in self?.expandSync(tier, token) ?? [] }, done)
    }

    /// The blocking forms, for a CLI probe and nothing else -- they hold the
    /// calling thread for as long as the shell takes, which on a cold first
    /// menu was measured at over a second. A surface that draws frames must
    /// use the callback forms above.
    public func itemsSync(_ tier: Win32ShellMenuTier = .full) -> [Win32ShellVerb] {
        fetch { handle, buffer, max in
            flwin32_shellmenu_items(handle, tier.rawValue, buffer, max)
        }
    }

    public func expandSync(_ tier: Win32ShellMenuTier,
                           _ token: Int32) -> [Win32ShellVerb] {
        fetch { handle, buffer, max in
            flwin32_shellmenu_expand(handle, tier.rawValue, token, buffer, max)
        }
    }

    /// Where the assembly's time went, in milliseconds. Blocks until the
    /// query is done, like `itemsSync` -- for the probe.
    public func timings() -> (bind: Double, query: Double, walk: Double, verbs: Double) {
        guard let handle else { return (0, 0, 0, 0) }
        var bind = 0.0, query = 0.0, walk = 0.0, verbs = 0.0
        flwin32_shellmenu_timings(handle, &bind, &query, &walk, &verbs)
        return (bind, query, walk, verbs)
    }

    /// Runs a verb. Off the UI thread for the reason everything else here is,
    /// and then some: Properties opens a modal sheet, and Delete a
    /// confirmation, and both of them run for as long as the user takes.
    public func invoke(_ tier: Win32ShellMenuTier, _ id: Int32) {
        guard let handle else { return }
        Self.queue.async { flwin32_shellmenu_invoke(handle, tier.rawValue, id) }
    }

    /// Ends the session. Queued behind whatever is already in flight, so a
    /// menu dismissed while the shell is still working closes cleanly rather
    /// than racing it.
    public func close() {
        guard let handle else { return }
        self.handle = nil
        Self.queue.async { flwin32_shellmenu_close(handle) }
    }

    deinit { close() }

    private func deliver(_ work: @escaping () -> [Win32ShellVerb],
                         _ done: @escaping ([Win32ShellVerb]) -> Void) {
        Self.queue.async {
            let rows = work()
            DispatchQueue.main.async { done(rows) }
        }
    }

    private func fetch(_ call: (OpaquePointer, UnsafeMutablePointer<FlWin32ShellVerb>?,
                               Int32) -> Int32) -> [Win32ShellVerb] {
        guard let handle else { return [] }
        var buffer = [FlWin32ShellVerb](repeating: FlWin32ShellVerb(),
                                        count: Int(FLWIN32_SHELLMENU_MAX))
        let n = buffer.withUnsafeMutableBufferPointer {
            call(handle, $0.baseAddress, Int32(FLWIN32_SHELLMENU_MAX))
        }
        return n > 0 ? buffer.prefix(Int(n)).map(Self.convert) : []
    }

    private static func convert(_ raw: FlWin32ShellVerb) -> Win32ShellVerb {
        var raw = raw
        let title = withUnsafeBytes(of: &raw.label) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let verb = withUnsafeBytes(of: &raw.verb) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return Win32ShellVerb(id: raw.id,
                              submenu: raw.submenu,
                              title: title,
                              verb: verb.lowercased(),
                              isSeparator: raw.is_separator != 0,
                              isSubmenu: raw.is_submenu != 0,
                              isEnabled: raw.is_enabled != 0,
                              isDefault: raw.is_default != 0)
    }
}
#endif
