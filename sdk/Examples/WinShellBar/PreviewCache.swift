// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Thumbnails of other people's windows, for the dock's hover previews.
//
// Separate from IconCache, which it otherwise resembles, because the two have
// opposite lifetimes. An icon is small, permanent and never changes, so that
// cache remembers what it has ATTEMPTED and never asks twice. A preview is
// large, temporary and stale the moment it is taken — the whole point is that
// it shows what the window looks like NOW — so this one re-captures on demand
// and throws everything away when the preview closes.
//
// Capturing is not free: it asks the window to render itself at full size.
// Hence one capture when a preview opens and one per second while it is up,
// rather than one per frame.

#if os(Windows)
import Flutter
import FlutterWin32
import Foundation

final class PreviewCache {
    /// Called on the UI thread when a thumbnail has landed.
    var onReady: (() -> Void)?

    private var textures: [UInt64: Int] = [:]
    private var inFlight: Set<UInt64> = []

    /// The longest side, in physical pixels. The card draws at a fixed
    /// logical size, so this is that size times the screen's scale.
    var pixelSide: Int = 320

    /// Captures anything in `windows` that is not already in flight. Existing
    /// thumbnails stay on screen until the new one lands, so a refresh does
    /// not blink.
    func refresh(_ windows: [UInt64]) {
        for handle in windows where !inFlight.contains(handle) {
            inFlight.insert(handle)
            let side = pixelSide
            Self.queue.async { [weak self] in
                let bitmap = Win32Capture.thumbnail(window: handle, maxSide: side)
                DispatchQueue.main.async {
                    guard let self else {
                        bitmap?.discard()
                        return
                    }
                    self.inFlight.remove(handle)
                    guard let bitmap else { return }
                    guard let id = Win32WindowedHost.host?.registerPixels(bitmap) else {
                        return
                    }
                    // Replace rather than skip: the old picture is a picture
                    // of the past, which is the one thing a preview must not
                    // be.
                    if let old = self.textures[handle] {
                        Win32WindowedHost.host?.unregisterTexture(old)
                    }
                    self.textures[handle] = id
                    self.onReady?()
                }
            }
        }
    }

    /// ONE serial queue, for the reason the icon cache has one: these are
    /// synchronous shell round trips, and asking for six at once is slower
    /// than asking for six in a row as well as being ruder to the apps.
    private static let queue = DispatchQueue(label: "starling.previews.capture",
                                             qos: .userInitiated)

    func view(_ handle: UInt64, width: Double, height: Double) -> Widget? {
        guard let id = textures[handle] else { return nil }
        return SizedBox(width: width, height: height) {
            TextureWidget(textureId: id)
        }
    }

    /// Everything goes when the preview closes. A dozen 320px thumbnails is
    /// real memory on the GPU, and the next preview wants fresh ones anyway.
    func releaseAll() {
        for id in textures.values { Win32WindowedHost.host?.unregisterTexture(id) }
        textures.removeAll()
    }
}
#endif
