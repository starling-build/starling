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
    /// An app's own formats, keyed by MIME type — e.g. Slides' shapes as
    /// "application/x-starling-slides-shapes". Only another Starling app
    /// understands them; every other program sees the standard flavours, so
    /// a writer should still set text (and html or png where it can).
    /// Name a private type "application/x-starling-<app>-<what>".
    public let custom: [String: Data]

    public init(text: String?, rtf: String? = nil, html: String? = nil, png: Data? = nil,
                custom: [String: Data] = [:]) {
        self.text = text
        self.rtf = rtf
        self.html = html
        self.png = png
        self.custom = custom
    }

    public var isEmpty: Bool {
        (text ?? "").isEmpty && rtf == nil && html == nil && png == nil && custom.isEmpty
    }

    /// MIME types of the standard flavours, as the Wayland bridge offers them.
    public static let mimeHtml = "text/html"
    public static let mimeRtf = "text/rtf"
    public static let mimePng = "image/png"

    /// Every MIME type this copy carries: the private ones (sorted, so the
    /// offer order is the same every run), then html, rtf, png and text.
    public var mimeTypes: [String] {
        var out = custom.keys.sorted()
        if html != nil { out.append(Self.mimeHtml) }
        if rtf != nil { out.append(Self.mimeRtf) }
        if png != nil { out.append(Self.mimePng) }
        if text != nil { out.append(Clipboard.kTextPlain) }
        return out
    }

    /// The bytes for one MIME type, or nil when this copy lacks it.
    public func bytes(for mime: String) -> Data? {
        switch mime {
        case Clipboard.kTextPlain: return text.map { Data($0.utf8) }
        case Self.mimeHtml: return html.map { Data($0.utf8) }
        case Self.mimeRtf: return rtf.map { Data($0.utf8) }
        case Self.mimePng: return png
        default: return custom[mime]
        }
    }

    /// What the browser page reads off the system clipboard (FlutterWeb's
    /// starling_clipboard_data): three little-endian UInt32 lengths — text,
    /// HTML, PNG — then those bytes. nil when all are empty or it is cut short.
    public init?(webPacked bytes: UnsafeBufferPointer<UInt8>) {
        guard bytes.count >= 12 else { return nil }
        func length(_ at: Int) -> Int { (0 ..< 4).reduce(0) { $0 | Int(bytes[at + $1]) << (8 * $1) } }
        let t = length(0), h = length(4), p = length(8)
        guard t + h + p > 0, 12 + t + h + p <= bytes.count else { return nil }
        let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[12 ..< 12 + t]), as: UTF8.self)
        let html = String(decoding: UnsafeBufferPointer(rebasing: bytes[12 + t ..< 12 + t + h]), as: UTF8.self)
        let png = Data(bytes[12 + t + h ..< 12 + t + h + p])
        self.init(text: t > 0 ? text : nil, html: h > 0 ? html : nil, png: p > 0 ? png : nil)
    }
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
    /// process (every flavour, private ones included), it just does not reach
    /// other applications.
    private nonisolated(unsafe) static var _fallback: ClipboardData? = nil
    private static let _fallbackLock = NSLock()

    /// Put `data` on the clipboard. Fire-and-forget, like Dart's.
    /// Every flavour, for a provider that trades them; the text alone for
    /// one that does not.
    public static let kAll = "*/*"

    public static func setData(_ data: ClipboardData) {
        if let provider = provider {
            _fallbackLock.lock()
            _lastSet = data.custom.isEmpty ? nil : data
            _fallbackLock.unlock()
            provider.setData(data)
        } else {
            _fallbackLock.lock()
            _fallback = data
            _fallbackLock.unlock()
        }
    }

    /// Read the clipboard. `completion` runs on the UI thread and is called
    /// exactly once; `nil` means there is nothing to paste.
    ///
    /// `format` is `kTextPlain` (text only), `kAll` (every standard flavour
    /// plus the private types in `readFormats`), or one MIME type — e.g. a
    /// private format — which comes back alone (in `custom` for a private type).
    public static func getData(_ format: String,
                               completion: @escaping (ClipboardData?) -> Void) {
        if let provider = provider {
            if format == kAll {
                provider.getData { data in completion(_restoringPrivate(data)) }
            } else if format == kTextPlain {
                provider.getText { text in
                    completion(text.map { ClipboardData(text: $0) })
                }
            } else {
                provider.getFormat(format) { bytes in
                    completion(bytes.map { _single(format, $0) })
                }
            }
            return
        }
        _fallbackLock.lock()
        let data = _fallback
        _fallbackLock.unlock()
        if format == kAll { completion(data); return }
        if format == kTextPlain { completion(data?.text.map { ClipboardData(text: $0) }); return }
        completion(data?.bytes(for: format).map { _single(format, $0) })
    }

    /// The last data set with private types, for a provider that cannot carry them (Cocoa, Win32, GTK, web).
    private nonisolated(unsafe) static var _lastSet: ClipboardData? = nil

    /// `data` read back through a provider that dropped the private types: when the clipboard still holds the
    /// text and picture this process last put there, it is still that copy, so its private types come back with it.
    /// Anything copied since differs in text or picture and comes back as it is.
    static func _restoringPrivate(_ data: ClipboardData?) -> ClipboardData? {
        guard let data, data.custom.isEmpty else { return data }
        _fallbackLock.lock()
        let last = _lastSet
        _fallbackLock.unlock()
        guard let last, (data.text ?? "") == (last.text ?? ""), data.png == nil || data.png == last.png,
              data.png != nil || last.png == nil || !(data.text ?? "").isEmpty else { return data }
        return ClipboardData(text: data.text, rtf: data.rtf, html: data.html, png: data.png, custom: last.custom)
    }

    /// The MIME types on offer right now, best first as the owner listed them
    /// (empty when the clipboard is empty or the provider cannot tell). Cheap:
    /// no data moves, so an app can call it to enable Paste or Paste Special.
    public static func availableFormats(_ completion: @escaping ([String]) -> Void) {
        if let provider = provider { provider.availableFormats(completion); return }
        _fallbackLock.lock()
        let data = _fallback
        _fallbackLock.unlock()
        completion(data?.mimeTypes ?? [])
    }

    /// Private types `getData(kAll)` also reads, besides the standard
    /// flavours. An app adds its own at startup; anything else on offer is
    /// left on the clipboard rather than copied across on every paste.
    public nonisolated(unsafe) static var readFormats: [String] = []

    static func _single(_ mime: String, _ bytes: Data) -> ClipboardData {
        let str = { String(decoding: bytes, as: UTF8.self) }
        switch mime {
        case ClipboardData.mimeHtml: return ClipboardData(text: nil, html: str())
        case ClipboardData.mimeRtf: return ClipboardData(text: nil, rtf: str())
        case ClipboardData.mimePng: return ClipboardData(text: nil, png: bytes)
        default: return ClipboardData(text: nil, custom: [mime: bytes])
        }
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
    /// One MIME type's bytes, or nil when it is not on offer.
    func getFormat(_ mime: String, _ completion: @escaping (Data?) -> Void)
    /// The MIME types on offer (see `Clipboard.availableFormats`).
    func availableFormats(_ completion: @escaping ([String]) -> Void)
}

