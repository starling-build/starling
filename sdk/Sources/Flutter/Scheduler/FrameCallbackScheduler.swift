// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Generic per-frame callback scheduler, driven from `onBeginFrame`.
///
/// Apps register closures to be called each frame. This is used by
/// external texture renderers that can't rely on `Foundation.Timer`
/// (e.g. in DRM mode where `RunLoop.main` never spins).

import FlutterSwiftBridge
import Foundation

// MARK: - FrameCallbackScheduler

public class FrameCallbackScheduler: @unchecked Sendable {
    public static nonisolated(unsafe) let shared = FrameCallbackScheduler()
    private init() {}

    private var _callbacks: [ObjectIdentifier: () -> Void] = [:]

    /// Set to true when any texture content is updated (DMA-BUF commit,
    /// SHM upload, GL renderer mark dirty, etc.).  Read and reset by
    /// `Adapter.onBeginFrame` to decide whether `compositeFrame()` is needed.
    public var textureDidUpdate = false

    /// The ids behind `textureDidUpdate`. Texture content updates carry no
    /// widget change, so pipeline dirty flags cannot see them; a view that
    /// shows one of these textures must re-composite anyway. Content arrives
    /// on compositor/reader threads while the drain runs on the UI thread,
    /// hence the lock.
    private let _updatedTexturesLock = NSLock()
    private var _updatedTextures: Set<Int64> = []

    /// Record that texture `id` has new content. Also sets
    /// `textureDidUpdate`, so a call site needs exactly one call.
    public func noteTextureUpdate(_ id: Int64) {
        _updatedTexturesLock.lock()
        _updatedTextures.insert(id)
        _updatedTexturesLock.unlock()
        textureDidUpdate = true
    }

    /// Drain the updated-texture ids — once per frame, from `onBeginFrame`.
    public func takeUpdatedTextures() -> Set<Int64> {
        _updatedTexturesLock.lock()
        defer { _updatedTexturesLock.unlock() }
        let ids = _updatedTextures
        _updatedTextures = []
        return ids
    }

    /// Register a callback to be called each frame.
    /// The key is used to identify the callback for later removal.
    public func register(_ key: AnyObject, callback: @escaping () -> Void) {
        _callbacks[ObjectIdentifier(key)] = callback
    }

    /// Unregister a callback.
    public func unregister(_ key: AnyObject) {
        _callbacks.removeValue(forKey: ObjectIdentifier(key))
    }

    /// Whether any callbacks are registered (e.g. external texture apps).
    public var hasCallbacks: Bool { !_callbacks.isEmpty }

    /// Called from `onBeginFrame` to invoke all registered callbacks.
    /// Does NOT schedule the next frame — the callbacks themselves trigger
    /// frame scheduling when they produce new content (via
    /// FlutterEngineScheduleFrame in markGLTextureDirty / updatePixelData).
    public func tick() {
        guard !_callbacks.isEmpty else { return }
        for (_, callback) in _callbacks {
            callback()
        }
    }
}
