// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Swift implementation of Flutter's channel_buffers.dart
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart`
///
/// This file provides the Swift implementation of the channel buffering
/// and dispatch mechanism for messages sent by plugins.

import Foundation
import FlutterSwiftBridgeCxx

// MARK: - Type Aliases

/// Deprecated. Migrate to [ChannelCallback] instead.
///
/// Signature for `ChannelBuffers.drain`'s `callback` argument.
///
/// The first argument is the data sent by the plugin.
///
/// The second argument is a closure that, when called, will send messages
/// back to the plugin.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:16-21`
/// **Original Name:** `DrainChannelCallback`
///
/// DIFFERENCE FROM DART: Uses Swift `Data?` instead of Dart `ByteData?`
/// REASON: Swift's Data type is the standard for binary data handling
@available(*, deprecated, message: "Migrate to ChannelCallback instead. This feature was deprecated after v3.11.0-20.0.pre.")
public typealias DrainChannelCallback = (Data?, @escaping (Data?) -> Void) async -> Void

/// Signature for `ChannelBuffers.setListener`'s `callback` argument.
///
/// The first argument is the data sent by the plugin.
///
/// The second argument is a closure that, when called, will send messages
/// back to the plugin.
///
/// See also:
///
///  * `PlatformMessageResponseCallback`, the type used for replies.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:23-33`
/// **Original Name:** `ChannelCallback`
///
/// DIFFERENCE FROM DART: Uses Swift `Data?` instead of Dart `ByteData?`
/// REASON: Swift's Data type is the standard for binary data handling
public typealias ChannelCallback = (Data?, @escaping (Data?) -> Void) -> Void

// MARK: - ChannelCallbackRecord

/// The data and logic required to store and invoke a callback.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:35-47`
/// **Original Name:** `_ChannelCallbackRecord`
///
/// This struct stores a callback and provides a method to invoke it.
struct ChannelCallbackRecord {
    /// Creates a ChannelCallbackRecord with the given callback.
    ///
    /// **Dart Source:** `channel_buffers.dart:39`
    /// **Original:** `_ChannelCallbackRecord(this._callback) : _zone = Zone.current`
    ///
    /// - Parameter callback: The callback to store and invoke later.
    init(_ callback: @escaping ChannelCallback) {
        self.callback = callback
    }

    /// The stored callback.
    ///
    /// **Dart Source:** `channel_buffers.dart:40`
    /// **Original:** `final ChannelCallback _callback`
    let callback: ChannelCallback

    // DIFFERENCE FROM DART: Zone removed - Swift has no Zone concept
    // DART SOURCE: channel_buffers.dart:41 - `final Zone _zone`
    // The Dart implementation captures Zone.current to ensure callbacks
    // execute in the correct zone context. Swift does not have an
    // equivalent Zone concept, so callbacks are invoked directly.

    /// Call the callback with the given arguments.
    ///
    /// **Dart Source:** `channel_buffers.dart:43-46`
    /// **Original:**
    /// ```dart
    /// void invoke(ByteData? dataArg, PlatformMessageResponseCallback callbackArg) {
    ///   _invoke2<ByteData?, PlatformMessageResponseCallback>(_callback, _zone, dataArg, callbackArg);
    /// }
    /// ```
    ///
    /// DIFFERENCE FROM DART: Direct callback invocation instead of `_invoke2` with Zone
    /// REASON: Swift has no Zone concept; callbacks are invoked directly
    ///
    /// - Parameters:
    ///   - data: The data to pass to the callback.
    ///   - responseCallback: The response callback to pass to the callback.
    func invoke(data: Data?, callback responseCallback: @escaping (Data?) -> Void) {
        callback(data, responseCallback)
    }
}

// MARK: - StoredMessage

/// A saved platform message for a channel with its callback.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:49-71`
/// **Original Name:** `_StoredMessage`
///
/// This struct wraps the data and callback for a platform message.
struct StoredMessage {
    /// Wraps the data and callback for a platform message into
    /// a `StoredMessage` instance.
    ///
    /// **Dart Source:** `channel_buffers.dart:50-58`
    /// **Original:** `_StoredMessage(this.data, this._callback) : _zone = Zone.current`
    ///
    /// - Parameters:
    ///   - data: A `Data?` that represents the payload of the message.
    ///   - callback: A callback that will be called when the message is handled.
    init(data: Data?, callback: @escaping (Data?) -> Void) {
        self.data = data
        self.callback = callback
    }

    /// Representation of the message's payload.
    ///
    /// **Dart Source:** `channel_buffers.dart:60-61`
    /// **Original:** `final ByteData? data`
    ///
    /// DIFFERENCE FROM DART: Uses Swift `Data?` instead of Dart `ByteData?`
    /// REASON: Swift's Data type is the standard for binary data handling
    let data: Data?

    /// Callback to be used when replying to the message.
    ///
    /// **Dart Source:** `channel_buffers.dart:63-64`
    /// **Original:** `final PlatformMessageResponseCallback _callback`
    ///
    /// DIFFERENCE FROM DART: Uses Swift closure `(Data?) -> Void` instead of `PlatformMessageResponseCallback`
    /// REASON: Swift closure syntax is more idiomatic
    let callback: (Data?) -> Void

    // DIFFERENCE FROM DART: Zone removed - Swift has no Zone concept
    // DART SOURCE: channel_buffers.dart:66 - `final Zone _zone`
    // The Dart implementation captures Zone.current for callback invocation.
    // Swift does not have an equivalent Zone concept, so callbacks are invoked directly.

