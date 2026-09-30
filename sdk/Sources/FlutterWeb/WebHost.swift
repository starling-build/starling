// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Runs a Starling app in a browser tab. The counterpart of CocoaHost, GTKHost
// and Win32Host — with one difference that shapes all of it: there is no
// engine to start and no event loop to run. The PAGE is the embedder
// (web/host/starling.js). It owns the canvas, the clock and the input
// devices, and it calls the functions exported at the bottom of this file;
// every one of them returns promptly, because a tab has one thread and
// blocking it freezes the page.
//
// So where the other hosts hand the engine a SwiftRuntimeCallbacks table,
// this one calls the SwiftRuntimeDelegate behind that table directly. The
// delegate is the same object either way.

import CSkwasm
import Flutter
import FlutterSwiftBridge
import FlutterSwiftBridgeCxx
import SwiftRuntime

public final class WebHost {
    /// The only one: a tab has one canvas. Created on first use, which may
    /// be the page delivering metrics before the app's `main` has run.
    nonisolated(unsafe) public static let shared = WebHost()

    let delegate = SwiftRuntimeDelegate()

    private var frameRequested = false
    /// A frame was asked for while the last one was still being rasterized.
    private var frameDeferred = false
    private var frameNumber: UInt64 = 0

    private var devicePixelRatio: Double = 1
    private var viewAdded = false

    private init() {
        WebPlatform.scheduleFrame = { [unowned self] in self.scheduleFrame() }
    }

    public func mountWidget(_ builder: () -> Widget) {
        runApp(builder())
        scheduleFrame()
    }

    // MARK: Frames

    func scheduleFrame() {
        if frameRequested { return }
        // One frame in flight. skwasm would queue a second, but the user
        // would only ever see the last, a frame late.
        if WebSurface.frameInFlight {
            frameDeferred = true
            return
        }
        frameRequested = true
        starling_host_request_frame()
    }

    func beginFrame(milliseconds: Double) {
        frameRequested = false
        frameNumber += 1
        delegate.beginFrame(Int64(milliseconds * 1000), frameNumber)
        delegate.drawFrame()
    }

    func framePresented() {
        WebSurface.framePresented()
        if frameDeferred {
            frameDeferred = false
            scheduleFrame()
        }
    }

    // MARK: Metrics

    /// `width` and `height` are CSS pixels, as the page measures them.
    func resize(width: Double, height: Double, ratio: Double) {
        devicePixelRatio = ratio
        WebView.devicePixelRatio = Float(ratio)
        let physicalWidth = (width * ratio).rounded()
        let physicalHeight = (height * ratio).rounded()
        // The implicit view, which an engine registers before its first
        // metrics; the canvas is view 0 on display 0.
        if !viewAdded {
            viewAdded = true
            delegate.addView(0, physicalWidth, physicalHeight, ratio, 0)
        }
        delegate.setViewportMetrics(
            0, physicalWidth, physicalHeight, ratio,
            0, 0, 0, 0,  // view padding
            0, 0, 0, 0,  // view insets
            0, 0, 0, 0,  // system gesture insets
            -1,  // touch slop: the framework's default
            0)
        scheduleFrame()
    }

    // MARK: Pointer

    // The framework expects the sequence an engine embedder produces — a
    // device is added before it hovers or goes down, and removed when it
    // leaves — where the DOM only reports what happened. This is the state
    // that fills the gap, per DOM pointerId.
    private struct Pointer {
        var down = false
        var x = 0.0, y = 0.0
        var identifier: Int64 = 0
    }
    private var pointers: [Int32: Pointer] = [:]
    private var nextPointerIdentifier: Int64 = 0

    enum PointerEvent: Int32 {
        case move = 0, down, up, leave, cancel
    }

