// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A picture of somebody else's window.
//
// DWM cannot be replaced, so a Starling shell on Windows never owns another
// app's pixels — but a taskbar preview and a window overview are pictures of
// exactly that, so it has to be able to ask. See flwin32_capture.c for what
// this can and cannot photograph, and why it asks the window to render rather
// than copying what is on the glass (an occluded window would otherwise come
// back as whatever is in front of it, which is the case a preview is FOR).

#if os(Windows)
import FlutterWin32Bridge
import Foundation

public enum Win32Capture {
    /// A thumbnail of `window`, longest side `maxSide` in pixels, or nil when
    /// the window is minimized, refused to render, or is one of our own
    /// surfaces.
    ///
    /// Call it OFF the UI thread: it asks the window to render itself at full
    /// size, which for a 4K window is a real cost paid on the calling thread.
    public static func thumbnail(window handle: UInt64, maxSide: Int) -> Win32Icon.Bitmap? {
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        var width: Int32 = 0
        var height: Int32 = 0
        guard flwin32_capture_window(handle, Int32(maxSide), &pixels,
                                     &width, &height) != 0,
              let pixels, width > 0, height > 0 else { return nil }
        return Win32Icon.Bitmap(pixels: pixels, width: Int(width), height: Int(height))
    }
}
#endif
