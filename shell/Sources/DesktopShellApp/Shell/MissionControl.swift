// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Mission Control
//
// The spaces overview (macOS Mission Control): a strip of live space
// thumbnails along the top (click to switch, ✕ to remove, "+" to add) and
// an exposé grid of the ACTIVE space's windows below (click to focus, drag
// onto a thumbnail to move the window to that space). Modal: opened with
// Ctrl+Up or the wallpaper context menu, closed by Esc / Ctrl+Up / clicking
// the backdrop. Stored state lives in _DesktopShellState (extensions can't
// add stored properties); this file is pure UI + geometry.

private enum MC {
    static let thumbW: Double = 168
    static let thumbH: Double = 94.5   // 16:9, matches the panel aspect
    static let gap: Double = 18
    static let stripTop: Double = 22
    static let labelH: Double = 22
    /// Horizontal inset of the exposé area.
    static let exposeInsetX: Double = 64
    static let cellPad: Double = 22
    static let dragCardW: Double = 220
    static let clickSlop: Double = 8
}

extension _DesktopShellState {

    // MARK: Geometry

    /// Number of spaces shown in the strip. A workspace (always past the
    /// user spaces) is not a desktop and never appears here.
    private var _mcStripCount: Int {
        windowManager.spaces.count - windowManager.spaces.filter({ $0.isSpecial }).count
    }

    /// Frame of the space thumbnail at `index`; index == stripCount is
    /// the trailing "+" tile. The whole strip is centered horizontally.
    private func _mcThumbRect(_ index: Int) -> Rect {
        let count = _mcStripCount
        let totalW = Double(count + 1) * MC.thumbW + Double(count) * MC.gap
        let left = (screenWidth - totalW) / 2
        return Rect.fromLTWH(left + Double(index) * (MC.thumbW + MC.gap),
                             MC.stripTop, MC.thumbW, MC.thumbH)
    }

    /// The space-thumbnail index containing `p`, or nil (excludes "+").
    private func _mcThumbIndex(at p: Offset) -> Int? {
        for i in 0..<_mcStripCount {
            let r = _mcThumbRect(i)
            if p.dx >= r.left && p.dx < r.right && p.dy >= r.top && p.dy < r.bottom {
                return i
            }
        }
        return nil
    }

    private func _mcExposeArea() -> Rect {
        let top = MC.stripTop + MC.thumbH + MC.labelH + 26
        let bottom = screenHeight - DesktopTheme.kDockContainerHeight
            - DesktopTheme.kDockBottomMargin - 16
        return Rect.fromLTRB(MC.exposeInsetX, top, screenWidth - MC.exposeInsetX, bottom)
    }

    /// Exposé target rects for the active space's windows: a centered grid,
    /// each window scaled to fit its cell (never upscaled), stable order by
    /// window id so cards don't shuffle between rebuilds.
    private func _mcExposeRects() -> [(win: WindowInfo, rect: Rect)] {
        let ordered = windowManager.visibleWindows.sorted { $0.id < $1.id }
        guard !ordered.isEmpty else { return [] }
        let area = _mcExposeArea()
        let n = ordered.count
        let cols = Int(Double(n).squareRoot().rounded(.up))
        let rows = (n + cols - 1) / cols
        let cellW = area.width / Double(cols)
        let cellH = area.height / Double(rows)
        var out: [(WindowInfo, Rect)] = []
        for (i, win) in ordered.enumerated() {
            let row = i / cols
            let col = i % cols
            // Center a short last row.
            let inRow = row == rows - 1 ? n - (rows - 1) * cols : cols
            let rowLeft = area.left + (area.width - Double(inRow) * cellW) / 2
            let cellX = rowLeft + Double(col) * cellW
            let cellY = area.top + Double(row) * cellH
            let scale = min((cellW - MC.cellPad * 2) / win.rect.width,
                            (cellH - MC.cellPad * 2) / win.rect.height,
                            1.0)
            let w = win.rect.width * scale
            let h = win.rect.height * scale
            out.append((win, Rect.fromLTWH(cellX + (cellW - w) / 2,
                                           cellY + (cellH - h) / 2, w, h)))
        }
        return out
    }

