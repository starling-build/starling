// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Window content

/// A window's live texture, the way every painter of it must draw it: cropped
/// to `textureCrop` when the window is one rectangle of a shared texture, and
/// Y-flipped when the buffer is bottom-up. One function, because the desktop
/// window, the Mission Control card and the workspace pane each drew this
/// themselves — and a crop honoured by one of them and not the others shows
/// a guest app in its window and the whole guest desktop in its thumbnail.
///
/// The flip is a `Transform` about the box's centre, which mirrors the WHOLE
/// oversized quad the crop paints — so the crop itself has to be mirrored
/// first, or the flipped box shows the region the same distance from the
/// other edge. `crop` is in upright coordinates; this is where the two meet.
func windowTextureContent(_ win: WindowInfo, textureId: Int,
                          filterQuality: FilterQuality) -> Widget {
    var crop = win.textureCrop
    if let c = crop, win.flipTextureY {
        crop = Rect.fromLTWH(c.left, 1.0 - c.top - c.height, c.width, c.height)
    }
    var content: Widget = TextureWidget(textureId: textureId,
                                        filterQuality: filterQuality, crop: crop)
    if crop != nil {
        content = ClipRect(child: content)
    }
    if win.flipTextureY {
        content = Transform(
            transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
            alignment: Alignment.center,
            child: content
        )
    }
    return content
}

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
        let texture = windowTextureContent(windowInfo, textureId: texId,
                                           filterQuality: .low)
        guard let forward = windowInfo.onPointerEvent else {
            // No pointer forwarding (native Flutter content) — still listen
            // for hover so the cursor resets to the default arrow when the
            // mouse leaves a resize edge.
            return Listener(
                onPointerHover: { [windowInfo] _ in
                    if let own = windowInfo.onPointerHoverCursor { own() }
                    else { DesktopCursor.setShape(.default) }
                },
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
            onPointerHover: { [windowInfo] event in
                if let own = windowInfo.onPointerHoverCursor { own() }
                else { DesktopCursor.setShape(.default) }
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
        let cornerRadius = isFullscreen ? 0.0 : DesktopTheme.kWindowCornerRadius
        let borderColor = isFullscreen ? Color(0x00000000)
            : (isFocused ? shellTheme.windowBorderFocused : shellTheme.windowBorderUnfocused)

        // Traffic lights on the left, or a caption trio on the right: which
        // one is the active style's business, not this window's.
        let titleBar = shellStyle.makeTitleBar(TitleBarParams(
            title: windowInfo.title,
            isFocused: isFocused,
            isMaximized: windowInfo.isMaximized,
            isFullscreen: isFullscreen,
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

        // Liquid-glass backdrop: frost whatever sits behind the window
        // (wallpaper, other windows) inside the rounded clip. The title bar
        // and any translucency the app leaves in its buffer show it
        // through; opaque content simply covers it. Skipped in fullscreen —
        // content is edge-to-edge and the blur would be pure cost.
        if !isFullscreen {
            stackChildren.append(
                Positioned(
                    fill: (),
                    child: IgnorePointer(
                        child: ClipRect(
                            child: BackdropFilter(
                                filter: ShellPalette.frostFilter(blurSigma: 18),
                                child: ColoredBox(
                                    color: shellTheme.windowGlassTint,
                                    child: SizedBox(expand: ())
                                )
                            )
                        )
                    )
                )
            )
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
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: cornerRadius)),
                child: Stack(children: stackChildren)
            )
        )
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