public extension ClipboardProvider {
    func setData(_ data: ClipboardData) { setText(data.text ?? "") }
    func getData(_ completion: @escaping (ClipboardData?) -> Void) {
        getText { completion($0.map { ClipboardData(text: $0) }) }
    }
    /// A text-only provider has text and nothing else.
    func getFormat(_ mime: String, _ completion: @escaping (Data?) -> Void) {
        guard mime == Clipboard.kTextPlain else { completion(nil); return }
        getText { completion($0.map { Data($0.utf8) }) }
    }
    func availableFormats(_ completion: @escaping ([String]) -> Void) {
        getText { completion($0 == nil ? [] : [Clipboard.kTextPlain]) }
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

    /// Every flavour at once: the text for every plain-text spelling, the
    /// rest each under its own MIME type.
    public func setData(_ data: ClipboardData) {
        guard let h = handle else { return }
        var mimes: [String] = []
        var blobs: [Data] = []
        for m in data.mimeTypes where m != Clipboard.kTextPlain {
            if let b = data.bytes(for: m) { mimes.append(m); blobs.append(b) }
        }
        // The C side copies everything before returning, so plain C copies
        // that live across the call are enough.
        let mimePtrs: [UnsafePointer<CChar>?] = mimes.map { m in
            let u = Array(m.utf8CString)
            let p = UnsafeMutablePointer<CChar>.allocate(capacity: u.count)
            p.initialize(from: u, count: u.count)
            return UnsafePointer(p)
        }
        let blobPtrs: [UnsafePointer<CChar>?] = blobs.map { d in
            let p = UnsafeMutablePointer<CChar>.allocate(capacity: max(d.count, 1))
            d.withUnsafeBytes { raw in
                if let base = raw.baseAddress { UnsafeMutableRawPointer(p).copyMemory(from: base, byteCount: d.count) }
            }
            return UnsafePointer(p)
        }
        defer { for p in mimePtrs + blobPtrs { p.map { UnsafeMutablePointer(mutating: $0).deallocate() } } }
        let lens = blobs.map { $0.count }
        let count = Int32(mimes.count)
        if let text = data.text {
            let n = text.utf8.count
            _ = text.withCString { wlclip_set_data(h, $0, n, mimePtrs, blobPtrs, lens, count) }
        } else {
            _ = wlclip_set_data(h, nil, 0, mimePtrs, blobPtrs, lens, count)
        }
    }

    public func getFormat(_ mime: String, _ completion: @escaping (Data?) -> Void) {
        guard let h = handle else { completion(nil); return }
        let box = Unmanaged.passRetained(_DataCompletionBox(completion)).toOpaque()
        let rc = mime.withCString { wlclip_read_mime(h, $0, _dataCallback, box) }
        if rc != 0 {
            Unmanaged<_DataCompletionBox>.fromOpaque(box).takeRetainedValue()
                .deliverOnMain(nil)
        }
    }

    public func availableFormats(_ completion: @escaping ([String]) -> Void) {
        guard let h = handle else { completion([]); return }
        let box = Unmanaged.passRetained(_DataCompletionBox { data in
            guard let data = data else { completion([]); return }
            completion(String(decoding: data, as: UTF8.self)
                .split(separator: "\n").map(String.init))
        }).toOpaque()
        if wlclip_read_mimes(h, _dataCallback, box) != 0 {
            Unmanaged<_DataCompletionBox>.fromOpaque(box).takeRetainedValue()
                .deliverOnMain(nil)
        }
    }

    /// The text, plus html, rtf, png and `Clipboard.readFormats` where the
    /// owner offers them. The reads queue in order on the bridge thread and
    /// answer in order on this one, so the last answer completes the set.
    public func getData(_ completion: @escaping (ClipboardData?) -> Void) {
        availableFormats { offered in
            let wanted = [ClipboardData.mimeHtml, ClipboardData.mimeRtf, ClipboardData.mimePng]
                + Clipboard.readFormats
            let reads = wanted.filter { offered.firstIndex(of: $0) != nil }
            var got: [String: Data] = [:]
            var text: String? = nil
            var left = reads.count + 1
            func finish() {
                left -= 1
                guard left == 0 else { return }
                let str = { (m: String) in got[m].map { String(decoding: $0, as: UTF8.self) } }
                var custom = got
                for m in [ClipboardData.mimeHtml, ClipboardData.mimeRtf, ClipboardData.mimePng] {
                    custom[m] = nil
                }
                let data = ClipboardData(text: text, rtf: str(ClipboardData.mimeRtf),
                                         html: str(ClipboardData.mimeHtml),
                                         png: got[ClipboardData.mimePng], custom: custom)
                completion(data.isEmpty && text == nil ? nil : data)
            }
            self.getText { text = $0; finish() }
            for m in reads { self.getFormat(m) { b in got[m] = b; finish() } }
        }
    }
}

private let _dataCallback: WlClipTextCallback = { ctx, bytes, len in
    guard let ctx = ctx else { return }
    let boxed = Unmanaged<_DataCompletionBox>.fromOpaque(ctx).takeRetainedValue()
    boxed.deliverOnMain(bytes.map { Data(bytes: $0, count: Int(len)) })
}

/// `_TextCompletionBox` for bytes.
private final class _DataCompletionBox {
    let completion: (Data?) -> Void
    init(_ completion: @escaping (Data?) -> Void) { self.completion = completion }

    func deliverOnMain(_ value: Data?) {
        let call: () -> Void = { self.completion(value) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(call, to: (@Sendable () -> Void).self))
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