    /// Invoke the stored callback with the given data.
    ///
    /// **Dart Source:** `channel_buffers.dart:68-70`
    /// **Original:** `void invoke(ByteData? dataArg) { _invoke1(_callback, _zone, dataArg); }`
    ///
    /// DIFFERENCE FROM DART: Direct callback invocation instead of `_invoke1` with Zone
    /// REASON: Swift has no Zone concept; callbacks are invoked directly
    func invoke(dataArg: Data?) {
        callback(dataArg)
    }
}

// MARK: - Constants

/// Default buffer size for channel buffers.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:318-319`
/// **Original:** `static const int kDefaultBufferSize = 1`
///
/// This constant is also defined in the ChannelBuffers class, but is placed here
/// so that the Channel class can use it before ChannelBuffers is defined.
private let kDefaultChannelBufferSize: Int = 1

// MARK: - Channel

/// The internal storage for a platform channel.
///
/// This consists of a fixed-size queue of `StoredMessage`s,
/// and the channel's callback, if any has been registered.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:73-235`
/// **Original Name:** `_Channel`
///
/// DIFFERENCE FROM DART: Uses class instead of struct for reference semantics
/// REASON: The class has mutable state (_draining) and is passed by reference
///
/// DIFFERENCE FROM DART: Marked as @MainActor for thread safety
/// REASON: Swift 6 strict concurrency requires explicit thread isolation;
///         Flutter channel buffers are always accessed from the UI thread
@MainActor
class Channel {
    /// Creates a Channel with the given capacity.
    ///
    /// **Dart Source:** `channel_buffers.dart:78-79`
    /// **Original:** `_Channel([this._capacity = ChannelBuffers.kDefaultBufferSize])`
    ///
    /// - Parameter capacity: The initial capacity of the channel. Defaults to `kDefaultChannelBufferSize` (1).
    init(capacity: Int = kDefaultChannelBufferSize) {
        self._capacity = capacity
        // DIFFERENCE FROM DART: Using Array instead of ListQueue
        // REASON: Swift Array provides efficient append/removeFirst for typical message counts
        self._queue = []
        _queue.reserveCapacity(capacity)
    }

    /// The underlying data for the buffered messages.
    ///
    /// **Dart Source:** `channel_buffers.dart:81-82`
    /// **Original:** `final collection.ListQueue<_StoredMessage> _queue`
    ///
    /// DIFFERENCE FROM DART: Using Array<StoredMessage> instead of ListQueue<_StoredMessage>
    /// REASON: Swift Array is sufficient for typical channel buffer sizes and provides O(1) append
    private var _queue: [StoredMessage]

    /// The number of messages currently in the Channel.
    ///
    /// This is equal to or less than the `capacity`.
    ///
    /// **Dart Source:** `channel_buffers.dart:84-87`
    /// **Original:** `int get length => _queue.length`
    var length: Int {
        _queue.count
    }

    /// Whether to dump messages to the console when a message is
    /// discarded due to the channel overflowing.
    ///
    /// Has no effect in release builds.
    ///
    /// **Dart Source:** `channel_buffers.dart:89-93`
    /// **Original:** `bool debugEnableDiscardWarnings = true`
    var debugEnableDiscardWarnings: Bool = true

    /// The number of messages that _can_ be stored in the Channel.
    ///
    /// When additional messages are stored, earlier ones are discarded,
    /// in a first-in-first-out fashion.
    ///
    /// **Dart Source:** `channel_buffers.dart:95-100`
    /// **Original:** `int get capacity => _capacity`
    var capacity: Int {
        get { _capacity }
        set {
            _capacity = newValue
            _dropOverflowMessages(newValue)
        }
    }

    /// The backing storage for capacity.
    ///
    /// **Dart Source:** `channel_buffers.dart:100`
    /// **Original:** `int _capacity`
    private var _capacity: Int

    /// Whether a microtask is queued to call `drainStep`.
    ///
    /// This is used to queue messages received while draining, rather
    /// than sending them out of order. This generally cannot happen in
    /// production but is possible in test scenarios.
    ///
    /// This is also necessary to avoid situations where multiple drains are
    /// invoked simultaneously. For example, if a listener is set
    /// (queuing a drain), then unset, then set again (which would queue
    /// a drain again), all in one stack frame (not allowing the drain
    /// itself an opportunity to check if a listener is set).
    ///
    /// **Dart Source:** `channel_buffers.dart:113-124`
    /// **Original:** `bool _draining = false`
    private var _draining: Bool = false

    /// Adds a message to the channel.
    ///
    /// If the channel overflows, earlier messages are discarded, in a
    /// first-in-first-out fashion. See `capacity`. If
    /// `debugEnableDiscardWarnings` is true, this method returns true
    /// on overflow. It is the responsibility of the caller to show the
    /// warning message.
    ///
    /// **Dart Source:** `channel_buffers.dart:126-145`
    /// **Original:**
    /// ```dart
    /// bool push(_StoredMessage message) {
    ///   if (!_draining && _channelCallbackRecord != null) {
    ///     assert(_queue.isEmpty);
    ///     _channelCallbackRecord!.invoke(message.data, message.invoke);
    ///     return false;
    ///   }
    ///   if (_capacity <= 0) {
    ///     return debugEnableDiscardWarnings;
    ///   }
    ///   final bool result = _dropOverflowMessages(_capacity - 1);
    ///   _queue.addLast(message);
    ///   return result;
    /// }
    /// ```
    ///
    /// - Parameter message: The message to add.
    /// - Returns: `true` if overflow occurred and warnings are enabled, `false` otherwise.
    func push(_ message: StoredMessage) -> Bool {
        if !_draining, let record = _channelCallbackRecord {
            assert(_queue.isEmpty)
            record.invoke(data: message.data, callback: message.invoke)
            return false
        }
        if _capacity <= 0 {
            return debugEnableDiscardWarnings
        }
        let result = _dropOverflowMessages(_capacity - 1)
        _queue.append(message)
        return result
    }

