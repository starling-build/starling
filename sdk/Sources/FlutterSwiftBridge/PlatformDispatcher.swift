// PlatformDispatcher.swift
// FlutterSwiftBridge
//
// Migrated from: engine/src/flutter/lib/ui/platform_dispatcher.dart
// This file contains the Swift implementation of platform_dispatcher.dart types.

import Foundation
@_exported import FlutterSwiftBridgeCxx

// Note: FlutterView is implemented in Window.swift

// MARK: - RootIsolateToken

/// A token that represents a root isolate.
///
/// **Dart Source:** `platform_dispatcher.dart:86-102`
/// **Original:** `class RootIsolateToken`
/// **Status:** STUB - Simplified version without C++ bridge
///
/// DIFFERENCE FROM DART: Always returns nil for instance (no isolate support yet).
/// REASON: Full isolate support deferred to later implementation phase.
/// The Dart version calls `__getRootIsolateToken()` via @Native to get the token
/// from `PlatformConfigurationNativeApi::GetRootIsolateToken`. In Swift, there is
/// no Dart VM or isolate concept, so this is stubbed.
public final class RootIsolateToken: Sendable {
  /// Internal token value.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:90-91`
  /// **Original:** `final int _token;`
  internal let token: Int

  /// **Dart Source:** `platform_dispatcher.dart:88`
  /// **Original:** `RootIsolateToken._(this._token);`
  private init(token: Int) {
    self.token = token
  }

  /// The token for the root isolate that is executing this code.
  /// If this code is not executing on a root isolate, [instance] will be nil.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:93-98`
  /// **Original:**
  /// ```dart
  /// static final RootIsolateToken? instance = () {
  ///   final int token = __getRootIsolateToken();
  ///   return token == 0 ? null : RootIsolateToken._(token);
  /// }();
  /// ```
  ///
  /// DIFFERENCE FROM DART: Always returns nil in this stub implementation.
  /// REASON: No isolate support in Swift. The Dart version calls the native
  /// `PlatformConfigurationNativeApi::GetRootIsolateToken` which is a Dart VM concept.
  public static let instance: RootIsolateToken? = nil
}

// MARK: - Type Aliases & Constants

/// Signature of callbacks that have no arguments and return no data.
///
/// **Dart Source:** `platform_dispatcher.dart:7`
/// **Original:** `typedef VoidCallback = void Function();`
public typealias VoidCallback = () -> Void

/// Internal type for reporting timings callback setter.
///
/// **Dart Source:** `platform_dispatcher.dart:63`
/// **Original:** `typedef _SetNeedsReportTimingsFunc = void Function(bool value);`
internal typealias SetNeedsReportTimingsFunc = (Bool) -> Void

/// A gesture setting value that indicates it has not been set by the engine.
///
/// **Dart Source:** `platform_dispatcher.dart:76`
/// **Original:** `const double _kUnsetGestureSetting = -1.0;`
internal let kUnsetGestureSetting: Double = -1.0

/// A message channel to receive KeyData from the platform.
///
/// See embedder.cc::kFlutterKeyDataChannel for more information.
///
/// **Dart Source:** `platform_dispatcher.dart:78-81`
/// **Original:** `const String _kFlutterKeyDataChannel = 'flutter/keydata';`
internal let kFlutterKeyDataChannel: String = "flutter/keydata"

/// Signature for [PlatformDispatcher.onBeginFrame].
///
/// **Dart Source:** `platform_dispatcher.dart:9-18`
/// **Original:** `typedef FrameCallback = void Function(Duration duration);`
///
/// The `duration` argument is the point at which the current frame interval
/// began, expressed as a duration since some epoch. The epoch in all
/// frames will be the same, but it may not match DateTime's epoch.
///
/// For any two frames `a` and `b` such that the frame number of `a` is less
/// than the frame number of `b`, the duration argument for `a` will be less
/// than or equal to the duration argument for `b`.
public typealias FrameCallback = (Duration) -> Void

/// Signature for [PlatformDispatcher.onReportTimings].
///
/// **Dart Source:** `platform_dispatcher.dart:20-32`
/// **Original:** `typedef TimingsCallback = void Function(List<FrameTiming> timings);`
///
/// The callback takes a list of [FrameTiming] because it may not be
/// immediately triggered after each frame. Instead, Flutter tries to batch
/// frames together and send all their timings at once to decrease the
/// overhead (as this is available in the release mode). The list is sorted in
/// ascending order of time (earliest frame first). The timing of any frame
/// will be sent within about 1 second (100ms if in the profile/debug mode)
/// even if there are no later frames to batch. The timing of the first frame
/// will be sent immediately without batching.
public typealias TimingsCallback = ([FrameTiming]) -> Void

/// Signature for [PlatformDispatcher.onPointerDataPacket].
///
/// **Dart Source:** `platform_dispatcher.dart:34-35`
/// **Original:** `typedef PointerDataPacketCallback = void Function(PointerDataPacket packet);`
public typealias PointerDataPacketCallback = (PointerDataPacket) -> Void

/// Signature for [PlatformDispatcher.onKeyData].
///
/// **Dart Source:** `platform_dispatcher.dart:37-41`
/// **Original:** `typedef KeyDataCallback = bool Function(KeyData data);`
///
/// The callback should return true if the key event has been handled by the
/// framework and should not be propagated further.
public typealias KeyDataCallback = (KeyData) -> Bool

/// Signature for [PlatformDispatcher.onSemanticsActionEvent].
///
/// **Dart Source:** `platform_dispatcher.dart:43-44`
/// **Original:** `typedef SemanticsActionEventCallback = void Function(SemanticsActionEvent action);`
public typealias SemanticsActionEventCallback = (SemanticsActionEvent) -> Void

/// Signature for responses to platform messages.
///
/// **Dart Source:** `platform_dispatcher.dart:46-50`
/// **Original:** `typedef PlatformMessageResponseCallback = void Function(ByteData? data);`
///
/// Used as a parameter to [PlatformDispatcher.sendPlatformMessage] and
/// [PlatformDispatcher.onPlatformMessage].
///
/// DIFFERENCE FROM DART: Uses Swift's `Data?` instead of Dart's `ByteData?`.
/// REASON: Swift's Foundation `Data` type is the idiomatic equivalent of Dart's `ByteData`.
public typealias PlatformMessageResponseCallback = (Data?) -> Void

/// Deprecated. Migrate to ChannelBuffers.setListener instead.
///
/// Signature for [PlatformDispatcher.onPlatformMessage].
///
/// **Dart Source:** `platform_dispatcher.dart:52-60`
/// **Original:** `typedef PlatformMessageCallback = void Function(String name, ByteData? data, PlatformMessageResponseCallback? callback);`
///
/// DIFFERENCE FROM DART: Uses Swift's `Data?` instead of Dart's `ByteData?`.
/// REASON: Swift's Foundation `Data` type is the idiomatic equivalent of Dart's `ByteData`.
@available(*, deprecated, message: "Migrate to ChannelBuffers.setListener instead. This feature was deprecated after v3.11.0-20.0.pre.")
public typealias PlatformMessageCallback = (String, Data?, PlatformMessageResponseCallback?) -> Void

/// Signature for [PlatformDispatcher.onError].
///
/// **Dart Source:** `platform_dispatcher.dart:65-73`
/// **Original:** `typedef ErrorCallback = bool Function(Object exception, StackTrace stackTrace);`
///
/// If this method returns false, the engine may use some fallback method to
/// provide information about the error.
///
/// After calling this method, the process or the VM may terminate. Some severe
/// unhandled errors may not be able to call this method either, such as Dart
/// compilation errors or process terminating errors.
///
/// DIFFERENCE FROM DART: Uses Swift's `Error` protocol instead of Dart's `Object` for the
/// exception parameter, and `String` instead of Dart's `StackTrace` type.
/// REASON: Swift's `Error` protocol is the idiomatic equivalent for exception types.
/// `String` is used for stack traces as Swift has no dedicated `StackTrace` type.
public typealias ErrorCallback = (Error, String) -> Bool

// NOTE: SemanticsAction stub removed - full implementation now in Semantics.swift

// MARK: - SemanticsActionEvent

/// An event to request a [SemanticsAction] of [type] to be performed on the
/// [SemanticsNode] identified by [nodeId] owned by the [FlutterView] identified
/// by [viewId].
///
/// **Dart Source:** `platform_dispatcher.dart:2995-3039`
/// **Original:** `class SemanticsActionEvent`
///
/// Used by [SemanticsBinding.performSemanticsAction].
///
/// DIFFERENCE FROM DART: Uses `Any?` for arguments instead of `Object?`. Custom
/// Equatable conformance compares only type, viewId, and nodeId (not arguments).
/// REASON: Swift's `Any` is not `Equatable`, so arguments cannot be compared generically.
public struct SemanticsActionEvent: Sendable, CustomStringConvertible {
  /// The type of action to be performed.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3009-3010`
  public let type: SemanticsAction

  /// The id of the [FlutterView] the [SemanticsNode] identified by [nodeId] is
  /// associated with.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3012-3014`
  public let viewId: Int

  /// The id of the [SemanticsNode] on which the action is to be performed.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3016-3017`
  public let nodeId: Int

  /// Optional arguments for the action.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3019-3020`
  ///
  /// DIFFERENCE FROM DART: Uses `(any Sendable)?` instead of `Object?`.
  /// REASON: Swift requires explicit type erasure for heterogeneous types.
  public let arguments: (any Sendable)?

  /// Creates a [SemanticsActionEvent].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3001-3007`
  public init(
    type: SemanticsAction,
    viewId: Int,
    nodeId: Int,
    arguments: (any Sendable)? = nil
  ) {
    self.type = type
    self.viewId = viewId
    self.nodeId = nodeId
    self.arguments = arguments
  }

  /// Create a clone of the [SemanticsActionEvent] but with provided parameters
  /// replaced.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3024-3038`
  ///
  /// DIFFERENCE FROM DART: Uses a `setArguments` Bool parameter instead of a
  /// sentinel `_noArgumentPlaceholder` object to distinguish "not provided" from "set to nil".
  /// REASON: Swift does not support Dart's sentinel-object pattern cleanly with `Any?`.
  public func copyWith(
    type: SemanticsAction? = nil,
    viewId: Int? = nil,
    nodeId: Int? = nil,
    arguments: (any Sendable)? = nil,
    setArguments: Bool = false
  ) -> SemanticsActionEvent {
    SemanticsActionEvent(
      type: type ?? self.type,
      viewId: viewId ?? self.viewId,
      nodeId: nodeId ?? self.nodeId,
      arguments: setArguments ? arguments : self.arguments
    )
  }

  /// **Dart Source:** (not in Dart, added for Swift debugging convenience)
  public var description: String {
    "SemanticsActionEvent(type: \(type.name), viewId: \(viewId), nodeId: \(nodeId), arguments: \(String(describing: arguments)))"
  }
}

// MARK: - PointerDataPacket Stub

/// Minimal stub for PointerDataPacket.
///
// NOTE: PointerDataPacket stub removed - full implementation is in Pointer.swift
// (migrated from pointer.dart)

// MARK: - FrameTiming

/// Time-related performance metrics of a frame.
///
/// If you're using the whole Flutter framework, please use
/// `SchedulerBinding.addTimingsCallback` to get this. It's preferred over using
/// `PlatformDispatcher.onReportTimings` directly because
/// `SchedulerBinding.addTimingsCallback` allows multiple callbacks. If
/// `SchedulerBinding` is unavailable, then see `PlatformDispatcher.onReportTimings`
/// for how to get this.
///
/// The metrics in debug mode (`flutter run` without any flags) may be very
/// different from those in profile and release modes due to the debug overhead.
/// Therefore it's recommended to only monitor and analyze performance metrics
/// in profile and release modes.
///
/// **Dart Source:** `platform_dispatcher.dart:2039-2196`
/// **Original:** `class FrameTiming`
public class FrameTiming: CustomStringConvertible {
  /// The expected length of the data array.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2096`
  /// **Original:** `static final int _dataLength = FramePhase.values.length + _FrameTimingInfo.values.length;`
  private static let _dataLength: Int = FramePhase.allCases.count + FrameTimingInfo.allCases.count

  /// Internal data array storing timing information.
  /// Some elements are in microseconds, some in bytes, some are counts.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2180`
  /// **Original:** `final List<int> _data;`
  internal let _data: [Int]

  /// Construct [FrameTiming] with raw timestamps in microseconds.
  ///
  /// This constructor is used for unit test only. Real [FrameTiming]s should
  /// be retrieved from [PlatformDispatcher.onReportTimings].
  ///
  /// If the [frameNumber] is not provided, it defaults to `-1`.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2053-2085`
  /// **Original:**
  /// ```dart
  /// factory FrameTiming({
  ///   required int vsyncStart,
  ///   required int buildStart,
  ///   required int buildFinish,
  ///   required int rasterStart,
  ///   required int rasterFinish,
  ///   required int rasterFinishWallTime,
  ///   int layerCacheCount = 0,
  ///   int layerCacheBytes = 0,
  ///   int pictureCacheCount = 0,
  ///   int pictureCacheBytes = 0,
  ///   int frameNumber = -1,
  /// })
  /// ```
  public convenience init(
    vsyncStart: Int,
    buildStart: Int,
    buildFinish: Int,
    rasterStart: Int,
    rasterFinish: Int,
    rasterFinishWallTime: Int,
    layerCacheCount: Int = 0,
    layerCacheBytes: Int = 0,
    pictureCacheCount: Int = 0,
    pictureCacheBytes: Int = 0,
    frameNumber: Int = -1
  ) {
    self.init([
      vsyncStart,
      buildStart,
      buildFinish,
      rasterStart,
      rasterFinish,
      rasterFinishWallTime,
      layerCacheCount,
      layerCacheBytes,
      pictureCacheCount,
      pictureCacheBytes,
      frameNumber,
    ])
  }

  /// Construct [FrameTiming] with raw timestamps in microseconds.
  ///
  /// The `data` array must have the same number of elements as
  /// `FramePhase.allCases.count + FrameTimingInfo.allCases.count`.
  ///
  /// This constructor is usually only called by the Flutter engine, or a test.
  /// To get the [FrameTiming] of your app, see [PlatformDispatcher.onReportTimings].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2087-2094`
  /// **Original:** `FrameTiming._(this._data) : assert(_data.length == _dataLength);`
  internal init(_ data: [Int]) {
    assert(data.count == FrameTiming._dataLength,
           "FrameTiming data must have \(FrameTiming._dataLength) elements, got \(data.count)")
    self._data = data
  }

  /// This is a raw timestamp in microseconds from some epoch. The epoch in all
  /// [FrameTiming] is the same, but it may not match DateTime's epoch.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2098-2100`
  /// **Original:** `int timestampInMicroseconds(FramePhase phase) => _data[phase.index];`
  public func timestampInMicroseconds(_ phase: FramePhase) -> Int {
    _data[phase.rawValue]
  }

  /// Returns a Duration for the given phase timestamp.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2102`
  /// **Original:** `Duration _rawDuration(FramePhase phase) => Duration(microseconds: _data[phase.index]);`
  private func _rawDuration(_ phase: FramePhase) -> Duration {
    .microseconds(Int64(_data[phase.rawValue]))
  }

  /// Returns the raw info value at the given index.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2104`
  /// **Original:** `int _rawInfo(_FrameTimingInfo info) => _data[FramePhase.values.length + info.index];`
  private func _rawInfo(_ info: FrameTimingInfo) -> Int {
    _data[FramePhase.allCases.count + info.rawValue]
  }

