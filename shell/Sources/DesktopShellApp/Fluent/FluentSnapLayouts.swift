// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Two pieces of Windows 11 window chrome that hang off the caption:
//
//   - the SYSTEM MENU a right-click on the caption opens (Restore, Move,
//     Size, Minimize, Maximize, Close — Windows' order, with Move and Size
//     present but disabled: they start keyboard-driven modes this shell
//     does not have yet, and Windows greys them out for a maximized window
//     anyway);
//   - SNAP LAYOUTS, the flyout that appears when the pointer rests on the
//     maximize control: six ways to divide the work area, each zone a
//     target that puts the window there.
//
// Both are positioned widgets in the shell's root stack, like every shell
// popup — there is no Overlay in the shell tree, so the SDK's MenuFlyout is
// used for its CONTENT and the shell owns placing and dismissing it. The
// menu sits inside its own FluentTheme because the SDK's controls read one
// and the shell tree carries none.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

// MARK: - Snap zones

/// A zone of the work area, as fractions of it.
struct SnapZone: Equatable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    func rect(in area: Rect) -> Rect {
        Rect.fromLTWH(area.left + area.width * x, area.top + area.height * y,
                      area.width * w, area.height * h)
    }

    static let leftHalf = SnapZone(x: 0, y: 0, w: 0.5, h: 1)
    static let rightHalf = SnapZone(x: 0.5, y: 0, w: 0.5, h: 1)
}

/// One of the flyout's layouts: the zones it offers.
struct SnapLayout {
    let zones: [SnapZone]

    /// Windows 11's six, in the flyout's order: halves; two-thirds and a
    /// third; three columns; a half beside two quarters; four quarters;
    /// a third and two-thirds.
    static let all: [SnapLayout] = [
        SnapLayout(zones: [.leftHalf, .rightHalf]),
        SnapLayout(zones: [SnapZone(x: 0, y: 0, w: 2 / 3, h: 1),
                           SnapZone(x: 2 / 3, y: 0, w: 1 / 3, h: 1)]),
        SnapLayout(zones: [SnapZone(x: 0, y: 0, w: 1 / 3, h: 1),
                           SnapZone(x: 1 / 3, y: 0, w: 1 / 3, h: 1),
                           SnapZone(x: 2 / 3, y: 0, w: 1 / 3, h: 1)]),
        SnapLayout(zones: [.leftHalf,
                           SnapZone(x: 0.5, y: 0, w: 0.5, h: 0.5),
                           SnapZone(x: 0.5, y: 0.5, w: 0.5, h: 0.5)]),
        SnapLayout(zones: [SnapZone(x: 0, y: 0, w: 0.5, h: 0.5),
                           SnapZone(x: 0.5, y: 0, w: 0.5, h: 0.5),
                           SnapZone(x: 0, y: 0.5, w: 0.5, h: 0.5),
                           SnapZone(x: 0.5, y: 0.5, w: 0.5, h: 0.5)]),
        SnapLayout(zones: [SnapZone(x: 0, y: 0, w: 1 / 3, h: 1),
                           SnapZone(x: 1 / 3, y: 0, w: 2 / 3, h: 1)]),
    ]
}

/// The flyout's geometry. A layout tile is a small picture of the work
/// area; the zones inside it are separated by a hairline gap.
enum SnapFlyoutMetrics {
    static let tileWidth: Double = 60
    static let tileHeight: Double = 40
    static let zoneGap: Double = 2
    static let columns = 3
    /// Gap between the caption control and the flyout.
    static let drop: Double = 4
}

// MARK: - The shell's builders

extension _DesktopShellState {

