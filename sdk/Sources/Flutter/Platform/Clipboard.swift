// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if os(Linux)
import WaylandClipboardBridge
#endif

/// Clipboard data, mirroring Dart's `ClipboardData` so Flutter documentation
/// keeps applying.
/// What goes on or comes off the clipboard: plain text always, and the
/// richer flavours a host and an app can trade — RTF and HTML for
/// formatted text, PNG bytes for a picture. A writer sets every flavour it
/// can; a reader takes the best it understands.
public struct ClipboardData: Sendable {
    public let text: String?
    public let rtf: String?
    public let html: String?
    public let png: Data?

    public init(text: String?, rtf: String? = nil, html: String? = nil, png: Data? = nil) {
        self.text = text
        self.rtf = rtf
        self.html = html
        self.png = png
    }

    public var isEmpty: Bool { (text ?? "").isEmpty && rtf == nil && html == nil && png == nil }
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
    /// Every flavour, for a provider that trades them; the text alone for
    /// one that does not.
    public static let kAll = "*/*"

    public static func setData(_ data: ClipboardData) {
        if let provider = provider {
            provider.setData(data)
        } else {
            _fallbackLock.lock()
            _fallbackText = data.text ?? ""
            _fallbackLock.unlock()
        }
    }

    /// Read the clipboard. `completion` runs on the UI thread and is called
    /// exactly once; `nil` means there is nothing to paste.
    public static func getData(_ format: String,
                               completion: @escaping (ClipboardData?) -> Void) {
        guard format == kTextPlain || format == kAll else { completion(nil); return }
        if let provider = provider {
            if format == kAll {
                provider.getData { data in completion(data) }
            } else {
                provider.getText { text in
                    completion(text.map { ClipboardData(text: $0) })
                }
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
    /// Rich flavours. A provider that has only text keeps the defaults.
    func setData(_ data: ClipboardData)
    func getData(_ completion: @escaping (ClipboardData?) -> Void)
}

public extension ClipboardProvider {
    func setData(_ data: ClipboardData) { setText(data.text ?? "") }
    func getData(_ completion: @escaping (ClipboardData?) -> Void) {
        getText { completion($0.map { ClipboardData(text: $0) }) }
    }
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
        if let h = handle { wlclip_destroy(h) }
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
