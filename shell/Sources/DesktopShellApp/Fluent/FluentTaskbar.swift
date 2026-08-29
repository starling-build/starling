// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The taskbar: the Fluent style's whole chrome, on the bottom edge.
//
// It replaces TWO macOS surfaces at once — the menu bar along the top and the
// floating dock along the bottom — and that is the point rather than a
// shortcut. Windows puts its shell chrome on one edge; two strips to reach for
// is worse than one wherever they sit, and the top of the screen goes back to
// being the user's.
//
// It is a FULL-WIDTH BAR, not a floating slab. A slab is the macOS shape and
// leaves wallpaper showing on both sides of a strip; the tiles are still
// centred, Windows 11 style, but the bar under them runs edge to edge. It also
// RESERVES its strip, where the dock only floats over one: a maximized window
// stops above the taskbar rather than sliding under it.
//
// The geometry here is duplicated once, in `FluentChrome.barSlots` — the
// broker serves those to tooling so `shell-drive.py dock NAME` clicks the real
// tile. Both derive from the constants below; change them here.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The Fluent type ramp, rather than point sizes chosen by eye.
///
/// `body`, `bodyStrong` and `caption` are a system with sizes and weights
/// Microsoft picked; the first cut of this chrome set 11, 12 and 13 by hand
/// and so was approximately right everywhere and exactly right nowhere. The
/// face is still ours to supply (Selawik, via `shellTheme.fontFamily`) --
/// the ramp brings the sizes and weights.
var fluentType: Typography {
    (shellTheme.isDark ? FluentThemeData.dark() : FluentThemeData.light())
        .typography
}

extension Typography {
    /// One ramp entry, in a colour, in the active style's face.
    /// `Flutter.TextStyle` spelled out: the bridge exports a `TextStyle` too,
    /// and while expression position resolves fine, a type annotation is
    /// ambiguous between them.
    func styled(_ pick: (Typography) -> Flutter.TextStyle?, _ color: Color,
                strong: Bool = false) -> Flutter.TextStyle {
        let base = pick(self) ?? Flutter.TextStyle(color: color, fontSize: 13)
        return base.copyWith(
            color: color,
            fontFamily: strong ? shellTheme.fontFamilyStrong
                               : shellTheme.fontFamily)
    }
}

// MARK: - Geometry

// The numbers are our WINDOWS shell's, not guesses and not re-derived:
// `kDockHeight`, `kDockIcon` and `kDockTile` in
// sdk/Examples/WinShellBar/Dock.swift, which were tuned sitting next to real
// Explorer. Taking them wholesale is the point -- the two shells should be the
// same product on two operating systems, and a Linux bar 48 tall with 24pt
// icons next to a Windows one that is 56 with 34 is simply wrong twice.
enum FluentBar {
    /// The strip, and the reason it is not a dock's height: a solid bar
    /// across the screen cannot afford what a floating slab can.
    static let height: Double = 56
    /// One tile's box, and the gap between two of them.
    static let tile: Double = 48        // kDockTile = kDockIcon + 14
    static let gap: Double = 4
    /// Centre-to-centre.
    static var pitch: Double { tile + gap }
    /// The app icon inside a tile.
    static let icon: Double = 34
    /// The running indicator: a rounded bar under the tile, longer for the
    /// window that currently has focus.
    static let indicatorHeight: Double = 3
    static let indicatorRunning: Double = 6
    static let indicatorFocused: Double = 16

    /// Total width of a cluster of `count` tiles (Start included).
    static func clusterWidth(count: Int) -> Double {
        count <= 0 ? 0 : Double(count) * pitch - gap
    }

    /// Left edge of the centred cluster on an output `outputWidth` wide.
    static func clusterLeft(count: Int, outputWidth: Double) -> Double {
        (outputWidth - clusterWidth(count: count)) / 2
    }

