// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Fluent style's chrome: what exists, and where.
//
// The shape of this class IS the difference between the two styles. There is
// no top bar, so `topBar` is nil and the desktop's top inset is zero. The
// bottom bar is a taskbar rather than a dock. Flyouts come up from the bottom
// right instead of down from a menu bar.
//
// Anything not yet ported falls through to the macOS builder ON PURPOSE and
// each one says so — a surface that is still macOS-shaped is a to-do with a
// date on it, not a decision.

import Flutter
import FlutterSwiftBridge

final class FluentChrome: ShellChrome {
    unowned let shell: _DesktopShellState

    init(shell: _DesktopShellState) { self.shell = shell }

    /// Nothing on the top edge. This is what makes the desktop's top inset 0
    /// and gives windows the whole upper screen.
    func topBar() -> Widget? { nil }

    func bottomBar(forOutput output: DisplayOutput, opacity: Double) -> Widget? {
        shell.fluentTaskbar(forOutput: output, opacity: opacity)
    }

    func launcher() -> Widget { shell.fluentStartMenu() }

    /// The macOS panels, but hung off the bottom-right corner where Windows
    /// puts them. Their CONTENT becomes Quick Settings and the notification
    /// centre in the flyouts phase; placing them correctly first means the
    /// taskbar is usable in the meantime.
    func statusFlyout(_ kind: _DesktopShellState.StatusBarPopup) -> Widget {
        shell.fluentStatusFlyout(kind)
    }

    func statusFlyoutOrigin(_ kind: _DesktopShellState.StatusBarPopup,
                            height: Double) -> Offset {
        shell.fluentStatusFlyoutOrigin(kind, height: height)
    }

    /// Still the macOS menu; the Fluent one lands with the rest of the menus.
    func desktopMenu() -> Widget { shell.macosDesktopMenu() }

    /// Reused as-is, and it lands in the right place for free: it anchors at
    /// `bottomBarMargin + bottomBarHeight + 10`, which in this style is just
    /// above the taskbar.
    func appIconMenu(forOutput output: DisplayOutput) -> Widget? {
        shell.dockIconMenuWidget(forOutput: output)
    }

    /// Tile hover, and specifically the LEAVE — a per-tile Listener hears
    /// every enter and no exit, so the hover label would stick after the
    /// pointer moved up onto a window. Cheap: it only calls setState when the
    /// tile under the cursor actually changes.
    func notePointerHover(x: Double, y: Double, outputId: Int) {
        shell.fluentNoteBarHover(x: x, y: y, outputId: outputId)
    }

    func hoverOverlay() -> Widget? { shell.fluentHoverPreview() }

    func barSlots(forOutput output: DisplayOutput)
        -> [(app: String, x: Double, y: Double, size: Double)] {
        let ids = ["launcher"] + shell._dockDisplayApps
        // Tiles are centred in the strip, and the strip is on the bottom edge.
        let y = output.logicalHeight - FluentBar.height
            + (FluentBar.height - FluentBar.tile) / 2 + FluentBar.tile / 2
        return ids.enumerated().map { i, id in
            (app: id,
             x: FluentBar.tileCenterX(index: i, count: ids.count,
                                      outputWidth: output.logicalWidth),
             y: y,
             size: FluentBar.tile)
        }
    }
}
