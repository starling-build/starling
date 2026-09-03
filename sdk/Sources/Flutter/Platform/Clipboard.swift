// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if os(Linux)
import WaylandClipboardBridge
#endif

/// Clipboard data, mirroring Dart's `ClipboardData` so Flutter documentation
/// keeps applying.
public struct ClipboardData: Sendable {
    public let text: String?
    public init(text: String?) { self.text = text }
}

/// The system clipboard.
///
///     Clipboard.setData(ClipboardData(text: "hello"))
///     Clipboard.getData(Clipboard.kTextPlain) { data in … }
///     let data = await Clipboard.getData(Clipboard.kTextPlain)
///
/// **The callback form is the primitive and the `async` form wraps it.** That
/// is deliberate: `DispatchQueue.main` is drained under the Starling dma-buf
/// child and the Win32 host, but *not* under `GTKHost`, which runs `gtk_main`
/// and pumps through `g_timeout_add`. An `async` API that resumed its
/// continuation on GCD's main queue would silently never fire there — no error,
/// just a paste that never returns. Hosts implement the callback; `async`
/// inherits whatever they get right.
///
/// Callbacks are delivered on the UI thread.
public enum Clipboard {
    /// The plain-text format, spelled as Dart spells it.
    public static let kTextPlain = "text/plain"

    /// A host installs this to provide a real clipboard. Left nil, the
    /// clipboard is process-local (see `_fallbackText`), which keeps apps
    /// working when there is no system clipboard to talk to.
    ///
    /// Shaped as a pair of closures rather than a protocol because that is how
    /// this SDK already does host capabilities — see `windowedHostBoot` in
    /// StarlingAppHost.swift. Three unrelated concrete hosts do not need an
    /// abstraction between them.
    public nonisolated(unsafe) static var provider: ClipboardProvider? = nil

    /// Used when no provider is installed: copy/paste still works within the
    /// process, it just does not reach other applications.
    private nonisolated(unsafe) static var _fallbackText: String? = nil
    private static let _fallbackLock = NSLock()

    /// Put `data` on the clipboard. Fire-and-forget, like Dart's.
    public static func setData(_ data: ClipboardData) {
        let text = data.text ?? ""
        if let provider = provider {
            provider.setText(text)
        } else {
            _fallbackLock.lock()
            _fallbackText = text
            _fallbackLock.unlock()
        }
    }

    /// Read the clipboard. `completion` runs on the UI thread and is called
    /// exactly once; `nil` means there is nothing to paste.
    public static func getData(_ format: String,
                               completion: @escaping (ClipboardData?) -> Void) {
        guard format == kTextPlain else { completion(nil); return }
        if let provider = provider {
            provider.getText { text in
                completion(text.map { ClipboardData(text: $0) })
            }
            return
        }
        _fallbackLock.lock()
        let text = _fallbackText
        _fallbackLock.unlock()
        completion(text.map { ClipboardData(text: $0) })
    }

    /// `async` convenience over `getData(_:completion:)`.
    ///
    /// Safe only where the host's callback actually fires — which is the
    /// host's job, not this wrapper's. Prefer the callback form in code that
    /// must run under every host.
    public static func getData(_ format: String) async -> ClipboardData? {
        await withCheckedContinuation { continuation in
            getData(format) { continuation.resume(returning: $0) }
        }
    }
}

/// What a host must supply to give `Clipboard` a real system clipboard.
/// `getText` must call its completion exactly once, on the UI thread, and must
/// not block waiting for another process — clipboard transfer is pull-based, so
/// the current owner may be slow, stopped, or gone.
public protocol ClipboardProvider {
    func setText(_ text: String)
    func getText(_ completion: @escaping (String?) -> Void)
}

#if os(Linux)

/// `Clipboard` for an app running under the Starling shell: a
/// zwlr_data_control client, so a copy here pastes into Chrome and a copy in
/// Chrome pastes here.
///
/// The bridge owns a private thread and Wayland connection; nothing below
/// blocks the UI thread. Completions are hopped back to it.
public final class WaylandClipboardProvider: ClipboardProvider {
    private let handle: OpaquePointer?

