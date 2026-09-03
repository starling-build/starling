// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import FlutterDRMBridge
#endif

/// Cursor shapes the shell can ask the DRM hardware cursor to display.
/// Raw values match the engine's `FlDrmCursorShape` enum.
public enum CursorShape: Int32 {
    case `default` = 0
    case resizeNS = 1   // top / bottom edges
    case resizeEW = 2   // left / right edges
    case resizeNESW = 3 // top-right / bottom-left corners
    case resizeNWSE = 4 // top-left / bottom-right corners
    case text = 5       // I-beam over editable text
    case pointer = 6    // pointing hand over links
}

/// Global setter wired up at startup (after fl_drm_view_create).
/// On macOS this is a no-op; on Linux it forwards to the DRM cursor.
public enum DesktopCursor {

    /// Set by main.swift once the DRM view is alive.
    nonisolated(unsafe) public static var shapeSetter: ((CursorShape) -> Void)?

    /// The same, for a bitmap cursor: (bgra, width, height, hotX, hotY).
    nonisolated(unsafe) public static var imageSetter:
        (([UInt8], Int, Int, Int, Int) -> Void)?

    /// Last shape we asked for — avoids redundant calls on every hover tick.
    /// Nil means the plane is showing an image instead, so the next shape has
    /// to be sent even if it is the one we last named.
    nonisolated(unsafe) private static var lastShape: CursorShape? = .default

    public static func setShape(_ shape: CursorShape) {
        guard shape != lastShape else { return }
        lastShape = shape
        shapeSetter?(shape)
    }

    /// Put a caller-supplied bitmap on the plane — a VM guest's own pointer,
    /// which arrives as pixels and has no shape to name it. Straight-alpha
    /// BGRA, tightly packed; the engine pre-multiplies and clips to 64x64.
    public static func setImage(_ bgra: [UInt8], width: Int, height: Int,
                                hotX: Int, hotY: Int) {
        lastShape = nil
        imageSetter?(bgra, width, height, hotX, hotY)
    }
}