    func pointer(
        _ event: PointerEvent, device: Int32, kind: PointerDeviceKind,
        x cssX: Double, y cssY: Double, buttons: Int32, milliseconds: Double
    ) {
        let x = cssX * devicePixelRatio
        let y = cssY * devicePixelRatio
        let time = Duration.microseconds(Int64(milliseconds * 1000))
        var packet: [PointerData] = []

        func emit(_ change: PointerChange, _ p: Pointer, dx: Double = 0, dy: Double = 0) {
            packet.append(
                PointerData(
                    timeStamp: time, change: change, kind: kind, device: Int64(device),
                    pointerIdentifier: p.identifier, physicalX: x, physicalY: y,
                    physicalDeltaX: dx, physicalDeltaY: dy,
                    buttons: Int64(buttons),
                    pressure: p.down ? 1 : 0, pressureMax: 1))
        }

        var p = pointers[device]
        if p == nil, event != .leave, event != .cancel {
            p = Pointer(x: x, y: y)
            emit(.add, p!)
        }
        guard var p else { return }

        switch event {
        case .move:
            emit(p.down ? .move : .hover, p, dx: x - p.x, dy: y - p.y)
        case .down:
            if !p.down {
                nextPointerIdentifier += 1
                p.identifier = nextPointerIdentifier
                p.down = true
                emit(.down, p)
            }
        case .up:
            if p.down {
                // `buttons` is already zero on the DOM's pointerup; the
                // framework reads the release from the change.
                emit(.up, p)
                p.down = false
            }
        case .leave, .cancel:
            if p.down {
                emit(.cancel, p)
                p.down = false
            }
            emit(.remove, p)
        }

        p.x = x
        p.y = y
        // A finger is gone once lifted; a mouse stays until it leaves.
        if event == .leave || event == .cancel {
            pointers[device] = nil
        } else if event == .up, kind == .touch {
            emit(.remove, p)
            pointers[device] = nil
        } else {
            pointers[device] = p
        }

        if !packet.isEmpty {
            delegate.dispatchPointerDataPacket(PointerDataPacket(data: packet))
        }
    }

    // MARK: Keys

    func key(
        type: Int32, physical: Int64, logical: Int64, character: String?, milliseconds: Double
    ) {
        let types: [KeyEventType] = [.down, .up, .repeat]
        guard types.indices.contains(Int(type)) else { return }
        delegate.dispatchKeyData(
            KeyData(
                timeStamp: milliseconds / 1000, type: types[Int(type)],
                physical: physical, logical: logical, character: character,
                synthesized: false))
    }

    func scroll(
        device: Int32, x cssX: Double, y cssY: Double, deltaX: Double, deltaY: Double,
        milliseconds: Double
    ) {
        let x = cssX * devicePixelRatio
        let y = cssY * devicePixelRatio
        var packet: [PointerData] = []
        let time = Duration.microseconds(Int64(milliseconds * 1000))
        if pointers[device] == nil {
            pointers[device] = Pointer(x: x, y: y)
            packet.append(
                PointerData(
                    timeStamp: time, change: .add, kind: .mouse, device: Int64(device),
                    physicalX: x, physicalY: y))
        }
        packet.append(
            PointerData(
                timeStamp: time, change: pointers[device]!.down ? .move : .hover,
                kind: .mouse, signalKind: .scroll, device: Int64(device),
                pointerIdentifier: pointers[device]!.identifier,
                physicalX: x, physicalY: y,
                scrollDeltaX: deltaX * devicePixelRatio,
                scrollDeltaY: deltaY * devicePixelRatio))
        delegate.dispatchPointerDataPacket(PointerDataPacket(data: packet))
    }
}

// MARK: - What the page calls

@_expose(wasm, "starling_resize")
@_cdecl("starling_resize")
func starlingResize(_ width: Double, _ height: Double, _ ratio: Double) {
    WebHost.shared.resize(width: width, height: height, ratio: ratio)
}

@_expose(wasm, "starling_begin_frame")
@_cdecl("starling_begin_frame")
func starlingBeginFrame(_ milliseconds: Double) {
    WebHost.shared.beginFrame(milliseconds: milliseconds)
}

