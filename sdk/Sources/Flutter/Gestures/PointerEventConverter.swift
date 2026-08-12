// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge

/// Callback to get the device pixel ratio for a given view.
///
/// Returns `nil` if the view with the given `viewId` does not exist.
///
/// **Dart Source:** `packages/flutter/lib/src/gestures/converter.dart:47`
/// **Original:** `typedef DevicePixelRatioGetter = double? Function(int viewId);`
public typealias DevicePixelRatioGetter = (_ viewId: Int) -> Double?

// MARK: - Private Helper

/// Ensures that down/move events always have at least `kPrimaryButton` set
/// for device kinds where a zero-buttons value is invalid.
///
/// For mouse and trackpad, the raw button value is passed through unchanged.
/// For touch, stylus, invertedStylus, and unknown, if `buttons` is 0 it is
/// replaced with `kPrimaryButton`.
///
/// **Dart Source:** `packages/flutter/lib/src/gestures/converter.dart:21-35`
private func synthesiseDownButtons(_ buttons: Int, _ kind: PointerDeviceKind) -> Int {
    switch kind {
    case .mouse, .trackpad:
        return buttons
    case .touch, .stylus, .invertedStylus, .unknown:
        return buttons == 0 ? kPrimaryButton : buttons
    }
}

// MARK: - PointerEventConverter

/// Converts `PointerData` objects from the engine into framework
/// `PointerEvent` objects.
///
/// This is an uninhabited enum (caseless) used as a namespace for static
/// conversion methods, matching the Dart `abstract final class` pattern.
///
/// **Dart Source:** `packages/flutter/lib/src/gestures/converter.dart:54-323`
/// **Original Name:** `PointerEventConverter`
///
/// DIFFERENCE FROM DART: Uses a caseless Swift `enum` instead of
/// `abstract final class`. REASON: Swift enums with no cases cannot be
/// instantiated, which mirrors the Dart pattern of a non-instantiable
/// utility class.
public enum PointerEventConverter {

    // MARK: - Private Helpers

    /// Last cumulative pan of each pan/zoom gesture, by device.
    ///
    /// The embedder API carries only the CUMULATIVE pan (`pan_x`/`pan_y`) —
    /// there is no delta field on the wire — so the per-event delta has to be
    /// remembered here, exactly as Dart's converter does with its
    /// `PointerState`. Reading a `panDelta` off the datum yields zero for
    /// every event, which is a touchpad that reports its whole gesture and
    /// still scrolls nothing.
    private nonisolated(unsafe) static var _lastPan: [Int: Offset] = [:]

    /// Converts a physical-pixel measurement to logical pixels.
    ///
    /// **Dart Source:** `converter.dart:320-321`
    private static func toLogicalPixels(
        _ physicalPixels: Double,
        _ devicePixelRatio: Double
    ) -> Double {
        physicalPixels / devicePixelRatio
    }

    // MARK: - Public API