  /// The duration to build the frame on the UI thread.
  ///
  /// The build starts approximately when [PlatformDispatcher.onBeginFrame] is
  /// called. The [Duration] in the [PlatformDispatcher.onBeginFrame] callback
  /// is exactly the `Duration(microseconds:
  /// timestampInMicroseconds(FramePhase.buildStart))`.
  ///
  /// The build finishes when [FlutterView.render] is called.
  ///
  /// To ensure smooth animations of X fps, this should not exceed 1000/X
  /// milliseconds. That's about 16ms for 60fps, and 8ms for 120fps.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2106-2123`
  /// **Original:** `Duration get buildDuration => _rawDuration(FramePhase.buildFinish) - _rawDuration(FramePhase.buildStart);`
  public var buildDuration: Duration {
    _rawDuration(.buildFinish) - _rawDuration(.buildStart)
  }

  /// The duration to rasterize the frame on the raster thread.
  ///
  /// To ensure smooth animations of X fps, this should not exceed 1000/X
  /// milliseconds. That's about 16ms for 60fps, and 8ms for 120fps.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2125-2130`
  /// **Original:** `Duration get rasterDuration => _rawDuration(FramePhase.rasterFinish) - _rawDuration(FramePhase.rasterStart);`
  public var rasterDuration: Duration {
    _rawDuration(.rasterFinish) - _rawDuration(.rasterStart)
  }

  /// The duration between receiving the vsync signal and starting building the
  /// frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2132-2135`
  /// **Original:** `Duration get vsyncOverhead => _rawDuration(FramePhase.buildStart) - _rawDuration(FramePhase.vsyncStart);`
  public var vsyncOverhead: Duration {
    _rawDuration(.buildStart) - _rawDuration(.vsyncStart)
  }

  /// The timespan between vsync start and raster finish.
  ///
  /// To achieve the lowest latency on an X fps display, this should not exceed
  /// 1000/X milliseconds. That's about 16ms for 60fps, and 8ms for 120fps.
  ///
  /// See also [vsyncOverhead], [buildDuration] and [rasterDuration].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2137-2145`
  /// **Original:** `Duration get totalSpan => _rawDuration(FramePhase.rasterFinish) - _rawDuration(FramePhase.vsyncStart);`
  public var totalSpan: Duration {
    _rawDuration(.rasterFinish) - _rawDuration(.vsyncStart)
  }

  /// The number of layers stored in the raster cache during the frame.
  ///
  /// See also [layerCacheBytes], [pictureCacheCount] and [pictureCacheBytes].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2147-2150`
  /// **Original:** `int get layerCacheCount => _rawInfo(_FrameTimingInfo.layerCacheCount);`
  public var layerCacheCount: Int {
    _rawInfo(.layerCacheCount)
  }

  /// The number of bytes of image data used to cache layers during the frame.
  ///
  /// See also [layerCacheCount], [layerCacheMegabytes], [pictureCacheCount] and [pictureCacheBytes].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2152-2155`
  /// **Original:** `int get layerCacheBytes => _rawInfo(_FrameTimingInfo.layerCacheBytes);`
  public var layerCacheBytes: Int {
    _rawInfo(.layerCacheBytes)
  }

  /// The number of megabytes of image data used to cache layers during the frame.
  ///
  /// See also [layerCacheCount], [layerCacheBytes], [pictureCacheCount] and [pictureCacheBytes].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2157-2160`
  /// **Original:** `double get layerCacheMegabytes => layerCacheBytes / 1024.0 / 1024.0;`
  public var layerCacheMegabytes: Double {
    Double(layerCacheBytes) / 1024.0 / 1024.0
  }

  /// The number of pictures stored in the raster cache during the frame.
  ///
  /// See also [layerCacheCount], [layerCacheBytes] and [pictureCacheBytes].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2162-2165`
  /// **Original:** `int get pictureCacheCount => _rawInfo(_FrameTimingInfo.pictureCacheCount);`
  public var pictureCacheCount: Int {
    _rawInfo(.pictureCacheCount)
  }

  /// The number of bytes of image data used to cache pictures during the frame.
  ///
  /// See also [layerCacheCount], [layerCacheBytes], [pictureCacheCount] and [pictureCacheMegabytes].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2167-2170`
  /// **Original:** `int get pictureCacheBytes => _rawInfo(_FrameTimingInfo.pictureCacheBytes);`
  public var pictureCacheBytes: Int {
    _rawInfo(.pictureCacheBytes)
  }

  /// The number of megabytes of image data used to cache pictures during the frame.
  ///
  /// See also [layerCacheCount], [layerCacheBytes], [pictureCacheCount] and [pictureCacheBytes].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2172-2175`
  /// **Original:** `double get pictureCacheMegabytes => pictureCacheBytes / 1024.0 / 1024.0;`
  public var pictureCacheMegabytes: Double {
    Double(pictureCacheBytes) / 1024.0 / 1024.0
  }

  /// The frame key associated with this frame measurement.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2177-2178`
  /// **Original:** `int get frameNumber => _data.last;`
  public var frameNumber: Int {
    _data.last!
  }

  /// Formats a Duration as milliseconds string.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2182`
  /// **Original:** `String _formatMS(Duration duration) => '${duration.inMicroseconds * 0.001}ms';`
  ///
  /// DIFFERENCE FROM DART: Uses Duration.components to extract microseconds then converts.
  /// REASON: Swift's Duration doesn't have a direct `inMicroseconds` property like Dart.
  /// The result is numerically identical.
  private func _formatMS(_ duration: Duration) -> String {
    let components = duration.components
    let totalMicroseconds = components.seconds * 1_000_000 + components.attoseconds / 1_000_000_000_000
    return "\(Double(totalMicroseconds) * 0.001)ms"
  }

  /// **Dart Source:** `platform_dispatcher.dart:2184-2195`
  /// **Original:**
  /// ```dart
  /// @override
  /// String toString() {
  ///   return '$runtimeType(buildDuration: ${_formatMS(buildDuration)}, '
  ///       'rasterDuration: ${_formatMS(rasterDuration)}, '
  ///       'vsyncOverhead: ${_formatMS(vsyncOverhead)}, '
  ///       'totalSpan: ${_formatMS(totalSpan)}, '
  ///       'layerCacheCount: $layerCacheCount, '
  ///       'layerCacheBytes: $layerCacheBytes, '
  ///       'pictureCacheCount: $pictureCacheCount, '
  ///       'pictureCacheBytes: $pictureCacheBytes, '
  ///       'frameNumber: ${_data.last})';
  /// }
  /// ```
  public var description: String {
    "FrameTiming(buildDuration: \(_formatMS(buildDuration)), " +
    "rasterDuration: \(_formatMS(rasterDuration)), " +
    "vsyncOverhead: \(_formatMS(vsyncOverhead)), " +
    "totalSpan: \(_formatMS(totalSpan)), " +
    "layerCacheCount: \(layerCacheCount), " +
    "layerCacheBytes: \(layerCacheBytes), " +
    "pictureCacheCount: \(pictureCacheCount), " +
    "pictureCacheBytes: \(pictureCacheBytes), " +
    "frameNumber: \(frameNumber))"
  }
}

// MARK: - FramePhase

/// Various important time points in the lifetime of a frame.
///
/// [FrameTiming] records a timestamp of each phase for performance analysis.
///
/// **Dart Source:** `platform_dispatcher.dart:1986-2020`
/// **Original:** `enum FramePhase`
public enum FramePhase: Int, CaseIterable, Sendable {
  /// The timestamp of the vsync signal given by the operating system.
  ///
  /// See also [FrameTiming.vsyncOverhead].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1993`
  case vsyncStart

  /// When the UI thread starts building a frame.
  ///
  /// See also [FrameTiming.buildDuration].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1998`
  case buildStart

  /// When the UI thread finishes building a frame.
  ///
  /// See also [FrameTiming.buildDuration].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2003`
  case buildFinish

  /// When the raster thread starts rasterizing a frame.
  ///
  /// See also [FrameTiming.rasterDuration].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2008`
  case rasterStart

  /// When the raster thread finishes rasterizing a frame.
  ///
  /// See also [FrameTiming.rasterDuration].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2013`
  case rasterFinish

  /// When the raster thread finished rasterizing a frame in wall-time.
  ///
  /// This is useful for correlating time raster finish time with the system
  /// clock to integrate with other profiling tools.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2019`
  case rasterFinishWallTime
}

// MARK: - FrameTimingInfo

/// Internal enum for frame timing information indices beyond [FramePhase].
///
/// These values index into the [FrameTiming] data array after the
/// [FramePhase] entries, providing additional frame statistics.
///
/// **Dart Source:** `platform_dispatcher.dart:2022-2037`
/// **Original:** `enum _FrameTimingInfo`
///
/// DIFFERENCE FROM DART: Named `FrameTimingInfo` (without underscore prefix) with `internal` access.
/// REASON: Swift uses access control keywords instead of underscore prefix for visibility.
internal enum FrameTimingInfo: Int, CaseIterable, Sendable {
  /// The number of engine layers cached in the raster cache during the frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2024`
  case layerCacheCount

  /// The number of bytes used to cache engine layers during the frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2027`
  case layerCacheBytes

  /// The number of picture layers cached in the raster cache during the frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2030`
  case pictureCacheCount

  /// The number of bytes used to cache pictures during the frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2033`
  case pictureCacheBytes

  /// The frame number of the frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2036`
  case frameNumber
}

// MARK: - AppLifecycleState

/// States that an application can be in once it is running.
///
/// States not supported on a platform will be synthesized by the framework when
/// transitioning between states which are supported, so that all
/// implementations share the same state machine.
///
/// The initial value for the state is the [detached] state, updated to the
/// current state (usually [resumed]) as soon as the first lifecycle update is
/// received from the platform.
///
/// For historical and name collision reasons, Flutter's application state names
/// do not correspond one to one with the state names on all platforms. On
/// Android, for instance, when the OS calls `Activity.onPause()`, Flutter will
/// enter the [inactive] state, but when Android calls `Activity.onStop()`,
/// Flutter enters the [paused] state. See the individual state's documentation
/// for descriptions of what they mean on each platform.
///
/// The current application state can be obtained from
/// `SchedulerBinding.instance.lifecycleState`, and changes to the state can be
/// observed by creating an `AppLifecycleListener`, or by using a
/// `WidgetsBindingObserver` by overriding the
/// `WidgetsBindingObserver.didChangeAppLifecycleState` method.
///
/// Applications should not rely on always receiving all possible notifications.
/// For example, if the application is killed with a task manager, a kill
/// signal, the user pulls the power from the device, or there is a rapid
/// unscheduled disassembly of the device, no notification will be sent before
/// the application is suddenly terminated, and some states may be skipped.
///
/// **Dart Source:** `platform_dispatcher.dart:2198-2333`
/// **Original:** `enum AppLifecycleState`
public enum AppLifecycleState: String, CaseIterable, Sendable {
  /// The application is still hosted by a Flutter engine but is detached from
  /// any host views.
  ///
  /// The application defaults to this state before it initializes, and can be
  /// in this state (applicable on Android, iOS, and web) after all views have been
  /// detached.
  ///
  /// When the application is in this state, the engine is running without a
  /// view.
  ///
  /// This state is only entered on iOS, Android, and web, although on all platforms
  /// it is the default state before the application begins running.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2258`
  case detached

  /// On all platforms, this state indicates that the application is in the
  /// default running mode for a running application that has input focus and is
  /// visible.
  ///
  /// On Android, this state corresponds to the Flutter host view having focus
  /// (`Activity.onWindowFocusChanged` was called with true) while in Android's
  /// "resumed" state. It is possible for the Flutter app to be in the [inactive]
  /// state while still being in Android's "onResume" state if the app has lost
  /// focus (`Activity.onWindowFocusChanged` was called with false), but hasn't
  /// had `Activity.onPause` called on it.
  ///
  /// On iOS and macOS, this corresponds to the app running in the foreground
  /// active state.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2278`
  case resumed

  /// At least one view of the application is visible, but none have input
  /// focus. The application is otherwise running normally.
  ///
  /// On non-web desktop platforms, this corresponds to an application that is
  /// not in the foreground, but still has visible windows.
  ///
  /// On the web, this corresponds to an application that is running in a
  /// window or tab that does not have input focus.
  ///
  /// On iOS and macOS, this state corresponds to the Flutter host view running in
  /// the foreground inactive state. Apps transition to this state when in a phone
  /// call, when responding to a TouchID request, when entering the app switcher
  /// or the control center, or when the UIViewController hosting the Flutter
  /// app is transitioning.
  ///
  /// On Android, this corresponds to the Flutter host view running in Android's
  /// paused state (i.e. `Activity.onPause` has been called), or in Android's
  /// "resumed" state (i.e. `Activity.onResume` has been called) but does not
  /// have window focus.
  ///
  /// On Android and iOS, apps in this state should assume that they may be
  /// [hidden] and [paused] at any time.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2309`
  case inactive

  /// All views of an application are hidden, either because the application is
  /// about to be paused (on iOS and Android), or because it has been minimized
  /// or placed on a desktop that is no longer visible (on non-web desktop), or
  /// is running in a window or tab that is no longer visible (on the web).
  ///
  /// On iOS and Android, in order to keep the state machine the same on all
  /// platforms, a transition to this state is synthesized before the [paused]
  /// state is entered when coming from [inactive], and before the [inactive]
  /// state is entered when coming from [paused].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2322`
  case hidden

  /// The application is not currently visible to the user, and not responding
  /// to user input.
  ///
  /// When the application is in this state, the engine will not call the
  /// `PlatformDispatcher.onBeginFrame` and `PlatformDispatcher.onDrawFrame`
  /// callbacks.
  ///
  /// This state is only entered on iOS and Android.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2332`
  case paused
}

// MARK: - AppExitResponse

/// The possible responses to a request to exit the application.
///
/// The request is typically responded to by creating an `AppLifecycleListener`
/// and supplying an `AppLifecycleListener.onExitRequested` callback, or by
/// overriding `WidgetsBindingObserver.didRequestAppExit`.
///
/// **Dart Source:** `platform_dispatcher.dart:2335-2346`
/// **Original:** `enum AppExitResponse`
public enum AppExitResponse: String, CaseIterable, Sendable {
  /// Exiting the application can proceed.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2342`
  case exit

  /// Cancel the exit: do not exit the application.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2345`
  case cancel
}

// MARK: - AppExitType

/// The type of application exit to perform when calling
/// `ServicesBinding.exitApplication`.
///
/// **Dart Source:** `platform_dispatcher.dart:2348-2367`
/// **Original:** `enum AppExitType`
public enum AppExitType: String, CaseIterable, Sendable {
  /// Requests that the application start an orderly exit, sending a request
  /// back to the framework through the `WidgetsBinding`. If that responds
  /// with [AppExitResponse.exit], then proceed with the same steps as a
  /// [required] exit. If that responds with [AppExitResponse.cancel], then the
  /// exit request is canceled and the application continues executing normally.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2356`
  case cancelable

  /// A non-cancelable orderly exit request. The engine will shut down the
  /// engine and call the native UI toolkit's exit API.
  ///
  /// If you need an even faster and more dangerous exit, then call `dart:io`'s
  /// `exit()` directly, and even the native toolkit's exit API won't be called.
  /// This is quite dangerous, though, since it's possible that the engine will
  /// crash because it hasn't been properly shut down, causing the app to crash
  /// on exit.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2366`
  case required
}

// MARK: - DisplayFeatureType