    /// Raised when the selection changes — a new owner, new content, or a
    /// clear. `hasText` says whether the new selection carries anything
    /// readable as text; `mine` says whether we are the new owner, which
    /// anything mirroring the selection elsewhere (a VM guest's clipboard)
    /// must check or it announces its own paste back to itself for ever.
    ///
    /// Fires on the bridge thread. Hop before touching app state.
    public var onSelectionChanged: ((_ hasText: Bool, _ mine: Bool) -> Void)? {
        didSet { _installSelectionCallback() }
    }

    /// True while this process owns the selection.
    public var ownsSelection: Bool {
        guard let h = handle else { return false }
        return wlclip_owns_selection(h) != 0
    }

    /// Returns nil when there is no data-control compositor to talk to, which
    /// is every environment except the Starling shell. Callers should fall
    /// back to leaving `Clipboard.provider` nil.
    public init?(display: String?) {
        if let display = display {
            handle = display.withCString { wlclip_connect($0) }
        } else {
            handle = wlclip_connect(nil)
        }
        if handle == nil { return nil }
    }

    deinit {
        if let h = handle {
            wlclip_set_selection_callback(h, nil, nil)
            wlclip_destroy(h)
        }
    }

    private func _installSelectionCallback() {
        guard let h = handle else { return }
        guard onSelectionChanged != nil else {
            wlclip_set_selection_callback(h, nil, nil)
            return
        }
        // Unretained: the bridge outlives no provider, and deinit clears the
        // callback before destroying it — so retaining here would be a cycle
        // that keeps the provider alive for ever.
        wlclip_set_selection_callback(h, { ctx, hasText, mine in
            guard let ctx else { return }
            let me = Unmanaged<WaylandClipboardProvider>
                .fromOpaque(ctx).takeUnretainedValue()
            me.onSelectionChanged?(hasText != 0, mine != 0)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    public func setText(_ text: String) {
        guard let h = handle else { return }
        let byteCount = text.utf8.count
        text.withCString { wlclip_set_text(h, $0, byteCount) }
    }

    public func getText(_ completion: @escaping (String?) -> Void) {
        guard let h = handle else { completion(nil); return }
        // The C callback fires on the bridge thread. Box the Swift closure so
        // it survives the trip through a raw pointer, and hop to the UI thread
        // before it touches anything the app owns.
        let box = Unmanaged.passRetained(_TextCompletionBox(completion))
            .toOpaque()
        let rc = wlclip_read_text(h, { ctx, text, len in
            guard let ctx = ctx else { return }
            let boxed = Unmanaged<_TextCompletionBox>.fromOpaque(ctx)
                .takeRetainedValue()
            var value: String? = nil
            if let text = text {
                value = String(decoding: UnsafeRawBufferPointer(
                    start: text, count: Int(len)), as: UTF8.self)
            }
            boxed.deliverOnMain(value)
        }, box)
        if rc != 0 {
            // Nothing was queued, so the C callback will never fire: reclaim
            // the box here or it leaks, and still answer the caller.
            Unmanaged<_TextCompletionBox>.fromOpaque(box).takeRetainedValue()
                .deliverOnMain(nil)
        }
    }
}

/// Carries a Swift closure through the C callback's `void*`.
private final class _TextCompletionBox {
    let completion: (String?) -> Void
    init(_ completion: @escaping (String?) -> Void) { self.completion = completion }

    func deliverOnMain(_ value: String?) {
        let call: () -> Void = { self.completion(value) }
        // Flutter builds in language mode 5 and this closure is not Sendable;
        // the same cast is used for host pushes in GpuDmaBufRenderer.
        DispatchQueue.main.async(
            execute: unsafeBitCast(call, to: (@Sendable () -> Void).self))
    }
}

#endif