    /// Returns the first message in the channel and removes it.
    ///
    /// Throws when empty.
    ///
    /// **Dart Source:** `channel_buffers.dart:147-150`
    /// **Original:** `_StoredMessage pop() => _queue.removeFirst()`
    ///
    /// - Returns: The first message in the queue.
    /// - Precondition: The queue must not be empty.
    func pop() -> StoredMessage {
        precondition(!_queue.isEmpty, "Cannot pop from an empty channel")
        return _queue.removeFirst()
    }

    /// Removes messages until `length` reaches `lengthLimit`.
    ///
    /// The callback of each removed message is invoked with nil
    /// as its argument.
    ///
    /// If any messages are removed, and `debugEnableDiscardWarnings` is
    /// true, then returns true. The caller is responsible for showing
    /// the warning message in that case.
    ///
    /// **Dart Source:** `channel_buffers.dart:152-168`
    /// **Original:**
    /// ```dart
    /// bool _dropOverflowMessages(int lengthLimit) {
    ///   bool result = false;
    ///   while (_queue.length > lengthLimit) {
    ///     final _StoredMessage message = _queue.removeFirst();
    ///     message.invoke(null); // send empty reply to the plugin side
    ///     result = true;
    ///   }
    ///   return result;
    /// }
    /// ```
    ///
    /// - Parameter lengthLimit: The maximum number of messages to keep.
    /// - Returns: `true` if any messages were removed and warnings are enabled, `false` otherwise.
    @discardableResult
    private func _dropOverflowMessages(_ lengthLimit: Int) -> Bool {
        var result = false
        while _queue.count > lengthLimit {
            let message = _queue.removeFirst()
            message.invoke(dataArg: nil)  // send empty reply to the plugin side
            result = true
        }
        return result && debugEnableDiscardWarnings
    }

    /// The channel callback record for this channel.
    ///
    /// **Dart Source:** `channel_buffers.dart:170`
    /// **Original:** `_ChannelCallbackRecord? _channelCallbackRecord`
    private var _channelCallbackRecord: ChannelCallbackRecord?

    /// Sets the listener for this channel.
    ///
    /// When there is a listener, messages are sent immediately.
    ///
    /// If any messages were queued before the listener is added,
    /// they are drained asynchronously after this method returns.
    /// (See `drain`.)
    ///
    /// Only one listener may be set at a time. Setting a
    /// new listener clears the previous one.
    ///
    /// Callbacks are invoked in their own stack frame and
    /// use the zone that was current when the callback was
    /// registered.
    ///
    /// **Dart Source:** `channel_buffers.dart:172-192`
    /// **Original:**
    /// ```dart
    /// void setListener(ChannelCallback callback) {
    ///   final bool needDrain = _channelCallbackRecord == null;
    ///   _channelCallbackRecord = _ChannelCallbackRecord(callback);
    ///   if (needDrain && !_draining) {
    ///     _drain();
    ///   }
    /// }
    /// ```
    ///
    /// DIFFERENCE FROM DART: Zone handling removed
    /// REASON: Swift has no Zone concept; callbacks are invoked directly
    ///
    /// - Parameter callback: The callback to invoke for each message.
    func setListener(_ callback: @escaping ChannelCallback) {
        let needDrain = _channelCallbackRecord == nil
        _channelCallbackRecord = ChannelCallbackRecord(callback)
        if needDrain && !_draining {
            _drain()
        }
    }

    /// Clears the listener for this channel.
    ///
    /// When there is no listener, messages are queued, up to `capacity`,
    /// and then discarded in a first-in-first-out fashion.
    ///
    /// **Dart Source:** `channel_buffers.dart:194-200`
    /// **Original:** `void clearListener() { _channelCallbackRecord = null; }`
    func clearListener() {
        _channelCallbackRecord = nil
    }

    /// Drains all the messages in the channel (invoking the currently
    /// registered listener for each one).
    ///
    /// Each message is handled in its own microtask. No messages can
    /// be queued by plugins while the queue is being drained, but any
    /// microtasks queued by the handler itself will be processed before
    /// the next message is handled.
    ///
    /// The draining stops if the listener is removed.
    ///
    /// See also:
    ///
    ///  * `setListener`, which is used to register the callback.
    ///  * `clearListener`, which removes it.
    ///
    /// **Dart Source:** `channel_buffers.dart:202-220`
    /// **Original:**
    /// ```dart
    /// void _drain() {
    ///   assert(!_draining);
    ///   _draining = true;
    ///   scheduleMicrotask(_drainStep);
    /// }
    /// ```
    ///
    /// DIFFERENCE FROM DART: Uses `DispatchQueue.main.async` instead of `scheduleMicrotask`
    /// REASON: Swift has no direct scheduleMicrotask equivalent; DispatchQueue.main.async
    ///         provides similar async execution semantics on the main thread
    private func _drain() {
        assert(!_draining)
        _draining = true
        DispatchQueue.main.async { [weak self] in
            self?._drainStep()
        }
    }