    /// Centre of tile `index` (0 = Start), in the output's coordinates.
    static func tileCenterX(index: Int, count: Int, outputWidth: Double) -> Double {
        clusterLeft(count: count, outputWidth: outputWidth)
            + Double(index) * pitch + tile / 2
    }
}

// MARK: - Data

/// One app on the bar. The visual is built by the shell (texture or painted
/// tile) so this file never has to know how an icon is drawn.
struct TaskbarTile {
    let appId: String
    let name: String
    let visual: Widget
    let isRunning: Bool
    /// Whether this app owns the focused window — a longer indicator, as on
    /// Windows.
    let isFocused: Bool
}

/// The right-hand readout. Windows groups the status glyphs into ONE button
/// that opens Quick Settings, and gives the clock its own, which opens the
/// notification centre.
struct TaskbarStatus {
    let statusIcons: [IconData]
    let statusActive: Bool
    /// Formats, not rendered text — the clock renders itself so that it can
    /// keep its own cadence (`ShellClock`).
    let clockFormat: String
    let dateFormat: String
    let clockActive: Bool
    /// The bell only appears when something has been collected, and tints
    /// until the user has looked at it.
    let showBell: Bool
    let bellTinted: Bool
    let bellActive: Bool
}

// MARK: - FluentTaskbar

class FluentTaskbar: StatelessWidget {
    let tiles: [TaskbarTile]
    let status: TaskbarStatus
    let outputWidth: Double
    let startActive: Bool
    /// Which tile the pointer is over (0 = Start), or nil.
    ///
    /// Tracked by the SHELL, from the global pointer hook, rather than by a
    /// Listener per tile — that is the only place a LEAVE is visible. A
    /// per-tile hover sets itself happily and then never hears that the
    /// pointer went up onto a window, so the name label sticks there forever.
    let hoveredIndex: Int?

    let onStart: () -> Void
    let onTile: (String) -> Void
    let onTileMenu: (String) -> Void
    let onStatus: () -> Void
    let onClock: () -> Void
    let onBell: () -> Void

