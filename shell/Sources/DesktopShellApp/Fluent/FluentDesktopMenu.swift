// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The desktop's right-click menu, as Windows draws it: a MenuFlyout on
// acrylic with 16px icons, 8px corners, elevation 32. Icon sizes and sort
// orders are moot — there are no desktop icons — so the menu is the
// desktop's own commands: wallpaper, appearance, the style, the spaces and
// the overview, Display settings. The style rows are radio items rather
// than a submenu: a submenu opens through the SDK's overlay, and the shell
// tree carries none.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

extension _DesktopShellState {

    func fluentDesktopMenu() -> Widget {
        func pick(_ action: @escaping () -> Void) -> () -> Void {
            { [self] in
                setState { contextMenuPosition = nil }
                action()
            }
        }
        var items: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Change wallpaper"),
                           leading: Icon(FluentSystemIcons.pictures, size: 16),
                           onPressed: pick { [self] in
                               setState {
                                   wallpaperPreset = wallpaperPreset.next
                                   _syncSharedWallpaper()
                               }
                           }),
            MenuFlyoutItem(text: Text(shellTheme.isDark ? "Light appearance" : "Dark appearance"),
                           leading: Icon(shellTheme.isDark ? FluentSystemIcons.sun : FluentSystemIcons.moon, size: 16),
                           onPressed: pick { [self] in _setAppearance(dark: !shellTheme.isDark) }),
            MenuFlyoutSeparator(),
        ]
        // One row per style, off the registry — adding a style should not
        // mean remembering to edit this menu.
        for style in ShellStyles.all {
            items.append(RadioMenuFlyoutItem(
                text: Text("\(style.name) style"),
                isSelected: style.id == shellStyle.id,
                onSelected: pick { [self] in _setStyle(style.id) }))
        }
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(text: Text("Task view"),
                                    leading: Icon(FluentSystemIcons.window, size: 16),
                                    onPressed: pick { [self] in _openMissionControl() }))
        items.append(MenuFlyoutItem(text: Text("New desktop"),
                                    leading: Icon(FluentSystemIcons.add, size: 16),
                                    onPressed: pick { [self] in
                                        let idx = windowManager.addSpace()
                                        _switchToSpace(idx, onOutput: contextMenuOutputId)
                                    }))
        items.append(MenuFlyoutItem(text: Text("Workspace"),
                                    leading: Icon(FluentSystemIcons.desktop, size: 16),
                                    onPressed: pick { [self] in
                                        if !windowManager.activeSpace.isWorkspace { _toggleWorkspaceSpace() }
                                    }))
        let active = windowManager.activeSpace
        if active.isUser && windowManager.spaces.filter({ $0.isUser }).count > 1 {
            items.append(MenuFlyoutItem(text: Text("Remove this desktop"),
                                        leading: Icon(FluentSystemIcons.delete, size: 16),
                                        onPressed: pick { [self] in
                                            setState { windowManager.removeSpace(at: windowManager.activeSpaceIndex) }
                                        }))
        }
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(text: Text("Display settings"),
                                    leading: Icon(FluentSystemIcons.settings, size: 16),
                                    onPressed: pick { [self] in _launchOrFocusApp("settings") }))
        items.append(MenuFlyoutItem(text: Text("Open Text Viewer"),
                                    leading: Icon(FluentSystemIcons.document, size: 16),
                                    onPressed: pick { [self] in _launchOrFocusApp("textviewer") }))
        return Positioned(
            left: contextMenuPosition?.dx ?? 0,
            top: contextMenuPosition?.dy ?? 0,
            child: fluentShellMenu(items))
    }
}
