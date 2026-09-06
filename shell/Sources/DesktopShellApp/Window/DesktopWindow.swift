// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - DesktopWindow

/// A single desktop window with title bar chrome, content area, and resize handles.
/// Clicking anywhere in the window brings it to front.
class DesktopWindow: StatelessWidget {

    private func _buildContentArea(_ context: any BuildContext) -> Widget {
        guard let texId = windowInfo.textureId else {
            return windowInfo.appBuilder(context)
        }
        // No sourceRect needed — MAXIMIZED state tells Chrome to skip CSD
        // shadows, so the buffer matches the content area exactly (like
        // Hyprland). The texture stretches to fill the content area.
        var content: Widget = TextureWidget(textureId: texId, filterQuality: .low)
        if windowInfo.flipTextureY {
            content = Transform(
                transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                alignment: Alignment.center,
                child: content
            )
        }
        let texture = content
        guard let forward = windowInfo.onPointerEvent else {
            // No pointer forwarding (native Flutter content) — still listen
            // for hover so the cursor resets to the default arrow when the
            // mouse leaves a resize edge.
            return Listener(
                onPointerHover: { _ in DesktopCursor.setShape(.default) },
                behavior: .deferToChild,
                child: texture
            )
        }
        // Wrap with Listener to capture pointer events and forward to child process.
        // behavior: .opaque ensures hit-testing succeeds even though TextureWidget
        // (a LeafRenderObjectWidget) doesn't report hits by default.
        return Listener(
            onPointerDown: { event in
                forward(2, event.localPosition.dx, event.localPosition.dy,
                        Int64(event.buttons))
            },
            onPointerMove: { [self, windowInfo] event in
                // Client-initiated interactive move/resize (xdg_toplevel.move/
                // resize): the compositor owns the rest of this drag. Divert
                // motion into window move/resize; the client stops receiving
                // pointer events until release. Flutter routes the whole
                // gesture here because the pointer-down hit this Listener.
                if windowInfo.interactiveMoveActive || windowInfo.interactiveResizeEdge != nil {
                    let last = windowInfo.interactiveLastPos ?? event.position
                    let delta = Offset(event.position.dx - last.dx,
                                       event.position.dy - last.dy)
                    windowInfo.interactiveLastPos = event.position
                    if windowInfo.interactiveMoveActive {
                        onMove?(delta)
                    } else if let edge = windowInfo.interactiveResizeEdge {
                        onResize?(edge, delta)
                    }
                    return
                }
                forward(3, event.localPosition.dx, event.localPosition.dy,
                        Int64(event.buttons))
            },
            onPointerUp: { [windowInfo] event in
                // End of a client-initiated move/resize: clear the grab and,
                // for resize, force-send the final configure (same contract
                // as the shell's own resize handles).
                if windowInfo.interactiveMoveActive || windowInfo.interactiveResizeEdge != nil {
                    let wasResize = windowInfo.interactiveResizeEdge != nil
                    windowInfo.interactiveMoveActive = false
                    windowInfo.interactiveResizeEdge = nil
                    windowInfo.interactiveLastPos = nil
                    if wasResize, let target = windowInfo.targetRect {
                        let contentW = target.width
                        let contentH = target.height - DesktopTheme.kTitleBarHeight
                        if contentW > 0 && contentH > 0 {
                            windowInfo.onResizeComplete?(contentW, contentH)
                        }
                    }
                }
                forward(1, event.localPosition.dx, event.localPosition.dy, 0)
            },
            onPointerHover: { event in
                DesktopCursor.setShape(.default)
                forward(6, event.localPosition.dx, event.localPosition.dy, 0)
            },
            onPointerSignal: { [windowInfo] event in
                if let scroll = event as? PointerScrollEvent {
                    windowInfo.onScrollEvent?(
                        scroll.localPosition.dx,
                        scroll.localPosition.dy,
                        scroll.scrollDelta.dx,
                        scroll.scrollDelta.dy
                    )
                }
            },
            behavior: .opaque,
            child: texture
        )
    }