    /// The caption's system menu, or nil when none is open.
    func fluentWindowMenu() -> Widget? {
        guard let menu = _windowMenu,
              let win = windowManager.windows.first(where: { $0.id == menu.winId })
        else { return nil }
        let winId = menu.winId
        func pick(_ action: @escaping () -> Void) -> () -> Void {
            { [self] in
                setState { _windowMenu = nil }
                action()
            }
        }
        let maximized = win.isMaximized
        let items: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Restore"),
                           leading: Icon(FluentSystemIcons.chromeRestore, size: 16),
                           onPressed: maximized ? pick { [self] in requestWindowMaximize(winId) } : nil),
            MenuFlyoutItem(text: Text("Move")),
            MenuFlyoutItem(text: Text("Size")),
            MenuFlyoutItem(text: Text("Minimize"),
                           leading: Icon(FluentSystemIcons.chromeMinimize, size: 16),
                           onPressed: pick { [self] in requestWindowMinimize(winId) }),
            MenuFlyoutItem(text: Text("Maximize"),
                           leading: Icon(FluentSystemIcons.chromeMaximize, size: 16),
                           onPressed: maximized ? nil : pick { [self] in requestWindowMaximize(winId) }),
            MenuFlyoutSeparator(),
            MenuFlyoutItem(text: Text("Close"),
                           leading: Icon(FluentSystemIcons.chromeClose, size: 16),
                           trailing: Text("Alt+F4"),
                           onPressed: pick { [self] in requestWindowClose(winId) }),
        ]
        return Positioned(left: menu.at.dx, top: menu.at.dy, child: fluentShellMenu(items))
    }

    /// Where the flyout lands for a control at `anchor`: centred under it,
    /// kept on screen. Computed once when it opens, so the shell's pointer
    /// tracking and the widget agree on the rectangle.
    func fluentSnapLayoutsFrame(anchor: Rect) -> Rect {
        let m = SnapFlyoutMetrics.self
        let rows = (SnapLayout.all.count + m.columns - 1) / m.columns
        let pad = FluentSpacing.s
        let gap = FluentSpacing.s
        let width = Double(m.columns) * m.tileWidth + Double(m.columns - 1) * gap + pad * 2
        let height = Double(rows) * m.tileHeight + Double(rows - 1) * gap + pad * 2
        let left = min(max(anchor.center.dx - width / 2, FluentSpacing.s),
                       screenWidth - width - FluentSpacing.s)
        return Rect.fromLTWH(left, anchor.bottom + m.drop, width, height)
    }

    /// Snap layouts, hung under the maximize control it was opened from.
    func fluentSnapLayouts() -> Widget? {
        guard let flyout = _snapFlyout else { return nil }
        let m = SnapFlyoutMetrics.self
        let rows = (SnapLayout.all.count + m.columns - 1) / m.columns
        let pad = FluentSpacing.s
        let gap = FluentSpacing.s
        let frame = flyout.frame
        let winId = flyout.winId

        let tiles: [Widget] = SnapLayout.all.map { layout in
            _SnapLayoutTile(layout: layout) { [self] zone in
                requestWindowSnap(winId, zone)
            }
        }
        var rowWidgets: [Widget] = []
        for r in 0..<rows {
            let slice = Array(tiles[(r * m.columns)..<min((r + 1) * m.columns, tiles.count)])
            rowWidgets.append(Row(mainAxisSize: .min, spacing: gap, children: slice))
        }

        let panel: Widget = DecoratedBox(
            decoration: BoxDecoration(
                color: shellTheme.panelFill,
                border: Border.all(color: shellTheme.panelStroke, width: FluentStrokeWidth.thin),
                borderRadius: FluentCorners.overlayRadius,
                boxShadow: FluentElevation.shadows(
                    FluentElevation.flyout, brightness: shellTheme.isDark ? .dark : .light)),
            child: Padding(
                padding: EdgeInsets(all: pad),
                child: Column(mainAxisSize: .min, spacing: gap, children: rowWidgets)))

        return Positioned(
            left: frame.left, top: frame.top, width: frame.width, height: frame.height,
            child: FluentEntrance(child: panel))
    }
}

// MARK: - A layout tile

/// One layout: its zones drawn to scale inside a tile, each a hover target
/// that fills with the accent, and a click that snaps the window there.
private final class _SnapLayoutTile: StatelessWidget {
    let layout: SnapLayout
    let onPick: (SnapZone) -> Void

    init(layout: SnapLayout, onPick: @escaping (SnapZone) -> Void) {
        self.layout = layout
        self.onPick = onPick
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let m = SnapFlyoutMetrics.self
        let zones: [Widget] = layout.zones.map { zone in
            // Each zone is inset by half the gap so neighbours sit a gap apart.
            let inset = m.zoneGap / 2
            return Positioned(
                left: zone.x * m.tileWidth + inset,
                top: zone.y * m.tileHeight + inset,
                width: zone.w * m.tileWidth - m.zoneGap,
                height: zone.h * m.tileHeight - m.zoneGap,
                child: HoverButton(
                    builder: { _, states in
                        let hot = states.isHovered || states.isPressed
                        return DecoratedBox(
                            decoration: BoxDecoration(
                                color: hot ? shellTheme.accent : shellTheme.controlFill,
                                border: Border.all(color: shellTheme.controlStroke,
                                                   width: FluentStrokeWidth.thin),
                                borderRadius: BorderRadius.circular(FluentCorners.small)),
                            child: SizedBox(expand: ()))
                    },
                    onPressed: { [self] in onPick(zone) }))
        }
        return SizedBox(
            width: m.tileWidth, height: m.tileHeight,
            child: Stack(children: zones))
    }
}