/// Type of [DisplayFeature], describing the [DisplayFeature] behaviour and if
/// it obstructs the display.
///
/// Some types of [DisplayFeature], like [DisplayFeatureType.fold], can be
/// reported without actually impeding drawing on the screen. They are useful
/// for knowing where the display is bent or has a crease. The
/// [DisplayFeature.bounds] can be 0-width in such cases.
///
/// The shape formed by the screens for types [DisplayFeatureType.fold] and
/// [DisplayFeatureType.hinge] is called the posture and is exposed in
/// [DisplayFeature.state]. For example, the [DisplayFeatureState.postureFlat] posture
/// means the screens form a flat surface.
///
/// **Dart Source:** `platform_dispatcher.dart:2611-2643`
/// **Original:** `enum DisplayFeatureType`
public enum DisplayFeatureType: Int, CaseIterable, Sendable {
  /// [DisplayFeature] type is new and not yet known to Flutter.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2631`
  case unknown

  /// A fold in the flexible screen without a physical gap.
  ///
  /// The bounds for this display feature type indicate where the display makes a crease.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2636`
  case fold

  /// A physical separation with a hinge that allows two display panels to fold.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2639`
  case hinge

  /// A non-displaying area of the screen, usually housing cameras or sensors.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2642`
  case cutout
}

// MARK: - DisplayFeatureState

/// State of the display feature, which contains information about the posture
/// for foldable features.
///
/// The posture is the shape made by the parts of the flexible screen or
/// physical screen panels. They are inspired by and similar to
/// [Android Postures](https://developer.android.com/guide/topics/ui/foldables#postures).
///
/// * For [DisplayFeatureType.fold]s & [DisplayFeatureType.hinge]s, the state is
///   the posture.
/// * For [DisplayFeatureType.cutout]s, the state is not used and has the
///   [DisplayFeatureState.unknown] value.
///
/// **Dart Source:** `platform_dispatcher.dart:2645-2671`
/// **Original:** `enum DisplayFeatureState`
public enum DisplayFeatureState: Int, CaseIterable, Sendable {
  /// The display feature is a [DisplayFeatureType.cutout] or this state is new
  /// and not yet known to Flutter.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2659`
  case unknown

  /// The foldable device is completely open.
  ///
  /// The screen space that is presented to the user is flat.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2664`
  case postureFlat

  /// Fold angle is in an intermediate position between opened and closed state.
  ///
  /// There is a non-flat angle between parts of the flexible screen or between
  /// physical screen panels such that the screens start to face each other.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2670`
  case postureHalfOpened
}

// MARK: - DisplayFeature

/// Area of the display that may be obstructed by a hardware feature.
///
/// This is populated only on Android.
///
/// The [bounds] are measured in logical pixels. On devices with two screens the
/// coordinate system starts with (0,0) in the top-left corner of the left or top screen
/// and expands to include both screens and the visual space between them.
///
/// The [type] describes the behaviour and if [DisplayFeature] obstructs the display.
/// For example, [DisplayFeatureType.hinge] and [DisplayFeatureType.cutout] both obstruct the display,
/// while [DisplayFeatureType.fold] does not.
///
/// The [state] contains information about the posture for foldable features
/// ([DisplayFeatureType.hinge] and [DisplayFeatureType.fold]). The posture is
/// the shape of the display, for example [DisplayFeatureState.postureFlat] or
/// [DisplayFeatureState.postureHalfOpened]. For [DisplayFeatureType.cutout],
/// the state is not used and has the [DisplayFeatureState.unknown] value.
///
/// **Dart Source:** `platform_dispatcher.dart:2535-2609`
/// **Original:** `class DisplayFeature`
///
/// DIFFERENCE FROM DART: Uses `struct` instead of `class` for value semantics.
/// REASON: DisplayFeature is immutable with all `final` fields in Dart, making it
/// a natural fit for Swift's value type (struct).
public struct DisplayFeature: Equatable, Hashable, CustomStringConvertible, Sendable {
  /// The area of the flutter view occupied by this display feature, measured in logical pixels.
  ///
  /// On devices with two screens, the Flutter view spans from the top-left corner
  /// of the left or top screen to the bottom-right corner of the right or bottom screen,
  /// including the visual area occupied by any display feature. Bounds of display
  /// features are reported in this coordinate system.
  ///
  /// For example, on a dual screen device in portrait mode:
  ///
  /// * [Rect.left] gives you the size of left screen, in logical pixels.
  /// * [Rect.right] gives you the size of the left screen + the hinge width.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2567-2578`
  /// **Original:** `final Rect bounds;`
  public let bounds: Rect

  /// Type of display feature, e.g. hinge, fold, cutout.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2580-2581`
  /// **Original:** `final DisplayFeatureType type;`
  public let type: DisplayFeatureType

  /// Posture of display feature, which is populated only for folds and hinges.
  ///
  /// For cutouts, this is [DisplayFeatureState.unknown].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2583-2586`
  /// **Original:** `final DisplayFeatureState state;`
  public let state: DisplayFeatureState

  /// Creates a display feature with the given properties.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2561-2565`
  /// **Original:**
  /// ```dart
  /// const DisplayFeature({required this.bounds, required this.type, required this.state})
  ///   : assert(
  ///       !identical(type, DisplayFeatureType.cutout) ||
  ///           identical(state, DisplayFeatureState.unknown),
  ///     );
  /// ```
  public init(bounds: Rect, type: DisplayFeatureType, state: DisplayFeatureState) {
    assert(
      type != .cutout || state == .unknown,
      "Cutout display features must have DisplayFeatureState.unknown state"
    )
    self.bounds = bounds
    self.type = type
    self.state = state
  }

  /// **Dart Source:** `platform_dispatcher.dart:2588-2600`
  /// **Original:**
  /// ```dart
  /// @override
  /// bool operator ==(Object other) { ... }
  /// ```
  ///
  /// DIFFERENCE FROM DART: Synthesized by Swift's Equatable conformance for structs.
  /// REASON: Swift structs with Equatable conformance auto-synthesize == for stored properties,
  /// which produces identical behavior to the Dart implementation.

  /// **Dart Source:** `platform_dispatcher.dart:2602-2603`
  /// **Original:** `int get hashCode => Object.hash(bounds, type, state);`
  ///
  /// DIFFERENCE FROM DART: Synthesized by Swift's Hashable conformance for structs.
  /// REASON: Swift structs with Hashable conformance auto-synthesize hash(into:) for stored
  /// properties, which hashes the same fields as the Dart implementation.

  /// **Dart Source:** `platform_dispatcher.dart:2605-2608`
  /// **Original:** `String toString() => 'DisplayFeature(rect: $bounds, type: $type, state: $state)';`
  public var description: String {
    "DisplayFeature(rect: \(bounds), type: \(type), state: \(state))"
  }
}

// MARK: - DartPerformanceMode

/// Various performance modes for tuning the Dart VM's GC performance.
///
/// For the editor of this enum, please keep the order in sync with
/// `Dart_PerformanceMode` in
/// [dart_api.h](https://github.com/dart-lang/sdk/blob/main/runtime/include/dart_api.h#L1302).
///
/// **Dart Source:** `platform_dispatcher.dart:2972-2993`
/// **Original:** `enum DartPerformanceMode`
public enum DartPerformanceMode: Int, CaseIterable, Sendable {
  /// This is the default mode that the Dart VM is in.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2978`
  case balanced

  /// Optimize for low latency, at the expense of throughput and memory overhead
  /// by performing work in smaller batches (requiring more overhead) or by
  /// delaying work (requiring more memory). An embedder should not remain in
  /// this mode indefinitely.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2984`
  case latency

  /// Optimize for high throughput, at the expense of latency and memory overhead
  /// by performing work in larger batches with more intervening growth.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2988`
  case throughput

  /// Optimize for low memory, at the expensive of throughput and latency by more
  /// frequently performing work.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2992`
  case memory
}

// MARK: - ViewFocusState

/// Represents the focus state of a given [FlutterView].
///
/// When focus is lost, the view's focus state changes to [ViewFocusState.unfocused].
///
/// When focus is gained, the view's focus state changes to [ViewFocusState.focused].
///
/// Valid transitions within a view are:
///
/// - [ViewFocusState.focused] to [ViewFocusState.unfocused].
/// - [ViewFocusState.unfocused] to [ViewFocusState.focused].
///
/// See also:
///
///   * [ViewFocusDirection], that specifies the focus direction.
///   * [ViewFocusEvent], that conveys information about a [FlutterView] focus change.
///
/// **Dart Source:** `platform_dispatcher.dart:3067-3088`
/// **Original:** `enum ViewFocusState`
public enum ViewFocusState: Int, CaseIterable, Sendable {
  /// Specifies that a view does not have platform focus.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3084`
  case unfocused

  /// Specifies that a view has platform focus.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3087`
  case focused
}

// MARK: - ViewFocusDirection

/// Represents the direction in which the focus transitioned across [FlutterView]s.
///
/// See also:
///
///   * [ViewFocusState], that specifies the current focus state of a [FlutterView].
///   * [ViewFocusEvent], that conveys information about a [FlutterView] focus change.
///
/// **Dart Source:** `platform_dispatcher.dart:3090-3112`
/// **Original:** `enum ViewFocusDirection`
public enum ViewFocusDirection: Int, CaseIterable, Sendable {
  /// Indicates the focus transition did not have a direction.
  ///
  /// This is typically associated with focus being programmatically requested or
  /// when focus is lost.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3101`
  case undefined

  /// Indicates the focus transition was performed in a forward direction.
  ///
  /// This is typically result of the user pressing tab.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3106`
  case forward

  /// Indicates the focus transition was performed in a backward direction.
  ///
  /// This is typically result of the user pressing shift + tab.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3111`
  case backward
}

// MARK: - ViewFocusEvent

/// An event for the engine to communicate view focus changes to the app.
///
/// This value will be typically passed to the [PlatformDispatcher.onViewFocusChange]
/// callback.
///
/// **Dart Source:** `platform_dispatcher.dart:3044-3065`
/// **Original:** `final class ViewFocusEvent`
///
/// DIFFERENCE FROM DART: Uses `struct` instead of `final class` for value semantics.
/// REASON: ViewFocusEvent is immutable with all `final` fields in Dart, making it
/// a natural fit for Swift's value type (struct).
public struct ViewFocusEvent: Equatable, CustomStringConvertible, Sendable {
  /// The ID of the [FlutterView] that experienced a focus change.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3052-3053`
  /// **Original:** `final int viewId;`
  public let viewId: Int

  /// The state focus changed to.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3055-3056`
  /// **Original:** `final ViewFocusState state;`
  public let state: ViewFocusState

  /// The direction focus changed to.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3058-3059`
  /// **Original:** `final ViewFocusDirection direction;`
  public let direction: ViewFocusDirection

  /// Creates a [ViewFocusEvent].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:3049-3050`
  /// **Original:** `const ViewFocusEvent({required this.viewId, required this.state, required this.direction});`
  public init(viewId: Int, state: ViewFocusState, direction: ViewFocusDirection) {
    self.viewId = viewId
    self.state = state
    self.direction = direction
  }

  /// **Dart Source:** `platform_dispatcher.dart:3061-3064`
  /// **Original:** `String toString() => 'ViewFocusEvent(viewId: $viewId, state: $state, direction: $direction)';`
  public var description: String {
    "ViewFocusEvent(viewId: \(viewId), state: \(state), direction: \(direction))"
  }
}

// MARK: - ViewPadding

/// A representation of distances for each of the four edges of a rectangle,
/// used to encode the view insets and padding that applications should place
/// around their user interface, as exposed by [FlutterView.viewInsets] and
/// [FlutterView.padding]. View insets and padding are preferably read via
/// [MediaQuery.of].
///
/// For a generic class that represents distances around a rectangle, see the
/// [EdgeInsets] class.
///
/// See also:
///
///  * [WidgetsBindingObserver], for a widgets layer mechanism to receive
///    notifications when the padding changes.
///  * [MediaQuery.of], for the preferred mechanism for accessing these values.
///  * [Scaffold], which automatically applies the padding in material design
///    applications.
///
/// **Dart Source:** `platform_dispatcher.dart:2369-2412`
/// **Original:** `class ViewPadding`
///
/// DIFFERENCE FROM DART: Uses `struct` instead of `class` for value semantics.
/// REASON: ViewPadding is immutable with all `final` fields in Dart, making it
/// a natural fit for Swift's value type (struct).
public struct ViewPadding: Equatable, CustomStringConvertible, Sendable {
  /// The distance from the left edge to the first unpadded pixel, in physical pixels.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2393-2394`
  /// **Original:** `final double left;`
  public let left: Double

  /// The distance from the top edge to the first unpadded pixel, in physical pixels.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2396-2397`
  /// **Original:** `final double top;`
  public let top: Double

  /// The distance from the right edge to the first unpadded pixel, in physical pixels.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2399-2400`
  /// **Original:** `final double right;`
  public let right: Double

  /// The distance from the bottom edge to the first unpadded pixel, in physical pixels.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2402-2403`
  /// **Original:** `final double bottom;`
  public let bottom: Double

  /// Creates insets from offsets from each side.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2386-2391`
  /// **Original:** `const ViewPadding._({required this.left, required this.top, required this.right, required this.bottom});`
  ///
  /// DIFFERENCE FROM DART: Constructor is public instead of private named constructor.
  /// REASON: Swift structs use public initializers; Dart's private named constructor pattern
  /// (`ViewPadding._()`) was used to restrict construction to the engine. In Swift, the
  /// memberwise initializer is the idiomatic approach.
  public init(left: Double, top: Double, right: Double, bottom: Double) {
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
  }

  /// A view padding that has zeros for each edge.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2405-2406`
  /// **Original:** `static const ViewPadding zero = ViewPadding._(left: 0.0, top: 0.0, right: 0.0, bottom: 0.0);`
  public static let zero = ViewPadding(left: 0.0, top: 0.0, right: 0.0, bottom: 0.0)

  /// **Dart Source:** `platform_dispatcher.dart:2408-2411`
  /// **Original:** `String toString() => 'ViewPadding(left: $left, top: $top, right: $right, bottom: $bottom)';`
  public var description: String {
    "ViewPadding(left: \(left), top: \(top), right: \(right), bottom: \(bottom))"
  }
}

/// Deprecated. Will be removed in a future version of Flutter.
///
/// Use [ViewPadding] instead.
///
/// **Dart Source:** `platform_dispatcher.dart:2414-2421`
/// **Original:** `typedef WindowPadding = ViewPadding;`
@available(*, deprecated, message: "Use ViewPadding instead. This feature was deprecated after v3.8.0-14.0.pre.")
public typealias WindowPadding = ViewPadding

// MARK: - ViewConstraints

/// Immutable layout constraints for [FlutterView]s.
///
/// Similar to `BoxConstraints`, a [Size] respects a [ViewConstraints] if, and
/// only if, all of the following relations hold:
///
/// * [minWidth] <= [Size.width] <= [maxWidth]
/// * [minHeight] <= [Size.height] <= [maxHeight]
///
/// The constraints themselves must satisfy these relations:
///
/// * 0.0 <= [minWidth] <= [maxWidth] <= [Double.infinity]
/// * 0.0 <= [minHeight] <= [maxHeight] <= [Double.infinity]
///
/// For each constraint, [Double.infinity] is a legal value.
///
/// For a generic class that represents these kind of constraints, see the
/// `BoxConstraints` class.
///
/// **Dart Source:** `platform_dispatcher.dart:2423-2533`
/// **Original:** `class ViewConstraints`
///
/// DIFFERENCE FROM DART: Uses `struct` instead of `class` for value semantics.
/// REASON: ViewConstraints is immutable with all `final` fields in Dart, making it
/// a natural fit for Swift's value type (struct).
public struct ViewConstraints: Equatable, Hashable, CustomStringConvertible, Sendable {
  /// The minimum width that satisfies the constraints.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2456-2457`
  /// **Original:** `final double minWidth;`
  public let minWidth: Double

