// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// SwiftRuntimeDelegate — The receiver for all Shell-to-Framework calls.
///
/// This Swift class replaces `PlatformConfiguration` + `hooks.dart` from the Dart-based
/// Flutter engine. It receives method calls from the C++ `SwiftRuntimeController` and
/// routes them to `PlatformDispatcher.instance`.
///
/// **How it works with C++ interop:**
/// - The Swift compiler auto-generates a C++ header (`<SwiftRuntime-Swift.h>`)
/// - C++ `SwiftRuntimeController` constructs this via `SwiftRuntime::SwiftRuntimeDelegate::init()`
/// - C++ calls methods directly — zero overhead, no callback registration
/// - ARC manages the Swift object's lifetime automatically
///
/// **Important design constraints:**
/// - NO `import Foundation` — pure Swift types only (critical for GN build integration)
/// - Method signatures use simple C++-bridgeable types: Int64, UInt64, Double, Bool, String, Int32
/// - `public private(set) var` pattern for Bool state avoids C++ setter name clashes
///
/// **Dart Source:** Replaces `engine/src/flutter/lib/ui/hooks.dart`
/// **See also:** `plans/shell_without_dart_exploration.md` Section 4.2, Section 5.1

import FlutterSwiftBridge
import Foundation

// MARK: - SwiftRuntimeDelegate

public class SwiftRuntimeDelegate: @unchecked Sendable {

  /// Reference to the PlatformDispatcher singleton.
  /// All Shell-to-Framework calls are routed through this.
  private let platformDispatcher = PlatformDispatcher.instance

  /// Whether semantics are currently enabled.
  ///
  /// Uses `public private(set) var` with `is` prefix to generate a C++ getter
  /// `isSemanticsEnabled()` without an auto-generated setter that would clash
  /// with the `setSemanticsEnabled(_:)` method.
  /// See exploration doc Section 10.3, gotcha #5.
  public private(set) var isSemanticsEnabled: Bool = false

  /// Public parameterless initializer for C++ construction.
  ///
  /// C++ constructs this via the auto-generated `SwiftRuntime::SwiftRuntimeDelegate::init()`.
  public init() {}

  // MARK: - Frame Scheduling

  /// Called by the engine at the start of a frame.
  ///
  /// **Replaces:** `hooks.dart` `_beginFrame(int microseconds)`
  /// **C++ caller:** `SwiftRuntimeController::BeginFrame`
  ///
  /// - Parameters:
  ///   - microseconds: The frame time in microseconds since some epoch.
  ///   - frameNumber: The monotonically increasing frame number.
  public func beginFrame(_ microseconds: Int64, _ frameNumber: UInt64) {
    platformDispatcher._updateFrameData(Int(frameNumber))
    platformDispatcher._beginFrame(Int(microseconds))
  }

  /// Called by the engine after `beginFrame` and microtasks are drained.
  ///
  /// **Replaces:** `hooks.dart` `_drawFrame()`
  /// **C++ caller:** `SwiftRuntimeController::BeginFrame` (after beginFrame)
  public func drawFrame() {
    platformDispatcher._drawFrame()
  }

  /// Called by the engine to report frame timing data.
  ///
  /// **Replaces:** `hooks.dart` `_reportTimings(List<int> timings)`
  /// **C++ caller:** `SwiftRuntimeController::ReportTimings`
  ///
  /// - Parameter timings: Raw timing data as a flat array of integers.
  ///   Each frame's data consists of `FramePhase.count + FrameTimingInfo.count` entries.
  public func reportTimings(_ timings: [Int]) {
    platformDispatcher._reportTimings(timings)
  }

  // MARK: - Pointer Input

