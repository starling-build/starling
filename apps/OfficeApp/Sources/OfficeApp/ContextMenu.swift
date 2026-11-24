// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

/// One button of a context menu's mini toolbar: an icon, its tooltip, whether its state is on, and the action.
struct MiniToolbarButton {
    var icon: IconData
    var tip: String
    var on = false
    var enabled = true
    var action: () -> Void
}

/// The right-click menu all three apps share: a row of quick formatting buttons on top (optional), then the
/// commands. An app fills it in and shows it; the helper drops doubled separators and a trailing one, so the
/// callers need not track them.
final class ContextMenuBuilder {
    private(set) var mini: [MiniToolbarButton] = []
    private(set) var items: [MenuFlyoutItemBase] = []

    func miniButton(_ icon: IconData, _ tip: String, on: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) {
        mini.append(MiniToolbarButton(icon: icon, tip: tip, on: on, enabled: enabled, action: action))
    }

    func item(_ text: String, enabled: Bool = true, _ action: @escaping () -> Void) {
        items.append(MenuFlyoutItem(text: Text(text), onPressed: enabled ? action : nil))
    }

    func separator() {
        if !items.isEmpty, !(items.last is MenuFlyoutSeparator) { items.append(MenuFlyoutSeparator()) }
    }

    /// The flyout's rows: the mini toolbar first (when there are buttons), then the items.
    var rows: [MenuFlyoutItemBase] {
        var out = items
        while out.last is MenuFlyoutSeparator { out.removeLast() }
        return (mini.isEmpty ? [] : [MiniToolbarRow(buttons: mini), MenuFlyoutSeparator()]) + out
    }

    func show(_ flyout: FlyoutController, in context: BuildContext, at point: Offset) {
        let all = rows
        guard !all.isEmpty else { return }
        flyout.showFlyout(in: context, at: point) { _ in MenuFlyout(items: all) }
    }
}

/// The mini toolbar as a menu row. A press runs the action and leaves the menu open, as a toggle in a toolbar does
/// not dismiss it; the buttons repaint with the new state when the menu is shown again.
final class MiniToolbarRow: MenuFlyoutItemBase {
    let buttons: [MiniToolbarButton]
    init(buttons: [MiniToolbarButton]) { self.buttons = buttons; super.init() }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return Row(children: buttons.map { b in
            b.enabled ? Chrome.toggle(b.icon, b.tip, b.on, fluent) { b.action() }
                      : Chrome.icon(b.icon, b.tip, fluent, enabled: false) {}
        })
    }
}
