// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Creates a `SwiftRuntimeCallbacks` C struct that bridges the engine's
/// callback-based interface to the Swift `SwiftRuntimeDelegate`.
///
/// Each function pointer in the struct captures an `Unmanaged` reference to
/// a `SwiftRuntimeDelegate` instance via the opaque `context` pointer.
/// The delegate is retained for the lifetime of the callbacks.

import FlutterSwiftBridge
import Foundation

// Helper to extract the delegate from the opaque context pointer.
@inline(__always)
private func delegate(from ctx: UnsafeMutableRawPointer?) -> SwiftRuntimeDelegate {
    Unmanaged<SwiftRuntimeDelegate>.fromOpaque(ctx!).takeUnretainedValue()
}

/// Creates a fully-populated `SwiftRuntimeCallbacks` struct backed by a
/// new `SwiftRuntimeDelegate` instance. The delegate is retained via
/// `Unmanaged.passRetained` — the caller must eventually release it
/// (or the process lifetime manages it).
public func createRuntimeCallbacks() -> SwiftRuntimeCallbacks {
    let d = SwiftRuntimeDelegate()
    let ctx = Unmanaged.passRetained(d).toOpaque()

    var cb = SwiftRuntimeCallbacks()
    cb.context = ctx

    // -- Frame scheduling -------------------------------------------------

    cb.begin_frame = {
        (ctx: UnsafeMutableRawPointer?, frameTimeMicros: Int64, frameNumber: UInt64) in
        delegate(from: ctx).beginFrame(frameTimeMicros, frameNumber)
    }

    cb.draw_frame = {
        (ctx: UnsafeMutableRawPointer?) in
        delegate(from: ctx).drawFrame()
    }

    cb.report_timings = {
        (ctx: UnsafeMutableRawPointer?, timingsPtr: UnsafePointer<Int64>?, count: Int) in
        guard let timingsPtr = timingsPtr else { return }
        let buffer = UnsafeBufferPointer(start: timingsPtr, count: count)
        delegate(from: ctx).reportTimings(buffer.map { Int($0) })
    }

    // -- View management --------------------------------------------------

    cb.add_view = {
        (ctx: UnsafeMutableRawPointer?,
         viewId: Int64, width: Double, height: Double,
         pixelRatio: Double, displayId: Int64) in
        delegate(from: ctx).addView(viewId, width, height, pixelRatio, displayId)
    }

    cb.remove_view = {
        (ctx: UnsafeMutableRawPointer?, viewId: Int64) in
        delegate(from: ctx).removeView(viewId)
    }

    cb.send_view_focus_event = {
        (ctx: UnsafeMutableRawPointer?, viewId: Int64, state: Int32, direction: Int32) in
        delegate(from: ctx).sendViewFocusEvent(viewId, state, direction)
    }

    cb.set_viewport_metrics = {
        (ctx: UnsafeMutableRawPointer?,
         viewId: Int64, width: Double, height: Double, pixelRatio: Double,
         padTop: Double, padRight: Double, padBottom: Double, padLeft: Double,
         insetTop: Double, insetRight: Double, insetBottom: Double, insetLeft: Double,
         gestureTop: Double, gestureRight: Double, gestureBottom: Double, gestureLeft: Double,
         touchSlop: Double, displayId: Int64) in
        delegate(from: ctx).setViewportMetrics(
            viewId, width, height, pixelRatio,
            padTop, padRight, padBottom, padLeft,
            insetTop, insetRight, insetBottom, insetLeft,
            gestureTop, gestureRight, gestureBottom, gestureLeft,
            touchSlop, displayId
        )
    }

    cb.set_displays = {
        (ctx: UnsafeMutableRawPointer?, displayData: UnsafePointer<Double>?, count: Int) in
        guard let displayData = displayData else { return }
        let buffer = UnsafeBufferPointer(start: displayData, count: count)
        delegate(from: ctx).updateDisplays(Array(buffer))
    }

    // -- Input ------------------------------------------------------------

    cb.dispatch_pointer_data_packet = {
        (ctx: UnsafeMutableRawPointer?, data: UnsafePointer<UInt8>?, dataLen: Int) in
        guard let data = data, dataLen > 0 else { return }

        // Each C++ PointerData is 36 fields × 8 bytes = 288 bytes.
        let kBytesPerField = 8
        let kFieldCount = 36
        let kPointerDataSize = kBytesPerField * kFieldCount
        let count = dataLen / kPointerDataSize
        guard count > 0 else { return }

        var pointerDataList: [PointerData] = []
        pointerDataList.reserveCapacity(count)

        for i in 0..<count {
            let base = data.advanced(by: i * kPointerDataSize)

            func readInt64(_ field: Int) -> Int64 {
                base.advanced(by: field * 8)
                    .withMemoryRebound(to: Int64.self, capacity: 1) { $0.pointee }
            }
            func readDouble(_ field: Int) -> Double {
                base.advanced(by: field * 8)
                    .withMemoryRebound(to: Double.self, capacity: 1) { $0.pointee }
            }

            // C++ field order: embedder_id(0), time_stamp(1), change(2), kind(3),
            // signal_kind(4), device(5), pointer_identifier(6), physical_x(7),
            // physical_y(8), physical_delta_x(9), physical_delta_y(10), buttons(11),
            // obscured(12), synthesized(13), pressure(14)..tilt(25),
            // platformData(26), scroll_delta_x(27)..rotation(34), view_id(35)

            let change: PointerChange
            switch readInt64(2) {
            case 0: change = .cancel
            case 1: change = .add
            case 2: change = .remove
            case 3: change = .hover
            case 4: change = .down
            case 5: change = .move
            case 6: change = .up
            case 7: change = .panZoomStart
            case 8: change = .panZoomUpdate
            case 9: change = .panZoomEnd
            default: change = .cancel
            }

            let kind: PointerDeviceKind
            switch readInt64(3) {
            case 0: kind = .touch
            case 1: kind = .mouse
            case 2: kind = .stylus
            case 3: kind = .invertedStylus
            case 4: kind = .trackpad
            default: kind = .touch
            }

            let signalKind: PointerSignalKind?
            switch readInt64(4) {
            case 0: signalKind = nil       // kNone
            case 1: signalKind = .scroll
            case 2: signalKind = .scrollInertiaCancel
            case 3: signalKind = .scale
            default: signalKind = nil
            }

            pointerDataList.append(PointerData(
                viewId: readInt64(35),
                embedderId: readInt64(0),
                timeStamp: .microseconds(readInt64(1)),
                change: change,
                kind: kind,
                signalKind: signalKind,
                device: readInt64(5),
                pointerIdentifier: readInt64(6),
                physicalX: readDouble(7),
                physicalY: readDouble(8),
                physicalDeltaX: readDouble(9),
                physicalDeltaY: readDouble(10),
                buttons: readInt64(11),
                obscured: readInt64(12) != 0,
                synthesized: readInt64(13) != 0,
                pressure: readDouble(14),
                pressureMin: readDouble(15),
                pressureMax: readDouble(16),
                distance: readDouble(17),
                distanceMax: readDouble(18),
                size: readDouble(19),
                radiusMajor: readDouble(20),
                radiusMinor: readDouble(21),
                radiusMin: readDouble(22),
                radiusMax: readDouble(23),
                orientation: readDouble(24),
                tilt: readDouble(25),
                platformData: readInt64(26),
                scrollDeltaX: readDouble(27),
                scrollDeltaY: readDouble(28),
                panX: readDouble(29),
                panY: readDouble(30),
                panDeltaX: readDouble(31),
                panDeltaY: readDouble(32),
                scale: readDouble(33),
                rotation: readDouble(34)
            ))
        }

        let packet = PointerDataPacket(data: pointerDataList)
        delegate(from: ctx).dispatchPointerDataPacket(packet)
    }

    cb.dispatch_key_data = {
        (ctx: UnsafeMutableRawPointer?, data: UnsafePointer<UInt8>?, dataLen: Int) in
        guard let data = data, dataLen > 0 else { return }
        let keyData = Data(bytes: data, count: dataLen)
        delegate(from: ctx).dispatchKeyData(keyData)
    }

    cb.dispatch_semantics_action = {
        (ctx: UnsafeMutableRawPointer?,
         viewId: Int32, nodeId: Int32, action: Int32,
         args: UnsafePointer<UInt8>?, argsLen: Int) in
        var argsArray: [UInt8] = []
        if let args = args, argsLen > 0 {
            let buffer = UnsafeBufferPointer(start: args, count: argsLen)
            argsArray = Array(buffer)
        }
        delegate(from: ctx).dispatchSemanticsAction(viewId, nodeId, action, argsArray)
    }

    // -- Configuration ----------------------------------------------------

    cb.set_semantics_enabled = {
        (ctx: UnsafeMutableRawPointer?, enabled: Bool) in
        delegate(from: ctx).setSemanticsEnabled(enabled)
    }

    cb.set_accessibility_features = {
        (ctx: UnsafeMutableRawPointer?, flags: Int32) in
        delegate(from: ctx).updateAccessibilityFeatures(flags)
    }

    cb.set_locales = {
        (ctx: UnsafeMutableRawPointer?,
         localeData: UnsafeMutablePointer<UnsafePointer<CChar>?>?, count: Int) in
        guard let localeData = localeData else { return }
        var locales: [String] = []
        locales.reserveCapacity(count)
        for i in 0..<count {
            if let cStr = localeData[i] {
                locales.append(String(cString: cStr))
            } else {
                locales.append("")
            }
        }
        delegate(from: ctx).updateLocales(locales)
    }

    cb.set_user_settings_data = {
        (ctx: UnsafeMutableRawPointer?, data: UnsafePointer<CChar>?) in
        guard let data = data else { return }
        delegate(from: ctx).updateUserSettingsData(String(cString: data))
    }

    cb.set_initial_lifecycle_state = {
        (ctx: UnsafeMutableRawPointer?, data: UnsafePointer<CChar>?) in
        guard let data = data else { return }
        delegate(from: ctx).updateInitialLifecycleState(String(cString: data))
    }

    // -- Platform messages ------------------------------------------------

    cb.dispatch_platform_message = {
        (ctx: UnsafeMutableRawPointer?,
         channel: UnsafePointer<CChar>?,
         data: UnsafePointer<UInt8>?,
         dataLen: Int,
         responseId: Int32) in
        guard let channel = channel else { return }
        let channelStr = String(cString: channel)
        var dataArray: [UInt8] = []
        if let data = data, dataLen > 0 {
            let buffer = UnsafeBufferPointer(start: data, count: dataLen)
            dataArray = Array(buffer)
        }
        delegate(from: ctx).dispatchPlatformMessage(channelStr, dataArray, responseId)
    }

    cb.platform_message_sender_ready = {
        (ctx: UnsafeMutableRawPointer?, sender: UnsafeMutableRawPointer?,
         send: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<UInt8>?, Int, Int32) -> Void)?) in
        guard let sender, let send else { return }
        delegate(from: ctx).installPlatformMessageSender(sender, send)
    }

    cb.platform_message_response = {
        (ctx: UnsafeMutableRawPointer?, responseId: Int32, data: UnsafePointer<UInt8>?, dataLen: Int) in
        var bytes: Data? = nil
        if let data, dataLen > 0 { bytes = Data(UnsafeBufferPointer(start: data, count: dataLen)) }
        delegate(from: ctx).completePlatformMessage(responseId, bytes)
    }

    return cb
}
