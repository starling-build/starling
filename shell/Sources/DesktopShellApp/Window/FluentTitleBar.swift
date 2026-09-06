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
    /// The app's icon, drawn 16px square at the left of the caption.
    let icon: Widget?
    let onMove: ((Offset) -> Void)?
    let onMinimize: (() -> Void)?
    let onMaximize: (() -> Void)?
    let onClose: (() -> Void)?
    let onDoubleTap: (() -> Void)?
    let onContextMenu: ((Offset) -> Void)?
    let onMaximizeHover: ((Bool, Rect) -> Void)?

    init(
        title: String,
        isFocused: Bool,
        isMaximized: Bool,
        isFullscreen: Bool = false,
        icon: Widget? = nil,
        onMove: ((Offset) -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        onMaximize: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil,
        onContextMenu: ((Offset) -> Void)? = nil,
        onMaximizeHover: ((Bool, Rect) -> Void)? = nil
    ) {
        self.title = title
        self.isFocused = isFocused
        self.isMaximized = isMaximized
        self.isFullscreen = isFullscreen
        self.icon = icon
        self.onMove = onMove
        self.onMinimize = onMinimize
        self.onMaximize = onMaximize
        self.onClose = onClose
        self.onDoubleTap = onDoubleTap
        self.onContextMenu = onContextMenu
        self.onMaximizeHover = onMaximizeHover
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

    /// Windows' caption geometry for the left half: a 16px app icon 16 from
    /// the edge, and the title 16 from the icon.
    private static let kIconSize: Double = 16
    private static let kIconInset: Double = 16

    /// Windows opens snap layouts once the pointer has RESTED on maximize
    /// (about half a second — a pass across the control does not); the
    /// delay is on the frame clock, the one timer every host has.
    private static let kSnapHoverDelay: Duration = .milliseconds(500)
    private let _snapHover = FluentDelay()
    /// The maximize control's build context, kept so the hover can report
    /// the control's global rect for the flyout to hang from.
    private var _maximizeContext: (any BuildContext)?

    private var w: FluentTitleBar { widget as! FluentTitleBar }

    override func dispose() {
        _snapHover.cancel()
        super.dispose()
    }

    private func _maximizeRect() -> Rect {
        guard let ctx = _maximizeContext,
              let box = ctx.findRenderObject() as? RenderBox else { return .zero }
        let origin = box.localToGlobal(Offset.zero)
        return Rect.fromLTWH(origin.dx, origin.dy, box.size.width, box.size.height)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let bgColor = w.isFocused
            ? shellTheme.titleBarActive
            : shellTheme.titleBarInactive
        let titleColor = w.isFocused
            ? shellTheme.titleTextActive
            : shellTheme.titleTextInactive
        // Inactive, every element of the caption dims — the icon by the same
        // ratio the title's ink does, so the two agree.
        let inactiveOpacity = shellTheme.titleTextActive.alpha == 0 ? 1.0
            : Double(shellTheme.titleTextInactive.alpha) / Double(shellTheme.titleTextActive.alpha)

        var rowChildren: [Widget] = [SizedBox(width: _FluentTitleBarState.kIconInset)]
        if let icon = w.icon {
            rowChildren.append(SizedBox(
                width: _FluentTitleBarState.kIconSize,
                height: _FluentTitleBarState.kIconSize,
                child: Opacity(opacity: w.isFocused ? 1.0 : inactiveOpacity, child: icon)))
            rowChildren.append(SizedBox(width: _FluentTitleBarState.kIconInset))
        }
        rowChildren.append(contentsOf: [
            // The title is left-aligned, not centred: Windows reads the bar
            // left to right, and the trio at the right needs the whole rest
            // of the row.
            Expanded(
                child: Text(
                    w.title,
                    style: TextStyle(
                        color: titleColor,
                        fontSize: 12,
                        fontWeight: .w400, fontFamily: shellTheme.fontFamily),
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
                isMaximize: true,
                onTap: w.onMaximize
            ),
            _captionButton(
                icon: FluentSystemIcons.chromeClose,
                isClose: true,
                onTap: w.onClose
            ),
        ])

        return Listener(
            onPointerDown: { [self] event in
                if event.buttons & kSecondaryButton != 0 {
                    // The caption's system menu, at the pointer; no drag.
                    w.onContextMenu?(event.position)
                    return
                }
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
                    child: Row(children: rowChildren)
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
        isMaximize: Bool = false,
        onTap: (() -> Void)?
    ) -> Widget {
        return SizedBox(
            width: _FluentTitleBarState.kButtonWidth,
            height: DesktopTheme.kTitleBarHeight,
            child: HoverButton(
                builder: { [self] context, states in
                    if isMaximize { _maximizeContext = context }
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
                onPressed: onTap,
                onPointerEnter: isMaximize ? { [self] _ in
                    _snapHover.schedule(after: _FluentTitleBarState.kSnapHoverDelay) { [self] in
                        w.onMaximizeHover?(true, _maximizeRect())
                    }
                } : nil,
                onPointerExit: isMaximize ? { [self] _ in
                    _snapHover.cancel()
                    w.onMaximizeHover?(false, _maximizeRect())
                } : nil
            )
        )
    }
}