    /// Expands a sequence of `PointerData` from the engine into framework
    /// `PointerEvent` instances.
    ///
    /// The `devicePixelRatioForView` callback is used to convert physical
    /// coordinates into logical coordinates for each view. If the callback
    /// returns `nil` for a given `viewId`, that datum is silently dropped.
    ///
    /// Unknown signal kinds are filtered out before conversion.
    ///
    /// **Dart Source:** `converter.dart:62-318`
    /// **Original:** `static Iterable<PointerEvent> expand(Iterable<ui.PointerData> data, DevicePixelRatioGetter devicePixelRatioForView)`
    public static func expand(
        _ data: some Sequence<PointerData>,
        devicePixelRatioForView: @escaping DevicePixelRatioGetter
    ) -> [PointerEvent] {
        return data.compactMap { datum -> PointerEvent? in
            // Filter out unknown signal kinds (matches Dart's .where filter).
            let signalKind = datum.signalKind ?? .none
            if signalKind == .unknown {
                return nil
            }

            // Look up pixel ratio; drop datum if view doesn't exist.
            guard let devicePixelRatio = devicePixelRatioForView(Int(datum.viewId)) else {
                return nil
            }

            // Convert physical coordinates to logical coordinates.
            let position = Offset(
                Double(datum.physicalX) / devicePixelRatio,
                Double(datum.physicalY) / devicePixelRatio
            )
            let delta = Offset(
                Double(datum.physicalDeltaX) / devicePixelRatio,
                Double(datum.physicalDeltaY) / devicePixelRatio
            )
            let radiusMinor = toLogicalPixels(datum.radiusMinor, devicePixelRatio)
            let radiusMajor = toLogicalPixels(datum.radiusMajor, devicePixelRatio)
            let radiusMin = toLogicalPixels(datum.radiusMin, devicePixelRatio)
            let radiusMax = toLogicalPixels(datum.radiusMax, devicePixelRatio)
            let timeStamp = datum.timeStamp
            let kind = datum.kind

            // Convenience Int conversions from PointerData's Int64 fields.
            let viewId = Int(datum.viewId)
            let device = Int(datum.device)
            let pointer = Int(datum.pointerIdentifier)
            let buttons = Int(datum.buttons)
            let embedderId = Int(datum.embedderId)
            let platformData = Int(datum.platformData)

            switch signalKind {
            case .none:
                switch datum.change {
                case .add:
                    return PointerAddedEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        kind: kind,
                        device: device,
                        position: position,
                        obscured: datum.obscured,
                        pressureMin: datum.pressureMin,
                        pressureMax: datum.pressureMax,
                        distance: datum.distance,
                        distanceMax: datum.distanceMax,
                        radiusMin: radiusMin,
                        radiusMax: radiusMax,
                        orientation: datum.orientation,
                        tilt: datum.tilt,
                        embedderId: embedderId
                    )

                case .hover:
                    return PointerHoverEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        kind: kind,
                        device: device,
                        position: position,
                        delta: delta,
                        buttons: buttons,
                        obscured: datum.obscured,
                        pressureMin: datum.pressureMin,
                        pressureMax: datum.pressureMax,
                        distance: datum.distance,
                        distanceMax: datum.distanceMax,
                        size: datum.size,
                        radiusMajor: radiusMajor,
                        radiusMinor: radiusMinor,
                        radiusMin: radiusMin,
                        radiusMax: radiusMax,
                        orientation: datum.orientation,
                        tilt: datum.tilt,
                        synthesized: datum.synthesized,
                        embedderId: embedderId
                    )

                case .down:
                    return PointerDownEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        pointer: pointer,
                        kind: kind,
                        device: device,
                        position: position,
                        buttons: synthesiseDownButtons(buttons, kind),
                        obscured: datum.obscured,
                        pressure: datum.pressure,
                        pressureMin: datum.pressureMin,
                        pressureMax: datum.pressureMax,
                        distanceMax: datum.distanceMax,
                        size: datum.size,
                        radiusMajor: radiusMajor,
                        radiusMinor: radiusMinor,
                        radiusMin: radiusMin,
                        radiusMax: radiusMax,
                        orientation: datum.orientation,
                        tilt: datum.tilt,
                        embedderId: embedderId
                    )

                case .move:
                    return PointerMoveEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        pointer: pointer,
                        kind: kind,
                        device: device,
                        position: position,
                        delta: delta,
                        buttons: synthesiseDownButtons(buttons, kind),
                        obscured: datum.obscured,
                        pressure: datum.pressure,
                        pressureMin: datum.pressureMin,
                        pressureMax: datum.pressureMax,
                        distanceMax: datum.distanceMax,
                        size: datum.size,
                        radiusMajor: radiusMajor,
                        radiusMinor: radiusMinor,
                        radiusMin: radiusMin,
                        radiusMax: radiusMax,
                        orientation: datum.orientation,
                        tilt: datum.tilt,
                        platformData: platformData,
                        synthesized: datum.synthesized,
                        embedderId: embedderId
                    )

