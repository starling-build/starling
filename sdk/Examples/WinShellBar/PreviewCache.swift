// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The pictures in the dock's hover preview, as DWM thumbnails.
//
// This used to be PrintWindow into a DIB, uploaded as an external texture.
// That is a PRINTING api doing a compositing job, and every symptom followed
// from it: a capture costs a full re-render of the target window, so it had to
// be throttled to once a second rather than being live; a MINIMIZED window
// paints nothing, so it came back empty and needed the app's icon drawn over
// the hole; and it re-captured on a timer that had to be cancelled, generation
// -tokened and re-armed.
//
// DwmRegisterThumbnail is what the taskbar's own preview is, and it deletes
// all three problems: DWM is already compositing those pixels, so it is live
// for free, and it keeps the last frame of a minimized window, so a minimized
// window shows its content exactly as Windows' preview does.
//
// WHAT IT COSTS. A thumbnail is not an image. DWM paints it into a rectangle
// of a destination window WE OWN -- here, the dock's own panel window -- and
// we never see the pixels. So these are not Widgets, and the card cannot draw
// anything ON one: the tree draws the chrome and the slot, and the picture
// arrives on top of it. Verified on the physical box that DWM does composite
// onto the dock's WS_EX_LAYERED colour-keyed window, which was the one thing
// this design depended on and which is documented nowhere -- see
// flwin32_thumb.c's probe.
//
// Positions are PHYSICAL pixels in the dock window's client space. The card
// lays out in logical points, so every rect goes through the screen scale on
// its way here.

#if os(Windows)
import FlutterWin32
import Foundation

final class PreviewCache {
    private var thumbs: [UInt64: Win32Thumbnail] = [:]

    /// The destination: the dock's own top-level window. Read on demand rather
    /// than stored, because the host is built after this object is.
    private var destination: UInt64 { Win32WindowedHost.host?.windowHandle ?? 0 }

    /// Registers anything in `windows` not already registered, and drops
    /// anything no longer listed. Called when a card opens and whenever its
    /// window list changes; there is no timer, because there is nothing to
    /// re-capture.
    func sync(_ windows: [UInt64]) {
        let dest = destination
        guard dest != 0 else { return }
        for handle in windows where thumbs[handle] == nil {
            if let thumb = Win32Thumbnail(source: handle, destination: dest) {
                thumbs[handle] = thumb
            }
        }
        for (handle, thumb) in thumbs where !windows.contains(handle) {
            thumb.release()
            thumbs.removeValue(forKey: handle)
        }
    }

    /// Puts one window's picture in a slot, aspect-fitted so a wide window in
    /// a 16:9 slot is letterboxed rather than stretched.
    func place(_ handle: UInt64, x: Int, y: Int, width: Int, height: Int) {
        thumbs[handle]?.fit(inX: x, y: y, width: width, height: height)
    }

    /// Whether there is a live registration for this window — the card uses it
    /// to decide between leaving the slot empty for DWM and drawing a
    /// placeholder, for the beat before a registration exists.
    func has(_ handle: UInt64) -> Bool { thumbs[handle] != nil }

    /// Everything goes when the card closes. NOT optional: a thumbnail that
    /// outlives its card keeps painting over the dock, which reads as the
    /// shell being broken rather than as a leak.
    func releaseAll() {
        for thumb in thumbs.values { thumb.release() }
        thumbs.removeAll()
    }
}
#endif
