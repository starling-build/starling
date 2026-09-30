// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// On Linux, Foundation.Timer and RunLoop.perform closures are @Sendable,
// but our widget types are not Sendable. Since all timers and RunLoop
// callbacks run on the main thread, this is safe.

import Foundation

/// Casts a Timer callback to @Sendable for use with Foundation.Timer on Linux.
/// All Timer callbacks in this framework are scheduled on RunLoop.main.
@inline(__always)
func _sendableTimer(_ block: @escaping (Timer) -> Void) -> @Sendable (Timer) -> Void {
    unsafeBitCast(block, to: (@Sendable (Timer) -> Void).self)
}

/// Casts a void callback to @Sendable for use with RunLoop.perform on Linux.
/// All RunLoop.perform callbacks in this framework run on RunLoop.main.
@inline(__always)
func _sendablePerform(_ block: @escaping () -> Void) -> @Sendable () -> Void {
    unsafeBitCast(block, to: (@Sendable () -> Void).self)
}

/// `Foundation.Timer`, for the code that has to name it in full because a
/// `Timer` of its own is in scope. On WASI Foundation's does not link, and
/// this is the stand-in in WebSupport.swift.
#if os(WASI)
typealias PlatformTimer = Timer
#else
typealias PlatformTimer = Foundation.Timer
#endif