    /// Drains a single message and then reinvokes itself asynchronously.
    ///
    /// See `drain` for more details.
    ///
    /// **Dart Source:** `channel_buffers.dart:222-234`
    /// **Original:**
    /// ```dart
    /// void _drainStep() {
    ///   assert(_draining);
    ///   if (_queue.isNotEmpty && _channelCallbackRecord != null) {
    ///     final _StoredMessage message = pop();
    ///     _channelCallbackRecord!.invoke(message.data, message.invoke);
    ///     scheduleMicrotask(_drainStep);
    ///   } else {
    ///     _draining = false;
    ///   }
    /// }
    /// ```
    ///
    /// DIFFERENCE FROM DART: Uses `DispatchQueue.main.async` instead of `scheduleMicrotask`
    /// REASON: Swift has no direct scheduleMicrotask equivalent
    private func _drainStep() {
        assert(_draining)
        if !_queue.isEmpty, let record = _channelCallbackRecord {
            let message = pop()
            record.invoke(data: message.data, callback: message.invoke)
            DispatchQueue.main.async { [weak self] in
                self?._drainStep()
            }
        } else {
            _draining = false
        }
    }
}

// MARK: - ChannelBuffers

/// The buffering and dispatch mechanism for messages sent by plugins
/// on the engine side to their corresponding plugin code on the
/// framework side.
///
/// Messages for a channel are stored until a listener is provided for that channel,
/// using `setListener`. Only one listener may be configured per channel.
///
/// Typically these buffers are drained once a callback is set up on
/// the `BinaryMessenger` in the Flutter framework. (See `setListener`.)
///
/// ## Channel names
///
/// By convention, channels are normally named with a reverse-DNS prefix, a
/// slash, and then a domain-specific name. For example, `com.example/demo`.
///
/// Channel names cannot contain the U+0000 NULL character, because they
/// are passed through APIs that use null-terminated strings.
///
/// ## Buffer capacity and overflow
///
/// Each channel has a finite buffer capacity and messages will
/// be deleted in a first-in-first-out (FIFO) manner if the capacity is exceeded.
///
/// By default buffers store one message per channel, and when a
/// message overflows, in debug mode, a message is printed to the
/// console. The message looks like the following:
///
/// > A message on the com.example channel was discarded before it could be
/// > handled.
/// > This happens when a plugin sends messages to the framework side before the
/// > framework has had an opportunity to register a listener. See the
/// > ChannelBuffers API documentation for details on how to configure the channel
/// > to expect more messages, or to expect messages to get discarded:
/// >   https://api.flutter.dev/flutter/dart-ui/ChannelBuffers-class.html
///
/// There are tradeoffs associated with any size. The correct size
/// should be chosen for the semantics of the channel. To change the
/// size a plugin can send a message using the control channel,
/// as described below.
///
/// Size 0 is appropriate for channels where messages sent before
/// the engine and framework are ready should be ignored. For
/// example, a plugin that notifies the framework any time a
/// radiation sensor detects an ionization event might set its size
/// to zero since past ionization events are typically not
/// interesting, only instantaneous readings are worth tracking.
///
/// Size 1 is appropriate for level-triggered plugins. For example,
/// a plugin that notifies the framework of the current value of a
/// pressure sensor might leave its size at one (the default), while
/// sending messages continually; once the framework side of the plugin
/// registers with the channel, it will immediately receive the most
/// up to date value and earlier messages will have been discarded.
///
/// Sizes greater than one are appropriate for plugins where every
/// message is important. For example, a plugin that itself
/// registers with another system that has been buffering events,
/// and immediately forwards all the previously-buffered events,
/// would likely wish to avoid having any messages dropped on the
/// floor. In such situations, it is important to select a size that
/// will avoid overflows. It is also important to consider the
/// potential for the framework side to never fully initialize (e.g. if
/// the user starts the application, but terminates it soon
/// afterwards, leaving time for the platform side of a plugin to
/// run but not the framework side).
///
/// ## The control channel
///
/// A plugin can configure its channel's buffers by sending messages to the
/// control channel, `dev.flutter/channel-buffers` (see `kControlChannelName`).
///
/// There are two messages that can be sent to this control channel, to adjust
/// the buffer size and to disable the overflow warnings. See `handleMessage`
/// for details on these messages.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:237-631`
/// **Original Name:** `ChannelBuffers`
///
/// DIFFERENCE FROM DART: Marked as @MainActor for thread safety
/// REASON: Swift 6 strict concurrency requires explicit thread isolation;
///         Flutter channel buffers are always accessed from the UI thread
@MainActor
public class ChannelBuffers {
    /// Create a buffer pool for platform messages.
    ///
    /// It is generally not necessary to create an instance of this class;
    /// the global `channelBuffers` instance is the one used by the engine.
    ///
    /// **Dart Source:** `channel_buffers.dart:312-316`
    /// **Original:** `ChannelBuffers()`
    public init() {}

    /// The number of messages that channel buffers will store by default.
    ///
    /// **Dart Source:** `channel_buffers.dart:318-319`
    /// **Original:** `static const int kDefaultBufferSize = 1`
    public static let kDefaultBufferSize: Int = 1

