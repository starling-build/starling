// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

/// U-LINK-2: the shared link card. Shows where the link under the caret goes,
/// its screen tip, and Open, Edit and Remove. Every app puts it in the same place
/// (a strip under the ribbon) and supplies the three actions.
final class LinkCard: StatelessWidget {
    let address: String
    let tip: String
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    init(address: String, tip: String = "", onOpen: @escaping () -> Void, onEdit: @escaping () -> Void,
         onRemove: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.address = address; self.tip = tip
        self.onOpen = onOpen; self.onEdit = onEdit; self.onRemove = onRemove; self.onClose = onClose
        super.init()
    }

    /// The link the card shows: the one under the caret, else the one the pointer last rested on.
    /// Nothing once the user closed it; a new caret link or hover reopens it.
    static func link(caret: String?, hover: String?, dismissed: Bool) -> String? {
        dismissed ? nil : (caret ?? hover)
    }

    /// What the card shows for a link target: "#name" reads as a place in this document.
    static func shown(_ link: String) -> String {
        link.hasPrefix("#") ? "Place in this document" : link
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let hint = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        var text: [Widget] = [Text(LinkCard.shown(address), style: fluent.typography.body)]
        if !tip.isEmpty { text.append(Text(tip, style: hint)) }
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                           child: Row(crossAxisAlignment: .center, children: [
                Expanded(child: Column(crossAxisAlignment: .start, children: text)),
                PKeyed("link-card-open", Button(onPressed: onOpen, child: Text("Open"))), Chrome.gap(8),
                PKeyed("link-card-edit", Button(onPressed: onEdit, child: Text("Edit"))), Chrome.gap(8),
                PKeyed("link-card-remove", Button(onPressed: onRemove, child: Text("Remove"))), Chrome.gap(4),
                Chrome.icon(FluentSystemIcons.chromeClose, "Close (Esc)", fluent, action: onClose),
            ])))
    }
}