    init(tiles: [TaskbarTile], status: TaskbarStatus, outputWidth: Double,
         startActive: Bool, hoveredIndex: Int?,
         onStart: @escaping () -> Void,
         onTile: @escaping (String) -> Void,
         onTileMenu: @escaping (String) -> Void,
         onStatus: @escaping () -> Void,
         onClock: @escaping () -> Void,
         onBell: @escaping () -> Void) {
        self.tiles = tiles
        self.status = status
        self.outputWidth = outputWidth
        self.startActive = startActive
        self.hoveredIndex = hoveredIndex
        self.onStart = onStart
        self.onTile = onTile
        self.onTileMenu = onTileMenu
        self.onStatus = onStatus
        self.onClock = onClock
        self.onBell = onBell
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Everything is anchored to the BOTTOM of the layout box, not stretched
        // to fill it: the box is taller than the strip so the hover label has
        // somewhere to draw, and that headroom must stay unpainted and
        // click-through.
        var layers: [Widget] = [
            Positioned(
                left: 0, right: 0, bottom: 0, height: FluentBar.height,
                // Acrylic, not a painted slab: the strip is a blur of the
                // desktop behind it with the bar's tint over the top. That
                // translucency is most of what makes a Windows taskbar read
                // as one — an opaque bar in the same colour looks like a
                // black rectangle laid on the wallpaper.
                child: Listener(
                    onPointerHover: { _ in DesktopCursor.setShape(.default) },
                    behavior: .opaque,
                    // SOLID, deliberately. Windows' taskbar measures the same
                    // colour straight across whatever is behind it -- see the
                    // reference capture -- so the strip is the flat WinUI
                    // surface colour and nothing more. Acrylic was tried here
                    // and is not what the real one looks like; the blur only
                    // made the bar harder to read against a busy wallpaper.
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: shellTheme.barFill,
                            border: Border(
                                top: BorderSide(
                                    color: shellTheme.barHairline, width: 1)
                            )
                        ),
                        child: SizedBox(expand: ())
                    )
                )
            )
        ]

        let count = tiles.count + 1  // Start, then the apps
        let left = FluentBar.clusterLeft(count: count, outputWidth: outputWidth)

        // The status readout spans the FULL width and right-aligns inside it,
        // rather than being anchored by its right edge alone: a `Positioned`
        // with `right` and no width leaves the child to size itself, and the
        // buttons then paint in the right place while their hit boxes collapse
        // — visible, and dead to the pointer.
        //
        // It goes in BELOW the tiles for the same reason: a full-width layer
        // above them would swallow the middle of the bar. The Row itself never
        // claims a hit, so the empty stretch stays click-through.
        layers.append(Positioned(
            left: 0, right: 0, bottom: 0, height: FluentBar.height,
            child: Row(mainAxisAlignment: .end, crossAxisAlignment: .center) {
                _statusCluster()
            }
        ))

        // The tile cluster is centred on the SCREEN, not on the space left
        // over by the status readout — that is what keeps it still as apps
        // open and close on the right. A Stack rather than a Row for exactly
        // that.
        layers.append(Positioned(
            left: left, bottom: (FluentBar.height - FluentBar.tile) / 2,
            width: FluentBar.clusterWidth(count: count), height: FluentBar.tile,
            child: Row(mainAxisSize: .min, spacing: FluentBar.gap) {
                _startTile()
                for (i, tile) in tiles.enumerated() {
                    _appTile(tile, index: i + 1)
                }
            }
        ))

        // The hover preview is NOT drawn here: it is taller than this box
        // and the shell hangs it above the bar as its own layer. See
        // `fluentHoverPreview`.

        return Stack(fit: .expand, children: layers)
    }

    // MARK: Tiles

    private func _startTile() -> Widget {
        _tileBox(
            index: 0,
            active: startActive,
            indicator: nil,
            onTap: { [self] in onStart() },
            onMenu: nil,
            // Four equal panes — the closest thing in this font to the
            // Windows logo, which it does not (and should not) ship.
            content: MacosIcon(
                icon: FluentSystemIcons.grid,
                color: shellTheme.fgPrimary,
                size: FluentBar.icon
            )
        )
    }

    private func _appTile(_ tile: TaskbarTile, index: Int) -> Widget {
        _tileBox(
            index: index,
            active: false,
            indicator: tile.isRunning
                ? (tile.isFocused
                    ? (FluentBar.indicatorFocused, shellTheme.runningIndicatorActive)
                    : (FluentBar.indicatorRunning, shellTheme.runningIndicator))
                : nil,
            onTap: { [self] in onTile(tile.appId) },
            onMenu: { [self] in onTileMenu(tile.appId) },
            content: SizedBox(
                width: FluentBar.icon, height: FluentBar.icon,
                child: tile.visual
            )
        )
    }

    /// The shared tile shape: a square hover fill, the content centred in it,
    /// and the running indicator hugging its bottom edge.
    private func _tileBox(
        index: Int,
        active: Bool,
        indicator: (width: Double, color: Color)?,
        onTap: @escaping () -> Void,
        onMenu: (() -> Void)?,
        content: Widget
    ) -> Widget {
        // `.opaque`: the HoverButton inside is a CHILD and is hit-tested
        // first, so it still gets its press and its tap, while the strip
        // behind this tile does not.
        let hovered = hoveredIndex == index
        return Listener(
            onPointerDown: { event in
                if event.buttons & kSecondaryButton != 0 { onMenu?() }
            },
            behavior: .opaque,
            child: SizedBox(
                width: FluentBar.tile, height: FluentBar.tile,
                child: HoverButton(
                    builder: { context, states in
                        let hot = hovered || states.isPressed || active
                        var children: [Widget] = [
                            Positioned(fill: (), child: Center(child: content))
                        ]
                        if let ind = indicator {
                            children.append(Positioned(
                                left: (FluentBar.tile - ind.width) / 2,
                                bottom: 0,
                                width: ind.width,
                                height: FluentBar.indicatorHeight,
                                child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: ind.color,
                                        borderRadius: BorderRadius.circular(
                                            FluentBar.indicatorHeight / 2)
                                    ),
                                    child: SizedBox(expand: ())
                                )
                            ))
                        }
                        return DecoratedBox(
                            decoration: BoxDecoration(
                                color: hot ? shellTheme.barHover
                                           : Color(0x00000000),
                                borderRadius: BorderRadius.circular(4)
                            ),
                            child: Stack(fit: .expand, children: children)
                        )
                    },
                    onPressed: onTap
                )
            )
        )
    }

    // MARK: Status readout

    private func _statusCluster() -> Widget {
        let s = status
        return Row(mainAxisSize: .min, crossAxisAlignment: .center) {
            // One button for the whole glyph group, Windows-style: the
            // individual icons are a readout, not separate controls.
            _trayButton(active: s.statusActive, onTap: { [self] in onStatus() }) {
                Row(mainAxisSize: .min, crossAxisAlignment: .center, spacing: 8) {
                    for icon in s.statusIcons {
                        MacosIcon(icon: icon, color: shellTheme.fgPrimary, size: 16)
                    }
                }
            }
            if s.showBell {
                _trayButton(active: s.bellActive, onTap: { [self] in onBell() }) {
                    MacosIcon(
                        icon: FluentSystemIcons.bell,
                        color: s.bellTinted ? shellTheme.accent
                                            : shellTheme.fgPrimary,
                        size: 16)
                }
            }
            // Time over date, right-aligned — Windows' two-line clock.
            _trayButton(active: s.clockActive, onTap: { [self] in onClock() }) {
                // Self-paced leaves, not strings from the status struct:
                // nothing rebuilds the shell on an idle desktop, so a clock
                // built from the parent's `Date()` stops. See `ShellClock`.
                Column(mainAxisAlignment: .center,
                       crossAxisAlignment: .end) {
                    ShellClock(format: s.clockFormat,
                               style: fluentType.styled({ $0.caption },
                                                        shellTheme.fgPrimary))
                    ShellClock(format: s.dateFormat,
                               style: fluentType.styled({ $0.caption },
                                                        shellTheme.fgPrimary))
                }
            }
            // No power button: Windows keeps that inside Start, and so do we
            // — see `FluentStartMenu`'s footer.
            SizedBox(width: 8)
        }
    }

    private func _trayButton(
        active: Bool,
        onTap: @escaping () -> Void,
        @ChildBuilder content: () -> Widget
    ) -> Widget {
        let child = content()
        return SizedBox(
            height: FluentBar.height,
            child: HoverButton(
                builder: { context, states in
                    let hot = states.isHovered || states.isPressed || active
                    return DecoratedBox(
                        decoration: BoxDecoration(
                            color: hot ? shellTheme.barHover : Color(0x00000000),
                            borderRadius: BorderRadius.circular(4)
                        ),
                        child: Padding(
                            padding: EdgeInsets(left: 8, top: 4, right: 8, bottom: 4),
                            child: Center(child: child)
                        )
                    )
                },
                onPressed: onTap
            )
        )
    }

    // MARK: Bits

    private func _nameLabel(_ text: String) -> Widget {
        DecoratedBox(
            decoration: BoxDecoration(
                color: shellTheme.panelFill,
                border: Border.all(color: shellTheme.panelStroke, width: 1),
                borderRadius: BorderRadius.circular(4)
            ),
            child: Padding(
                padding: EdgeInsets(left: 8, top: 3, right: 8, bottom: 3),
                child: Text(text, style: fluentType.styled({ $0.body },
                                           shellTheme.fgPrimary))
            )
        )
    }
}
