// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A Windows caption bar: title at the left, the minimise/maximise/close trio
// at the right.
//
// The trio's geometry is Windows' own and is not arbitrary. Each button is
// 46x32 — wide, flat rectangles rather than the round targets a Mac uses —
// and close is the only one that colours on hover, going red with a white
// glyph in BOTH appearances. That red is the whole reason the buttons are
// this wide: it has to read as a distinct block, not as a tinted icon.
//
// Drag-to-move and double-click-to-maximise work exactly as in the macOS bar,
// including the reason double-click is detected by hand — see below.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

// MARK: - FluentTitleBar

class FluentTitleBar: StatefulWidget {

    let title: String
    let isFocused: Bool
    let isMaximized: Bool
    let isFullscreen: Bool
    let onMove: ((Offset) -> Void)?
    let onMinimize: (() -> Void)?
    let onMaximize: (() -> Void)?
    let onClose: (() -> Void)?
    let onDoubleTap: (() -> Void)?

    init(
        title: String,
        isFocused: Bool,
        isMaximized: Bool,
        isFullscreen: Bool = false,
        onMove: ((Offset) -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        onMaximize: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.isFocused = isFocused
        self.isMaximized = isMaximized
        self.isFullscreen = isFullscreen
        self.onMove = onMove
        self.onMinimize = onMinimize
        self.onMaximize = onMaximize
        self.onClose = onClose
        self.onDoubleTap = onDoubleTap
    }

    override func createState() -> State<StatefulWidget> {
        return _FluentTitleBarState()
    }
}

// MARK: - _FluentTitleBarState

class _FluentTitleBarState: State<StatefulWidget> {

    /// Last pointer position during an active drag (nil when not dragging).
    private var lastPointerPos: Offset? = nil

    /// Time of the last pointer-down, for detecting a double-click. Done by
    /// hand rather than with `onDoubleTap`, which on the DRM embedder kills
    /// tap AND double-tap (its Foundation.Timer never fires there).
    private var lastDownTime: TimeInterval = 0
    private static let kDoubleTapThreshold: TimeInterval = 0.4

    /// Windows' caption button box, and the glyph inside it. The button is
    /// far wider than it is tall on purpose: the hover fill is the affordance,
    /// so it has to be a block you can see.
    private static let kButtonWidth: Double = 46
    private static let kGlyphSize: Double = 12

    private var w: FluentTitleBar { widget as! FluentTitleBar }

    override func build(_ context: any BuildContext) -> Widget {
        let bgColor = w.isFocused
            ? shellTheme.titleBarActive
            : shellTheme.titleBarInactive
        let titleColor = w.isFocused
            ? shellTheme.titleTextActive
            : shellTheme.titleTextInactive

        return Listener(
            onPointerDown: { [self] event in
                lastPointerPos = event.position
                let now = Date.timeIntervalSinceReferenceDate
                if now - lastDownTime < _FluentTitleBarState.kDoubleTapThreshold {
                    w.onDoubleTap?()
                    lastDownTime = 0  // so a triple-click doesn't fire again
                } else {
                    lastDownTime = now
                }
            },
            onPointerMove: { [self] event in
                guard let last = lastPointerPos else { return }
                let delta = Offset(
                    event.position.dx - last.dx,
                    event.position.dy - last.dy
                )
                lastPointerPos = event.position
                w.onMove?(delta)
            },
            onPointerUp: { [self] _ in
                lastPointerPos = nil
            },
            onPointerHover: { _ in
                DesktopCursor.setShape(.default)
            },
            behavior: .opaque,
            child: SizedBox(
                height: DesktopTheme.kTitleBarHeight,
                child: ColoredBox(
                    color: bgColor,
                    child: Row(
                        children: [
                            SizedBox(width: 12),
                            // The title is left-aligned, not centred: Windows
                            // reads the bar left to right, and the trio at the
                            // right needs the whole rest of the row.
                            Expanded(
                                child: Text(
                                    w.title,
                                    style: TextStyle(
                                        color: titleColor,
                                        fontSize: 12,
                                        fontWeight: .w400
                                    ),
                                    overflow: .ellipsis,
                                    maxLines: 1
                                )
                            ),
                            SizedBox(width: 8),
                            _captionButton(
                                icon: FluentSystemIcons.chromeMinimize,
                                onTap: w.onMinimize
                            ),
                            _captionButton(
                                icon: w.isMaximized
                                    ? FluentSystemIcons.chromeRestore
                                    : FluentSystemIcons.chromeMaximize,
                                onTap: w.onMaximize
                            ),
                            _captionButton(
                                icon: FluentSystemIcons.chromeClose,
                                isClose: true,
                                onTap: w.onClose
                            ),
                        ]
                    )
                )
            )
        )
    }

    /// One caption button. Close is the odd one: it fills red on hover and its
    /// glyph goes white on that red whatever the appearance, so the ink has to
    /// be picked from the hover state rather than from the theme alone.
    private func _captionButton(
        icon: IconData,
        isClose: Bool = false,
        onTap: (() -> Void)?
    ) -> Widget {
        return SizedBox(
            width: _FluentTitleBarState.kButtonWidth,
            height: DesktopTheme.kTitleBarHeight,
            child: HoverButton(
                builder: { context, states in
                    let hot = states.isHovered || states.isPressed
                    let fill: Color
                    if !hot {
                        fill = Color(0x00000000)
                    } else if isClose {
                        fill = shellTheme.captionCloseHover
                    } else {
                        fill = shellTheme.captionHover
                    }
                    let ink = (hot && isClose)
                        ? shellTheme.captionCloseInk
                        : (self.w.isFocused
                            ? shellTheme.titleTextActive
                            : shellTheme.titleTextInactive)
                    return ColoredBox(
                        color: fill,
                        child: Center(
                            child: MacosIcon(
                                icon: icon,
                                color: ink,
                                size: _FluentTitleBarState.kGlyphSize
                            )
                        )
                    )
                },
                onPressed: onTap
            )
        )
    }
}