    /// The name of the channel that plugins can use to communicate with the
    /// channel buffers system.
    ///
    /// These messages are handled by `handleMessage`.
    ///
    /// **Dart Source:** `channel_buffers.dart:321-325`
    /// **Original:** `static const String kControlChannelName = 'dev.flutter/channel-buffers'`
    public static let kControlChannelName: String = "dev.flutter/channel-buffers"

    /// A mapping between a channel name and its associated `Channel`.
    ///
    /// **Dart Source:** `channel_buffers.dart:327-328`
    /// **Original:** `final Map<String, _Channel> _channels = <String, _Channel>{}`
    private var _channels: [String: Channel] = [:]

    /// Adds a message (`data`) to the named channel buffer (`name`).
    ///
    /// The `callback` argument is a closure that, when called, will send messages
    /// back to the plugin.
    ///
    /// If a message overflows the channel, and the channel has not been
    /// configured to expect overflow, then, in debug mode, a message
    /// will be printed to the console warning about the overflow.
    ///
    /// Channel names cannot contain the U+0000 NULL character, because they
    /// are passed through APIs that use null-terminated strings.
    ///
    /// **Dart Source:** `channel_buffers.dart:330-355`
    /// **Original:**
    /// ```dart
    /// void push(String name, ByteData? data, PlatformMessageResponseCallback callback) {
    ///   assert(!name.contains('\u0000'), 'Channel names must not contain U+0000 NULL characters.');
    ///   final _Channel channel = _channels.putIfAbsent(name, () => _Channel());
    ///   if (channel.push(_StoredMessage(data, callback))) {
    ///     _printDebug(...);
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the channel.
    ///   - data: The message data.
    ///   - callback: The response callback.
    public func push(_ name: String, _ data: Data?, _ callback: @escaping (Data?) -> Void) {
        assert(!name.contains(Character("\u{0000}")), "Channel names must not contain U+0000 NULL characters.")
        let channel = _channels[name] ?? {
            let newChannel = Channel()
            _channels[name] = newChannel
            return newChannel
        }()
        if channel.push(StoredMessage(data: data, callback: callback)) {
            // DIFFERENCE FROM DART: Using print() instead of _printDebug()
            // REASON: Swift has no direct equivalent to Dart's _printDebug
            #if DEBUG
            print("""
                A message on the \(name) channel was discarded before it could be handled.
                This happens when a plugin sends messages to the framework side before the \
                framework has had an opportunity to register a listener. See the ChannelBuffers \
                API documentation for details on how to configure the channel to expect more \
                messages, or to expect messages to get discarded:
                  https://api.flutter.dev/flutter/dart-ui/ChannelBuffers-class.html
                The capacity of the \(name) channel is \(channel.capacity) message\(channel.capacity != 1 ? "s" : "").
                """)
            #endif
        }
    }

    /// Sets the listener for the specified channel.
    ///
    /// When there is a listener, messages are sent immediately.
    ///
    /// Each channel may have up to one listener set at a time. Setting
    /// a new listener on a channel with an existing listener clears the
    /// previous one.
    ///
    /// Callbacks are invoked in their own stack frame and
    /// use the zone that was current when the callback was
    /// registered.
    ///
    /// ## Draining
    ///
    /// If any messages were queued before the listener is added,
    /// they are drained asynchronously after this method returns.
    ///
    /// Each message is handled in its own microtask. No messages can
    /// be queued by plugins while the queue is being drained, but any
    /// microtasks queued by the handler itself will be processed before
    /// the next message is handled.
    ///
    /// The draining stops if the listener is removed.
    ///
    /// **Dart Source:** `channel_buffers.dart:357-385`
    /// **Original:**
    /// ```dart
    /// void setListener(String name, ChannelCallback callback) {
    ///   assert(!name.contains('\u0000'), 'Channel names must not contain U+0000 NULL characters.');
    ///   final _Channel channel = _channels.putIfAbsent(name, () => _Channel());
    ///   channel.setListener(callback);
    ///   sendChannelUpdate(name, listening: true);
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the channel.
    ///   - callback: The callback to invoke for each message.
    public func setListener(_ name: String, _ callback: @escaping ChannelCallback) {
        assert(!name.contains(Character("\u{0000}")), "Channel names must not contain U+0000 NULL characters.")
        let channel = _channels[name] ?? {
            let newChannel = Channel()
            _channels[name] = newChannel
            return newChannel
        }()
        channel.setListener(callback)
        sendChannelUpdate(name, listening: true)
    }

    /// Clears the listener for the specified channel.
    ///
    /// When there is no listener, messages on that channel are queued,
    /// up to `kDefaultBufferSize` (or the size configured via the
    /// control channel), and then discarded in a first-in-first-out
    /// fashion.
    ///
    /// **Dart Source:** `channel_buffers.dart:387-399`
    /// **Original:**
    /// ```dart
    /// void clearListener(String name) {
    ///   final _Channel? channel = _channels[name];
    ///   if (channel != null) {
    ///     channel.clearListener();
    ///     sendChannelUpdate(name, listening: false);
    ///   }
    /// }
    /// ```
    ///
    /// - Parameter name: The name of the channel.
    public func clearListener(_ name: String) {
        if let channel = _channels[name] {
            channel.clearListener()
            sendChannelUpdate(name, listening: false)
        }
    }

