// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The strip Insert → Link (⌘K) opens: the address, Insert, and Remove
/// when the caret is already on a link. ⌘-click follows a link; the
/// status bar shows the target under the pointer.
final class LinkBar: StatelessWidget {
    let session: OfficeSession
    let address: TextEditingController
    let hasLink: Bool
    let onApply: () -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    init(session: OfficeSession, address: TextEditingController, hasLink: Bool,
         onApply: @escaping () -> Void, onRemove: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.address = address
        self.hasLink = hasLink
        self.onApply = onApply
        self.onRemove = onRemove
        self.onClose = onClose
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let hint = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        var items: [Widget] = [
            SizedBox(width: 60, height: nil, child: Text("Link", style: fluent.typography.body)),
            SizedBox(width: 420, height: 30, child: FluentTextBox(
                controller: address, placeholderText: "https://…", onSubmitted: { [onApply] _ in onApply() })),
            Chrome.gap(12),
            Text(session.summary.hasSelection ? "Links the selected text" : "With nothing selected, the address becomes the text",
                 style: hint),
            Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
        ]
        if hasLink {
            items.append(Button(onPressed: onRemove, child: Text("Remove Link")))
            items.append(Chrome.gap(8))
        }
        items.append(FilledButton(onPressed: onApply, child: Text("Insert")))
        items.append(Chrome.gap(4))
        items.append(Chrome.icon(FluentSystemIcons.chromeClose, "Close (Esc)", fluent, action: onClose))
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                           child: Row(crossAxisAlignment: .center, children: items)))
    }
}
