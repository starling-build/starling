// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The jump list: Windows' menu on a taskbar tile. The app itself (opens
// it, or brings it forward), Close window(s) while it has any, and Pin to
// or Unpin from taskbar. The recent-documents section Windows shows comes
// when apps report their recent files; nothing is drawn for it until then.
// The SDK's MenuFlyout content placed by the shell above the tile, like
// every shell popup; the pinned list is the same one the macOS dock keeps,
// so the two styles never disagree about what is pinned.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import StarlingRegistry

extension _DesktopShellState {

    func fluentJumpList(forOutput output: DisplayOutput) -> Widget? {
        guard output.isPrimary, let appId = _dockMenuAppId else { return nil }
        let name = AppRegistry.shared.app(id: appId)?.name ?? appId
        let running = windowManager.windows.contains { win in
            win.ownerAgentId == nil && _appOwning(win)?.id == appId
        }
        let windowCount = windowManager.windows.filter { win in
            win.ownerAgentId == nil && _appOwning(win)?.id == appId
        }.count
        let pinned = dockAppOrder.contains(appId)
        func pick(_ action: @escaping () -> Void) -> () -> Void {
            { [self] in
                setState { _dockMenuAppId = nil }
                action()
            }
        }
        var items: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text(name),
                           leading: SizedBox(width: 16, height: 16,
                                             child: fluentIconVisual(appId: appId, size: 16)),
                           onPressed: pick { [self] in _launchOrFocusApp(appId) }),
        ]
        if running {
            items.append(MenuFlyoutItem(
                text: Text(windowCount > 1 ? "Close all windows" : "Close window"),
                leading: Icon(FluentSystemIcons.close, size: 16),
                onPressed: pick { [self] in _quitApp(appId) }))
        }
        items.append(MenuFlyoutSeparator())
        items.append(MenuFlyoutItem(
            text: Text(pinned ? "Unpin from taskbar" : "Pin to taskbar"),
            leading: Icon(pinned ? FluentSystemIcons.pinOff : FluentSystemIcons.pin, size: 16),
            onPressed: pick { [self] in
                setState {
                    if pinned {
                        dockAppOrder.removeAll { $0 == appId }
                        _dockRemovedByUser.insert(appId)
                    } else if AppRegistry.shared.app(id: appId) != nil {
                        dockAppOrder.append(appId)
                        _dockRemovedByUser.remove(appId)
                    }
                }
            }))
        // Above the tile, centred on it as far as the screen allows; the
        // menu sizes itself, so the centring assumes its usual width.
        let nominal = 200.0
        let left = max(FluentSpacing.s, min(_dockMenuAnchorX - nominal / 2,
                                            output.logicalWidth - nominal - FluentSpacing.s))
        return Positioned(
            left: left,
            bottom: DesktopTheme.kDockHeight + FluentSpacing.s,
            child: fluentShellMenu(items))
    }
}