    /// Send a channel update notification to the engine.
    ///
    /// **Dart Source:** `channel_buffers.dart:401-407`
    /// **Original:**
    /// ```dart
    /// @Native<Void Function(Handle, Bool)>(symbol: 'PlatformConfigurationNativeApi::SendChannelUpdate')
    /// external static void _sendChannelUpdate(String name, bool listening);
    ///
    /// void sendChannelUpdate(String name, {required bool listening}) =>
    ///     _sendChannelUpdate(name, listening);
    /// ```
    ///
    /// DIFFERENCE FROM DART: Uses C++ bridge callback instead of @Native annotation
    /// REASON: Swift cannot use Dart FFI; the C++ bridge provides equivalent functionality
    ///
    /// - Parameters:
    ///   - name: The name of the channel.
    ///   - listening: Whether the channel is now being listened to.
    public func sendChannelUpdate(_ name: String, listening: Bool) {
        // Call the C++ bridge which forwards to the engine
        // Note: The bridge uses a callback registered by the engine during initialization
        // If no callback is registered, the update is silently ignored
        flutter.swift_bridge.ChannelBuffersBridge.SendChannelUpdate(name, listening)
    }

    /// Deprecated. Migrate to `setListener` instead.
    ///
    /// Remove and process all stored messages for a given channel.
    ///
    /// This should be called once a channel is prepared to handle messages
    /// (i.e. when a message handler is set up in the framework).
    ///
    /// The messages are processed by calling the given `callback`. Each message
    /// is processed in its own microtask.
    ///
    /// **Dart Source:** `channel_buffers.dart:409-428`
    /// **Original:**
    /// ```dart
    /// @Deprecated('Migrate to setListener instead. This feature was deprecated after v3.11.0-20.0.pre.')
    /// Future<void> drain(String name, DrainChannelCallback callback) async {
    ///   final _Channel? channel = _channels[name];
    ///   while (channel != null && !channel._queue.isEmpty) {
    ///     final _StoredMessage message = channel.pop();
    ///     await callback(message.data, message.invoke);
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the channel.
    ///   - callback: The callback to invoke for each message.
    @available(*, deprecated, message: "Migrate to setListener instead. This feature was deprecated after v3.11.0-20.0.pre.")
    public func drain(_ name: String, _ callback: @escaping DrainChannelCallback) async {
        guard let channel = _channels[name] else { return }
        while channel.length > 0 {
            let message = channel.pop()
            // DIFFERENCE FROM DART: Using nonisolated(unsafe) to bypass Sendable check
            // REASON: This method is deprecated and will be removed. The original Dart
            // implementation also does not handle concurrency safely (uses Zone).
            // In practice, this method is always called from the main thread in Flutter.
            let messageData = message.data
            nonisolated(unsafe) let responseCallback = message.callback
            await callback(messageData, { @Sendable responseData in
                // Response callback must be called on main actor
                Task { @MainActor in
                    responseCallback(responseData)
                }
            })
        }
    }

