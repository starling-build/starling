// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// The size a picture takes when one of its eight handles is dragged.
///
/// Handles are numbered clockwise from the top-left corner: 0 top-left, 1 top, 2 top-right, 3 right, 4 bottom-right,
/// 5 bottom, 6 bottom-left, 7 left. Even numbers are corners.
public enum PictureResize {
    /// `start` is the size when the drag began, (`dx`, `dy`) how far the pointer has moved, in the same unit.
    /// With `keepAspect` a corner scales both sides together and an edge brings the other side along; without it
    /// both are free. Never wider than `maxWidth`, never below 8.
    public static func size(from start: Size, handle: Int, dx: Double, dy: Double,
                            keepAspect: Bool, maxWidth: Double) -> Size {
        let sx: Double = [2, 3, 4].contains(handle) ? 1 : [0, 6, 7].contains(handle) ? -1 : 0
        let sy: Double = [4, 5, 6].contains(handle) ? 1 : [0, 1, 2].contains(handle) ? -1 : 0
        var w = start.width + sx * dx
        var h = start.height + sy * dy
        if keepAspect, handle % 2 == 0 {
            let scale = max(w / start.width, h / start.height)
            w = start.width * scale
            h = start.height * scale
        } else if keepAspect, sx == 0 {
            w = start.width * h / start.height
        } else if keepAspect, sy == 0 {
            h = start.height * w / start.width
        }
        if w > maxWidth { if keepAspect { h *= maxWidth / w }; w = maxWidth }
        return Size(max(8, w), max(8, h))
    }
}