                case .up:
                    return PointerUpEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        pointer: pointer,
                        kind: kind,
                        device: device,
                        position: position,
                        buttons: buttons,
                        obscured: datum.obscured,
                        pressure: datum.pressure,
                        pressureMin: datum.pressureMin,
                        pressureMax: datum.pressureMax,
                        distance: datum.distance,
                        distanceMax: datum.distanceMax,
                        size: datum.size,
                        radiusMajor: radiusMajor,
                        radiusMinor: radiusMinor,
                        radiusMin: radiusMin,
                        radiusMax: radiusMax,
                        orientation: datum.orientation,
                        tilt: datum.tilt,
                        embedderId: embedderId
                    )

                case .cancel:
                    return PointerCancelEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        pointer: pointer,
                        kind: kind,
                        device: device,
                        position: position,
                        buttons: buttons,
                        obscured: datum.obscured,
                        pressureMin: datum.pressureMin,
                        pressureMax: datum.pressureMax,
                        distance: datum.distance,
                        distanceMax: datum.distanceMax,
                        size: datum.size,
                        radiusMajor: radiusMajor,
                        radiusMinor: radiusMinor,
                        radiusMin: radiusMin,
                        radiusMax: radiusMax,
                        orientation: datum.orientation,
                        tilt: datum.tilt,
                        embedderId: embedderId
                    )

                case .remove:
                    return PointerRemovedEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        kind: kind,
                        device: device,
                        position: position,
                        obscured: datum.obscured,
                        pressureMin: datum.pressureMin,
                        pressureMax: datum.pressureMax,
                        distanceMax: datum.distanceMax,
                        radiusMin: radiusMin,
                        radiusMax: radiusMax,
                        embedderId: embedderId
                    )

                case .panZoomStart:
                    _lastPan[device] = Offset.zero
                    return PointerPanZoomStartEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        device: device,
                        pointer: pointer,
                        position: position,
                        embedderId: embedderId,
                        synthesized: datum.synthesized
                    )

                case .panZoomUpdate:
                    let pan = Offset(
                        datum.panX / devicePixelRatio,
                        datum.panY / devicePixelRatio
                    )
                    let lastPan = _lastPan[device] ?? Offset.zero
                    let panDelta = Offset(pan.dx - lastPan.dx, pan.dy - lastPan.dy)
                    _lastPan[device] = pan
                    return PointerPanZoomUpdateEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        device: device,
                        pointer: pointer,
                        position: position,
                        embedderId: embedderId,
                        pan: pan,
                        panDelta: panDelta,
                        scale: datum.scale,
                        rotation: datum.rotation,
                        synthesized: datum.synthesized
                    )

                case .panZoomEnd:
                    _lastPan.removeValue(forKey: device)
                    return PointerPanZoomEndEvent(
                        viewId: viewId,
                        timeStamp: timeStamp,
                        device: device,
                        pointer: pointer,
                        position: position,
                        embedderId: embedderId,
                        synthesized: datum.synthesized
                    )
                }

            case .scroll:
                // Guard against non-finite scroll deltas and invalid pixel ratios.
                guard datum.scrollDeltaX.isFinite,
                      datum.scrollDeltaY.isFinite,
                      devicePixelRatio > 0 else {
                    return nil
                }
                let scrollDelta = Offset(
                    datum.scrollDeltaX / devicePixelRatio,
                    datum.scrollDeltaY / devicePixelRatio
                )
                return PointerScrollEvent(
                    viewId: viewId,
                    timeStamp: timeStamp,
                    kind: kind,
                    device: device,
                    position: position,
                    scrollDelta: scrollDelta,
                    embedderId: embedderId,
                    onRespond: datum.respond
                )

            case .scrollInertiaCancel:
                return PointerScrollInertiaCancelEvent(
                    viewId: viewId,
                    timeStamp: timeStamp,
                    kind: kind,
                    device: device,
                    position: position,
                    embedderId: embedderId
                )

            case .scale:
                return PointerScaleEvent(
                    viewId: viewId,
                    timeStamp: timeStamp,
                    kind: kind,
                    device: device,
                    position: position,
                    embedderId: embedderId,
                    scale: datum.scale
                )

            case .unknown:
                // Already filtered above; this is unreachable.
                fatalError("Unreachable: unknown signal kinds are filtered before this switch.")
            }
        }
    }
}
