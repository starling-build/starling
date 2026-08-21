// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Rasterizing an app's icon, off the UI thread.
//
// Making an icon into something the engine can draw is two jobs with opposite
// rules, and they used to be one call:
//
//   1. RASTERIZE — ask the shell for the HICON and draw it into a DIB. Pure
//      GDI and shell, safe on any thread, and slow: 79 Start Menu icons
//      measured 607ms, which is what it was costing the launcher's UI thread
//      at startup.
//   2. REGISTER — hand the pixels to the engine's texture registrar. Fast,
//      and belongs to the platform thread.
//
// This is (1), as a free function with no host in sight, so it can be called
// from a `Task.detached`. `Win32Host.registerPixels` is (2).

#if os(Windows)
import FlutterWin32Bridge
import Foundation

public enum Win32Icon {

    /// Rasterized pixels, owned by whoever holds this.
    ///
    /// The buffer is C-allocated. Passing it to `Win32Host.registerPixels`
    /// hands ownership over — after that the texture frees it. Anything that
    /// rasterizes and then decides not to register must call `discard()`, or
    /// the bitmap leaks.
    public struct Bitmap: @unchecked Sendable {
        public let pixels: UnsafeMutablePointer<UInt8>
        public let width: Int
        public let height: Int

        public func discard() { flwin32_icon_free(pixels) }
    }

    /// The icon for a file — an executable, or a `.lnk` whose icon is a
    /// property of the shortcut. **Safe on any thread.**
    public static func rasterize(path: String, size: Int = 48) -> Bitmap? {
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        var width: Int32 = 0
        var height: Int32 = 0
        guard flwin32_icon_rasterize_path(path, Int32(size), &pixels,
                                          &width, &height) != 0,
              let pixels, width > 0, height > 0 else { return nil }
        return Bitmap(pixels: pixels, width: Int(width), height: Int(height))
    }

    /// A file's THUMBNAIL -- the picture itself, a video's frame -- through
    /// the shell's image factory and its on-disk thumbnail cache. nil for a
    /// type with no thumbnail handler (SIIGBF_THUMBNAILONLY fails rather
    /// than answering with the icon), which is the caller's cue to keep the
    /// type icon it already has. Letterboxed to a square. Blocks on decode:
    /// background thread only.
    public static func thumbnail(path: String, side: Int) -> Bitmap? {
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        var width: Int32 = 0
        var height: Int32 = 0
        guard flwin32_icon_thumbnail(path, Int32(side), &pixels,
                                     &width, &height) != 0,
              let pixels, width > 0, height > 0 else { return nil }
        return Bitmap(pixels: pixels, width: Int(width), height: Int(height))
    }

    /// The wallpaper, rastered to COVER exactly width x height (Windows'
    /// "Fill" fit) — the desktop surface's backdrop. Blocks on the decode:
    /// background thread only.
    public static func wallpaper(width: Int, height: Int) -> Bitmap? {
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        guard flwin32_wallpaper_raster(Int32(width), Int32(height),
                                       &pixels) != 0,
              let pixels else { return nil }
        return Bitmap(pixels: pixels, width: width, height: height)
    }

    /// The icon a live window reports. **Safe on any thread**, though it
    /// sends a message to the owning window with a timeout, so it is not
    /// instant when that window is busy — another reason not to do it on the
    /// thread drawing the shell.
    public static func rasterize(window handle: UInt64, size: Int = 32) -> Bitmap? {
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        var width: Int32 = 0
        var height: Int32 = 0
        guard flwin32_icon_rasterize(handle, Int32(size), &pixels,
                                     &width, &height) != 0,
              let pixels, width > 0, height > 0 else { return nil }
        return Bitmap(pixels: pixels, width: Int(width), height: Int(height))
    }

    /// Releases a handle the caller took ownership of — a tray icon out of a
    /// `Win32Tray.snapshot()`. Not for handles that were only borrowed.
    public static func destroy(_ handle: UInt64) {
        flwin32_icon_destroy(handle)
    }

    /// From an icon handle the caller already has — a tray icon, which arrives
    /// as a handle and never as a path or a window. Borrows it: the handle is
    /// still the caller's to destroy.
    public static func rasterize(icon handle: UInt64, size: Int = 32) -> Bitmap? {
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        var width: Int32 = 0
        var height: Int32 = 0
        guard flwin32_icon_rasterize_handle(handle, Int32(size), &pixels,
                                            &width, &height) != 0,
              let pixels, width > 0, height > 0 else { return nil }
        return Bitmap(pixels: pixels, width: Int(width), height: Int(height))
    }
}
#endif