  /// The maximum width that satisfies the constraints.
  ///
  /// Might be [Double.infinity].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2459-2462`
  /// **Original:** `final double maxWidth;`
  public let maxWidth: Double

  /// The minimum height that satisfies the constraints.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2464-2465`
  /// **Original:** `final double minHeight;`
  public let minHeight: Double

  /// The maximum height that satisfies the constraints.
  ///
  /// Might be [Double.infinity].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2467-2470`
  /// **Original:** `final double maxHeight;`
  public let maxHeight: Double

  /// Creates view constraints with the given constraints.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2441-2447`
  /// **Original:**
  /// ```dart
  /// const ViewConstraints({
  ///   this.minWidth = 0.0,
  ///   this.maxWidth = double.infinity,
  ///   this.minHeight = 0.0,
  ///   this.maxHeight = double.infinity,
  /// });
  /// ```
  public init(
    minWidth: Double = 0.0,
    maxWidth: Double = .infinity,
    minHeight: Double = 0.0,
    maxHeight: Double = .infinity
  ) {
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.minHeight = minHeight
    self.maxHeight = maxHeight
  }

  /// Creates view constraints that is respected only by the given size.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2449-2454`
  /// **Original:**
  /// ```dart
  /// ViewConstraints.tight(Size size)
  ///   : minWidth = size.width,
  ///     maxWidth = size.width,
  ///     minHeight = size.height,
  ///     maxHeight = size.height;
  /// ```
  public init(tight size: Size) {
    self.minWidth = size.width
    self.maxWidth = size.width
    self.minHeight = size.height
    self.maxHeight = size.height
  }

  /// Whether the given size satisfies the constraints.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2472-2478`
  /// **Original:**
  /// ```dart
  /// bool isSatisfiedBy(Size size) {
  ///   return (minWidth <= size.width) &&
  ///       (size.width <= maxWidth) &&
  ///       (minHeight <= size.height) &&
  ///       (size.height <= maxHeight);
  /// }
  /// ```
  public func isSatisfiedBy(_ size: Size) -> Bool {
    (minWidth <= size.width) &&
    (size.width <= maxWidth) &&
    (minHeight <= size.height) &&
    (size.height <= maxHeight)
  }

  /// Whether there is exactly one size that satisfies the constraints.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2480-2481`
  /// **Original:** `bool get isTight => minWidth >= maxWidth && minHeight >= maxHeight;`
  public var isTight: Bool {
    minWidth >= maxWidth && minHeight >= maxHeight
  }

  /// Scales each constraint parameter by the inverse of the given factor.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2483-2491`
  /// **Original:**
  /// ```dart
  /// ViewConstraints operator /(double factor) {
  ///   return ViewConstraints(
  ///     minWidth: minWidth / factor,
  ///     maxWidth: maxWidth / factor,
  ///     minHeight: minHeight / factor,
  ///     maxHeight: maxHeight / factor,
  ///   );
  /// }
  /// ```
  public static func / (lhs: ViewConstraints, rhs: Double) -> ViewConstraints {
    ViewConstraints(
      minWidth: lhs.minWidth / rhs,
      maxWidth: lhs.maxWidth / rhs,
      minHeight: lhs.minHeight / rhs,
      maxHeight: lhs.maxHeight / rhs
    )
  }

  /// **Dart Source:** `platform_dispatcher.dart:2493-2506`
  /// **Original:**
  /// ```dart
  /// @override
  /// bool operator ==(Object other) {
  ///   if (identical(this, other)) { return true; }
  ///   if (other.runtimeType != runtimeType) { return false; }
  ///   return other is ViewConstraints &&
  ///       other.minWidth == minWidth &&
  ///       other.maxWidth == maxWidth &&
  ///       other.minHeight == minHeight &&
  ///       other.maxHeight == maxHeight;
  /// }
  /// ```
  ///
  /// DIFFERENCE FROM DART: Synthesized by Swift's Equatable conformance for structs.
  /// REASON: Swift structs with Equatable conformance auto-synthesize == for stored properties,
  /// which produces identical behavior to the Dart implementation.

  /// **Dart Source:** `platform_dispatcher.dart:2508-2509`
  /// **Original:** `int get hashCode => Object.hash(minWidth, maxWidth, minHeight, maxHeight);`
  ///
  /// DIFFERENCE FROM DART: Synthesized by Swift's Hashable conformance for structs.
  /// REASON: Swift structs with Hashable conformance auto-synthesize hash(into:) for stored
  /// properties, which hashes the same fields as the Dart implementation.

  /// **Dart Source:** `platform_dispatcher.dart:2511-2532`
  /// **Original:**
  /// ```dart
  /// @override
  /// String toString() {
  ///   if (minWidth == double.infinity && minHeight == double.infinity) {
  ///     return 'ViewConstraints(biggest)';
  ///   }
  ///   if (minWidth == 0 && maxWidth == double.infinity &&
  ///       minHeight == 0 && maxHeight == double.infinity) {
  ///     return 'ViewConstraints(unconstrained)';
  ///   }
  ///   String describe(double min, double max, String dim) {
  ///     if (min == max) { return '$dim=${min.toStringAsFixed(1)}'; }
  ///     return '${min.toStringAsFixed(1)}<=$dim<=${max.toStringAsFixed(1)}';
  ///   }
  ///   final String width = describe(minWidth, maxWidth, 'w');
  ///   final String height = describe(minHeight, maxHeight, 'h');
  ///   return 'ViewConstraints($width, $height)';
  /// }
  /// ```
  public var description: String {
    if minWidth == .infinity && minHeight == .infinity {
      return "ViewConstraints(biggest)"
    }
    if minWidth == 0 && maxWidth == .infinity &&
       minHeight == 0 && maxHeight == .infinity {
      return "ViewConstraints(unconstrained)"
    }
    func describe(_ min: Double, _ max: Double, _ dim: String) -> String {
      if min == max {
        return "\(dim)=\(String(format: "%.1f", min))"
      }
      return "\(String(format: "%.1f", min))<=\(dim)<=\(String(format: "%.1f", max))"
    }
    let width = describe(minWidth, maxWidth, "w")
    let height = describe(minHeight, maxHeight, "h")
    return "ViewConstraints(\(width), \(height))"
  }
}

// MARK: - Locale

/// An identifier used to select a user's language and formatting preferences.
///
/// This represents a [Unicode Language
/// Identifier](https://www.unicode.org/reports/tr35/#Unicode_language_identifier)
/// (i.e. without Locale extensions), except variants are not supported.
///
/// Locales are canonicalized according to the "preferred value" entries in the
/// [IANA Language Subtag
/// Registry](https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry).
/// For example, `Locale("he")` and `Locale("iw")` are equal and
/// both have the [languageCode] `he`, because `iw` is a deprecated language
/// subtag that was replaced by the subtag `he`.
///
/// See also:
///
///  * `PlatformDispatcher.locale`, which specifies the system's currently selected
///    [Locale].
///
/// **Dart Source:** `platform_dispatcher.dart:2673-2970`
/// **Original:** `class Locale`
///
/// DIFFERENCE FROM DART: Uses `struct` instead of `class` for value semantics.
/// REASON: Locale is immutable with all `final` fields in Dart, making it
/// a natural fit for Swift's value type (struct).
///
/// DIFFERENCE FROM DART: No toString() caching with static `_cachedLocale` / `_cachedLocaleString`.
/// REASON: Dart's caching optimization is tied to `identical()` reference checks on classes.
/// Swift structs use value semantics, so reference-identity caching is not applicable.
/// The performance impact is negligible for locale string formatting.
public struct Locale: Equatable, Hashable, CustomStringConvertible, Sendable {
  /// The primary language subtag for the locale (internal storage).
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2778`
  /// **Original:** `final String _languageCode;`
  private let _languageCode: String

  /// The script subtag for the locale.
  ///
  /// This may be nil, indicating that there is no specified script subtag.
  ///
  /// This must be a valid Unicode Language Identifier script subtag as listed
  /// in [Unicode CLDR supplemental
  /// data](https://github.com/unicode-org/cldr/blob/master/common/validity/script.xml).
  ///
  /// See also:
  ///
  ///  * [Locale.init(fromSubtags:)], which describes the conventions for creating
  ///    [Locale] objects.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2863-2875`
  /// **Original:** `final String? scriptCode;`
  public let scriptCode: String?

  /// The region subtag for the locale (internal storage).
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2897`
  /// **Original:** `final String? _countryCode;`
  private let _countryCode: String?

  /// Creates a new Locale object. The first argument is the
  /// primary language subtag, the second is the region (also
  /// referred to as 'country') subtag.
  ///
  /// For example:
  ///
  /// ```swift
  /// let swissFrench = Locale("fr", "CH")
  /// let canadianFrench = Locale("fr", "CA")
  /// ```
  ///
  /// The primary language subtag must not be empty. The region subtag is
  /// optional. When there is no region/country subtag, the parameter should
  /// be omitted or passed `nil` instead of an empty string.
  ///
  /// The subtag values are _case sensitive_ and must be one of the valid
  /// subtags according to CLDR supplemental data:
  /// [language](https://github.com/unicode-org/cldr/blob/master/common/validity/language.xml),
  /// [region](https://github.com/unicode-org/cldr/blob/master/common/validity/region.xml). The
  /// primary language subtag must be at least two and at most eight lowercase
  /// letters, but not four letters. The region subtag must be two
  /// uppercase letters or three digits. See the [Unicode Language
  /// Identifier](https://www.unicode.org/reports/tr35/#Unicode_language_identifier)
  /// specification.
  ///
  /// Validity is not checked by default, but some methods may throw away
  /// invalid data.
  ///
  /// See also:
  ///
  ///  * [Locale.init(fromSubtags:)], which also allows a [scriptCode] to be
  ///    specified.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2691-2725`
  /// **Original:** `const Locale(this._languageCode, [this._countryCode])`
  public init(_ languageCode: String, _ countryCode: String? = nil) {
    assert(!languageCode.isEmpty, "languageCode must not be empty")
    self._languageCode = languageCode
    self.scriptCode = nil
    self._countryCode = countryCode
  }

  /// Creates a new Locale object.
  ///
  /// The keyword arguments specify the subtags of the Locale.
  ///
  /// The subtag values are _case sensitive_ and must be valid subtags according
  /// to CLDR supplemental data:
  /// [language](https://github.com/unicode-org/cldr/blob/master/common/validity/language.xml),
  /// [script](https://github.com/unicode-org/cldr/blob/master/common/validity/script.xml) and
  /// [region](https://github.com/unicode-org/cldr/blob/master/common/validity/region.xml) for
  /// each of languageCode, scriptCode and countryCode respectively.
  ///
  /// The [languageCode] subtag is optional. When there is no language subtag,
  /// the parameter should be omitted or set to "und". When not supplied, the
  /// [languageCode] defaults to "und", an undefined language code.
  ///
  /// The [countryCode] subtag is optional. When there is no country subtag,
  /// the parameter should be omitted or passed `nil` instead of an empty string.
  ///
  /// Validity is not checked by default, but some methods may throw away
  /// invalid data.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2727-2752`
  /// **Original:** `const Locale.fromSubtags({String languageCode = 'und', this.scriptCode, String? countryCode})`
  public init(fromSubtags languageCode: String = "und", scriptCode: String? = nil, countryCode: String? = nil) {
    assert(!languageCode.isEmpty, "languageCode must not be empty")
    assert(scriptCode == nil || !scriptCode!.isEmpty, "scriptCode must not be empty")
    assert(countryCode == nil || !countryCode!.isEmpty, "countryCode must not be empty")
    self._languageCode = languageCode
    self.scriptCode = scriptCode
    self._countryCode = countryCode
  }

  /// The primary language subtag for the locale.
  ///
  /// This must not be empty. It may be 'und', representing 'undefined'.
  ///
  /// This is expected to be string registered in the [IANA Language Subtag
  /// Registry](https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry)
  /// with the type "language". The string specified must match the case of the
  /// string in the registry.
  ///
  /// Language subtags that are deprecated in the registry and have a preferred
  /// code are changed to their preferred code. For example,
  /// `Locale("he")` and `Locale("iw")` are equal, and both have the
  /// [languageCode] `he`, because `iw` is a deprecated language subtag that was
  /// replaced by the subtag `he`.
  ///
  /// This must be a valid Unicode Language subtag as listed in [Unicode CLDR
  /// supplemental
  /// data](https://github.com/unicode-org/cldr/blob/master/common/validity/language.xml).
  ///
  /// See also:
  ///
  ///  * [Locale.init(fromSubtags:)], which describes the conventions for creating
  ///    [Locale] objects.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2754-2778`
  /// **Original:** `String get languageCode => _deprecatedLanguageSubtagMap[_languageCode] ?? _languageCode;`
  public var languageCode: String {
    Locale._deprecatedLanguageSubtagMap[_languageCode] ?? _languageCode
  }

