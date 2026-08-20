// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Live thumbnails of other people's windows, via DWM.
//
// The counterpart of Win32Capture, and its replacement for anything that has
// to stay live. Capture asks a window to re-render itself into a bitmap we
// own; this asks DWM for the pixels it is ALREADY compositing. That makes it
// free, live, and correct for a minimized window -- DWM keeps the last frame,
// which is exactly what the taskbar's own preview shows.
//
// THE CATCH, and it shapes every caller: a thumbnail is not an image. DWM
// paints it into a rectangle of a destination window we own, and we never get
// the pixels. So this cannot be a Widget. A surface using it draws its chrome
// in the tree and then asks for a rectangle to be filled in, in the
// destination window's client coordinates and PHYSICAL pixels.

#if os(Windows)
import FlutterWin32Bridge
import Foundation

/// One registered (destination, source) pair. Registration is not free and is
/// not a lookup -- it is a relationship DWM maintains -- so a caller keeps
/// these for as long as the surface is up and releases them when it closes.
public final class Win32Thumbnail {
    public let source: UInt64
    private var handle: UInt64
    private var released = false

    /// Registers `source` into `destination`. Both are HWNDs; `destination`
    /// must belong to this process. Returns nil when either has gone away,
    /// which is ordinary rather than exceptional: windows close while a
    /// preview is open.
    public init?(source: UInt64, destination: UInt64) {
        var out: UInt64 = 0
        guard flwin32_thumb_register(destination, source, &out) != 0, out != 0 else {
            return nil
        }
        self.source = source
        self.handle = out
    }

    /// The source's size as DWM knows it, for fitting the picture into a slot
    /// without distorting it. Not the window rect: a minimized window's rect
    /// is off-screen nonsense while DWM still knows how big its frame was.
    public var sourceSize: (width: Int, height: Int)? {
        var w: Int32 = 0
        var h: Int32 = 0
        guard flwin32_thumb_source_size(handle, &w, &h) != 0, w > 0, h > 0 else {
            return nil
        }
        return (Int(w), Int(h))
    }

    /// Places the picture. `x`/`y`/`width`/`height` are the destination
    /// window's CLIENT coordinates in PHYSICAL pixels -- multiply logical
    /// points by the screen scale first, or it lands at half size on a 200%
    /// display and is exactly right on a 100% one.
    @discardableResult
    public func place(x: Int, y: Int, width: Int, height: Int,
                      opacity: Int = 255, clientAreaOnly: Bool = true) -> Bool {
        guard !released else { return false }
        return flwin32_thumb_place(handle, Int32(x), Int32(y),
                                   Int32(width), Int32(height),
                                   Int32(opacity), clientAreaOnly ? 1 : 0) != 0
    }

    /// Aspect-fits the source inside a slot and places it centred. A window is
    /// almost never the slot's shape, and stretching it to fit is the one
    /// thing that makes a preview look wrong at a glance.
    @discardableResult
    public func fit(inX x: Int, y: Int, width: Int, height: Int,
                    opacity: Int = 255) -> Bool {
        guard let size = sourceSize else {
            return place(x: x, y: y, width: width, height: height, opacity: opacity)
        }
        let scale = min(Double(width) / Double(size.width),
                        Double(height) / Double(size.height))
        let w = max(1, Int((Double(size.width) * scale).rounded()))
        let h = max(1, Int((Double(size.height) * scale).rounded()))
        return place(x: x + (width - w) / 2, y: y + (height - h) / 2,
                     width: w, height: h, opacity: opacity)
    }

    @discardableResult
    public func hide() -> Bool {
        guard !released else { return false }
        return flwin32_thumb_hide(handle) != 0
    }

    /// Idempotent, and called from deinit as well: a thumbnail that outlives
    /// its card keeps painting over the dock, which is the one failure mode
    /// here that a user would describe as the shell being broken.
    public func release() {
        guard !released else { return }
        released = true
        flwin32_thumb_unregister(handle)
        handle = 0
    }

    deinit { release() }
}
#endif