    /// Handle a control message.
    ///
    /// This is intended to be called by the platform messages dispatcher, forwarding
    /// messages from plugins to the `kControlChannelName` channel.
    ///
    /// Messages use the `StandardMethodCodec` format. There are two methods
    /// supported: `resize` and `overflow`. The `resize` method changes the size
    /// of the buffer, and the `overflow` method controls whether overflow is
    /// expected or not.
    ///
    /// ## `resize`
    ///
    /// The `resize` method takes as its argument a list with two values, first
    /// the channel name (a UTF-8 string less than 254 bytes long and not
    /// containing any null bytes), and second the allowed size of the channel
    /// buffer (an integer between 0 and 2147483647).
    ///
    /// Upon receiving the message, the channel's buffer is resized. If necessary,
    /// messages are silently discarded to ensure the buffer is no bigger than
    /// specified.
    ///
    /// For historical reasons, this message can also be sent using a bespoke
    /// format consisting of a UTF-8-encoded string with three parts separated
    /// from each other by U+000D CARRIAGE RETURN (CR) characters, the three parts
    /// being the string `resize`, the string giving the channel name, and then
    /// the string giving the decimal serialization of the new channel buffer
    /// size. For example: `resize\rchannel\r1`
    ///
    /// ## `overflow`
    ///
    /// The `overflow` method takes as its argument a list with two values, first
    /// the channel name (a UTF-8 string less than 254 bytes long and not
    /// containing any null bytes), and second a boolean which is true if overflow
    /// is expected and false if it is not.
    ///
    /// This sets a flag on the channel in debug mode. In release mode the message
    /// is silently ignored. The flag indicates whether overflow is expected on this
    /// channel. When the flag is set, messages are discarded silently. When the
    /// flag is cleared (the default), any overflow on the channel causes a message
    /// to be printed to the console, warning that a message was lost.
    ///
    /// **Dart Source:** `channel_buffers.dart:430-582`
    ///
    /// - Parameter data: The control message data.
    /// - Throws: An error if the message format is invalid.
    public func handleMessage(_ data: Data) throws {
        // We hard-code the deserialization here because the StandardMethodCodec class
        // is part of the framework, not dart:ui.
        let bytes = [UInt8](data)

        guard !bytes.isEmpty else {
            throw ChannelBuffersError.invalidMessage("Empty message sent to \(Self.kControlChannelName)")
        }

        if bytes[0] == 0x07 {
            // 7 = value code for string
            guard bytes.count > 1 else {
                throw ChannelBuffersError.invalidMessage("Message too short for \(Self.kControlChannelName)")
            }
            let methodNameLength = Int(bytes[1])
            if methodNameLength >= 254 {
                // lengths greater than 253 have more elaborate encoding
                throw ChannelBuffersError.invalidMessage("Unrecognized message sent to \(Self.kControlChannelName) (method name too long)")
            }
            var index = 2 // where we are in reading the bytes
            guard index + methodNameLength <= bytes.count else {
                throw ChannelBuffersError.invalidMessage("Message truncated at method name for \(Self.kControlChannelName)")
            }
            guard let methodName = String(bytes: bytes[index..<(index + methodNameLength)], encoding: .utf8) else {
                throw ChannelBuffersError.invalidMessage("Invalid UTF-8 in method name for \(Self.kControlChannelName)")
            }
            index += methodNameLength

            switch methodName {
            case "resize":
                guard index < bytes.count, bytes[index] == 0x0C else {
                    // 12 = value code for list
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'resize' method sent to \(Self.kControlChannelName) (arguments must be a two-element list, channel name and new capacity)")
                }
                index += 1
                guard index < bytes.count, bytes[index] >= 0x02 else {
                    // We ignore extra arguments, in case we need to support them in the future, hence >=2
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'resize' method sent to \(Self.kControlChannelName) (arguments must be a two-element list, channel name and new capacity)")
                }
                index += 1
                guard index < bytes.count, bytes[index] == 0x07 else {
                    // 7 = value code for string
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'resize' method sent to \(Self.kControlChannelName) (first argument must be a string)")
                }
                index += 1
                guard index < bytes.count else {
                    throw ChannelBuffersError.invalidMessage("Message truncated for \(Self.kControlChannelName)")
                }
                let channelNameLength = Int(bytes[index])
                if channelNameLength >= 254 {
                    // lengths greater than 253 have more elaborate encoding
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'resize' method sent to \(Self.kControlChannelName) (channel name must be less than 254 characters long)")
                }
                index += 1
                guard index + channelNameLength <= bytes.count else {
                    throw ChannelBuffersError.invalidMessage("Message truncated at channel name for \(Self.kControlChannelName)")
                }
                guard let channelName = String(bytes: bytes[index..<(index + channelNameLength)], encoding: .utf8) else {
                    throw ChannelBuffersError.invalidMessage("Invalid UTF-8 in channel name for \(Self.kControlChannelName)")
                }
                if channelName.contains(Character("\u{0000}")) {
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'resize' method sent to \(Self.kControlChannelName) (channel name must not contain any null bytes)")
                }
                index += channelNameLength
                guard index < bytes.count, bytes[index] == 0x03 else {
                    // 3 = value code for uint32
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'resize' method sent to \(Self.kControlChannelName) (second argument must be an integer in the range 0 to 2147483647)")
                }
                index += 1
                guard index + 4 <= bytes.count else {
                    throw ChannelBuffersError.invalidMessage("Message truncated at capacity for \(Self.kControlChannelName)")
                }
                // Read UInt32 in host endian (little endian on most platforms)
                let newSize = Int(UInt32(bytes[index]) |
                                  (UInt32(bytes[index + 1]) << 8) |
                                  (UInt32(bytes[index + 2]) << 16) |
                                  (UInt32(bytes[index + 3]) << 24))
                resize(channelName, newSize)

            case "overflow":
                guard index < bytes.count, bytes[index] == 0x0C else {
                    // 12 = value code for list
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'overflow' method sent to \(Self.kControlChannelName) (arguments must be a two-element list, channel name and flag state)")
                }
                index += 1
                guard index < bytes.count, bytes[index] >= 0x02 else {
                    // We ignore extra arguments, in case we need to support them in the future
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'overflow' method sent to \(Self.kControlChannelName) (arguments must be a two-element list, channel name and flag state)")
                }
                index += 1
                guard index < bytes.count, bytes[index] == 0x07 else {
                    // 7 = value code for string
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'overflow' method sent to \(Self.kControlChannelName) (first argument must be a string)")
                }
                index += 1
                guard index < bytes.count else {
                    throw ChannelBuffersError.invalidMessage("Message truncated for \(Self.kControlChannelName)")
                }
                let channelNameLength = Int(bytes[index])
                if channelNameLength >= 254 {
                    // lengths greater than 253 have more elaborate encoding
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'overflow' method sent to \(Self.kControlChannelName) (channel name must be less than 254 characters long)")
                }
                index += 1
                guard index + channelNameLength <= bytes.count else {
                    throw ChannelBuffersError.invalidMessage("Message truncated at channel name for \(Self.kControlChannelName)")
                }
                guard let channelName = String(bytes: bytes[index..<(index + channelNameLength)], encoding: .utf8) else {
                    throw ChannelBuffersError.invalidMessage("Invalid UTF-8 in channel name for \(Self.kControlChannelName)")
                }
                index += channelNameLength
                guard index < bytes.count, bytes[index] == 0x01 || bytes[index] == 0x02 else {
                    // 1 = value code for true, 2 = value code for false
                    throw ChannelBuffersError.invalidMessage("Invalid arguments for 'overflow' method sent to \(Self.kControlChannelName) (second argument must be a boolean)")
                }
                allowOverflow(channelName, bytes[index] == 0x01)

            default:
                throw ChannelBuffersError.invalidMessage("Unrecognized method '\(methodName)' sent to \(Self.kControlChannelName)")
            }
        } else {
            // Legacy CR-separated format
            guard let message = String(data: data, encoding: .utf8) else {
                throw ChannelBuffersError.invalidMessage("Invalid UTF-8 in legacy message sent to \(Self.kControlChannelName)")
            }
            let parts = message.split(separator: "\r", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 3 && parts[0] == "resize" {
                guard let newSize = Int(parts[2]) else {
                    throw ChannelBuffersError.invalidMessage("Invalid capacity in legacy resize message sent to \(Self.kControlChannelName)")
                }
                resize(parts[1], newSize)
            } else {
                throw ChannelBuffersError.invalidMessage("Unrecognized message \(parts) sent to \(Self.kControlChannelName).")
            }
        }
    }

    /// Changes the capacity of the queue associated with the given channel.
    ///
    /// This could result in the dropping of messages if newSize is less
    /// than the current length of the queue.
    ///
    /// This is expected to be called by platform-specific plugin code (indirectly
    /// via the control channel), not by code on the framework side. See
    /// `handleMessage`.
    ///
    /// Calling this from framework code is redundant since by the time framework
    /// code can be running, it can just subscribe to the relevant channel and
    /// there is therefore no need for any buffering.
    ///
    /// **Dart Source:** `channel_buffers.dart:584-605`
    /// **Original:**
    /// ```dart
    /// void resize(String name, int newSize) {
    ///   _Channel? channel = _channels[name];
    ///   if (channel == null) {
    ///     assert(!name.contains('\u0000'), 'Channel names must not contain U+0000 NULL characters.');
    ///     channel = _Channel(newSize);
    ///     _channels[name] = channel;
    ///   } else {
    ///     channel.capacity = newSize;
    ///   }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the channel.
    ///   - newSize: The new capacity for the channel buffer.
    public func resize(_ name: String, _ newSize: Int) {
        if let channel = _channels[name] {
            channel.capacity = newSize
        } else {
            assert(!name.contains(Character("\u{0000}")), "Channel names must not contain U+0000 NULL characters.")
            _channels[name] = Channel(capacity: newSize)
        }
    }

    /// Toggles whether the channel should show warning messages when discarding
    /// messages due to overflow.
    ///
    /// This is expected to be called by platform-specific plugin code (indirectly
    /// via the control channel), not by code on the framework side. See
    /// `handleMessage`.
    ///
    /// Calling this from framework code is redundant since by the time framework
    /// code can be running, it can just subscribe to the relevant channel and
    /// there is therefore no need for any messages to overflow.
    ///
    /// This method has no effect in release builds.
    ///
    /// **Dart Source:** `channel_buffers.dart:607-630`
    /// **Original:**
    /// ```dart
    /// void allowOverflow(String name, bool allowed) {
    ///   assert(() {
    ///     _Channel? channel = _channels[name];
    ///     if (channel == null && allowed) {
    ///       assert(!name.contains('\u0000'), 'Channel names must not contain U+0000 NULL characters.');
    ///       channel = _Channel();
    ///       _channels[name] = channel;
    ///     }
    ///     channel?.debugEnableDiscardWarnings = !allowed;
    ///     return true;
    ///   }());
    /// }
    /// ```
    ///
    /// DIFFERENCE FROM DART: Uses `#if DEBUG` instead of `assert(() { ... }())`
    /// REASON: Swift idiom for debug-only code
    ///
    /// - Parameters:
    ///   - name: The name of the channel.
    ///   - allowed: Whether overflow is expected (true) or not (false).
    public func allowOverflow(_ name: String, _ allowed: Bool) {
        #if DEBUG
        var channel = _channels[name]
        if channel == nil && allowed {
            assert(!name.contains(Character("\u{0000}")), "Channel names must not contain U+0000 NULL characters.")
            channel = Channel()
            _channels[name] = channel
        }
        channel?.debugEnableDiscardWarnings = !allowed
        #endif
    }
}

// MARK: - ChannelBuffersError

/// Errors that can occur when handling channel buffer messages.
///
/// **Dart Source:** N/A - Swift-specific error type
///
/// DIFFERENCE FROM DART: Uses Swift Error enum instead of Dart Exception
/// REASON: Swift idiom for error handling
public enum ChannelBuffersError: Error, CustomStringConvertible {
    case invalidMessage(String)

    public var description: String {
        switch self {
        case .invalidMessage(let message):
            return "Exception: \(message)"
        }
    }
}

// MARK: - Global ChannelBuffers Instance

/// `ChannelBuffers` that allow the storage of messages between the
/// Engine and the Framework. Typically messages that can't be delivered
/// are stored here until the Framework is able to process them.
///
/// See also:
///
/// * `BinaryMessenger`, where `ChannelBuffers` are typically read.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/channel_buffers.dart:633-640`
/// **Original:** `final ChannelBuffers channelBuffers = ChannelBuffers()`
///
/// DIFFERENCE FROM DART: Wrapped in MainActor.assumeIsolated closure
/// REASON: Swift 6 strict concurrency requires @MainActor isolation for
///         accessing main-actor-isolated types. The channelBuffers global
///         is always accessed from the UI thread.
public let channelBuffers: ChannelBuffers = {
    // Use MainActor.assumeIsolated to create the instance during module load
    // This is safe because the Flutter engine guarantees this code runs on the main thread
    MainActor.assumeIsolated {
        ChannelBuffers()
    }
}()
