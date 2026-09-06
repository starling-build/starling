// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What Start hangs above itself: a tile's pin menu, the power flyout, and
// the power confirm dialog. Like every shell popup these are positioned
// widgets in the root stack with the shell owning placement and dismissal
// — there is no Overlay or Navigator in the shell tree — so the SDK's
// MenuFlyout and ContentDialog supply the CONTENT inside a FluentTheme of
// the shell's appearance, and the dialog's Smoke is the SDK's.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

extension _DesktopShellState {

    /// The SDK's Fluent theme in the shell's appearance and face.
    func fluentThemeData() -> FluentThemeData {
        FluentThemeData(brightness: shellTheme.isDark ? .dark : .light,
                        fontFamily: shellTheme.fontFamily)
    }

    /// A MenuFlyout the shell can place: content-sized inside WinUI's flyout
    /// box exactly as the SDK's own positioner does it. A positioned slot
    /// hands the menu an unbounded width, and a menu row's `Expanded` label
    /// under that lays out to nothing — built, and invisible.
    func fluentShellMenu(_ items: [MenuFlyoutItemBase]) -> Widget {
        FluentTheme(
            data: fluentThemeData(),
            child: ConstrainedBox(
                constraints: kFlyoutThemeConstraints,
                child: IntrinsicWidth(child: IntrinsicHeight(
                    child: FluentEntrance(child: MenuFlyout(items: items))))))
    }

    /// A full-screen catch for the click that puts a popup away.
    func fluentDismissBarrier(_ dismiss: @escaping () -> Void) -> Widget {
        Positioned(
            fill: (),
            child: Listener(
                onPointerDown: { [self] _ in setState { dismiss() } },
                behavior: .opaque,
                child: ColoredBox(color: Color(0x00000000), child: SizedBox(expand: ()))))
    }

    /// Everything open above Start right now, as one fill-the-screen stack,
    /// or nil.
    func fluentStartOverlays() -> Widget? {
        var layers: [Widget] = []
        if _launcherOpen, let menu = _startTileMenu {
            layers.append(fluentDismissBarrier { [self] in _startTileMenu = nil })
            layers.append(_startTileMenuWidget(appId: menu.appId, at: menu.at))
        }
        if _launcherOpen, let anchor = _startPowerMenu {
            layers.append(fluentDismissBarrier { [self] in _startPowerMenu = nil })
            layers.append(_startPowerMenuWidget(anchor: anchor))
        }
        if let action = _powerDialog {
            layers.append(_powerDialogWidget(action))
        }
        guard !layers.isEmpty else { return nil }
        return Positioned(fill: (), child: Stack(fit: .expand, children: layers))
    }

    /// Pin / Unpin, and Open — Windows' tile menu without the parts that
    /// need an Explorer (More, Uninstall).
    private func _startTileMenuWidget(appId: String, at: Offset) -> Widget {
        let pinned = (_startPins ?? _launcherAllApps().map { $0.appId }).contains(appId)
        let items: [MenuFlyoutItemBase] = [
            MenuFlyoutItem(text: Text("Open"),
                           leading: Icon(FluentSystemIcons.openExternal, size: 16),
                           onPressed: { [self] in
                               setState { _startTileMenu = nil }
                               _launchFromLauncher(appId)
                           }),
            MenuFlyoutItem(text: Text(pinned ? "Unpin from Start" : "Pin to Start"),
                           leading: Icon(pinned ? FluentSystemIcons.pinOff : FluentSystemIcons.pin, size: 16),
                           onPressed: { [self] in
                               setState { _startTileMenu = nil }
                               _toggleStartPin(appId)
                           }),
        ]
        return Positioned(left: at.dx, top: at.dy, child: fluentShellMenu(items))
    }

    /// Shut Down / Restart / Log Out, above the power control. Each goes to
    /// the confirm dialog; ending a session is not undoable.
    private func _startPowerMenuWidget(anchor: Rect) -> Widget {
        func item(_ action: PowerAction, _ icon: IconData) -> MenuFlyoutItemBase {
            MenuFlyoutItem(text: Text(action.title),
                           leading: Icon(icon, size: 16),
                           onPressed: { [self] in
                               _closeLauncher()
                               setState { _powerDialog = action }
                           })
        }
        let items: [MenuFlyoutItemBase] = [
            item(.shutDown, FluentSystemIcons.power),
            item(.restart, FluentSystemIcons.restart),
            item(.logOut, FluentSystemIcons.signOut),
        ]
        // Its bottom edge just above the control, right edges aligned, as
        // Windows hangs it.
        let menuHeight: Double = 3 * (FluentSpacing.controlHeight + 4) + 12
        return Positioned(
            top: anchor.top - menuHeight - FluentSpacing.xs,
            right: screenWidth - anchor.right,
            child: fluentShellMenu(items))
    }

    /// The confirm, as a ContentDialog over Smoke: the whole desktop dims
    /// and the choice is the only live thing on it.
    private func _powerDialogWidget(_ action: PowerAction) -> Widget {
        let theme = fluentThemeData()
        return Positioned(
            fill: (),
            child: FluentTheme(
                data: theme,
                child: FluentMaterialSettings(
                    transparencyEffects: true,
                    child: Smoke(
                        child: Listener(
                            onPointerDown: { _ in },
                            behavior: .opaque,
                            child: Center(
                                child: FluentEntrance(
                                    child: ContentDialog(
                                        title: Text(action.title),
                                        content: Text(action.prompt),
                                        actions: [
                                            Button(onPressed: { [self] in
                                                setState { _powerDialog = nil }
                                            }, child: Text("Cancel")),
                                            FilledButton(onPressed: { [self] in
                                                setState { _powerDialog = nil }
                                                _runPowerAction(action)
                                            }, child: Text(action.title)),
                                        ]),
                                    slideFrom: Offset(0, 0))))))))
    }
}