    let windowInfo: WindowInfo
    let isFocused: Bool
    /// In fullscreen mode, whether the title bar should be visible because
    /// the cursor is currently in the system status bar area. Ignored when
    /// the window is not fullscreen (title bar is always shown then).
    let isTopBarRevealed: Bool
    /// The owning app's icon at 16px, for a title bar that shows one.
    let appIcon: Widget?
    let onBringToFront: (() -> Void)?
    let onMove: ((Offset) -> Void)?
    let onResize: ((ResizeEdge, Offset) -> Void)?
    let onMinimize: (() -> Void)?
    let onMaximize: (() -> Void)?
    let onClose: (() -> Void)?
    /// macOS-style: double-click on the title bar toggles maximized state.
    let onTitleBarDoubleTap: (() -> Void)?

    init(
        windowInfo: WindowInfo,
        isFocused: Bool,
        isTopBarRevealed: Bool = false,
        appIcon: Widget? = nil,
        onBringToFront: (() -> Void)? = nil,
        onMove: ((Offset) -> Void)? = nil,
        onResize: ((ResizeEdge, Offset) -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        onMaximize: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onTitleBarDoubleTap: (() -> Void)? = nil
    ) {
        self.windowInfo = windowInfo
        self.isFocused = isFocused
        self.isTopBarRevealed = isTopBarRevealed
        self.appIcon = appIcon
        self.onBringToFront = onBringToFront
        self.onMove = onMove
        self.onResize = onResize
        self.onMinimize = onMinimize
        self.onMaximize = onMaximize
        self.onClose = onClose
        self.onTitleBarDoubleTap = onTitleBarDoubleTap
    }

    override func build(_ context: any BuildContext) -> Widget {
        let isFullscreen = windowInfo.isFullscreen
        // Fullscreen squares every style's corners; maximized squares them
        // where the style says so (Windows does, macOS does not).
        let isSquare = isFullscreen
            || (windowInfo.isMaximized && shellMetrics.squareWhenMaximized)
        let cornerRadius = isSquare ? 0.0 : DesktopTheme.kWindowCornerRadius
        let borderColor = isFullscreen ? Color(0x00000000)
            : (isFocused ? shellTheme.windowBorderFocused : shellTheme.windowBorderUnfocused)

        // Traffic lights on the left, or a caption trio on the right: which
        // one is the active style's business, not this window's.
        let titleBar = shellStyle.makeTitleBar(TitleBarParams(
            title: windowInfo.title,
            isFocused: isFocused,
            isMaximized: windowInfo.isMaximized,
            isFullscreen: isFullscreen,
            icon: appIcon,
            onMove: onMove,
            onMinimize: onMinimize,
            onMaximize: onMaximize,
            onClose: onClose,
            onDoubleTap: onTitleBarDoubleTap
        ))

        let windowBody: Widget
        if isFullscreen {
            // Fullscreen: content fills the whole window. The title bar
            // overlays at the top only while the shell is revealing the
            // system status bar (cursor in the top edge of the screen).
            //
            // The backing is the OPAQUE version of the window material.
            // Windowed content sits on the liquid-glass backdrop below;
            // fullscreen rightly skips that blur (nothing meaningful to
            // frost), but skipping the backing entirely let every
            // translucent app surface composite straight onto the
            // wallpaper — a fullscreen window looked like a ghost of
            // itself. macOS resolves fullscreen materials against an
            // opaque base; do the same with the glass tint at full alpha.
            let tint = shellTheme.windowGlassTint
            let opaqueBase = Color(
                alpha: 1.0, red: tint.r, green: tint.g, blue: tint.b)
            var bodyChildren: [Widget] = [
                Positioned(
                    fill: (),
                    child: ColoredBox(
                        color: opaqueBase, child: SizedBox(expand: ()))
                ),
                Positioned(
                    fill: (),
                    child: ClipRect(child: _buildContentArea(context))
                )
            ]
            if isTopBarRevealed {
                bodyChildren.append(
                    Positioned(
                        left: 0, top: 0, right: 0,
                        height: DesktopTheme.kTitleBarHeight,
                        child: titleBar
                    )
                )
            }
            windowBody = Stack(children: bodyChildren)
        } else {
            // Non-fullscreen window: title bar always visible above content.
            windowBody = Column(
                children: [
                    titleBar,
                    Expanded(child: ClipRect(child: _buildContentArea(context))),
                ]
            )
        }

        var stackChildren: [Widget] = []

        // The window's material, under the title bar and whatever
        // translucency the app leaves in its buffer; opaque content simply
        // covers it. Skipped in fullscreen — content is edge-to-edge.
        //
        // Glass (macOS) is a live blur of what sits behind the window,
        // tinted. Mica (Windows) is NOT a blur: one wallpaper sample resolved
        // into an opaque colour, once, which is what makes it cheap enough
        // for every window — so the acrylic material paints a flat fill and
        // no BackdropFilter at all. The focused window gets the material,
        // the rest the style's inactive surface.
        if !isFullscreen {
            let surface = isFocused
                ? shellTheme.windowGlassTint
                : shellTheme.windowSurfaceInactive
            let fill: Widget = ColoredBox(color: surface, child: SizedBox(expand: ()))
            let material: Widget
            switch shellTheme.material {
            case .glass:
                material = ClipRect(
                    child: BackdropFilter(
                        filter: ShellPalette.frostFilter(blurSigma: 18),
                        child: fill))
            case .acrylic:
                material = fill
            }
            stackChildren.append(
                Positioned(fill: (), child: IgnorePointer(child: material)))
        }
        stackChildren.append(windowBody)

        // Border overlay (skip in fullscreen)
        if !isFullscreen {
            stackChildren.append(
                Positioned(
                    fill: (),
                    child: IgnorePointer(
                        child: _WindowBorder(color: borderColor, cornerRadius: cornerRadius)
                    )
                )
            )
        }

        // Resize handles are always rendered — including fullscreen/maximized,
        // since dragging an edge implicitly demotes the window to a free state
        // (handled in WindowManager.resizeWindow).
        stackChildren.append(
            Positioned(
                fill: (),
                child: WindowResizeHandles(
                    windowWidth: windowInfo.rect.width,
                    windowHeight: windowInfo.rect.height,
                    onResize: onResize,
                    onResizeDragStart: { [windowInfo] in
                        windowInfo.targetRect = windowInfo.rect
                    },
                    onResizeDragEnd: { [windowInfo] in
                        if let target = windowInfo.targetRect {
                            let contentW = target.width
                            let contentH = target.height - DesktopTheme.kTitleBarHeight
                            if contentW > 0 && contentH > 0 {
                                windowInfo.onResizeComplete?(contentW, contentH)
                            }
                        }
                    }
                )
            )
        )

        return Listener(
            onPointerDown: { [self] _ in
                onBringToFront?()
            },
            behavior: .deferToChild,
            child: _shadowed(
                ClipRRect(
                    borderRadius: BorderRadius.all(Radius(circular: cornerRadius)),
                    child: Stack(children: stackChildren)
                ),
                cornerRadius: cornerRadius,
                square: isSquare)
        )
    }

    /// The style's window shadow, painted OUTSIDE the rounded clip (a
    /// decoration casts beyond its box; the clip inside it does not reach
    /// the shadow). None for a square window: maximized and fullscreen
    /// windows meet the work area's edges and cast nothing.
    private func _shadowed(_ child: Widget, cornerRadius: Double, square: Bool) -> Widget {
        let shadow = shellTheme.windowShadow
        guard !square, !shadow.isEmpty else { return child }
        return DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius(circular: cornerRadius)),
                boxShadow: shadow),
            child: child)
    }
}

// MARK: - _WindowBorder

/// Paints a thin border around the window using CustomPainter.
private class _WindowBorder: StatelessWidget {

    let color: Color
    let cornerRadius: Double

    init(color: Color, cornerRadius: Double = DesktopTheme.kWindowCornerRadius) {
        self.color = color
        self.cornerRadius = cornerRadius
    }

    override func build(_ context: any BuildContext) -> Widget {
        return CustomPaint(
            painter: _WindowBorderPainter(color: color, cornerRadius: cornerRadius),
            child: SizedBox(expand: ())
        )
    }
}

private class _WindowBorderPainter: CustomPainter {
    let color: Color
    let cornerRadius: Double

    init(color: Color, cornerRadius: Double) {
        self.color = color
        self.cornerRadius = cornerRadius
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let paint = Paint()
        paint.color = color
        paint.style = .stroke
        paint.strokeWidth = 1.0

        canvas.drawRRect(
            RRect(
                fromRectAndRadius: Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
                Radius(circular: cornerRadius)
            ),
            paint
        )
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? _WindowBorderPainter else { return true }
        return old.color != color || old.cornerRadius != cornerRadius
    }
}