  /// Map of deprecated language subtags to their preferred replacements.
  ///
  /// This map is generated by //flutter/tools/gen_locale.dart
  /// Mappings generated for language subtag registry as of 2019-02-27.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2782-2861`
  /// **Original:** `static const Map<String, String> _deprecatedLanguageSubtagMap`
  private static let _deprecatedLanguageSubtagMap: [String: String] = [
    "in": "id",   // Indonesian; deprecated 1989-01-01
    "iw": "he",   // Hebrew; deprecated 1989-01-01
    "ji": "yi",   // Yiddish; deprecated 1989-01-01
    "jw": "jv",   // Javanese; deprecated 2001-08-13
    "mo": "ro",   // Moldavian, Moldovan; deprecated 2008-11-22
    "aam": "aas", // Aramanik; deprecated 2015-02-12
    "adp": "dz",  // Adap; deprecated 2015-02-12
    "aue": "ktz", // ǂKxʼauǁʼein; deprecated 2015-02-12
    "ayx": "nun", // Ayi (China); deprecated 2011-08-16
    "bgm": "bcg", // Baga Mboteni; deprecated 2016-05-30
    "bjd": "drl", // Bandjigali; deprecated 2012-08-12
    "ccq": "rki", // Chaungtha; deprecated 2012-08-12
    "cjr": "mom", // Chorotega; deprecated 2010-03-11
    "cka": "cmr", // Khumi Awa Chin; deprecated 2012-08-12
    "cmk": "xch", // Chimakum; deprecated 2010-03-11
    "coy": "pij", // Coyaima; deprecated 2016-05-30
    "cqu": "quh", // Chilean Quechua; deprecated 2016-05-30
    "drh": "khk", // Darkhat; deprecated 2010-03-11
    "drw": "prs", // Darwazi; deprecated 2010-03-11
    "gav": "dev", // Gabutamon; deprecated 2010-03-11
    "gfx": "vaj", // Mangetti Dune ǃXung; deprecated 2015-02-12
    "ggn": "gvr", // Eastern Gurung; deprecated 2016-05-30
    "gti": "nyc", // Gbati-ri; deprecated 2015-02-12
    "guv": "duz", // Gey; deprecated 2016-05-30
    "hrr": "jal", // Horuru; deprecated 2012-08-12
    "ibi": "opa", // Ibilo; deprecated 2012-08-12
    "ilw": "gal", // Talur; deprecated 2013-09-10
    "jeg": "oyb", // Jeng; deprecated 2017-02-23
    "kgc": "tdf", // Kasseng; deprecated 2016-05-30
    "kgh": "kml", // Upper Tanudan Kalinga; deprecated 2012-08-12
    "koj": "kwv", // Sara Dunjo; deprecated 2015-02-12
    "krm": "bmf", // Krim; deprecated 2017-02-23
    "ktr": "dtp", // Kota Marudu Tinagas; deprecated 2016-05-30
    "kvs": "gdj", // Kunggara; deprecated 2016-05-30
    "kwq": "yam", // Kwak; deprecated 2015-02-12
    "kxe": "tvd", // Kakihum; deprecated 2015-02-12
    "kzj": "dtp", // Coastal Kadazan; deprecated 2016-05-30
    "kzt": "dtp", // Tambunan Dusun; deprecated 2016-05-30
    "lii": "raq", // Lingkhim; deprecated 2015-02-12
    "lmm": "rmx", // Lamam; deprecated 2014-02-28
    "meg": "cir", // Mea; deprecated 2013-09-10
    "mst": "mry", // Cataelano Mandaya; deprecated 2010-03-11
    "mwj": "vaj", // Maligo; deprecated 2015-02-12
    "myt": "mry", // Sangab Mandaya; deprecated 2010-03-11
    "nad": "xny", // Nijadali; deprecated 2016-05-30
    "ncp": "kdz", // Ndaktup; deprecated 2018-03-08
    "nnx": "ngv", // Ngong; deprecated 2015-02-12
    "nts": "pij", // Natagaimas; deprecated 2016-05-30
    "oun": "vaj", // ǃOǃung; deprecated 2015-02-12
    "pcr": "adx", // Panang; deprecated 2013-09-10
    "pmc": "huw", // Palumata; deprecated 2016-05-30
    "pmu": "phr", // Mirpur Panjabi; deprecated 2015-02-12
    "ppa": "bfy", // Pao; deprecated 2016-05-30
    "ppr": "lcq", // Piru; deprecated 2013-09-10
    "pry": "prt", // Pray 3; deprecated 2016-05-30
    "puz": "pub", // Purum Naga; deprecated 2014-02-28
    "sca": "hle", // Sansu; deprecated 2012-08-12
    "skk": "oyb", // Sok; deprecated 2017-02-23
    "tdu": "dtp", // Tempasuk Dusun; deprecated 2016-05-30
    "thc": "tpo", // Tai Hang Tong; deprecated 2016-05-30
    "thx": "oyb", // The; deprecated 2015-02-12
    "tie": "ras", // Tingal; deprecated 2011-08-16
    "tkk": "twm", // Takpa; deprecated 2011-08-16
    "tlw": "weo", // South Wemale; deprecated 2012-08-12
    "tmp": "tyj", // Tai Mène; deprecated 2016-05-30
    "tne": "kak", // Tinoc Kallahan; deprecated 2016-05-30
    "tnf": "prs", // Tangshewi; deprecated 2010-03-11
    "tsf": "taj", // Southwestern Tamang; deprecated 2015-02-12
    "uok": "ema", // Uokha; deprecated 2015-02-12
    "xba": "cax", // Kamba (Brazil); deprecated 2016-05-30
    "xia": "acn", // Xiandao; deprecated 2013-09-10
    "xkh": "waw", // Karahawyana; deprecated 2016-05-30
    "xsj": "suj", // Subi; deprecated 2015-02-12
    "ybd": "rki", // Yangbye; deprecated 2012-08-12
    "yma": "lrr", // Yamphe; deprecated 2012-08-12
    "ymt": "mtm", // Mator-Taygi-Karagas; deprecated 2015-02-12
    "yos": "zom", // Yos; deprecated 2013-09-10
    "yuu": "yug", // Yugh; deprecated 2014-02-28
  ]

  /// The region subtag for the locale.
  ///
  /// This may be nil, indicating that there is no specified region subtag.
  ///
  /// This is expected to be string registered in the [IANA Language Subtag
  /// Registry](https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry)
  /// with the type "region". The string specified must match the case of the
  /// string in the registry.
  ///
  /// Region subtags that are deprecated in the registry and have a preferred
  /// code are changed to their preferred code. For example, `Locale("de",
  /// "DE")` and `Locale("de", "DD")` are equal, and both have the
  /// [countryCode] `DE`, because `DD` is a deprecated language subtag that was
  /// replaced by the subtag `DE`.
  ///
  /// See also:
  ///
  ///  * [Locale.init(fromSubtags:)], which describes the conventions for creating
  ///    [Locale] objects.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2877-2897`
  /// **Original:** `String? get countryCode => _deprecatedRegionSubtagMap[_countryCode] ?? _countryCode;`
  public var countryCode: String? {
    if let code = _countryCode {
      return Locale._deprecatedRegionSubtagMap[code] ?? code
    }
    return nil
  }

  /// Map of deprecated region subtags to their preferred replacements.
  ///
  /// This map is generated by //flutter/tools/gen_locale.dart
  /// Mappings generated for language subtag registry as of 2019-02-27.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2901-2908`
  /// **Original:** `static const Map<String, String> _deprecatedRegionSubtagMap`
  private static let _deprecatedRegionSubtagMap: [String: String] = [
    "BU": "MM", // Burma; deprecated 1989-12-05
    "DD": "DE", // German Democratic Republic; deprecated 1990-10-30
    "FX": "FR", // Metropolitan France; deprecated 1997-07-14
    "TP": "TL", // East Timor; deprecated 2002-05-20
    "YD": "YE", // Democratic Yemen; deprecated 1990-08-14
    "ZR": "CD", // Zaire; deprecated 1997-07-14
  ]

  /// **Dart Source:** `platform_dispatcher.dart:2910-2929`
  /// **Original:**
  /// ```dart
  /// @override
  /// bool operator ==(Object other) {
  ///   if (identical(this, other)) { return true; }
  ///   if (other is! Locale) { return false; }
  ///   final String? thisCountryCode = countryCode;
  ///   final String? otherCountryCode = other.countryCode;
  ///   return other.languageCode == languageCode &&
  ///       other.scriptCode == scriptCode &&
  ///       (other.countryCode == thisCountryCode ||
  ///           otherCountryCode != null && otherCountryCode.isEmpty && thisCountryCode == null ||
  ///           thisCountryCode != null && thisCountryCode.isEmpty && other.countryCode == null);
  /// }
  /// ```
  ///
  /// DIFFERENCE FROM DART: Custom == implementation instead of auto-synthesized.
  /// REASON: Dart treats empty-string countryCode as equivalent to nil. This behavior
  /// must be preserved explicitly in Swift.
  public static func == (lhs: Locale, rhs: Locale) -> Bool {
    let lhsCountry = lhs.countryCode
    let rhsCountry = rhs.countryCode
    return lhs.languageCode == rhs.languageCode &&
      lhs.scriptCode == rhs.scriptCode &&
      (lhsCountry == rhsCountry ||
        (rhsCountry != nil && rhsCountry!.isEmpty && lhsCountry == nil) ||
        (lhsCountry != nil && lhsCountry!.isEmpty && rhsCountry == nil))
  }

  /// **Dart Source:** `platform_dispatcher.dart:2931-2932`
  /// **Original:** `int get hashCode => Object.hash(languageCode, scriptCode, countryCode == '' ? null : countryCode);`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(languageCode)
    hasher.combine(scriptCode)
    let country = countryCode
    hasher.combine(country == "" ? nil : country)
  }

  /// Returns a string representing the locale.
  ///
  /// This identifier happens to be a valid Unicode Locale Identifier using
  /// underscores as separator, however it is intended to be used for debugging
  /// purposes only. For parsable results, use [toLanguageTag] instead.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2937-2950`
  /// **Original:**
  /// ```dart
  /// @override
  /// String toString() {
  ///   if (!identical(_cachedLocale, this)) {
  ///     _cachedLocale = this;
  ///     _cachedLocaleString = _rawToString('_');
  ///   }
  ///   return _cachedLocaleString!;
  /// }
  /// ```
  ///
  /// DIFFERENCE FROM DART: No caching of toString() result.
  /// REASON: Dart caches using static `_cachedLocale` with `identical()` reference check.
  /// Swift structs use value semantics, so reference-identity caching is not applicable.
  public var description: String {
    _rawToString("_")
  }

  /// Returns a syntactically valid Unicode BCP47 Locale Identifier.
  ///
  /// Some examples of such identifiers: "en", "es-419", "hi-Deva-IN" and
  /// "zh-Hans-CN". See http://www.unicode.org/reports/tr35/ for technical
  /// details.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2952-2957`
  /// **Original:** `String toLanguageTag() => _rawToString('-');`
  public func toLanguageTag() -> String {
    _rawToString("-")
  }

  /// Internal helper to format the locale as a string with a given separator.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:2959-2969`
  /// **Original:**
  /// ```dart
  /// String _rawToString(String separator) {
  ///   final StringBuffer out = StringBuffer(languageCode);
  ///   if (scriptCode != null && scriptCode!.isNotEmpty) {
  ///     out.write('$separator$scriptCode');
  ///   }
  ///   final String? countryCode = _countryCode;
  ///   if (countryCode != null && countryCode.isNotEmpty) {
  ///     out.write('$separator${this.countryCode}');
  ///   }
  ///   return out.toString();
  /// }
  /// ```
  private func _rawToString(_ separator: String) -> String {
    var result = languageCode
    if let script = scriptCode, !script.isEmpty {
      result += "\(separator)\(script)"
    }
    if let country = _countryCode, !country.isEmpty {
      // Use the public countryCode getter which applies deprecation mapping
      result += "\(separator)\(countryCode!)"
    }
    return result
  }
}

// MARK: - _ViewConfiguration

/// An immutable view configuration.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/platform_dispatcher.dart:1886-1984`
/// **Original:** `class _ViewConfiguration`
///
/// DIFFERENCE FROM DART: Uses `struct` instead of `class` for value semantics.
/// REASON: Swift idiomatic approach for immutable data types.
package struct ViewConfiguration: CustomStringConvertible, Sendable {
  /// The identifier for a display for this view, in
  /// [PlatformDispatcher._displays].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1901-1903`
  public let displayId: Int

  /// The sizing constraints for this view in physical pixels.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1905-1906`
  public let viewConstraints: ViewConstraints

  /// The pixel density of the output surface.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1908-1909`
  public let devicePixelRatio: Double

  /// The size requested for the view in physical pixels.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1911-1912`
  public let size: Size

  /// The number of physical pixels on each side of the display rectangle into
  /// which the view can render, but over which the operating system will likely
  /// place system UI, such as the keyboard, that fully obscures any content.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1914-1920`
  public let viewInsets: ViewPadding

  /// The number of physical pixels on each side of the display rectangle into
  /// which the view can render, but which may be partially obscured by system
  /// UI (such as the system notification area), or physical intrusions in
  /// the display (e.g. overscan regions on television screens or phone sensor
  /// housings).
  ///
  /// Unlike [padding], this value does not change relative to [viewInsets].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1922-1934`
  public let viewPadding: ViewPadding

  /// The number of physical pixels on each side of the display rectangle into
  /// which the view can render, but where the operating system will consume
  /// input gestures for the sake of system navigation.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1936-1943`
  public let systemGestureInsets: ViewPadding

  /// The number of physical pixels on each side of the display rectangle into
  /// which the view can render, but which may be partially obscured by system
  /// UI (such as the system notification area), or physical intrusions in
  /// the display (e.g. overscan regions on television screens or phone sensor
  /// housings).
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1945-1953`
  public let padding: ViewPadding

  /// Additional configuration for touch gestures performed on this view.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1955-1960`
  public let gestureSettings: GestureSettings

  /// Areas of the display that are obstructed by hardware features.
  ///
  /// This list is populated only on Android. If the device has no display
  /// features, this list is empty.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1962-1978`
  public let displayFeatures: [DisplayFeature]

  /// Creates an immutable view configuration.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1888-1899`
  /// **Original:** `const _ViewConfiguration({...})`
  public init(
    devicePixelRatio: Double = 1.0,
    size: Size = .zero,
    viewInsets: ViewPadding = .zero,
    viewPadding: ViewPadding = .zero,
    systemGestureInsets: ViewPadding = .zero,
    padding: ViewPadding = .zero,
    gestureSettings: GestureSettings = GestureSettings(),
    displayFeatures: [DisplayFeature] = [],
    displayId: Int = 0,
    viewConstraints: ViewConstraints = ViewConstraints(maxWidth: 0, maxHeight: 0)
  ) {
    self.devicePixelRatio = devicePixelRatio
    self.size = size
    self.viewInsets = viewInsets
    self.viewPadding = viewPadding
    self.systemGestureInsets = systemGestureInsets
    self.padding = padding
    self.gestureSettings = gestureSettings
    self.displayFeatures = displayFeatures
    self.displayId = displayId
    self.viewConstraints = viewConstraints
  }

  /// **Dart Source:** `platform_dispatcher.dart:1980-1983`
  /// **Original:** `String toString() => '$runtimeType[size: $size]';`
  public var description: String {
    "ViewConfiguration[size: \(size)]"
  }
}

// MARK: - PlatformConfiguration

/// Configuration of the platform.
///
/// Immutable struct holding platform-wide configuration values.
///
/// **Dart Source:** `platform_dispatcher.dart:1800-1884`
/// **Original:** `class _PlatformConfiguration`
///
/// DIFFERENCE FROM DART: Named `PlatformConfiguration` (without underscore prefix) with `internal` access.
/// REASON: Swift uses access control keywords instead of underscore prefix for visibility.
internal struct PlatformConfiguration: Sendable {
  /// Additional accessibility features that may be enabled by the platform.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1840-1841`
  public let accessibilityFeatures: AccessibilityFeatures

  /// The setting indicating whether time should always be shown in the 24-hour
  /// format.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1843-1845`
  public let alwaysUse24HourFormat: Bool

  /// Whether the user has requested that updateSemantics be called when the
  /// semantic contents of a view changes.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1847-1849`
  public let semanticsEnabled: Bool

  /// The setting indicating the current brightness mode of the host platform.
  /// If the platform has no preference, [platformBrightness] defaults to
  /// [Brightness.light].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1851-1854`
  public let platformBrightness: Brightness

  /// The system-reported text scale.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1856-1857`
  public let textScaleFactor: Double

  /// The full system-reported supported locales of the device.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1859-1860`
  public let locales: [Locale]

  /// The route or path that the embedder requested when the application was
  /// launched.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1862-1864`
  public let defaultRouteName: String?

  /// The system-reported default font family.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1866-1867`
  public let systemFontFamily: String?

  /// A unique identifier for this [PlatformConfiguration].
  ///
  /// This unique identifier is optionally assigned by the platform embedder.
  /// Dart code that runs on the Flutter UI thread and synchronously invokes
  /// platform APIs can use this identifier to tell the embedder to use the
  /// configuration that matches the current [PlatformConfiguration] in
  /// dart:ui. See the `_getScaledFontSize` function for an example.
  ///
  /// This field's nullability also indicates whether the platform supports
  /// nonlinear text scaling (as it's the only feature that requires synchronous
  /// invocation of platform APIs). This field is always nil if the platform
  /// does not use nonlinear text scaling, or when dart:ui has not received any
  /// configuration updates from the embedder yet. The _getScaledFontSize
  /// function should not be called in either case.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1869-1883`
  public let configurationId: Int?

