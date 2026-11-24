// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// A one-line question under the ribbon with a confirming button and a Cancel, for an action that throws work away.
final class ConfirmBar: StatelessWidget {
    let message: String
    let action: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(message: String, action: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.message = message
        self.action = action
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6), child: Row(crossAxisAlignment: .center, children: [
                Expanded(child: Text(message, style: fluent.typography.body)),
                FilledButton(onPressed: onConfirm, child: Text(action)),
                Chrome.gap(8),
                Button(onPressed: onCancel, child: Text("Cancel")),
            ])))
    }
}