@_expose(wasm, "starling_frame_presented")
@_cdecl("starling_frame_presented")
func starlingFramePresented() {
    WebHost.shared.framePresented()
}

/// `event` is WebHost.PointerEvent; `kind` is PointerDeviceKind's order
/// (0 touch, 1 mouse, 2 stylus); `buttons` is the DOM's bitmask, which is
/// also the framework's.
@_expose(wasm, "starling_pointer")
@_cdecl("starling_pointer")
func starlingPointer(
    _ event: Int32, _ device: Int32, _ kind: Int32, _ x: Double, _ y: Double,
    _ buttons: Int32, _ milliseconds: Double
) {
    guard let event = WebHost.PointerEvent(rawValue: event) else { return }
    let kinds: [PointerDeviceKind] = [.touch, .mouse, .stylus]
    WebHost.shared.pointer(
        event, device: device,
        kind: kinds.indices.contains(Int(kind)) ? kinds[Int(kind)] : .mouse,
        x: x, y: y, buttons: buttons, milliseconds: milliseconds)
}

/// `type` is 0 down, 1 up, 2 repeat; the ids are Flutter's physical and
/// logical key ids; `character` (UTF-8, in OUR memory) is what the key
/// types, empty when nothing.
@_expose(wasm, "starling_key")
@_cdecl("starling_key")
func starlingKey(
    _ type: Int32, _ physical: Int64, _ logical: Int64,
    _ character: UnsafePointer<UInt8>?, _ characterLength: Int32, _ milliseconds: Double
) {
    var text: String? = nil
    if let character, characterLength > 0 {
        text = String(
            decoding: UnsafeBufferPointer(start: character, count: Int(characterLength)),
            as: UTF8.self)
    }
    WebHost.shared.key(
        type: type, physical: physical, logical: logical, character: text,
        milliseconds: milliseconds)
}

@_expose(wasm, "starling_scroll")
@_cdecl("starling_scroll")
func starlingScroll(
    _ device: Int32, _ x: Double, _ y: Double, _ deltaX: Double, _ deltaY: Double,
    _ milliseconds: Double
) {
    WebHost.shared.scroll(
        device: device, x: x, y: y, deltaX: deltaX, deltaY: deltaY,
        milliseconds: milliseconds)
}

@_expose(wasm, "starling_timer_fired")
@_cdecl("starling_timer_fired")
func starlingTimerFired(_ id: Int32) {
    WebTimers.fire(id)
}

/// The page fetched a font and wrote it into an SkData in skwasm's memory.
/// `family` and `familyLength` name it (UTF-8, in OUR memory, from
/// starling_alloc); a length of 0 takes the name inside the font file.
@_expose(wasm, "starling_font_loaded")
@_cdecl("starling_font_loaded")
func starlingFontLoaded(_ data: sk_ptr, _ family: UnsafePointer<UInt8>?, _ familyLength: Int32)
    -> Int32
{
    let typeface = typeface_create(data)
    skData_dispose(data)
    guard typeface != 0 else { return 0 }
    var name: sk_ptr = 0
    if let family, familyLength > 0 {
        name = makeSkString(
            String(decoding: UnsafeBufferPointer(start: family, count: Int(familyLength)),
                   as: UTF8.self))
    }
    fontCollection_registerTypeface(WebFonts.collection, typeface, name)
    if name != 0 { skString_free(name) }
    return 1
}

/// Scratch memory in our heap for the page to write arguments into.
@_expose(wasm, "starling_alloc")
@_cdecl("starling_alloc")
func starlingAlloc(_ byteCount: Int32) -> UnsafeMutableRawPointer? {
    UnsafeMutableRawPointer.allocate(byteCount: Int(max(byteCount, 1)), alignment: 8)
}

@_expose(wasm, "starling_free")
@_cdecl("starling_free")
func starlingFree(_ pointer: UnsafeMutableRawPointer?) {
    pointer?.deallocate()
}