  /// Creates a platform configuration.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1804-1814`
  /// **Original:** `const _PlatformConfiguration({...})`
  public init(
    accessibilityFeatures: AccessibilityFeatures = AccessibilityFeatures(0),
    alwaysUse24HourFormat: Bool = false,
    semanticsEnabled: Bool = false,
    platformBrightness: Brightness = .light,
    textScaleFactor: Double = 1.0,
    locales: [Locale] = [],
    defaultRouteName: String? = nil,
    systemFontFamily: String? = nil,
    configurationId: Int? = nil
  ) {
    self.accessibilityFeatures = accessibilityFeatures
    self.alwaysUse24HourFormat = alwaysUse24HourFormat
    self.semanticsEnabled = semanticsEnabled
    self.platformBrightness = platformBrightness
    self.textScaleFactor = textScaleFactor
    self.locales = locales
    self.defaultRouteName = defaultRouteName
    self.systemFontFamily = systemFontFamily
    self.configurationId = configurationId
  }

  /// Returns a copy with the given fields replaced with new values.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1816-1838`
  /// **Original:** `_PlatformConfiguration copyWith({...})`
  public func copyWith(
    accessibilityFeatures: AccessibilityFeatures? = nil,
    alwaysUse24HourFormat: Bool? = nil,
    semanticsEnabled: Bool? = nil,
    platformBrightness: Brightness? = nil,
    textScaleFactor: Double? = nil,
    locales: [Locale]? = nil,
    defaultRouteName: String?? = nil,
    systemFontFamily: String?? = nil,
    configurationId: Int?? = nil
  ) -> PlatformConfiguration {
    PlatformConfiguration(
      accessibilityFeatures: accessibilityFeatures ?? self.accessibilityFeatures,
      alwaysUse24HourFormat: alwaysUse24HourFormat ?? self.alwaysUse24HourFormat,
      semanticsEnabled: semanticsEnabled ?? self.semanticsEnabled,
      platformBrightness: platformBrightness ?? self.platformBrightness,
      textScaleFactor: textScaleFactor ?? self.textScaleFactor,
      locales: locales ?? self.locales,
      defaultRouteName: defaultRouteName ?? self.defaultRouteName,
      systemFontFamily: systemFontFamily ?? self.systemFontFamily,
      configurationId: configurationId ?? self.configurationId
    )
  }
}

// MARK: - SystemColor

/// A color specified in the operating system UI color palette.
///
/// **Dart Source:** `platform_dispatcher.dart:1555-1650`
/// **Original:** `final class SystemColor`
///
/// As of the current release, system colors are supported on web only. To check
/// if the current platform supports system colors, use the static
/// [platformProvidesSystemColors] field.
///
/// This class is typically used in conjunction with
/// [AccessibilityFeatures.highContrast]. In particular, on Windows, when a user
/// enables high-contrast mode, they may also pick specific colors that should
/// be used by application user interfaces.
///
/// The "light" system colors are available through [SystemColor.light], and the
/// "dark" system colors are available through [SystemColor.dark].
///
/// See also:
///   * https://drafts.csswg.org/css-color/#css-system-colors
///   * https://developer.mozilla.org/en-US/docs/Web/CSS/system-color
///   * https://developer.mozilla.org/en-US/docs/Web/CSS/@media/forced-colors
public struct SystemColor: Sendable {
  /// Standard system color name, as defined by W3C CSS specification.
  ///
  /// System color names in Flutter are case-sensitive.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1608-1619`
  /// **Original:** `final String name;`
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  public let name: String

  /// The color value used for the color named [name], if supported.
  ///
  /// If [isSupported] is false, the [value] is nil. If [isSupported] is true,
  /// the [value] is not nil.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1621-1625`
  /// **Original:** `final Color? value;`
  public let value: Color?

  /// Creates an instance of a system color.
  ///
  /// [name] is the name of the color. System colors provided by
  /// [SystemColorPalette], such as [SystemColorPalette.accentColor] and
  /// [SystemColorPalette.buttonText], use standard names defined by the
  /// W3C CSS specification.
  ///
  /// [value] is the color value, if this color name is supported, and nil if
  /// it's unsupported.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1598-1606`
  /// **Original:** `const SystemColor({required this.name, this.value});`
  public init(name: String, value: Color? = nil) {
    self.name = name
    self.value = value
  }

  /// Returns true if the current platform provides the system color with the
  /// given [name].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1627-1634`
  /// **Original:** `bool get isSupported => value != null;`
  ///
  /// See also:
  ///   * [platformProvidesSystemColors], which returns whether the current
  ///     platform provides system colors.
  public var isSupported: Bool {
    value != nil
  }

  /// Returns true if the current platform provides system colors.
  ///
  /// As of the current release, system colors are supported on web only.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1636-1643`
  /// **Original:** `static bool get platformProvidesSystemColors => false;`
  ///
  /// See also:
  ///   * [isSupported], which returns whether a specific color is supported.
  public static var platformProvidesSystemColors: Bool {
    false
  }

  /// A palette of system colors for light mode.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1645-1646`
  /// **Original:** `static final SystemColorPalette light = SystemColorPalette._(Brightness.light);`
  public static let light = SystemColorPalette(brightness: .light)

  /// A palette of system colors for dark mode.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1648-1649`
  /// **Original:** `static final SystemColorPalette dark = SystemColorPalette._(Brightness.dark);`
  public static let dark = SystemColorPalette(brightness: .dark)
}

// MARK: - SystemColorPalette

/// A palette of system colors specified in the operating system for a given
/// [brightness].
///
/// The getters in this class, such as [accentColor] and [buttonText], provide
/// standard system colors defined by the
/// [W3C CSS specification](https://drafts.csswg.org/css-color/#css-system-colors).
///
/// **Dart Source:** `platform_dispatcher.dart:1652-1798`
/// **Original:** `final class SystemColorPalette`
///
/// DIFFERENCE FROM DART: Dart version throws UnsupportedError on all getters.
/// Swift version returns SystemColor with nil value (equivalent behavior since
/// SystemColor.isSupported returns false when value is nil).
/// REASON: Swift does not use exceptions for control flow. Returning unsupported
/// SystemColor achieves the same semantic effect.
public struct SystemColorPalette: Sendable {
  /// The brightness mode for which this palette is defined.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1659-1660`
  /// **Original:** `final Brightness brightness;`
  public let brightness: Brightness

  /// **Dart Source:** `platform_dispatcher.dart:1657`
  /// **Original:** `SystemColorPalette._(this.brightness);`
  internal init(brightness: Brightness) {
    self.brightness = brightness
  }

  /// Helper that returns an unsupported SystemColor.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1662-1664`
  /// **Original:** `static UnsupportedError _systemColorUnsupportedError()`
  ///
  /// DIFFERENCE FROM DART: Returns unsupported SystemColor instead of throwing.
  /// REASON: Swift avoids exceptions for expected unsupported-platform scenarios.
  private func _unsupportedSystemColor(name: String) -> SystemColor {
    SystemColor(name: name, value: nil)
  }

  /// Returns system color named "AccentColor".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1666-1671`
  /// **Original:** `SystemColor get accentColor => throw _systemColorUnsupportedError();`
  public var accentColor: SystemColor { _unsupportedSystemColor(name: "AccentColor") }

  /// Returns system color named "AccentColorText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1673-1678`
  /// **Original:** `SystemColor get accentColorText => throw _systemColorUnsupportedError();`
  public var accentColorText: SystemColor { _unsupportedSystemColor(name: "AccentColorText") }

  /// Returns system color named "ActiveText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1680-1685`
  /// **Original:** `SystemColor get activeText => throw _systemColorUnsupportedError();`
  public var activeText: SystemColor { _unsupportedSystemColor(name: "ActiveText") }

  /// Returns system color named "ButtonBorder".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1687-1692`
  /// **Original:** `SystemColor get buttonBorder => throw _systemColorUnsupportedError();`
  public var buttonBorder: SystemColor { _unsupportedSystemColor(name: "ButtonBorder") }

  /// Returns system color named "ButtonFace".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1694-1699`
  /// **Original:** `SystemColor get buttonFace => throw _systemColorUnsupportedError();`
  public var buttonFace: SystemColor { _unsupportedSystemColor(name: "ButtonFace") }

  /// Returns system color named "ButtonText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1701-1706`
  /// **Original:** `SystemColor get buttonText => throw _systemColorUnsupportedError();`
  public var buttonText: SystemColor { _unsupportedSystemColor(name: "ButtonText") }

  /// Returns system color named "Canvas".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1708-1713`
  /// **Original:** `SystemColor get canvas => throw _systemColorUnsupportedError();`
  public var canvas: SystemColor { _unsupportedSystemColor(name: "Canvas") }

  /// Returns system color named "CanvasText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1715-1720`
  /// **Original:** `SystemColor get canvasText => throw _systemColorUnsupportedError();`
  public var canvasText: SystemColor { _unsupportedSystemColor(name: "CanvasText") }

  /// Returns system color named "Field".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1722-1727`
  /// **Original:** `SystemColor get field => throw _systemColorUnsupportedError();`
  public var field: SystemColor { _unsupportedSystemColor(name: "Field") }

  /// Returns system color named "FieldText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1729-1734`
  /// **Original:** `SystemColor get fieldText => throw _systemColorUnsupportedError();`
  public var fieldText: SystemColor { _unsupportedSystemColor(name: "FieldText") }

  /// Returns system color named "GrayText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1736-1741`
  /// **Original:** `SystemColor get grayText => throw _systemColorUnsupportedError();`
  public var grayText: SystemColor { _unsupportedSystemColor(name: "GrayText") }

  /// Returns system color named "Highlight".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1743-1748`
  /// **Original:** `SystemColor get highlight => throw _systemColorUnsupportedError();`
  public var highlight: SystemColor { _unsupportedSystemColor(name: "Highlight") }

  /// Returns system color named "HighlightText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1750-1755`
  /// **Original:** `SystemColor get highlightText => throw _systemColorUnsupportedError();`
  public var highlightText: SystemColor { _unsupportedSystemColor(name: "HighlightText") }

  /// Returns system color named "LinkText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1757-1762`
  /// **Original:** `SystemColor get linkText => throw _systemColorUnsupportedError();`
  public var linkText: SystemColor { _unsupportedSystemColor(name: "LinkText") }

  /// Returns system color named "Mark".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1764-1769`
  /// **Original:** `SystemColor get mark => throw _systemColorUnsupportedError();`
  public var mark: SystemColor { _unsupportedSystemColor(name: "Mark") }

  /// Returns system color named "MarkText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1771-1776`
  /// **Original:** `SystemColor get markText => throw _systemColorUnsupportedError();`
  public var markText: SystemColor { _unsupportedSystemColor(name: "MarkText") }

  /// Returns system color named "SelectedItem".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1778-1783`
  /// **Original:** `SystemColor get selectedItem => throw _systemColorUnsupportedError();`
  public var selectedItem: SystemColor { _unsupportedSystemColor(name: "SelectedItem") }

  /// Returns system color named "SelectedItemText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1785-1790`
  /// **Original:** `SystemColor get selectedItemText => throw _systemColorUnsupportedError();`
  public var selectedItemText: SystemColor { _unsupportedSystemColor(name: "SelectedItemText") }

  /// Returns system color named "VisitedText".
  ///
  /// See also:
  ///   * https://drafts.csswg.org/css-color/#css-system-colors
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1792-1797`
  /// **Original:** `SystemColor get visitedText => throw _systemColorUnsupportedError();`
  public var visitedText: SystemColor { _unsupportedSystemColor(name: "VisitedText") }
}

// MARK: - ViewFocusChangeCallback

/// Signature for [PlatformDispatcher.onViewFocusChange].
///
/// **Dart Source:** `platform_dispatcher.dart:3042`
/// **Original:** `typedef ViewFocusChangeCallback = void Function(ViewFocusEvent viewFocusEvent);`
public typealias ViewFocusChangeCallback = (ViewFocusEvent) -> Void

// MARK: - FrameData

/// Data associated with the current frame.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/window.dart:1100-1110`
/// **Original:** `class FrameData`
///
/// DIFFERENCE FROM DART: Uses struct instead of class for value semantics.
/// REASON: Swift idiomatic approach for simple data containers.
public struct FrameData: Sendable {
  /// The number of the current frame.
  ///
  /// This number monotonically increases, but doesn't necessarily
  /// start at a particular value.
  ///
  /// If not provided, defaults to -1.
  ///
  /// **Dart Source:** `window.dart:1109`
  /// **Original:** `final int frameNumber;`
  public let frameNumber: Int

  /// **Dart Source:** `window.dart:1101`
  /// **Original:** `const FrameData._({this.frameNumber = -1});`
  internal init(frameNumber: Int = -1) {
    self.frameNumber = frameNumber
  }
}

// MARK: - PlatformDispatcher

/// Platform event dispatcher singleton.
///
/// The most basic interface to the host operating system's interface.
///
/// This is the central entry point for platform messages and configuration
/// events from the platform.
///
/// It exposes the core scheduler API, the input event callback, the graphics
/// drawing API, and other such core services.
///
/// It manages the list of the application's [views] as well as the
/// [configuration] of various platform attributes.
///
/// **Dart Source:** `platform_dispatcher.dart:104-1553`
/// **Original:** `class PlatformDispatcher`
/// **Status:** MINIMAL STUB - Core structure with callback properties
///
/// DIFFERENCE FROM DART: This is a simplified stub implementation.
/// REASON: Full PlatformDispatcher migration is complex. This stub provides
/// the basic structure needed for framework compilation. Platform messaging,
/// zone-aware callback invocation, and many native calls are deferred.
///
/// Key differences from Dart:
/// - No Dart Zone support (callbacks invoked directly, not in registration zone)
/// - Platform messaging skipped (sendPlatformMessage, channelBuffers, etc.)
/// - Many internal engine-callback methods (_beginFrame, _drawFrame, etc.) are stubbed
/// - No pointer data packet unpacking
/// - No key data channel listener
/// - Font size scaling is simplified (no memoization with configurationId)
public class PlatformDispatcher {

  // MARK: - C++ Bridge

  /// C++ bridge object for engine interaction.
  private let bridge: flutter.swift_bridge.PlatformDispatcherBridge

  // MARK: - Singleton

  /// The [PlatformDispatcher] singleton.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:148-149`
  /// **Original:**
  /// ```dart
  /// static PlatformDispatcher get instance => _instance;
  /// static final PlatformDispatcher _instance = PlatformDispatcher._();
  /// ```
  ///
  /// Consider avoiding static references to this singleton through
  /// [PlatformDispatcher.instance] and instead prefer using a binding for
  /// dependency resolution such as `WidgetsBinding.instance.platformDispatcher`.
  nonisolated(unsafe) public static let instance: PlatformDispatcher = PlatformDispatcher()

  /// Private constructor, since only dart:ui is supposed to create one of
  /// these. Use [instance] to access the singleton.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:125-127`
  /// **Original:** `PlatformDispatcher._() { _setNeedsReportTimings = _nativeSetNeedsReportTimings; }`
  ///
  /// DIFFERENCE FROM DART: Does not set up _setNeedsReportTimings function.
  /// REASON: Native timing reporting deferred to later implementation phase.
  private init() {
    self.bridge = flutter.swift_bridge.PlatformDispatcherBridge()
    self._configuration = PlatformConfiguration()
    // Set the implicit view ID to match kFlutterImplicitViewId (0).
    // In Dart, this is set by the engine during DartUI_DartLifecycle_Initialize
    // via Dart_SetField(dart_ui, "_implicitViewId", kFlutterImplicitViewId).
    self._implicitViewId = 0
  }

  // MARK: - Configuration

  /// Internal platform configuration state.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:151`
  /// **Original:** `_PlatformConfiguration _configuration = const _PlatformConfiguration();`
  internal var _configuration: PlatformConfiguration