  /// Called by the engine to dispatch pointer data.
  ///
  /// **Replaces:** `hooks.dart` `_dispatchPointerDataPacket(ByteData packet)`
  /// **C++ caller:** `SwiftRuntimeController::DispatchPointerDataPacket`
  ///
  /// The C++ side constructs PointerData from the engine's PointerDataPacket
  /// and passes individual fields. For the initial implementation, this accepts
  /// a pre-constructed PointerDataPacket from the bridge layer.
  ///
  /// - Parameter packet: The pointer data packet containing pointer events.
  public func dispatchPointerDataPacket(_ packet: PointerDataPacket) {
    if ProcessInfo.processInfo.environment["FLUTTER_SWIFT_DEBUG_POINTER"] != nil,
       let first = packet.data.first {
      FileHandle.standardError.write(Data(
        "[SwiftRuntimeDelegate] pointer packet n=\(packet.data.count) change=\(first.change) x=\(first.physicalX) y=\(first.physicalY) view=\(first.viewId) handler=\(platformDispatcher.onPointerDataPacket != nil)\n".utf8))
    }
    platformDispatcher.onPointerDataPacket?(packet)
  }

  /// Called by the engine to dispatch key data directly (bypassing channelBuffers).
  ///
  /// **C++ caller:** `SwiftRuntimeController::DispatchPlatformMessage` (intercepts "flutter/keydata")
  ///
  /// Uses the same binary packet format as the flutter/keydata channel.
  /// Calls pd.onKeyData directly, same pattern as dispatchPointerDataPacket.
  public func dispatchKeyData(_ data: Data) {
    platformDispatcher.onKeyData?(KeyData.fromPacket(data))
  }

  // MARK: - Platform Messages

  /// Called by the engine to dispatch a platform channel message.
  ///
  /// **Replaces:** `hooks.dart` `_dispatchPlatformMessage(String name, ByteData? data, int responseId)`
  /// **C++ caller:** `SwiftRuntimeController::DispatchPlatformMessage`
  ///
  /// Routes the message through ChannelBuffers for proper buffering and dispatch.
  ///
  /// - Parameters:
  ///   - name: The platform channel name.
  ///   - data: The message data (may be empty).
  ///   - responseId: An opaque identifier for sending the response back to the engine.
  // MARK: - Outbound platform messages