    private func _mcLerpRect(_ a: Rect, _ b: Rect, _ t: Double) -> Rect {
        Rect.fromLTWH(a.left + (b.left - a.left) * t,
                      a.top + (b.top - a.top) * t,
                      a.width + (b.width - a.width) * t,
                      a.height + (b.height - a.height) * t)
    }

    // MARK: Pieces

    /// A window's live content, scaled to whatever box it's placed in.
    private func _mcWindowContent(_ win: WindowInfo, _ context: any BuildContext) -> Widget {
        guard let texId = win.textureId else {
            return win.appBuilder(context)
        }
        var content: Widget = TextureWidget(textureId: texId, filterQuality: .low)
        if win.flipTextureY {
            content = Transform(
                transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                alignment: Alignment.center,
                child: content
            )
        }
        return content
    }

    /// An exposé card: rounded live window content with a hairline border.
    private func _mcCard(_ win: WindowInfo, _ context: any BuildContext) -> Widget {
        return DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(color: Color(0x40FFFFFF), width: 1),
                borderRadius: BorderRadius.all(Radius(circular: 8)),
                boxShadow: [
                    BoxShadow(color: Color(0x66000000),
                              offset: Offset(0, 6), blurRadius: 18),
                ]
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: 8)),
                child: _mcWindowContent(win, context)
            )
        )
    }

    /// One space thumbnail: mini wallpaper + mini windows + border, with a
    /// ✕ badge on removable user desktops.
    private func _mcThumb(_ index: Int, _ context: any BuildContext) -> Widget {
        let wm = windowManager
        let space = wm.spaces[index]
        let isActive = index == wm.activeSpaceIndex
        let isDropTarget = _mcDragMoved && _mcDragPos.map { p in
            _mcThumbIndex(at: p) == index && space.isUser
        } ?? false
        let accent = shellTheme.accent

        let sx = MC.thumbW / screenWidth
        let sy = MC.thumbH / screenHeight

        var inner: [Widget] = []
        #if os(Linux)
        if wallpaperTextureId >= 0 {
            inner.append(Positioned(fill: (), child:
                TextureWidget(textureId: Int(wallpaperTextureId), filterQuality: .low)))
        } else {
            inner.append(Positioned(fill: (), child: DesktopBackground(preset: wallpaperPreset)))
        }
        #else
        inner.append(Positioned(fill: (), child: DesktopBackground(preset: wallpaperPreset)))
        #endif
        for win in wm.visibleWindows(inSpaceId: space.id) {
            // A card mid-flight into this thumbnail renders as the flying
            // departing card, not as a settled mini yet.
            if win.id == _mcDeparting?.id { continue }
            inner.append(Positioned(
                left: win.rect.left * sx, top: win.rect.top * sy,
                width: win.rect.width * sx, height: win.rect.height * sy,
                child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius(circular: 2)),
                    child: _mcWindowContent(win, context)
                )
            ))
        }

        let borderColor = isDropTarget ? accent
            : (isActive ? Color(0xFFFFFFFF) : Color(0x50FFFFFF))
        let thumb: Widget = DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: isActive || isDropTarget ? 2 : 1),
                borderRadius: BorderRadius.all(Radius(circular: 6))
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: 6)),
                child: Stack(children: inner)
            )
        )

        var layers: [Widget] = [
            Positioned(fill: (), child: GestureDetector(
                onTap: { [self] in
                    // Retarget the exposé instantly, then the animated close
                    // lands the new space's cards on their desktop rects.
                    if index != windowManager.activeSpaceIndex {
                        _switchToSpace(index, animated: false)
                    }
                    _closeMissionControlAnimated()
                },
                behavior: .opaque,
                child: thumb
            ))
        ]

        // ✕ badge: user desktops only, and never the last one.
        if space.isUser && wm.spaces.filter({ $0.isUser }).count > 1 {
            layers.append(Positioned(
                left: 5, top: 5, width: 18, height: 18,
                child: GestureDetector(
                    onTap: { [self] in
                        // Migrated windows may join the exposé — tween the
                        // grid to its new layout.
                        let fromRects = Dictionary(uniqueKeysWithValues:
                            _mcExposeRects().map { ($0.win.id, $0.rect) })
                        setState {
                            windowManager.removeSpace(at: index)
                        }
                        _mcStartRelayout(from: fromRects, departing: nil)
                    },
                    behavior: .opaque,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Color(0xCC202024),
                            border: Border.all(color: Color(0x60FFFFFF), width: 1),
                            borderRadius: BorderRadius.all(Radius(circular: 9))
                        ),
                        child: Center(child: Text("×", style: TextStyle(
                            color: Color(0xFFFFFFFF), fontSize: 12, fontWeight: .w600)))
                    )
                )
            ))
        }

        return Stack(children: layers)
    }

    /// Label under a thumbnail: "Desktop N" for user spaces, the window
    /// title for fullscreen spaces.
    private func _mcThumbLabel(_ index: Int) -> String {
        let wm = windowManager
        let space = wm.spaces[index]
        if case .fullscreen(let winId) = space.kind {
            let title = wm.windows.first(where: { $0.id == winId })?.title ?? "App"
            return String(title.prefix(20))
        }
        let userNumber = wm.spaces[0...index].filter { $0.isUser }.count
        return "Desktop \(userNumber)"
    }

    // MARK: Overlay

    func _buildMissionControl(_ context: any BuildContext) -> Widget {
        let wm = windowManager
        let t = _mcOpenCurve?.value ?? 1.0
        let settled = t >= 0.99

        var layers: [Widget] = []

        // Backdrop: wallpaper + dark tint; click exits to the current space.
        var backdrop: [Widget] = []
        #if os(Linux)
        if wallpaperTextureId >= 0 {
            backdrop.append(Positioned(fill: (), child:
                TextureWidget(textureId: Int(wallpaperTextureId), filterQuality: .low)))
        } else {
            backdrop.append(Positioned(fill: (), child: DesktopBackground(preset: wallpaperPreset)))
        }
        #else
        backdrop.append(Positioned(fill: (), child: DesktopBackground(preset: wallpaperPreset)))
        #endif
        backdrop.append(Positioned(fill: (), child: ColoredBox(
            color: shellTheme.overlayScrim, child: SizedBox(expand: ()))))
        layers.append(Positioned(fill: (), child: Listener(
            onPointerDown: { [self] _ in _closeMissionControlAnimated() },
            behavior: .opaque,
            child: Stack(children: backdrop)
        )))

        // Exposé cards, animating desktop rect -> grid rect on open (and,
        // during a re-flow, old grid rect -> new grid rect).
        let picking = _mcPickRecordTarget
        let relaying = !_mcRelayoutFrom.isEmpty || _mcDeparting != nil
        let rv = relaying ? (_mcRelayoutCurve?.value ?? 1.0) : 1.0
        for (win, target) in _mcExposeRects() {
            let winId = win.id
            let gridRect = _mcLerpRect(_mcRelayoutFrom[winId] ?? target, target, rv)
            let r = _mcLerpRect(win.rect, gridRect, t)
            let dragging = _mcDragMoved && _mcDragWindowId == winId
            // Picker: a card is a plain tap target that starts recording
            // its window — no drags, no focus change. Windows without a
            // recordable texture render dimmed and inert.
            if picking {
                let inner = _mcCard(win, context)
                let card: Widget = win.textureId != nil
                    ? GestureDetector(
                          onTap: { [self] in _startWindowRecording(win) },
                          behavior: .opaque,
                          child: inner)
                    : Opacity(opacity: 0.35, child: inner)
                layers.append(Positioned(
                    key: ValueKey("mc-\(winId)"),
                    left: r.left, top: r.top, width: r.width, height: r.height,
                    child: card
                ))
                if settled {
                    layers.append(Positioned(
                        left: r.left, top: r.bottom + 6, width: r.width, height: 18,
                        child: IgnorePointer(child: Center(child: Text(
                            String(win.title.prefix(32)),
                            style: TextStyle(color: shellTheme.overlayText, fontSize: 12,
                                             fontWeight: .w500))))
                    ))
                }
                continue
            }
            let card: Widget = Listener(
                onPointerDown: { [self] event in
                    setState {
                        _mcDragWindowId = winId
                        _mcDragStart = event.position
                        _mcDragPos = event.position
                        _mcDragMoved = false
                    }
                },
                onPointerMove: { [self] event in
                    guard _mcDragWindowId == winId else { return }
                    setState {
                        _mcDragPos = event.position
                        if let start = _mcDragStart, !_mcDragMoved {
                            let dx = event.position.dx - start.dx
                            let dy = event.position.dy - start.dy
                            if dx * dx + dy * dy > MC.clickSlop * MC.clickSlop {
                                _mcDragMoved = true
                            }
                        }
                    }
                },
                onPointerUp: { [self] event in
                    let moved = _mcDragMoved
                    let dropIndex = _mcThumbIndex(at: event.position)
                    setState {
                        _mcDragWindowId = nil
                        _mcDragStart = nil
                        _mcDragPos = nil
                        _mcDragMoved = false
                    }
                    if !moved {
                        // Click: focus the window and leave the overview.
                        setState { windowManager.bringToFront(winId) }
                        _closeMissionControlAnimated()
                        return
                    }
                    // Drop onto a user-space thumbnail moves the window
                    // there (fullscreen windows own their space and the
                    // private fullscreen spaces accept no guests). The
                    // dropped card flies into its mini-rect inside the
                    // thumbnail while the grid tweens to its new layout.
                    if let idx = dropIndex,
                       windowManager.spaces[idx].isUser,
                       !win.isFullscreen,
                       windowManager.spaces[idx].id != win.spaceId {
                        let fromRects = Dictionary(uniqueKeysWithValues:
                            _mcExposeRects().map { ($0.win.id, $0.rect) })
                        let w = MC.dragCardW
                        let h = w * win.rect.height / win.rect.width
                        let departFrom = Rect.fromLTWH(
                            event.position.dx - w / 2, event.position.dy - h / 2, w, h)
                        let thumb = _mcThumbRect(idx)
                        let sx = MC.thumbW / screenWidth
                        let sy = MC.thumbH / screenHeight
                        let departTo = Rect.fromLTWH(
                            thumb.left + win.rect.left * sx,
                            thumb.top + win.rect.top * sy,
                            win.rect.width * sx, win.rect.height * sy)
                        setState {
                            windowManager.moveWindow(winId, toSpaceIndex: idx)
                        }
                        _mcStartRelayout(from: fromRects,
                                         departing: (winId, departFrom, departTo))
                    }
                },
                behavior: .opaque,
                child: _mcCard(win, context)
            )
            // The dragged card is represented by the floating mini card;
            // dim its grid slot instead of moving it.
            layers.append(Positioned(
                key: ValueKey("mc-\(winId)"),
                left: r.left, top: r.top, width: r.width, height: r.height,
                child: dragging ? Opacity(opacity: 0.25, child: card) : card
            ))
            if settled && !dragging {
                layers.append(Positioned(
                    left: r.left, top: r.bottom + 6, width: r.width, height: 18,
                    child: IgnorePointer(child: Center(child: Text(
                        String(win.title.prefix(32)),
                        style: TextStyle(color: shellTheme.overlayText, fontSize: 12,
                                         fontWeight: .w500))))
                ))
            }
        }

        // Picker: the strip's place is taken by the instruction header —
        // space management has no business in a "choose a window" moment.
        if picking {
            layers.append(Positioned(
                left: 0, top: MC.stripTop + 18, width: screenWidth, height: 70,
                child: IgnorePointer(child: Column(children: [
                    Text("Choose a window to record",
                         style: TextStyle(color: shellTheme.overlayText,
                                          fontSize: 21, fontWeight: .w600)),
                    SizedBox(height: 7),
                    Text("Click a window to start recording — Esc cancels",
                         style: TextStyle(color: shellTheme.overlayTextDim,
                                          fontSize: 13, fontWeight: .w400)),
                ]))
            ))
            return Stack(children: layers)
        }

        // Spaces strip: thumbnails, labels, and the "+" tile. A workspace
        // is not part of the strip.
        for i in 0..<_mcStripCount {
            let r = _mcThumbRect(i)
            layers.append(Positioned(
                key: ValueKey("mc-thumb-\(wm.spaces[i].id)"),
                left: r.left, top: r.top, width: r.width, height: r.height,
                child: _mcThumb(i, context)
            ))
            layers.append(Positioned(
                left: r.left, top: r.bottom + 4, width: r.width, height: MC.labelH - 4,
                child: IgnorePointer(child: Center(child: Text(
                    _mcThumbLabel(i),
                    style: TextStyle(
                        color: i == wm.activeSpaceIndex ? Color(0xFFFFFFFF) : shellTheme.overlayTextDim,
                        fontSize: 12, fontWeight: .w500))))
            ))
        }
        let plusRect = _mcThumbRect(_mcStripCount)
        layers.append(Positioned(
            left: plusRect.left, top: plusRect.top,
            width: plusRect.width, height: plusRect.height,
            child: GestureDetector(
                onTap: { [self] in
                    setState { _ = windowManager.addSpace() }
                },
                behavior: .opaque,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x22FFFFFF),
                        border: Border.all(color: Color(0x50FFFFFF), width: 1),
                        borderRadius: BorderRadius.all(Radius(circular: 6))
                    ),
                    child: Center(child: Text("+", style: TextStyle(
                        color: Color(0xCCFFFFFF), fontSize: 30, fontWeight: .w300)))
                )
            )
        ))

        // A dropped card flying into its new thumbnail (over the strip).
        if let d = _mcDeparting,
           let departWin = wm.windows.first(where: { $0.id == d.id }) {
            let r = _mcLerpRect(d.from, d.to, rv)
            layers.append(Positioned(
                left: r.left, top: r.top, width: r.width, height: r.height,
                child: IgnorePointer(child: _mcCard(departWin, context))
            ))
        }

        // Floating mini card following the pointer during a drag.
        if _mcDragMoved,
           let dragId = _mcDragWindowId,
           let pos = _mcDragPos,
           let win = wm.windows.first(where: { $0.id == dragId }) {
            let w = MC.dragCardW
            let h = w * win.rect.height / win.rect.width
            layers.append(Positioned(
                left: pos.dx - w / 2, top: pos.dy - h / 2, width: w, height: h,
                child: IgnorePointer(child: _mcCard(win, context))
            ))
        }

        return Stack(children: layers)
    }

    /// Record-App picker card centers for the broker: tests click these
    /// instead of reproducing the grid arithmetic. Empty unless the picker
    /// is open; only recordable (textured) windows are listed.
    func recordPickerTargets() -> [(title: String, x: Double, y: Double)] {
        guard _missionControlOpen, _mcPickRecordTarget else { return [] }
        return _mcExposeRects()
            .filter { $0.win.textureId != nil }
            .map { ($0.win.title,
                    ($0.rect.left + $0.rect.right) / 2,
                    ($0.rect.top + $0.rect.bottom) / 2) }
    }

    /// Kick the grid re-flow tween: surviving cards lerp old->new grid
    /// rects; `departing` (window id, start rect, thumbnail mini-rect) flies
    /// into its new space's thumbnail.
    func _mcStartRelayout(from: [String: Rect], departing: (String, Rect, Rect)?) {
        _mcRelayoutFrom = from
        _mcDeparting = departing.map { (id: $0.0, from: $0.1, to: $0.2) }
        if _mcRelayoutController == nil {
            let c = AnimationController(duration: .milliseconds(260), vsync: self)
            c.addListener { [weak self] in
                self?.setState {}
            }
            c.addStatusListener { [weak self] status in
                guard let self, status == .completed else { return }
                self.setState {
                    self._mcRelayoutFrom = [:]
                    self._mcDeparting = nil
                }
            }
            _mcRelayoutController = c
            _mcRelayoutCurve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic)
        }
        _ = _mcRelayoutController?.forward(from: 0)
    }
}