  /// Called when the platform configuration changes.
  ///
  /// The engine invokes this callback in the same zone in which the callback
  /// was set.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:157-163`
  ///
  /// DIFFERENCE FROM DART: No zone tracking for callback invocation.
  /// REASON: Swift has no Zone concept. Callbacks are invoked directly.
  public var onPlatformConfigurationChanged: VoidCallback?

  // MARK: - Display and View Management

  /// Internal display storage.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:183`
  /// **Original:** `final Map<int, Display> _displays = <int, Display>{};`
  private var _displays: [Int: Display] = [:]

  /// Internal view storage.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:190`
  /// **Original:** `final Map<int, FlutterView> _views = <int, FlutterView>{};`
  private var _views: [Int: FlutterView] = [:]

  /// The implicit view ID, set by the engine for single-view platforms.
  ///
  /// **Dart Source:** `engine/src/flutter/lib/ui/natives.dart:121`
  /// **Original:** `int? _implicitViewId;`
  ///
  /// DIFFERENCE FROM DART: Stored as a property on PlatformDispatcher instead of
  /// a top-level variable in natives.dart.
  /// REASON: In Swift, there is no top-level mutable state shared with the engine.
  internal var _implicitViewId: Int?

  /// The current list of displays.
  ///
  /// If any of their configurations change, [onMetricsChanged] will be called.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:165-183`
  /// **Original:** `Iterable<Display> get displays => _displays.values;`
  public var displays: [Display] {
    Array(_displays.values)
  }

  /// The current list of views, including top level platform windows used by
  /// the application.
  ///
  /// If any of their configurations change, [onMetricsChanged] will be called.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:185-190`
  /// **Original:** `Iterable<FlutterView> get views => _views.values;`
  public var views: [FlutterView] {
    Array(_views.values)
  }

  /// Returns the [Display] with the provided ID if one exists, or nil otherwise.
  ///
  /// **Dart Source:** Internal access to `_displays` map used by FlutterView.display.
  /// **Original:** `platformDispatcher._displays[_viewConfiguration.displayId]!`
  ///
  /// This is an internal method for FlutterView to access displays by ID.
  /// External users should use the `displays` property to iterate all displays.
  internal func _display(id: Int) -> Display? {
    _displays[id]
  }

  /// Returns the [FlutterView] with the provided ID if one exists, or nil
  /// otherwise.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:192-194`
  /// **Original:** `FlutterView? view({required int id}) => _views[id];`
  public func view(id: Int) -> FlutterView? {
    _views[id]
  }

  /// The [FlutterView] provided by the engine if the platform is unable to
  /// create windows, or, for backwards compatibility.
  ///
  /// If the platform provides an implicit view, it can be used to bootstrap
  /// the framework. This is common for platforms designed for single-view
  /// applications like mobile devices with a single display.
  ///
  /// Applications and libraries must not rely on this property being set
  /// as it may be nil depending on the engine's configuration.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:196-245`
  /// **Original:** `FlutterView? get implicitView { ... }`
  ///
  /// DIFFERENCE FROM DART: Simplified without debug assertions about immutability.
  /// REASON: Debug assertion tracking deferred to later implementation.
  public var implicitView: FlutterView? {
    guard let implicitId = _implicitViewId else {
      return nil
    }
    return _views[implicitId]
  }

  /// Opaque engine identifier for the engine running current isolate.
  /// Can be used in native code to retrieve the engine instance.
  /// The identifier is valid while the isolate is running.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:308-313`
  /// **Original:** `int? get engineId => _engineId;`
  public var engineId: Int? {
    let id = Int(bridge.GetEngineId())
    return id == 0 ? nil : id
  }

  // MARK: - View/Display Update Methods (Called from engine)

  /// Adds a new view with the specific view configuration.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:282-286`
  /// **Original:**
  /// ```dart
  /// void _addView(int id, _ViewConfiguration viewConfiguration) {
  ///   assert(!_views.containsKey(id));
  ///   _views[id] = FlutterView._(id, this, viewConfiguration);
  ///   _invoke(onMetricsChanged, _onMetricsChangedZone);
  /// }
  /// ```
  package func _addView(_ id: Int, _ viewConfiguration: ViewConfiguration) {
    assert(_views[id] == nil, "View ID \(id) already exists.")
    _views[id] = FlutterView(
      viewId: id,
      platformDispatcher: self,
      viewConfiguration: viewConfiguration
    )
    onMetricsChanged?()
  }

  /// Removes the specific view.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:294-302`
  /// **Original:** `void _removeView(int id) { ... }`
  package func _removeView(_ id: Int) {
    assert(id != _implicitViewId, "The implicit view #\(id) can not be removed.")
    if id == _implicitViewId {
      return
    }
    assert(_views[id] != nil, "View ID \(id) does not exist.")
    _views.removeValue(forKey: id)
    onMetricsChanged?()
  }

  /// Updates the metrics of the view with the given id.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:326-333`
  /// **Original:**
  /// ```dart
  /// void _updateWindowMetrics(int viewId, _ViewConfiguration viewConfiguration) {
  ///   assert(_views.containsKey(viewId), 'View $viewId does not exist.');
  ///   _views[viewId]!._viewConfiguration = viewConfiguration;
  ///   _invoke(onMetricsChanged, _onMetricsChangedZone);
  /// }
  /// ```
  package func _updateWindowMetrics(_ viewId: Int, _ viewConfiguration: ViewConfiguration) {
    assert(_views[viewId] != nil, "View \(viewId) does not exist.")
    _views[viewId]?.viewConfiguration = viewConfiguration
    onMetricsChanged?()
  }

  /// Updates the available displays.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:318-324`
  /// **Original:** `void _updateDisplays(List<Display> displays) { ... }`
  package func _updateDisplays(_ displays: [Display]) {
    _displays.removeAll()
    for display in displays {
      _displays[display.id] = display
    }
    onMetricsChanged?()
  }

  /// Sends a view focus event to the registered callback.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:304-306`
  /// **Original:** `void _sendViewFocusEvent(ViewFocusEvent event) { ... }`
  package func _sendViewFocusEvent(_ event: ViewFocusEvent) {
    onViewFocusChange?(event)
  }

  // MARK: - Callbacks

  /// A callback invoked whenever the [ViewConfiguration] of any of the
  /// [views] changes.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:250-274`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onMetricsChanged => _onMetricsChanged;
  /// VoidCallback? _onMetricsChanged;
  /// ```
  public var onMetricsChanged: VoidCallback?

  /// A callback invoked immediately after the focus is transitioned across
  /// [FlutterView]s.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:335-376`
  /// **Original:**
  /// ```dart
  /// ViewFocusChangeCallback? get onViewFocusChange => _onViewFocusChange;
  /// ViewFocusChangeCallback? _onViewFocusChange;
  /// ```
  public var onViewFocusChange: ViewFocusChangeCallback?

  /// A callback invoked when any view begins a frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:406-422`
  /// **Original:**
  /// ```dart
  /// FrameCallback? get onBeginFrame => _onBeginFrame;
  /// FrameCallback? _onBeginFrame;
  /// ```
  public var onBeginFrame: FrameCallback?

  /// A callback that is invoked for each frame after [onBeginFrame] has
  /// completed and after the microtask queue has been drained.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:429-440`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onDrawFrame => _onDrawFrame;
  /// VoidCallback? _onDrawFrame;
  /// ```
  public var onDrawFrame: VoidCallback?

  /// A callback that is invoked when pointer data is available.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:447-462`
  /// **Original:**
  /// ```dart
  /// PointerDataPacketCallback? get onPointerDataPacket => _onPointerDataPacket;
  /// PointerDataPacketCallback? _onPointerDataPacket;
  /// ```
  public var onPointerDataPacket: PointerDataPacketCallback?

  /// A callback that is invoked when key data is available.
  ///
  /// The callback should return true if the key event has been handled by the
  /// framework and should not be propagated further.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:548-564`
  /// **Original:**
  /// ```dart
  /// KeyDataCallback? get onKeyData => _onKeyData;
  /// KeyDataCallback? _onKeyData;
  /// ```
  ///
  /// DIFFERENCE FROM DART: Does not register/unregister channelBuffers listener.
  /// REASON: ChannelBuffers integration deferred to later implementation.
  public var onKeyData: KeyDataCallback?

  /// A callback that is invoked to report the [FrameTiming] of recently
  /// rasterized frames.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:596-626`
  /// **Original:**
  /// ```dart
  /// TimingsCallback? get onReportTimings => _onReportTimings;
  /// TimingsCallback? _onReportTimings;
  /// ```
  ///
  /// DIFFERENCE FROM DART: Does not call _setNeedsReportTimings when callback changes.
  /// REASON: Native timing reporting integration deferred to later implementation.
  public var onReportTimings: TimingsCallback?

  /// Deprecated. Migrate to ChannelBuffers.setListener instead.
  ///
  /// Called whenever this platform dispatcher receives a message from a
  /// platform-specific plugin.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:739-768`
  /// **Original:**
  /// ```dart
  /// PlatformMessageCallback? get onPlatformMessage => _onPlatformMessage;
  /// PlatformMessageCallback? _onPlatformMessage;
  /// ```
  @available(*, deprecated, message: "Migrate to ChannelBuffers.setListener instead. This feature was deprecated after v3.11.0-20.0.pre.")
  public var onPlatformMessage: PlatformMessageCallback?

  /// A callback that is invoked when the value of [accessibilityFeatures]
  /// changes.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:917-928`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onAccessibilityFeaturesChanged => _onAccessibilityFeaturesChanged;
  /// VoidCallback? _onAccessibilityFeaturesChanged;
  /// ```
  public var onAccessibilityFeaturesChanged: VoidCallback?

  /// A callback that is invoked whenever [locale] changes value.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1041-1056`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onLocaleChanged => _onLocaleChanged;
  /// VoidCallback? _onLocaleChanged;
  /// ```
  public var onLocaleChanged: VoidCallback?

  /// A callback that is invoked whenever [textScaleFactor] changes value.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1138-1153`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onTextScaleFactorChanged => _onTextScaleFactorChanged;
  /// VoidCallback? _onTextScaleFactorChanged;
  /// ```
  public var onTextScaleFactorChanged: VoidCallback?

  /// A callback that is invoked whenever [platformBrightness] changes value.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1186-1201`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onPlatformBrightnessChanged => _onPlatformBrightnessChanged;
  /// VoidCallback? _onPlatformBrightnessChanged;
  /// ```
  public var onPlatformBrightnessChanged: VoidCallback?

  /// A callback that is invoked whenever [systemFontFamily] changes value.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1206-1221`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onSystemFontFamilyChanged => _onSystemFontFamilyChanged;
  /// VoidCallback? _onSystemFontFamilyChanged;
  /// ```
  public var onSystemFontFamilyChanged: VoidCallback?

  /// A callback that is invoked when the value of [semanticsEnabled] changes.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1300-1310`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onSemanticsEnabledChanged => _onSemanticsEnabledChanged;
  /// VoidCallback? _onSemanticsEnabledChanged;
  /// ```
  public var onSemanticsEnabledChanged: VoidCallback?

  /// A callback that is invoked whenever the user requests an action to be
  /// performed on a semantics node.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1323-1337`
  /// **Original:**
  /// ```dart
  /// SemanticsActionEventCallback? get onSemanticsActionEvent => _onSemanticsActionEvent;
  /// SemanticsActionEventCallback? _onSemanticsActionEvent;
  /// ```
  public var onSemanticsActionEvent: SemanticsActionEventCallback?

  /// A callback that is invoked when the window updates the [FrameData].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1353-1360`
  /// **Original:**
  /// ```dart
  /// VoidCallback? get onFrameDataChanged => _onFrameDataChanged;
  /// VoidCallback? _onFrameDataChanged;
  /// ```
  public var onFrameDataChanged: VoidCallback?

  /// A callback that is invoked when an unhandled error occurs in the root
  /// isolate.
  ///
  /// This callback must return `true` if it has handled the error. Otherwise,
  /// it must return `false` and a fallback mechanism such as printing to stderr
  /// will be used.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1376-1399`
  /// **Original:**
  /// ```dart
  /// ErrorCallback? get onError => _onError;
  /// set onError(ErrorCallback? callback) { ... }
  /// ```
  ///
  /// DIFFERENCE FROM DART: No zone tracking for error callback.
  /// REASON: Swift has no Zone concept.
  public var onError: ErrorCallback?

  // MARK: - Configuration Accessors

  /// Additional accessibility features that may be enabled by the platform.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:915`
  /// **Original:** `AccessibilityFeatures get accessibilityFeatures => _configuration.accessibilityFeatures;`
  public var accessibilityFeatures: AccessibilityFeatures {
    _configuration.accessibilityFeatures
  }

  /// The system-reported default locale of the device.
  ///
  /// This is the first locale selected by the user and is the user's primary
  /// locale. This is equivalent to `locales.first`, except that it will provide
  /// an undefined (using the language tag "und") non-nil locale if the [locales]
  /// list has not been set or is empty.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:966-977`
  /// **Original:** `Locale get locale => locales.isEmpty ? const Locale.fromSubtags() : locales.first;`
  public var locale: Locale {
    locales.isEmpty ? Locale(fromSubtags: "und") : locales[0]
  }

  /// The full system-reported supported locales of the device.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:988-1003`
  /// **Original:** `List<Locale> get locales => _configuration.locales;`
  public var locales: [Locale] {
    _configuration.locales
  }

  /// The setting indicating whether time should always be shown in the 24-hour
  /// format.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1118-1122`
  /// **Original:** `bool get alwaysUse24HourFormat => _configuration.alwaysUse24HourFormat;`
  public var alwaysUse24HourFormat: Bool {
    _configuration.alwaysUse24HourFormat
  }

  /// The system-reported text scale.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1124-1136`
  /// **Original:** `double get textScaleFactor => _configuration.textScaleFactor;`
  public var textScaleFactor: Double {
    _configuration.textScaleFactor
  }

  /// The setting indicating the current brightness mode of the host platform.
  /// If the platform has no preference, [platformBrightness] defaults to
  /// [Brightness.light].
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1181-1184`
  /// **Original:** `Brightness get platformBrightness => _configuration.platformBrightness;`
  public var platformBrightness: Brightness {
    _configuration.platformBrightness
  }

  /// The setting indicating the current system font of the host platform.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1203-1204`
  /// **Original:** `String? get systemFontFamily => _configuration.systemFontFamily;`
  public var systemFontFamily: String? {
    _configuration.systemFontFamily
  }

  /// Whether the spell check service is supported on the current platform.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1155-1161`
  /// **Original:** `bool get nativeSpellCheckServiceDefined => _nativeSpellCheckServiceDefined;`
  public private(set) var nativeSpellCheckServiceDefined: Bool = false

  /// Whether showing system context menu is supported on the current platform.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1163-1169`
  /// **Original:** `bool get supportsShowingSystemContextMenu => _supportsShowingSystemContextMenu;`
  public private(set) var supportsShowingSystemContextMenu: Bool = false

  /// Whether briefly displaying the characters as you type in obscured text
  /// fields is enabled in system settings.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1171-1179`
  /// **Original:** `bool get brieflyShowPassword => _brieflyShowPassword;`
  public private(set) var brieflyShowPassword: Bool = true

  /// Whether the user has requested that updateSemantics be called when the
  /// semantic contents of a view changes.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1293-1298`
  /// **Original:** `bool get semanticsEnabled => _configuration.semanticsEnabled;`
  public var semanticsEnabled: Bool {
    _configuration.semanticsEnabled
  }