  public typealias PlatformMessageSend =
    @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<UInt8>?, Int, Int32) -> Void

  private var _sender: UnsafeMutableRawPointer? = nil
  private var _send: PlatformMessageSend? = nil
  private var _pending: [Int32: PlatformMessageResponseCallback] = [:]
  private var _nextResponseId: Int32 = 1

  /// The engine owns the runtime now: the framework's
  /// `sendPlatformMessage` goes through `send` from here on.
  public func installPlatformMessageSender(_ sender: UnsafeMutableRawPointer, _ send: @escaping PlatformMessageSend) {
    _sender = sender
    _send = send
    platformDispatcher.platformMessageSender = { [weak self] name, data, callback in
      guard let self, let send = self._send else { callback?(nil); return }
      var id: Int32 = 0
      if let callback {
        id = self._nextResponseId
        self._nextResponseId &+= 1
        if self._nextResponseId == 0 { self._nextResponseId = 1 }
        self._pending[id] = callback
      }
      let bytes = data.map { [UInt8]($0) } ?? []
      name.withCString { channel in
        bytes.withUnsafeBufferPointer { buffer in
          send(self._sender, channel, buffer.baseAddress, buffer.count, id)
        }
      }
    }
  }

  /// The platform's reply to a message the framework sent.
  public func completePlatformMessage(_ responseId: Int32, _ data: Data?) {
    guard let callback = _pending.removeValue(forKey: responseId) else { return }
    callback(data)
  }

  public func dispatchPlatformMessage(_ name: String, _ data: [UInt8], _ responseId: Int32) {
    let messageData: Data? = data.isEmpty ? nil : Data(data)
    // Platform messages are dispatched on the engine's UI task runner,
    // which is the main thread on macOS. Use assumeIsolated to satisfy
    // @MainActor isolation requirement of channelBuffers.
    // Note: On Linux DRM, "flutter/keydata" is intercepted at the C++ level
    // and dispatched via dispatch_key_data callback, so it never reaches here.
    MainActor.assumeIsolated {
      channelBuffers.push(name, messageData) { _ in
        // Response callback — the C++ side auto-completes responses for now,
        // so this is a no-op. When full response support is wired up,
        // this will call back into C++ with the responseId and response data.
      }
    }
  }

  // MARK: - Semantics

  /// Called by the engine to dispatch a semantics action.
  ///
  /// **Replaces:** `hooks.dart` `_dispatchSemanticsAction(int viewId, int nodeId, int action, ByteData? args)`
  /// **C++ caller:** `SwiftRuntimeController::DispatchSemanticsAction`
  ///
  /// - Parameters:
  ///   - viewId: The view containing the semantics node.
  ///   - nodeId: The semantics node ID.
  ///   - action: The semantics action index (maps to SemanticsAction).
  ///   - args: Optional arguments data for the action.
  public func dispatchSemanticsAction(_ viewId: Int32, _ nodeId: Int32, _ action: Int32, _ args: [UInt8]) {
    // Uses the [UInt8] overload on PlatformDispatcher to avoid Foundation Data dependency.
    // Empty args array is treated as nil arguments by PlatformDispatcher.
    platformDispatcher._dispatchSemanticsAction(
      Int(viewId), Int(nodeId), Int(action), args
    )
  }

  /// Called by the engine to enable or disable semantics.
  ///
  /// **Replaces:** `hooks.dart` `_updateSemanticsEnabled(bool enabled)`
  /// **C++ caller:** `SwiftRuntimeController::SetSemanticsEnabled`
  ///
  /// - Parameter enabled: Whether semantics should be enabled.
  public func setSemanticsEnabled(_ enabled: Bool) {
    isSemanticsEnabled = enabled
    platformDispatcher._updateSemanticsEnabled(enabled)
  }

  /// Called by the engine to update accessibility feature flags.
  ///
  /// **Replaces:** `hooks.dart` `_updateAccessibilityFeatures(int values)`
  /// **C++ caller:** `SwiftRuntimeController::SetAccessibilityFeatures`
  ///
  /// - Parameter flags: Bitmask of accessibility features (see AccessibilityFeatures).
  public func updateAccessibilityFeatures(_ flags: Int32) {
    platformDispatcher._updateAccessibilityFeatures(Int(flags))
  }

  // MARK: - View Management

  /// Called by the engine to set viewport metrics for a view.
  ///
  /// **Replaces:** `hooks.dart` `_updateWindowMetrics(...)`
  /// **C++ caller:** `SwiftRuntimeController::SetViewportMetrics`
  ///
  /// Constructs a ViewConfiguration from the raw metric values and updates
  /// the PlatformDispatcher's view state.
  ///
  /// - Parameters:
  ///   - viewId: The view to update.
  ///   - width: Physical width in pixels.
  ///   - height: Physical height in pixels.
  ///   - dpr: Device pixel ratio.
  ///   - viewPaddingTop: Top view padding in physical pixels.
  ///   - viewPaddingRight: Right view padding in physical pixels.
  ///   - viewPaddingBottom: Bottom view padding in physical pixels.
  ///   - viewPaddingLeft: Left view padding in physical pixels.
  ///   - viewInsetTop: Top view inset in physical pixels.
  ///   - viewInsetRight: Right view inset in physical pixels.
  ///   - viewInsetBottom: Bottom view inset in physical pixels.
  ///   - viewInsetLeft: Left view inset in physical pixels.
  ///   - systemGestureInsetTop: Top system gesture inset in physical pixels.
  ///   - systemGestureInsetRight: Right system gesture inset in physical pixels.
  ///   - systemGestureInsetBottom: Bottom system gesture inset in physical pixels.
  ///   - systemGestureInsetLeft: Left system gesture inset in physical pixels.
  ///   - physicalTouchSlop: Touch slop in physical pixels (-1 for unset).
  ///   - displayId: The display this view is on.
  public func setViewportMetrics(
    _ viewId: Int64,
    _ width: Double,
    _ height: Double,
    _ dpr: Double,
    _ viewPaddingTop: Double,
    _ viewPaddingRight: Double,
    _ viewPaddingBottom: Double,
    _ viewPaddingLeft: Double,
    _ viewInsetTop: Double,
    _ viewInsetRight: Double,
    _ viewInsetBottom: Double,
    _ viewInsetLeft: Double,
    _ systemGestureInsetTop: Double,
    _ systemGestureInsetRight: Double,
    _ systemGestureInsetBottom: Double,
    _ systemGestureInsetLeft: Double,
    _ physicalTouchSlop: Double,
    _ displayId: Int64
  ) {
    let touchSlop: Double? = physicalTouchSlop < 0 ? nil : physicalTouchSlop
    let physicalSize = Size(width, height)
    let viewConfig = ViewConfiguration(
      devicePixelRatio: dpr,
      size: physicalSize,
      viewInsets: ViewPadding(
        left: viewInsetLeft, top: viewInsetTop,
        right: viewInsetRight, bottom: viewInsetBottom
      ),
      viewPadding: ViewPadding(
        left: viewPaddingLeft, top: viewPaddingTop,
        right: viewPaddingRight, bottom: viewPaddingBottom
      ),
      systemGestureInsets: ViewPadding(
        left: systemGestureInsetLeft, top: systemGestureInsetTop,
        right: systemGestureInsetRight, bottom: systemGestureInsetBottom
      ),
      padding: ViewPadding(
        left: max(0.0, viewPaddingLeft - viewInsetLeft),
        top: max(0.0, viewPaddingTop - viewInsetTop),
        right: max(0.0, viewPaddingRight - viewInsetRight),
        bottom: max(0.0, viewPaddingBottom - viewInsetBottom)
      ),
      gestureSettings: GestureSettings(physicalTouchSlop: touchSlop),
      displayId: Int(displayId),
      viewConstraints: ViewConstraints(tight: physicalSize)
    )
    platformDispatcher._updateWindowMetrics(Int(viewId), viewConfig)
  }

  /// Called by the engine to add a new view.
  ///
  /// **Replaces:** `hooks.dart` `_addView(int viewId, ...)`
  /// **C++ caller:** `SwiftRuntimeController::AddView`
  ///
  /// - Parameters:
  ///   - viewId: The view ID to add.
  ///   - width: Physical width in pixels.
  ///   - height: Physical height in pixels.
  ///   - dpr: Device pixel ratio.
  ///   - displayId: The display this view is on.
  public func addView(
    _ viewId: Int64,
    _ width: Double,
    _ height: Double,
    _ dpr: Double,
    _ displayId: Int64
  ) {
    let physicalSize = Size(width, height)
    let viewConfig = ViewConfiguration(
      devicePixelRatio: dpr,
      size: physicalSize,
      displayId: Int(displayId),
      viewConstraints: ViewConstraints(tight: physicalSize)
    )
    platformDispatcher._addView(Int(viewId), viewConfig)
  }

  /// Called by the engine to remove a view.
  ///
  /// **Replaces:** `hooks.dart` `_removeView(int viewId)`
  /// **C++ caller:** `SwiftRuntimeController::RemoveView`
  ///
  /// - Parameter viewId: The view ID to remove.
  public func removeView(_ viewId: Int64) {
    platformDispatcher._removeView(Int(viewId))
  }

  /// Called by the engine when view focus changes.
  ///
  /// **Replaces:** `hooks.dart` `_sendViewFocusEvent(...)`
  /// **C++ caller:** `SwiftRuntimeController::SendViewFocusEvent`
  ///
  /// - Parameters:
  ///   - viewId: The view ID that changed focus.
  ///   - state: The focus state (0 = unfocused, 1 = focused).
  ///   - direction: The focus direction (0 = undefined, 1 = forward, 2 = backward).
  public func sendViewFocusEvent(_ viewId: Int64, _ state: Int32, _ direction: Int32) {
    guard let focusState = ViewFocusState(rawValue: Int(state)),
          let focusDirection = ViewFocusDirection(rawValue: Int(direction)) else {
      return
    }
    let event = ViewFocusEvent(
      viewId: Int(viewId),
      state: focusState,
      direction: focusDirection
    )
    platformDispatcher._sendViewFocusEvent(event)
  }

  // MARK: - Display Configuration

  /// Called by the engine to update display information.
  ///
  /// **Replaces:** `hooks.dart` `_updateDisplays(...)`
  /// **C++ caller:** `SwiftRuntimeController::SetDisplays`
  ///
  /// Display data is encoded as a flat array of doubles where each display
  /// uses 4 entries: [id, devicePixelRatio, width, height, refreshRate].
  ///
  /// - Parameter encodedDisplays: Flat array of display data, 5 values per display:
  ///   [id, dpr, width, height, refreshRate, id, dpr, width, height, refreshRate, ...]
  public func updateDisplays(_ encodedDisplays: [Double]) {
    let valuesPerDisplay = 5
    let numDisplays = encodedDisplays.count / valuesPerDisplay
    var displays: [Display] = []
    displays.reserveCapacity(numDisplays)

    for i in 0..<numDisplays {
      let base = i * valuesPerDisplay
      displays.append(Display(
        id: Int(encodedDisplays[base]),
        devicePixelRatio: encodedDisplays[base + 1],
        size: Size(encodedDisplays[base + 2], encodedDisplays[base + 3]),
        refreshRate: encodedDisplays[base + 4]
      ))
    }
    platformDispatcher._updateDisplays(displays)
  }

  // MARK: - Localization & Settings

  /// Called by the engine to update the locale list.
  ///
  /// **Replaces:** `hooks.dart` `_updateLocales(List<String> locales)`
  /// **C++ caller:** `SwiftRuntimeController::SetLocales`
  ///
  /// Locale data is a flat array of strings, 4 per locale:
  /// [languageCode, countryCode, scriptCode, variant, ...]
  ///
  /// - Parameter locales: Flat array of locale strings, 4 per locale.
  public func updateLocales(_ locales: [String]) {
    platformDispatcher._updateLocales(locales)
  }

  /// Called by the engine to update user settings (JSON-encoded).
  ///
  /// **Replaces:** `hooks.dart` `_updateUserSettingsData(String jsonData)`
  /// **C++ caller:** `SwiftRuntimeController::SetUserSettingsData`
  ///
  /// - Parameter jsonData: JSON string containing user settings.
  ///
  /// TODO: Parse the JSON string to extract textScaleFactor, alwaysUse24HourFormat,
  /// platformBrightness, and systemFontFamily. For now this is a stub because
  /// PlatformDispatcher._updateUserSettings takes typed parameters rather than
  /// a raw JSON string, and JSON parsing requires Foundation.
  public func updateUserSettingsData(_ jsonData: String) {
    // TODO: Parse JSON without Foundation dependency.
    // The Dart version parses JSON in _updateUserSettingsData to extract:
    //   - textScaleFactor: double
    //   - alwaysUse24HourFormat: bool
    //   - platformBrightness: "light" or "dark"
    //   - systemFontFamily: string?
    //
    // For now, we provide defaults. A proper implementation will either:
    // 1. Pass pre-parsed values from C++ (preferred — avoids Foundation dependency)
    // 2. Use a minimal JSON parser written in pure Swift
    platformDispatcher._updateUserSettings(
      textScaleFactor: 1.0,
      alwaysUse24HourFormat: false,
      platformBrightness: .light,
      systemFontFamily: nil
    )
  }

  /// Called by the engine to set the initial lifecycle state.
  ///
  /// **Replaces:** `hooks.dart` `_updateInitialLifecycleState(String state)`
  /// **C++ caller:** `SwiftRuntimeController::SetInitialLifecycleState`
  ///
  /// - Parameter state: The lifecycle state string (e.g. "AppLifecycleState.resumed").
  public func updateInitialLifecycleState(_ state: String) {
    platformDispatcher._updateInitialLifecycleState(state)
  }

  // MARK: - Error Handling

  /// Called by the engine to report an unhandled error.
  ///
  /// **Replaces:** `hooks.dart` error dispatch mechanism
  ///
  /// - Parameters:
  ///   - error: A description of the error.
  ///   - stackTrace: The stack trace string.
  /// - Returns: `true` if the error was handled by the framework.
  public func onError(_ error: String, _ stackTrace: String) -> Bool {
    // Create a simple error wrapper for the Swift Error protocol
    struct RuntimeError: Error, CustomStringConvertible {
      let description: String
    }
    return platformDispatcher._dispatchError(
      RuntimeError(description: error),
      stackTrace
    )
  }
}