  /// The [FrameData] object for the current frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1349-1351`
  /// **Original:** `FrameData get frameData => _frameData;`
  public private(set) var frameData: FrameData = FrameData()

  /// The lifecycle state immediately after dart isolate initialization.
  ///
  /// This property will not be updated as the lifecycle changes.
  ///
  /// It is used to initialize [SchedulerBinding.lifecycleState] at startup with
  /// any buffered lifecycle state events.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1091-1107`
  /// **Original:** `String get initialLifecycleState { ... }`
  ///
  /// DIFFERENCE FROM DART: Does not track access state to stop updates after first read.
  /// REASON: Simplified for initial stub. Full lifecycle management deferred.
  public private(set) var initialLifecycleState: String = ""

  // MARK: - Frame Scheduling

  /// Requests that, at the next appropriate opportunity, the [onBeginFrame] and
  /// [onDrawFrame] callbacks be invoked.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:866-878`
  /// **Original:** `void scheduleFrame() => _scheduleFrame();`
  public func scheduleFrame() {
    bridge.ScheduleFrame()
  }

  /// Schedule a frame to run as soon as possible, rather than waiting for the
  /// engine to request a frame in response to a system "Vsync" signal.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:880-912`
  /// **Original:** `void scheduleWarmUpFrame({required VoidCallback beginFrame, required VoidCallback drawFrame}) { ... }`
  ///
  /// DIFFERENCE FROM DART: Calls callbacks synchronously instead of via Timer.run.
  /// REASON: Swift has no Dart Timer.run equivalent. The Dart version uses Timer.run
  /// to ensure microtasks flush between beginFrame and drawFrame. This stub calls
  /// them directly. Full deferred execution support will be added later.
  public func scheduleWarmUpFrame(beginFrame: VoidCallback, drawFrame: VoidCallback) {
    beginFrame()
    drawFrame()
    // Note: _endWarmUpFrame() native call deferred to later implementation
  }

  /// Requests a focus change of the [FlutterView] with the given ID.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:378-404`
  /// **Original:** `void requestViewFocusChange({required int viewId, required ViewFocusState state, required ViewFocusDirection direction}) { ... }`
  ///
  /// DIFFERENCE FROM DART: No-op stub. The Dart version calls
  /// PlatformConfigurationNativeApi::RequestViewFocusChange.
  /// REASON: Native call deferred to later implementation via C++ bridge.
  public func requestViewFocusChange(
    viewId: Int,
    state: ViewFocusState,
    direction: ViewFocusDirection
  ) {
    // Stub - native RequestViewFocusChange call deferred
  }

  /// Sets the locale for the application in engine.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:979-986`
  /// **Original:** `void setApplicationLocale(Locale locale) => _setApplicationLocale(locale.toLanguageTag());`
  ///
  /// DIFFERENCE FROM DART: No-op stub. The Dart version calls
  /// PlatformConfigurationNativeApi::SetApplicationLocale.
  /// REASON: Native call deferred to later implementation via C++ bridge.
  public func setApplicationLocale(_ locale: Locale) {
    // Stub - native SetApplicationLocale call deferred
  }

  /// Performs the platform-native locale resolution.
  ///
  /// Each platform may return different results.
  ///
  /// If the platform fails to resolve a locale, then this will return nil.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1005-1039`
  /// **Original:** `Locale? computePlatformResolvedLocale(List<Locale> supportedLocales) { ... }`
  ///
  /// DIFFERENCE FROM DART: Always returns nil (stub).
  /// REASON: Native ComputePlatformResolvedLocale call deferred to later implementation.
  public func computePlatformResolvedLocale(_ supportedLocales: [Locale]) -> Locale? {
    // Stub - native ComputePlatformResolvedLocale call deferred
    return nil
  }

  /// Informs the engine whether the framework is generating a semantics tree.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:719-737`
  /// **Original:** `void setSemanticsTreeEnabled(bool enabled) => _setSemanticsTreeEnabled(enabled);`
  ///
  /// DIFFERENCE FROM DART: No-op stub.
  /// REASON: Native SetSemanticsTreeEnabled call deferred to later implementation.
  public func setSemanticsTreeEnabled(_ enabled: Bool) {
    // Stub - native SetSemanticsTreeEnabled call deferred
  }

  /// Set the debug name associated with this platform dispatcher's root
  /// isolate.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:825-837`
  /// **Original:** `void setIsolateDebugName(String name) => _setIsolateDebugName(name);`
  ///
  /// DIFFERENCE FROM DART: No-op stub.
  /// REASON: Native SetIsolateDebugName call deferred. No isolate concept in Swift.
  public func setIsolateDebugName(_ name: String) {
    // Stub - no isolate concept in Swift
  }

  /// Requests the Dart VM to adjust the GC heuristics based on the requested performance mode.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:839-850`
  /// **Original:** `void requestDartPerformanceMode(DartPerformanceMode mode) { ... }`
  ///
  /// DIFFERENCE FROM DART: No-op stub.
  /// REASON: No Dart VM GC heuristics in Swift. Performance tuning deferred.
  public func requestDartPerformanceMode(_ mode: DartPerformanceMode) {
    // Stub - no Dart VM GC heuristics in Swift
  }

  /// The embedder can specify data that the isolate can request synchronously
  /// on launch. This accessor fetches that data.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:852-864`
  /// **Original:** `ByteData? getPersistentIsolateData() => _getPersistentIsolateData();`
  ///
  /// DIFFERENCE FROM DART: Always returns nil (stub).
  /// REASON: Native GetPersistentIsolateData call deferred to later implementation.
  public func getPersistentIsolateData() -> Data? {
    // Stub - native GetPersistentIsolateData call deferred
    return nil
  }

  /// The route or path that the embedder requested when the application was
  /// launched.
  ///
  /// This will be the string "/" if no particular route was requested.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1419-1452`
  /// **Original:** `String get defaultRouteName => _defaultRouteName();`
  ///
  /// DIFFERENCE FROM DART: Returns "/" stub instead of calling native method.
  /// REASON: C++ bridge GetDefaultRouteName returns const char* which Swift C++ interop
  /// cannot bridge (interior pointer issue). Will be fixed when bridge returns std::string.
  public var defaultRouteName: String {
    // Stub - C++ bridge method returns const char* which is not bridgeable
    // TODO: Fix bridge to return std::string or use a different approach
    return "/"
  }

  /// Sends a message to a platform-specific plugin.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:645-678`
  /// **Original:** `void sendPlatformMessage(String name, ByteData? data, PlatformMessageResponseCallback? callback) { ... }`
  ///
  /// DIFFERENCE FROM DART: No-op stub. The Dart version calls
  /// PlatformConfigurationNativeApi::SendPlatformMessage.
  /// REASON: Platform messaging deferred to later implementation.
  public func sendPlatformMessage(_ name: String, _ data: Data?, _ callback: PlatformMessageResponseCallback?) {
    if let sender = platformMessageSender {
      sender(name, data, callback)
    } else {
      callback?(nil)
    }
  }

  /// Installed by the Swift runtime once the engine hands it a sender;
  /// nil before that (and in tests), when every message answers nil.
  public var platformMessageSender: ((String, Data?, PlatformMessageResponseCallback?) -> Void)?

  /// Computes the scaled font size from the given `unscaledFontSize`, according
  /// to the user's platform preferences.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1454-1530`
  /// **Original:** `double scaleFontSize(double unscaledFontSize) { ... }`
  ///
  /// DIFFERENCE FROM DART: Simplified implementation using linear scaling only.
  /// REASON: The Dart version uses _getScaledFontSize native call with configurationId
  /// for non-linear scaling on Android SDK 34+. This stub uses simple multiplication.
  public func scaleFontSize(_ unscaledFontSize: Double) -> Double {
    assert(unscaledFontSize >= 0)
    assert(unscaledFontSize.isFinite)
    return unscaledFontSize * textScaleFactor
  }

  // MARK: - Internal Update Methods (Called from engine via hooks)

  /// Called from the engine to begin a frame.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:424-427`
  /// **Original:** `void _beginFrame(int microseconds) { ... }`
  package func _beginFrame(_ microseconds: Int) {
    onBeginFrame?(.microseconds(Int64(microseconds)))
  }

  /// Called from the engine after begin frame and microtasks are drained.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:442-445`
  /// **Original:** `void _drawFrame() { ... }`
  package func _drawFrame() {
    onDrawFrame?()
  }

  /// Called from the engine to report frame timings.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:636-643`
  /// **Original:** `void _reportTimings(List<int> timings) { ... }`
  package func _reportTimings(_ timings: [Int]) {
    let dataLength = FramePhase.allCases.count + FrameTimingInfo.allCases.count
    assert(timings.count % dataLength == 0)
    var frameTimings: [FrameTiming] = []
    var i = 0
    while i < timings.count {
      frameTimings.append(FrameTiming(Array(timings[i..<(i + dataLength)])))
      i += dataLength
    }
    onReportTimings?(frameTimings)
  }

  /// Called from the engine to update accessibility features.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:931-940`
  /// **Original:** `void _updateAccessibilityFeatures(int values) { ... }`
  package func _updateAccessibilityFeatures(_ values: Int) {
    let newFeatures = AccessibilityFeatures(values)
    let previousConfiguration = _configuration
    if newFeatures == previousConfiguration.accessibilityFeatures {
      return
    }
    _configuration = previousConfiguration.copyWith(accessibilityFeatures: newFeatures)
    onPlatformConfigurationChanged?()
    onAccessibilityFeaturesChanged?()
  }

  /// Called from the engine to update locale information.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1059-1086`
  /// **Original:** `void _updateLocales(List<String> locales) { ... }`
  package func _updateLocales(_ locales: [String]) {
    let stringsPerLocale = 4
    let numLocales = locales.count / stringsPerLocale
    let previousConfiguration = _configuration
    var newLocales: [Locale] = []
    var localesDiffer = numLocales != previousConfiguration.locales.count
    for localeIndex in 0..<numLocales {
      let countryCode = locales[localeIndex * stringsPerLocale + 1]
      let scriptCode = locales[localeIndex * stringsPerLocale + 2]

      newLocales.append(
        Locale(
          fromSubtags: locales[localeIndex * stringsPerLocale],
          scriptCode: scriptCode.isEmpty ? nil : scriptCode,
          countryCode: countryCode.isEmpty ? nil : countryCode
        )
      )
      if !localesDiffer && newLocales[localeIndex] != previousConfiguration.locales[localeIndex] {
        localesDiffer = true
      }
    }
    if !localesDiffer {
      return
    }
    _configuration = previousConfiguration.copyWith(locales: newLocales)
    onPlatformConfigurationChanged?()
    onLocaleChanged?()
  }

  /// Called from the engine to update user settings (text scale, brightness, etc.).
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1224-1291`
  /// **Original:** `void _updateUserSettingsData(String jsonData) { ... }`
  ///
  /// DIFFERENCE FROM DART: Simplified; does not parse JSON from engine.
  /// REASON: JSON parsing from engine deferred; settings updated via typed methods instead.
  package func _updateUserSettings(
    textScaleFactor: Double,
    alwaysUse24HourFormat: Bool,
    platformBrightness: Brightness,
    systemFontFamily: String?,
    nativeSpellCheckServiceDefined: Bool? = nil,
    supportsShowingSystemContextMenu: Bool? = nil,
    brieflyShowPassword: Bool? = nil,
    configurationId: Int? = nil
  ) {
    if let value = nativeSpellCheckServiceDefined {
      self.nativeSpellCheckServiceDefined = value
    }
    if let value = supportsShowingSystemContextMenu {
      self.supportsShowingSystemContextMenu = value
    }
    if let value = brieflyShowPassword {
      self.brieflyShowPassword = value
    }

    let previousConfiguration = _configuration
    let platformBrightnessChanged = previousConfiguration.platformBrightness != platformBrightness
    let textScaleFactorChanged = previousConfiguration.textScaleFactor != textScaleFactor
    let systemFontFamilyChanged = previousConfiguration.systemFontFamily != systemFontFamily

    if !platformBrightnessChanged && !textScaleFactorChanged &&
       previousConfiguration.alwaysUse24HourFormat == alwaysUse24HourFormat &&
       !systemFontFamilyChanged && configurationId == nil {
      return
    }

    _configuration = previousConfiguration.copyWith(
      alwaysUse24HourFormat: alwaysUse24HourFormat,
      platformBrightness: platformBrightness,
      textScaleFactor: textScaleFactor,
      systemFontFamily: systemFontFamily,
      configurationId: configurationId
    )
    onPlatformConfigurationChanged?()
    if textScaleFactorChanged {
      onTextScaleFactorChanged?()
    }
    if platformBrightnessChanged {
      onPlatformBrightnessChanged?()
    }
    if systemFontFamilyChanged {
      onSystemFontFamilyChanged?()
    }
  }

  /// Called from the engine to update semantics enabled state.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1313-1321`
  /// **Original:** `void _updateSemanticsEnabled(bool enabled) { ... }`
  package func _updateSemanticsEnabled(_ enabled: Bool) {
    let previousConfiguration = _configuration
    if previousConfiguration.semanticsEnabled == enabled {
      return
    }
    _configuration = previousConfiguration.copyWith(semanticsEnabled: enabled)
    onPlatformConfigurationChanged?()
    onSemanticsEnabledChanged?()
  }

  /// Called from the engine to update frame data.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1340-1347`
  /// **Original:** `void _updateFrameData(int frameNumber) { ... }`
  package func _updateFrameData(_ frameNumber: Int) {
    if frameData.frameNumber == frameNumber {
      return
    }
    frameData = FrameData(frameNumber: frameNumber)
    onFrameDataChanged?()
  }

  /// Called from the engine to update the initial lifecycle state.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1110-1116`
  /// **Original:** `void _updateInitialLifecycleState(String state) { ... }`
  package func _updateInitialLifecycleState(_ state: String) {
    initialLifecycleState = state
  }

  /// Called from the engine to dispatch a semantics action.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1363-1374`
  /// **Original:** `void _dispatchSemanticsAction(int viewId, int nodeId, int action, ByteData? args) { ... }`
  package func _dispatchSemanticsAction(_ viewId: Int, _ nodeId: Int, _ action: Int, _ args: Data?) {
    guard let semanticsAction = SemanticsAction.fromIndex(action) else {
      return
    }
    onSemanticsActionEvent?(SemanticsActionEvent(
      type: semanticsAction,
      viewId: viewId,
      nodeId: nodeId,
      arguments: args
    ))
  }

  /// Convenience overload that accepts `[UInt8]` instead of Foundation's `Data`.
  ///
  /// This enables callers that cannot import Foundation (e.g., SwiftRuntime target
  /// for GN build integration) to dispatch semantics actions using pure Swift types.
  /// An empty array is treated as nil arguments.
  package func _dispatchSemanticsAction(_ viewId: Int, _ nodeId: Int, _ action: Int, _ args: [UInt8]) {
    let argsData: Data? = args.isEmpty ? nil : Data(args)
    _dispatchSemanticsAction(viewId, nodeId, action, argsData)
  }

  /// Dispatches an unhandled error.
  ///
  /// **Dart Source:** `platform_dispatcher.dart:1401-1417`
  /// **Original:** `bool _dispatchError(Object error, StackTrace stackTrace) { ... }`
  ///
  /// DIFFERENCE FROM DART: No zone-aware invocation.
  /// REASON: Swift has no Zone concept.
  package func _dispatchError(_ error: Error, _ stackTrace: String) -> Bool {
    guard let onError = onError else {
      return false
    }
    return onError(error, stackTrace)
  }
}
